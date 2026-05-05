package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

type SeedEntry struct {
	GameTitle      string `json:"game_title"`
	PokemonID      int    `json:"pokemon_id"`
	MethodName     string `json:"method_name"`
	AvgTimeSeconds int    `json:"avg_time_seconds"`
	BaseRolls      int    `json:"base_rolls"`
	CharmRolls     int    `json:"charm_rolls"`
}

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	seedFile := "internal/database/seeds/paldea.json"
	if len(os.Args) > 1 {
		seedFile = os.Args[1]
	}

	data, err := os.ReadFile(seedFile)
	if err != nil {
		log.Fatalf("Failed to read seed file %q: %v", seedFile, err)
	}

	var entries []SeedEntry
	if err := json.Unmarshal(data, &entries); err != nil {
		log.Fatalf("Failed to parse seed file: %v", err)
	}

	// Build game title -> id map
	rows, err := database.DB.Query(context.Background(), "SELECT id, title FROM games")
	if err != nil {
		log.Fatal("Failed to fetch games:", err)
	}
	gameIDs := make(map[string]int)
	for rows.Next() {
		var id int
		var title string
		if err := rows.Scan(&id, &title); err == nil {
			gameIDs[title] = id
		}
	}
	rows.Close()

	inserted, skipped, failed := 0, 0, 0

	for _, e := range entries {
		gameID, ok := gameIDs[e.GameTitle]
		if !ok {
			log.Printf("SKIP  unknown game %q — not in games table", e.GameTitle)
			skipped++
			continue
		}

		tag, err := database.DB.Exec(context.Background(),
			`INSERT INTO encounters (pokemon_id, game_id, method_name, avg_time_seconds, base_rolls, charm_rolls)
			 SELECT $1, $2, $3, $4, $5, $6
			 WHERE NOT EXISTS (
			     SELECT 1 FROM encounters
			     WHERE pokemon_id = $1 AND game_id = $2 AND method_name = $3
			 )`,
			e.PokemonID, gameID, e.MethodName, e.AvgTimeSeconds, e.BaseRolls, e.CharmRolls,
		)
		if err != nil {
			log.Printf("FAIL  pokemon_id=%-4d game=%q method=%s — %v", e.PokemonID, e.GameTitle, e.MethodName, err)
			failed++
			continue
		}

		if tag.RowsAffected() == 0 {
			fmt.Printf("SKIP  pokemon_id=%-4d game=%q method=%s (already exists)\n", e.PokemonID, e.GameTitle, e.MethodName)
			skipped++
		} else {
			fmt.Printf("OK    pokemon_id=%-4d game=%q method=%s\n", e.PokemonID, e.GameTitle, e.MethodName)
			inserted++
		}
	}

	fmt.Printf("\nDone — inserted: %d  skipped: %d  failed: %d\n", inserted, skipped, failed)
}
