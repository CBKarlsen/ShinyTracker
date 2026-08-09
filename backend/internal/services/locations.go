package services

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"encoding/json"

	"github.com/casper/shinytracker/internal/database"
)

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

	if err := loadGameIDs(); err != nil {
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

	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for id := range jobs {
				seedLocationsFor(id)
			}
		}()
	}
	wg.Wait()

	log.Println("Locations seeded.")
	return reportLocationCounts()
}

func seedLocationsFor(pokemonID int) {
	time.Sleep(50 * time.Millisecond)

	url := fmt.Sprintf("https://pokeapi.co/api/v2/pokemon/%d/encounters", pokemonID)
	resp, err := http.Get(url)
	if err != nil {
		log.Printf("Failed to fetch encounters for %d: %v", pokemonID, err)
		return
	}
	defer resp.Body.Close()

	var encounters []PokeAPIEncounter
	if err := json.NewDecoder(resp.Body).Decode(&encounters); err != nil {
		log.Printf("Failed to decode encounters for %d: %v", pokemonID, err)
		return
	}

	gameIDMutex.Lock()
	ids := make(map[string]int, len(gameIDCache))
	for k, v := range gameIDCache {
		ids[k] = v
	}
	gameIDMutex.Unlock()

	locs := ParseLocations(pokemonID, encounters, ids)

	ctx := context.Background()
	// Delete-then-insert makes the command idempotent without an upsert path.
	if _, err := database.DB.Exec(ctx,
		"DELETE FROM pokemon_locations WHERE pokemon_id = $1", pokemonID); err != nil {
		log.Printf("Failed to clear locations for %d: %v", pokemonID, err)
		return
	}
	for _, l := range locs {
		_, err := database.DB.Exec(ctx,
			`INSERT INTO pokemon_locations
			   (pokemon_id, game_id, version, area, terrain, pokeapi_method,
			    min_level, max_level, chance, conditions)
			 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
			l.PokemonID, l.GameID, l.Version, l.Area, l.Terrain, l.PokeAPIMethod,
			l.MinLevel, l.MaxLevel, l.Chance, l.Conditions)
		if err != nil {
			log.Printf("Failed to insert location for %d (%s): %v", pokemonID, l.Area, err)
		}
	}
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
