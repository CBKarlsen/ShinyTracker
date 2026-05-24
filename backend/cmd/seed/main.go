package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/services"
	"github.com/joho/godotenv"
)

type HuntMethod struct {
	IDStr           string   `json:"id"`
	Games           []string `json:"games"`
	MethodName      string   `json:"method_name"`
	AvgTimeSeconds  int      `json:"avg_time_seconds"`
	BaseRolls       int      `json:"base_rolls"`
	CharmRolls      int      `json:"charm_rolls"`
	FormulaType     string   `json:"formula_type"`
	RequiresKind    string   `json:"requires_kind"`
	RequiresTerrain string   `json:"requires_terrain"`
}

// LegendaryEncounter is one curated entry describing the static/raid encounters
// for a single Pokemon. The covered game set is default_games plus the keys of
// overrides; default_games get default_kind, overrides get their own value.
type LegendaryEncounter struct {
	PokemonID    int               `json:"pokemon_id"`
	Name         string            `json:"name"`
	DefaultKind  string            `json:"default_kind"`
	DefaultGames []string          `json:"default_games"`
	Overrides    map[string]string `json:"overrides"`
}

var methodIDMap = make(map[string]int)
var validKinds = map[string]bool{"wild": true, "static": true, "raid": true, "egg": true}

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	ctx := context.Background()

	log.Println("Wiping method tables (keeping wild encounter kinds)...")
	if _, err := database.DB.Exec(ctx, `TRUNCATE TABLE hunt_methods, method_games, method_availability CASCADE`); err != nil {
		log.Fatal("Failed to truncate method tables: ", err)
	}
	// Curated/derived kinds are rebuilt every run; wild kinds come from the
	// PokeAPI sync and are preserved.
	if _, err := database.DB.Exec(ctx, `DELETE FROM pokemon_game_encounter WHERE kind IN ('egg','static','raid')`); err != nil {
		log.Fatal("Failed to clear derived/curated encounter kinds: ", err)
	}
	// Purge any wild rows for legendaries/mythicals: PokeAPI reports their
	// stationary encounters as locations, which must not become wild kinds.
	// Curated static/raid records are authoritative for these Pokemon.
	if _, err := database.DB.Exec(ctx, `
		DELETE FROM pokemon_game_encounter pge
		USING pokemon p
		WHERE pge.pokemon_id = p.id AND pge.kind = 'wild' AND (p.is_legendary OR p.is_mythical)
	`); err != nil {
		log.Fatal("Failed to purge legendary wild encounter kinds: ", err)
	}

	log.Println("Seeding hunt_methods...")
	seedMethods(ctx)

	log.Println("Ensuring wild encounter kinds are populated...")
	ensureWildEncounters(ctx)

	log.Println("Deriving egg encounter kinds...")
	deriveEggEncounters(ctx)

	log.Println("Seeding curated static/raid encounter kinds...")
	seedCuratedEncounters(ctx)

	log.Println("Computing method_availability...")
	computeAvailability(ctx)

	log.Println("Running invariant checks...")
	runInvariantChecks(ctx)

	log.Println("Seeding complete.")
}

func seedMethods(ctx context.Context) {
	data, err := os.ReadFile("seeds/hunt_methods.json")
	if err != nil {
		log.Fatal("Failed to read hunt_methods.json: ", err)
	}
	var methods []HuntMethod
	if err := json.Unmarshal(data, &methods); err != nil {
		log.Fatal("JSON parse error: ", err)
	}

	for _, m := range methods {
		if !validKinds[m.RequiresKind] {
			log.Fatalf("Method %q has missing/invalid requires_kind %q", m.MethodName, m.RequiresKind)
		}

		var id int
		err := database.DB.QueryRow(ctx,
			`INSERT INTO hunt_methods (method_name, avg_time_seconds, base_rolls, charm_rolls, formula_type, requires_kind, requires_terrain)
			 VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, '')) RETURNING id`,
			m.MethodName, m.AvgTimeSeconds, m.BaseRolls, m.CharmRolls, m.FormulaType, m.RequiresKind, m.RequiresTerrain,
		).Scan(&id)
		if err != nil {
			log.Fatalf("Failed to insert method %s: %v", m.MethodName, err)
		}

		methodIDMap[m.IDStr] = id

		for _, gameTitle := range m.Games {
			var gameID int
			err = database.DB.QueryRow(ctx, "SELECT id FROM games WHERE title = $1", gameTitle).Scan(&gameID)
			if err != nil {
				log.Fatalf("Failed to find game %s: %v", gameTitle, err)
			}

			_, err = database.DB.Exec(ctx, "INSERT INTO method_games (method_id, game_id) VALUES ($1, $2)", id, gameID)
			if err != nil {
				log.Fatalf("Failed to map method %s to game %s: %v", m.MethodName, gameTitle, err)
			}
		}
	}
}

