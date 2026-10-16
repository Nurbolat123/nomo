package app

import (
	"context"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/nomo-taxi/nomo/backend/internal/payments"
	"github.com/nomo-taxi/nomo/backend/internal/pricing"
	"github.com/nomo-taxi/nomo/backend/internal/push"
)

func (a *App) listTariffs(w http.ResponseWriter, r *http.Request) {
	ts, err := a.activeTariffs(r.Context(), false)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, ts)
}

type QuoteItem struct {
	Tariff    string  `json:"tariff"`
	Name      string  `json:"name"`
	Price     int     `json:"price"`
	Surge     float64 `json:"surge"`
	EtaS      *int    `json:"eta_s"`
	DistanceM int     `json:"distance_m"`
	DurationS int     `json:"duration_s"`
	Currency  string  `json:"currency"`
}

type tripInput struct {
	From  Place      `json:"from"`
	To    Place      `json:"to"`
	Route *RouteHint `json:"route"`
}

func (in tripInput) valid() bool {
	return validCoord(in.From.Lat, in.From.Lng) && validCoord(in.To.Lat, in.To.Lng)
}

func (a *App) quote(w http.ResponseWriter, r *http.Request) {
	var in tripInput
	if !readJSON(w, r, &in) {
		return
	}
	if !in.valid() {
		writeErr(w, http.StatusBadRequest, "invalid_route", "Укажите адреса подачи и назначения")
		return
	}
	items, err := a.quoteAll(r.Context(), in.From, in.To, in.Route)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, items)
}

func (a *App) quoteAll(ctx context.Context, from, to Place, hint *RouteHint) ([]QuoteItem, error) {
	ts, err := a.activeTariffs(ctx, false)
	if err != nil {
		return nil, err
	}
	route, _ := resolveRoute(from, to, hint)
	surge := a.surgeAt(ctx, from)
	out := make([]QuoteItem, 0, len(ts))
	for _, t := range ts {
		item := QuoteItem{
			Tariff: t.Code, Name: t.Name, Surge: surge, Currency: a.cfg.Currency,
			DistanceM: route.DistanceM, DurationS: route.DurationS,
			Price: pricing.Price(t, route.DistanceM, route.DurationS, surge),
		}
		if c, ok := a.findCandidate(ctx, "", t.Code, from, 7); ok {
			eta := c.etaS
			item.EtaS = &eta
		}
		out = append(out, item)
	}
	return out, nil
}

// surgeAt compares open orders and free drivers within ~3 km.
func (a *App) surgeAt(ctx context.Context, p Place) float64 {
	var orders int
	// ~0.03° ≈ 3 km box; precise enough for a demand coefficient.
	_ = a.db.QueryRow(ctx, `SELECT count(*) FROM orders WHERE status='searching'
		AND from_lat BETWEEN $1-0.03 AND $1+0.03 AND from_lng BETWEEN $2-0.04 AND $2+0.04`, p.Lat, p.Lng).Scan(&orders)
	free := len(a.freeDriversNear(ctx, p, 3, ""))
	return pricing.Surge(orders, free)
}

func (a *App) nearbyDrivers(w http.ResponseWriter, r *http.Request) {
	lat, _ := strconv.ParseFloat(r.URL.Query().Get("lat"), 64)
	lng, _ := strconv.ParseFloat(r.URL.Query().Get("lng"), 64)
	if !validCoord(lat, lng) {
		writeErr(w, http.StatusBadRequest, "invalid_location", "Нет координат")
		return
	}
	type car struct {
		Lat     float64 `json:"lat"`
		Lng     float64 `json:"lng"`
		Heading float64 `json:"heading"`
	}
	out := []car{}
	for _, c := range a.freeDriversNear(r.Context(), Place{Lat: lat, Lng: lng}, 3, "") {
		out = append(out, car{Lat: c.pos.Lat, Lng: c.pos.Lng, Heading: c.heading})
		if len(out) >= 15 {
			break
		}
	}
	writeJSON(w, http.StatusOK, out)
}

type orderInput struct {
	tripInput
	Tariff          string `json:"tariff"`
	PaymentMethod   string `json:"payment_method"`
	PaymentMethodID string `json:"payment_method_id"`
	Comment         string `json:"comment"`
	ChildSeat       bool   `json:"child_seat"`
	WithPet         bool   `json:"with_pet"`
}

