//go:build ignore

package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load()
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL must be set")
	}

	pool, err := pgxpool.New(context.Background(), dbURL)
	if err != nil {
		log.Fatal("Unable to connect to database:", err)
	}
	defer pool.Close()

	const pokemonID = 129
	const pokemonName = "Magikarp"

	// Fetch all games
	rows, err := pool.Query(context.Background(), "SELECT id, title, generation FROM games ORDER BY id ASC")
	if err != nil {
		log.Fatal("Failed to fetch games:", err)
	}
	type game struct {
		id         int
		title      string
		generation int
	}
	var games []game
	for rows.Next() {
		var g game
		if err := rows.Scan(&g.id, &g.title, &g.generation); err == nil {
			games = append(games, g)
		}
	}
	rows.Close()

	// Fetch encounters for Magikarp, grouped by game
	encRows, err := pool.Query(context.Background(),
		`SELECT game_id, method_name FROM encounters WHERE pokemon_id = $1 ORDER BY game_id ASC`,
		pokemonID)
	if err != nil {
		log.Fatal("Failed to fetch encounters:", err)
	}
	encountersByGame := make(map[int][]string)
	for encRows.Next() {
		var gameID int
		var method string
		if err := encRows.Scan(&gameID, &method); err == nil {
			encountersByGame[gameID] = append(encountersByGame[gameID], method)
		}
	}
	encRows.Close()

	// Report
	fmt.Printf("Encounter coverage for %s (ID %d)\n", pokemonName, pokemonID)
	fmt.Println("============================================")

	var missing []string
	for _, g := range games {
		methods, ok := encountersByGame[g.id]
		if !ok || len(methods) == 0 {
			fmt.Printf("  MISSING  Gen %d  %s\n", g.generation, g.title)
			missing = append(missing, g.title)
		} else {
			fmt.Printf("  OK       Gen %d  %-40s  methods: %v\n", g.generation, g.title, methods)
		}
	}

	fmt.Println("============================================")
	if len(missing) == 0 {
		fmt.Println("All games have encounter data.")
	} else {
		fmt.Printf("%d game(s) missing encounter data:\n", len(missing))
		for _, t := range missing {
			fmt.Printf("  - %s\n", t)
		}
	}
}
