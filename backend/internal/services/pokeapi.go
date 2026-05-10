package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
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
	} `json:"sprites"`
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
		} `json:"encounter_details"`
	} `json:"version_details"`
}

var versionMap = map[string]string{
	"red": "Red/Blue/Yellow", "blue": "Red/Blue/Yellow", "yellow": "Red/Blue/Yellow",
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
	"scarlet": "Scarlet/Violet", "violet": "Scarlet/Violet",
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
	resp, err := http.Get("https://pokeapi.co/api/v2/pokemon?limit=1025")
	if err != nil {
		return fmt.Errorf("failed to fetch list: %w", err)
	}
	defer resp.Body.Close()

	var listResp PokeAPIListResponse
	if err := json.NewDecoder(resp.Body).Decode(&listResp); err != nil {
		return fmt.Errorf("failed to decode list: %w", err)
	}

	urls := make(chan string, len(listResp.Results))
	for _, result := range listResp.Results {
		urls <- result.URL
	}
	close(urls)

	var wg sync.WaitGroup
	// Limit concurrency to avoid hitting rate limits or db connection limits
	numWorkers := 5

	for i := 0; i < numWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for url := range urls {
				processPokemon(url)
			}
		}()
	}

	wg.Wait()
	log.Println("PokeAPI sync completed!")
	return nil
}

func processPokemon(url string) {
	time.Sleep(100 * time.Millisecond)

	resp, err := http.Get(url)
	if err != nil {
		log.Printf("Failed to fetch %s: %v", url, err)
		return
	}
	defer resp.Body.Close()

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

	_, err = database.DB.Exec(context.Background(),
		`INSERT INTO pokemon (id, name, sprite_url, types) 
		 VALUES ($1, $2, $3, $4) 
		 ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, sprite_url = EXCLUDED.sprite_url, types = EXCLUDED.types`,
		p.ID, p.Name, p.Sprites.FrontDefault, typesJSON)

	if err != nil {
		log.Printf("Failed to insert pokemon %s: %v", p.Name, err)
		return
	}

	// Also sync encounters for this pokemon
	syncEncounters(p.ID)
}

func syncEncounters(pokemonID int) {
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

	gameMethodsFound := make(map[int]map[string]bool)

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

			if gameMethodsFound[gameID] == nil {
				gameMethodsFound[gameID] = make(map[string]bool)
			}

			for _, ed := range vd.EncounterDetails {
				methodName := ed.Method.Name

				if gameMethodsFound[gameID][methodName] {
					continue // Already recorded this method for this game
				}
				gameMethodsFound[gameID][methodName] = true

				avgTime := 30
				baseRolls := 1
				charmRolls := 2 // Standard shiny charm is +2 rolls

				_, err = database.DB.Exec(context.Background(),
					`INSERT INTO hunt_methods (pokemon_id, game_id, method_name, avg_time_seconds, base_rolls, charm_rolls)
					 VALUES ($1, $2, $3, $4, $5, $6)`,
					pokemonID, gameID, methodName, avgTime, baseRolls, charmRolls)
				if err != nil {
					log.Printf("Failed to insert encounter for %d in %d: %v", pokemonID, gameID, err)
				}
			}
		}
	}

	// Always inject Masuda Method for any game this Pokemon was found in natively
	for gameID := range gameMethodsFound {
		_, _ = database.DB.Exec(context.Background(),
			`INSERT INTO hunt_methods (pokemon_id, game_id, method_name, avg_time_seconds, base_rolls, charm_rolls)
			 VALUES ($1, $2, $3, $4, $5, $6)`,
			pokemonID, gameID, "masuda-method", 45, 6, 2)
	}
}

func SeedGames() error {
	log.Println("Seeding games...")
	games := []struct {
		Title      string
		Generation int
		BaseOdds   int
	}{
		{"Red/Blue/Yellow", 1, 8192},
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
