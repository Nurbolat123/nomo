package app

import (
	"crypto/rand"
	"crypto/subtle"
	"fmt"
	"math/big"
	"net/http"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/nomo-taxi/nomo/backend/internal/auth"
)

const (
	codeTTL         = 5 * time.Minute
	codeResendDelay = 60 * time.Second
	codeMaxAttempts = 5
)

// NormalizePhone turns user input into +<digits>. Kazakhstan/Russia numbers
// written as 8XXXXXXXXXX become +7XXXXXXXXXX.
func NormalizePhone(in string) (string, bool) {
	var b strings.Builder
	for _, r := range in {
		if r >= '0' && r <= '9' {
			b.WriteRune(r)
		}
	}
	d := b.String()
	if len(d) == 11 && d[0] == '8' {
		d = "7" + d[1:]
	}
	if len(d) == 10 && d[0] == '7' { // 7XXXXXXXXX without country code
		d = "7" + d
	}
	if len(d) < 10 || len(d) > 15 {
		return "", false
	}
	return "+" + d, true
}

func validRole(r string) bool { return r == auth.RolePassenger || r == auth.RoleDriver }

func (a *App) requestCode(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Phone string `json:"phone"`
		Role  string `json:"role"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	phone, ok := NormalizePhone(in.Phone)
	if !ok || !validRole(in.Role) {
		writeErr(w, http.StatusBadRequest, "invalid_phone", "Проверьте номер телефона")
		return
	}
	ctx := r.Context()
	if a.isDemoPhone(phone) {
		writeJSON(w, http.StatusOK, map[string]any{"sent": true, "resend_in": 0})
		return
	}
	set, err := a.rdb.SetNX(ctx, "otp:wait:"+phone, 1, codeResendDelay).Result()
	if err != nil {
		a.internal(w, err)
		return
	}
	if !set {
		ttl, _ := a.rdb.TTL(ctx, "otp:wait:"+phone).Result()
		writeJSON(w, http.StatusTooManyRequests, map[string]any{
			"error":     apiError{Code: "too_soon", Message: "Код уже отправлен, подождите"},
			"resend_in": int(ttl.Seconds()),
		})
		return
	}
	code, err := randomCode()
	if err != nil {
		a.internal(w, err)
		return
	}
	pipe := a.rdb.TxPipeline()
	pipe.Set(ctx, "otp:code:"+phone, code, codeTTL)
	pipe.Del(ctx, "otp:tries:"+phone)
	if _, err := pipe.Exec(ctx); err != nil {
		a.internal(w, err)
		return
	}
	if err := a.sms.Send(ctx, phone, fmt.Sprintf("Nomo: ваш код %s. Никому его не сообщайте.", code)); err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"sent": true, "resend_in": int(codeResendDelay.Seconds())})
}

func (a *App) isDemoPhone(phone string) bool {
	return a.cfg.DemoMode && (phone == a.cfg.DemoPhone || phone == a.cfg.DemoDriverPhone)
}

func randomCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(10000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%04d", n.Int64()), nil
}

func (a *App) verifyCode(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Phone string `json:"phone"`
		Code  string `json:"code"`
		Role  string `json:"role"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	phone, ok := NormalizePhone(in.Phone)
	if !ok || !validRole(in.Role) {
		writeErr(w, http.StatusBadRequest, "invalid_phone", "Проверьте номер телефона")
		return
	}
	ctx := r.Context()
	valid := false
	if a.isDemoPhone(phone) {
		valid = subtle.ConstantTimeCompare([]byte(in.Code), []byte(a.cfg.DemoCode)) == 1
	} else {
		tries, _ := a.rdb.Incr(ctx, "otp:tries:"+phone).Result()
		a.rdb.Expire(ctx, "otp:tries:"+phone, codeTTL)
		if tries > codeMaxAttempts {
			writeErr(w, http.StatusTooManyRequests, "too_many_attempts", "Слишком много попыток, запросите новый код")
			return
		}
		stored, err := a.rdb.Get(ctx, "otp:code:"+phone).Result()
		if err != nil && err != redis.Nil {
			a.internal(w, err)
			return
		}
		valid = stored != "" && subtle.ConstantTimeCompare([]byte(in.Code), []byte(stored)) == 1
		if valid {
			a.rdb.Del(ctx, "otp:code:"+phone, "otp:tries:"+phone)
		}
	}
	if !valid {
		writeErr(w, http.StatusUnauthorized, "wrong_code", "Неверный код")
		return
	}

	id, isNew, err := a.upsertUser(r, phone, in.Role)
	if err != nil {
		a.internal(w, err)
		return
	}
	toks, err := a.tokens.Issue(id, in.Role)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tokens": toks, "user_id": id, "is_new": isNew})
}

func (a *App) upsertUser(r *http.Request, phone, role string) (string, bool, error) {
	ctx := r.Context()
	var id string
	var inserted bool
	err := a.db.QueryRow(ctx, `
		INSERT INTO users (phone, role) VALUES ($1, $2)
		ON CONFLICT (phone, role) DO UPDATE SET phone = EXCLUDED.phone
		RETURNING id, (xmax = 0)`, phone, role).Scan(&id, &inserted)
	if err != nil {
		return "", false, err
	}
	if role == auth.RoleDriver {
		if _, err := a.db.Exec(ctx, `INSERT INTO drivers (user_id) VALUES ($1) ON CONFLICT DO NOTHING`, id); err != nil {
			return "", false, err
		}
	}
	return id, inserted, nil
}

func (a *App) refresh(w http.ResponseWriter, r *http.Request) {
	var in struct {
		RefreshToken string `json:"refresh_token"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	c, err := a.tokens.Parse(in.RefreshToken, "refresh")
	if err != nil {
		writeErr(w, http.StatusUnauthorized, "unauthorized", "Войдите заново")
		return
	}
	if c.Role != auth.RoleAdmin {
		var deleted bool
		err := a.db.QueryRow(r.Context(), `SELECT deleted_at IS NOT NULL FROM users WHERE id=$1`, c.Subject).Scan(&deleted)
		if err != nil || deleted {
			writeErr(w, http.StatusUnauthorized, "unauthorized", "Войдите заново")
			return
		}
	}
	toks, err := a.tokens.Issue(c.Subject, c.Role)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tokens": toks})
}

func (a *App) adminLogin(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Email    string `json:"email"`
		Password string `json:"password"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	okEmail := subtle.ConstantTimeCompare([]byte(strings.ToLower(in.Email)), []byte(strings.ToLower(a.cfg.AdminEmail))) == 1
	okPass := subtle.ConstantTimeCompare([]byte(in.Password), []byte(a.cfg.AdminPassword)) == 1
	if !okEmail || !okPass {
		time.Sleep(500 * time.Millisecond)
		writeErr(w, http.StatusUnauthorized, "wrong_credentials", "Неверный email или пароль")
		return
	}
	toks, err := a.tokens.Issue("admin", auth.RoleAdmin)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tokens": toks})
}
