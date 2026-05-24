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
    
    _, err := database.DB.Exec(context.Background(), "ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS is_legendary BOOLEAN NOT NULL DEFAULT FALSE; ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS is_mythical BOOLEAN NOT NULL DEFAULT FALSE;")
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
