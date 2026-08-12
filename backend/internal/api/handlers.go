package api

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"sync/atomic"

	"github.com/casper/shinytracker/internal/calc"
	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/models"
	"github.com/casper/shinytracker/internal/services"
	"github.com/go-chi/chi/v5"
)

func GetUserGamesHandler(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	authUserID := r.Header.Get("X-User-ID")

	if userID != authUserID {
		http.Error(w, "Unauthorized access to user games", http.StatusForbidden)
		return
	}

	rows, err := database.DB.Query(context.Background(),
		"SELECT game_id, has_shiny_charm FROM user_games WHERE user_id = $1", userID)
	if err != nil {
		http.Error(w, "Failed to fetch user games", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var userGames []models.UserGame
	for rows.Next() {
		var ug models.UserGame
		ug.UserID = userID
		if err := rows.Scan(&ug.GameID, &ug.HasShinyCharm); err != nil {
			continue
		}
		userGames = append(userGames, ug)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(userGames)
}

func ToggleUserGameHandler(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	gameIDStr := chi.URLParam(r, "gameId")
	authUserID := r.Header.Get("X-User-ID")

	if userID != authUserID {
		http.Error(w, "Unauthorized access", http.StatusForbidden)
		return
	}

	gameID, err := strconv.Atoi(gameIDStr)
	if err != nil {
		http.Error(w, "gameId must be an integer", http.StatusBadRequest)
		return
	}

	var req struct {
		HasShinyCharm bool `json:"has_shiny_charm"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Guard: the Shiny Charm was not introduced until Black 2/White 2 (Gen 5 sequel).
	// Reject attempts to set it for pre-B2W2 games so stale charm flags can never
	// inflate odds. Unsetting (false) is always allowed.
	if req.HasShinyCharm && !calc.ShinyCharmAvailable(gameID) {
		http.Error(w, "Shiny Charm is not available in this game", http.StatusBadRequest)
		return
	}

	_, err = database.DB.Exec(context.Background(),
		`INSERT INTO user_games (user_id, game_id, has_shiny_charm) 
		 VALUES ($1, $2, $3) 
		 ON CONFLICT (user_id, game_id) 
		 DO UPDATE SET has_shiny_charm = EXCLUDED.has_shiny_charm`,
		userID, gameID, req.HasShinyCharm)

	if err != nil {
		http.Error(w, "Failed to update user game", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "success"})
}

func RemoveUserGameHandler(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	gameID := chi.URLParam(r, "gameId")
	authUserID := r.Header.Get("X-User-ID")

	if userID != authUserID {
		http.Error(w, "Unauthorized access", http.StatusForbidden)
		return
	}

	_, err := database.DB.Exec(context.Background(),
		"DELETE FROM user_games WHERE user_id = $1 AND game_id = $2",
		userID, gameID)
	if err != nil {
		http.Error(w, "Failed to remove user game", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "success"})
}

// MeHandler is the bootstrap endpoint called by the frontend on login.
// It upserts a profiles row for the current Supabase user (deriving a display
// name from the token claims), then returns { id, username, is_admin }.
func MeHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	// Derive the best display name from the token claims.
	username := usernameFromClaims(claimsFromContext(r.Context()))

	// Upsert: create the profile on first login; on subsequent calls only update
	// the username (is_admin is never overwritten by this path).
	var profile struct {
		ID       string `json:"id"`
		Username string `json:"username"`
		IsAdmin  bool   `json:"is_admin"`
	}
	err := database.DB.QueryRow(context.Background(),
		`INSERT INTO profiles (id, username)
		 VALUES ($1, $2)
		 ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username
		 RETURNING id, username, is_admin`,
		userID, username).Scan(&profile.ID, &profile.Username, &profile.IsAdmin)
	if err != nil {
		http.Error(w, "Failed to upsert profile", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(profile)
}

// usernameFromClaims derives the best display name from a Supabase JWT's
// MapClaims. Priority: user_metadata.user_name → user_metadata.name →
// user_metadata.full_name → email local-part → "user".
func usernameFromClaims(claims map[string]interface{}) string {
	if claims == nil {
		return "user"
	}

	// user_metadata is a sub-map embedded in the JWT by the OAuth provider.
	if meta, ok := claims["user_metadata"].(map[string]interface{}); ok {
		for _, key := range []string{"user_name", "name", "full_name"} {
			if v, ok := meta[key].(string); ok && v != "" {
				return v
			}
		}
	}

	// Fall back to the email local-part.
	if email, ok := claims["email"].(string); ok && email != "" {
		if at := strings.Index(email, "@"); at > 0 {
			return email[:at]
		}
		return email
	}

	return "user"
}

// syncRunning guards against concurrent PokeAPI re-seeds. SyncPokemonData runs a
// multi-worker fetch of 1000+ Pokemon; overlapping runs would multiply PokeAPI
// load and can starve the DB connection pool. Admin-only, but still guarded.
var syncRunning atomic.Bool

func SyncHandler(w http.ResponseWriter, r *http.Request) {
	if !syncRunning.CompareAndSwap(false, true) {
		http.Error(w, "A sync is already in progress", http.StatusConflict)
		return
	}
	go func() {
		defer syncRunning.Store(false)
		if err := services.SyncPokemonData(); err != nil {
			log.Printf("SyncPokemonData error: %v", err)
		}
	}()
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]string{"message": "Sync started in background"})
}

func GetGamesHandler(w http.ResponseWriter, r *http.Request) {
	rows, err := database.DB.Query(context.Background(), "SELECT id, title, generation, base_odds FROM games ORDER BY id ASC")
	if err != nil {
		http.Error(w, "Failed to fetch games", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var games []models.Game
	for rows.Next() {
		var g models.Game
		if err := rows.Scan(&g.ID, &g.Title, &g.Generation, &g.BaseOdds); err == nil {
			games = append(games, g)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(games)
}

func GetPokemonHandler(w http.ResponseWriter, r *http.Request) {
	search := r.URL.Query().Get("q")
	query := "SELECT id, name, sprite_url, types, is_legendary, is_mythical FROM pokemon"
	args := []interface{}{}

	limit := r.URL.Query().Get("limit")

	if search != "" {
		query += " WHERE name ILIKE $1"
		args = append(args, "%"+search+"%")
	}
	query += " ORDER BY id ASC"

	if limit != "all" {
		query += " LIMIT 50"
	}

	rows, err := database.DB.Query(context.Background(), query, args...)
	if err != nil {
		http.Error(w, "Failed to fetch pokemon", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var pokemon []models.Pokemon
	for rows.Next() {
		var p models.Pokemon
		if err := rows.Scan(&p.ID, &p.Name, &p.SpriteURL, &p.Types, &p.IsLegendary, &p.IsMythical); err == nil {
			pokemon = append(pokemon, p)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(pokemon)
}

type HuntMethodDetail struct {
	ID             int    `json:"id"`
	PokemonID      int    `json:"pokemon_id"`
	GameID         int    `json:"game_id"`
	GameTitle      string `json:"game_title"`
	MethodName     string `json:"method_name"`
	AvgTimeSeconds int    `json:"avg_time_seconds"`
	BaseRolls      int    `json:"base_rolls"`
	CharmRolls     int    `json:"charm_rolls"`
	FormulaType    string `json:"formula_type"`
}

type MethodDetail struct {
	ID             int    `json:"id"`
	GameID         int    `json:"game_id"`
	GameTitle      string `json:"game_title"`
	MethodName     string `json:"method_name"`
	BaseRolls      int    `json:"base_rolls"`
	CharmRolls     int    `json:"charm_rolls"`
	AvgTimeSeconds int    `json:"avg_time_seconds"`
	FormulaType    string `json:"formula_type"`
}

type OddsResponse struct {
	Fraction           string  `json:"fraction"`
	Percentage         string  `json:"percentage"`
	ExpectedEncounters int     `json:"expected_encounters"`
	ETAHours           float64 `json:"eta_hours"`
}

// GetGamePokemonHandler returns the pokemon_id values obtainable in a given
// game per pokemon_availability. Public reference data, same as /games and
// /pokemon — no auth required.
func GetGamePokemonHandler(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, "Invalid id", http.StatusBadRequest)
		return
	}

	rows, err := database.DB.Query(context.Background(),
		"SELECT pokemon_id FROM pokemon_availability WHERE game_id = $1 ORDER BY pokemon_id ASC", id)
	if err != nil {
		http.Error(w, "Failed to fetch pokemon availability", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	ids := []int{}
	for rows.Next() {
		var pokemonID int
		if err := rows.Scan(&pokemonID); err == nil {
			ids = append(ids, pokemonID)
		}
	}
	// The Dex uses this list as the exact obtainable set, so a truncated read must not come
	// back as a 200 — a short list would silently shrink the completion bar's denominator.
	if err := rows.Err(); err != nil {
		http.Error(w, "Failed to fetch pokemon availability", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(ids)
}

func GetMethodsHandler(w http.ResponseWriter, r *http.Request) {
	gameIDStr := r.URL.Query().Get("game_id")
	gameID := 0
	if gameIDStr != "" {
		var err error
		gameID, err = strconv.Atoi(gameIDStr)
		if err != nil {
			http.Error(w, "game_id must be an integer", http.StatusBadRequest)
			return
		}
	}

	rows, err := database.DB.Query(context.Background(), `
		SELECT DISTINCT ON (g.id, hm.method_name)
			hm.id, g.id as game_id, g.title, hm.method_name,
			hm.base_rolls, hm.charm_rolls, hm.avg_time_seconds, hm.formula_type
		FROM method_games mg
		JOIN hunt_methods hm ON mg.method_id = hm.id
		JOIN games g ON g.id = mg.game_id
		WHERE ($1 = 0 OR g.id = $1)
		ORDER BY g.id ASC, hm.method_name ASC
	`, gameID)
	if err != nil {
		log.Printf("GetMethodsHandler error: %v", err)
		http.Error(w, "Failed to fetch methods", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var methods []MethodDetail
	for rows.Next() {
		var m MethodDetail
		if err := rows.Scan(&m.ID, &m.GameID, &m.GameTitle, &m.MethodName,
			&m.BaseRolls, &m.CharmRolls, &m.AvgTimeSeconds, &m.FormulaType); err == nil {
			methods = append(methods, m)
		}
	}
	if methods == nil {
		methods = []MethodDetail{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(methods)
}

func GetOddsHandler(w http.ResponseWriter, r *http.Request) {
	huntMethodIDStr := r.URL.Query().Get("hunt_method_id")
	if huntMethodIDStr == "" {
		http.Error(w, "hunt_method_id is required", http.StatusBadRequest)
		return
	}
	huntMethodID, err := strconv.Atoi(huntMethodIDStr)
	if err != nil {
		http.Error(w, "hunt_method_id must be an integer", http.StatusBadRequest)
		return
	}
	shinyCharmParam := r.URL.Query().Get("shiny_charm") == "true"

	var baseRolls, charmRolls, avgTimeSeconds, baseOdds, gameID int
	var formulaType string
	err = database.DB.QueryRow(context.Background(), `
		SELECT e.base_rolls, e.charm_rolls, e.avg_time_seconds, g.base_odds, e.formula_type, g.id
		FROM hunt_methods e
		JOIN method_games mg ON e.id = mg.method_id
		JOIN games g ON mg.game_id = g.id
		WHERE e.id = $1
		LIMIT 1
	`, huntMethodID).Scan(&baseRolls, &charmRolls, &avgTimeSeconds, &baseOdds, &formulaType, &gameID)
	if err != nil {
		http.Error(w, "Hunt method not found", http.StatusNotFound)
		return
	}

	// Guard: ignore a caller-supplied shiny_charm=true when the charm doesn't
	// exist for this game, even if a stale DB flag somehow survived.
	hasCharm := shinyCharmParam && calc.ShinyCharmAvailable(gameID)

	base := calc.OddsConfig{
		BaseOdds:       baseOdds,
		BaseRolls:      baseRolls,
		CharmRolls:     charmRolls,
		AvgTimeSeconds: avgTimeSeconds,
	}
	// Use EffectiveOdds (mirrors route ranking) with best-case default params.
	// This ensures formula-aware methods (chaining, SOS, DexNav, etc.) agree
	// with the denominator shown in the route drawer / hunt-next panel.
	expectedEncounters := calc.EffectiveOdds(formulaType, calc.DefaultParams(formulaType), base, hasCharm)
	if expectedEncounters < 1 {
		expectedEncounters = 1
	}

	// ETA mirrors routes.go: expected_encounters * avg_time_seconds / 3600.
	etaHours := float64(expectedEncounters) * float64(avgTimeSeconds) / 3600.0
	// Round to one decimal place (same rounding as the old handler).
	etaHours = float64(int(etaHours*10+0.5)) / 10

	resp := OddsResponse{
		Fraction:           fmt.Sprintf("1/%d", expectedEncounters),
		Percentage:         fmt.Sprintf("%.4f%%", float64(1)/float64(expectedEncounters)*100),
		ExpectedEncounters: expectedEncounters,
		ETAHours:           etaHours,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func GetHuntMethodsHandler(w http.ResponseWriter, r *http.Request) {
	pokemonIDStr := r.URL.Query().Get("pokemon_id")
	if pokemonIDStr == "" {
		http.Error(w, "pokemon_id is required", http.StatusBadRequest)
		return
	}
	pokemonID, err := strconv.Atoi(pokemonIDStr)
	if err != nil {
		http.Error(w, "pokemon_id must be an integer", http.StatusBadRequest)
		return
	}

	userID := r.Header.Get("X-User-ID")
	if userID == "" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Fetch methods from our new rules-based availability table
	rows, err := database.DB.Query(context.Background(), `
		SELECT hm.id, ma.pokemon_id, g.id as game_id, g.title, hm.method_name, hm.avg_time_seconds, hm.base_rolls, hm.charm_rolls, hm.formula_type
		FROM method_availability ma
		JOIN hunt_methods hm ON ma.method_id = hm.id
		JOIN games g ON g.id = ma.game_id
		JOIN user_games ug ON g.id = ug.game_id
		WHERE ma.pokemon_id = $1 AND ug.user_id = $2
		ORDER BY g.generation ASC, g.id ASC
	`, pokemonID, userID)
	if err != nil {
		http.Error(w, "Failed to fetch hunt methods", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var methods []HuntMethodDetail
	for rows.Next() {
		var m HuntMethodDetail
		if err := rows.Scan(
			&m.ID, &m.PokemonID, &m.GameID, &m.GameTitle,
			&m.MethodName, &m.AvgTimeSeconds, &m.BaseRolls, &m.CharmRolls, &m.FormulaType,
		); err != nil {
			continue
		}
		methods = append(methods, m)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(methods)
}
