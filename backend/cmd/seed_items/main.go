// cmd/seed_items seeds held items from PokeAPI.
//
// RUNBOOK: run after migrations/023_teams.sql. Safe to re-run — every write is an
// upsert on the slug, which is PokeAPI's own stable identifier.
//
// Only the competitively relevant categories are fetched. PokeAPI carries ~2000 items
// including every berry, TM and key item; a team builder needs the ~100 a set can hold.
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

// PokeAPI item categories a held item can come from.
var heldItemCategories = []string{
	"held-items", "choice", "type-enhancement", "bad-held-items",
	"training", "species-specific", "type-protection", "picky-healing",
}

var httpClient = &http.Client{Timeout: 30 * time.Second}

type categoryResponse struct {
	Items []struct {
		Name string `json:"name"`
		URL  string `json:"url"`
	} `json:"items"`
}

type itemResponse struct {
	Name    string `json:"name"`
	Sprites struct {
		Default string `json:"default"`
	} `json:"sprites"`
	Names []struct {
		Name     string `json:"name"`
		Language struct {
			Name string `json:"name"`
		} `json:"language"`
	} `json:"names"`
	EffectEntries []struct {
		ShortEffect string `json:"short_effect"`
		Language    struct {
			Name string `json:"name"`
		} `json:"language"`
	} `json:"effect_entries"`
}

func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal(err)
	}
	defer database.CloseDB()

	seen := map[string]bool{}
	total := 0
	attempted := 0

	for _, category := range heldItemCategories {
		url := fmt.Sprintf("https://pokeapi.co/api/v2/item-category/%s", category)
		var cat categoryResponse
		if err := getJSON(url, &cat); err != nil {
			log.Printf("category %s: %v", category, err)
			continue
		}

		for _, ref := range cat.Items {
			if seen[ref.Name] {
				continue
			}
			seen[ref.Name] = true
			attempted++

			var item itemResponse
			if err := getJSON(ref.URL, &item); err != nil {
				log.Printf("item %s: %v", ref.Name, err)
			} else if err := upsert(item); err != nil {
				log.Printf("upsert %s: %v", ref.Name, err)
			} else {
				total++
			}
			// ponytail: sleep on every item iteration, not just successful paths,
			// so rate-limit errors self-heal rather than cascade
			time.Sleep(100 * time.Millisecond) // same courtesy delay as cmd/seed
		}
	}

	failed := attempted - total
	log.Printf("seeded %d items (%d attempted, %d failed)", total, attempted, failed)
	if total == 0 {
		// ponytail: exit non-zero if seeding was wholly unsuccessful;
		// upgrade to failure-rate-based thresholds if partial seeds become acceptable
		os.Exit(1)
	}
}

func getJSON(url string, into any) error {
	resp, err := httpClient.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("status %d", resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(into)
}

func upsert(item itemResponse) error {
	displayName := item.Name
	for _, n := range item.Names {
		if n.Language.Name == "en" {
			displayName = n.Name
			break
		}
	}

	description := ""
	for _, e := range item.EffectEntries {
		if e.Language.Name == "en" {
			description = e.ShortEffect
			break
		}
	}

	_, err := database.DB.Exec(context.Background(),
		`INSERT INTO items (slug, name, sprite_url, description)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (slug) DO UPDATE SET
		   name = EXCLUDED.name,
		   sprite_url = EXCLUDED.sprite_url,
		   description = EXCLUDED.description`,
		item.Name, displayName, item.Sprites.Default, description)
	return err
}
