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
		`SELECT h.id, h.user_id, h.encounter_id, h.encounter_count, h.status, h.hunt_parameters, h.created_at, h.updated_at
		 FROM user_hunts h
		 WHERE h.user_id = $1
		 ORDER BY h.created_at DESC`, userID)
	if err != nil {
		http.Error(w, "Failed to fetch hunts", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var hunts []models.UserHunt
	for rows.Next() {
		var h models.UserHunt
		if err := rows.Scan(&h.ID, &h.UserID, &h.EncounterID, &h.EncounterCount, &h.Status, &h.HuntParameters, &h.CreatedAt, &h.UpdatedAt); err != nil {
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
		EncounterID    int             `json:"encounter_id"`
		HuntParameters json.RawMessage `json:"hunt_parameters"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	var hunt models.UserHunt
	err := database.DB.QueryRow(context.Background(),
		`INSERT INTO user_hunts (user_id, encounter_id, hunt_parameters) 
		 VALUES ($1, $2, $3) 
		 RETURNING id, user_id, encounter_id, encounter_count, status, hunt_parameters, created_at, updated_at`,
		userID, req.EncounterID, req.HuntParameters).
		Scan(&hunt.ID, &hunt.UserID, &hunt.EncounterID, &hunt.EncounterCount, &hunt.Status, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt)

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
		 RETURNING id, user_id, encounter_id, encounter_count, status, hunt_parameters, created_at, updated_at`,
		req.EncounterCount, req.Status, huntID, userID).
		Scan(&hunt.ID, &hunt.UserID, &hunt.EncounterID, &hunt.EncounterCount, &hunt.Status, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt)

	if err != nil {
		http.Error(w, "Failed to update hunt", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunt)
}
