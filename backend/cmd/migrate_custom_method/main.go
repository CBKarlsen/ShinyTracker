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
		"ALTER TABLE user_hunts ADD COLUMN IF NOT EXISTS custom_method_name TEXT")
	if err != nil {
		log.Fatal("Migration failed (add column):", err)
	}

	// Drop constraint first in case it exists with wrong definition, then re-add.
	_, _ = database.DB.Exec(context.Background(),
		"ALTER TABLE user_hunts DROP CONSTRAINT IF EXISTS chk_method_xor")

	_, err = database.DB.Exec(context.Background(), `
		ALTER TABLE user_hunts ADD CONSTRAINT chk_method_xor
		CHECK (NOT (hunt_method_id IS NOT NULL AND custom_method_name IS NOT NULL))`)
	if err != nil {
		log.Fatal("Migration failed (add constraint):", err)
	}

	fmt.Println("✅ custom_method_name column and chk_method_xor constraint added to user_hunts")
}
