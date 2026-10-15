// Command api runs the Nomo HTTP + WebSocket API.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/nomo-taxi/nomo/backend/internal/app"
	"github.com/nomo-taxi/nomo/backend/internal/config"
	"github.com/nomo-taxi/nomo/backend/internal/db"
	"github.com/nomo-taxi/nomo/backend/internal/payments"
	"github.com/nomo-taxi/nomo/backend/internal/push"
	"github.com/nomo-taxi/nomo/backend/internal/sms"
)

func main() {
	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	cfg := config.Load()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pool, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("database", "err", err)
		os.Exit(1)
	}
	defer pool.Close()
	if err := db.Migrate(ctx, pool); err != nil {
		slog.Error("migrate", "err", err)
		os.Exit(1)
	}

	rdb := redis.NewClient(&redis.Options{Addr: cfg.RedisAddr})
	if err := rdb.Ping(ctx).Err(); err != nil {
		slog.Error("redis", "err", err)
		os.Exit(1)
	}

	var pusher push.Sender = push.LogSender{}
	if cfg.FCMProjectID != "" && cfg.FCMServiceAccountJSON != "" {
		f, err := push.NewFCM(cfg.FCMProjectID, cfg.FCMServiceAccountJSON)
		if err != nil {
			slog.Error("fcm", "err", err)
			os.Exit(1)
		}
		pusher = f
	}

	if cfg.JWTSecret == "dev-secret-change-me" || cfg.AdminPassword == "admin" {
		slog.Warn("using development secrets: set JWT_SECRET and ADMIN_PASSWORD before going live")
	}

	a := app.New(ctx, app.Deps{
		Config:   cfg,
		DB:       pool,
		Redis:    rdb,
		SMS:      sms.LogSender{}, // TODO: real SMS provider before launch
		Push:     pusher,
		Payments: payments.NewFake(), // TODO: real acquiring before launch
	})

	srv := &http.Server{Addr: cfg.Addr, Handler: a.Handler(), ReadHeaderTimeout: 10 * time.Second}
	go func() {
		slog.Info("listening", "addr", cfg.Addr)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server", "err", err)
			stop()
		}
	}()
	<-ctx.Done()
	shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdown)
}
