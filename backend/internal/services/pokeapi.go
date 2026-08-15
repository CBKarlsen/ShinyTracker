package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/casper/shinytracker/internal/database"
)

type PokeAPIListResponse struct {
	Results []struct {
		Name string `json:"name"`
		URL  string `json:"url"`
	} `json:"results"`
}

type PokeAPIPokemonResponse struct {
	ID      int    `json:"id"`
	Name    string `json:"name"`
	Sprites struct {
		FrontDefault string `json:"front_default"`
		FrontShiny   string `json:"front_shiny"`
	} `json:"sprites"`
	Species struct {
		URL string `json:"url"`
	} `json:"species"`
	Types []struct {
		Type struct {
			Name string `json:"name"`
		} `json:"type"`
	} `json:"types"`
}

type PokeAPIEncounter struct {
	LocationArea struct {
		Name string `json:"name"`
	} `json:"location_area"`
	VersionDetails []struct {
		Version struct {
			Name string `json:"name"`
		} `json:"version"`
		EncounterDetails []struct {
			Method struct {
				Name string `json:"name"`
			} `json:"method"`
			MinLevel        int `json:"min_level"`
			MaxLevel        int `json:"max_level"`
			Chance          int `json:"chance"`
			ConditionValues []struct {
				Name string `json:"name"`
			} `json:"condition_values"`
		} `json:"encounter_details"`
	} `json:"version_details"`
}

// versionMap translates PokeAPI version names to the game-group titles used in
// the games table. Gen-1 versions (red/blue/yellow) are deliberately absent:
// shinies do not exist in Gen 1, so those encounter rows are never needed.
var versionMap = map[string]string{
	"gold": "Gold/Silver/Crystal", "silver": "Gold/Silver/Crystal", "crystal": "Gold/Silver/Crystal",
	"ruby": "Ruby/Sapphire/Emerald", "sapphire": "Ruby/Sapphire/Emerald", "emerald": "Ruby/Sapphire/Emerald",
	"firered": "FireRed/LeafGreen", "leafgreen": "FireRed/LeafGreen",
	"diamond": "Diamond/Pearl/Platinum", "pearl": "Diamond/Pearl/Platinum", "platinum": "Diamond/Pearl/Platinum",
	"heartgold": "HeartGold/SoulSilver", "soulsilver": "HeartGold/SoulSilver",
	"black": "Black/White", "white": "Black/White",
	"black-2": "Black 2/White 2", "white-2": "Black 2/White 2",
	"x": "X/Y", "y": "X/Y",
	"omega-ruby": "Omega Ruby/Alpha Sapphire", "alpha-sapphire": "Omega Ruby/Alpha Sapphire",
	"sun": "Sun/Moon", "moon": "Sun/Moon",
	"ultra-sun": "Ultra Sun/Ultra Moon", "ultra-moon": "Ultra Sun/Ultra Moon",
	"lets-go-pikachu": "Let's Go Pikachu/Eevee", "lets-go-eevee": "Let's Go Pikachu/Eevee",
	"sword": "Sword/Shield", "shield": "Sword/Shield",
	"brilliant-diamond": "Brilliant Diamond/Shining Pearl", "shining-pearl": "Brilliant Diamond/Shining Pearl",
	"legends-arceus": "Legends: Arceus",
	"scarlet":        "Scarlet/Violet", "violet": "Scarlet/Violet",
}

// methodTerrain buckets PokeAPI encounter method names into the coarse terrain
// classes used for hunt-method availability. Anything not listed (rock-smash,
// headbutt, cave-spots, gifts, …) falls through to "other". Note: PokeAPI's
// "walk" conflates tall grass and cave floors, so cave-only Pokemon land in the
// grass bucket — an accepted limitation.
var methodTerrain = map[string]string{
	"walk":            "grass",
	"grass-spots":     "grass",
	"dark-grass":      "grass",
	"yellow-flowers":  "grass",
	"purple-flowers":  "grass",
	"red-flowers":     "grass",
	"old-rod":         "fishing",
	"good-rod":        "fishing",
	"super-rod":       "fishing",
	"super-rod-spots": "fishing",
	"surf":            "surf",
	"surf-spots":      "surf",
	"seaweed":         "surf",
}

func terrainForMethod(method string) string {
	if t, ok := methodTerrain[method]; ok {
		return t
	}
	return "other"
}

