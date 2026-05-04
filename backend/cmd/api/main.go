package main

import (
	"log"
	"net/http"

	"github.com/casper/shinytracker/internal/api"
	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, relying on environment variables")
	}

	if err := database.ConnectDB(); err != nil {
		log.Fatalf("Database connection failed: %v", err)
	}
	defer database.CloseDB()

	r := api.NewRouter()

	port := "8080"
	log.Printf("Server starting on port %s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatalf("Server error: %v", err)
	}
}
