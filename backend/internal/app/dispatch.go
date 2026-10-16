package app

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/nomo-taxi/nomo/backend/internal/geo"
	"github.com/nomo-taxi/nomo/backend/internal/push"
)

const (
	geoKey       = "drivers:geo"
	seenTTL      = 60 * time.Second // a driver silent longer than this is not offered orders
	idleWaitStep = 5 * time.Second
)

var errConflict = errors.New("conflict")

func decodeBody(r *http.Request, v any) error {
	return json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20)).Decode(v)
}

type candidate struct {
	id      string
	pos     geo.Point
	distM   float64
	etaS    int
	heading float64
}

// freeDriversNear returns online, approved, free drivers within radiusKm,
// nearest first. tariff "" skips the car-class check.
func (a *App) freeDriversNear(ctx context.Context, p Place, radiusKm float64, tariff string) []candidate {
	locs, err := a.rdb.GeoSearchLocation(ctx, geoKey, &redis.GeoSearchLocationQuery{
		GeoSearchQuery: redis.GeoSearchQuery{
			Longitude: p.Lng, Latitude: p.Lat, Radius: radiusKm, RadiusUnit: "km", Sort: "ASC", Count: 40,
		},
		WithCoord: true, WithDist: true,
	}).Result()
	if err != nil || len(locs) == 0 {
		return nil
	}
	ids := make([]string, 0, len(locs))
	for _, l := range locs {
		ids = append(ids, l.Name)
	}
	// Drop drivers whose app stopped reporting.
	seenKeys := make([]string, len(ids))
	headKeys := make([]string, len(ids))
	for i, id := range ids {
		seenKeys[i] = "driver:seen:" + id
		headKeys[i] = "driver:heading:" + id
	}
	seen, _ := a.rdb.MGet(ctx, seenKeys...).Result()
	heads, _ := a.rdb.MGet(ctx, headKeys...).Result()

	q := `SELECT user_id FROM drivers WHERE user_id = ANY($1::uuid[]) AND status='approved' AND online AND NOT busy`
	args := []any{ids}
	if tariff != "" {
		q += ` AND $2 = ANY(classes)`
		args = append(args, tariff)
	}
	rows, err := a.db.Query(ctx, q, args...)
	if err != nil {
		return nil
	}
	ok := map[string]bool{}
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ok[id] = true
		}
	}
	rows.Close()

	var out []candidate
	for i, l := range locs {
		if !ok[l.Name] || (len(seen) > i && seen[i] == nil) {
			continue
		}
		c := candidate{id: l.Name, pos: geo.Point{Lat: l.Latitude, Lng: l.Longitude}, distM: l.Dist * 1000}
		c.etaS = geo.TravelSeconds(c.distM * geo.RoadFactor)
		if len(heads) > i {
			if s, ok := heads[i].(string); ok {
				c.heading, _ = strconv.ParseFloat(s, 64)
			}
		}
		out = append(out, c)
	}
	return out
}

// findCandidate picks the nearest free driver of the tariff who has not seen
// this order yet and is not considering another offer.
func (a *App) findCandidate(ctx context.Context, orderID, tariff string, p Place, radiusKm float64) (candidate, bool) {
	cands := a.freeDriversNear(ctx, p, radiusKm, tariff)
	if len(cands) == 0 {
		return candidate{}, false
	}
	ids := make([]string, len(cands))
	for i, c := range cands {
		ids[i] = c.id
	}
	rows, err := a.db.Query(ctx, `
		SELECT DISTINCT driver_id FROM order_offers
		WHERE driver_id = ANY($1::uuid[]) AND (order_id::text = $2 OR (status='offered' AND created_at > now() - $3::interval))`,
		ids, orderID, a.cfg.OfferTimeout.String())
	if err != nil {
		return candidate{}, false
	}
	skip := map[string]bool{}
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			skip[id] = true
		}
	}
	rows.Close()
	for _, c := range cands {
		if !skip[c.id] {
			return c, true
		}
	}
	return candidate{}, false
}