// nonWildMethods lists PokeAPI encounter methods that are not "stand here and
// find one": ParseLocations excludes them so they never surface as a place to
// hunt. Left unfiltered, generic wild routes (requires_terrain IS NULL) accept
// terrain "other", and 100%-chance non-wild rows like a Game Corner prize
// outrank real wild spots under chance-descending sort.
var nonWildMethods = map[string]bool{
	"gift":     true, // handed over the counter (Game Corner prizes, etc.), not encountered
	"gift-egg": true, // starter/gift eggs -- not a wild encounter, has no location in the hunting sense
	"static":   true, // scripted stationary encounter (legendaries, gift Pokemon)
	"wanderer": true, // roaming legendary; "location" is the whole region, not one area
	"max-raid": true, // Dynamax Adventures / Max Raid Den, a queue not a place to walk
	"only-one": true, // one-time scripted encounter, not repeatable wild hunting
}

// isColosseumMethod reports whether method is one of the Colosseum/XD
// "colosseum-..." family, which are all scripted battles, not wild encounters.
func isColosseumMethod(method string) bool {
	return strings.HasPrefix(method, "colosseum-")
}

var gameIDCache map[string]int
var gameIDMutex sync.Mutex

func loadGameIDs() error {
	gameIDMutex.Lock()
	defer gameIDMutex.Unlock()

	gameIDCache = make(map[string]int)
	rows, err := database.DB.Query(context.Background(), "SELECT id, title FROM games")
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var id int
		var title string
		if err := rows.Scan(&id, &title); err == nil {
			gameIDCache[title] = id
		}
	}
	return nil
}

func SyncPokemonData() error {
	log.Println("Starting PokeAPI sync...")

	// 1. Seed Games first
	if err := SeedGames(); err != nil {
		return fmt.Errorf("failed to seed games: %w", err)
	}

	// 2. Load Game IDs for mapping
	if err := loadGameIDs(); err != nil {
		return fmt.Errorf("failed to load game IDs: %w", err)
	}

	// 3. Clear hunt_methods table to avoid duplicates during resync
	_, _ = database.DB.Exec(context.Background(), "TRUNCATE TABLE hunt_methods CASCADE")

	// Fetch up to Gen 9
	resp, err := httpClient.Get("https://pokeapi.co/api/v2/pokemon?limit=1025")
	if err != nil {
		return fmt.Errorf("failed to fetch list: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("failed to fetch list: unexpected status %d", resp.StatusCode)
	}

	var listResp PokeAPIListResponse
	if err := json.NewDecoder(resp.Body).Decode(&listResp); err != nil {
		return fmt.Errorf("failed to decode list: %w", err)
	}

	urls := make(chan string, len(listResp.Results))
	for _, result := range listResp.Results {
		urls <- result.URL
	}
	close(urls)

	// parentPairs collects (childID, parentID) for the post-insert backfill pass.
	parentPairs := make(chan [2]int, len(listResp.Results))

	var wg sync.WaitGroup
	// Limit concurrency to avoid hitting rate limits or db connection limits
	numWorkers := 5

	for i := 0; i < numWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for url := range urls {
				processPokemon(url, parentPairs)
			}
		}()
	}

	wg.Wait()
	close(parentPairs)

	// Second pass: backfill evolves_from_id now that all pokemon rows exist,
	// so the FK reference to the parent always resolves.
	for pair := range parentPairs {
		childID, parentID := pair[0], pair[1]
		if _, err := database.DB.Exec(context.Background(),
			`UPDATE pokemon SET evolves_from_id = $2 WHERE id = $1`,
			childID, parentID); err != nil {
			log.Printf("warn: evolves_from for #%d -> #%d: %v", childID, parentID, err)
		}
	}

	log.Println("PokeAPI sync completed!")
	return nil
}

type PokeAPISpeciesResponse struct {
	IsLegendary        bool `json:"is_legendary"`
	IsMythical         bool `json:"is_mythical"`
	EvolvesFromSpecies *struct {
		Name string `json:"name"`
		URL  string `json:"url"`
	} `json:"evolves_from_species"`
}

