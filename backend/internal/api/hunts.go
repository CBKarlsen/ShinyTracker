package api

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/models"
	"github.com/go-chi/chi/v5"
)

func GetHuntsHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	rows, err := database.DB.Query(context.Background(),
		`SELECT h.id, h.user_id, h.pokemon_id, h.encounter_id, h.encounter_count, h.status, h.acquisition_type, h.hunt_parameters, h.created_at, h.updated_at,
		        p.name as pokemon_name, e.method_name, g.title as game_title
		 FROM user_hunts h
		 JOIN pokemon p ON h.pokemon_id = p.id
		 LEFT JOIN encounters e ON h.encounter_id = e.id
		 LEFT JOIN games g ON e.game_id = g.id
		 WHERE h.user_id = $1
		 ORDER BY h.created_at DESC`, userID)
	if err != nil {
		http.Error(w, "Failed to fetch hunts", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var hunts []models.UserHuntDetail
	for rows.Next() {
		var h models.UserHuntDetail
		if err := rows.Scan(
			&h.ID, &h.UserID, &h.PokemonID, &h.EncounterID, &h.EncounterCount, &h.Status, &h.AcquisitionType, &h.HuntParameters, &h.CreatedAt, &h.UpdatedAt,
			&h.PokemonName, &h.MethodName, &h.GameTitle,
		); err != nil {
			continue
		}
		hunts = append(hunts, h)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunts)
}

func CreateHuntHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	var req struct {
		EncounterID int    `json:"encounter_id"`
		PokemonID   int    `json:"pokemon_id"`
		MethodName  string `json:"method_name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	var pokemonID int
	var encounterID *int
	var huntParameters json.RawMessage

	if req.EncounterID == 0 {
		// Synthetic encounter (e.g. Masuda Method) — no row in encounters table.
		if req.PokemonID == 0 {
			http.Error(w, "pokemon_id required for synthetic encounters", http.StatusBadRequest)
			return
		}
		pokemonID = req.PokemonID
		encounterID = nil
		params, _ := json.Marshal(map[string]string{"method": req.MethodName})
		huntParameters = params
	} else {
		// Real encounter — resolve pokemon_id from the encounters table.
		err := database.DB.QueryRow(context.Background(),
			`SELECT pokemon_id FROM encounters WHERE id = $1`, req.EncounterID).Scan(&pokemonID)
		if err != nil {
			http.Error(w, "Invalid encounter ID", http.StatusBadRequest)
			return
		}
		encounterID = &req.EncounterID
		huntParameters = json.RawMessage(`{}`)
	}

	var hunt models.UserHunt
	err := database.DB.QueryRow(context.Background(),
		`INSERT INTO user_hunts (user_id, pokemon_id, encounter_id, acquisition_type, hunt_parameters)
		 VALUES ($1, $2, $3, 'HUNTED', $4)
		 RETURNING id, user_id, pokemon_id, encounter_id, encounter_count, status, acquisition_type, hunt_parameters, created_at, updated_at`,
		userID, pokemonID, encounterID, huntParameters).
		Scan(&hunt.ID, &hunt.UserID, &hunt.PokemonID, &hunt.EncounterID, &hunt.EncounterCount, &hunt.Status, &hunt.AcquisitionType, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt)

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

	var hunt models.UserHunt
	err := database.DB.QueryRow(context.Background(),
		`UPDATE user_hunts 
		 SET encounter_count = $1, status = $2, updated_at = CURRENT_TIMESTAMP
		 WHERE id = $3 AND user_id = $4
		 RETURNING id, user_id, pokemon_id, encounter_id, encounter_count, status, acquisition_type, hunt_parameters, created_at, updated_at`,
		req.EncounterCount, req.Status, huntID, userID).
		Scan(&hunt.ID, &hunt.UserID, &hunt.PokemonID, &hunt.EncounterID, &hunt.EncounterCount, &hunt.Status, &hunt.AcquisitionType, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt)

	if err != nil {
		http.Error(w, "Failed to update hunt", http.StatusInternalServerError)
		return
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
		`INSERT INTO user_hunts (user_id, pokemon_id, encounter_id, acquisition_type, encounter_count, status, hunt_parameters) 
		 VALUES ($1, $2, NULL, 'MANUAL_OVERRIDE', 1, 'completed', '{"manual": true}') 
		 RETURNING id, user_id, pokemon_id, encounter_id, encounter_count, status, acquisition_type, hunt_parameters, created_at, updated_at`,
		userID, req.PokemonID).
		Scan(&hunt.ID, &hunt.UserID, &hunt.PokemonID, &hunt.EncounterID, &hunt.EncounterCount, &hunt.Status, &hunt.AcquisitionType, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt)

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
