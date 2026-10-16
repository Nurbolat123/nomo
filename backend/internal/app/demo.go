package app

import (
	"context"
	"log/slog"
	"time"

	"github.com/nomo-taxi/nomo/backend/internal/geo"
)

// Demo mode lets App Store / Google Play reviewers complete a whole trip
// without real drivers: signing in with DEMO_PHONE and DEMO_CODE, every order
// is taken by a bot driver who drives to the pickup and to the destination.
// When the app sent a road route (Yandex MapKit), the bot follows real streets.

const (
	demoApproachM    = 900  // how far from the pickup the bot starts
	demoApproachTime = 20.0 // seconds to reach the pickup
	demoTripTime     = 35.0 // seconds for the whole trip
	demoTick         = time.Second
)

func (a *App) isDemoPassenger(ctx context.Context, uid string) bool {
	var phone string
	_ = a.db.QueryRow(ctx, `SELECT phone FROM users WHERE id=$1`, uid).Scan(&phone)
	return phone == a.cfg.DemoPhone
}

func (a *App) ensureDemoDriver(ctx context.Context) (string, error) {
	var id string
	err := a.db.QueryRow(ctx, `
		INSERT INTO users (phone, role, name, rating_sum, rating_count) VALUES ($1, 'driver', 'Демо водитель', 49, 10)
		ON CONFLICT (phone, role) DO UPDATE SET phone = EXCLUDED.phone RETURNING id`, a.cfg.DemoDriverPhone).Scan(&id)
	if err != nil {
		return "", err
	}
	_, err = a.db.Exec(ctx, `
		INSERT INTO drivers (user_id, status, car_make, car_model, car_color, car_plate, car_year, classes, online, busy)
		VALUES ($1, 'approved', 'Toyota', 'Camry', 'Белая', '777NMO02', 2022, ARRAY['economy','comfort','business'], true, false)
		ON CONFLICT (user_id) DO UPDATE SET status='approved', online=true, busy=false,
			classes=ARRAY['economy','comfort','business']`, id)
	return id, err
}

// demoPaths returns the approach path (ends at the pickup) and the trip path.
// With a road route the bot comes back along the first part of the route,
// so it stays on real streets; otherwise it drives in straight lines.
func demoPaths(o *Order) (approach, trip []geo.Point) {
	pickup := geo.Point{Lat: o.From.Lat, Lng: o.From.Lng}
	dest := geo.Point{Lat: o.To.Lat, Lng: o.To.Lng}
	if pts, err := geo.Decode(o.Route); err == nil && len(pts) >= 2 {
		trip = pts
		approach = geo.Reverse(geo.Head(pts, demoApproachM))
		return approach, trip
	}
	start := geo.Offset(pickup, 700, 500)
	return []geo.Point{start, pickup}, []geo.Point{pickup, dest}
}

func (a *App) runDemoRide(orderID string) {
	ctx := a.ctx
	o, err := a.loadOrder(ctx, orderID)
	if err != nil {
		return
	}
	driverID, err := a.ensureDemoDriver(ctx)
	if err != nil {
		slog.Error("demo driver", "err", err)
		return
	}
	approach, trip := demoPaths(o)
	a.rdb.Del(ctx, "driver:order:"+driverID)
	start, heading := geo.Along(approach, 0)
	a.updateDriverLocation(ctx, driverID, start.Lat, start.Lng, heading)

	if !a.demoWait(ctx, orderID, 3*time.Second, "searching") {
		return
	}
	if _, err := a.db.Exec(ctx, `INSERT INTO order_offers (order_id, driver_id, status, eta_s) VALUES ($1,$2,'offered',120) ON CONFLICT DO NOTHING`, orderID, driverID); err != nil {
		return
	}
	if err := a.assign(ctx, orderID, driverID); err != nil {
		return
	}
	a.notifyOrder(ctx, orderID)

	if !a.demoDrive(ctx, orderID, driverID, approach, demoApproachTime, "assigned") {
		return
	}
	if a.transition(ctx, orderID, driverID, "assigned", "arrived", "arrived_at") != nil {
		return
	}
	a.notifyOrder(ctx, orderID)
	if !a.demoWait(ctx, orderID, 6*time.Second, "arrived") {
		return
	}
	if a.transition(ctx, orderID, driverID, "arrived", "in_progress", "started_at") != nil {
		return
	}
	a.notifyOrder(ctx, orderID)
	if !a.demoDrive(ctx, orderID, driverID, trip, demoTripTime, "in_progress") {
		return
	}
	if _, err := a.complete(ctx, orderID, driverID); err != nil {
		slog.Error("demo complete", "err", err)
	}
}

// demoDrive moves the bot along the path in about `seconds`, sending a
// position every tick; it stops early (false) if the order leaves `status`.
func (a *App) demoDrive(ctx context.Context, orderID, driverID string, path []geo.Point, seconds float64, status string) bool {
	total := geo.Length(path)
	steps := int(seconds / demoTick.Seconds())
	if steps < 1 {
		steps = 1
	}
	for i := 1; i <= steps; i++ {
		if !a.demoWait(ctx, orderID, demoTick, status) {
			return false
		}
		p, heading := geo.Along(path, total*float64(i)/float64(steps))
		a.updateDriverLocation(ctx, driverID, p.Lat, p.Lng, heading)
	}
	return true
}

func (a *App) demoWait(ctx context.Context, orderID string, d time.Duration, status string) bool {
	sleepCtx(ctx, d)
	var s string
	if err := a.db.QueryRow(ctx, `SELECT status FROM orders WHERE id=$1`, orderID).Scan(&s); err != nil {
		return false
	}
	return s == status
}
