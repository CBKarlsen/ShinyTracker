package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/seeds"
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

	// RUNBOOK ORDER (each step depends on the ones above it):
	//   1. seedMethods          — populate hunt_methods / method_games
	//   2. seedMethodExceptions — manual include/exclude corrections
	//   3. ensureWildEncounters — PokeAPI wild kinds (skipped if already present)
	//   4. seedCuratedEncounters / seedOverworldSpecies / seedFishingSpecies /
	//      seedFriendSafariSpecies / seedBDSPWildEncounters — curated encounter rows
	//   5. reconcileAvailability — backfill pokemon_availability from encounters
	//   6. deriveEggEncounters   — egg kinds for breedable base-stage Pokemon
	//   7. seedShinyLocks        — MUST run before computeAvailability so locked
	//                              pairs are guaranteed current when availability
	//                              is derived (replaces run-order dependency on
	//                              standalone cmd/seed_shiny_locks)
	//   8. computeAvailability   — join encounters × methods, exclude locked pairs
	//   9. runInvariantChecks    — sanity assertions including regression guard
	//      against shiny_locks leaking into method_availability

	log.Println("Wiping derived method tables (keeping wild encounter kinds)...")
	// hunt_methods is intentionally NOT truncated: its ids must stay stable
	// across re-seeds (user_hunts.hunt_method_id references them, with no FK
	// on production to protect it — see migrations/011_add_hunt_methods_slug.sql).
	// seedMethods upserts on the stable slug instead; method_games and
	// method_availability are fully derived and safe to rebuild every run.
	if _, err := database.DB.Exec(ctx, `TRUNCATE TABLE method_games, method_availability CASCADE`); err != nil {
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

	log.Println("Seeding curated static/raid encounter kinds...")
	seedCuratedEncounters(ctx)

	log.Println("Seeding overworld wild species (Gen 8/9 curated)...")
	seedOverworldSpecies(ctx)

	log.Println("Seeding fishing wild species (curated terrain=fishing)...")
	seedFishingSpecies(ctx)

	log.Println("Seeding Friend Safari species (X/Y, terrain=friend_safari)...")
	seedFriendSafariSpecies(ctx)

	log.Println("Seeding BDSP wild encounters (DPPt proxy + Grand Underground)...")
	seedBDSPWildEncounters(ctx)

	log.Println("Seeding ORAS wild encounters (RSE proxy + ORAS additions)...")
	seedORASWildEncounters(ctx)

	log.Println("Reconciling pokemon_availability with encounters...")
	reconcileAvailability(ctx)

	// Egg derivation runs AFTER reconcileAvailability so that pokemon_availability
	// is fully populated for all games (including Gen 5/6/7 rows inserted by
	// cmd/seed_availability_legacy) before we fan out egg rows from it.
	// Running it before reconcile on a fresh DB would silently produce zero egg
	// rows for any game whose availability comes solely from that seeder.
	log.Println("Deriving egg encounter kinds...")
	deriveEggEncounters(ctx)

	log.Println("Seeding shiny_locks (must precede computeAvailability)...")
	seedShinyLocks(ctx)

	log.Println("Computing method_availability...")
	computeAvailability(ctx)

	log.Println("Running invariant checks...")
	runInvariantChecks(ctx)

	log.Println("Seeding complete.")
}

