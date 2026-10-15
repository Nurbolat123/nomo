// Package app holds the HTTP API: routes, handlers, dispatch and demo mode.
package app

import (
	"bufio"
	"context"
	"net"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/nomo-taxi/nomo/backend/internal/auth"
	"github.com/nomo-taxi/nomo/backend/internal/config"
	"github.com/nomo-taxi/nomo/backend/internal/payments"
	"github.com/nomo-taxi/nomo/backend/internal/push"
	"github.com/nomo-taxi/nomo/backend/internal/realtime"
	"github.com/nomo-taxi/nomo/backend/internal/sms"
)

type App struct {
	cfg    config.Config
	db     *pgxpool.Pool
	rdb    *redis.Client
	hub    *realtime.Hub
	tokens *auth.Issuer
	sms    sms.Sender
	push   push.Sender
	pay    payments.Provider
	calls  CallProvider

	// ctx lives as long as the server; background work (dispatch, demo bot) uses it.
	ctx context.Context
}

type Deps struct {
	Config   config.Config
	DB       *pgxpool.Pool
	Redis    *redis.Client
	SMS      sms.Sender
	Push     push.Sender
	Payments payments.Provider
	Calls    CallProvider
}

func New(ctx context.Context, d Deps) *App {
	if d.Calls == nil {
		d.Calls = DirectCalls{}
	}
	return &App{
		cfg:    d.Config,
		db:     d.DB,
		rdb:    d.Redis,
		hub:    realtime.NewHub(),
		tokens: auth.NewIssuer(d.Config.JWTSecret, d.Config.AccessTTL, d.Config.RefreshTTL),
		sms:    d.SMS,
		push:   d.Push,
		pay:    d.Payments,
		calls:  d.Calls,
		ctx:    ctx,
	}
}

// Handler returns the API router.
func (a *App) Handler() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// Auth
	mux.HandleFunc("POST /v1/auth/request-code", a.requestCode)
	mux.HandleFunc("POST /v1/auth/verify", a.verifyCode)
	mux.HandleFunc("POST /v1/auth/refresh", a.refresh)
	mux.HandleFunc("POST /v1/admin/login", a.adminLogin)

	// Any signed-in user
	user := func(h http.HandlerFunc) http.Handler { return a.requireRole(h, auth.RolePassenger, auth.RoleDriver) }
	mux.Handle("GET /v1/me", user(a.getMe))
	mux.Handle("PATCH /v1/me", user(a.updateMe))
	mux.Handle("DELETE /v1/me", user(a.deleteMe))
	mux.Handle("POST /v1/push-tokens", user(a.savePushToken))
	mux.Handle("GET /v1/tariffs", user(a.listTariffs))
	mux.Handle("GET /v1/orders/{id}", user(a.getOrder))
	mux.Handle("GET /v1/orders/{id}/messages", user(a.listMessages))
	mux.Handle("POST /v1/orders/{id}/messages", user(a.sendMessage))
	mux.Handle("GET /v1/orders/{id}/call", user(a.callCounterpart))
	mux.Handle("GET /v1/ws", user(a.websocket))

	// Passenger
	pas := func(h http.HandlerFunc) http.Handler { return a.requireRole(h, auth.RolePassenger) }
	mux.Handle("POST /v1/quotes", pas(a.quote))
	mux.Handle("GET /v1/drivers/nearby", pas(a.nearbyDrivers))
	mux.Handle("POST /v1/orders", pas(a.createOrder))
	mux.Handle("GET /v1/orders", pas(a.listPassengerOrders))
	mux.Handle("GET /v1/orders/active", pas(a.activePassengerOrder))
	mux.Handle("POST /v1/orders/{id}/cancel", pas(a.cancelOrder))
	mux.Handle("POST /v1/orders/{id}/rate", pas(a.rateDriver))
	mux.Handle("POST /v1/orders/{id}/tip", pas(a.addTip))
	mux.Handle("GET /v1/payment-methods", pas(a.listPaymentMethods))
	mux.Handle("POST /v1/payment-methods", pas(a.addPaymentMethod))
	mux.Handle("DELETE /v1/payment-methods/{id}", pas(a.deletePaymentMethod))
	mux.Handle("GET /v1/places", pas(a.listPlaces))
	mux.Handle("POST /v1/places", pas(a.addPlace))
	mux.Handle("DELETE /v1/places/{id}", pas(a.deletePlace))

	// Driver
	drv := func(h http.HandlerFunc) http.Handler { return a.requireRole(h, auth.RoleDriver) }
	mux.Handle("GET /v1/driver/profile", drv(a.driverProfile))
	mux.Handle("PUT /v1/driver/car", drv(a.updateCar))
	mux.Handle("POST /v1/driver/documents", drv(a.uploadDocument))
	mux.Handle("POST /v1/driver/submit", drv(a.submitForReview))
	mux.Handle("POST /v1/driver/online", drv(a.setOnline))
	mux.Handle("POST /v1/driver/location", drv(a.driverLocationHTTP))
	mux.Handle("GET /v1/driver/offer", drv(a.currentOffer))
	mux.Handle("POST /v1/driver/offers/{id}/accept", drv(a.acceptOffer))
	mux.Handle("POST /v1/driver/offers/{id}/decline", drv(a.declineOffer))
	mux.Handle("GET /v1/driver/orders/active", drv(a.activeDriverOrder))
	mux.Handle("GET /v1/driver/orders", drv(a.listDriverOrders))
	mux.Handle("POST /v1/driver/orders/{id}/arrived", drv(a.driverArrived))
	mux.Handle("POST /v1/driver/orders/{id}/start", drv(a.driverStart))
	mux.Handle("POST /v1/driver/orders/{id}/complete", drv(a.driverComplete))
	mux.Handle("POST /v1/driver/orders/{id}/cancel", drv(a.driverCancel))
	mux.Handle("POST /v1/driver/orders/{id}/rate", drv(a.ratePassenger))
	mux.Handle("GET /v1/driver/earnings", drv(a.earnings))
	mux.Handle("GET /v1/driver/demand", drv(a.demandMap))

	// Admin
	adm := func(h http.HandlerFunc) http.Handler { return a.requireRole(h, auth.RoleAdmin) }
	mux.Handle("GET /v1/admin/live", adm(a.adminLive))
	mux.Handle("GET /v1/admin/stats", adm(a.adminStats))
	mux.Handle("GET /v1/admin/drivers", adm(a.adminDrivers))
	mux.Handle("GET /v1/admin/drivers/{id}", adm(a.adminDriver))
	mux.Handle("POST /v1/admin/drivers/{id}/status", adm(a.adminSetDriverStatus))
	mux.Handle("GET /v1/admin/files/{path...}", adm(a.adminFile))
	mux.Handle("GET /v1/admin/tariffs", adm(a.adminTariffs))
	mux.Handle("PUT /v1/admin/tariffs/{code}", adm(a.adminUpdateTariff))
	mux.Handle("GET /v1/admin/orders", adm(a.adminOrders))
	mux.Handle("POST /v1/admin/orders/{id}/cancel", adm(a.adminCancelOrder))

	// Public account-deletion page required by Google Play.
	mux.HandleFunc("GET /delete-account", a.deleteAccountPage)

	return withCORS(withRecover(withLog(mux)))
}

