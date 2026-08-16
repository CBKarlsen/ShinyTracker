// cmd/seed_champions populates pokemon_availability for Pokemon Champions from
// PokeAPI's champions Pokedex.
//
// RUNBOOK: run after migrations/025_champions.sql. Safe to re-run — the write
// is an idempotent upsert on the (pokemon_id, game_id) pair.
//
// The Champions roster is NOT a mainline game's dex. Pokemon arrive through
// Pokemon HOME from the core series and Pokemon GO, limited to species that
// exist in Champions, and the pool GROWS IN BATCHES alongside new Regulation
// Sets — so this seeder is not a one-time run.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

const championsGameID = 18

var httpClient = &http.Client{Timeout: 30 * time.Second}

type pokedexResponse struct {
	PokemonEntries []struct {
		PokemonSpecies struct {
			Name string `json:"name"`
		} `json:"pokemon_species"`
	} `json:"pokemon_entries"`
}

func main() { os.Exit(run()) }

func run() int {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Print(err)
		return 1
	}
	defer database.CloseDB()

	resp, err := httpClient.Get("https://pokeapi.co/api/v2/pokedex/champions")
	if err != nil {
		log.Printf("fetch champions pokedex: %v", err)
		return 1
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		log.Printf("fetch champions pokedex: status %d", resp.StatusCode)
		return 1
	}

	var dex pokedexResponse
	if err := json.NewDecoder(resp.Body).Decode(&dex); err != nil {
		log.Printf("decode champions pokedex: %v", err)
		return 1
	}

	seeded, missing := 0, 0
	for _, entry := range dex.PokemonEntries {
		name := entry.PokemonSpecies.Name
		// The pokedex names SPECIES; our pokemon table is keyed on the PokeAPI
		// pokemon name, which matches for every default form. A species whose
		// default form is suffixed will not match, and is reported rather than
		// silently skipped.
		var pokemonID int
		err := database.DB.QueryRow(context.Background(),
			`SELECT id FROM pokemon WHERE name = $1`, name).Scan(&pokemonID)
		if err != nil {
			log.Printf("no pokemon row for champions species %q", name)
			missing++
			continue
		}

		if _, err := database.DB.Exec(context.Background(),
			`INSERT INTO pokemon_availability (pokemon_id, game_id)
			 VALUES ($1, $2) ON CONFLICT DO NOTHING`,
			pokemonID, championsGameID); err != nil {
			log.Printf("upsert availability for %q: %v", name, err)
			missing++
			continue
		}
		seeded++
	}

	log.Printf("seeded %d champions species (%d unmatched)", seeded, missing)
	if seeded == 0 {
		// ponytail: nothing seeded means the pokedex fetch or the name join is
		// broken, not that Champions has no roster. Exit non-zero so a script
		// or a human notices.
		return 1
	}
	fmt.Println("done")
	return 0
}
