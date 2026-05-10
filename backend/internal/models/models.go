package models

import (
	"encoding/json"
	"time"
)

type User struct {
	ID           string    `json:"id"`
	Username     string    `json:"username"`
	Email        string    `json:"email"`
	PasswordHash string    `json:"-"`
	IsAdmin      bool      `json:"is_admin"`
	CreatedAt    time.Time `json:"created_at"`
}

type Pokemon struct {
	ID        int             `json:"id"`
	Name      string          `json:"name"`
	SpriteURL string          `json:"sprite_url"`
	Types     json.RawMessage `json:"types"`
}

type Game struct {
	ID         int    `json:"id"`
	Title      string `json:"title"`
	Generation int    `json:"generation"`
	BaseOdds   int    `json:"base_odds"`
}

type UserGame struct {
	UserID        string `json:"user_id"`
	GameID        int    `json:"game_id"`
	HasShinyCharm bool   `json:"has_shiny_charm"`
}

type HuntMethod struct {
	ID             int    `json:"id"`
	PokemonID      int    `json:"pokemon_id"`
	GameID         int    `json:"game_id"`
	MethodName     string `json:"method_name"`
	AvgTimeSeconds int    `json:"avg_time_seconds"`
	BaseRolls      int    `json:"base_rolls"`
	CharmRolls     int    `json:"charm_rolls"`
}

type UserHunt struct {
	ID              string          `json:"id"`
	UserID          string          `json:"user_id"`
	PokemonID       int             `json:"pokemon_id"`
	HuntMethodID    *int            `json:"hunt_method_id"`
	EncounterCount  int             `json:"encounter_count"`
	PhaseCount      int             `json:"phase_count"`
	Status          string          `json:"status"`
	AcquisitionType string          `json:"acquisition_type"`
	HuntParameters  json.RawMessage `json:"hunt_parameters"`
	CreatedAt       time.Time       `json:"created_at"`
	UpdatedAt       time.Time       `json:"updated_at"`
}

type HuntPhase struct {
	ID                   string    `json:"id"`
	HuntID               string    `json:"hunt_id"`
	PokemonID            int       `json:"pokemon_id"`
	PokemonName          string    `json:"pokemon_name"`
	SpriteURL            string    `json:"sprite_url"`
	EncounterCountAtPhase int      `json:"encounter_count_at_phase"`
	CreatedAt            time.Time `json:"created_at"`
}

type UserHuntDetail struct {
	UserHunt
	PokemonName      string      `json:"pokemon_name"`
	MethodName       *string     `json:"method_name"`
	GameTitle        *string     `json:"game_title"`
	TotalTimeSeconds int         `json:"total_time_seconds"`
	BaseRolls        *int        `json:"base_rolls"`
	CharmRolls       *int        `json:"charm_rolls"`
	AvgTimeSeconds   *int        `json:"avg_time_seconds"`
	BaseOdds         *int        `json:"base_odds"`
	HasShinyCharm    *bool       `json:"has_shiny_charm"`
	PhaseCount       int         `json:"phase_count"`
	Phases           []HuntPhase `json:"phases"`
}
