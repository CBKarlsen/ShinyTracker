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

	log.Println("Seeding method exceptions...")
	seedMethodExceptions(ctx)

	log.Println("Ensuring wild encounter kinds are populated...")
	ensureWildEncounters(ctx)

	log.Println("Deriving egg encounter kinds...")
	deriveEggEncounters(ctx)

	log.Println("Seeding curated static/raid encounter kinds...")
	seedCuratedEncounters(ctx)

	log.Println("Seeding overworld wild species (Gen 8/9 curated)...")
	seedOverworldSpecies(ctx)

	log.Println("Reconciling pokemon_availability with encounters...")
	reconcileAvailability(ctx)

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

// MethodExceptionSeed is one manual correction in seeds/method_exceptions.json.
// Method is the hunt_methods.json "id" string (stable across re-seeds; note that
// method_name is NOT unique, e.g. several "Random Encounter" rows exist). Game is
// a game title, or null to apply to every game the method is mapped to.
type MethodExceptionSeed struct {
	PokemonID int     `json:"pokemon_id"`
	Method    string  `json:"method"`
	Game      *string `json:"game"`
	Include   bool    `json:"include"`
}

// seedMethodExceptions repopulates method_exceptions from JSON. The table is
// cascade-truncated with hunt_methods at the start of every seed, so corrections
// must live in version control here rather than as DB-only edits. Must run after
// seedMethods so methodIDMap is populated.
func seedMethodExceptions(ctx context.Context) {
	data, err := os.ReadFile("seeds/method_exceptions.json")
	if err != nil {
		if os.IsNotExist(err) {
			log.Println("No method_exceptions.json found; skipping.")
			return
		}
		log.Fatal("Failed to read method_exceptions.json: ", err)
	}
	var exceptions []MethodExceptionSeed
	if err := json.Unmarshal(data, &exceptions); err != nil {
		log.Fatal("method_exceptions.json parse error: ", err)
	}

	for _, e := range exceptions {
		methodID, ok := methodIDMap[e.Method]
		if !ok {
			log.Fatalf("method_exceptions: unknown method id %q (must match an \"id\" in hunt_methods.json)", e.Method)
		}
		var gameID *int
		if e.Game != nil {
			var gid int
			if err := database.DB.QueryRow(ctx, "SELECT id FROM games WHERE title = $1", *e.Game).Scan(&gid); err != nil {
				log.Fatalf("method_exceptions: unknown game %q for method %q: %v", *e.Game, e.Method, err)
			}
			gameID = &gid
		}
		if _, err := database.DB.Exec(ctx,
			`INSERT INTO method_exceptions (pokemon_id, method_id, game_id, include)
			 VALUES ($1, $2, $3, $4)
			 ON CONFLICT (pokemon_id, method_id, game_id) DO UPDATE SET include = EXCLUDED.include`,
			e.PokemonID, methodID, gameID, e.Include,
		); err != nil {
			log.Fatalf("method_exceptions: failed to insert (pokemon %d, method %q): %v", e.PokemonID, e.Method, err)
		}
	}
	log.Printf("Seeded %d method exceptions.", len(exceptions))
}

