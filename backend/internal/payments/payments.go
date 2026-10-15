// Package payments wraps card acquiring behind a provider interface.
package payments

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"sync"
)

// Provider is implemented by an acquiring bank integration (Kaspi Pay,
// Halyk ePay, CloudPayments, Stripe…). Card data never reaches our servers:
// the app tokenizes the card on the provider's page and we store the token.
type Provider interface {
	// Hold reserves amount on the card and returns the provider's hold reference.
	Hold(ctx context.Context, cardToken string, amount int, currency, orderID string) (string, error)
	// Capture charges amount (≤ the held amount) from an earlier hold.
	Capture(ctx context.Context, holdRef string, amount int) error
	// Void releases a hold without charging.
	Void(ctx context.Context, holdRef string) error
}

var ErrDeclined = errors.New("payment declined")

// FakeProvider approves every operation except cards whose token is "decline".
// Development and reviewer demo only.
type FakeProvider struct {
	mu    sync.Mutex
	holds map[string]int
}

func NewFake() *FakeProvider { return &FakeProvider{holds: map[string]int{}} }

func (f *FakeProvider) Hold(_ context.Context, cardToken string, amount int, _ string, _ string) (string, error) {
	if cardToken == "decline" {
		return "", ErrDeclined
	}
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	ref := "hold_" + hex.EncodeToString(b)
	f.mu.Lock()
	f.holds[ref] = amount
	f.mu.Unlock()
	return ref, nil
}

func (f *FakeProvider) Capture(_ context.Context, ref string, amount int) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if _, ok := f.holds[ref]; !ok {
		return errors.New("unknown hold")
	}
	delete(f.holds, ref)
	return nil
}

func (f *FakeProvider) Void(_ context.Context, ref string) error {
	f.mu.Lock()
	delete(f.holds, ref)
	f.mu.Unlock()
	return nil
}

// HoldAmount is how much to reserve for a quoted price: 20% above, to cover
// waiting and route changes.
func HoldAmount(price int) int { return price * 12 / 10 }