func processPokemon(url string, parentPairs chan<- [2]int) {
	time.Sleep(100 * time.Millisecond)

	resp, err := httpClient.Get(url)
	if err != nil {
		log.Printf("Failed to fetch %s: %v", url, err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		log.Printf("Failed to fetch %s: unexpected status %d", url, resp.StatusCode)
		return
	}

	var p PokeAPIPokemonResponse
	if err := json.NewDecoder(resp.Body).Decode(&p); err != nil {
		log.Printf("Failed to decode %s: %v", url, err)
		return
	}

	var types []string
	for _, t := range p.Types {
		types = append(types, t.Type.Name)
	}
	typesJSON, _ := json.Marshal(types)

	var isLegendary, isMythical bool
	var evolvesFromID *int
	if p.Species.URL != "" {
		sResp, sErr := httpClient.Get(p.Species.URL)
		if sErr == nil {
			defer sResp.Body.Close()
			var species PokeAPISpeciesResponse
			if sResp.StatusCode == http.StatusOK && json.NewDecoder(sResp.Body).Decode(&species) == nil {
				isLegendary = species.IsLegendary
				isMythical = species.IsMythical
				if species.EvolvesFromSpecies != nil {
					if id := idFromSpeciesURL(species.EvolvesFromSpecies.URL); id > 0 {
						evolvesFromID = &id
					}
				}
			}
		}
	}

	_, err = database.DB.Exec(context.Background(),
		`INSERT INTO pokemon (id, name, sprite_url, shiny_sprite_url, types, is_legendary, is_mythical)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, sprite_url = EXCLUDED.sprite_url, shiny_sprite_url = EXCLUDED.shiny_sprite_url, types = EXCLUDED.types, is_legendary = EXCLUDED.is_legendary, is_mythical = EXCLUDED.is_mythical`,
		p.ID, p.Name, p.Sprites.FrontDefault, p.Sprites.FrontShiny, typesJSON, isLegendary, isMythical)

	if err != nil {
		log.Printf("Failed to insert pokemon %s: %v", p.Name, err)
		return
	}

	// Queue the parent pointer for the post-insert backfill pass.
	if evolvesFromID != nil {
		parentPairs <- [2]int{p.ID, *evolvesFromID}
	}
}

// idFromSpeciesURL extracts the trailing numeric id from a PokeAPI
// pokemon-species URL like ".../pokemon-species/129/".
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

// SyncEncounterKinds derives `wild` encounter-kind records for every Pokemon in
// the database from PokeAPI's /encounters endpoint. A Pokemon that has any wild
// location-area encounter in a game's versions gets a (pokemon, game, 'wild') row
// in pokemon_game_encounter. static/raid/egg kinds are populated elsewhere.
func SyncEncounterKinds() error {
	log.Println("Deriving wild encounter kinds from PokeAPI...")

	if err := loadGameIDs(); err != nil {
		return fmt.Errorf("failed to load game IDs: %w", err)
	}

	// Clear existing wild rows so the re-sync repopulates them per terrain;
	// otherwise stale terrain='none' wild rows would linger alongside the new
	// grass/surf/fishing rows. Non-wild kinds (egg/static/raid) are untouched.
	if _, err := database.DB.Exec(context.Background(),
		"DELETE FROM pokemon_game_encounter WHERE kind = 'wild'"); err != nil {
		return fmt.Errorf("failed to clear wild encounter rows: %w", err)
	}

	// Legendaries/mythicals are excluded: PokeAPI reports their stationary
	// encounters as location encounters, which would be wrongly classified as
	// wild. Their kinds come exclusively from curated static/raid records.
	rows, err := database.DB.Query(context.Background(),
		"SELECT id FROM pokemon WHERE is_legendary = false AND is_mythical = false ORDER BY id")
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
	log.Printf("Fetching wild encounters for %d pokemon...", len(ids))

	jobs := make(chan int, len(ids))
	for _, id := range ids {
		jobs <- id
	}
	close(jobs)

	var wg sync.WaitGroup
	numWorkers := 8
	for i := 0; i < numWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for id := range jobs {
				syncWildEncounters(id)
			}
		}()
	}
	wg.Wait()

	log.Println("Wild encounter kinds derived.")
	return nil
}

func syncWildEncounters(pokemonID int) {
	time.Sleep(50 * time.Millisecond)

	url := fmt.Sprintf("https://pokeapi.co/api/v2/pokemon/%d/encounters", pokemonID)
	resp, err := httpClient.Get(url)
	if err != nil {
		log.Printf("Failed to fetch encounters for %d: %v", pokemonID, err)
		return
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		log.Printf("Failed to fetch encounters for %d: unexpected status %d", pokemonID, resp.StatusCode)
		return
	}

	var encounters []PokeAPIEncounter
	if err := json.NewDecoder(resp.Body).Decode(&encounters); err != nil {
		log.Printf("Failed to decode encounters for %d: %v", pokemonID, err)
		return
	}

	// Collect the set of (game, terrain) pairs where this Pokemon has a wild
	// encounter, derived from each encounter's PokeAPI method name.
	type gameTerrain struct {
		gameID  int
		terrain string
	}
	wild := make(map[gameTerrain]bool)
	for _, enc := range encounters {
		for _, vd := range enc.VersionDetails {
			gameTitle, ok := versionMap[vd.Version.Name]
			if !ok {
				continue
			}
			gameIDMutex.Lock()
			gameID, ok := gameIDCache[gameTitle]
			gameIDMutex.Unlock()
			if !ok {
				continue
			}
			for _, ed := range vd.EncounterDetails {
				wild[gameTerrain{gameID, terrainForMethod(ed.Method.Name)}] = true
			}
		}
	}

	for gt := range wild {
		_, err = database.DB.Exec(context.Background(),
			`INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
			 VALUES ($1, $2, 'wild', $3) ON CONFLICT DO NOTHING`,
			pokemonID, gt.gameID, gt.terrain)
		if err != nil {
			log.Printf("Failed to insert wild terrain for %d in %d (%s): %v", pokemonID, gt.gameID, gt.terrain, err)
		}
	}
}

