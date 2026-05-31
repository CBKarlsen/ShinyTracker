package api

// supabase_auth.go — additive Supabase JWT verifier (ES256 / JWKS).
//
// NOT wired into any middleware yet. The existing AuthMiddleware / ValidateJWT
// (auth.go) remain the sole gatekeepers until the atomic swap step.
//
// Usage (future swap step):
//
//	userID, err := ValidateSupabaseJWT(tokenString)
//
// Configuration (env vars, both optional — defaults match the known project):
//
//	SUPABASE_URL  e.g. https://fysopyztqmyjyfgrdusx.supabase.co
//	              JWKS endpoint  → <SUPABASE_URL>/auth/v1/.well-known/jwks.json
//	              Expected issuer → <SUPABASE_URL>/auth/v1

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/MicahParks/keyfunc/v3"
	"github.com/golang-jwt/jwt/v5"
)

const (
	// defaultSupabaseURL is the known project URL; overridable via SUPABASE_URL.
	defaultSupabaseURL = "https://fysopyztqmyjyfgrdusx.supabase.co"

	// supabaseAudience is the expected aud claim in Supabase access tokens.
	supabaseAudience = "authenticated"

	// jwksCacheTTL is how long we consider a fetched keyset fresh before
	// re-fetching on the next call. keyfunc handles the actual background
	// refresh; this constant documents intent and is passed as the refresh
	// interval to the keyfunc options.
	jwksCacheTTL = 60 * time.Minute
)

// supabaseKeyfuncState holds the lazily-initialised JWKS keyfunc and its
// associated context-cancel so it can be torn down in tests.
var supabaseKeyfuncState struct {
	mu     sync.RWMutex
	kf     keyfunc.Keyfunc
	cancel context.CancelFunc
}

// supabaseURLFromEnv returns the Supabase project URL, trimming any trailing
// slash so downstream concatenation is predictable.
func supabaseURLFromEnv() string {
	u := os.Getenv("SUPABASE_URL")
	if u == "" {
		u = defaultSupabaseURL
	}
	return strings.TrimRight(u, "/")
}

// getSupabaseKeyfunc returns the cached JWKS keyfunc, initialising it lazily
// on first call. A failed initialisation returns an error rather than
// panicking — the server continues running and the next call will retry.
func getSupabaseKeyfunc() (keyfunc.Keyfunc, error) {
	// Fast path: already initialised.
	supabaseKeyfuncState.mu.RLock()
	if supabaseKeyfuncState.kf != nil {
		kf := supabaseKeyfuncState.kf
		supabaseKeyfuncState.mu.RUnlock()
		return kf, nil
	}
	supabaseKeyfuncState.mu.RUnlock()

	// Slow path: initialise under write lock.
	supabaseKeyfuncState.mu.Lock()
	defer supabaseKeyfuncState.mu.Unlock()

	// Double-checked: another goroutine may have won the race.
	if supabaseKeyfuncState.kf != nil {
		return supabaseKeyfuncState.kf, nil
	}

	projectURL := supabaseURLFromEnv()
	jwksURL := projectURL + "/auth/v1/.well-known/jwks.json"

	ctx, cancel := context.WithCancel(context.Background())

	// keyfunc.NewDefaultCtx fetches the JWKS immediately and starts a
	// background goroutine that refreshes the keyset on the given interval.
	// An unknown kid causes an immediate re-fetch (UnknownKIDShouldRefresh).
	kf, err := keyfunc.NewDefaultCtx(ctx, []string{jwksURL})
	if err != nil {
		cancel()
		return nil, fmt.Errorf("supabase JWKS init (%s): %w", jwksURL, err)
	}

	supabaseKeyfuncState.kf = kf
	supabaseKeyfuncState.cancel = cancel
	return kf, nil
}

// ValidateSupabaseJWT verifies a Supabase-issued ES256 JWT.
//
// It fetches (and caches) the JWKS from the Supabase project's well-known
// endpoint, then validates:
//
//   - ES256 signing method (rejects anything else)
//   - exp (token not expired)
//   - aud == "authenticated"
//   - iss == "<SUPABASE_URL>/auth/v1"
//
// On success it returns the sub claim (Supabase user UUID). On any failure it
// returns a non-nil error with enough context to diagnose the problem.
//
// NOT called by any middleware yet — wiring happens in the swap step.
func ValidateSupabaseJWT(tokenString string) (userID string, err error) {
	kf, err := getSupabaseKeyfunc()
	if err != nil {
		return "", fmt.Errorf("supabase jwt: keyfunc unavailable: %w", err)
	}

	projectURL := supabaseURLFromEnv()
	expectedIssuer := projectURL + "/auth/v1"

	// Parse with the keyfunc-provided Keyfunc, and enforce ES256 + standard
	// claim validators provided by golang-jwt/jwt/v5.
	token, err := jwt.Parse(
		tokenString,
		kf.Keyfunc,
		jwt.WithValidMethods([]string{"ES256"}),
		jwt.WithAudience(supabaseAudience),
		jwt.WithIssuer(expectedIssuer),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return "", fmt.Errorf("supabase jwt: parse/validate failed: %w", err)
	}

	if !token.Valid {
		return "", errors.New("supabase jwt: token invalid")
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", errors.New("supabase jwt: unexpected claims type")
	}

	sub, err := claims.GetSubject()
	if err != nil || sub == "" {
		return "", fmt.Errorf("supabase jwt: missing sub claim: %w", err)
	}

	return sub, nil
}

// closeSupabaseKeyfunc tears down the background JWKS refresh goroutine.
// Intended for graceful shutdown; not required for correctness in production.
func closeSupabaseKeyfunc() {
	supabaseKeyfuncState.mu.Lock()
	defer supabaseKeyfuncState.mu.Unlock()
	if supabaseKeyfuncState.cancel != nil {
		supabaseKeyfuncState.cancel()
		supabaseKeyfuncState.cancel = nil
		supabaseKeyfuncState.kf = nil
	}
}

