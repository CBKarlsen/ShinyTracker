package main

import (
	"context"
	"log"
	"os"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	ctx := context.Background()

	// Drop old table to recreate with new schema
	_, err := database.DB.Exec(ctx, "DROP TABLE IF EXISTS user_hunts CASCADE")
	if err != nil {
		log.Fatal(err)
	}
	_, err = database.DB.Exec(ctx, "DROP TABLE IF EXISTS hunt_methods CASCADE")
	if err != nil {
		log.Fatal(err)
	}
	_, err = database.DB.Exec(ctx, "DROP TABLE IF EXISTS method_rules CASCADE")
	if err != nil {
		log.Fatal(err)
	}
	_, err = database.DB.Exec(ctx, "DROP TABLE IF EXISTS method_exceptions CASCADE")
	if err != nil {
		log.Fatal(err)
	}
	_, err = database.DB.Exec(ctx, "DROP TABLE IF EXISTS method_availability CASCADE")
	if err != nil {
		log.Fatal(err)
	}

	schema, err := os.ReadFile("schema.sql")
	if err != nil {
		log.Fatal(err)
	}

	_, err = database.DB.Exec(ctx, string(schema))
	if err != nil {
		log.Fatal("Failed to execute schema.sql:", err)
	}

	log.Println("Schema migration complete!")
}
