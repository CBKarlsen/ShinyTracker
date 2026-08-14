// cmd/seed_pokedex seeds pokedex_entries (per-game regional Pokedex numbering)
// from PokeAPI's /api/v2/pokedex/{slug} endpoint. Idempotent: re-running
// upserts on (game_id, dex_slug, pokemon_id).
//
// The games table bundles version pairs (e.g. "Ruby/Sapphire/Emerald" is one
// row), so game_id -> dex slug(s) cannot be derived and is hardcoded below.
// Every slug was verified against the live `/api/v2/pokedex?limit=100` list
// before being hardcoded here (see PR notes) — a slug that PokeAPI does not
// recognize 404s and this command fails loudly rather than skipping it.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

// gameDex is one game's ordered list of PokeAPI pokedex slugs. Multi-dex
// games (e.g. X/Y's Central/Coastal/Mountain Kalos) list all of them; a
// Pokemon's dex_order is that slug's index in Dexes.
//
// Title, not a hardcoded id, is the key: games.id is a live SERIAL and the
// current values only look stable because a removed game left a gap at id 1.
// Every other seeder resolves game_id by title for the same reason.
type gameDex struct {
	Title string
	Dexes []string
}

// gameDexes maps a games.title to the PokeAPI pokedex slug(s) that provide its
// regional dex numbering. Diamond/Pearl/Platinum is one row here but D/P and
// Platinum number Sinnoh differently — the bundle gets Platinum's extended dex.
var gameDexes = []gameDex{
	{"Gold/Silver/Crystal", []string{"original-johto"}},
	{"Ruby/Sapphire/Emerald", []string{"hoenn"}},
	{"FireRed/LeafGreen", []string{"kanto"}},
	{"Diamond/Pearl/Platinum", []string{"extended-sinnoh"}},
	{"HeartGold/SoulSilver", []string{"updated-johto"}},
	{"Black/White", []string{"original-unova"}},
	{"Black 2/White 2", []string{"updated-unova"}},
	{"X/Y", []string{"kalos-central", "kalos-coastal", "kalos-mountain"}},
	{"Omega Ruby/Alpha Sapphire", []string{"updated-hoenn"}},
	{"Sun/Moon", []string{"original-melemele", "original-akala", "original-ulaula", "original-poni"}},
	{"Ultra Sun/Ultra Moon", []string{"updated-melemele", "updated-akala", "updated-ulaula", "updated-poni"}},
	{"Let's Go Pikachu/Eevee", []string{"letsgo-kanto"}},
	{"Sword/Shield", []string{"galar", "isle-of-armor", "crown-tundra"}},
	// BDSP is a D/P remake: its Sinnoh dex is the original 151-entry list, not
	// Platinum's extended 210. Verified against PokeAPI entry counts.
	{"Brilliant Diamond/Shining Pearl", []string{"original-sinnoh"}},
	{"Legends: Arceus", []string{"hisui"}},
	{"Scarlet/Violet", []string{"paldea", "kitakami", "blueberry"}},
}

type pokeAPIPokedexResponse struct {
	Names []struct {
		Language struct {
			Name string `json:"name"`
		} `json:"language"`
		Name string `json:"name"`
	} `json:"names"`
	PokemonEntries []struct {
		EntryNumber    int `json:"entry_number"`
		PokemonSpecies struct {
			URL string `json:"url"`
		} `json:"pokemon_species"`
	} `json:"pokemon_entries"`
}

// fetchPokedex fetches and decodes a single PokeAPI pokedex. A non-200 status
// (e.g. an unrecognized slug 404ing) is returned as an error so the caller
// can fail loudly instead of silently seeding a partial game.
func fetchPokedex(slug string) (*pokeAPIPokedexResponse, error) {
	url := fmt.Sprintf("https://pokeapi.co/api/v2/pokedex/%s", slug)
	resp, err := http.Get(url)
	if err != nil {
		return nil, fmt.Errorf("GET %s: %w", url, err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("GET %s: unexpected status %d (unknown pokedex slug?)", url, resp.StatusCode)
	}

	var out pokeAPIPokedexResponse
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil {
		return nil, fmt.Errorf("decode %s: %w", url, err)
	}
	return &out, nil
}

// englishName picks the "en" localization out of a PokeAPI names list,
// falling back to the slug if English is somehow absent.
func englishName(names []struct {
	Language struct {
		Name string `json:"name"`
	} `json:"language"`
	Name string `json:"name"`
}, fallback string) string {
	for _, n := range names {
		if n.Language.Name == "en" {
			return n.Name
		}
	}
	return fallback
}

// idFromSpeciesURL extracts the trailing numeric id from a PokeAPI
// pokemon-species URL like ".../pokemon-species/129/". Duplicated locally
// rather than importing internal/services' unexported copy, matching the
// existing precedent in cmd/seed_availability_legacy.
func idFromSpeciesURL(u string) int {
	u = strings.TrimRight(u, "/")
	i := strings.LastIndex(u, "/")
	if i < 0 || i+1 >= len(u) {
		return 0
	}
	n, err := strconv.Atoi(u[i+1:])
	if err != nil {
		return 0
	}
	return n
}

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	ctx := context.Background()

	// Species ids not present in our pokemon table are skipped (counted, not
	// fatal) rather than tripping the pokedex_entries -> pokemon FK.
	knownPokemon := map[int]bool{}
	rows, err := database.DB.Query(ctx, "SELECT id FROM pokemon")
	if err != nil {
		log.Fatal("failed to load pokemon ids:", err)
	}
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err == nil {
			knownPokemon[id] = true
		}
	}
	rows.Close()

	upserted, unknownSpecies := 0, 0

	for _, g := range gameDexes {
		var gameID int
		if err := database.DB.QueryRow(ctx,
			"SELECT id FROM games WHERE title = $1", g.Title).Scan(&gameID); err != nil {
			log.Fatalf("game %q: not found in games table (%v)", g.Title, err)
		}

		for order, slug := range g.Dexes {
			time.Sleep(100 * time.Millisecond)

			dex, err := fetchPokedex(slug)
			if err != nil {
				log.Fatalf("game %q (id=%d), dex %q: %v", g.Title, gameID, slug, err)
			}
			dexName := englishName(dex.Names, slug)

			for _, entry := range dex.PokemonEntries {
				pokemonID := idFromSpeciesURL(entry.PokemonSpecies.URL)
				if !knownPokemon[pokemonID] {
					unknownSpecies++
					continue
				}

				_, err := database.DB.Exec(ctx,
					`INSERT INTO pokedex_entries (game_id, dex_slug, dex_name, dex_order, pokemon_id, entry_number)
					 VALUES ($1, $2, $3, $4, $5, $6)
					 ON CONFLICT (game_id, dex_slug, pokemon_id) DO UPDATE SET
					   dex_name = EXCLUDED.dex_name,
					   dex_order = EXCLUDED.dex_order,
					   entry_number = EXCLUDED.entry_number`,
					gameID, slug, dexName, order, pokemonID, entry.EntryNumber)
				if err != nil {
					log.Fatalf("game %q (id=%d), dex %q, pokemon_id=%d: %v", g.Title, gameID, slug, pokemonID, err)
				}
				upserted++
			}

			log.Printf("OK    game=%q dex=%q (%q) — %d entries", g.Title, slug, dexName, len(dex.PokemonEntries))
		}
	}

	log.Printf("Done — upserted: %d, skipped (species not in pokemon table): %d", upserted, unknownSpecies)
}
