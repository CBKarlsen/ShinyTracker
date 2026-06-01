// cmd/seed_availability_legacy populates pokemon_availability for Gen 5/6/7
// games (Black/White, Black 2/White 2, X/Y, Omega Ruby/Alpha Sapphire,
// Sun/Moon, Ultra Sun/Ultra Moon) by fetching their regional Pokédexes from
// the PokeAPI. These games are absent from the Switch-based CSV used by
// cmd/seed_availability, so without this seeder no egg (Masuda) rows are
// derived for them by cmd/seed.
//
// Obtainability proxy: regional-dex membership is used as the proxy for
// "legally obtainable in this game." This is accurate for the vast majority
// of species; version-exclusives and pure-trade species that appear in the
// regional dex but require trading are an accepted minor caveat, noted with
// ON CONFLICT DO NOTHING so the seeder is fully idempotent.
//
// Run this BEFORE cmd/seed so that deriveEggEncounters sees the full
// pokemon_availability set.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

// pokedexMapping describes which PokeAPI pokedex names cover each game title
// (as stored in the games table). Multiple pokedex names are unioned — XY uses
// three regional sub-dexes (central/coastal/mountain) that together constitute
// the full Kalos dex.
//
// PokeAPI pokedex IDs confirmed via /version-group/<slug> → .pokedexes:
//
//	black-white            → original-unova  (id 8,  156 entries)
//	black-2-white-2        → updated-unova   (id 9,  301 entries)
//	x-y                    → kalos-central   (id 12, 150 entries)
//	                          kalos-coastal   (id 13, 153 entries)
//	                          kalos-mountain  (id 14, 151 entries)
//	omega-ruby-alpha-sapphire → updated-hoenn (id 15, 211 entries)
//	sun-moon               → original-alola  (id 16, 302 entries)
//	ultra-sun-ultra-moon   → updated-alola   (id 21, 403 entries)
var pokedexMapping = []struct {
	gameTitle string
	pokedexes []string
}{
	{"Black/White", []string{"original-unova"}},
	{"Black 2/White 2", []string{"updated-unova"}},
	{"X/Y", []string{"kalos-central", "kalos-coastal", "kalos-mountain"}},
	{"Omega Ruby/Alpha Sapphire", []string{"updated-hoenn"}},
	{"Sun/Moon", []string{"original-alola"}},
	{"Ultra Sun/Ultra Moon", []string{"updated-alola"}},
}

// pokedexResponse is the subset of the PokeAPI /pokedex/<name> response we need.
type pokedexResponse struct {
	PokemonEntries []struct {
		EntryNumber    int `json:"entry_number"`
		PokemonSpecies struct {
			Name string `json:"name"`
			URL  string `json:"url"`
		} `json:"pokemon_species"`
	} `json:"pokemon_entries"`
}

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database: ", err)
	}
	defer database.CloseDB()

	ctx := context.Background()

	// Load game title → id from DB.
	gameIDs := loadGameIDs(ctx)

	totalInserted := 0
	totalSkipped := 0

	for _, mapping := range pokedexMapping {
		gameID, ok := gameIDs[mapping.gameTitle]
		if !ok {
			log.Fatalf("Game %q not found in games table — run cmd/seed or SeedGames first", mapping.gameTitle)
		}

		// Collect the union of species IDs across all regional sub-dexes for this game.
		speciesIDs := make(map[int]bool)
		for _, dexName := range mapping.pokedexes {
			ids, err := fetchPokedexSpeciesIDs(dexName)
			if err != nil {
				log.Fatalf("Failed to fetch pokedex %q: %v", dexName, err)
			}
			for _, id := range ids {
				speciesIDs[id] = true
			}
			log.Printf("  %s / %s: %d species", mapping.gameTitle, dexName, len(ids))
		}

		// Upsert availability rows. ON CONFLICT DO NOTHING makes this idempotent.
		inserted := 0
		skipped := 0
		for speciesID := range speciesIDs {
			tag, err := database.DB.Exec(ctx,
				`INSERT INTO pokemon_availability (pokemon_id, game_id)
				 VALUES ($1, $2)
				 ON CONFLICT DO NOTHING`,
				speciesID, gameID,
			)
			if err != nil {
				log.Printf("WARN  pokemon_id=%-4d game=%q: %v", speciesID, mapping.gameTitle, err)
				continue
			}
			if tag.RowsAffected() == 0 {
				skipped++
			} else {
				inserted++
			}
		}
		log.Printf("%-30s total species=%d  inserted=%d  skipped=%d",
			mapping.gameTitle, len(speciesIDs), inserted, skipped)
		totalInserted += inserted
		totalSkipped += skipped
	}

	fmt.Printf("\nDone — inserted: %d  skipped (already existed): %d\n", totalInserted, totalSkipped)
}

// fetchPokedexSpeciesIDs retrieves all pokemon-species IDs listed in a PokeAPI
// regional pokedex. The species ID equals the National Dex number and is the
// same value used as pokemon.id in our DB (both sourced from PokeAPI).
func fetchPokedexSpeciesIDs(dexName string) ([]int, error) {
	url := fmt.Sprintf("https://pokeapi.co/api/v2/pokedex/%s/", dexName)

	// Simple linear retry: PokeAPI is public and occasionally slow.
	client := &http.Client{Timeout: 30 * time.Second}
	var resp *http.Response
	var err error
	for attempt := 1; attempt <= 3; attempt++ {
		resp, err = client.Get(url)
		if err == nil && resp.StatusCode == http.StatusOK {
			break
		}
		if err != nil {
			log.Printf("  attempt %d: GET %s: %v", attempt, url, err)
		} else {
			log.Printf("  attempt %d: GET %s: HTTP %d", attempt, url, resp.StatusCode)
			resp.Body.Close()
			err = fmt.Errorf("HTTP %d", resp.StatusCode)
		}
		if attempt < 3 {
			time.Sleep(time.Duration(attempt) * 2 * time.Second)
		}
	}
	if err != nil {
		return nil, fmt.Errorf("GET %s: %w", url, err)
	}
	defer resp.Body.Close()

	var dex pokedexResponse
	if err := json.NewDecoder(resp.Body).Decode(&dex); err != nil {
		return nil, fmt.Errorf("decode %s: %w", url, err)
	}

	ids := make([]int, 0, len(dex.PokemonEntries))
	for _, entry := range dex.PokemonEntries {
		id := idFromSpeciesURL(entry.PokemonSpecies.URL)
		if id <= 0 {
			log.Printf("  WARN: could not extract ID from species URL %q", entry.PokemonSpecies.URL)
			continue
		}
		ids = append(ids, id)
	}
	return ids, nil
}

// idFromSpeciesURL extracts the trailing numeric ID from a PokeAPI
// pokemon-species URL such as ".../pokemon-species/494/".
func idFromSpeciesURL(u string) int {
	u = strings.TrimRight(u, "/")
	i := strings.LastIndex(u, "/")
	if i < 0 || i+1 >= len(u) {
		return 0
	}
	var id int
	_, err := fmt.Sscan(u[i+1:], &id)
	if err != nil {
		return 0
	}
	return id
}

func loadGameIDs(ctx context.Context) map[string]int {
	rows, err := database.DB.Query(ctx, "SELECT id, title FROM games")
	if err != nil {
		log.Fatal("Failed to load game IDs: ", err)
	}
	defer rows.Close()
	ids := make(map[string]int)
	for rows.Next() {
		var id int
		var title string
		if err := rows.Scan(&id, &title); err == nil {
			ids[title] = id
		}
	}
	return ids
}
