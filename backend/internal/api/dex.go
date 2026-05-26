package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/casper/shinytracker/internal/calc"
	"github.com/casper/shinytracker/internal/database"
	"github.com/go-chi/chi/v5"
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

// fetchMethodCandidates returns the huntable methods for a Pokemon in the
// user's owned games, with the data needed to compute odds.
func fetchMethodCandidates(ctx context.Context, userID string, pokemonID int) ([]calc.MethodCandidate, error) {
	rows, err := database.DB.Query(ctx, `
		SELECT g.id, g.title, hm.method_name, g.base_odds,
		       hm.base_rolls, hm.charm_rolls, hm.avg_time_seconds, ug.has_shiny_charm
		FROM method_availability ma
		JOIN hunt_methods hm ON ma.method_id = hm.id
		JOIN games g         ON g.id = ma.game_id
		JOIN user_games ug   ON ug.game_id = g.id
		WHERE ma.pokemon_id = $1 AND ug.user_id = $2
		ORDER BY g.generation ASC, g.id ASC
	`, pokemonID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var cands []calc.MethodCandidate
	for rows.Next() {
		var c calc.MethodCandidate
		if err := rows.Scan(&c.GameID, &c.GameTitle, &c.MethodName, &c.BaseOdds,
			&c.BaseRolls, &c.CharmRolls, &c.AvgTimeSeconds, &c.HasShinyCharm); err != nil {
			return nil, err
		}
		cands = append(cands, c)
	}
	return cands, rows.Err()
}

type PokemonRouteResponse struct {
	Status string       `json:"status"` // available | not_in_your_games | locked_everywhere
	Routes []calc.Route `json:"routes"`
}

// PokemonRouteHandler returns blocked status + ranked routes (direct + evolve)
// for one Pokemon, scoped to the authenticated user's owned games.
func PokemonRouteHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	if userID == "" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	pokemonID, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, "id must be an integer", http.StatusBadRequest)
		return
	}
	ctx := context.Background()

	availGames, err := queryIntColumn(ctx,
		`SELECT game_id FROM pokemon_availability WHERE pokemon_id = $1`, pokemonID)
	if err != nil {
		http.Error(w, "Failed to load availability", http.StatusInternalServerError)
		return
	}
	lockedGames, err := queryIntColumn(ctx,
		`SELECT game_id FROM shiny_locks WHERE pokemon_id = $1`, pokemonID)
	if err != nil {
		http.Error(w, "Failed to load locks", http.StatusInternalServerError)
		return
	}
	ownedGames, err := queryIntColumn(ctx,
		`SELECT game_id FROM user_games WHERE user_id = $1`, userID)
	if err != nil {
		http.Error(w, "Failed to load games", http.StatusInternalServerError)
		return
	}

	resp := PokemonRouteResponse{Routes: []calc.Route{}}
	switch {
	case calc.IsLockedEverywhere(availGames, lockedGames):
		resp.Status = "locked_everywhere"
	case len(availGames) > 0 && !anyOwned(availGames, ownedGames):
		resp.Status = "not_in_your_games"
	default:
		resp.Status = "available"
	}

	if resp.Status == "available" {
		direct, err := fetchMethodCandidates(ctx, userID, pokemonID)
		if err != nil {
			http.Error(w, "Failed to load routes", http.StatusInternalServerError)
			return
		}
		routes := calc.RankDirectRoutes(direct)

		ancestors, err := fetchAncestors(ctx, pokemonID)
		if err != nil {
			http.Error(w, "Failed to load evolution line", http.StatusInternalServerError)
			return
		}
		for _, anc := range ancestors {
			cands, err := fetchMethodCandidates(ctx, userID, anc.PokemonID)
			if err != nil || len(cands) == 0 {
				continue
			}
			best, ok := calc.BestRoute(cands, anc)
			if ok && calc.ShouldIncludeEvolveRoute(routes, best) {
				routes = append(routes, best)
			}
		}
		resp.Routes = routes
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// anyOwned reports whether any availability game is in the owned set.
func anyOwned(avail, owned []int) bool {
	set := make(map[int]bool, len(owned))
	for _, g := range owned {
		set[g] = true
	}
	for _, g := range avail {
		if set[g] {
			return true
		}
	}
	return false
}

// fetchAncestors returns the pre-evolution line (nearest first) for a Pokemon.
func fetchAncestors(ctx context.Context, pokemonID int) ([]calc.EvolveFrom, error) {
	rows, err := database.DB.Query(ctx, `
		WITH RECURSIVE line AS (
			SELECT id, evolves_from_id FROM pokemon WHERE id = $1
			UNION ALL
			SELECT p.id, p.evolves_from_id
			FROM pokemon p JOIN line ON p.id = line.evolves_from_id
		)
		SELECT p.id, p.name
		FROM line JOIN pokemon p ON p.id = line.id
		WHERE line.id <> $1
	`, pokemonID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []calc.EvolveFrom
	for rows.Next() {
		var e calc.EvolveFrom
		if err := rows.Scan(&e.PokemonID, &e.Name); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
