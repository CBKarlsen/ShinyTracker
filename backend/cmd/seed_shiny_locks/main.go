package main

import (
	"context"
	"log"
	"os"

	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/seeds"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	path := "seeds/shiny_locks.json"
	if len(os.Args) > 1 {
		path = os.Args[1]
	}

	ctx := context.Background()
	inserted, skipped, err := seeds.SeedShinyLocks(ctx, database.DB, path)
	if err != nil {
		log.Fatal("seed_shiny_locks: ", err)
	}
	log.Printf("shiny_locks seeded: %d inserted, %d skipped (unknown game)", inserted, skipped)
}