func SeedGames() error {
	log.Println("Seeding games...")
	// Red/Blue/Yellow (Gen 1) is intentionally absent: shinies do not exist in
	// Gen 1, so there is nothing to track there. The earliest supported game is
	// Gold/Silver/Crystal (Gen 2), where the shiny DV mechanic was introduced.
	games := []struct {
		Title      string
		Generation int
		BaseOdds   int
	}{
		{"Gold/Silver/Crystal", 2, 8192},
		{"Ruby/Sapphire/Emerald", 3, 8192},
		{"FireRed/LeafGreen", 3, 8192},
		{"Diamond/Pearl/Platinum", 4, 8192},
		{"HeartGold/SoulSilver", 4, 8192},
		{"Black/White", 5, 8192},
		{"Black 2/White 2", 5, 8192},
		{"X/Y", 6, 4096},
		{"Omega Ruby/Alpha Sapphire", 6, 4096},
		{"Sun/Moon", 7, 4096},
		{"Ultra Sun/Ultra Moon", 7, 4096},
		{"Let's Go Pikachu/Eevee", 7, 4096},
		{"Sword/Shield", 8, 4096},
		{"Brilliant Diamond/Shining Pearl", 8, 4096},
		{"Legends: Arceus", 8, 4096},
		{"Scarlet/Violet", 9, 4096},
	}

	for _, g := range games {
		_, err := database.DB.Exec(context.Background(),
			`INSERT INTO games (title, generation, base_odds)
			 SELECT $1, $2, $3
			 WHERE NOT EXISTS (SELECT 1 FROM games WHERE title = $1)`,
			g.Title, g.Generation, g.BaseOdds)
		if err != nil {
			log.Printf("Failed to seed game %s: %v", g.Title, err)
		}
	}
	log.Println("Games seeded!")
	return nil
}

// LocationRow is one parsed encounter slot, ready for insertion into
// pokemon_locations.
type LocationRow struct {
	PokemonID     int
	GameID        int
	Version       string
	Area          string
	Terrain       string
	PokeAPIMethod string
	MinLevel      int
	MaxLevel      int
	Chance        int
	Conditions    []string
}

// ParseLocations flattens a PokeAPI /encounters payload into location rows.
//
// Versions absent from versionMap are skipped, which is how Gen 1 (no shinies,
// no game row) and Gen 8/9 (no PokeAPI encounter data) fall out without a
// special case. Game titles absent from gameIDs are skipped rather than
// defaulted, so a missing game row can never produce game_id 0.
//
// PokeAPI repeats an encounter slot once per condition combination, so
// identical rows are deduped on the full natural key.
func ParseLocations(pokemonID int, encounters []PokeAPIEncounter, gameIDs map[string]int) []LocationRow {
	type key struct {
		gameID         int
		version        string
		area           string
		method         string
		minLvl, maxLvl int
		chance         int
		conditions     string
	}
	seen := make(map[key]bool)
	var rows []LocationRow

	for _, enc := range encounters {
		for _, vd := range enc.VersionDetails {
			gameTitle, ok := versionMap[vd.Version.Name]
			if !ok {
				continue
			}
			gameID, ok := gameIDs[gameTitle]
			if !ok {
				continue
			}
			for _, ed := range vd.EncounterDetails {
				if nonWildMethods[ed.Method.Name] || isColosseumMethod(ed.Method.Name) {
					continue
				}
				conds := make([]string, 0, len(ed.ConditionValues))
				for _, cv := range ed.ConditionValues {
					conds = append(conds, cv.Name)
				}
				sort.Strings(conds)

				k := key{
					gameID:     gameID,
					version:    vd.Version.Name,
					area:       enc.LocationArea.Name,
					method:     ed.Method.Name,
					minLvl:     ed.MinLevel,
					maxLvl:     ed.MaxLevel,
					chance:     ed.Chance,
					conditions: strings.Join(conds, ","),
				}
				if seen[k] {
					continue
				}
				seen[k] = true

				rows = append(rows, LocationRow{
					PokemonID:     pokemonID,
					GameID:        gameID,
					Version:       vd.Version.Name,
					Area:          enc.LocationArea.Name,
					Terrain:       terrainForMethod(ed.Method.Name),
					PokeAPIMethod: ed.Method.Name,
					MinLevel:      ed.MinLevel,
					MaxLevel:      ed.MaxLevel,
					Chance:        ed.Chance,
					Conditions:    conds,
				})
			}
		}
	}
	return rows
}
