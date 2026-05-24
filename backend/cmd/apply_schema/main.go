package main

import (
	"context"
	"log"
	"os"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(".env"); err != nil {
		log.Println("No .env file found")
	}
	if err := database.ConnectDB(); err != nil {
		log.Fatal(err)
	}
	defer database.CloseDB()
    
    // Drop the tables that changed constraints so they can be recreated cleanly
    _, err := database.DB.Exec(context.Background(), "DROP TABLE IF EXISTS method_availability, method_exceptions, method_rules, method_games, hunt_methods CASCADE")
    if err != nil {
        log.Fatal(err)
    }

	schema, err := os.ReadFile("schema.sql")
	if err != nil {
		log.Fatal(err)
	}

	_, err = database.DB.Exec(context.Background(), string(schema))
	if err != nil {
		log.Fatal(err)
	}
    log.Println("Schema applied successfully!")
}