// reconcileAvailability makes pokemon_availability a superset of the encounter
// table: a Pokemon with a wild/static/raid encounter in a game is by definition
// obtainable there, so it must be listed as available. This closes
// "huntable but not legally available" gaps where the CSV-sourced availability
// table was missing legitimately-catchable Pokemon (Great Marsh, honey trees,
// Hidden Grottoes, Pokewalker, fossil revivals, curated statics). Wild rows come
// from PokeAPI (the actual games), and legendary wild rows are already purged, so
// there are no false positives. egg is omitted because egg rows are themselves
// derived from pokemon_availability and so are already a subset of it.
func reconcileAvailability(ctx context.Context) {
	tag, err := database.DB.Exec(ctx, `
		INSERT INTO pokemon_availability (pokemon_id, game_id)
		SELECT DISTINCT pge.pokemon_id, pge.game_id
		FROM pokemon_game_encounter pge
		WHERE pge.kind IN ('wild','static','raid')
		ON CONFLICT DO NOTHING
	`)
	if err != nil {
		log.Fatal("Failed to reconcile pokemon_availability: ", err)
	}
	log.Printf("Reconciled pokemon_availability with encounters (+%d rows).", tag.RowsAffected())
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
		-- Eggs only ever hatch the base form of an evolution line, so an egg
		-- (Masuda) route belongs only to base-stage species. Evolved forms get
		-- a "hunt a pre-evolution, then evolve" route instead (computed in the
		-- /api/pokemon/{id}/route handler from evolves_from_id).
		WHERE p.can_breed = true AND p.evolves_from_id IS NULL
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

// seedOverworldSpecies inserts curated wild encounter rows for games where PokeAPI
// provides no wild data (Gen 8/9). The source (seeds/overworld_species.json) maps a
// game title to the National-Dex IDs that are wild/overworld-encounterable there,
// taken from regional-dex membership. Legendaries/mythicals are guarded out — in
// these games they are static/shiny-locked, not wild spawns.
func seedOverworldSpecies(ctx context.Context) {
	data, err := os.ReadFile("seeds/overworld_species.json")
	if err != nil {
		log.Fatal("Failed to read overworld_species.json: ", err)
	}
	var byGame map[string][]int
	if err := json.Unmarshal(data, &byGame); err != nil {
		log.Fatal("JSON parse error in overworld_species.json: ", err)
	}
	gameIDs := loadGameIDs(ctx)
	inserted := 0
	for title, ids := range byGame {
		gameID, ok := gameIDs[title]
		if !ok {
			log.Printf("WARNING: overworld_species.json: unknown game title %q — skipping", title)
			continue
		}
		tag, err := database.DB.Exec(ctx, `
			INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
			SELECT p.id, $1, 'wild', 'none'
			FROM pokemon p
			WHERE p.id = ANY($2::int[]) AND NOT (p.is_legendary OR p.is_mythical)
			ON CONFLICT DO NOTHING
		`, gameID, ids)
		if err != nil {
			log.Fatalf("overworld_species: failed to insert wild rows for %s: %v", title, err)
		}
		inserted += int(tag.RowsAffected())
	}
	log.Printf("Inserted %d overworld wild encounter rows.", inserted)
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

	// Apply manual includes: force a method onto a Pokemon for the game(s) the
	// method is mapped to (game_id NULL = every game in method_games). Joining
	// method_games means we never invent a method for a game it doesn't exist in.
	if _, err := database.DB.Exec(ctx, `
		INSERT INTO method_availability (pokemon_id, method_id, game_id)
		SELECT me.pokemon_id, me.method_id, mg.game_id
		FROM method_exceptions me
		JOIN method_games mg ON mg.method_id = me.method_id
			AND (me.game_id IS NULL OR me.game_id = mg.game_id)
		WHERE me.include = true
		ON CONFLICT DO NOTHING
	`); err != nil {
		log.Fatal("Failed to apply method_exceptions includes: ", err)
	}

	// Apply manual excludes last so they win over both the derivation and any
	// include (game_id NULL = remove from every game).
	if _, err := database.DB.Exec(ctx, `
		DELETE FROM method_availability ma
		USING method_exceptions me
		WHERE me.include = false
			AND ma.pokemon_id = me.pokemon_id
			AND ma.method_id = me.method_id
			AND (me.game_id IS NULL OR ma.game_id = me.game_id)
	`); err != nil {
		log.Fatal("Failed to apply method_exceptions excludes: ", err)
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

	// Warning (non-fatal): a Pokemon is huntable in a game it isn't legally
	// available in. Contradictory by definition — usually a mislabeled encounter
	// kind (e.g. a fossil/gift marked 'wild') or a hole in pokemon_availability.
	var huntableNotAvailable int
	database.DB.QueryRow(ctx, `
		SELECT COUNT(DISTINCT (ma.pokemon_id, ma.game_id))
		FROM method_availability ma
		WHERE NOT EXISTS (
			SELECT 1 FROM pokemon_availability pa
			WHERE pa.pokemon_id = ma.pokemon_id AND pa.game_id = ma.game_id)
	`).Scan(&huntableNotAvailable)
	if huntableNotAvailable > 0 {
		log.Printf("WARNING: %d (pokemon,game) pairs are huntable but not in pokemon_availability "+
			"(run `go run ./cmd/audit_methods` for the list)", huntableNotAvailable)
	}

	// Warning (non-fatal): a game has wild encounter rows but no wild method
	// mapped to it, so none of those encounters are huntable. Flags games whose
	// method catalog is incomplete (e.g. Gen 1/2/5 have wild data but no
	// random-encounter method defined in seeds/hunt_methods.json).
	rows, err := database.DB.Query(ctx, `
		SELECT g.title FROM games g
		WHERE EXISTS (SELECT 1 FROM pokemon_game_encounter pge WHERE pge.game_id = g.id AND pge.kind = 'wild')
		  AND NOT EXISTS (
			SELECT 1 FROM method_games mg JOIN hunt_methods hm ON hm.id = mg.method_id
			WHERE mg.game_id = g.id AND hm.requires_kind = 'wild')
		ORDER BY g.generation`)
	if err == nil {
		var games []string
		for rows.Next() {
			var t string
			rows.Scan(&t)
			games = append(games, t)
		}
		rows.Close()
		for _, g := range games {
			log.Printf("WARNING: %q has wild encounters but no wild method mapped — those Pokemon have no hunt method", g)
		}
	}

	log.Println("Invariant checks passed.")
}
