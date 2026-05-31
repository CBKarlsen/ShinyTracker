package api

// supabase_auth.go — Supabase JWT verifier (ES256 / JWKS).
//
// Wired into AuthMiddleware as of the Supabase Auth swap step.
//
// Usage:
//
//	userID, claims, err := ValidateSupabaseJWTWithClaims(tokenString)
//	userID, err         := ValidateSupabaseJWT(tokenString)  // thin wrapper
//
// Configuration (env vars — SUPABASE_URL is required at startup):
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
// slash so downstream concatenation is predictable. Returns an error if
// SUPABASE_URL is unset — the server must not start without it.
func supabaseURLFromEnv() (string, error) {
	u := os.Getenv("SUPABASE_URL")
	if u == "" {
		return "", errors.New("SUPABASE_URL env var is required but not set")
	}
	return strings.TrimRight(u, "/"), nil
}

// getSupabaseKeyfunc returns the cached JWKS keyfunc, initialising it lazily
// on first call. If the initial JWKS fetch fails (network down, bad URL, empty
// keyset) the error is returned and the keyfunc is NOT cached — the next
// request will retry initialisation. This prevents the server from silently
// accepting tokens against a zero-key verifier.
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

	projectURL, err := supabaseURLFromEnv()
	if err != nil {
		return nil, err
	}
	jwksURL := projectURL + "/auth/v1/.well-known/jwks.json"

	ctx, cancel := context.WithCancel(context.Background())

	// NoErrorReturnFirstHTTPReq=false makes the initial JWKS fetch a hard
	// requirement: if the remote endpoint is unreachable or returns an
	// error, NewDefaultOverrideCtx returns a non-nil error rather than
	// succeeding with an empty keyset. This ensures we never serve auth
	// from a verifier that holds zero keys.
	falseVar := false
	kf, err := keyfunc.NewDefaultOverrideCtx(ctx, []string{jwksURL}, keyfunc.Override{
		NoErrorReturnFirstHTTPReq: &falseVar,
		RefreshInterval:           jwksCacheTTL,
	})
	if err != nil {
		cancel()
		// Do NOT cache — next request will retry init.
		return nil, fmt.Errorf("supabase JWKS init (%s): %w", jwksURL, err)
	}

	supabaseKeyfuncState.kf = kf
	supabaseKeyfuncState.cancel = cancel
	return kf, nil
}

// ValidateSupabaseJWTWithClaims verifies a Supabase-issued ES256 JWT and
// returns the sub claim (user UUID) together with the full MapClaims so the
// caller can inspect email / user_metadata without re-parsing the token.
//
// Validates:
//   - ES256 signing method (rejects anything else)
//   - exp (token not expired)
//   - aud == "authenticated"
//   - iss == "<SUPABASE_URL>/auth/v1"
func ValidateSupabaseJWTWithClaims(tokenString string) (userID string, claims jwt.MapClaims, err error) {
	kf, err := getSupabaseKeyfunc()
	if err != nil {
		return "", nil, fmt.Errorf("supabase jwt: keyfunc unavailable: %w", err)
	}

	projectURL, err := supabaseURLFromEnv()
	if err != nil {
		return "", nil, fmt.Errorf("supabase jwt: %w", err)
	}
	expectedIssuer := projectURL + "/auth/v1"

	// Parse with the JWKS-backed keyfunc and enforce ES256 + standard claim validators.
	token, err := jwt.Parse(
		tokenString,
		kf.Keyfunc,
		jwt.WithValidMethods([]string{"ES256"}),
		jwt.WithAudience(supabaseAudience),
		jwt.WithIssuer(expectedIssuer),
		jwt.WithExpirationRequired(),
	)
	if err != nil {
		return "", nil, fmt.Errorf("supabase jwt: parse/validate failed: %w", err)
	}
	// golang-jwt v5 guarantees token.Valid == true when err is nil; no
	// redundant !token.Valid check needed.

	mc, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", nil, errors.New("supabase jwt: unexpected claims type")
	}

	sub, err := mc.GetSubject()
	if err != nil || sub == "" {
		return "", nil, fmt.Errorf("supabase jwt: missing sub claim: %w", err)
	}

	return sub, mc, nil
}

// ValidateSupabaseJWT is a thin wrapper around ValidateSupabaseJWTWithClaims
// that discards the claims and returns only the sub (user UUID). Kept for
// call-sites that do not need the full claims map.
func ValidateSupabaseJWT(tokenString string) (userID string, err error) {
	id, _, err := ValidateSupabaseJWTWithClaims(tokenString)
	return id, err
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

