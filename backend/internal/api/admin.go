package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/casper/shinytracker/internal/database"
	"github.com/go-chi/chi/v5"
)

// ── Hunt Methods ─────────────────────────────────────────────────────────────
//
// In the rules-based model, hunt_methods are GLOBAL definitions and a Pokemon's
// available methods are derived into method_availability (see cmd/seed). So this
// admin surface is a read-only per-Pokemon view of derived availability, plus
// edit/delete that act on the GLOBAL method (by id). Creating per-Pokemon rows
// is no longer meaningful, so there is no create/import endpoint.

func AdminGetHuntMethods(w http.ResponseWriter, r *http.Request) {
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

	rows, err := database.DB.Query(context.Background(), `
		SELECT hm.id, ma.pokemon_id, g.id as game_id, g.title, hm.method_name,
		       hm.base_rolls, hm.charm_rolls, hm.avg_time_seconds, hm.formula_type
		FROM method_availability ma
		JOIN hunt_methods hm ON ma.method_id = hm.id
		JOIN games g ON g.id = ma.game_id
		WHERE ma.pokemon_id = $1
		ORDER BY g.id ASC, hm.method_name ASC
	`, pokemonID)
	if err != nil {
		http.Error(w, "Failed to fetch hunt methods", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type row struct {
		ID             int    `json:"id"`
		PokemonID      int    `json:"pokemon_id"`
		GameID         int    `json:"game_id"`
		GameTitle      string `json:"game_title"`
		MethodName     string `json:"method_name"`
		BaseRolls      int    `json:"base_rolls"`
		CharmRolls     int    `json:"charm_rolls"`
		AvgTimeSeconds int    `json:"avg_time_seconds"`
		FormulaType    string `json:"formula_type"`
	}
	var result []row
	for rows.Next() {
		var enc row
		if err := rows.Scan(&enc.ID, &enc.PokemonID, &enc.GameID, &enc.GameTitle,
			&enc.MethodName, &enc.BaseRolls, &enc.CharmRolls, &enc.AvgTimeSeconds, &enc.FormulaType); err == nil {
			result = append(result, enc)
		}
	}
	if result == nil {
		result = []row{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}


func AdminUpdateHuntMethod(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, "Invalid id", http.StatusBadRequest)
		return
	}

	// Edits the GLOBAL method definition; the change applies to every Pokemon and
	// game this method is available for.
	var req struct {
		MethodName      *string `json:"method_name"`
		BaseRolls       *int    `json:"base_rolls"`
		CharmRolls      *int    `json:"charm_rolls"`
		AvgTimeSeconds  *int    `json:"avg_time_seconds"`
		FormulaType     *string `json:"formula_type"`
		RequiresTerrain *string `json:"requires_terrain"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	tag, err := database.DB.Exec(context.Background(), `
		UPDATE hunt_methods SET
			method_name      = COALESCE($2, method_name),
			base_rolls       = COALESCE($3, base_rolls),
			charm_rolls      = COALESCE($4, charm_rolls),
			avg_time_seconds = COALESCE($5, avg_time_seconds),
			formula_type     = COALESCE($6, formula_type),
			requires_terrain = COALESCE(NULLIF($7, ''), requires_terrain)
		WHERE id = $1
	`, id, req.MethodName, req.BaseRolls, req.CharmRolls, req.AvgTimeSeconds, req.FormulaType, req.RequiresTerrain)
	if err != nil {
		http.Error(w, "Failed to update hunt method", http.StatusInternalServerError)
		return
	}
	if tag.RowsAffected() == 0 {
		http.Error(w, "Hunt method not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func AdminDeleteHuntMethod(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, "Invalid id", http.StatusBadRequest)
		return
	}
	tag, err := database.DB.Exec(context.Background(), "DELETE FROM hunt_methods WHERE id = $1", id)
	if err != nil {
		http.Error(w, "Failed to delete hunt method", http.StatusInternalServerError)
		return
	}
	if tag.RowsAffected() == 0 {
		http.Error(w, "Hunt method not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusOK)
}

// ── Games ────────────────────────────────────────────────────────────────────

func AdminGetGames(w http.ResponseWriter, r *http.Request) {
	rows, err := database.DB.Query(context.Background(),
		"SELECT id, title, generation, base_odds, supports_breeding FROM games ORDER BY id ASC")
	if err != nil {
		http.Error(w, "Failed to fetch games", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type gameRow struct {
		ID               int    `json:"id"`
		Title            string `json:"title"`
		Generation       int    `json:"generation"`
		BaseOdds         int    `json:"base_odds"`
		SupportsBreeding bool   `json:"supports_breeding"`
	}
	var result []gameRow
	for rows.Next() {
		var g gameRow
		if err := rows.Scan(&g.ID, &g.Title, &g.Generation, &g.BaseOdds, &g.SupportsBreeding); err == nil {
			result = append(result, g)
		}
	}
	if result == nil {
		result = []gameRow{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

func AdminCreateGame(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Title            string `json:"title"`
		Generation       int    `json:"generation"`
		BaseOdds         int    `json:"base_odds"`
		SupportsBreeding bool   `json:"supports_breeding"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	var id int
	err := database.DB.QueryRow(context.Background(), `
		INSERT INTO games (title, generation, base_odds, supports_breeding)
		VALUES ($1, $2, $3, $4) RETURNING id
	`, req.Title, req.Generation, req.BaseOdds, req.SupportsBreeding).Scan(&id)
	if err != nil {
		if isUniqueViolation(err) {
			http.Error(w, "A game with this title already exists", http.StatusConflict)
			return
		}
		http.Error(w, "Failed to create game", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]int{"id": id})
}

func AdminUpdateGame(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, "Invalid id", http.StatusBadRequest)
		return
	}

	var req struct {
		Title            *string `json:"title"`
		Generation       *int    `json:"generation"`
		BaseOdds         *int    `json:"base_odds"`
		SupportsBreeding *bool   `json:"supports_breeding"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	tag, err := database.DB.Exec(context.Background(), `
		UPDATE games SET
			title             = COALESCE($2, title),
			generation        = COALESCE($3, generation),
			base_odds         = COALESCE($4, base_odds),
			supports_breeding = COALESCE($5, supports_breeding)
		WHERE id = $1
	`, id, req.Title, req.Generation, req.BaseOdds, req.SupportsBreeding)
	if err != nil {
		http.Error(w, "Failed to update game", http.StatusInternalServerError)
		return
	}
	if tag.RowsAffected() == 0 {
		http.Error(w, "Game not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusOK)
}

func AdminDeleteGame(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, "Invalid id", http.StatusBadRequest)
		return
	}

	var count int
	_ = database.DB.QueryRow(context.Background(),
		"SELECT COUNT(*) FROM hunt_methods WHERE game_id = $1", id).Scan(&count)
	if count > 0 {
		http.Error(w, "Remove all hunt methods for this game before deleting it", http.StatusConflict)
		return
	}

	tag, err := database.DB.Exec(context.Background(), "DELETE FROM games WHERE id = $1", id)
	if err != nil {
		http.Error(w, "Failed to delete game", http.StatusInternalServerError)
		return
	}
	if tag.RowsAffected() == 0 {
		http.Error(w, "Game not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusOK)
}

// ── Availability ─────────────────────────────────────────────────────────────

func AdminGetAvailability(w http.ResponseWriter, r *http.Request) {
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

	rows, err := database.DB.Query(context.Background(), `
		SELECT g.id, g.title,
		       EXISTS(SELECT 1 FROM pokemon_availability pa WHERE pa.game_id = g.id AND pa.pokemon_id = $1) AS available
		FROM games g
		ORDER BY g.id ASC
	`, pokemonID)
	if err != nil {
		http.Error(w, "Failed to fetch availability", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type availRow struct {
		GameID    int    `json:"game_id"`
		GameTitle string `json:"game_title"`
		Available bool   `json:"available"`
	}
	var result []availRow
	for rows.Next() {
		var a availRow
		if err := rows.Scan(&a.GameID, &a.GameTitle, &a.Available); err == nil {
			result = append(result, a)
		}
	}
	if result == nil {
		result = []availRow{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

func AdminSetAvailability(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PokemonID int  `json:"pokemon_id"`
		GameID    int  `json:"game_id"`
		Available bool `json:"available"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.PokemonID == 0 || req.GameID == 0 {
		http.Error(w, "pokemon_id and game_id are required", http.StatusBadRequest)
		return
	}

	if req.Available {
		_, err := database.DB.Exec(context.Background(), `
			INSERT INTO pokemon_availability (pokemon_id, game_id)
			VALUES ($1, $2) ON CONFLICT DO NOTHING
		`, req.PokemonID, req.GameID)
		if err != nil {
			http.Error(w, "Failed to set availability", http.StatusInternalServerError)
			return
		}
	} else {
		_, err := database.DB.Exec(context.Background(),
			"DELETE FROM pokemon_availability WHERE pokemon_id = $1 AND game_id = $2",
			req.PokemonID, req.GameID)
		if err != nil {
			http.Error(w, "Failed to remove availability", http.StatusInternalServerError)
			return
		}
	}
	w.WriteHeader(http.StatusOK)
}

// ── Users ─────────────────────────────────────────────────────────────────────

func AdminGetUsers(w http.ResponseWriter, r *http.Request) {
	rows, err := database.DB.Query(context.Background(),
		"SELECT id, username, is_admin, created_at FROM profiles ORDER BY created_at ASC")
	if err != nil {
		http.Error(w, "Failed to fetch users", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type userRow struct {
		ID        string    `json:"id"`
		Username  string    `json:"username"`
		IsAdmin   bool      `json:"is_admin"`
		CreatedAt time.Time `json:"created_at"`
	}
	var result []userRow
	for rows.Next() {
		var u userRow
		if err := rows.Scan(&u.ID, &u.Username, &u.IsAdmin, &u.CreatedAt); err == nil {
			result = append(result, u)
		}
	}
	if result == nil {
		result = []userRow{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(result)
}

func AdminPatchUser(w http.ResponseWriter, r *http.Request) {
	targetID := chi.URLParam(r, "id")
	callerID := r.Header.Get("X-User-ID")

	var req struct {
		IsAdmin bool `json:"is_admin"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if targetID == callerID && !req.IsAdmin {
		http.Error(w, "You cannot remove your own admin privileges", http.StatusBadRequest)
		return
	}

	tag, err := database.DB.Exec(context.Background(),
		"UPDATE profiles SET is_admin = $2 WHERE id = $1", targetID, req.IsAdmin)
	if err != nil {
		http.Error(w, "Failed to update user", http.StatusInternalServerError)
		return
	}
	if tag.RowsAffected() == 0 {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}
	w.WriteHeader(http.StatusOK)
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func isUniqueViolation(err error) bool {
	return err != nil && (strings.Contains(err.Error(), "23505") || strings.Contains(err.Error(), "unique"))
}
