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

	_, err := database.DB.Exec(context.Background(), "TRUNCATE TABLE encounters CASCADE;")
	if err != nil {
		log.Fatal("Failed to truncate encounters:", err)
	}

	fmt.Println("✅ encounters table truncated successfully.")
}