type Offer struct {
	OrderID         string    `json:"order_id"`
	Tariff          string    `json:"tariff"`
	From            Place     `json:"from"`
	To              Place     `json:"to"`
	Price           int       `json:"price"`
	Currency        string    `json:"currency"`
	DistanceM       int       `json:"distance_m"`
	DurationS       int       `json:"duration_s"`
	PickupDistanceM int       `json:"pickup_distance_m"`
	PickupEtaS      int       `json:"pickup_eta_s"`
	PaymentMethod   string    `json:"payment_method"`
	PassengerRating float64   `json:"passenger_rating"`
	Comment         string    `json:"comment"`
	ChildSeat       bool      `json:"child_seat"`
	WithPet         bool      `json:"with_pet"`
	ExpiresAt       time.Time `json:"expires_at"`
	Route           string    `json:"route"`
}

// dispatch offers the order to drivers one at a time, nearest first, widening
// the radius when nobody is left, until someone accepts or search times out.
func (a *App) dispatch(orderID string) {
	ctx := a.ctx
	deadline := time.Now().Add(a.cfg.SearchTimeout)
	radius := 0
	for time.Now().Before(deadline) {
		if ctx.Err() != nil {
			return
		}
		o, err := a.loadOrder(ctx, orderID)
		if err != nil || o.Status != "searching" {
			return
		}
		c, ok := a.findCandidate(ctx, orderID, o.Tariff, o.From, a.cfg.SearchRadiiKm[radius])
		if !ok {
			if radius < len(a.cfg.SearchRadiiKm)-1 {
				radius++
				continue
			}
			sleepCtx(ctx, min(idleWaitStep, time.Until(deadline)))
			continue
		}
		if a.offer(ctx, o, c) {
			return
		}
	}
	a.giveUp(ctx, orderID)
}

// offer sends the order to one driver and waits for the answer. It reports
// whether the driver accepted.
func (a *App) offer(ctx context.Context, o *Order, c candidate) bool {
	_, err := a.db.Exec(ctx, `INSERT INTO order_offers (order_id, driver_id, status, eta_s) VALUES ($1,$2,'offered',$3) ON CONFLICT DO NOTHING`, o.ID, c.id, c.etaS)
	if err != nil {
		slog.Error("offer insert", "err", err)
		return false
	}
	off := a.buildOffer(o, c, time.Now().Add(a.cfg.OfferTimeout))
	a.hub.Publish(c.id, "offer.new", off)
	a.sendPush(c.id, push.Message{Title: "Новый заказ", Body: o.From.Addr, Data: map[string]string{"type": "offer", "order_id": o.ID}})

	wait := time.NewTimer(a.cfg.OfferTimeout)
	defer wait.Stop()
	tick := time.NewTicker(300 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return false
		case <-wait.C:
			tag, _ := a.db.Exec(ctx, `UPDATE order_offers SET status='expired' WHERE order_id=$1 AND driver_id=$2 AND status='offered'`, o.ID, c.id)
			if tag.RowsAffected() > 0 {
				a.hub.Publish(c.id, "offer.cancelled", map[string]string{"order_id": o.ID})
				return false
			}
			return a.offerStatus(ctx, o.ID, c.id) == "accepted"
		case <-tick.C:
			switch a.offerStatus(ctx, o.ID, c.id) {
			case "accepted":
				return true
			case "declined", "expired":
				return false
			}
		}
	}
}

func (a *App) offerStatus(ctx context.Context, orderID, driverID string) string {
	var s string
	_ = a.db.QueryRow(ctx, `SELECT status FROM order_offers WHERE order_id=$1 AND driver_id=$2`, orderID, driverID).Scan(&s)
	return s
}

