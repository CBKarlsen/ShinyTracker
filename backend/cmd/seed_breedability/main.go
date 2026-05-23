package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

type PokemonSpeciesResponse struct {
	EggGroups []struct {
		Name string `json:"name"`
	} `json:"egg_groups"`
}

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	ctx := context.Background()

	// Fetch all pokemon IDs from database
	rows, err := database.DB.Query(ctx, "SELECT id, name FROM pokemon ORDER BY id")
	if err != nil {
		log.Fatal("Failed to query pokemon:", err)
	}
	defer rows.Close()

	type pokemonInfo struct {
		id   int
		name string
	}

	var pokemonList []pokemonInfo
	for rows.Next() {
		var p pokemonInfo
		if err := rows.Scan(&p.id, &p.name); err == nil {
			pokemonList = append(pokemonList, p)
		}
	}
	rows.Close()
	log.Printf("Loaded %d pokemon from database.", len(pokemonList))

	// Channel for distributing tasks
	jobs := make(chan pokemonInfo, len(pokemonList))
	for _, p := range pokemonList {
		jobs <- p
	}
	close(jobs)

	var wg sync.WaitGroup
	numWorkers := 10

	// Mutex to protect database operations and prints
	var dbMutex sync.Mutex
	var nonBreedablesCount int

	for i := 0; i < numWorkers; i++ {
		wg.Add(1)
		go func(workerID int) {
			defer wg.Done()
			client := &http.Client{Timeout: 5 * time.Second}

			for p := range jobs {
				// Retry loop for robustness
				var speciesResp PokemonSpeciesResponse
				success := false

				url := fmt.Sprintf("https://pokeapi.co/api/v2/pokemon-species/%d/", p.id)
				for retry := 0; retry < 3; retry++ {
					resp, err := client.Get(url)
					if err != nil {
						time.Sleep(200 * time.Millisecond)
						continue
					}

					if resp.StatusCode == http.StatusNotFound {
						// Some PokeAPI pokemon don't have a matching species (e.g. special forms that are separate in pokemon table but shares a species).
						// If species not found, we can assume it can breed unless it's a known form, or check fallback.
						resp.Body.Close()
						success = true // Skip and treat as breedable by default
						break
					}

					if resp.StatusCode != http.StatusOK {
						resp.Body.Close()
						time.Sleep(200 * time.Millisecond)
						continue
					}

					err = json.NewDecoder(resp.Body).Decode(&speciesResp)
					resp.Body.Close()
					if err == nil {
						success = true
						break
					}
					time.Sleep(200 * time.Millisecond)
				}

				if !success {
					log.Printf("[Worker %d] Failed to fetch breedability for %s (ID: %d) after retries", workerID, p.name, p.id)
					continue
				}

				canBreed := true
				for _, eg := range speciesResp.EggGroups {
					if eg.Name == "no-eggs" {
						canBreed = false
						break
					}
				}

				if !canBreed {
					dbMutex.Lock()
					nonBreedablesCount++
					dbMutex.Unlock()

					// Update database
					_, err := database.DB.Exec(context.Background(),
						"UPDATE pokemon SET can_breed = FALSE WHERE id = $1",
						p.id,
					)
					if err != nil {
						log.Printf("Failed to update can_breed for %s (ID: %d): %v", p.name, p.id, err)
					} else {
						log.Printf("Marked %s (ID: %d) as non-breedable", p.name, p.id)
					}
				}

				// Sleep slightly to avoid hitting PokeAPI limits
				time.Sleep(50 * time.Millisecond)
			}
		}(i)
	}

	wg.Wait()
	log.Printf("Seeding complete! Marked %d pokemon as non-breedable out of %d total.", nonBreedablesCount, len(pokemonList))
}
