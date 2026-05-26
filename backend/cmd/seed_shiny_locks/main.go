package main

import (
	"context"
	"encoding/json"
	"log"
	"os"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

type lockEntry struct {
	PokemonID int      `json:"pokemon_id"`
	Games     []string `json:"games"`
}
type lockFile struct {
	Locks []lockEntry `json:"locks"`
}

func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	path := "seeds/shiny_locks.json"
	if len(os.Args) > 1 {
		path = os.Args[1]
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		log.Fatalf("read %q: %v", path, err)
	}
	var lf lockFile
	if err := json.Unmarshal(raw, &lf); err != nil {
		log.Fatalf("parse %q: %v", path, err)
	}

	rows, err := database.DB.Query(context.Background(), "SELECT id, title FROM games")
	if err != nil {
		log.Fatal("fetch games:", err)
	}
	gameID := map[string]int{}
	for rows.Next() {
		var id int
		var title string
		if err := rows.Scan(&id, &title); err == nil {
			gameID[title] = id
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		log.Fatal("fetch games (rows):", err)
	}

	inserted, skipped := 0, 0
	for _, e := range lf.Locks {
		for _, title := range e.Games {
			gid, ok := gameID[title]
			if !ok {
				log.Printf("warn: unknown game title %q (pokemon #%d) — skipped", title, e.PokemonID)
				skipped++
				continue
			}
			ct, err := database.DB.Exec(context.Background(),
				`INSERT INTO shiny_locks (pokemon_id, game_id) VALUES ($1, $2)
				 ON CONFLICT DO NOTHING`,
				e.PokemonID, gid)
			if err != nil {
				log.Printf("warn: insert lock #%d/%s: %v", e.PokemonID, title, err)
				continue
			}
			if ct.RowsAffected() > 0 {
				inserted++
			} else {
				skipped++
			}
		}
	}
	log.Printf("shiny_locks seeded: %d inserted, %d skipped", inserted, skipped)
}