// ---- auth middleware ----

type ctxKey int

const (
	ctxUserID ctxKey = iota
	ctxRole
)

func (a *App) requireRole(h http.HandlerFunc, roles ...string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tok := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if tok == "" {
			tok = r.URL.Query().Get("token") // WebSocket clients
		}
		c, err := a.tokens.Parse(tok, "access")
		if err != nil {
			writeErr(w, http.StatusUnauthorized, "unauthorized", "Войдите заново")
			return
		}
		ok := false
		for _, role := range roles {
			if c.Role == role {
				ok = true
			}
		}
		if !ok {
			writeErr(w, http.StatusForbidden, "forbidden", "Нет доступа")
			return
		}
		ctx := context.WithValue(r.Context(), ctxUserID, c.Subject)
		ctx = context.WithValue(ctx, ctxRole, c.Role)
		h(w, r.WithContext(ctx))
	})
}

func userID(r *http.Request) string { s, _ := r.Context().Value(ctxUserID).(string); return s }
func role(r *http.Request) string   { s, _ := r.Context().Value(ctxRole).(string); return s }

// ---- helpers ----

type apiError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeErr(w http.ResponseWriter, status int, code, msg string) {
	writeJSON(w, status, map[string]apiError{"error": {Code: code, Message: msg}})
}

func readJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20)
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(v); err != nil {
		writeErr(w, http.StatusBadRequest, "bad_request", "Некорректный запрос")
		return false
	}
	return true
}

func (a *App) internal(w http.ResponseWriter, err error) {
	slog.Error("internal error", "err", err)
	writeErr(w, http.StatusInternalServerError, "internal", "Что-то пошло не так, попробуйте ещё раз")
}

func isNoRows(err error) bool { return errors.Is(err, pgx.ErrNoRows) }

func withLog(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: 200}
		h.ServeHTTP(sw, r)
		if r.URL.Path != "/health" {
			slog.Info("http", "method", r.Method, "path", r.URL.Path, "status", sw.status, "ms", time.Since(start).Milliseconds())
		}
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (s *statusWriter) WriteHeader(code int) { s.status = code; s.ResponseWriter.WriteHeader(code) }

// Unwrap lets http.ResponseController reach the underlying writer.
func (s *statusWriter) Unwrap() http.ResponseWriter { return s.ResponseWriter }

// Hijack is needed for WebSocket upgrades.
func (s *statusWriter) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	hj, ok := s.ResponseWriter.(http.Hijacker)
	if !ok {
		return nil, nil, errors.New("hijack not supported")
	}
	s.status = http.StatusSwitchingProtocols
	return hj.Hijack()
}

func withRecover(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if v := recover(); v != nil {
				slog.Error("panic", "value", v, "path", r.URL.Path)
				writeErr(w, http.StatusInternalServerError, "internal", "Что-то пошло не так")
			}
		}()
		h.ServeHTTP(w, r)
	})
}

func withCORS(h http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		h.ServeHTTP(w, r)
	})
}
