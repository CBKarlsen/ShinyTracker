package api

import (
	"context"
	"net/http"
	"strings"

	"github.com/casper/shinytracker/internal/database"
	"github.com/golang-jwt/jwt/v5"
)

// contextKey is an unexported type for context keys in this package, to avoid
// collisions with keys from other packages.
type contextKey int

const (
	// ctxKeyClaims holds the parsed jwt.MapClaims for the authenticated request.
	ctxKeyClaims contextKey = iota
)

// claimsFromContext retrieves the Supabase JWT claims stashed by AuthMiddleware.
// Returns nil if not present (e.g. on unauthenticated routes).
func claimsFromContext(ctx context.Context) jwt.MapClaims {
	v, _ := ctx.Value(ctxKeyClaims).(jwt.MapClaims)
	return v
}

// AuthMiddleware verifies the Supabase ES256 bearer token on every request
// inside the authenticated route group. On success it:
//   - injects the token's sub claim as the X-User-ID request header (so all
//     existing handlers that read that header keep working unchanged), and
//   - stashes the full MapClaims in the request context for handlers that need
//     additional claims (e.g. email, user_metadata).
//
// Missing or invalid tokens are rejected with 401.
func AuthMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			http.Error(w, "Authorization header required", http.StatusUnauthorized)
			return
		}

		parts := strings.Split(authHeader, " ")
		if len(parts) != 2 || parts[0] != "Bearer" {
			http.Error(w, "Invalid authorization header format", http.StatusUnauthorized)
			return
		}

		userID, claims, err := ValidateSupabaseJWTWithClaims(parts[1])
		if err != nil {
			http.Error(w, "Invalid or expired token", http.StatusUnauthorized)
			return
		}

		// Keep the X-User-ID header so every existing handler reads the user
		// identity the same way it always has.
		r.Header.Set("X-User-ID", userID)

		// Stash the full claims for handlers that need them (e.g. MeHandler).
		ctx := context.WithValue(r.Context(), ctxKeyClaims, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// AdminMiddleware rejects requests from non-admin users with 403.
// Must be used after AuthMiddleware (relies on X-User-ID being set).
// Admin status is looked up from the profiles table (Supabase Auth era).
func AdminMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		userID := r.Header.Get("X-User-ID")
		if userID == "" {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		var isAdmin bool
		err := database.DB.QueryRow(context.Background(),
			"SELECT is_admin FROM profiles WHERE id = $1", userID).Scan(&isAdmin)
		if err != nil || !isAdmin {
			http.Error(w, "Forbidden", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}
