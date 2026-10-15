package app

import (
	"fmt"
	"log/slog"
	"net/http"
	"strings"

	"github.com/nomo-taxi/nomo/backend/internal/auth"
	"github.com/nomo-taxi/nomo/backend/internal/push"
)

type Me struct {
	ID     string  `json:"id"`
	Phone  string  `json:"phone"`
	Role   string  `json:"role"`
	Name   string  `json:"name"`
	Email  string  `json:"email"`
	Locale string  `json:"locale"`
	Rating float64 `json:"rating"`
}

func (a *App) getMe(w http.ResponseWriter, r *http.Request) {
	var m Me
	var sum, cnt int
	err := a.db.QueryRow(r.Context(), `SELECT id, phone, role, name, email, locale, rating_sum, rating_count FROM users WHERE id=$1 AND deleted_at IS NULL`, userID(r)).
		Scan(&m.ID, &m.Phone, &m.Role, &m.Name, &m.Email, &m.Locale, &sum, &cnt)
	if isNoRows(err) {
		writeErr(w, http.StatusUnauthorized, "unauthorized", "Войдите заново")
		return
	}
	if err != nil {
		a.internal(w, err)
		return
	}
	m.Rating = rating(sum, cnt)
	writeJSON(w, http.StatusOK, m)
}

func (a *App) updateMe(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Name   *string `json:"name"`
		Email  *string `json:"email"`
		Locale *string `json:"locale"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if in.Name != nil && len([]rune(*in.Name)) > 60 {
		writeErr(w, http.StatusBadRequest, "invalid_name", "Имя слишком длинное")
		return
	}
	if in.Locale != nil && !(*in.Locale == "ru" || *in.Locale == "kk" || *in.Locale == "en") {
		writeErr(w, http.StatusBadRequest, "invalid_locale", "Неизвестный язык")
		return
	}
	_, err := a.db.Exec(r.Context(), `
		UPDATE users SET name = COALESCE($2, name), email = COALESCE($3, email), locale = COALESCE($4, locale)
		WHERE id=$1`, userID(r), trimPtr(in.Name), trimPtr(in.Email), in.Locale)
	if err != nil {
		a.internal(w, err)
		return
	}
	a.getMe(w, r)
}

func trimPtr(s *string) *string {
	if s == nil {
		return nil
	}
	t := strings.TrimSpace(*s)
	return &t
}

// deleteMe removes the account (App Store 5.1.1(v), Google Play account deletion).
// Personal data is erased; trip records stay anonymized for accounting.
func (a *App) deleteMe(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	id := userID(r)
	var active int
	col := "passenger_id"
	if role(r) == auth.RoleDriver {
		col = "driver_id"
	}
	if err := a.db.QueryRow(ctx, fmt.Sprintf(`SELECT count(*) FROM orders WHERE %s=$1 AND status IN %s`, col, activeStatuses), id).Scan(&active); err != nil {
		a.internal(w, err)
		return
	}
	if active > 0 {
		writeErr(w, http.StatusConflict, "active_order", "Сначала завершите или отмените текущую поездку")
		return
	}
	tx, err := a.db.Begin(ctx)
	if err != nil {
		a.internal(w, err)
		return
	}
	defer tx.Rollback(ctx)
	stmts := []string{
		`UPDATE users SET phone = 'deleted:' || id::text, name = '', email = '', deleted_at = now() WHERE id=$1`,
		`UPDATE payment_methods SET deleted_at = now(), token = '' WHERE user_id=$1`,
		`DELETE FROM saved_places WHERE user_id=$1`,
		`DELETE FROM push_tokens WHERE user_id=$1`,
		`DELETE FROM driver_documents WHERE driver_id=$1`,
		`UPDATE drivers SET online=false, status='blocked', status_note='account deleted', car_plate='' WHERE user_id=$1`,
	}
	for _, s := range stmts {
		if _, err := tx.Exec(ctx, s, id); err != nil {
			a.internal(w, err)
			return
		}
	}
	if err := tx.Commit(ctx); err != nil {
		a.internal(w, err)
		return
	}
	a.rdb.ZRem(ctx, geoKey, id)
	writeJSON(w, http.StatusOK, map[string]bool{"deleted": true})
}

func (a *App) savePushToken(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Token    string `json:"token"`
		Platform string `json:"platform"`
	}
	if !readJSON(w, r, &in) || in.Token == "" {
		return
	}
	_, err := a.db.Exec(r.Context(), `
		INSERT INTO push_tokens (user_id, token, platform) VALUES ($1,$2,$3)
		ON CONFLICT (user_id, token) DO UPDATE SET updated_at = now(), platform = EXCLUDED.platform`, userID(r), in.Token, in.Platform)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// sendPush delivers a notification to every device of the user, in the background.
func (a *App) sendPush(userID string, m push.Message) {
	go func() {
		ctx := a.ctx
		rows, err := a.db.Query(ctx, `SELECT token FROM push_tokens WHERE user_id=$1`, userID)
		if err != nil {
			return
		}
		var tokens []string
		for rows.Next() {
			var t string
			if rows.Scan(&t) == nil {
				tokens = append(tokens, t)
			}
		}
		rows.Close()
		for _, t := range tokens {
			if err := a.push.Send(ctx, t, m); err != nil {
				slog.Warn("push failed", "err", err)
			}
		}
	}()
}

// ---- saved places ----

type SavedPlace struct {
	ID    string  `json:"id"`
	Label string  `json:"label"`
	Addr  string  `json:"addr"`
	Lat   float64 `json:"lat"`
	Lng   float64 `json:"lng"`
}

func (a *App) listPlaces(w http.ResponseWriter, r *http.Request) {
	rows, err := a.db.Query(r.Context(), `SELECT id, label, addr, lat, lng FROM saved_places WHERE user_id=$1 ORDER BY label`, userID(r))
	if err != nil {
		a.internal(w, err)
		return
	}
	defer rows.Close()
	out := []SavedPlace{}
	for rows.Next() {
		var p SavedPlace
		if err := rows.Scan(&p.ID, &p.Label, &p.Addr, &p.Lat, &p.Lng); err != nil {
			a.internal(w, err)
			return
		}
		out = append(out, p)
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *App) addPlace(w http.ResponseWriter, r *http.Request) {
	var p SavedPlace
	if !readJSON(w, r, &p) {
		return
	}
	if strings.TrimSpace(p.Label) == "" || !validCoord(p.Lat, p.Lng) {
		writeErr(w, http.StatusBadRequest, "invalid_place", "Укажите название и точку на карте")
		return
	}
	err := a.db.QueryRow(r.Context(), `INSERT INTO saved_places (user_id, label, addr, lat, lng) VALUES ($1,$2,$3,$4,$5) RETURNING id`,
		userID(r), strings.TrimSpace(p.Label), p.Addr, p.Lat, p.Lng).Scan(&p.ID)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, p)
}

func (a *App) deletePlace(w http.ResponseWriter, r *http.Request) {
	_, err := a.db.Exec(r.Context(), `DELETE FROM saved_places WHERE id=$1 AND user_id=$2`, r.PathValue("id"), userID(r))
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

// ---- payment methods ----

type PaymentMethod struct {
	ID    string `json:"id"`
	Brand string `json:"brand"`
	Last4 string `json:"last4"`
}

func (a *App) listPaymentMethods(w http.ResponseWriter, r *http.Request) {
	rows, err := a.db.Query(r.Context(), `SELECT id, brand, last4 FROM payment_methods WHERE user_id=$1 AND deleted_at IS NULL ORDER BY created_at`, userID(r))
	if err != nil {
		a.internal(w, err)
		return
	}
	defer rows.Close()
	out := []PaymentMethod{}
	for rows.Next() {
		var p PaymentMethod
		if err := rows.Scan(&p.ID, &p.Brand, &p.Last4); err != nil {
			a.internal(w, err)
			return
		}
		out = append(out, p)
	}
	writeJSON(w, http.StatusOK, out)
}

// addPaymentMethod stores a card token produced by the acquirer's
// tokenization page. Raw card numbers must never be sent here.
func (a *App) addPaymentMethod(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Token string `json:"token"`
		Brand string `json:"brand"`
		Last4 string `json:"last4"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	if in.Token == "" || len(in.Last4) != 4 {
		writeErr(w, http.StatusBadRequest, "invalid_card", "Не удалось привязать карту")
		return
	}
	var p PaymentMethod
	err := a.db.QueryRow(r.Context(), `INSERT INTO payment_methods (user_id, brand, last4, token) VALUES ($1,$2,$3,$4) RETURNING id, brand, last4`,
		userID(r), in.Brand, in.Last4, in.Token).Scan(&p.ID, &p.Brand, &p.Last4)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, p)
}

