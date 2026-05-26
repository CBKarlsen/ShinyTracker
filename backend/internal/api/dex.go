package api

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/casper/shinytracker/internal/database"
)

type DexStatusResponse struct {
	NotInYourGames   []int `json:"not_in_your_games"`
	LockedEverywhere []int `json:"locked_everywhere"`
}

// DexStatusHandler returns, for the authenticated user, the Pokemon that are
// locked everywhere (globally) and the ones not available in any owned game.
func DexStatusHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	if userID == "" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	ctx := context.Background()

	// Available somewhere, but zero owned-game availability.
	notInGames, err := queryIntColumn(ctx, `
		SELECT pa.pokemon_id
		FROM pokemon_availability pa
		GROUP BY pa.pokemon_id
		HAVING COUNT(*) FILTER (
			WHERE pa.game_id IN (SELECT game_id FROM user_games WHERE user_id = $1)
		) = 0
	`, userID)
	if err != nil {
		http.Error(w, "Failed to compute dex status", http.StatusInternalServerError)
		return
	}

	// Available in >=1 game and locked in all of them (global).
	lockedEverywhere, err := queryIntColumn(ctx, `
		SELECT pa.pokemon_id
		FROM pokemon_availability pa
		LEFT JOIN shiny_locks sl
		  ON sl.pokemon_id = pa.pokemon_id AND sl.game_id = pa.game_id
		GROUP BY pa.pokemon_id
		HAVING COUNT(*) = COUNT(sl.pokemon_id)
	`)
	if err != nil {
		http.Error(w, "Failed to compute dex status", http.StatusInternalServerError)
		return
	}

	resp := DexStatusResponse{NotInYourGames: notInGames, LockedEverywhere: lockedEverywhere}
	if resp.NotInYourGames == nil {
		resp.NotInYourGames = []int{}
	}
	if resp.LockedEverywhere == nil {
		resp.LockedEverywhere = []int{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// queryIntColumn runs a query whose first column is an int and returns all values.
func queryIntColumn(ctx context.Context, sql string, args ...any) ([]int, error) {
	rows, err := database.DB.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []int
	for rows.Next() {
		var v int
		if err := rows.Scan(&v); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}

// PokemonRouteHandler is implemented in Task 6. Temporary stub so the route
// registration compiles.
func PokemonRouteHandler(w http.ResponseWriter, r *http.Request) {
	http.Error(w, "not implemented", http.StatusNotImplemented)
}
