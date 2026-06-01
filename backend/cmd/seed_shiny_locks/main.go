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

	// Validate all game titles before touching the DB so we can fail fast
	// without opening a transaction.
	skipped := 0
	type resolved struct {
		pokemonID int
		gameID    int
		title     string
	}
	var inserts []resolved
	for _, e := range lf.Locks {
		for _, title := range e.Games {
			gid, ok := gameID[title]
			if !ok {
				log.Printf("warn: unknown game title %q (pokemon #%d) — skipped", title, e.PokemonID)
				skipped++
				continue
			}
			inserts = append(inserts, resolved{pokemonID: e.PokemonID, gameID: gid, title: title})
		}
	}

	// Single transaction: TRUNCATE then re-insert the full resolved set.
	// A failure at any point rolls back so the table is never left empty.
	ctx := context.Background()
	tx, err := database.DB.Begin(ctx)
	if err != nil {
		log.Fatal("begin transaction:", err)
	}

	if _, err := tx.Exec(ctx, "TRUNCATE shiny_locks"); err != nil {
		_ = tx.Rollback(ctx)
		log.Fatal("truncate shiny_locks:", err)
	}

	inserted := 0
	for _, r := range inserts {
		if _, err := tx.Exec(ctx,
			`INSERT INTO shiny_locks (pokemon_id, game_id) VALUES ($1, $2)`,
			r.pokemonID, r.gameID,
		); err != nil {
			_ = tx.Rollback(ctx)
			log.Fatalf("insert lock #%d/%s: %v — rolled back", r.pokemonID, r.title, err)
		}
		inserted++
	}

	if err := tx.Commit(ctx); err != nil {
		log.Fatal("commit shiny_locks:", err)
	}
	log.Printf("shiny_locks seeded: %d inserted, %d skipped (unknown game)", inserted, skipped)
}
