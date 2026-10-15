package app

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/nomo-taxi/nomo/backend/internal/config"
	"github.com/nomo-taxi/nomo/backend/internal/db"
	"github.com/nomo-taxi/nomo/backend/internal/payments"
	"github.com/nomo-taxi/nomo/backend/internal/push"
	"github.com/nomo-taxi/nomo/backend/internal/sms"
)

// Integration tests need Postgres and Redis:
//   TEST_DATABASE_URL=postgres://nomo:nomo@localhost:5432/nomo_test?sslmode=disable
//   TEST_REDIS_ADDR=localhost:6379 (database 15 is flushed)

type env struct {
	t   *testing.T
	srv *httptest.Server
	rdb *redis.Client
}

func setup(t *testing.T, mutate func(*config.Config)) *env {
	t.Helper()
	dbURL := os.Getenv("TEST_DATABASE_URL")
	if dbURL == "" {
		t.Skip("TEST_DATABASE_URL not set")
	}
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	if _, err := pool.Exec(ctx, `DROP SCHEMA public CASCADE; CREATE SCHEMA public;`); err != nil {
		t.Fatal(err)
	}
	if err := db.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	addr := os.Getenv("TEST_REDIS_ADDR")
	if addr == "" {
		addr = "localhost:6379"
	}
	rdb := redis.NewClient(&redis.Options{Addr: addr, DB: 15})
	rdb.FlushDB(ctx)

	cfg := config.Load()
	cfg.UploadDir = t.TempDir()
	cfg.OfferTimeout = 3 * time.Second
	cfg.SearchTimeout = 20 * time.Second
	cfg.DemoMode = false
	if mutate != nil {
		mutate(&cfg)
	}
	a := New(ctx, Deps{Config: cfg, DB: pool, Redis: rdb, SMS: sms.LogSender{}, Push: push.LogSender{}, Payments: payments.NewFake()})
	srv := httptest.NewServer(a.Handler())
	t.Cleanup(srv.Close)
	return &env{t: t, srv: srv, rdb: rdb}
}

func (e *env) do(method, path, token string, body any, want int) map[string]any {
	e.t.Helper()
	var rd io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rd = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, e.srv.URL+path, rd)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		e.t.Fatal(err)
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != want {
		e.t.Fatalf("%s %s: status %d, want %d: %s", method, path, resp.StatusCode, want, raw)
	}
	var out map[string]any
	_ = json.Unmarshal(raw, &out)
	return out
}

func (e *env) login(phone, role string) string {
	e.t.Helper()
	e.do("POST", "/v1/auth/request-code", "", map[string]string{"phone": phone, "role": role}, 200)
	norm, _ := NormalizePhone(phone)
	code, err := e.rdb.Get(context.Background(), "otp:code:"+norm).Result()
	if err != nil {
		e.t.Fatal("no code stored: ", err)
	}
	e.do("POST", "/v1/auth/verify", "", map[string]string{"phone": phone, "role": role, "code": "9999x"}, 401)
	out := e.do("POST", "/v1/auth/verify", "", map[string]string{"phone": phone, "role": role, "code": code}, 200)
	return out["tokens"].(map[string]any)["access_token"].(string)
}

func (e *env) upload(token, kind string) {
	e.t.Helper()
	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	_ = mw.WriteField("kind", kind)
	fw, _ := mw.CreateFormFile("file", kind+".png")
	fw.Write([]byte("\x89PNG\r\n\x1a\n" + strings.Repeat("0", 100)))
	mw.Close()
	req, _ := http.NewRequest("POST", e.srv.URL+"/v1/driver/documents", &buf)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	resp, err := http.DefaultClient.Do(req)
	if err != nil || resp.StatusCode != 201 {
		b, _ := io.ReadAll(resp.Body)
		e.t.Fatalf("upload %s: %v %d %s", kind, err, resp.StatusCode, b)
	}
	resp.Body.Close()
}

const (
	pickLat, pickLng = 51.2333, 51.3667 // Uralsk (Oral)
	destLat, destLng = 51.2050, 51.3900
)

// onboardDriver registers, verifies and puts a driver online next to the pickup point.
func (e *env) onboardDriver(phone string) (string, string) {
	tok := e.login(phone, "driver")
	e.do("POST", "/v1/driver/online", tok, map[string]any{"online": true, "lat": pickLat, "lng": pickLng}, 403)
	e.do("PUT", "/v1/driver/car", tok, map[string]any{"name": "Ерлан", "car_make": "Toyota", "car_model": "Camry", "car_color": "Белая", "car_plate": "123 abc 07", "car_year": 2020}, 200)
	e.do("POST", "/v1/driver/submit", tok, nil, 400) // documents missing
	for _, k := range requiredDocs {
		e.upload(tok, k)
	}
	p := e.do("POST", "/v1/driver/submit", tok, nil, 200)
	if p["status"] != "pending" {
		e.t.Fatalf("status after submit = %v", p["status"])
	}
	admin := e.do("POST", "/v1/admin/login", "", map[string]string{"email": "admin@nomo.local", "password": "admin"}, 200)["tokens"].(map[string]any)["access_token"].(string)
	id := p["id"].(string)
	e.do("POST", "/v1/admin/drivers/"+id+"/status", admin, map[string]any{"status": "approved"}, 200)
	e.do("POST", "/v1/driver/online", tok, map[string]any{"online": true, "lat": pickLat + 0.004, "lng": pickLng + 0.003}, 200)
	return tok, admin
}

