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
		"ALTER TABLE hunt_methods ADD COLUMN IF NOT EXISTS is_recommended BOOLEAN NOT NULL DEFAULT FALSE")
	if err != nil {
		log.Fatal("Migration failed:", err)
	}

	fmt.Println("✅ is_recommended column added to hunt_methods table")
}
