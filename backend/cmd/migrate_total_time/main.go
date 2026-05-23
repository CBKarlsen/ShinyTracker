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
		"ALTER TABLE user_hunts ADD COLUMN IF NOT EXISTS total_time_seconds INT NOT NULL DEFAULT 0")
	if err != nil {
		log.Fatal("Migration failed:", err)
	}

	fmt.Println("✅ total_time_seconds column added to user_hunts table")
}
