package main

import (
	"context"
	"encoding/csv"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

var gameTitleMap = map[string]string{
	"SV":                "Scarlet/Violet",
	"SV DLC":            "Scarlet/Violet",
	"SV + Transfer":     "Scarlet/Violet",
	"SV DLC + Transfer": "Scarlet/Violet",
	"SwSh":              "Sword/Shield",
	"SwSh DLC":          "Sword/Shield",
	"PLA":               "Legends: Arceus",
	"PLA + Transfer":    "Legends: Arceus",
	"BDSP":              "Brilliant Diamond/Shining Pearl",
	"LGPE":              "Let's Go Pikachu/Eevee",
}

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	seedFile := "Copy of Switch-Based Shiny Living Dex - Database of Easiest Hunting Methods - Shinies.csv"
	if len(os.Args) > 1 {
		seedFile = os.Args[1]
	}

	file, err := os.Open(seedFile)
	if err != nil {
		log.Fatalf("Failed to read seed file %q: %v", seedFile, err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		log.Fatalf("Failed to parse CSV: %v", err)
	}

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

	for i, row := range records {
		if i == 0 {
			continue
		}

		pokedexStr := strings.TrimSpace(row[1])
		if pokedexStr == "" {
			continue
		}

		pokedexFloat, err := strconv.ParseFloat(pokedexStr, 64)
		if err != nil {
			continue
		}
		pokemonID := int(pokedexFloat)

		csvGame := strings.TrimSpace(row[3])
		if csvGame == "UNAVAILABLE" || csvGame == "HOME" || csvGame == "Pokémon Go" || csvGame == "" {
			continue
		}

		dbGameTitle, exists := gameTitleMap[csvGame]
		if !exists {
			log.Printf("SKIP  pokemon_id=%-4d game=%q — unmapped CSV game string", pokemonID, csvGame)
			skipped++
			continue
		}

		gameID, ok := gameIDs[dbGameTitle]
		if !ok {
			log.Printf("SKIP  pokemon_id=%-4d game=%q — not in games table", pokemonID, dbGameTitle)
			skipped++
			continue
		}

		tag, err := database.DB.Exec(context.Background(),
			`INSERT INTO pokemon_availability (pokemon_id, game_id)
			 VALUES ($1, $2)
			 ON CONFLICT DO NOTHING`,
			pokemonID, gameID,
		)
		if err != nil {
			log.Printf("FAIL  pokemon_id=%-4d game=%q — %v", pokemonID, dbGameTitle, err)
			failed++
			continue
		}

		if tag.RowsAffected() == 0 {
			fmt.Printf("SKIP  pokemon_id=%-4d game=%q (already exists)\n", pokemonID, dbGameTitle)
			skipped++
		} else {
			fmt.Printf("OK    pokemon_id=%-4d game=%q\n", pokemonID, dbGameTitle)
			inserted++
		}
	}

	fmt.Printf("\nDone — inserted: %d  skipped: %d  failed: %d\n", inserted, skipped, failed)
}