func (a *App) deletePaymentMethod(w http.ResponseWriter, r *http.Request) {
	_, err := a.db.Exec(r.Context(), `UPDATE payment_methods SET deleted_at=now(), token='' WHERE id=$1 AND user_id=$2`, r.PathValue("id"), userID(r))
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func validCoord(lat, lng float64) bool {
	return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 && !(lat == 0 && lng == 0)
}

// ---- account deletion web page (Google Play requirement) ----

func (a *App) deleteAccountPage(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprint(w, `<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Nomo — удаление аккаунта</title>
<style>body{font-family:system-ui,sans-serif;max-width:640px;margin:40px auto;padding:0 16px;line-height:1.5;color:#0A0A0A}h1{font-size:28px}</style></head>
<body><h1>Удаление аккаунта Nomo</h1>
<p><b>В приложении:</b> Профиль → Настройки → «Удалить аккаунт». Удаление происходит сразу.</p>
<p><b>Без приложения:</b> напишите на <a href="mailto:support@nomo.kz">support@nomo.kz</a> с номера телефона, привязанного к аккаунту, — мы удалим его в течение 7 дней.</p>
<p><b>Что удаляется:</b> имя, email, номер телефона, привязанные карты, сохранённые адреса, документы водителя.</p>
<p><b>Что хранится:</b> обезличенные записи поездок и платежей — столько, сколько требует налоговое законодательство.</p>
</body></html>`)
}
