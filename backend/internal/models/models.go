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
	ID             int             `json:"id"`
	Name           string          `json:"name"`
	SpriteURL      string          `json:"sprite_url"`
	ShinySpriteURL string          `json:"shiny_sprite_url"`
	Types          json.RawMessage `json:"types"`
	IsLegendary    bool            `json:"is_legendary"`
	IsMythical     bool            `json:"is_mythical"`
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
	FormulaType    string `json:"formula_type"`
}

type UserHunt struct {
	ID              string          `json:"id"`
	UserID          string          `json:"user_id"`
	PokemonID       int             `json:"pokemon_id"`
	GameID          *int            `json:"game_id"`
	HuntMethodID    *int            `json:"hunt_method_id"`
	EncounterCount  int             `json:"encounter_count"`
	PhaseCount      int             `json:"phase_count"`
	Status          string          `json:"status"`
	AcquisitionType string          `json:"acquisition_type"`
	HuntParameters  json.RawMessage `json:"hunt_parameters"`
	// Nickname is an optional, user-supplied name for the catch. Nullable:
	// absent stays absent (nil), and the column never holds "" — PATCHing an
	// empty string clears it back to NULL.
	Nickname  *string   `json:"nickname"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type HuntPhase struct {
	ID                    string    `json:"id"`
	HuntID                string    `json:"hunt_id"`
	PokemonID             int       `json:"pokemon_id"`
	PokemonName           string    `json:"pokemon_name"`
	SpriteURL             string    `json:"sprite_url"`
	ShinySpriteURL        string    `json:"shiny_sprite_url"`
	EncounterCountAtPhase int       `json:"encounter_count_at_phase"`
	CreatedAt             time.Time `json:"created_at"`
}

// ─────────────────────────────────────────────────────────────────────────
// Nuzlocke mode (migrations/013_add_nuzlocke.sql)
// ─────────────────────────────────────────────────────────────────────────

// NuzlockeEncounterOption is one species in a location's wild encounter pool.
type NuzlockeEncounterOption struct {
	PokemonID   int    `json:"pokemon_id"`
	PokemonName string `json:"pokemon_name"`
	SpriteURL   string `json:"sprite_url"`
}

// NuzlockeBossMove is one move in a boss squad member's set.
//
// DamageClass ('physical' | 'special' | 'status') is what the client's
// party-coverage warning keys off, NOT Power: moves.power is NULL for every
// variable-power damaging move (Grass Knot, Metal Burst, Dragon Rage…), so a
// power test reads a Grass gym's main attack as harmless. See migration 017.
type NuzlockeBossMove struct {
	Name        string `json:"name"`
	Type        string `json:"type"`
	Power       int    `json:"power"`
	DamageClass string `json:"damage_class"`
}

// NuzlockeBossMon is one member of a boss's squad.
type NuzlockeBossMon struct {
	PokemonID   int                `json:"pokemon_id"`
	PokemonName string             `json:"pokemon_name"`
	SpriteURL   string             `json:"sprite_url"`
	Level       int                `json:"level"`
	Ability     string             `json:"ability"`
	Moves       []NuzlockeBossMove `json:"moves"`
}

// NuzlockeTimelineEntry is one point on the seeded route timeline — either a
// location (Encounters populated) or a boss (BossTitle/Place/LevelCap/Squad
// populated). Reference data, shared by every run of the same game.
type NuzlockeTimelineEntry struct {
	ID         int                       `json:"id"`
	Slug       string                    `json:"slug"`
	Kind       string                    `json:"kind"` // "location" or "boss"
	Name       string                    `json:"name"`
	SortOrder  int                       `json:"sort_order"`
	Place      *string                   `json:"place,omitempty"`
	BossTitle  *string                   `json:"boss_title,omitempty"`
	LevelCap   *int                      `json:"level_cap,omitempty"`
	Encounters []NuzlockeEncounterOption `json:"encounters,omitempty"`
	Squad      []NuzlockeBossMon         `json:"squad,omitempty"`
}

// NuzlockeRun is one user's playthrough of the seeded timeline.
type NuzlockeRun struct {
	ID     string `json:"id"`
	UserID string `json:"user_id"`
	GameID *int   `json:"game_id"`
	// Which version's timeline this run follows — 'platinum', 'diamond', …,
	// the same vocabulary pokemon_locations.version uses. Fixed at creation:
	// games.id 5 is "Diamond/Pearl/Platinum" and the three disagree about both
	// encounter tables and trainers (migration 017).
	Version           string     `json:"version"`
	GameTitle         *string    `json:"game_title,omitempty"`
	DupesClause       bool       `json:"dupes_clause"`
	BattleStyle       string     `json:"battle_style"`
	NicknamesRequired bool       `json:"nicknames_required"`
	Status            string     `json:"status"` // "active" or "ended"
	StartedAt         time.Time  `json:"started_at"`
	EndedAt           *time.Time `json:"ended_at"`
	CreatedAt         time.Time  `json:"created_at"`
	UpdatedAt         time.Time  `json:"updated_at"`
}

// NuzlockeEncounterLog is the logged encounter at one location for one run.
type NuzlockeEncounterLog struct {
	ID           string    `json:"id"`
	RunID        string    `json:"run_id"`
	LocationSlug string    `json:"location_slug"`
	PokemonID    *int      `json:"pokemon_id"`
	PokemonName  *string   `json:"pokemon_name,omitempty"`
	Nickname     *string   `json:"nickname"`
	Status       string    `json:"status"` // "caught", "missed", "fainted", "ran"
	Nature       *string   `json:"nature"`
	IsBoxed      bool      `json:"is_boxed"`
	IsDupe       bool      `json:"is_dupe"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

// NuzlockeBossProgress is the beaten toggle for one boss in one run.
type NuzlockeBossProgress struct {
	BossSlug string `json:"boss_slug"`
	Beaten   bool   `json:"beaten"`
}

// NuzlockeRunDetail is a run plus everything logged against it: the seeded
// timeline (for rendering), the logged encounters, and boss progress.
type NuzlockeRunDetail struct {
	NuzlockeRun
	Timeline     []NuzlockeTimelineEntry `json:"timeline"`
	Encounters   []NuzlockeEncounterLog  `json:"encounters"`
	BossProgress []NuzlockeBossProgress  `json:"boss_progress"`
}

type UserHuntDetail struct {
	UserHunt
	PokemonName      string      `json:"pokemon_name"`
	SpriteURL        string      `json:"sprite_url"`
	ShinySpriteURL   string      `json:"shiny_sprite_url"`
	MethodName       *string     `json:"method_name"`
	CustomMethodName *string     `json:"custom_method_name"`
	GameTitle        *string     `json:"game_title"`
	TotalTimeSeconds int         `json:"total_time_seconds"`
	BaseRolls        *int        `json:"base_rolls"`
	CharmRolls       *int        `json:"charm_rolls"`
	AvgTimeSeconds   *int        `json:"avg_time_seconds"`
	BaseOdds         *int        `json:"base_odds"`
	HasShinyCharm    *bool       `json:"has_shiny_charm"`
	FormulaType      *string     `json:"formula_type"`
	PhaseCount       int         `json:"phase_count"`
	Phases           []HuntPhase `json:"phases"`
}