func (a *App) createOrder(w http.ResponseWriter, r *http.Request) {
	var in orderInput
	if !readJSON(w, r, &in) {
		return
	}
	ctx := r.Context()
	uid := userID(r)
	if !in.valid() {
		writeErr(w, http.StatusBadRequest, "invalid_route", "Укажите адреса подачи и назначения")
		return
	}
	if in.PaymentMethod != "cash" && in.PaymentMethod != "card" {
		writeErr(w, http.StatusBadRequest, "invalid_payment", "Выберите способ оплаты")
		return
	}
	if len([]rune(in.Comment)) > 300 {
		writeErr(w, http.StatusBadRequest, "comment_too_long", "Комментарий слишком длинный")
		return
	}
	t, err := a.loadTariff(ctx, in.Tariff)
	if err != nil || !t.Active {
		writeErr(w, http.StatusBadRequest, "invalid_tariff", "Тариф недоступен")
		return
	}
	var active int
	if err := a.db.QueryRow(ctx, `SELECT count(*) FROM orders WHERE passenger_id=$1 AND status IN `+activeStatuses, uid).Scan(&active); err != nil {
		a.internal(w, err)
		return
	}
	if active > 0 {
		writeErr(w, http.StatusConflict, "active_order", "У вас уже есть активная поездка")
		return
	}

	route, polyline := resolveRoute(in.From, in.To, in.Route)
	surge := a.surgeAt(ctx, in.From)
	price := pricing.Price(t, route.DistanceM, route.DurationS, surge)

	var pmID *string
	payRef, payStatus := "", "none"
	if in.PaymentMethod == "card" {
		var token string
		err := a.db.QueryRow(ctx, `SELECT id, token FROM payment_methods WHERE id=$1 AND user_id=$2 AND deleted_at IS NULL`, in.PaymentMethodID, uid).Scan(&in.PaymentMethodID, &token)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "invalid_card", "Выберите карту")
			return
		}
		pmID = &in.PaymentMethodID
		payRef, err = a.pay.Hold(ctx, token, payments.HoldAmount(price), a.cfg.Currency, "")
		if err != nil {
			writeErr(w, http.StatusPaymentRequired, "card_declined", "Банк отклонил оплату. Выберите другую карту или наличные")
			return
		}
		payStatus = "held"
	}

	var id string
	err = a.db.QueryRow(ctx, `
		INSERT INTO orders (passenger_id, tariff, status, from_lat, from_lng, from_addr, to_lat, to_lng, to_addr,
			distance_m, duration_s, surge, price, payment_method, payment_method_id, payment_ref, payment_status,
			comment, child_seat, with_pet, route_polyline)
		VALUES ($1,$2,'searching',$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20)
		RETURNING id`,
		uid, t.Code, in.From.Lat, in.From.Lng, in.From.Addr, in.To.Lat, in.To.Lng, in.To.Addr,
		route.DistanceM, route.DurationS, surge, price, in.PaymentMethod, pmID, payRef, payStatus,
		strings.TrimSpace(in.Comment), in.ChildSeat, in.WithPet, polyline).Scan(&id)
	if err != nil {
		if payRef != "" {
			_ = a.pay.Void(ctx, payRef)
		}
		a.internal(w, err)
		return
	}

	if a.cfg.DemoMode && a.isDemoPassenger(ctx, uid) {
		go a.runDemoRide(id)
	} else {
		go a.dispatch(id)
	}
	o, err := a.loadOrder(ctx, id)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, o)
}

func (a *App) getOrder(w http.ResponseWriter, r *http.Request) {
	o, err := a.loadOrder(r.Context(), r.PathValue("id"))
	if err != nil || !canSee(r, o) {
		writeErr(w, http.StatusNotFound, "not_found", "Поездка не найдена")
		return
	}
	writeJSON(w, http.StatusOK, o)
}

func canSee(r *http.Request, o *Order) bool {
	uid := userID(r)
	return o.PassengerID == uid || (o.DriverID != nil && *o.DriverID == uid)
}

