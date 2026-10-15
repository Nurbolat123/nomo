package app

import (
	"context"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/nomo-taxi/nomo/backend/internal/pricing"
	"github.com/nomo-taxi/nomo/backend/internal/push"
)

type DriverProfile struct {
	ID         string     `json:"id"`
	Phone      string     `json:"phone"`
	Name       string     `json:"name"`
	Rating     float64    `json:"rating"`
	Status     string     `json:"status"`
	StatusNote string     `json:"status_note"`
	CarMake    string     `json:"car_make"`
	CarModel   string     `json:"car_model"`
	CarColor   string     `json:"car_color"`
	CarPlate   string     `json:"car_plate"`
	CarYear    int        `json:"car_year"`
	Classes    []string   `json:"classes"`
	Online     bool       `json:"online"`
	Busy       bool       `json:"busy"`
	Balance    int64      `json:"balance"`
	Documents  []Document `json:"documents"`
	Currency   string     `json:"currency"`
}

type Document struct {
	ID        string    `json:"id"`
	Kind      string    `json:"kind"`
	URL       string    `json:"url,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

var requiredDocs = []string{"license", "sts", "osago", "car_photo", "selfie"}

func (a *App) loadDriverProfile(ctx context.Context, id string, withURLs bool) (*DriverProfile, error) {
	var p DriverProfile
	var sum, cnt int
	err := a.db.QueryRow(ctx, `
		SELECT u.id, u.phone, u.name, u.rating_sum, u.rating_count, d.status, d.status_note,
		       d.car_make, d.car_model, d.car_color, d.car_plate, d.car_year, d.classes, d.online, d.busy, d.balance
		FROM users u JOIN drivers d ON d.user_id = u.id WHERE u.id=$1`, id).
		Scan(&p.ID, &p.Phone, &p.Name, &sum, &cnt, &p.Status, &p.StatusNote, &p.CarMake, &p.CarModel, &p.CarColor,
			&p.CarPlate, &p.CarYear, &p.Classes, &p.Online, &p.Busy, &p.Balance)
	if err != nil {
		return nil, err
	}
	p.Rating = rating(sum, cnt)
	p.Currency = a.cfg.Currency
	rows, err := a.db.Query(ctx, `SELECT DISTINCT ON (kind) id, kind, path, created_at FROM driver_documents WHERE driver_id=$1 ORDER BY kind, created_at DESC`, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	p.Documents = []Document{}
	for rows.Next() {
		var d Document
		var path string
		if err := rows.Scan(&d.ID, &d.Kind, &path, &d.CreatedAt); err != nil {
			return nil, err
		}
		if withURLs {
			d.URL = "/v1/admin/files/" + path
		}
		p.Documents = append(p.Documents, d)
	}
	return &p, nil
}

func (a *App) driverProfile(w http.ResponseWriter, r *http.Request) {
	p, err := a.loadDriverProfile(r.Context(), userID(r), false)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (a *App) updateCar(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name     string `json:"name"`
		CarMake  string `json:"car_make"`
		CarModel string `json:"car_model"`
		CarColor string `json:"car_color"`
		CarPlate string `json:"car_plate"`
		CarYear  int    `json:"car_year"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	in.CarPlate = strings.ToUpper(strings.ReplaceAll(strings.TrimSpace(in.CarPlate), " ", ""))
	year := time.Now().Year()
	if strings.TrimSpace(in.Name) == "" || in.CarMake == "" || in.CarModel == "" || in.CarPlate == "" || in.CarYear < 1990 || in.CarYear > year+1 {
		writeErr(w, http.StatusBadRequest, "invalid_car", "Заполните имя и все данные машины")
		return
	}
	ctx := r.Context()
	// Changing the car of an approved driver sends the profile back to review.
	_, err := a.db.Exec(ctx, `
		UPDATE drivers SET car_make=$2, car_model=$3, car_color=$4, car_plate=$5, car_year=$6,
			status = CASE WHEN status='approved' AND (car_plate <> $5 OR car_make <> $2 OR car_model <> $3) THEN 'pending' ELSE status END,
			online = CASE WHEN status='approved' AND (car_plate <> $5 OR car_make <> $2 OR car_model <> $3) THEN false ELSE online END
		WHERE user_id=$1`, userID(r), strings.TrimSpace(in.CarMake), strings.TrimSpace(in.CarModel), strings.TrimSpace(in.CarColor), in.CarPlate, in.CarYear)
	if err != nil {
		a.internal(w, err)
		return
	}
	if _, err := a.db.Exec(ctx, `UPDATE users SET name=$2 WHERE id=$1`, userID(r), strings.TrimSpace(in.Name)); err != nil {
		a.internal(w, err)
		return
	}
	a.driverProfile(w, r)
}

