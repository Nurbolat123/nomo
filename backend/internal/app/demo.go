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
	start := geo.Offset(geo.Point{Lat: o.From.Lat, Lng: o.From.Lng}, 700, 500)
	a.rdb.Del(ctx, "driver:order:"+driverID)
	a.updateDriverLocation(ctx, driverID, start.Lat, start.Lng, 0)

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

	pickup := geo.Point{Lat: o.From.Lat, Lng: o.From.Lng}
	dest := geo.Point{Lat: o.To.Lat, Lng: o.To.Lng}
	if !a.demoDrive(ctx, orderID, driverID, start, pickup, 20, "assigned") {
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
	if !a.demoDrive(ctx, orderID, driverID, pickup, dest, 30, "in_progress") {
		return
	}
	if _, err := a.complete(ctx, orderID, driverID); err != nil {
		slog.Error("demo complete", "err", err)
	}
}

// demoDrive moves the bot from a to b in `steps` one-second steps; it stops
// early (returning false) if the order leaves the expected status.
func (a *App) demoDrive(ctx context.Context, orderID, driverID string, from, to geo.Point, steps int, status string) bool {
	heading := geo.Bearing(from, to)
	for i := 1; i <= steps; i++ {
		if !a.demoWait(ctx, orderID, time.Second, status) {
			return false
		}
		p := geo.Interpolate(from, to, float64(i)/float64(steps))
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
