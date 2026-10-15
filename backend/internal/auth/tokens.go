// Package auth issues and checks JWT access and refresh tokens.
package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	RolePassenger = "passenger"
	RoleDriver    = "driver"
	RoleAdmin     = "admin"
)

type Claims struct {
	Role string `json:"role"`
	Kind string `json:"kind"` // "access" or "refresh"
	jwt.RegisteredClaims
}

type Issuer struct {
	secret     []byte
	accessTTL  time.Duration
	refreshTTL time.Duration
}

func NewIssuer(secret string, accessTTL, refreshTTL time.Duration) *Issuer {
	return &Issuer{secret: []byte(secret), accessTTL: accessTTL, refreshTTL: refreshTTL}
}

type Tokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
}

func (i *Issuer) Issue(userID, role string) (Tokens, error) {
	access, err := i.sign(userID, role, "access", i.accessTTL)
	if err != nil {
		return Tokens{}, err
	}
	refresh, err := i.sign(userID, role, "refresh", i.refreshTTL)
	if err != nil {
		return Tokens{}, err
	}
	return Tokens{AccessToken: access, RefreshToken: refresh, ExpiresIn: int(i.accessTTL.Seconds())}, nil
}

func (i *Issuer) sign(userID, role, kind string, ttl time.Duration) (string, error) {
	now := time.Now()
	c := Claims{
		Role: role,
		Kind: kind,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
			Issuer:    "nomo",
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString(i.secret)
}

var ErrInvalidToken = errors.New("invalid token")

// Parse validates a token of the given kind and returns its claims.
func (i *Issuer) Parse(token, kind string) (*Claims, error) {
	c := &Claims{}
	t, err := jwt.ParseWithClaims(token, c, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, ErrInvalidToken
		}
		return i.secret, nil
	})
	if err != nil || !t.Valid || c.Kind != kind || c.Subject == "" {
		return nil, ErrInvalidToken
	}
	return c, nil
}