func (a *App) uploadDocument(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, 11<<20)
	if err := r.ParseMultipartForm(11 << 20); err != nil {
		writeErr(w, http.StatusBadRequest, "file_too_large", "Файл больше 10 МБ")
		return
	}
	kind := r.FormValue("kind")
	known := false
	for _, k := range requiredDocs {
		if k == kind {
			known = true
		}
	}
	if !known {
		writeErr(w, http.StatusBadRequest, "invalid_kind", "Неизвестный тип документа")
		return
	}
	f, hdr, err := r.FormFile("file")
	if err != nil {
		writeErr(w, http.StatusBadRequest, "no_file", "Прикрепите фото")
		return
	}
	defer f.Close()
	head := make([]byte, 512)
	n, _ := io.ReadFull(f, head)
	ext := ""
	switch http.DetectContentType(head[:n]) {
	case "image/jpeg":
		ext = ".jpg"
	case "image/png":
		ext = ".png"
	case "application/pdf":
		ext = ".pdf"
	default:
		if strings.HasSuffix(strings.ToLower(hdr.Filename), ".heic") {
			ext = ".heic"
		} else {
			writeErr(w, http.StatusBadRequest, "invalid_type", "Нужно фото JPG, PNG или PDF")
			return
		}
	}
	id := userID(r)
	rel := filepath.Join(id, fmt.Sprintf("%s-%d%s", kind, time.Now().UnixNano(), ext))
	full := filepath.Join(a.cfg.UploadDir, rel)
	if err := os.MkdirAll(filepath.Dir(full), 0o750); err != nil {
		a.internal(w, err)
		return
	}
	out, err := os.OpenFile(full, os.O_CREATE|os.O_WRONLY|os.O_EXCL, 0o640)
	if err != nil {
		a.internal(w, err)
		return
	}
	if _, err := out.Write(head[:n]); err == nil {
		_, err = io.Copy(out, f)
	}
	out.Close()
	if err != nil {
		a.internal(w, err)
		return
	}
	var d Document
	err = a.db.QueryRow(r.Context(), `INSERT INTO driver_documents (driver_id, kind, path) VALUES ($1,$2,$3) RETURNING id, kind, created_at`, id, kind, filepath.ToSlash(rel)).
		Scan(&d.ID, &d.Kind, &d.CreatedAt)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, d)
}

func (a *App) submitForReview(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	p, err := a.loadDriverProfile(ctx, userID(r), false)
	if err != nil {
		a.internal(w, err)
		return
	}
	if p.CarPlate == "" || p.Name == "" {
		writeErr(w, http.StatusBadRequest, "car_missing", "Заполните данные машины")
		return
	}
	have := map[string]bool{}
	for _, d := range p.Documents {
		have[d.Kind] = true
	}
	for _, k := range requiredDocs {
		if !have[k] {
			writeErr(w, http.StatusBadRequest, "docs_missing", "Загрузите все документы")
			return
		}
	}
	if p.Status == "blocked" {
		writeErr(w, http.StatusForbidden, "blocked", "Аккаунт заблокирован. Обратитесь в поддержку")
		return
	}
	if _, err := a.db.Exec(ctx, `UPDATE drivers SET status='pending', status_note='' WHERE user_id=$1 AND status IN ('new','rejected','pending')`, userID(r)); err != nil {
		a.internal(w, err)
		return
	}
	a.driverProfile(w, r)
}

