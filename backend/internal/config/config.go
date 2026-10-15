// Package config reads service settings from environment variables.
package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	Addr        string
	DatabaseURL string
	RedisAddr   string
	JWTSecret   string
	UploadDir   string
	PublicURL   string

	AccessTTL  time.Duration
	RefreshTTL time.Duration

	AdminEmail    string
	AdminPassword string

	// Demo mode for App Store / Google Play reviewers.
	DemoMode        bool
	DemoPhone       string
	DemoCode        string
	DemoDriverPhone string

	// Dispatch tuning.
	OfferTimeout  time.Duration
	SearchTimeout time.Duration
	SearchRadiiKm []float64

	// Push (Firebase Cloud Messaging HTTP v1). Empty = log only.
	FCMProjectID          string
	FCMServiceAccountJSON string

	Currency string
}

func Load() Config {
	return Config{
		Addr:                  env("ADDR", ":8080"),
		DatabaseURL:           env("DATABASE_URL", "postgres://nomo:nomo@localhost:5432/nomo?sslmode=disable"),
		RedisAddr:             env("REDIS_ADDR", "localhost:6379"),
		JWTSecret:             env("JWT_SECRET", "dev-secret-change-me"),
		UploadDir:             env("UPLOAD_DIR", "./uploads"),
		PublicURL:             env("PUBLIC_URL", "http://localhost:8080"),
		AccessTTL:             dur("ACCESS_TTL", 30*time.Minute),
		RefreshTTL:            dur("REFRESH_TTL", 30*24*time.Hour),
		AdminEmail:            env("ADMIN_EMAIL", "admin@nomo.local"),
		AdminPassword:         env("ADMIN_PASSWORD", "admin"),
		DemoMode:              env("DEMO_MODE", "true") == "true",
		DemoPhone:             env("DEMO_PHONE", "+77000000000"),
		DemoCode:              env("DEMO_CODE", "0000"),
		DemoDriverPhone:       env("DEMO_DRIVER_PHONE", "+77000000001"),
		OfferTimeout:          dur("OFFER_TIMEOUT", 15*time.Second),
		SearchTimeout:         dur("SEARCH_TIMEOUT", 3*time.Minute),
		SearchRadiiKm:         []float64{2, 4, 7},
		FCMProjectID:          env("FCM_PROJECT_ID", ""),
		FCMServiceAccountJSON: env("FCM_SERVICE_ACCOUNT_JSON", ""),
		Currency:              env("CURRENCY", "KZT"),
	}
}

func env(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func dur(k string, def time.Duration) time.Duration {
	v := os.Getenv(k)
	if v == "" {
		return def
	}
	if d, err := time.ParseDuration(v); err == nil {
		return d
	}
	if n, err := strconv.Atoi(v); err == nil {
		return time.Duration(n) * time.Second
	}
	return def
}