func (a *App) activePassengerOrder(w http.ResponseWriter, r *http.Request) {
	var id string
	err := a.db.QueryRow(r.Context(), `SELECT id FROM orders WHERE passenger_id=$1 AND status IN `+activeStatuses+` ORDER BY created_at DESC LIMIT 1`, userID(r)).Scan(&id)
	if isNoRows(err) {
		writeJSON(w, http.StatusOK, nil)
		return
	}
	if err != nil {
		a.internal(w, err)
		return
	}
	o, err := a.loadOrder(r.Context(), id)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, o)
}

func (a *App) listPassengerOrders(w http.ResponseWriter, r *http.Request) {
	a.listOrdersBy(w, r, "passenger_id")
}

func (a *App) listOrdersBy(w http.ResponseWriter, r *http.Request, col string) {
	limit := 30
	rows, err := a.db.Query(r.Context(), `SELECT o.id FROM orders o WHERE o.`+col+`=$1 ORDER BY o.created_at DESC LIMIT $2`, userID(r), limit)
	if err != nil {
		a.internal(w, err)
		return
	}
	var ids []string
	for rows.Next() {
		var id string
		if rows.Scan(&id) == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()
	out := []*Order{}
	for _, id := range ids {
		if o, err := a.loadOrder(r.Context(), id); err == nil {
			out = append(out, o)
		}
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *App) cancelOrder(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Reason string `json:"reason"`
	}
	_ = readJSONOptional(r, &in)
	ctx := r.Context()
	o, err := a.loadOrder(ctx, r.PathValue("id"))
	if err != nil || o.PassengerID != userID(r) {
		writeErr(w, http.StatusNotFound, "not_found", "Поездка не найдена")
		return
	}
	if o.Status != "searching" && o.Status != "assigned" && o.Status != "arrived" {
		writeErr(w, http.StatusConflict, "cannot_cancel", "Поездку уже нельзя отменить")
		return
	}
	t, _ := a.loadTariff(ctx, o.Tariff)
	var assignedAt time.Time
	if o.AssignedAt != nil {
		assignedAt = *o.AssignedAt
	}
	fee := pricing.CancelFee(t, o.Status, assignedAt, time.Now())
	if err := a.cancel(ctx, o, "passenger", in.Reason, fee); err != nil {
		writeErr(w, http.StatusConflict, "cannot_cancel", "Поездку уже нельзя отменить")
		return
	}
	writeJSON(w, http.StatusOK, a.notifyOrder(ctx, o.ID))
}

// cancel moves an active order to cancelled, frees the driver and settles payment.
func (a *App) cancel(ctx context.Context, o *Order, by, reason string, fee int) error {
	tag, err := a.db.Exec(ctx, `
		UPDATE orders SET status='cancelled', cancelled_by=$2, cancel_reason=$3, cancel_fee=$4, cancelled_at=now()
		WHERE id=$1 AND status IN ('searching','assigned','arrived','in_progress')`, o.ID, by, reason, fee)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errConflict
	}
	_, _ = a.db.Exec(ctx, `UPDATE order_offers SET status='expired' WHERE order_id=$1 AND status='offered'`, o.ID)
	if o.DriverID != nil {
		a.releaseDriver(ctx, *o.DriverID)
		a.sendPush(*o.DriverID, push.Message{Title: "Заказ отменён", Body: "Пассажир отменил поездку", Data: map[string]string{"order_id": o.ID}})
		if fee > 0 {
			t, _ := a.loadTariff(ctx, o.Tariff)
			a.creditDriver(ctx, *o.DriverID, o.ID, o.PaymentMethod, fee, pricing.Commission(t, fee))
		}
	}
	if o.paymentRef != "" {
		if fee > 0 {
			err = a.pay.Capture(ctx, o.paymentRef, fee)
			a.setPaymentStatus(ctx, o.ID, "paid", err)
		} else {
			_ = a.pay.Void(ctx, o.paymentRef)
			a.setPaymentStatus(ctx, o.ID, "voided", nil)
		}
	}
	return nil
}

func (a *App) setPaymentStatus(ctx context.Context, orderID, status string, err error) {
	if err != nil {
		slog.Error("payment failed", "order", orderID, "err", err)
		status = "failed"
	}
	_, _ = a.db.Exec(ctx, `UPDATE orders SET payment_status=$2 WHERE id=$1`, orderID, status)
}