func (a *App) setOnline(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Online bool    `json:"online"`
		Lat    float64 `json:"lat"`
		Lng    float64 `json:"lng"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	ctx := r.Context()
	id := userID(r)
	if in.Online {
		tag, err := a.db.Exec(ctx, `UPDATE drivers SET online=true WHERE user_id=$1 AND status='approved'`, id)
		if err != nil {
			a.internal(w, err)
			return
		}
		if tag.RowsAffected() == 0 {
			writeErr(w, http.StatusForbidden, "not_approved", "Профиль ещё на проверке")
			return
		}
		a.updateDriverLocation(ctx, id, in.Lat, in.Lng, 0)
	} else {
		if _, err := a.db.Exec(ctx, `UPDATE drivers SET online=false WHERE user_id=$1`, id); err != nil {
			a.internal(w, err)
			return
		}
		a.rdb.ZRem(ctx, geoKey, id)
		a.rdb.Del(ctx, "driver:seen:"+id)
	}
	a.driverProfile(w, r)
}

func (a *App) driverLocationHTTP(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Lat     float64 `json:"lat"`
		Lng     float64 `json:"lng"`
		Heading float64 `json:"heading"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	a.updateDriverLocation(r.Context(), userID(r), in.Lat, in.Lng, in.Heading)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (a *App) currentOffer(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var orderID string
	var eta int
	var created time.Time
	err := a.db.QueryRow(ctx, `SELECT order_id, eta_s, created_at FROM order_offers WHERE driver_id=$1 AND status='offered' AND created_at > now() - $2::interval ORDER BY created_at DESC LIMIT 1`,
		userID(r), a.cfg.OfferTimeout.String()).Scan(&orderID, &eta, &created)
	if isNoRows(err) {
		writeJSON(w, http.StatusOK, nil)
		return
	}
	if err != nil {
		a.internal(w, err)
		return
	}
	o, err := a.loadOrder(ctx, orderID)
	if err != nil {
		a.internal(w, err)
		return
	}
	c := candidate{etaS: eta, distM: float64(eta) * 28 / 3.6 / 1.35}
	writeJSON(w, http.StatusOK, a.buildOffer(o, c, created.Add(a.cfg.OfferTimeout)))
}

func (a *App) acceptOffer(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	orderID, driverID := r.PathValue("id"), userID(r)
	if err := a.assign(ctx, orderID, driverID); err != nil {
		writeErr(w, http.StatusConflict, "offer_gone", "Заказ уже недоступен")
		return
	}
	o := a.notifyOrder(ctx, orderID)
	if o != nil {
		a.sendPush(o.PassengerID, push.Message{Title: "Водитель едет к вам", Body: carLine(o), Data: map[string]string{"order_id": orderID}})
	}
	writeJSON(w, http.StatusOK, o)
}

// assign atomically gives the order to the driver if the offer is still open.
func (a *App) assign(ctx context.Context, orderID, driverID string) error {
	tx, err := a.db.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	tag, err := tx.Exec(ctx, `UPDATE order_offers SET status='accepted' WHERE order_id=$1 AND driver_id=$2 AND status='offered'`, orderID, driverID)
	if err != nil || tag.RowsAffected() == 0 {
		return errConflict
	}
	tag, err = tx.Exec(ctx, `UPDATE orders SET driver_id=$2, status='assigned', assigned_at=now() WHERE id=$1 AND status='searching'`, orderID, driverID)
	if err != nil || tag.RowsAffected() == 0 {
		return errConflict
	}
	tag, err = tx.Exec(ctx, `UPDATE drivers SET busy=true WHERE user_id=$1 AND NOT busy`, driverID)
	if err != nil || tag.RowsAffected() == 0 {
		return errConflict
	}
	if err := tx.Commit(ctx); err != nil {
		return err
	}
	a.rdb.Set(ctx, "driver:order:"+driverID, orderID, 24*time.Hour)
	return nil
}

func carLine(o *Order) string {
	if o.Driver == nil {
		return ""
	}
	return strings.TrimSpace(fmt.Sprintf("%s %s %s, %s", o.Driver.CarColor, o.Driver.CarMake, o.Driver.CarModel, o.Driver.CarPlate))
}

func (a *App) declineOffer(w http.ResponseWriter, r *http.Request) {
	_, err := a.db.Exec(r.Context(), `UPDATE order_offers SET status='declined' WHERE order_id=$1 AND driver_id=$2 AND status='offered'`, r.PathValue("id"), userID(r))
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (a *App) activeDriverOrder(w http.ResponseWriter, r *http.Request) {
	var id string
	err := a.db.QueryRow(r.Context(), `SELECT id FROM orders WHERE driver_id=$1 AND status IN ('assigned','arrived','in_progress') ORDER BY created_at DESC LIMIT 1`, userID(r)).Scan(&id)
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

func (a *App) listDriverOrders(w http.ResponseWriter, r *http.Request) {
	a.listOrdersBy(w, r, "driver_id")
}

// transition moves the driver's order from one status to the next.
func (a *App) transition(ctx context.Context, orderID, driverID, from, to, tsCol string) error {
	tag, err := a.db.Exec(ctx, `UPDATE orders SET status=$4, `+tsCol+`=now() WHERE id=$1 AND driver_id=$2 AND status=$3`, orderID, driverID, from, to)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return errConflict
	}
	return nil
}

func (a *App) driverArrived(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if err := a.transition(ctx, r.PathValue("id"), userID(r), "assigned", "arrived", "arrived_at"); err != nil {
		writeErr(w, http.StatusConflict, "bad_status", "Нельзя изменить статус поездки")
		return
	}
	o := a.notifyOrder(ctx, r.PathValue("id"))
	if o != nil {
		a.sendPush(o.PassengerID, push.Message{Title: "Водитель на месте", Body: carLine(o), Data: map[string]string{"order_id": o.ID}})
	}
	writeJSON(w, http.StatusOK, o)
}

func (a *App) driverStart(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	if err := a.transition(ctx, r.PathValue("id"), userID(r), "arrived", "in_progress", "started_at"); err != nil {
		writeErr(w, http.StatusConflict, "bad_status", "Нельзя изменить статус поездки")
		return
	}
	writeJSON(w, http.StatusOK, a.notifyOrder(ctx, r.PathValue("id")))
}

func (a *App) driverComplete(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	o, err := a.complete(ctx, r.PathValue("id"), userID(r))
	if err != nil {
		writeErr(w, http.StatusConflict, "bad_status", "Нельзя завершить поездку")
		return
	}
	writeJSON(w, http.StatusOK, o)
}

// complete finishes the trip: final price with waiting fee, payment, driver balance.
func (a *App) complete(ctx context.Context, orderID, driverID string) (*Order, error) {
	o, err := a.loadOrder(ctx, orderID)
	if err != nil || o.DriverID == nil || *o.DriverID != driverID || o.Status != "in_progress" {
		return nil, errConflict
	}
	t, err := a.loadTariff(ctx, o.Tariff)
	if err != nil {
		return nil, err
	}
	final := o.Price
	if o.ArrivedAt != nil && o.StartedAt != nil {
		final += pricing.WaitingFee(t, *o.ArrivedAt, *o.StartedAt)
	}
	tag, err := a.db.Exec(ctx, `UPDATE orders SET status='completed', completed_at=now(), final_price=$2 WHERE id=$1 AND status='in_progress'`, orderID, final)
	if err != nil || tag.RowsAffected() == 0 {
		return nil, errConflict
	}
	a.releaseDriver(ctx, driverID)
	if o.PaymentMethod == "card" && o.paymentRef != "" {
		err := a.pay.Capture(ctx, o.paymentRef, final)
		a.setPaymentStatus(ctx, orderID, "paid", err)
	} else {
		a.setPaymentStatus(ctx, orderID, "cash", nil)
	}
	a.creditDriver(ctx, driverID, orderID, o.PaymentMethod, final, pricing.Commission(t, final))
	done := a.notifyOrder(ctx, orderID)
	a.sendPush(o.PassengerID, push.Message{Title: "Поездка завершена", Body: fmt.Sprintf("К оплате %d ₸. Оцените поездку", final), Data: map[string]string{"order_id": orderID}})
	return done, nil
}

// driverCancel: the driver drops the trip before pickup; the order goes back to search.
func (a *App) driverCancel(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	orderID, driverID := r.PathValue("id"), userID(r)
	tag, err := a.db.Exec(ctx, `UPDATE orders SET status='searching', driver_id=NULL, assigned_at=NULL, arrived_at=NULL
		WHERE id=$1 AND driver_id=$2 AND status IN ('assigned','arrived')`, orderID, driverID)
	if err != nil || tag.RowsAffected() == 0 {
		writeErr(w, http.StatusConflict, "bad_status", "Нельзя отменить поездку")
		return
	}
	a.releaseDriver(ctx, driverID)
	o := a.notifyOrder(ctx, orderID)
	a.hub.Publish(driverID, "order.updated", o)
	if o != nil {
		a.sendPush(o.PassengerID, push.Message{Title: "Ищем другого водителя", Body: "Водитель не сможет приехать", Data: map[string]string{"order_id": orderID}})
	}
	go a.dispatch(orderID)
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (a *App) ratePassenger(w http.ResponseWriter, r *http.Request) {
	a.rate(w, r, "driver_id", "passenger_id", "passenger_rating")
}

func (a *App) earnings(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id := userID(r)
	type period struct {
		Trips    int `json:"trips"`
		Earned   int `json:"earned"`
		Cash     int `json:"cash"`
		Card     int `json:"card"`
		Tips     int `json:"tips"`
		Commiss  int `json:"commission"`
	}
	load := func(since time.Time) (period, error) {
		var p period
		err := a.db.QueryRow(ctx, `
			SELECT count(*),
			       COALESCE(sum(final_price + tip), 0),
			       COALESCE(sum(final_price) FILTER (WHERE payment_method='cash'), 0),
			       COALESCE(sum(final_price) FILTER (WHERE payment_method='card'), 0),
			       COALESCE(sum(tip), 0)
			FROM orders WHERE driver_id=$1 AND status='completed' AND completed_at >= $2`, id, since).
			Scan(&p.Trips, &p.Earned, &p.Cash, &p.Card, &p.Tips)
		if err != nil {
			return p, err
		}
		err = a.db.QueryRow(ctx, `SELECT COALESCE(-sum(amount),0) FROM driver_transactions WHERE driver_id=$1 AND kind='commission' AND created_at >= $2`, id, since).Scan(&p.Commiss)
		p.Earned -= p.Commiss
		return p, err
	}
	now := time.Now()
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	weekStart := today.AddDate(0, 0, -((int(today.Weekday()) + 6) % 7))
	d, err := load(today)
	if err != nil {
		a.internal(w, err)
		return
	}
	wk, err := load(weekStart)
	if err != nil {
		a.internal(w, err)
		return
	}
	var balance int64
	_ = a.db.QueryRow(ctx, `SELECT balance FROM drivers WHERE user_id=$1`, id).Scan(&balance)
	writeJSON(w, http.StatusOK, map[string]any{"today": d, "week": wk, "balance": balance, "currency": a.cfg.Currency})
}

// demandMap returns recent order density in ~1 km cells, for the driver's demand heat map.
func (a *App) demandMap(w http.ResponseWriter, r *http.Request) {
	rows, err := a.db.Query(r.Context(), `
		SELECT round(from_lat::numeric, 2)::float8 AS lat, round(from_lng::numeric, 2)::float8 AS lng, count(*)
		FROM orders WHERE created_at > now() - interval '30 minutes'
		GROUP BY 1, 2 HAVING count(*) >= 2 ORDER BY 3 DESC LIMIT 50`)
	if err != nil {
		a.internal(w, err)
		return
	}
	defer rows.Close()
	type cell struct {
		Lat    float64 `json:"lat"`
		Lng    float64 `json:"lng"`
		Orders int     `json:"orders"`
		Level  int     `json:"level"`
	}
	out := []cell{}
	for rows.Next() {
		var c cell
		if err := rows.Scan(&c.Lat, &c.Lng, &c.Orders); err != nil {
			a.internal(w, err)
			return
		}
		c.Level = int(math.Min(3, float64(c.Orders)/3+1))
		out = append(out, c)
	}
	writeJSON(w, http.StatusOK, out)
}
