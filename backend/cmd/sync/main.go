package main

import (
	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/services"
	"github.com/joho/godotenv"
	"log"
)

func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal(err)
	}
	defer database.CloseDB()

	if err := services.SyncPokemonData(); err != nil {
		log.Fatal(err)
	}
}
