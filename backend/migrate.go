package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load()
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL must be set")
	}

	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		log.Fatal("Unable to connect to database:", err)
	}
	defer pool.Close()

	queries := []string{
		`ALTER TABLE user_hunts ADD COLUMN IF NOT EXISTS pokemon_id INTEGER REFERENCES pokemon(id) ON DELETE CASCADE`,
		`ALTER TABLE user_hunts ADD COLUMN IF NOT EXISTS acquisition_type VARCHAR DEFAULT 'HUNTED'`,
		`UPDATE user_hunts uh SET pokemon_id = e.pokemon_id FROM hunt_methods e WHERE uh.hunt_method_id = e.id AND uh.pokemon_id IS NULL`,
		`ALTER TABLE user_hunts ALTER COLUMN pokemon_id SET NOT NULL`,
		`ALTER TABLE user_hunts ALTER COLUMN acquisition_type SET NOT NULL`,
		`ALTER TABLE user_hunts ALTER COLUMN encounter_id DROP NOT NULL`,
		// Remove existing constraint if it exists to make script idempotent
		`ALTER TABLE user_hunts DROP CONSTRAINT IF EXISTS check_acquisition_type`,
		`ALTER TABLE user_hunts ADD CONSTRAINT check_acquisition_type CHECK (acquisition_type IN ('HUNTED', 'EVOLVED', 'MANUAL_OVERRIDE', 'TRADED'))`,

		// Add breeding support flag to games (true for all games except LGPE and Legends: Arceus)
		`ALTER TABLE games ADD COLUMN IF NOT EXISTS supports_breeding BOOLEAN NOT NULL DEFAULT TRUE`,
		`UPDATE games SET supports_breeding = FALSE WHERE title IN ('Let''s Go Pikachu/Eevee', 'Legends: Arceus')`,

		// Track which Pokémon are legally obtainable in each game (regardless of wild encounters)
		`CREATE TABLE IF NOT EXISTS pokemon_availability (
			pokemon_id INTEGER REFERENCES pokemon(id) ON DELETE CASCADE,
			game_id    INTEGER REFERENCES games(id)   ON DELETE CASCADE,
			PRIMARY KEY (pokemon_id, game_id)
		)`,

		// Backfill availability from existing hunt method data
		`INSERT INTO pokemon_availability (pokemon_id, game_id)
		 SELECT DISTINCT pokemon_id, game_id FROM hunt_methods
		 ON CONFLICT DO NOTHING`,
	}

	for i, q := range queries {
		_, err := pool.Exec(context.Background(), q)
		if err != nil {
			log.Fatalf("Error executing query %d: %v\nQuery: %s", i, err, q)
		}
		fmt.Printf("Successfully executed query %d\n", i)
	}
	fmt.Println("Migration complete!")
}
