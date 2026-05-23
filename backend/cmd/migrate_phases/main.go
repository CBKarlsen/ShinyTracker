package main

import (
	"context"
	"fmt"
	"log"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	_, err := database.DB.Exec(context.Background(),
		`ALTER TABLE user_hunts ADD COLUMN IF NOT EXISTS phase_count INT NOT NULL DEFAULT 0`)
	if err != nil {
		log.Fatal("Migration failed (phase_count):", err)
	}
	fmt.Println("✅ phase_count column added to user_hunts")

	_, err = database.DB.Exec(context.Background(),
		`CREATE TABLE IF NOT EXISTS hunt_phases (
			id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
			hunt_id UUID NOT NULL REFERENCES user_hunts(id) ON DELETE CASCADE,
			pokemon_id INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
			encounter_count_at_phase INTEGER NOT NULL DEFAULT 0,
			created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
		)`)
	if err != nil {
		log.Fatal("Migration failed (hunt_phases):", err)
	}
	fmt.Println("✅ hunt_phases table created")
}
