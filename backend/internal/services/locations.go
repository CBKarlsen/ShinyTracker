package services

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"sync"
	"sync/atomic"
	"time"

	"encoding/json"

	"github.com/casper/shinytracker/internal/database"
	"github.com/jackc/pgx/v5"
)

// httpClient bounds every PokeAPI request in this file to 30s: DefaultClient
// has no timeout, and across ~1,025 requests one hung connection would park a
// worker permanently.
var httpClient = &http.Client{Timeout: 30 * time.Second}

// SeedLocations repopulates pokemon_locations for every Pokemon from PokeAPI's
// /encounters endpoint.
//
// Independent of cmd/sync on purpose: cmd/sync truncates hunt_methods (cascading
// method_availability to 0), so it cannot be re-run casually against the live
// database. This command touches only pokemon_locations and is safe to re-run.
//
// Legendaries and mythicals are INCLUDED here, unlike SyncEncounterKinds -- see
// the package comment on that function. This table stores raw location facts and
// derives no encounter kind, so the misclassification risk does not apply.
func SeedLocations() error {
	log.Println("Seeding Pokemon locations from PokeAPI...")

	// Restricted to Gen 2-7, matching what the schema comment and spec promise.
	// versionMap DOES have keys for Sword/Shield, Scarlet/Violet, Legends: Arceus,
	// BDSP and LGPE, and PokeAPI does serve real encounter data for them -- but
	// coverage would be silently partial: DLC version keys (e.g.
	// the-isle-of-armor-sword/shield) are absent from versionMap, so Isle of
	// Armor/Crown Tundra areas would just vanish with no error. An honest empty
	// state for Gen 8/9 beats a quietly-incomplete one; that generation gets its
	// own slice once the DLC keys are added. This deliberately does not reuse
	// loadGameIDs()/gameIDCache, which cover every generation.
	gameIDs, err := loadLocationGameIDs()
	if err != nil {
		return fmt.Errorf("failed to load game IDs: %w", err)
	}

	rows, err := database.DB.Query(context.Background(),
		"SELECT id FROM pokemon ORDER BY id")
	if err != nil {
		return fmt.Errorf("failed to list pokemon: %w", err)
	}
	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()
	log.Printf("Fetching locations for %d pokemon...", len(ids))

	jobs := make(chan int, len(ids))
	for _, id := range ids {
		jobs <- id
	}
	close(jobs)

	var failures atomic.Int64
	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for id := range jobs {
				if err := seedLocationsFor(id, gameIDs); err != nil {
					failures.Add(1)
				}
			}
		}()
	}
	wg.Wait()

	log.Println("Locations seeded.")
	if n := failures.Load(); n > 0 {
		return fmt.Errorf("%d pokemon failed to seed locations (see logs above)", n)
	}
	return reportLocationCounts()
}

// loadLocationGameIDs builds a title -> id map restricted to Gen 2-7, the
// generations this table supports. Deliberately separate from
// loadGameIDs()/gameIDCache, which is unrestricted and shared with other
// syncs; reusing it here would silently let Gen 8/9 back in.
func loadLocationGameIDs() (map[string]int, error) {
	rows, err := database.DB.Query(context.Background(),
		"SELECT id, title FROM games WHERE generation BETWEEN 2 AND 7")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	ids := make(map[string]int)
	for rows.Next() {
		var id int
		var title string
		if err := rows.Scan(&id, &title); err != nil {
			return nil, err
		}
		ids[title] = id
	}
	return ids, rows.Err()
}