// seedMethods upserts hunt_methods on its stable slug (HuntMethod.IDStr, the
// JSON "id" field) rather than truncate+insert, so a method's integer id
// never changes across re-seeds — user_hunts.hunt_method_id depends on that
// stability (see migrations/011_add_hunt_methods_slug.sql). method_games rows
// are still fully rebuilt (the table is truncated in main before this runs).
func seedMethods(ctx context.Context) {
	data, err := os.ReadFile("seeds/hunt_methods.json")
	if err != nil {
		log.Fatal("Failed to read hunt_methods.json: ", err)
	}
	var methods []HuntMethod
	if err := json.Unmarshal(data, &methods); err != nil {
		log.Fatal("JSON parse error: ", err)
	}

	currentSlugs := make([]string, 0, len(methods))

	for _, m := range methods {
		if !validKinds[m.RequiresKind] {
			log.Fatalf("Method %q has missing/invalid requires_kind %q", m.MethodName, m.RequiresKind)
		}
		if m.IDStr == "" {
			log.Fatalf("Method %q is missing its stable \"id\" slug", m.MethodName)
		}

		var id int
		err := database.DB.QueryRow(ctx,
			`INSERT INTO hunt_methods (slug, method_name, avg_time_seconds, base_rolls, charm_rolls, formula_type, requires_kind, requires_terrain)
			 VALUES ($1, $2, $3, $4, $5, $6, $7, NULLIF($8, ''))
			 ON CONFLICT (slug) DO UPDATE SET
			     method_name = EXCLUDED.method_name,
			     avg_time_seconds = EXCLUDED.avg_time_seconds,
			     base_rolls = EXCLUDED.base_rolls,
			     charm_rolls = EXCLUDED.charm_rolls,
			     formula_type = EXCLUDED.formula_type,
			     requires_kind = EXCLUDED.requires_kind,
			     requires_terrain = EXCLUDED.requires_terrain
			 RETURNING id`,
			m.IDStr, m.MethodName, m.AvgTimeSeconds, m.BaseRolls, m.CharmRolls, m.FormulaType, m.RequiresKind, m.RequiresTerrain,
		).Scan(&id)
		if err != nil {
			log.Fatalf("Failed to upsert method %s: %v", m.MethodName, err)
		}

		methodIDMap[m.IDStr] = id
		currentSlugs = append(currentSlugs, m.IDStr)

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

	pruneRemovedMethods(ctx, currentSlugs)
}

// pruneRemovedMethods deletes any hunt_methods row whose slug is no longer
// present in hunt_methods.json. hunt_methods is no longer truncated each run
// (see seedMethods), so a row removed from the JSON would otherwise linger
// forever. Deleting it still orphans any user_hunts row pointing at that id
// (production has no FK enforcing hunt_method_id — see schema.sql), so every
// deletion is logged loudly rather than dropped silently.
func pruneRemovedMethods(ctx context.Context, currentSlugs []string) {
	rows, err := database.DB.Query(ctx,
		`SELECT id, slug, method_name FROM hunt_methods WHERE NOT (slug = ANY($1))`, currentSlugs)
	if err != nil {
		log.Fatal("Failed to query stale hunt_methods: ", err)
	}
	type staleMethod struct {
		id   int
		slug string
		name string
	}
	var stale []staleMethod
	for rows.Next() {
		var s staleMethod
		if err := rows.Scan(&s.id, &s.slug, &s.name); err != nil {
			rows.Close()
			log.Fatal("Failed to scan stale hunt_methods row: ", err)
		}
		stale = append(stale, s)
	}
	rows.Close()

	for _, s := range stale {
		log.Printf("PRUNING hunt_method %q (id=%d, slug=%q): no longer present in hunt_methods.json. "+
			"Any user_hunts row referencing hunt_method_id=%d is now orphaned.", s.name, s.id, s.slug, s.id)
		if _, err := database.DB.Exec(ctx, `DELETE FROM hunt_methods WHERE id = $1`, s.id); err != nil {
			log.Fatalf("Failed to prune hunt_method %q (id=%d): %v", s.name, s.id, err)
		}
	}
	if len(stale) > 0 {
		log.Printf("Pruned %d hunt_method(s) removed from hunt_methods.json.", len(stale))
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

// seedMethodExceptions repopulates method_exceptions from JSON, upserting on
// (pokemon_id, method_id, game_id) — the table is no longer truncated each run
// (hunt_methods, which it cascades from, is now stable-id upserted rather than
// truncated). Corrections still live in version control here rather than as
// DB-only edits. Must run after seedMethods so methodIDMap is populated.
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

// deriveEggEncounters records an `egg` kind for every breedable base-stage
// Pokemon in each game that supports breeding. It must run AFTER
// reconcileAvailability (and after cmd/seed_availability_legacy for Gen 5/6/7)
// so that pokemon_availability is fully populated before we fan out egg rows.
// The supports_breeding guard keeps LGPE (no Day-Care) and Legends: Arceus
// (no breeding at all) from gaining egg rows.
func deriveEggEncounters(ctx context.Context) {
	tag, err := database.DB.Exec(ctx, `
		INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind)
		SELECT pa.pokemon_id, pa.game_id, 'egg'
		FROM pokemon_availability pa
		JOIN pokemon p ON p.id = pa.pokemon_id
		-- Restrict to games where breeding is possible (excludes LGPE and PLA).
		JOIN games g ON g.id = pa.game_id AND g.supports_breeding = true
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

// seedFishingSpecies inserts curated wild encounter rows with terrain='fishing' for
// games where PokeAPI lacks fishing-terrain data (e.g. ORAS). Source maps a game title
// to the National-Dex IDs catchable via rods there. Legendaries/mythicals are guarded
// out. This is the terrain='fishing' sibling of seedOverworldSpecies.
func seedFishingSpecies(ctx context.Context) {
	data, err := os.ReadFile("seeds/fishing_species.json")
	if err != nil {
		log.Fatal("Failed to read fishing_species.json: ", err)
	}
	var byGame map[string][]int
	if err := json.Unmarshal(data, &byGame); err != nil {
		log.Fatal("JSON parse error in fishing_species.json: ", err)
	}
	gameIDs := loadGameIDs(ctx)
	inserted := 0
	for title, ids := range byGame {
		gameID, ok := gameIDs[title]
		if !ok {
			log.Printf("WARNING: fishing_species.json: unknown game title %q — skipping", title)
			continue
		}
		tag, err := database.DB.Exec(ctx, `
			INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
			SELECT p.id, $1, 'wild', 'fishing'
			FROM pokemon p
			WHERE p.id = ANY($2::int[]) AND NOT (p.is_legendary OR p.is_mythical)
			ON CONFLICT DO NOTHING
		`, gameID, ids)
		if err != nil {
			log.Fatalf("fishing_species: failed to insert fishing rows for %s: %v", title, err)
		}
		inserted += int(tag.RowsAffected())
	}
	log.Printf("Inserted %d fishing wild encounter rows.", inserted)
}

// seedFriendSafariSpecies inserts wild encounter rows with terrain='friend_safari'
// for X/Y (game_id resolved by title "X/Y"). seeds/friend_safari_species.json
// is the verified Friend Safari Pokémon pool (185 entries as of last audit).
// These rows feed the friend_safari_xy method (requires_terrain='friend_safari')
// during computeAvailability, scoping Friend Safari to exactly the right species.
// Legendaries and mythicals are not in the FS pool and are guarded out anyway.
//
// RUNBOOK: the pokemon_game_encounter.terrain CHECK constraint must already
// include 'friend_safari' on the live DB (via the ALTER TABLE in schema.sql)
// before running cmd/seed. If the method tables were truncated and this seeder
// runs against a DB whose CHECK doesn't yet know about 'friend_safari', the
// INSERT will fail with a check-violation error. Apply the schema ALTER first.
func seedFriendSafariSpecies(ctx context.Context) {
	data, err := os.ReadFile("seeds/friend_safari_species.json")
	if err != nil {
		log.Fatal("Failed to read friend_safari_species.json: ", err)
	}
	var ids []int
	if err := json.Unmarshal(data, &ids); err != nil {
		log.Fatal("JSON parse error in friend_safari_species.json: ", err)
	}
	gameIDs := loadGameIDs(ctx)
	gameID, ok := gameIDs["X/Y"]
	if !ok {
		log.Fatal("seedFriendSafariSpecies: game title 'X/Y' not found in games table")
	}
	tag, err := database.DB.Exec(ctx, `
		INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
		SELECT p.id, $1, 'wild', 'friend_safari'
		FROM pokemon p
		WHERE p.id = ANY($2::int[]) AND NOT (p.is_legendary OR p.is_mythical)
		ON CONFLICT DO NOTHING
	`, gameID, ids)
	if err != nil {
		log.Fatal("seedFriendSafariSpecies: failed to insert rows: ", err)
	}
	log.Printf("Inserted %d Friend Safari encounter rows (X/Y).", tag.RowsAffected())
}

// seedBDSPWildEncounters populates wild encounter rows for Brilliant
// Diamond/Shining Pearl (game_id resolved by title). Two sources:
//
//  1. DPPt proxy: copies all kind='wild' rows from Diamond/Pearl/Platinum,
//     excluding Pokémon that are Great-Marsh/DPPt-only and absent from BDSP
//     routes: Ekans(23)/Arbok(24) — Great Marsh / not on BDSP routes;
//     Tangela(114)/Tropius(357) Great-Marsh-only.
//
//  2. Grand Underground: reads seeds/bdsp_underground_species.json and
//     inserts each as (pokemon_id, BDSP, 'wild', 'other') so they receive
//     the random_encounter_bdsp method but NOT poke_radar_bdsp (which
//     requires terrain='grass').
//
// Both steps use ON CONFLICT DO NOTHING for idempotency.
func seedBDSPWildEncounters(ctx context.Context) {
	gameIDs := loadGameIDs(ctx)

	bdspID, ok := gameIDs["Brilliant Diamond/Shining Pearl"]
	if !ok {
		log.Fatal("seedBDSPWildEncounters: game 'Brilliant Diamond/Shining Pearl' not found in games table")
	}
	dpptID, ok := gameIDs["Diamond/Pearl/Platinum"]
	if !ok {
		log.Fatal("seedBDSPWildEncounters: game 'Diamond/Pearl/Platinum' not found in games table")
	}

	// Part 1: DPPt proxy. Excludes Great-Marsh species absent from BDSP routes:
	// Ekans(23)/Arbok(24) — Great Marsh only, not on BDSP routes (Ekans is
	// Grand-Underground-only in BDSP and is handled via bdsp_underground_species.json);
	// Tangela(114)/Tropius(357) — Great-Marsh-only in DPPt.
	tag, err := database.DB.Exec(ctx, `
		INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
		SELECT pokemon_id, $1, kind, terrain
		FROM pokemon_game_encounter
		WHERE game_id = $2
		  AND kind = 'wild'
		  AND pokemon_id NOT IN (23, 24, 114, 357)
		ON CONFLICT DO NOTHING
	`, bdspID, dpptID)
	if err != nil {
		log.Fatal("seedBDSPWildEncounters: DPPt proxy insert failed: ", err)
	}
	log.Printf("  BDSP DPPt proxy: +%d wild rows", tag.RowsAffected())

	// Part 2: Grand Underground species (terrain='other' — random encounter
	// but not Poké Radar, which requires terrain='grass').
	data, err := os.ReadFile("seeds/bdsp_underground_species.json")
	if err != nil {
		log.Fatal("seedBDSPWildEncounters: failed to read bdsp_underground_species.json: ", err)
	}
	var undergroundIDs []int
	if err := json.Unmarshal(data, &undergroundIDs); err != nil {
		log.Fatal("seedBDSPWildEncounters: JSON parse error in bdsp_underground_species.json: ", err)
	}
	tag, err = database.DB.Exec(ctx, `
		INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
		SELECT p.id, $1, 'wild', 'other'
		FROM pokemon p
		WHERE p.id = ANY($2::int[]) AND NOT (p.is_legendary OR p.is_mythical)
		ON CONFLICT DO NOTHING
	`, bdspID, undergroundIDs)
	if err != nil {
		log.Fatal("seedBDSPWildEncounters: Grand Underground insert failed: ", err)
	}
	log.Printf("  BDSP Grand Underground: +%d wild rows (terrain=other)", tag.RowsAffected())
}

// seedORASWildEncounters populates wild encounter rows for Omega Ruby/Alpha
// Sapphire (game_id resolved by title). Two sources:
//
//  1. RSE proxy: copies all kind='wild' rows from Ruby/Sapphire/Emerald,
//     excluding Pokémon that are RSE-only and absent from ORAS routes (see
//     exclusion set below). Preserves the original kind and terrain values.
//
//  2. ORAS additions: reads seeds/oras_wild_additions.json and inserts each
//     as (pokemon_id, ORAS, 'wild', 'other') so they receive the
//     random_encounter_oras and dexnav_gen6 methods (both have NULL
//     requires_terrain and therefore match terrain='other') but NOT
//     chain_fishing_gen6 (which requires_terrain='fishing').
//
// Both steps use ON CONFLICT DO NOTHING for idempotency.
func seedORASWildEncounters(ctx context.Context) {
	gameIDs := loadGameIDs(ctx)

	orasID, ok := gameIDs["Omega Ruby/Alpha Sapphire"]
	if !ok {
		log.Fatal("seedORASWildEncounters: game 'Omega Ruby/Alpha Sapphire' not found in games table")
	}
	rseID, ok := gameIDs["Ruby/Sapphire/Emerald"]
	if !ok {
		log.Fatal("seedORASWildEncounters: game 'Ruby/Sapphire/Emerald' not found in games table")
	}

	// Part 1: RSE proxy. Excludes species that exist in RSE but are not
	// available as wild encounters in ORAS routes.
	tag, err := database.DB.Exec(ctx, `
		INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
		SELECT pokemon_id, $1, kind, terrain
		FROM pokemon_game_encounter
		WHERE game_id = $2
		  AND kind = 'wild'
		  AND pokemon_id NOT IN (
		    55, 85, 111, 163, 165, 167, 177, 179, 183, 190, 191, 194, 195, 204,
		    207, 209, 213, 216, 223, 224, 228, 231, 234, 241, 277, 310, 321
		  )
		ON CONFLICT DO NOTHING
	`, orasID, rseID)
	if err != nil {
		log.Fatal("seedORASWildEncounters: RSE proxy insert failed: ", err)
	}
	log.Printf("  ORAS RSE proxy: +%d wild rows", tag.RowsAffected())

	// Part 2: ORAS-added species not in RSE (terrain='other' → Random
	// Encounter / DexNav; not terrain='grass' so Poké Radar never applies,
	// and these rows won't interfere with fishing-terrain methods).
	data, err := os.ReadFile("seeds/oras_wild_additions.json")
	if err != nil {
		log.Fatal("seedORASWildEncounters: failed to read oras_wild_additions.json: ", err)
	}
	var additionIDs []int
	if err := json.Unmarshal(data, &additionIDs); err != nil {
		log.Fatal("seedORASWildEncounters: JSON parse error in oras_wild_additions.json: ", err)
	}
	tag, err = database.DB.Exec(ctx, `
		INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
		SELECT p.id, $1, 'wild', 'other'
		FROM pokemon p
		WHERE p.id = ANY($2::int[]) AND NOT (p.is_legendary OR p.is_mythical)
		ON CONFLICT DO NOTHING
	`, orasID, additionIDs)
	if err != nil {
		log.Fatal("seedORASWildEncounters: ORAS additions insert failed: ", err)
	}
	log.Printf("  ORAS additions: +%d wild rows (terrain=other)", tag.RowsAffected())
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

// seedShinyLocks delegates to the shared helper in internal/seeds. It must be
// called after the games table is populated and before computeAvailability so
// that locked (pokemon_id, game_id) pairs are excluded from method derivation.
// The standalone cmd/seed_shiny_locks calls the same helper for ad-hoc re-seeds.
func seedShinyLocks(ctx context.Context) {
	inserted, skipped, err := seeds.SeedShinyLocks(ctx, database.DB, "seeds/shiny_locks.json")
	if err != nil {
		log.Fatal("Failed to seed shiny_locks: ", err)
	}
	log.Printf("shiny_locks seeded: %d inserted, %d skipped (unknown game)", inserted, skipped)
}

// computeAvailability rebuilds method_availability as the join of encounter kinds
// to methods (on the kind a method consumes) and to method_games (on the game).
//
// Terrain-matching rule:
//   - hm.requires_terrain = pge.terrain  → explicit match (e.g. friend_safari,
//     grass Poké Radar, fishing Chain Fishing).
//   - hm.requires_terrain IS NULL AND pge.terrain <> 'friend_safari'  → generic
//     method (e.g. Random Encounter) matches any terrain except the dedicated
//     friend_safari terrain, preventing spurious Random Encounter rows for
//     Friend-Safari-only species.
//
// Shiny-lock guard: any (pokemon_id, game_id) pair that is present in
// shiny_locks is unconditionally excluded from method_availability. This is the
// systemic fix for locked Pokemon (e.g. the SV Indigo Disk Paradoxes) that
// previously leaked hunt methods via their encounter rows. seedShinyLocks must
// run before computeAvailability for this guard to be effective.
//
// Generation-1 guard: shinies do not exist in Gen 1 (RBY). Game IDs whose
// generation = 1 are excluded entirely so that static encounter rows for the
// legendary birds and Mewtwo never produce method_availability entries.
// Shiny hunting legitimately starts in Gen 2 (GSC introduced the DV mechanic).
// NOTE: Red/Blue/Yellow has been removed from SeedGames and all seed data, so
// this guard will never match any existing row — it remains as a cheap invariant
// preventing accidental Gen-1 reintroduction and is safe when no Gen-1 row exists.
func computeAvailability(ctx context.Context) {
	_, err := database.DB.Exec(ctx, `
		INSERT INTO method_availability (pokemon_id, method_id, game_id)
		SELECT DISTINCT pge.pokemon_id, hm.id, pge.game_id
		FROM pokemon_game_encounter pge
		-- Shinies do not exist in Gen 1; skip all Gen-1 games.
		JOIN games g ON g.id = pge.game_id AND g.generation >= 2
		JOIN hunt_methods hm ON hm.requires_kind = pge.kind
			AND (hm.requires_terrain = pge.terrain
				OR (hm.requires_terrain IS NULL AND pge.terrain <> 'friend_safari'))
		JOIN method_games mg ON mg.method_id = hm.id AND mg.game_id = pge.game_id
		-- Never grant a hunt method to a shiny-locked (pokemon, game) pair.
		AND NOT EXISTS (
			SELECT 1 FROM shiny_locks sl
			WHERE sl.pokemon_id = pge.pokemon_id AND sl.game_id = pge.game_id)
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
	// Uses the same terrain-matching rule as computeAvailability: explicit
	// requires_terrain must equal pge.terrain; NULL requires_terrain matches any
	// terrain except 'friend_safari' (which is reserved for its dedicated method).
	// Shiny-locked pairs are excluded from this check to match the insertion rule:
	// a method_exceptions include on a locked Pokemon is explicitly tolerated (it
	// would never have been inserted by computeAvailability) and must not trigger
	// a false orphan report.
	var orphans int
	database.DB.QueryRow(ctx, `
		SELECT COUNT(*)
		FROM method_availability ma
		JOIN hunt_methods hm ON hm.id = ma.method_id
		LEFT JOIN pokemon_game_encounter pge
			ON pge.pokemon_id = ma.pokemon_id
			AND pge.game_id = ma.game_id
			AND pge.kind = hm.requires_kind
			AND (hm.requires_terrain = pge.terrain
				OR (hm.requires_terrain IS NULL AND pge.terrain <> 'friend_safari'))
		WHERE pge.pokemon_id IS NULL
		  -- Mirror the computeAvailability exclusion: locked pairs are never
		  -- inserted by the derivation, so they must not be checked here either.
		  AND NOT EXISTS (
			SELECT 1 FROM shiny_locks sl
			WHERE sl.pokemon_id = ma.pokemon_id AND sl.game_id = ma.game_id)
	`).Scan(&orphans)
	if orphans > 0 {
		log.Fatalf("Invariant violation: %d method_availability rows have no matching encounter kind", orphans)
	}

	// 6.3 (regression guard): no method_availability row may exist for a
	// shiny-locked (pokemon, game) pair. A violation means either
	// computeAvailability ran before shiny_locks was populated, or a
	// method_exceptions include was added for a locked Pokemon (which would
	// bypass the derivation guard). Logged as a warning rather than fatal so
	// that a single misconfigured method_exception does not abort the entire
	// seed — the operator can inspect and fix.
	var lockedWithMethods int
	database.DB.QueryRow(ctx, `
		SELECT COUNT(DISTINCT (ma.pokemon_id, ma.game_id))
		FROM method_availability ma
		JOIN shiny_locks sl ON sl.pokemon_id = ma.pokemon_id AND sl.game_id = ma.game_id
	`).Scan(&lockedWithMethods)
	if lockedWithMethods > 0 {
		log.Printf("WARNING: %d shiny-locked (pokemon,game) pairs still have method_availability rows "+
			"— check method_exceptions for include=true overrides on locked Pokemon, "+
			"or verify seedShinyLocks ran before computeAvailability", lockedWithMethods)
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
	// method catalog is incomplete (e.g. Gen 5 has wild data but no
	// random-encounter method defined in seeds/hunt_methods.json).
	// Gen 1 is excluded: shinies don't exist in RBY, so having wild encounters
	// with no wild method is correct-by-design, not an anomaly. RBY has been
	// removed from the seed data entirely, so generation >= 2 simply never
	// matches a Gen-1 row (the filter is a no-cost invariant, not dead code).
	rows, err := database.DB.Query(ctx, `
		SELECT g.title FROM games g
		WHERE g.generation >= 2
		  AND EXISTS (SELECT 1 FROM pokemon_game_encounter pge WHERE pge.game_id = g.id AND pge.kind = 'wild')
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
