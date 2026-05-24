package main

import (
	"log"

	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/services"
	"github.com/joho/godotenv"
)

// Derives `wild` encounter-kind records for all Pokemon from PokeAPI's
// /encounters endpoint into pokemon_game_encounter. Run after the Pokemon
// table is populated; the method seeder (cmd/seed) will also auto-run this
// once if no wild rows exist.
func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	if err := services.SyncEncounterKinds(); err != nil {
		log.Fatal(err)
	}
}
