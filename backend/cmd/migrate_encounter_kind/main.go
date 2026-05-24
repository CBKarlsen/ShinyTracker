package main

import (
	"context"
	"log"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

// Idempotent migration for the encounter-kind model.
// Adds pokemon_game_encounter and hunt_methods.requires_kind to an existing
// database without dropping user_hunts (or any other) data.
func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	ctx := context.Background()

	stmts := []string{
		`CREATE TABLE IF NOT EXISTS pokemon_game_encounter (
			pokemon_id INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
			game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
			kind TEXT NOT NULL CHECK (kind IN ('wild','static','raid','egg')),
			PRIMARY KEY (pokemon_id, game_id, kind)
		)`,
		`ALTER TABLE hunt_methods
			ADD COLUMN IF NOT EXISTS requires_kind TEXT NOT NULL DEFAULT 'wild'`,
		// Add the CHECK constraint separately so re-runs don't error if it exists.
		`DO $$
		BEGIN
			IF NOT EXISTS (
				SELECT 1 FROM pg_constraint WHERE conname = 'hunt_methods_requires_kind_check'
			) THEN
				ALTER TABLE hunt_methods
					ADD CONSTRAINT hunt_methods_requires_kind_check
					CHECK (requires_kind IN ('wild','static','raid','egg'));
			END IF;
		END $$;`,
	}

	for _, s := range stmts {
		if _, err := database.DB.Exec(ctx, s); err != nil {
			log.Fatalf("Migration step failed: %v\nStatement: %s", err, s)
		}
	}

	log.Println("encounter-kind migration applied (pokemon_game_encounter + hunt_methods.requires_kind).")
}
