package app

import (
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/nomo-taxi/nomo/backend/internal/pricing"
	"github.com/nomo-taxi/nomo/backend/internal/push"
)

func (a *App) adminLive(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	type car struct {
		ID     string  `json:"id"`
		Name   string  `json:"name"`
		Plate  string  `json:"plate"`
		Lat    float64 `json:"lat"`
		Lng    float64 `json:"lng"`
		Busy   bool    `json:"busy"`
	}
	cars := []car{}
	rows, err := a.db.Query(ctx, `SELECT u.id, u.name, d.car_plate, d.busy FROM drivers d JOIN users u ON u.id=d.user_id WHERE d.online`)
	if err != nil {
		a.internal(w, err)
		return
	}
	var list []car
	for rows.Next() {
		var c car
		if rows.Scan(&c.ID, &c.Name, &c.Plate, &c.Busy) == nil {
			list = append(list, c)
		}
	}
	rows.Close()
	if len(list) > 0 {
		names := make([]string, len(list))
		for i, c := range list {
			names[i] = c.ID
		}
		pos, _ := a.rdb.GeoPos(ctx, geoKey, names...).Result()
		for i, c := range list {
			if i < len(pos) && pos[i] != nil {
				c.Lat, c.Lng = pos[i].Latitude, pos[i].Longitude
				cars = append(cars, c)
			}
		}
	}
	orders := []*Order{}
	ids, err := a.collectIDs(r, `SELECT id FROM orders WHERE status IN `+activeStatuses+` ORDER BY created_at DESC LIMIT 200`)
	if err != nil {
		a.internal(w, err)
		return
	}
	for _, id := range ids {
		if o, err := a.loadOrder(ctx, id); err == nil {
			orders = append(orders, o)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"drivers": cars, "orders": orders})
}