func (a *App) buildOffer(o *Order, c candidate, expires time.Time) Offer {
	off := Offer{
		OrderID: o.ID, Tariff: o.Tariff, From: o.From, To: o.To, Price: o.Price, Currency: a.cfg.Currency,
		DistanceM: o.DistanceM, DurationS: o.DurationS, PickupDistanceM: int(c.distM * geo.RoadFactor), PickupEtaS: c.etaS,
		PaymentMethod: o.PaymentMethod, Comment: o.Comment, ChildSeat: o.ChildSeat, WithPet: o.WithPet, ExpiresAt: expires,
		Route: o.Route,
	}
	if o.Passenger != nil {
		off.PassengerRating = o.Passenger.Rating
	}
	return off
}

func (a *App) giveUp(ctx context.Context, orderID string) {
	o, err := a.loadOrder(ctx, orderID)
	if err != nil {
		return
	}
	tag, err := a.db.Exec(ctx, `UPDATE orders SET status='no_drivers', cancelled_at=now() WHERE id=$1 AND status='searching'`, orderID)
	if err != nil || tag.RowsAffected() == 0 {
		return
	}
	if o.paymentRef != "" {
		_ = a.pay.Void(ctx, o.paymentRef)
		a.setPaymentStatus(ctx, orderID, "voided", nil)
	}
	a.notifyOrder(ctx, orderID)
	a.sendPush(o.PassengerID, push.Message{Title: "Машин нет рядом", Body: "Попробуйте заказать ещё раз через пару минут", Data: map[string]string{"order_id": orderID}})
}

// creditDriver books the fare and commission for a finished (or paid-cancelled) trip.
// Card trips: the service collected the money, so the driver earns fare − commission.
// Cash trips: the driver holds the cash, so only the commission is debited.
func (a *App) creditDriver(ctx context.Context, driverID, orderID, method string, fare, commission int) {
	tx, err := a.db.Begin(ctx)
	if err != nil {
		slog.Error("credit driver", "err", err)
		return
	}
	defer tx.Rollback(ctx)
	delta := -commission
	if method == "card" {
		delta = fare - commission
		if _, err := tx.Exec(ctx, `INSERT INTO driver_transactions (driver_id, order_id, kind, amount) VALUES ($1,$2,'fare',$3)`, driverID, orderID, fare); err != nil {
			return
		}
	}
	if _, err := tx.Exec(ctx, `INSERT INTO driver_transactions (driver_id, order_id, kind, amount) VALUES ($1,$2,'commission',$3)`, driverID, orderID, -commission); err != nil {
		return
	}
	if _, err := tx.Exec(ctx, `UPDATE drivers SET balance = balance + $2 WHERE user_id=$1`, driverID, delta); err != nil {
		return
	}
	_ = tx.Commit(ctx)
}

func sleepCtx(ctx context.Context, d time.Duration) {
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-ctx.Done():
	case <-t.C:
	}
}

// updateDriverLocation stores the position and forwards it to the passenger of the active trip.
func (a *App) updateDriverLocation(ctx context.Context, driverID string, lat, lng, heading float64) {
	if !validCoord(lat, lng) {
		return
	}
	var online bool
	_ = a.db.QueryRow(ctx, `SELECT online FROM drivers WHERE user_id=$1`, driverID).Scan(&online)
	if online {
		a.rdb.GeoAdd(ctx, geoKey, &redis.GeoLocation{Name: driverID, Longitude: lng, Latitude: lat})
		a.rdb.Set(ctx, "driver:seen:"+driverID, 1, seenTTL)
		a.rdb.Set(ctx, "driver:heading:"+driverID, strconv.FormatFloat(heading, 'f', 0, 64), seenTTL)
	}
	orderID, err := a.rdb.Get(ctx, "driver:order:"+driverID).Result()
	if err != nil || orderID == "" {
		return
	}
	var passengerID string
	if err := a.db.QueryRow(ctx, `SELECT passenger_id FROM orders WHERE id=$1 AND status IN ('assigned','arrived','in_progress')`, orderID).Scan(&passengerID); err != nil {
		return
	}
	a.hub.Publish(passengerID, "driver.location", map[string]any{"order_id": orderID, "lat": lat, "lng": lng, "heading": heading})
}
