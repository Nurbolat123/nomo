package app

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/nomo-taxi/nomo/backend/internal/pricing"
)

type Place struct {
	Lat  float64 `json:"lat"`
	Lng  float64 `json:"lng"`
	Addr string  `json:"addr"`
}

type DriverCard struct {
	ID       string  `json:"id"`
	Name     string  `json:"name"`
	Rating   float64 `json:"rating"`
	CarMake  string  `json:"car_make"`
	CarModel string  `json:"car_model"`
	CarColor string  `json:"car_color"`
	CarPlate string  `json:"car_plate"`
}

type PassengerCard struct {
	ID     string  `json:"id"`
	Name   string  `json:"name"`
	Rating float64 `json:"rating"`
}

type Order struct {
	ID              string         `json:"id"`
	PassengerID     string         `json:"passenger_id"`
	DriverID        *string        `json:"driver_id"`
	Tariff          string         `json:"tariff"`
	Status          string         `json:"status"`
	From            Place          `json:"from"`
	To              Place          `json:"to"`
	DistanceM       int            `json:"distance_m"`
	DurationS       int            `json:"duration_s"`
	Surge           float64        `json:"surge"`
	Price           int            `json:"price"`
	FinalPrice      *int           `json:"final_price"`
	Tip             int            `json:"tip"`
	PaymentMethod   string         `json:"payment_method"`
	PaymentStatus   string         `json:"payment_status"`
	Comment         string         `json:"comment"`
	ChildSeat       bool           `json:"child_seat"`
	WithPet         bool           `json:"with_pet"`
	CancelledBy     string         `json:"cancelled_by"`
	CancelReason    string         `json:"cancel_reason"`
	CancelFee       int            `json:"cancel_fee"`
	DriverRating    *int           `json:"driver_rating"`
	PassengerRating *int           `json:"passenger_rating"`
	CreatedAt       time.Time      `json:"created_at"`
	AssignedAt      *time.Time     `json:"assigned_at"`
	ArrivedAt       *time.Time     `json:"arrived_at"`
	StartedAt       *time.Time     `json:"started_at"`
	CompletedAt     *time.Time     `json:"completed_at"`
	CancelledAt     *time.Time     `json:"cancelled_at"`
	Currency        string         `json:"currency"`
	Driver          *DriverCard    `json:"driver,omitempty"`
	Passenger       *PassengerCard `json:"passenger,omitempty"`

	paymentRef      string
	paymentMethodID *string
}

const orderCols = `o.id, o.passenger_id, o.driver_id, o.tariff, o.status,
	o.from_lat, o.from_lng, o.from_addr, o.to_lat, o.to_lng, o.to_addr,
	o.distance_m, o.duration_s, o.surge::float8, o.price, o.final_price, o.tip,
	o.payment_method, o.payment_status, o.comment, o.child_seat, o.with_pet,
	o.cancelled_by, o.cancel_reason, o.cancel_fee, o.driver_rating, o.passenger_rating,
	o.created_at, o.assigned_at, o.arrived_at, o.started_at, o.completed_at, o.cancelled_at,
	o.payment_ref, o.payment_method_id`

func scanOrder(row pgx.Row) (*Order, error) {
	var o Order
	err := row.Scan(&o.ID, &o.PassengerID, &o.DriverID, &o.Tariff, &o.Status,
		&o.From.Lat, &o.From.Lng, &o.From.Addr, &o.To.Lat, &o.To.Lng, &o.To.Addr,
		&o.DistanceM, &o.DurationS, &o.Surge, &o.Price, &o.FinalPrice, &o.Tip,
		&o.PaymentMethod, &o.PaymentStatus, &o.Comment, &o.ChildSeat, &o.WithPet,
		&o.CancelledBy, &o.CancelReason, &o.CancelFee, &o.DriverRating, &o.PassengerRating,
		&o.CreatedAt, &o.AssignedAt, &o.ArrivedAt, &o.StartedAt, &o.CompletedAt, &o.CancelledAt,
		&o.paymentRef, &o.paymentMethodID)
	if err != nil {
		return nil, err
	}
	return &o, nil
}

// loadOrder reads an order with driver and passenger cards filled in.
func (a *App) loadOrder(ctx context.Context, id string) (*Order, error) {
	o, err := scanOrder(a.db.QueryRow(ctx, `SELECT `+orderCols+` FROM orders o WHERE o.id=$1`, id))
	if err != nil {
		return nil, err
	}
	o.Currency = a.cfg.Currency
	var p PassengerCard
	var sum, cnt int
	if err := a.db.QueryRow(ctx, `SELECT id, name, rating_sum, rating_count FROM users WHERE id=$1`, o.PassengerID).Scan(&p.ID, &p.Name, &sum, &cnt); err == nil {
		p.Rating = rating(sum, cnt)
		o.Passenger = &p
	}
	if o.DriverID != nil {
		var d DriverCard
		err := a.db.QueryRow(ctx, `
			SELECT u.id, u.name, u.rating_sum, u.rating_count, d.car_make, d.car_model, d.car_color, d.car_plate
			FROM users u JOIN drivers d ON d.user_id = u.id WHERE u.id=$1`, *o.DriverID).
			Scan(&d.ID, &d.Name, &sum, &cnt, &d.CarMake, &d.CarModel, &d.CarColor, &d.CarPlate)
		if err == nil {
			d.Rating = rating(sum, cnt)
			o.Driver = &d
		}
	}
	return o, nil
}

func rating(sum, count int) float64 {
	if count == 0 {
		return 5.0
	}
	r := float64(sum) / float64(count)
	return float64(int(r*100+0.5)) / 100
}

func (a *App) loadTariff(ctx context.Context, code string) (pricing.Tariff, error) {
	var t pricing.Tariff
	err := a.db.QueryRow(ctx, `SELECT code, name, base_fare, per_km, per_min, min_fare, free_wait_min, wait_per_min, cancel_fee, commission_pct, sort, active FROM tariffs WHERE code=$1`, code).
		Scan(&t.Code, &t.Name, &t.BaseFare, &t.PerKm, &t.PerMin, &t.MinFare, &t.FreeWaitMin, &t.WaitPerMin, &t.CancelFee, &t.CommissionPct, &t.Sort, &t.Active)
	return t, err
}

func (a *App) activeTariffs(ctx context.Context, all bool) ([]pricing.Tariff, error) {
	q := `SELECT code, name, base_fare, per_km, per_min, min_fare, free_wait_min, wait_per_min, cancel_fee, commission_pct, sort, active FROM tariffs`
	if !all {
		q += ` WHERE active`
	}
	q += ` ORDER BY sort`
	rows, err := a.db.Query(ctx, q)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []pricing.Tariff
	for rows.Next() {
		var t pricing.Tariff
		if err := rows.Scan(&t.Code, &t.Name, &t.BaseFare, &t.PerKm, &t.PerMin, &t.MinFare, &t.FreeWaitMin, &t.WaitPerMin, &t.CancelFee, &t.CommissionPct, &t.Sort, &t.Active); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// notifyOrder sends the fresh order to both sides over WebSocket.
func (a *App) notifyOrder(ctx context.Context, id string) *Order {
	o, err := a.loadOrder(ctx, id)
	if err != nil {
		return nil
	}
	a.hub.Publish(o.PassengerID, "order.updated", o)
	if o.DriverID != nil {
		a.hub.Publish(*o.DriverID, "order.updated", o)
	}
	return o
}

const activeStatuses = `('searching','assigned','arrived','in_progress')`
