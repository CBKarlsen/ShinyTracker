package api

import (
	"context"
	"encoding/json"
	"net/http"
	"time"

	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/models"
	"github.com/go-chi/chi/v5"
)

// loadPhasesForHunts fetches all phases for the given hunt IDs and groups them by hunt ID.
func loadPhasesForHunts(ctx context.Context, huntIDs []string) (map[string][]models.HuntPhase, error) {
	result := make(map[string][]models.HuntPhase)
	if len(huntIDs) == 0 {
		return result, nil
	}

	rows, err := database.DB.Query(ctx,
		`SELECT hp.id, hp.hunt_id, hp.pokemon_id, p.name, COALESCE(p.sprite_url, ''), hp.encounter_count_at_phase, hp.created_at
		 FROM hunt_phases hp
		 JOIN pokemon p ON hp.pokemon_id = p.id
		 WHERE hp.hunt_id = ANY($1::uuid[])
		 ORDER BY hp.hunt_id, hp.created_at ASC`, huntIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var ph models.HuntPhase
		if err := rows.Scan(&ph.ID, &ph.HuntID, &ph.PokemonID, &ph.PokemonName, &ph.SpriteURL, &ph.EncounterCountAtPhase, &ph.CreatedAt); err != nil {
			continue
		}
		result[ph.HuntID] = append(result[ph.HuntID], ph)
	}
	return result, rows.Err()
}

func GetHuntsHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	rows, err := database.DB.Query(context.Background(),
		`SELECT h.id, h.user_id, h.pokemon_id, h.hunt_method_id, h.encounter_count, h.phase_count, h.status, h.acquisition_type, h.hunt_parameters, h.created_at, h.updated_at,
		        p.name as pokemon_name, e.method_name, h.custom_method_name, g.title as game_title,
		        h.total_time_seconds, e.base_rolls, e.charm_rolls, e.avg_time_seconds, g.base_odds, ug.has_shiny_charm
		 FROM user_hunts h
		 JOIN pokemon p ON h.pokemon_id = p.id
		 LEFT JOIN hunt_methods e ON h.hunt_method_id = e.id
		 LEFT JOIN games g ON e.game_id = g.id
		 LEFT JOIN user_games ug ON ug.game_id = g.id AND ug.user_id = h.user_id
		 WHERE h.user_id = $1
		 ORDER BY h.created_at DESC`, userID)
	if err != nil {
		http.Error(w, "Failed to fetch hunts", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var hunts []models.UserHuntDetail
	var huntIDs []string
	for rows.Next() {
		var h models.UserHuntDetail
		if err := rows.Scan(
			&h.ID, &h.UserID, &h.PokemonID, &h.HuntMethodID, &h.EncounterCount, &h.PhaseCount, &h.Status, &h.AcquisitionType, &h.HuntParameters, &h.CreatedAt, &h.UpdatedAt,
			&h.PokemonName, &h.MethodName, &h.CustomMethodName, &h.GameTitle,
			&h.TotalTimeSeconds, &h.BaseRolls, &h.CharmRolls, &h.AvgTimeSeconds, &h.BaseOdds, &h.HasShinyCharm,
		); err != nil {
			continue
		}
		h.Phases = []models.HuntPhase{}
		hunts = append(hunts, h)
		huntIDs = append(huntIDs, h.ID)
	}

	phasesByHunt, err := loadPhasesForHunts(context.Background(), huntIDs)
	if err == nil {
		for i, h := range hunts {
			if phases, ok := phasesByHunt[h.ID]; ok {
				hunts[i].Phases = phases
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunts)
}

func CreateHuntHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	var req struct {
		HuntMethodID     int    `json:"hunt_method_id"`
		PokemonID        int    `json:"pokemon_id"`
		MethodName       string `json:"method_name"`
		CustomMethodName string `json:"custom_method_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	hasCurated := req.HuntMethodID != 0
	hasCustom := req.CustomMethodName != ""

	if hasCurated && hasCustom {
		http.Error(w, "Provide hunt_method_id or custom_method_name, not both", http.StatusBadRequest)
		return
	}

	var pokemonID int
	var huntMethodID *int
	var customMethodName *string
	var huntParameters json.RawMessage

	if hasCustom {
		// User-defined method — pokemon_id required, no hunt_methods row.
		if req.PokemonID == 0 {
			http.Error(w, "pokemon_id required for custom hunt methods", http.StatusBadRequest)
			return
		}
		pokemonID = req.PokemonID
		huntMethodID = nil
		customMethodName = &req.CustomMethodName
		huntParameters = json.RawMessage(`{}`)
	} else if hasCurated {
		// Curated method — resolve pokemon_id from hunt_methods.
		err := database.DB.QueryRow(context.Background(),
			`SELECT pokemon_id FROM hunt_methods WHERE id = $1`, req.HuntMethodID).Scan(&pokemonID)
		if err != nil {
			http.Error(w, "Invalid hunt method ID", http.StatusBadRequest)
			return
		}
		huntMethodID = &req.HuntMethodID
		customMethodName = nil
		huntParameters = json.RawMessage(`{}`)
	} else {
		// Legacy: synthetic method (Masuda etc.) — keep existing behaviour.
		if req.PokemonID == 0 {
			http.Error(w, "pokemon_id required", http.StatusBadRequest)
			return
		}
		pokemonID = req.PokemonID
		huntMethodID = nil
		customMethodName = nil
		params, _ := json.Marshal(map[string]string{"method": req.MethodName})
		huntParameters = params
	}

	var hunt models.UserHunt
	err := database.DB.QueryRow(context.Background(),
		`INSERT INTO user_hunts (user_id, pokemon_id, hunt_method_id, custom_method_name, acquisition_type, hunt_parameters)
		 VALUES ($1, $2, $3, $4, 'HUNTED', $5)
		 RETURNING id, user_id, pokemon_id, hunt_method_id, encounter_count, phase_count, status, acquisition_type, hunt_parameters, created_at, updated_at`,
		userID, pokemonID, huntMethodID, customMethodName, huntParameters).
		Scan(&hunt.ID, &hunt.UserID, &hunt.PokemonID, &hunt.HuntMethodID, &hunt.EncounterCount, &hunt.PhaseCount, &hunt.Status, &hunt.AcquisitionType, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt)

	if err != nil {
		http.Error(w, "Failed to create hunt", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunt)
}

func UpdateHuntHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	huntID := chi.URLParam(r, "id")

	var req struct {
		EncounterCount int    `json:"encounter_count"`
		Status         string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	var prevUpdatedAt time.Time
	var currentTotalTime int
	err := database.DB.QueryRow(context.Background(),
		`SELECT updated_at, total_time_seconds FROM user_hunts WHERE id = $1 AND user_id = $2`,
		huntID, userID).Scan(&prevUpdatedAt, &currentTotalTime)
	if err != nil {
		http.Error(w, "Hunt not found", http.StatusNotFound)
		return
	}

	newTotalTime := currentTotalTime
	delta := time.Since(prevUpdatedAt)
	if delta < 600*time.Second {
		newTotalTime += int(delta.Seconds())
	}

	var hunt models.UserHunt
	err = database.DB.QueryRow(context.Background(),
		`UPDATE user_hunts
		 SET encounter_count = $1, status = $2, updated_at = CURRENT_TIMESTAMP, total_time_seconds = $3
		 WHERE id = $4 AND user_id = $5
		 RETURNING id, user_id, pokemon_id, hunt_method_id, encounter_count, phase_count, status, acquisition_type, hunt_parameters, created_at, updated_at`,
		req.EncounterCount, req.Status, newTotalTime, huntID, userID).
		Scan(&hunt.ID, &hunt.UserID, &hunt.PokemonID, &hunt.HuntMethodID, &hunt.EncounterCount, &hunt.PhaseCount, &hunt.Status, &hunt.AcquisitionType, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt)

	if err != nil {
		http.Error(w, "Failed to update hunt", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunt)
}

func LogPhaseHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	huntID := chi.URLParam(r, "id")

	var req struct {
		PokemonID int `json:"pokemon_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PokemonID == 0 {
		http.Error(w, "pokemon_id required", http.StatusBadRequest)
		return
	}

	// Verify hunt ownership, active status, and capture current encounter count.
	var currentCount int
	var huntStatus string
	err := database.DB.QueryRow(context.Background(),
		`SELECT encounter_count, status FROM user_hunts WHERE id = $1 AND user_id = $2`,
		huntID, userID).Scan(&currentCount, &huntStatus)
	if err != nil {
		http.Error(w, "Hunt not found", http.StatusNotFound)
		return
	}
	if huntStatus != "active" {
		http.Error(w, "Cannot log phase on a completed hunt", http.StatusBadRequest)
		return
	}

	tx, err := database.DB.Begin(context.Background())
	if err != nil {
		http.Error(w, "Failed to start transaction", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(context.Background())

	// Insert phase record.
	if _, err := tx.Exec(context.Background(),
		`INSERT INTO hunt_phases (hunt_id, pokemon_id, encounter_count_at_phase) VALUES ($1, $2, $3)`,
		huntID, req.PokemonID, currentCount); err != nil {
		http.Error(w, "Failed to log phase", http.StatusInternalServerError)
		return
	}

	// Reset encounter count, increment phase count.
	if _, err := tx.Exec(context.Background(),
		`UPDATE user_hunts SET encounter_count = 0, phase_count = phase_count + 1, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
		huntID); err != nil {
		http.Error(w, "Failed to update hunt", http.StatusInternalServerError)
		return
	}

	// Add phase pokemon to collection (completed hunt entry).
	if _, err := tx.Exec(context.Background(),
		`INSERT INTO user_hunts (user_id, pokemon_id, hunt_method_id, acquisition_type, encounter_count, status, hunt_parameters)
		 VALUES ($1, $2, NULL, 'HUNTED', $3, 'completed', '{}')`,
		userID, req.PokemonID, currentCount); err != nil {
		http.Error(w, "Failed to add phase pokemon to collection", http.StatusInternalServerError)
		return
	}

	if err := tx.Commit(context.Background()); err != nil {
		http.Error(w, "Failed to commit transaction", http.StatusInternalServerError)
		return
	}

	// Load full hunt detail with phases for response.
	var hunt models.UserHuntDetail
	if err := database.DB.QueryRow(context.Background(),
		`SELECT h.id, h.user_id, h.pokemon_id, h.hunt_method_id, h.encounter_count, h.phase_count, h.status, h.acquisition_type, h.hunt_parameters, h.created_at, h.updated_at,
		        p.name, e.method_name, h.custom_method_name, g.title,
		        h.total_time_seconds, e.base_rolls, e.charm_rolls, e.avg_time_seconds, g.base_odds, ug.has_shiny_charm
		 FROM user_hunts h
		 JOIN pokemon p ON h.pokemon_id = p.id
		 LEFT JOIN hunt_methods e ON h.hunt_method_id = e.id
		 LEFT JOIN games g ON e.game_id = g.id
		 LEFT JOIN user_games ug ON ug.game_id = g.id AND ug.user_id = h.user_id
		 WHERE h.id = $1 AND h.user_id = $2`,
		huntID, userID).Scan(
		&hunt.ID, &hunt.UserID, &hunt.PokemonID, &hunt.HuntMethodID, &hunt.EncounterCount, &hunt.PhaseCount, &hunt.Status, &hunt.AcquisitionType, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt,
		&hunt.PokemonName, &hunt.MethodName, &hunt.CustomMethodName, &hunt.GameTitle,
		&hunt.TotalTimeSeconds, &hunt.BaseRolls, &hunt.CharmRolls, &hunt.AvgTimeSeconds, &hunt.BaseOdds, &hunt.HasShinyCharm,
	); err != nil {
		http.Error(w, "Failed to load updated hunt", http.StatusInternalServerError)
		return
	}

	phasesByHunt, _ := loadPhasesForHunts(context.Background(), []string{huntID})
	if phases, ok := phasesByHunt[huntID]; ok {
		hunt.Phases = phases
	} else {
		hunt.Phases = []models.HuntPhase{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunt)
}

func ManualCatchHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	var req struct {
		PokemonID int `json:"pokemon_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	var hunt models.UserHunt
	err := database.DB.QueryRow(context.Background(),
		`INSERT INTO user_hunts (user_id, pokemon_id, hunt_method_id, acquisition_type, encounter_count, status, hunt_parameters)
		 VALUES ($1, $2, NULL, 'MANUAL_OVERRIDE', 1, 'completed', '{"manual": true}')
		 RETURNING id, user_id, pokemon_id, hunt_method_id, encounter_count, phase_count, status, acquisition_type, hunt_parameters, created_at, updated_at`,
		userID, req.PokemonID).
		Scan(&hunt.ID, &hunt.UserID, &hunt.PokemonID, &hunt.HuntMethodID, &hunt.EncounterCount, &hunt.PhaseCount, &hunt.Status, &hunt.AcquisitionType, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt)

	if err != nil {
		http.Error(w, "Failed to create manual catch", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunt)
}

func RemoveManualCatchHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	pokemonID := chi.URLParam(r, "pokemonId")

	_, err := database.DB.Exec(context.Background(),
		`DELETE FROM user_hunts
		 WHERE user_id = $1 AND status = 'completed' AND pokemon_id = $2 AND acquisition_type = 'MANUAL_OVERRIDE'`,
		userID, pokemonID)

	if err != nil {
		http.Error(w, "Failed to remove catch", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Catch removed successfully"})
}
