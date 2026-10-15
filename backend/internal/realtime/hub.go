// Package realtime delivers live events to connected apps over WebSocket.
//
// The hub is in-process: run one API instance, or replace Publish with
// Redis pub/sub before scaling horizontally.
package realtime

import (
	"encoding/json"
	"sync"
)

type Event struct {
	Type string `json:"type"`
	Data any    `json:"data"`
}

type client struct {
	send chan []byte
}

type Hub struct {
	mu      sync.RWMutex
	clients map[string]map[*client]struct{}
}

func NewHub() *Hub { return &Hub{clients: map[string]map[*client]struct{}{}} }

// Subscribe registers a connection for userID. Call the returned cancel func on disconnect.
func (h *Hub) Subscribe(userID string) (<-chan []byte, func()) {
	c := &client{send: make(chan []byte, 64)}
	h.mu.Lock()
	if h.clients[userID] == nil {
		h.clients[userID] = map[*client]struct{}{}
	}
	h.clients[userID][c] = struct{}{}
	h.mu.Unlock()
	return c.send, func() {
		h.mu.Lock()
		if set := h.clients[userID]; set != nil {
			if _, ok := set[c]; ok {
				delete(set, c)
				close(c.send)
			}
			if len(set) == 0 {
				delete(h.clients, userID)
			}
		}
		h.mu.Unlock()
	}
}

// Publish sends an event to every connection of userID. Slow clients drop events.
func (h *Hub) Publish(userID string, typ string, data any) {
	b, err := json.Marshal(Event{Type: typ, Data: data})
	if err != nil {
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.clients[userID] {
		select {
		case c.send <- b:
		default:
		}
	}
}

// Online reports whether userID has at least one open connection.
func (h *Hub) Online(userID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients[userID]) > 0
}