func (a *App) collectIDs(r *http.Request, q string, args ...any) ([]string, error) {
	rows, err := a.db.Query(r.Context(), q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (a *App) adminStats(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	days, _ := strconv.Atoi(r.URL.Query().Get("days"))
	if days <= 0 || days > 365 {
		days = 1
	}
	since := time.Now().AddDate(0, 0, -days)
	var s struct {
		Trips          int     `json:"trips"`
		Revenue        int     `json:"revenue"`
		Commission     int     `json:"commission"`
		Cancelled      int     `json:"cancelled"`
		NoDrivers      int     `json:"no_drivers"`
		CancelRate     float64 `json:"cancel_rate"`
		AvgPickupS     int     `json:"avg_pickup_s"`
		DriversOnline  int     `json:"drivers_online"`
		DriversPending int     `json:"drivers_pending"`
		Currency       string  `json:"currency"`
	}
	err := a.db.QueryRow(ctx, `
		SELECT count(*) FILTER (WHERE status='completed'),
		       COALESCE(sum(final_price) FILTER (WHERE status='completed'), 0),
		       count(*) FILTER (WHERE status='cancelled'),
		       count(*) FILTER (WHERE status='no_drivers'),
		       COALESCE(avg(EXTRACT(EPOCH FROM arrived_at - assigned_at)) FILTER (WHERE arrived_at IS NOT NULL), 0)::int
		FROM orders WHERE created_at >= $1`, since).Scan(&s.Trips, &s.Revenue, &s.Cancelled, &s.NoDrivers, &s.AvgPickupS)
	if err != nil {
		a.internal(w, err)
		return
	}
	_ = a.db.QueryRow(ctx, `SELECT COALESCE(-sum(amount),0) FROM driver_transactions WHERE kind='commission' AND created_at >= $1`, since).Scan(&s.Commission)
	_ = a.db.QueryRow(ctx, `SELECT count(*) FILTER (WHERE online), count(*) FILTER (WHERE status='pending') FROM drivers`).Scan(&s.DriversOnline, &s.DriversPending)
	total := s.Trips + s.Cancelled + s.NoDrivers
	if total > 0 {
		s.CancelRate = float64(int(float64(s.Cancelled+s.NoDrivers)/float64(total)*1000)) / 10
	}
	s.Currency = a.cfg.Currency
	writeJSON(w, http.StatusOK, s)
}

func (a *App) adminDrivers(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	q := `SELECT user_id FROM drivers d JOIN users u ON u.id=d.user_id WHERE u.deleted_at IS NULL`
	var args []any
	if status != "" {
		q += ` AND d.status=$1`
		args = append(args, status)
	}
	q += ` ORDER BY d.created_at DESC LIMIT 300`
	ids, err := a.collectIDs(r, q, args...)
	if err != nil {
		a.internal(w, err)
		return
	}
	out := []*DriverProfile{}
	for _, id := range ids {
		if p, err := a.loadDriverProfile(r.Context(), id, true); err == nil {
			out = append(out, p)
		}
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *App) adminDriver(w http.ResponseWriter, r *http.Request) {
	p, err := a.loadDriverProfile(r.Context(), r.PathValue("id"), true)
	if err != nil {
		writeErr(w, http.StatusNotFound, "not_found", "Водитель не найден")
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (a *App) adminSetDriverStatus(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Status  string   `json:"status"`
		Note    string   `json:"note"`
		Classes []string `json:"classes"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if in.Status != "approved" && in.Status != "rejected" && in.Status != "blocked" && in.Status != "pending" {
		writeErr(w, http.StatusBadRequest, "invalid_status", "Неизвестный статус")
		return
	}
	ctx := r.Context()
	id := r.PathValue("id")
	q := `UPDATE drivers SET status=$2, status_note=$3, online = CASE WHEN $2='approved' THEN online ELSE false END`
	args := []any{id, in.Status, strings.TrimSpace(in.Note)}
	if len(in.Classes) > 0 {
		q += `, classes=$4`
		args = append(args, in.Classes)
	}
	tag, err := a.db.Exec(ctx, q+` WHERE user_id=$1`, args...)
	if err != nil {
		a.internal(w, err)
		return
	}
	if tag.RowsAffected() == 0 {
		writeErr(w, http.StatusNotFound, "not_found", "Водитель не найден")
		return
	}
	if in.Status != "approved" {
		a.rdb.ZRem(ctx, geoKey, id)
	}
	msg := map[string]string{
		"approved": "Профиль одобрен — можно выходить на линию",
		"rejected": "Профиль отклонён: " + in.Note,
		"blocked":  "Аккаунт заблокирован. Обратитесь в поддержку",
		"pending":  "Профиль снова на проверке",
	}[in.Status]
	a.sendPush(id, push.Message{Title: "Nomo Driver", Body: msg, Data: map[string]string{"type": "driver_status"}})
	p, _ := a.loadDriverProfile(ctx, id, true)
	a.hub.Publish(id, "driver.status", p)
	writeJSON(w, http.StatusOK, p)
}

func (a *App) adminFile(w http.ResponseWriter, r *http.Request) {
	rel := filepath.Clean("/" + r.PathValue("path"))
	full := filepath.Join(a.cfg.UploadDir, rel)
	base, _ := filepath.Abs(a.cfg.UploadDir)
	abs, _ := filepath.Abs(full)
	if !strings.HasPrefix(abs, base+string(os.PathSeparator)) {
		writeErr(w, http.StatusNotFound, "not_found", "Файл не найден")
		return
	}
	w.Header().Set("Cache-Control", "private, max-age=300")
	http.ServeFile(w, r, abs)
}

func (a *App) adminTariffs(w http.ResponseWriter, r *http.Request) {
	ts, err := a.activeTariffs(r.Context(), true)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, ts)
}

func (a *App) adminUpdateTariff(w http.ResponseWriter, r *http.Request) {
	var t pricing.Tariff
	if !readJSON(w, r, &t) {
		return
	}
	if t.Name == "" || t.BaseFare < 0 || t.PerKm < 0 || t.PerMin < 0 || t.MinFare < 0 || t.CommissionPct < 0 || t.CommissionPct > 50 {
		writeErr(w, http.StatusBadRequest, "invalid_tariff", "Проверьте значения тарифа")
		return
	}
	code := r.PathValue("code")
	_, err := a.db.Exec(r.Context(), `
		INSERT INTO tariffs (code, name, base_fare, per_km, per_min, min_fare, free_wait_min, wait_per_min, cancel_fee, commission_pct, sort, active)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
		ON CONFLICT (code) DO UPDATE SET name=$2, base_fare=$3, per_km=$4, per_min=$5, min_fare=$6, free_wait_min=$7,
			wait_per_min=$8, cancel_fee=$9, commission_pct=$10, sort=$11, active=$12`,
		code, t.Name, t.BaseFare, t.PerKm, t.PerMin, t.MinFare, t.FreeWaitMin, t.WaitPerMin, t.CancelFee, t.CommissionPct, t.Sort, t.Active)
	if err != nil {
		a.internal(w, err)
		return
	}
	t, _ = a.loadTariff(r.Context(), code)
	writeJSON(w, http.StatusOK, t)
}

func (a *App) adminOrders(w http.ResponseWriter, r *http.Request) {
	q := `SELECT id FROM orders WHERE true`
	var args []any
	if s := r.URL.Query().Get("status"); s != "" {
		args = append(args, s)
		q += ` AND status=$` + strconv.Itoa(len(args))
	}
	if p := r.URL.Query().Get("phone"); p != "" {
		if phone, ok := NormalizePhone(p); ok {
			args = append(args, phone)
			n := strconv.Itoa(len(args))
			q += ` AND (passenger_id IN (SELECT id FROM users WHERE phone=$` + n + `) OR driver_id IN (SELECT id FROM users WHERE phone=$` + n + `))`
		}
	}
	q += ` ORDER BY created_at DESC LIMIT 200`
	ids, err := a.collectIDs(r, q, args...)
	if err != nil {
		a.internal(w, err)
		return
	}
	out := []*Order{}
	for _, id := range ids {
		if o, err := a.loadOrder(r.Context(), id); err == nil {
			out = append(out, o)
		}
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *App) adminCancelOrder(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	o, err := a.loadOrder(ctx, r.PathValue("id"))
	if err != nil {
		writeErr(w, http.StatusNotFound, "not_found", "Поездка не найдена")
		return
	}
	if err := a.cancel(ctx, o, "admin", "Отменено поддержкой", 0); err != nil {
		writeErr(w, http.StatusConflict, "cannot_cancel", "Поездку уже нельзя отменить")
		return
	}
	writeJSON(w, http.StatusOK, a.notifyOrder(ctx, o.ID))
}
