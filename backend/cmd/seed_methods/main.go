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

func getOdds(method string) (int, int, int) {
	m := strings.ToLower(method)
	switch {
	case strings.Contains(m, "masuda"):
		return 6, 8, 45
	case strings.Contains(m, "outbreak"):
		return 3, 5, 15
	case strings.Contains(m, "dynamax adventure"):
		return 14, 41, 900
	case strings.Contains(m, "isolated") || strings.Contains(m, "sandwich"):
		return 4, 6, 15
	case strings.Contains(m, "soft reset"):
		return 1, 3, 40
	case strings.Contains(m, "radar"):
		return 41, 41, 60
	case strings.Contains(m, "gift") || strings.Contains(m, "fossil"):
		return 1, 1, 30
	default:
		return 1, 3, 20
	}
}

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	file, err := os.Open("Copy of Switch-Based Shiny Living Dex - Database of Easiest Hunting Methods - Shinies.csv")
	if err != nil {
		log.Fatalf("Failed to open CSV: %v", err)
	}
	defer file.Close()

	records, err := csv.NewReader(file).ReadAll()
	if err != nil {
		log.Fatal("Failed to parse CSV:", err)
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

	inserted, skipped := 0, 0

	for i, row := range records {
		if i == 0 || len(row) < 5 {
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
		dbGameTitle, exists := gameTitleMap[csvGame]
		if !exists {
			continue
		}

		gameID, ok := gameIDs[dbGameTitle]
		if !ok {
			continue
		}

		methodName := strings.TrimSpace(row[4])
		if methodName == "" || methodName == "-" || methodName == "UNAVAILABLE" {
			continue
		}

		baseRolls, charmRolls, avgTime := getOdds(methodName)

		tag, err := database.DB.Exec(context.Background(),
			`INSERT INTO hunt_methods (pokemon_id, game_id, method_name, avg_time_seconds, base_rolls, charm_rolls)
			 SELECT $1, $2, $3, $4, $5, $6
			 WHERE NOT EXISTS (
				 SELECT 1 FROM hunt_methods
				 WHERE pokemon_id = $1 AND game_id = $2 AND method_name = $3
			 )`,
			pokemonID, gameID, methodName, avgTime, baseRolls, charmRolls,
		)

		if err != nil {
			log.Printf("FAIL pokemon_id=%d game=%q method=%q: %v", pokemonID, dbGameTitle, methodName, err)
			continue
		}

		if tag.RowsAffected() > 0 {
			inserted++
		} else {
			skipped++
		}
	}

	fmt.Printf("\n✅ Method Injection Complete — inserted: %d  skipped: %d\n", inserted, skipped)
}
