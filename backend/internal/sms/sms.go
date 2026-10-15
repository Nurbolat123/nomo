// Package sms sends one-time login codes.
package sms

import (
	"context"
	"log/slog"
)

// Sender delivers an SMS. Connect a real provider (Mobizon, SMSC.kz, Twilio…)
// by implementing this interface and wiring it in cmd/api/main.go.
type Sender interface {
	Send(ctx context.Context, phone, text string) error
}

// LogSender writes messages to the log instead of sending them. Development only.
type LogSender struct{}

func (LogSender) Send(_ context.Context, phone, text string) error {
	slog.Info("sms (log only)", "phone", phone, "text", text)
	return nil
}
