// Package seeds contains shared seeding helpers that are called by both the
// primary cmd/seed pipeline and the standalone ad-hoc seed commands.
package seeds

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

// lockEntry is one entry in seeds/shiny_locks.json.
type lockEntry struct {
	PokemonID int      `json:"pokemon_id"`
	Games     []string `json:"games"`
}

// lockFile is the top-level structure of seeds/shiny_locks.json.
type lockFile struct {
	Locks []lockEntry `json:"locks"`
}

// SeedShinyLocks reads the JSON file at path, resolves game titles against the
// games table, then TRUNCATE-then-inserts the full resolved set inside a single
// transaction. A failure at any point rolls back so the table is never left
// empty. The return value is the number of rows inserted.
//
// path is typically "seeds/shiny_locks.json" but can be overridden for testing
// or ad-hoc runs (cmd/seed_shiny_locks accepts it as an optional CLI argument).
//
// This function is the single source of truth for shiny_locks seeding; both
// cmd/seed and cmd/seed_shiny_locks delegate here so they can never drift.
func SeedShinyLocks(ctx context.Context, db *pgxpool.Pool, path string) (inserted int, skipped int, err error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return 0, 0, fmt.Errorf("read %q: %w", path, err)
	}
	var lf lockFile
	if err := json.Unmarshal(raw, &lf); err != nil {
		return 0, 0, fmt.Errorf("parse %q: %w", path, err)
	}

	// Load game title → id mapping.
	rows, err := db.Query(ctx, "SELECT id, title FROM games")
	if err != nil {
		return 0, 0, fmt.Errorf("fetch games: %w", err)
	}
	gameID := map[string]int{}
	for rows.Next() {
		var id int
		var title string
		if scanErr := rows.Scan(&id, &title); scanErr == nil {
			gameID[title] = id
		}
	}
	rows.Close()
	if rowErr := rows.Err(); rowErr != nil {
		return 0, 0, fmt.Errorf("fetch games (rows): %w", rowErr)
	}

	// Resolve all entries to (pokemon_id, game_id) pairs. Validate before
	// opening the transaction so we can fail fast without leaving the table
	// in a partial state.
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
				log.Printf("shiny_locks: warn: unknown game title %q (pokemon #%d) — skipped", title, e.PokemonID)
				skipped++
				continue
			}
			inserts = append(inserts, resolved{pokemonID: e.PokemonID, gameID: gid, title: title})
		}
	}

	// Single transaction: TRUNCATE then re-insert the full resolved set.
	// A failure at any point rolls back so the table is never left empty.
	tx, err := db.Begin(ctx)
	if err != nil {
		return 0, skipped, fmt.Errorf("begin transaction: %w", err)
	}

	if _, err := tx.Exec(ctx, "TRUNCATE shiny_locks"); err != nil {
		_ = tx.Rollback(ctx)
		return 0, skipped, fmt.Errorf("truncate shiny_locks: %w", err)
	}

	for _, r := range inserts {
		if _, err := tx.Exec(ctx,
			`INSERT INTO shiny_locks (pokemon_id, game_id) VALUES ($1, $2)`,
			r.pokemonID, r.gameID,
		); err != nil {
			_ = tx.Rollback(ctx)
			return 0, skipped, fmt.Errorf("insert lock #%d/%s: %w — rolled back", r.pokemonID, r.title, err)
		}
		inserted++
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, skipped, fmt.Errorf("commit shiny_locks: %w", err)
	}
	return inserted, skipped, nil
}