// fetchEncounters fetches and decodes the /encounters payload for one Pokemon.
// A 429 or 5xx is retried once after a short backoff; any other non-200, or a
// second failure, is returned as an error rather than silently skipped.
func fetchEncounters(pokemonID int) ([]PokeAPIEncounter, error) {
	url := fmt.Sprintf("https://pokeapi.co/api/v2/pokemon/%d/encounters", pokemonID)

	var lastErr error
	for attempt := 0; attempt < 2; attempt++ {
		if attempt > 0 {
			time.Sleep(500 * time.Millisecond)
		}
		resp, err := httpClient.Get(url)
		if err != nil {
			lastErr = err
			continue
		}
		if resp.StatusCode != http.StatusOK {
			status := resp.StatusCode
			resp.Body.Close()
			lastErr = fmt.Errorf("unexpected status %d", status)
			if status == http.StatusTooManyRequests || status >= 500 {
				continue // retryable
			}
			break
		}
		var encounters []PokeAPIEncounter
		err = json.NewDecoder(resp.Body).Decode(&encounters)
		resp.Body.Close()
		if err != nil {
			return nil, fmt.Errorf("decode: %w", err)
		}
		return encounters, nil
	}
	return nil, lastErr
}

// seedLocationsFor refreshes one Pokemon's rows and reports failure to the
// caller: a DELETE that succeeds followed by an insert that fails must not be
// silently swallowed with hundreds of thousands of writes in play.
func seedLocationsFor(pokemonID int, gameIDs map[string]int) error {
	time.Sleep(50 * time.Millisecond)

	encounters, err := fetchEncounters(pokemonID)
	if err != nil {
		log.Printf("Failed to fetch encounters for %d: %v", pokemonID, err)
		return err
	}

	locs := ParseLocations(pokemonID, encounters, gameIDs)

	ctx := context.Background()
	// Delete-then-insert makes the command idempotent without an upsert path.
	if _, err := database.DB.Exec(ctx,
		"DELETE FROM pokemon_locations WHERE pokemon_id = $1", pokemonID); err != nil {
		log.Printf("Failed to clear locations for %d: %v", pokemonID, err)
		return err
	}
	if len(locs) == 0 {
		return nil
	}

	// Batch insert: one Exec per row (Magikarp alone is ~3,900 rows, ~450k
	// across the dex) would be 15-45 minutes of pure round-trip time against
	// remote Supabase. CopyFrom sends the whole species in one round trip.
	copyRows := make([][]any, len(locs))
	for i, l := range locs {
		copyRows[i] = []any{
			l.PokemonID, l.GameID, l.Version, l.Area, l.Terrain, l.PokeAPIMethod,
			l.MinLevel, l.MaxLevel, l.Chance, l.Conditions,
		}
	}
	if _, err := database.DB.CopyFrom(ctx,
		pgx.Identifier{"pokemon_locations"},
		[]string{"pokemon_id", "game_id", "version", "area", "terrain", "pokeapi_method",
			"min_level", "max_level", "chance", "conditions"},
		pgx.CopyFromRows(copyRows),
	); err != nil {
		log.Printf("Failed to insert locations for %d: %v", pokemonID, err)
		return err
	}
	return nil
}

// reportLocationCounts logs a per-game row count and fails loudly if any Gen 2-7
// game ended up with zero rows -- a silently-empty crawl is the realistic
// failure mode here, and it would otherwise look like "this game has no data".
func reportLocationCounts() error {
	rows, err := database.DB.Query(context.Background(), `
		SELECT g.id, g.title, g.generation, COUNT(pl.id)
		FROM games g
		LEFT JOIN pokemon_locations pl ON pl.game_id = g.id
		GROUP BY g.id, g.title, g.generation
		ORDER BY g.generation, g.id`)
	if err != nil {
		return err
	}
	defer rows.Close()

	var empty []string
	for rows.Next() {
		var id, gen, count int
		var title string
		if err := rows.Scan(&id, &title, &gen, &count); err != nil {
			return err
		}
		log.Printf("  gen %d  %-32s %6d rows", gen, title, count)
		if gen >= 2 && gen <= 7 && count == 0 {
			empty = append(empty, title)
		}
	}
	if len(empty) > 0 {
		return fmt.Errorf("no locations seeded for Gen 2-7 games: %v", empty)
	}
	return rows.Err()
}
