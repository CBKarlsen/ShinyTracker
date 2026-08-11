package main

import (
	"log"

	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/services"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	if err := services.SeedLocations(); err != nil {
		log.Fatal("Failed to seed locations: ", err)
	}
}