// ensureWildEncounters populates `wild` kinds from PokeAPI if none exist yet.
// Otherwise it leaves them in place — refresh explicitly via cmd/sync_encounters.
func ensureWildEncounters(ctx context.Context) {
	var wildCount int
	if err := database.DB.QueryRow(ctx, "SELECT COUNT(*) FROM pokemon_game_encounter WHERE kind = 'wild'").Scan(&wildCount); err != nil {
		log.Fatal("Failed to count wild encounters: ", err)
	}
	if wildCount > 0 {
		log.Printf("Found %d existing wild encounter rows; skipping PokeAPI sync (run cmd/sync_encounters to refresh).", wildCount)
		return
	}
	log.Println("No wild encounter kinds present; deriving from PokeAPI (this can take a few minutes)...")
	if err := services.SyncEncounterKinds(); err != nil {
		log.Fatal("Failed to sync wild encounter kinds: ", err)
	}
}

// deriveEggEncounters records an `egg` kind for every breedable Pokemon in each
// game it is available in. Masuda methods are mapped only to Switch-era games,
// which is exactly the coverage of pokemon_availability, so this gating is safe.
func deriveEggEncounters(ctx context.Context) {
	tag, err := database.DB.Exec(ctx, `
		INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind)
		SELECT pa.pokemon_id, pa.game_id, 'egg'
		FROM pokemon_availability pa
		JOIN pokemon p ON p.id = pa.pokemon_id
		WHERE p.can_breed = true
		ON CONFLICT DO NOTHING
	`)
	if err != nil {
		log.Fatal("Failed to derive egg encounters: ", err)
	}
	log.Printf("Inserted %d egg encounter rows.", tag.RowsAffected())
}

