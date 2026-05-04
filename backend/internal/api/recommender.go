package api

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/casper/shinytracker/internal/database"
	"github.com/go-chi/chi/v5"
)

type Recommendation struct {
	EncounterID        int     `json:"encounter_id"`
	PokemonID          int     `json:"pokemon_id"`
	GameID             int     `json:"game_id"`
	GameTitle          string  `json:"game_title"`
	MethodName         string  `json:"method_name"`
	AvgTimeSeconds     int     `json:"avg_time_seconds"`
	BaseOdds           int     `json:"base_odds"`
	TotalRolls         int     `json:"total_rolls"`
	HasShinyCharm      bool    `json:"has_shiny_charm"`
	EstimatedTimeHours float64 `json:"estimated_time_hours"`
}

func GetRecommendationsHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	pokemonIDStr := chi.URLParam(r, "pokemonId")
	pokemonID, err := strconv.Atoi(pokemonIDStr)
	if err != nil {
		http.Error(w, "Invalid Pokemon ID", http.StatusBadRequest)
		return
	}

	query := `
		SELECT 
			e.id, e.pokemon_id, e.game_id, g.title, e.method_name, e.avg_time_seconds, 
			g.base_odds, e.base_rolls, e.charm_rolls, COALESCE(ug.has_shiny_charm, FALSE)
		FROM encounters e
		JOIN games g ON e.game_id = g.id
		JOIN user_games ug ON g.id = ug.game_id AND ug.user_id = $1
		WHERE e.pokemon_id = $2
	`

	rows, err := database.DB.Query(context.Background(), query, userID, pokemonID)
	if err != nil {
		http.Error(w, "Failed to fetch encounters", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var recommendations []Recommendation
	for rows.Next() {
		var rec Recommendation
		var baseRolls, charmRolls int
		if err := rows.Scan(
			&rec.EncounterID, &rec.PokemonID, &rec.GameID, &rec.GameTitle, 
			&rec.MethodName, &rec.AvgTimeSeconds, &rec.BaseOdds, 
			&baseRolls, &charmRolls, &rec.HasShinyCharm); err != nil {
			continue
		}

		rec.TotalRolls = baseRolls
		if rec.HasShinyCharm {
			rec.TotalRolls += charmRolls
		}

		if rec.TotalRolls <= 0 {
			rec.TotalRolls = 1 // Safety net
		}

		expectedEncounters := float64(rec.BaseOdds) / float64(rec.TotalRolls)
		ettsSeconds := expectedEncounters * float64(rec.AvgTimeSeconds)
		rec.EstimatedTimeHours = ettsSeconds / 3600.0

		recommendations = append(recommendations, rec)
	}

	// Sort recommendations by EstimatedTimeHours (most efficient first)
	for i := 0; i < len(recommendations)-1; i++ {
		for j := 0; j < len(recommendations)-i-1; j++ {
			if recommendations[j].EstimatedTimeHours > recommendations[j+1].EstimatedTimeHours {
				recommendations[j], recommendations[j+1] = recommendations[j+1], recommendations[j]
			}
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(recommendations)
}
