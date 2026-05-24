package api

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/casper/shinytracker/internal/database"
	"github.com/go-chi/chi/v5"
)

// ── Hunt Methods ─────────────────────────────────────────────────────────────

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
		JOIN games g ON g.generation = hm.generation
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


func AdminCreateHuntMethod(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PokemonID      int    `json:"pokemon_id"`
		GameID         int    `json:"game_id"`
		MethodName     string `json:"method_name"`
		BaseRolls      int    `json:"base_rolls"`
		CharmRolls     int    `json:"charm_rolls"`
		AvgTimeSeconds int    `json:"avg_time_seconds"`
		FormulaType    string `json:"formula_type"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	if req.FormulaType == "" {
		req.FormulaType = "static"
	}

	var id int
	err := database.DB.QueryRow(context.Background(), `
		INSERT INTO hunt_methods (pokemon_id, game_id, method_name, base_rolls, charm_rolls, avg_time_seconds, formula_type)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id
	`, req.PokemonID, req.GameID, req.MethodName, req.BaseRolls, req.CharmRolls, req.AvgTimeSeconds, req.FormulaType).Scan(&id)
	if err != nil {
		if isUniqueViolation(err) {
			http.Error(w, "Hunt method with this pokemon/game/method already exists", http.StatusConflict)
			return
		}
		http.Error(w, "Failed to create hunt method", http.StatusInternalServerError)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]int{"id": id})
}

func AdminImportHuntMethods(w http.ResponseWriter, r *http.Request) {
	reader := csv.NewReader(r.Body)
	reader.TrimLeadingSpace = true

	// Read header row.
	header, err := reader.Read()
	if err != nil {
		http.Error(w, "Failed to read CSV header", http.StatusBadRequest)
		return
	}
	// Build column index map (case-insensitive).
	colIdx := make(map[string]int)
	for i, h := range header {
		colIdx[strings.ToLower(strings.TrimSpace(h))] = i
	}
	// is_recommended is intentionally omitted: a legacy is_recommended column is
	// accepted but ignored (see get/insert below).
	required := []string{"pokemon_id", "game_id", "method_name", "base_rolls", "charm_rolls", "avg_time_seconds"}
	for _, col := range required {
		if _, ok := colIdx[col]; !ok {
			http.Error(w, "Missing required column: "+col, http.StatusBadRequest)
			return
		}
	}

	type importResult struct {
		RowNumber int    `json:"row_number"`
		Status    string `json:"status"` // inserted | skipped | error
		Message   string `json:"message,omitempty"`
	}

	var results []importResult
	rowNum := 1

	for {
		record, err := reader.Read()
		if err != nil {
			break // EOF or unrecoverable parse error
		}
		rowNum++

		get := func(col string) string {
			i, ok := colIdx[col]
			if !ok || i >= len(record) {
				return ""
			}
			return strings.TrimSpace(record[i])
		}

		pokemonID, e1 := strconv.Atoi(get("pokemon_id"))
		gameID, e2 := strconv.Atoi(get("game_id"))
		baseRolls, e3 := strconv.Atoi(get("base_rolls"))
		charmRolls, e4 := strconv.Atoi(get("charm_rolls"))
		avgTime, e5 := strconv.Atoi(get("avg_time_seconds"))
		methodName := get("method_name")

		if e1 != nil || e2 != nil || e3 != nil || e4 != nil || e5 != nil || methodName == "" {
			results = append(results, importResult{RowNumber: rowNum, Status: "error", Message: "invalid or missing field"})
			continue
		}

		formulaType := get("formula_type")
		if formulaType == "" {
			formulaType = "static"
		}

		tag, err := database.DB.Exec(context.Background(), `
			INSERT INTO hunt_methods (pokemon_id, game_id, method_name, base_rolls, charm_rolls, avg_time_seconds, formula_type)
			VALUES ($1, $2, $3, $4, $5, $6, $7)
			ON CONFLICT (pokemon_id, game_id, method_name) DO NOTHING
		`, pokemonID, gameID, methodName, baseRolls, charmRolls, avgTime, formulaType)

		if err != nil {
			results = append(results, importResult{RowNumber: rowNum, Status: "error", Message: err.Error()})
			continue
		}

		if tag.RowsAffected() == 0 {
			results = append(results, importResult{RowNumber: rowNum, Status: "skipped"})
		} else {
			results = append(results, importResult{RowNumber: rowNum, Status: "inserted"})
		}
	}

	if len(results) == 0 {
		http.Error(w, "CSV has no data rows", http.StatusBadRequest)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(results)
}

func AdminUpdateHuntMethod(w http.ResponseWriter, r *http.Request) {
	idStr := chi.URLParam(r, "id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		http.Error(w, "Invalid id", http.StatusBadRequest)
		return
	}

	var req struct {
		MethodName     *string `json:"method_name"`
		BaseRolls      *int    `json:"base_rolls"`
		CharmRolls     *int    `json:"charm_rolls"`
		AvgTimeSeconds *int    `json:"avg_time_seconds"`
		FormulaType    *string `json:"formula_type"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	tag, err := database.DB.Exec(context.Background(), `
		UPDATE hunt_methods SET
			method_name     = COALESCE($2, method_name),
			base_rolls      = COALESCE($3, base_rolls),
			charm_rolls     = COALESCE($4, charm_rolls),
			avg_time_seconds = COALESCE($5, avg_time_seconds),
			formula_type    = COALESCE($6, formula_type)
		WHERE id = $1
	`, id, req.MethodName, req.BaseRolls, req.CharmRolls, req.AvgTimeSeconds, req.FormulaType)
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
		"SELECT id, username, email, is_admin, created_at FROM users ORDER BY created_at ASC")
	if err != nil {
		http.Error(w, "Failed to fetch users", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type userRow struct {
		ID        string    `json:"id"`
		Username  string    `json:"username"`
		Email     string    `json:"email"`
		IsAdmin   bool      `json:"is_admin"`
		CreatedAt time.Time `json:"created_at"`
	}
	var result []userRow
	for rows.Next() {
		var u userRow
		if err := rows.Scan(&u.ID, &u.Username, &u.Email, &u.IsAdmin, &u.CreatedAt); err == nil {
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
		"UPDATE users SET is_admin = $2 WHERE id = $1", targetID, req.IsAdmin)
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