func TestFullRide(t *testing.T) {
	e := setup(t, nil)
	driver, admin := e.onboardDriver("8 701 111 22 33")
	pas := e.login("+7 702 444 55 66", "passenger")
	e.do("PATCH", "/v1/me", pas, map[string]any{"name": "Айгерим"}, 200)

	// Live updates over WebSocket.
	wsURL := "ws" + strings.TrimPrefix(e.srv.URL, "http") + "/v1/ws?token=" + pas
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	conn, _, err := websocket.Dial(ctx, wsURL, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.CloseNow()

	trip := map[string]any{
		"from": map[string]any{"lat": pickLat, "lng": pickLng, "addr": "пр. Достык, 1"},
		"to":   map[string]any{"lat": destLat, "lng": destLng, "addr": "Аэропорт"},
	}
	var quotes []map[string]any
	req, _ := http.NewRequest("POST", e.srv.URL+"/v1/quotes", bytes.NewReader(mustJSON(trip)))
	req.Header.Set("Authorization", "Bearer "+pas)
	resp, _ := http.DefaultClient.Do(req)
	_ = json.NewDecoder(resp.Body).Decode(&quotes)
	resp.Body.Close()
	if len(quotes) != 3 || quotes[0]["eta_s"] == nil {
		t.Fatalf("quotes = %v", quotes)
	}
	price := int(quotes[0]["price"].(float64))

	card := e.do("POST", "/v1/payment-methods", pas, map[string]any{"token": "tok_test", "brand": "visa", "last4": "4242"}, 201)
	order := map[string]any{"tariff": "economy", "payment_method": "card", "payment_method_id": card["id"], "comment": "у второго подъезда"}
	for k, v := range trip {
		order[k] = v
	}
	o := e.do("POST", "/v1/orders", pas, order, 201)
	id := o["id"].(string)
	if o["status"] != "searching" || int(o["price"].(float64)) != price {
		t.Fatalf("order = %v", o)
	}
	e.do("POST", "/v1/orders", pas, order, 409) // one active order at a time

	// The driver receives the offer and accepts.
	var offer map[string]any
	for i := 0; i < 30 && offer == nil; i++ {
		time.Sleep(200 * time.Millisecond)
		offer = e.do("GET", "/v1/driver/offer", driver, nil, 200)
	}
	if offer == nil || offer["order_id"] != id {
		t.Fatalf("offer = %v", offer)
	}
	e.do("POST", "/v1/driver/offers/"+id+"/accept", driver, nil, 200)
	e.do("POST", "/v1/driver/offers/"+id+"/accept", driver, nil, 409)

	waitEvent(t, ctx, conn, "order.updated", func(d map[string]any) bool { return d["status"] == "assigned" })
	e.do("POST", "/v1/driver/location", driver, map[string]any{"lat": pickLat + 0.001, "lng": pickLng, "heading": 180}, 200)
	waitEvent(t, ctx, conn, "driver.location", nil)

	// Chat both ways.
	e.do("POST", "/v1/orders/"+id+"/messages", pas, map[string]string{"body": "Я в белой куртке"}, 201)
	e.do("POST", "/v1/orders/"+id+"/messages", driver, map[string]string{"body": "Подъезжаю"}, 201)
	waitEvent(t, ctx, conn, "chat.message", nil)
	if call := e.do("GET", "/v1/orders/"+id+"/call", pas, nil, 200); call["phone"] != "+77011112233" {
		t.Fatalf("call = %v", call)
	}

	e.do("POST", "/v1/driver/orders/"+id+"/start", driver, nil, 409) // must arrive first
	e.do("POST", "/v1/driver/orders/"+id+"/arrived", driver, nil, 200)
	e.do("POST", "/v1/driver/orders/"+id+"/start", driver, nil, 200)
	e.do("POST", "/v1/orders/"+id+"/cancel", pas, nil, 409) // cannot cancel in progress
	done := e.do("POST", "/v1/driver/orders/"+id+"/complete", driver, nil, 200)
	if done["status"] != "completed" || done["payment_status"] != "paid" || int(done["final_price"].(float64)) != price {
		t.Fatalf("completed = %v", done)
	}

	e.do("POST", "/v1/orders/"+id+"/rate", pas, map[string]any{"rating": 4}, 200)
	e.do("POST", "/v1/orders/"+id+"/rate", pas, map[string]any{"rating": 5}, 409)
	e.do("POST", "/v1/driver/orders/"+id+"/rate", driver, map[string]any{"rating": 5}, 200)
	e.do("POST", "/v1/orders/"+id+"/tip", pas, map[string]any{"amount": 200}, 200)

	earn := e.do("GET", "/v1/driver/earnings", driver, nil, 200)
	today := earn["today"].(map[string]any)
	commission := (price*15 + 50) / 100
	if int(today["trips"].(float64)) != 1 || int(earn["balance"].(float64)) != price-commission+200 {
		t.Fatalf("earnings = %v (price %d)", earn, price)
	}
	prof := e.do("GET", "/v1/driver/profile", driver, nil, 200)
	if prof["busy"] != false || prof["rating"].(float64) != 4 {
		t.Fatalf("driver after trip = %v", prof)
	}
	stats := e.do("GET", "/v1/admin/stats", admin, nil, 200)
	if int(stats["trips"].(float64)) != 1 {
		t.Fatalf("stats = %v", stats)
	}
}

func TestCancelAndNoDrivers(t *testing.T) {
	e := setup(t, func(c *config.Config) { c.SearchTimeout = 2 * time.Second })
	pas := e.login("+77025556677", "passenger")
	order := map[string]any{
		"from": map[string]any{"lat": pickLat, "lng": pickLng}, "to": map[string]any{"lat": destLat, "lng": destLng},
		"tariff": "economy", "payment_method": "cash",
	}
	o := e.do("POST", "/v1/orders", pas, order, 201)
	c := e.do("POST", "/v1/orders/"+o["id"].(string)+"/cancel", pas, map[string]string{"reason": "передумал"}, 200)
	if c["status"] != "cancelled" || int(c["cancel_fee"].(float64)) != 0 {
		t.Fatalf("cancel = %v", c)
	}
	o = e.do("POST", "/v1/orders", pas, order, 201)
	time.Sleep(3 * time.Second)
	got := e.do("GET", "/v1/orders/"+o["id"].(string), pas, nil, 200)
	if got["status"] != "no_drivers" {
		t.Fatalf("status = %v, want no_drivers", got["status"])
	}
}

func TestDriverDeclineGoesToNext(t *testing.T) {
	e := setup(t, nil)
	d1, _ := e.onboardDriver("+77010000001")
	d2, _ := e.onboardDriver("+77010000002")
	// d2 is a bit farther away.
	e.do("POST", "/v1/driver/location", d2, map[string]any{"lat": pickLat + 0.01, "lng": pickLng + 0.01}, 200)
	pas := e.login("+77020000003", "passenger")
	o := e.do("POST", "/v1/orders", pas, map[string]any{
		"from": map[string]any{"lat": pickLat, "lng": pickLng}, "to": map[string]any{"lat": destLat, "lng": destLng},
		"tariff": "economy", "payment_method": "cash",
	}, 201)
	id := o["id"].(string)
	first := pollOffer(t, e, d1)
	if first["order_id"] != id {
		t.Fatal("nearest driver should get the offer first")
	}
	e.do("POST", "/v1/driver/offers/"+id+"/decline", d1, nil, 200)
	second := pollOffer(t, e, d2)
	if second["order_id"] != id {
		t.Fatal("second driver should get the offer after decline")
	}
	e.do("POST", "/v1/driver/offers/"+id+"/accept", d2, nil, 200)
	// Driver drops the trip; the order goes back to search and nobody is left.
	e.do("POST", "/v1/driver/orders/"+id+"/cancel", d2, nil, 200)
	got := e.do("GET", "/v1/orders/"+id, pas, nil, 200)
	if got["status"] != "searching" {
		t.Fatalf("status after driver cancel = %v", got["status"])
	}
	e.do("DELETE", "/v1/me", pas, nil, 409) // active order blocks deletion
	e.do("POST", "/v1/orders/"+id+"/cancel", pas, nil, 200)
	e.do("DELETE", "/v1/me", pas, nil, 200)
	e.do("GET", "/v1/me", pas, nil, 401)
}

func pollOffer(t *testing.T, e *env, tok string) map[string]any {
	t.Helper()
	for i := 0; i < 40; i++ {
		if off := e.do("GET", "/v1/driver/offer", tok, nil, 200); off != nil {
			return off
		}
		time.Sleep(200 * time.Millisecond)
	}
	t.Fatal("no offer")
	return nil
}

func waitEvent(t *testing.T, ctx context.Context, conn *websocket.Conn, typ string, match func(map[string]any) bool) {
	t.Helper()
	for {
		_, b, err := conn.Read(ctx)
		if err != nil {
			t.Fatalf("waiting for %s: %v", typ, err)
		}
		var ev struct {
			Type string         `json:"type"`
			Data map[string]any `json:"data"`
		}
		_ = json.Unmarshal(b, &ev)
		if ev.Type == typ && (match == nil || match(ev.Data)) {
			return
		}
	}
}

func mustJSON(v any) []byte { b, _ := json.Marshal(v); return b }

func TestNormalizePhone(t *testing.T) {
	cases := map[string]string{"8 (701) 111-22-33": "+77011112233", "+7 701 111 22 33": "+77011112233", "7011112233": "+77011112233"}
	for in, want := range cases {
		if got, ok := NormalizePhone(in); !ok || got != want {
			t.Errorf("NormalizePhone(%q) = %q, want %q", in, got, want)
		}
	}
	if _, ok := NormalizePhone("123"); ok {
		t.Error("short number accepted")
	}
	_ = fmt.Sprint()
}
