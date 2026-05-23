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
		log.Fatal(err)
	}
	defer database.CloseDB()

	// 1. Get Pikachu's ID
	var pikachuID int
	var pikachuName string
	err := database.DB.QueryRow(context.Background(), "SELECT id, name FROM pokemon WHERE name = 'pikachu'").Scan(&pikachuID, &pikachuName)
	if err != nil {
		log.Fatalf("Pikachu not found: %v", err)
	}
	fmt.Printf("Pikachu: ID=%d, Name=%s\n", pikachuID, pikachuName)

	// 2. Get availability of Pikachu
	rows, err := database.DB.Query(context.Background(), `
		SELECT pa.game_id, g.title, g.generation
		FROM pokemon_availability pa
		JOIN games g ON pa.game_id = g.id
		WHERE pa.pokemon_id = $1
	`, pikachuID)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	fmt.Println("Pikachu availability:")
	for rows.Next() {
		var gameID int
		var title string
		var gen int
		rows.Scan(&gameID, &title, &gen)
		fmt.Printf("  GameID=%d, Title=%q, Gen=%d\n", gameID, title, gen)
	}
}