func (a *App) releaseDriver(ctx context.Context, driverID string) {
	_, _ = a.db.Exec(ctx, `UPDATE drivers SET busy=false WHERE user_id=$1`, driverID)
	a.rdb.Del(ctx, "driver:order:"+driverID)
}

func (a *App) rateDriver(w http.ResponseWriter, r *http.Request) {
	a.rate(w, r, "passenger_id", "driver_id", "driver_rating")
}

// rate stores a 1–5 rating once per completed trip and updates the average.
func (a *App) rate(w http.ResponseWriter, r *http.Request, selfCol, otherCol, ratingCol string) {
	var in struct {
		Rating  int    `json:"rating"`
		Comment string `json:"comment"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if in.Rating < 1 || in.Rating > 5 {
		writeErr(w, http.StatusBadRequest, "invalid_rating", "Оценка от 1 до 5")
		return
	}
	ctx := r.Context()
	tx, err := a.db.Begin(ctx)
	if err != nil {
		a.internal(w, err)
		return
	}
	defer tx.Rollback(ctx)
	var other *string
	err = tx.QueryRow(ctx, `UPDATE orders SET `+ratingCol+`=$3, rating_comment = CASE WHEN $4 <> '' THEN $4 ELSE rating_comment END
		WHERE id=$1 AND `+selfCol+`=$2 AND status='completed' AND `+ratingCol+` IS NULL RETURNING `+otherCol,
		r.PathValue("id"), userID(r), in.Rating, strings.TrimSpace(in.Comment)).Scan(&other)
	if isNoRows(err) {
		writeErr(w, http.StatusConflict, "cannot_rate", "Эту поездку уже оценили")
		return
	}
	if err != nil {
		a.internal(w, err)
		return
	}
	if other != nil {
		if _, err := tx.Exec(ctx, `UPDATE users SET rating_sum = rating_sum + $2, rating_count = rating_count + 1 WHERE id=$1`, *other, in.Rating); err != nil {
			a.internal(w, err)
			return
		}
	}
	if err := tx.Commit(ctx); err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (a *App) addTip(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Amount int `json:"amount"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if in.Amount <= 0 || in.Amount > 20000 {
		writeErr(w, http.StatusBadRequest, "invalid_tip", "Некорректная сумма")
		return
	}
	ctx := r.Context()
	o, err := a.loadOrder(ctx, r.PathValue("id"))
	if err != nil || o.PassengerID != userID(r) || o.Status != "completed" || o.DriverID == nil || o.Tip > 0 {
		writeErr(w, http.StatusConflict, "cannot_tip", "Чаевые для этой поездки недоступны")
		return
	}
	if o.PaymentMethod != "card" || o.paymentMethodID == nil {
		writeErr(w, http.StatusConflict, "cash_trip", "Чаевые за поездку с наличными передайте водителю")
		return
	}
	var token string
	if err := a.db.QueryRow(ctx, `SELECT token FROM payment_methods WHERE id=$1 AND deleted_at IS NULL`, *o.paymentMethodID).Scan(&token); err != nil {
		writeErr(w, http.StatusConflict, "invalid_card", "Карта больше недоступна")
		return
	}
	ref, err := a.pay.Hold(ctx, token, in.Amount, a.cfg.Currency, o.ID)
	if err == nil {
		err = a.pay.Capture(ctx, ref, in.Amount)
	}
	if err != nil {
		writeErr(w, http.StatusPaymentRequired, "card_declined", "Банк отклонил оплату")
		return
	}
	_, _ = a.db.Exec(ctx, `UPDATE orders SET tip=$2 WHERE id=$1`, o.ID, in.Amount)
	_, _ = a.db.Exec(ctx, `INSERT INTO driver_transactions (driver_id, order_id, kind, amount) VALUES ($1,$2,'tip',$3)`, *o.DriverID, o.ID, in.Amount)
	_, _ = a.db.Exec(ctx, `UPDATE drivers SET balance = balance + $2 WHERE user_id=$1`, *o.DriverID, in.Amount)
	writeJSON(w, http.StatusOK, a.notifyOrder(ctx, o.ID))
}

func readJSONOptional(r *http.Request, v any) bool {
	if r.ContentLength == 0 {
		return false
	}
	return decodeBody(r, v) == nil
}
