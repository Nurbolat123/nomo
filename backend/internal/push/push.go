// Package push sends mobile push notifications via Firebase Cloud Messaging.
package push

import (
	"bytes"
	"context"
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type Message struct {
	Title string
	Body  string
	Data  map[string]string
}

type Sender interface {
	Send(ctx context.Context, token string, m Message) error
}

// LogSender only logs. Used when FCM credentials are not configured.
type LogSender struct{}

func (LogSender) Send(_ context.Context, token string, m Message) error {
	slog.Info("push (log only)", "token", short(token), "title", m.Title, "body", m.Body)
	return nil
}

// FCM sends through the FCM HTTP v1 API using a service account.
type FCM struct {
	projectID string
	email     string
	key       any
	tokenURI  string
	client    *http.Client

	mu     sync.Mutex
	access string
	expiry time.Time
}

type serviceAccount struct {
	ClientEmail string `json:"client_email"`
	PrivateKey  string `json:"private_key"`
	TokenURI    string `json:"token_uri"`
}

// NewFCM builds a sender from the service-account JSON downloaded from the Firebase console.
func NewFCM(projectID, serviceAccountJSON string) (*FCM, error) {
	var sa serviceAccount
	if err := json.Unmarshal([]byte(serviceAccountJSON), &sa); err != nil {
		return nil, fmt.Errorf("service account json: %w", err)
	}
	block, _ := pem.Decode([]byte(sa.PrivateKey))
	if block == nil {
		return nil, errors.New("service account: no private key")
	}
	key, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	if sa.TokenURI == "" {
		sa.TokenURI = "https://oauth2.googleapis.com/token"
	}
	return &FCM{projectID: projectID, email: sa.ClientEmail, key: key, tokenURI: sa.TokenURI, client: &http.Client{Timeout: 10 * time.Second}}, nil
}

func (f *FCM) accessToken(ctx context.Context) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.access != "" && time.Until(f.expiry) > time.Minute {
		return f.access, nil
	}
	now := time.Now()
	assertion, err := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss":   f.email,
		"scope": "https://www.googleapis.com/auth/firebase.messaging",
		"aud":   f.tokenURI,
		"iat":   now.Unix(),
		"exp":   now.Add(time.Hour).Unix(),
	}).SignedString(f.key)
	if err != nil {
		return "", err
	}
	form := url.Values{"grant_type": {"urn:ietf:params:oauth:grant-type:jwt-bearer"}, "assertion": {assertion}}
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, f.tokenURI, strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := f.client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	var out struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil || out.AccessToken == "" {
		return "", fmt.Errorf("fcm oauth: status %d", resp.StatusCode)
	}
	f.access = out.AccessToken
	f.expiry = now.Add(time.Duration(out.ExpiresIn) * time.Second)
	return f.access, nil
}

func (f *FCM) Send(ctx context.Context, token string, m Message) error {
	at, err := f.accessToken(ctx)
	if err != nil {
		return err
	}
	body, _ := json.Marshal(map[string]any{
		"message": map[string]any{
			"token":        token,
			"notification": map[string]string{"title": m.Title, "body": m.Body},
			"data":         m.Data,
			"android":      map[string]any{"priority": "high"},
			"apns":         map[string]any{"payload": map[string]any{"aps": map[string]any{"sound": "default"}}},
		},
	})
	u := fmt.Sprintf("https://fcm.googleapis.com/v1/projects/%s/messages:send", f.projectID)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+at)
	req.Header.Set("Content-Type", "application/json")
	resp, err := f.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		return fmt.Errorf("fcm send: status %d", resp.StatusCode)
	}
	return nil
}

func short(t string) string {
	if len(t) > 8 {
		return t[:8] + "…"
	}
	return t
}