func seedCuratedEncounters(ctx context.Context) {
	groups := loadGameGroups()
	gameIDs := loadGameIDs(ctx)

	data, err := os.ReadFile("seeds/legendary_encounters.json")
	if err != nil {
		log.Fatal("Failed to read legendary_encounters.json: ", err)
	}
	var entries []LegendaryEncounter
	if err := json.Unmarshal(data, &entries); err != nil {
		log.Fatal("JSON parse error in legendary_encounters.json: ", err)
	}

	inserted := 0
	for _, e := range entries {
		if e.DefaultKind != "static" && e.DefaultKind != "raid" {
			log.Fatalf("Legendary %s (#%d): default_kind must be static or raid, got %q", e.Name, e.PokemonID, e.DefaultKind)
		}

		// Resolve game -> kind. Precedence: explicit override > group override > default.
		covered := make(map[string]string)
		for _, g := range e.DefaultGames {
			for _, game := range expandGameRef(g, groups, e) {
				covered[game] = e.DefaultKind
			}
		}
		// Group (alias) overrides first, then explicit per-game overrides win.
		for key, kind := range e.Overrides {
			if kind != "static" && kind != "raid" && kind != "none" {
				log.Fatalf("Legendary %s (#%d): override kind must be static, raid, or none, got %q", e.Name, e.PokemonID, kind)
			}
			if strings.HasPrefix(key, "@") {
				for _, game := range expandGameRef(key, groups, e) {
					covered[game] = kind
				}
			}
		}
		for key, kind := range e.Overrides {
			if !strings.HasPrefix(key, "@") {
				covered[key] = kind // explicit single game
			}
		}

		for game, kind := range covered {
			gameID, ok := gameIDs[game]
			if !ok {
				log.Fatalf("Legendary %s (#%d): unknown game %q (not in games table)", e.Name, e.PokemonID, game)
			}
			if kind == "none" {
				continue
			}
			tag, err := database.DB.Exec(ctx,
				`INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind)
				 VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
				e.PokemonID, gameID, kind)
			if err != nil {
				log.Fatalf("Legendary %s (#%d): failed to insert %s in %s: %v", e.Name, e.PokemonID, kind, game, err)
			}
			inserted += int(tag.RowsAffected())
		}
	}
	log.Printf("Inserted %d curated static/raid encounter rows.", inserted)
}

// expandGameRef turns a game title or @alias into a list of game titles.
func expandGameRef(ref string, groups map[string][]string, e LegendaryEncounter) []string {
	if strings.HasPrefix(ref, "@") {
		games, ok := groups[ref]
		if !ok {
			log.Fatalf("Legendary %s (#%d): unknown game-group alias %q", e.Name, e.PokemonID, ref)
		}
		return games
	}
	return []string{ref}
}

func loadGameGroups() map[string][]string {
	data, err := os.ReadFile("seeds/game_groups.json")
	if err != nil {
		log.Fatal("Failed to read game_groups.json: ", err)
	}
	var groups map[string][]string
	if err := json.Unmarshal(data, &groups); err != nil {
		log.Fatal("JSON parse error in game_groups.json: ", err)
	}
	return groups
}

func loadGameIDs(ctx context.Context) map[string]int {
	rows, err := database.DB.Query(ctx, "SELECT id, title FROM games")
	if err != nil {
		log.Fatal("Failed to load games: ", err)
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

// computeAvailability rebuilds method_availability as the join of encounter kinds
// to methods (on the kind a method consumes) and to method_games (on the game).
func computeAvailability(ctx context.Context) {
	_, err := database.DB.Exec(ctx, `
		INSERT INTO method_availability (pokemon_id, method_id, game_id)
		SELECT DISTINCT pge.pokemon_id, hm.id, pge.game_id
		FROM pokemon_game_encounter pge
		JOIN hunt_methods hm ON hm.requires_kind = pge.kind
			AND (hm.requires_terrain IS NULL OR hm.requires_terrain = pge.terrain)
		JOIN method_games mg ON mg.method_id = hm.id AND mg.game_id = pge.game_id
		ON CONFLICT DO NOTHING
	`)
	if err != nil {
		log.Fatal("Failed to compute method_availability: ", err)
	}

	var count int
	database.DB.QueryRow(ctx, "SELECT COUNT(*) FROM method_availability").Scan(&count)
	fmt.Printf("Inserted %d availability records.\n", count)
}

func runInvariantChecks(ctx context.Context) {
	// 6.2: every method has a valid required kind.
	var badMethods int
	database.DB.QueryRow(ctx, `
		SELECT COUNT(*) FROM hunt_methods
		WHERE requires_kind IS NULL OR requires_kind NOT IN ('wild','static','raid','egg')
	`).Scan(&badMethods)
	if badMethods > 0 {
		log.Fatalf("Invariant violation: %d hunt_methods have a missing/invalid requires_kind", badMethods)
	}

	// 6.1: every availability row is backed by a matching encounter-kind record.
	var orphans int
	database.DB.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM method_availability ma
		JOIN hunt_methods hm ON hm.id = ma.method_id
		LEFT JOIN pokemon_game_encounter pge
			ON pge.pokemon_id = ma.pokemon_id
			AND pge.game_id = ma.game_id
			AND pge.kind = hm.requires_kind
			AND (hm.requires_terrain IS NULL OR pge.terrain = hm.requires_terrain)
		WHERE pge.pokemon_id IS NULL
	`).Scan(&orphans)
	if orphans > 0 {
		log.Fatalf("Invariant violation: %d method_availability rows have no matching encounter kind", orphans)
	}

	log.Println("Invariant checks passed.")
}
