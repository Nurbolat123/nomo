package app

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/coder/websocket"

	"github.com/nomo-taxi/nomo/backend/internal/auth"
	"github.com/nomo-taxi/nomo/backend/internal/push"
)

// websocket streams events (order.updated, offer.new, offer.cancelled,
// driver.location, chat.message) and accepts driver location updates:
// {"type":"location","lat":..,"lng":..,"heading":..}.
func (a *App) websocket(w http.ResponseWriter, r *http.Request) {
	uid, rl := userID(r), role(r)
	conn, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		return
	}
	defer conn.CloseNow()

	ctx, cancel := context.WithCancel(a.ctx)
	defer cancel()
	events, unsubscribe := a.hub.Subscribe(uid)
	defer unsubscribe()

	go func() {
		defer cancel()
		for {
			_, data, err := conn.Read(ctx)
			if err != nil {
				return
			}
			var msg struct {
				Type    string  `json:"type"`
				Lat     float64 `json:"lat"`
				Lng     float64 `json:"lng"`
				Heading float64 `json:"heading"`
			}
			if json.Unmarshal(data, &msg) != nil {
				continue
			}
			if msg.Type == "location" && rl == auth.RoleDriver {
				a.updateDriverLocation(ctx, uid, msg.Lat, msg.Lng, msg.Heading)
			}
		}
	}()

	ping := time.NewTicker(25 * time.Second)
	defer ping.Stop()
	for {
		select {
		case <-ctx.Done():
			conn.Close(websocket.StatusNormalClosure, "")
			return
		case b, ok := <-events:
			if !ok {
				return
			}
			wctx, c := context.WithTimeout(ctx, 10*time.Second)
			err := conn.Write(wctx, websocket.MessageText, b)
			c()
			if err != nil {
				return
			}
		case <-ping.C:
			pctx, c := context.WithTimeout(ctx, 10*time.Second)
			err := conn.Ping(pctx)
			c()
			if err != nil {
				return
			}
		}
	}
}

// ---- chat ----

type Message struct {
	ID        int64     `json:"id"`
	OrderID   string    `json:"order_id"`
	SenderID  string    `json:"sender_id"`
	Body      string    `json:"body"`
	CreatedAt time.Time `json:"created_at"`
}

func (a *App) listMessages(w http.ResponseWriter, r *http.Request) {
	o, err := a.loadOrder(r.Context(), r.PathValue("id"))
	if err != nil || !canSee(r, o) {
		writeErr(w, http.StatusNotFound, "not_found", "Поездка не найдена")
		return
	}
	rows, err := a.db.Query(r.Context(), `SELECT id, order_id, sender_id, body, created_at FROM messages WHERE order_id=$1 ORDER BY id`, o.ID)
	if err != nil {
		a.internal(w, err)
		return
	}
	defer rows.Close()
	out := []Message{}
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID, &m.OrderID, &m.SenderID, &m.Body, &m.CreatedAt); err != nil {
			a.internal(w, err)
			return
		}
		out = append(out, m)
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *App) sendMessage(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Body string `json:"body"`
	}
	if !readJSON(w, r, &in) {
		return
	}
	in.Body = strings.TrimSpace(in.Body)
	if in.Body == "" || len([]rune(in.Body)) > 500 {
		writeErr(w, http.StatusBadRequest, "invalid_message", "Сообщение пустое или слишком длинное")
		return
	}
	ctx := r.Context()
	o, err := a.loadOrder(ctx, r.PathValue("id"))
	if err != nil || !canSee(r, o) {
		writeErr(w, http.StatusNotFound, "not_found", "Поездка не найдена")
		return
	}
	if o.DriverID == nil || (o.Status != "assigned" && o.Status != "arrived" && o.Status != "in_progress") {
		writeErr(w, http.StatusConflict, "chat_closed", "Чат доступен только во время поездки")
		return
	}
	m := Message{OrderID: o.ID, SenderID: userID(r), Body: in.Body}
	if err := a.db.QueryRow(ctx, `INSERT INTO messages (order_id, sender_id, body) VALUES ($1,$2,$3) RETURNING id, created_at`, o.ID, m.SenderID, m.Body).Scan(&m.ID, &m.CreatedAt); err != nil {
		a.internal(w, err)
		return
	}
	other := o.PassengerID
	if other == m.SenderID {
		other = *o.DriverID
	}
	a.hub.Publish(o.PassengerID, "chat.message", m)
	a.hub.Publish(*o.DriverID, "chat.message", m)
	a.sendPush(other, push.Message{Title: "Новое сообщение", Body: m.Body, Data: map[string]string{"type": "chat", "order_id": o.ID}})
	writeJSON(w, http.StatusCreated, m)
}

// ---- calls ----

// CallProvider returns the number one side dials to reach the other.
// Replace DirectCalls with a telephony provider (Zadarma, Mango Office, Twilio
// Proxy) to hand out temporary masked numbers instead of real ones.
type CallProvider interface {
	NumberFor(ctx context.Context, orderID, callerPhone, calleePhone string) (string, error)
}

// DirectCalls returns the other person's real number. Development only.
type DirectCalls struct{}

func (DirectCalls) NumberFor(_ context.Context, _, _, callee string) (string, error) { return callee, nil }

func (a *App) callCounterpart(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	o, err := a.loadOrder(ctx, r.PathValue("id"))
	if err != nil || !canSee(r, o) || o.DriverID == nil {
		writeErr(w, http.StatusNotFound, "not_found", "Поездка не найдена")
		return
	}
	if o.Status != "assigned" && o.Status != "arrived" && o.Status != "in_progress" {
		writeErr(w, http.StatusConflict, "call_closed", "Звонок доступен только во время поездки")
		return
	}
	callee := o.PassengerID
	if callee == userID(r) {
		callee = *o.DriverID
	}
	var callerPhone, calleePhone string
	_ = a.db.QueryRow(ctx, `SELECT phone FROM users WHERE id=$1`, userID(r)).Scan(&callerPhone)
	if err := a.db.QueryRow(ctx, `SELECT phone FROM users WHERE id=$1`, callee).Scan(&calleePhone); err != nil {
		a.internal(w, err)
		return
	}
	num, err := a.calls.NumberFor(ctx, o.ID, callerPhone, calleePhone)
	if err != nil {
		a.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"phone": num})
}
