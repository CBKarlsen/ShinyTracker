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

type speciesResponse struct {
	Varieties []struct {
		IsDefault bool `json:"is_default"`
		Pokemon   struct {
			Name string `json:"name"`
		} `json:"pokemon"`
	} `json:"varieties"`
}

func main() { os.Exit(run()) }

// resolvePokemonID finds the pokemon table row for a Champions Pokedex
// species entry. The Pokedex names the SPECIES; the pokemon table is keyed
// on the PokeAPI pokemon name, which matches the species name for every
// default form. It does not match for species whose default form is
// suffixed (aegislash-shield, lycanroc-midday, ...), so a miss on the exact
// name falls back to /pokemon-species/{name}'s varieties array and takes
// the one PokeAPI marks is_default -- that is authoritative about which row
// is the species' default form, unlike guessing from a name prefix.
func resolvePokemonID(name string) (int, error) {
	var pokemonID int
	err := database.DB.QueryRow(context.Background(),
		`SELECT id FROM pokemon WHERE name = $1`, name).Scan(&pokemonID)
	if err == nil {
		return pokemonID, nil
	}

	resp, httpErr := httpClient.Get(fmt.Sprintf("https://pokeapi.co/api/v2/pokemon-species/%s", name))
	if httpErr != nil {
		return 0, fmt.Errorf("exact name miss, species fetch failed: %w", httpErr)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("exact name miss, species fetch status %d", resp.StatusCode)
	}

	var species speciesResponse
	if err := json.NewDecoder(resp.Body).Decode(&species); err != nil {
		return 0, fmt.Errorf("exact name miss, species decode failed: %w", err)
	}

	for _, v := range species.Varieties {
		if !v.IsDefault {
			continue
		}
		err := database.DB.QueryRow(context.Background(),
			`SELECT id FROM pokemon WHERE name = $1`, v.Pokemon.Name).Scan(&pokemonID)
		if err != nil {
			return 0, fmt.Errorf("default variety %q has no pokemon row: %w", v.Pokemon.Name, err)
		}
		return pokemonID, nil
	}
	return 0, fmt.Errorf("species has no default variety")
}

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
		pokemonID, err := resolvePokemonID(name)
		if err != nil {
			log.Printf("no pokemon row for champions species %q: %v", name, err)
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
