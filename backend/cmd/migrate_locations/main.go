package main

import (
	"context"
	"log"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

// Additive migration: creates pokemon_locations and its indexes. Safe to re-run.
// Deliberately NOT part of cmd/apply_schema, which drops the method tables.
func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	ctx := context.Background()
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS pokemon_locations (
			id             SERIAL PRIMARY KEY,
			pokemon_id     INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
			game_id        INTEGER NOT NULL REFERENCES games(id)   ON DELETE CASCADE,
			version        TEXT    NOT NULL,
			area           TEXT    NOT NULL,
			terrain        TEXT    NOT NULL,
			pokeapi_method TEXT    NOT NULL,
			min_level      INTEGER,
			max_level      INTEGER,
			chance         INTEGER,
			conditions     TEXT[]
		)`,
		`CREATE INDEX IF NOT EXISTS idx_pokemon_locations_pokemon_game
			ON pokemon_locations (pokemon_id, game_id)`,
		`CREATE INDEX IF NOT EXISTS idx_pokemon_locations_game_area
			ON pokemon_locations (game_id, area)`,
	}
	for _, s := range stmts {
		if _, err := database.DB.Exec(ctx, s); err != nil {
			log.Fatal("migration failed: ", err)
		}
	}
	log.Println("pokemon_locations ready.")
}
