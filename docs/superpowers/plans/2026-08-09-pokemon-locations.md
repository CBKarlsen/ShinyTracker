# Pokémon Locations (Layer 0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store per-game, per-version Pokémon encounter locations for Gen 2–7 and surface them on the existing route list, so a route says *where to stand*, not just which method to use.

**Architecture:** One new table (`pokemon_locations`), seeded by a standalone command from the PokeAPI `/pokemon/{id}/encounters` payload the crawler already fetches and currently discards. Locations ride along on the existing `GET /api/pokemon/{id}/route` response — no new endpoint. Matching a location to a route reuses the terrain rule already documented in `computeAvailability`.

**Tech Stack:** Go 1.x, chi, pgx (raw SQL, no ORM), PostgreSQL (Supabase), React 19 + TypeScript + Vite, Biome.

**Spec:** `docs/superpowers/specs/2026-08-09-pokemon-locations-design.md`

## Global Constraints

- **Node must be arm64 ≥ 20.19 for any frontend command.** Prefix frontend commands with `PATH="/opt/homebrew/opt/node@20/bin:$PATH"`. The default `/usr/local/bin/node` is x64 Node 19 under Rosetta and fails both `vite build` and `biome`.
- **Gen 2–7 only.** Gen 1 is out of scope: `SeedGames` has no Red/Blue/Yellow row and `versionMap` has no `red`/`blue`/`yellow` keys. Do not add them.
- **Do not modify `versionMap`, `SeedGames`, `syncWildEncounters`, or `SyncEncounterKinds` behaviour.** This slice adds a reader alongside them.
- **No new dependencies.** Everything needed is already in `go.mod` and `package.json`.
- **Raw SQL via pgx with `$1`/`$2` placeholders.** No ORM, matching the existing codebase.
- **Terrain rule is copied, not reinvented.** The single source of truth is `cmd/seed/main.go:665` `computeAvailability`: `requires_terrain = terrain` OR (`requires_terrain IS NULL` AND `terrain <> 'friend_safari'`).
- **Frontend lint is currently failing repo-wide (184 pre-existing errors).** Do not attempt to fix unrelated lint findings, and never run `biome check --write` — it also runs the formatter and rewrites ~760 lines across 31 files. Only `npm run build` must pass.
- Backend verification commands: `go build ./...`, `go vet ./...`, `go test ./...` — all must stay clean.

---

### Task 1: `pokemon_locations` schema

**Files:**
- Modify: `backend/schema.sql` (append after the `method_availability` block, ~line 118)
- Create: `backend/cmd/migrate_locations/main.go`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: table `pokemon_locations` with columns `id, pokemon_id, game_id, version, area, terrain, pokeapi_method, min_level, max_level, chance, conditions`. Tasks 3 and 4 read and write it.

Surrogate primary key rather than a natural one because `min_level`/`max_level` are nullable, and a nullable column inside a primary key is a correctness trap. Seeding is delete-then-insert per Pokémon, so no upsert path is needed.

- [ ] **Step 1: Append the table to `backend/schema.sql`**

```sql
-- Per-game, per-version wild encounter locations (Gen 2-7, seeded from PokeAPI
-- by cmd/seed_locations). Distinct from pokemon_game_encounter, which stores the
-- derived encounter KIND; this stores the raw WHERE facts.
--
-- The version column exists because the games table groups versions (versionMap
-- maps diamond/pearl/platinum onto one row). That grouping is correct for odds
-- and methods but wrong for locations: Platinum rebuilt much of Sinnoh's
-- encounter tables and D/P exclusives differ from each other.
CREATE TABLE IF NOT EXISTS pokemon_locations (
    id             SERIAL PRIMARY KEY,
    pokemon_id     INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    game_id        INTEGER NOT NULL REFERENCES games(id)   ON DELETE CASCADE,
    version        TEXT    NOT NULL,   -- PokeAPI version name, e.g. 'platinum'
    area           TEXT    NOT NULL,   -- PokeAPI slug, e.g. 'route-210-area'
    terrain        TEXT    NOT NULL,   -- from services.terrainForMethod
    pokeapi_method TEXT    NOT NULL,   -- 'walk', 'surf', 'old-rod', ...
    min_level      INTEGER,
    max_level      INTEGER,
    chance         INTEGER,            -- percent, per encounter slot
    conditions     TEXT[]              -- 'time-night', 'season-spring', ...
);

CREATE INDEX IF NOT EXISTS idx_pokemon_locations_pokemon_game
    ON pokemon_locations (pokemon_id, game_id);
-- Reverse lookup (area -> species). Unused today; the nuzlocke slice needs it.
CREATE INDEX IF NOT EXISTS idx_pokemon_locations_game_area
    ON pokemon_locations (game_id, area);
```

Also add `pokemon_locations` to the `ENABLE ROW LEVEL SECURITY` block near the end of `schema.sql` (~line 191), keeping the existing column alignment. Every public table carries it: Supabase exposes public tables over PostgREST, and RLS with no policies is what denies anon access.

- [ ] **Step 2: Create `backend/cmd/migrate_locations/main.go`**

`cmd/apply_schema` is destructive to the method tables, so this slice gets its own additive migration command.

```go
package main

import (
	"context"
	"log"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

// Additive migration: creates pokemon_locations and its indexes. Safe to re-run.
// Deliberately NOT part of cmd/apply_schema, which drops the method tables.
func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	ctx := context.Background()
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS pokemon_locations (
			id             SERIAL PRIMARY KEY,
			pokemon_id     INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
			game_id        INTEGER NOT NULL REFERENCES games(id)   ON DELETE CASCADE,
			version        TEXT    NOT NULL,
			area           TEXT    NOT NULL,
			terrain        TEXT    NOT NULL,
			pokeapi_method TEXT    NOT NULL,
			min_level      INTEGER,
			max_level      INTEGER,
			chance         INTEGER,
			conditions     TEXT[]
		)`,
		`CREATE INDEX IF NOT EXISTS idx_pokemon_locations_pokemon_game
			ON pokemon_locations (pokemon_id, game_id)`,
		`CREATE INDEX IF NOT EXISTS idx_pokemon_locations_game_area
			ON pokemon_locations (game_id, area)`,
		// Required, not optional: schema.sql:176-184 documents that Supabase
		// auto-exposes every public table over PostgREST, and that RLS with no
		// policies is what denies anon/authenticated access. Omitting it here
		// would leave the live table readable while schema.sql claims otherwise.
		`ALTER TABLE pokemon_locations ENABLE ROW LEVEL SECURITY`,
	}
	for _, s := range stmts {
		if _, err := database.DB.Exec(ctx, s); err != nil {
			log.Fatal("migration failed: ", err)
		}
	}
	log.Println("pokemon_locations ready.")
}
```

- [ ] **Step 3: Verify it builds**

Run: `cd backend && go build ./... && go vet ./...`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add backend/schema.sql backend/cmd/migrate_locations/main.go
git commit -m "feat(db): add pokemon_locations table and additive migration"
```

---

### Task 2: Parse locations out of the PokeAPI payload

**Files:**
- Modify: `backend/internal/services/pokeapi.go:40-54` (widen `PokeAPIEncounter`), and append `LocationRow` + `ParseLocations`
- Create: `backend/internal/services/locations_test.go`

**Interfaces:**
- Consumes: `terrainForMethod(method string) string` and `versionMap` (both already in `pokeapi.go`)
- Produces:
  - `type LocationRow struct { PokemonID, GameID int; Version, Area, Terrain, PokeAPIMethod string; MinLevel, MaxLevel, Chance int; Conditions []string }`
  - `func ParseLocations(pokemonID int, encounters []PokeAPIEncounter, gameIDs map[string]int) []LocationRow`

`gameIDs` is a parameter rather than the package-level `gameIDCache` specifically so this is testable without a database.

- [ ] **Step 1: Write the failing test**

Create `backend/internal/services/locations_test.go`:

```go
package services

import (
	"encoding/json"
	"testing"
)

// A trimmed real-shaped /pokemon/{id}/encounters payload. Covers: a mapped
// version (platinum -> Diamond/Pearl/Platinum), an unmapped version (red, Gen 1,
// deliberately absent from versionMap), two terrains, and condition values.
const samplePayload = `[
  {
    "location_area": {"name": "route-210-area"},
    "version_details": [
      {
        "version": {"name": "platinum"},
        "encounter_details": [
          {"method": {"name": "walk"}, "min_level": 20, "max_level": 24,
           "chance": 15, "condition_values": [{"name": "time-night"}]},
          {"method": {"name": "walk"}, "min_level": 20, "max_level": 24,
           "chance": 15, "condition_values": [{"name": "time-night"}]}
        ]
      },
      {
        "version": {"name": "red"},
        "encounter_details": [
          {"method": {"name": "walk"}, "min_level": 5, "max_level": 7,
           "chance": 20, "condition_values": []}
        ]
      }
    ]
  },
  {
    "location_area": {"name": "lake-verity-area"},
    "version_details": [
      {
        "version": {"name": "platinum"},
        "encounter_details": [
          {"method": {"name": "surf"}, "min_level": 10, "max_level": 20,
           "chance": 60, "condition_values": []}
        ]
      }
    ]
  }
]`

func TestParseLocations(t *testing.T) {
	var encounters []PokeAPIEncounter
	if err := json.Unmarshal([]byte(samplePayload), &encounters); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	gameIDs := map[string]int{"Diamond/Pearl/Platinum": 4}

	rows := ParseLocations(129, encounters, gameIDs)

	// The duplicate walk slot is deduped; the Gen-1 'red' row is skipped
	// because versionMap has no entry for it.
	if len(rows) != 2 {
		t.Fatalf("want 2 rows, got %d: %+v", len(rows), rows)
	}

	byArea := map[string]LocationRow{}
	for _, r := range rows {
		byArea[r.Area] = r
	}

	walk, ok := byArea["route-210-area"]
	if !ok {
		t.Fatal("missing route-210-area")
	}
	if walk.PokemonID != 129 {
		t.Errorf("PokemonID = %d, want 129", walk.PokemonID)
	}
	if walk.GameID != 4 {
		t.Errorf("GameID = %d, want 4", walk.GameID)
	}
	if walk.Version != "platinum" {
		t.Errorf("Version = %q, want platinum", walk.Version)
	}
	if walk.Terrain != "grass" {
		t.Errorf("Terrain = %q, want grass (walk buckets to grass)", walk.Terrain)
	}
	if walk.PokeAPIMethod != "walk" {
		t.Errorf("PokeAPIMethod = %q, want walk", walk.PokeAPIMethod)
	}
	if walk.MinLevel != 20 || walk.MaxLevel != 24 {
		t.Errorf("levels = %d-%d, want 20-24", walk.MinLevel, walk.MaxLevel)
	}
	if walk.Chance != 15 {
		t.Errorf("Chance = %d, want 15", walk.Chance)
	}
	if len(walk.Conditions) != 1 || walk.Conditions[0] != "time-night" {
		t.Errorf("Conditions = %v, want [time-night]", walk.Conditions)
	}

	surf, ok := byArea["lake-verity-area"]
	if !ok {
		t.Fatal("missing lake-verity-area")
	}
	if surf.Terrain != "surf" {
		t.Errorf("Terrain = %q, want surf", surf.Terrain)
	}
	if len(surf.Conditions) != 0 {
		t.Errorf("Conditions = %v, want empty", surf.Conditions)
	}
}

// A version present in versionMap but whose game title is absent from the
// gameIDs map (e.g. the game row was never seeded) must be skipped, not
// defaulted to game 0.
func TestParseLocationsSkipsUnknownGameTitle(t *testing.T) {
	var encounters []PokeAPIEncounter
	if err := json.Unmarshal([]byte(samplePayload), &encounters); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	rows := ParseLocations(129, encounters, map[string]int{})
	if len(rows) != 0 {
		t.Fatalf("want 0 rows when no game IDs are known, got %d", len(rows))
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && go test ./internal/services/ -run TestParseLocations -v`
Expected: FAIL — `undefined: ParseLocations` and `undefined: LocationRow`.

- [ ] **Step 3: Widen `PokeAPIEncounter`**

In `backend/internal/services/pokeapi.go`, replace the `PokeAPIEncounter` struct (currently lines 40-54) with:

```go
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
```

This only adds fields. `syncWildEncounters` reads `ed.Method.Name` and is unaffected.

- [ ] **Step 4: Add `LocationRow` and `ParseLocations`**

Append to `backend/internal/services/pokeapi.go`:

```go
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
		gameID           int
		version          string
		area             string
		method           string
		minLvl, maxLvl   int
		chance           int
		conditions       string
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
```

Ensure `sort` and `strings` are in the file's import block (`strings` already is; add `sort` if absent).

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd backend && go test ./internal/services/ -run TestParseLocations -v`
Expected: PASS for both `TestParseLocations` and `TestParseLocationsSkipsUnknownGameTitle`.

- [ ] **Step 6: Verify nothing else broke**

Run: `cd backend && go build ./... && go vet ./... && go test ./...`
Expected: clean; `internal/calc` still ok.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/services/pokeapi.go backend/internal/services/locations_test.go
git commit -m "feat(services): parse location/level/rate/conditions from PokeAPI encounters"
```

---

### Task 3: `cmd/seed_locations`

**Files:**
- Create: `backend/cmd/seed_locations/main.go`
- Create: `backend/internal/services/locations.go`

**Interfaces:**
- Consumes: `ParseLocations`, `LocationRow` (Task 2); `loadGameIDs()`, `gameIDCache`, `gameIDMutex` (existing in `pokeapi.go`)
- Produces: `func SeedLocations() error` — crawls every Pokémon and repopulates `pokemon_locations`

Unlike `SyncEncounterKinds`, this does **not** exclude legendaries and mythicals. That exclusion exists because PokeAPI reports stationary legendary encounters as location encounters, which would corrupt a derived `wild` *kind*. This table stores raw location facts and derives no kind, so the exclusion does not apply — and a normal player looking up where to find Mesprit is exactly the use case.

- [ ] **Step 1: Create `backend/internal/services/locations.go`**

```go
package services

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"encoding/json"

	"github.com/casper/shinytracker/internal/database"
)

// SeedLocations repopulates pokemon_locations for every Pokemon from PokeAPI's
// /encounters endpoint.
//
// Independent of cmd/sync on purpose: cmd/sync truncates hunt_methods (cascading
// method_availability to 0), so it cannot be re-run casually against the live
// database. This command touches only pokemon_locations and is safe to re-run.
//
// Legendaries and mythicals are INCLUDED here, unlike SyncEncounterKinds -- see
// the package comment on that function. This table stores raw location facts and
// derives no encounter kind, so the misclassification risk does not apply.
func SeedLocations() error {
	log.Println("Seeding Pokemon locations from PokeAPI...")

	if err := loadGameIDs(); err != nil {
		return fmt.Errorf("failed to load game IDs: %w", err)
	}

	rows, err := database.DB.Query(context.Background(),
		"SELECT id FROM pokemon ORDER BY id")
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
	log.Printf("Fetching locations for %d pokemon...", len(ids))

	jobs := make(chan int, len(ids))
	for _, id := range ids {
		jobs <- id
	}
	close(jobs)

	var wg sync.WaitGroup
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for id := range jobs {
				seedLocationsFor(id)
			}
		}()
	}
	wg.Wait()

	log.Println("Locations seeded.")
	return reportLocationCounts()
}

func seedLocationsFor(pokemonID int) {
	time.Sleep(50 * time.Millisecond)

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

	gameIDMutex.Lock()
	ids := make(map[string]int, len(gameIDCache))
	for k, v := range gameIDCache {
		ids[k] = v
	}
	gameIDMutex.Unlock()

	locs := ParseLocations(pokemonID, encounters, ids)

	ctx := context.Background()
	// Delete-then-insert makes the command idempotent without an upsert path.
	if _, err := database.DB.Exec(ctx,
		"DELETE FROM pokemon_locations WHERE pokemon_id = $1", pokemonID); err != nil {
		log.Printf("Failed to clear locations for %d: %v", pokemonID, err)
		return
	}
	for _, l := range locs {
		_, err := database.DB.Exec(ctx,
			`INSERT INTO pokemon_locations
			   (pokemon_id, game_id, version, area, terrain, pokeapi_method,
			    min_level, max_level, chance, conditions)
			 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)`,
			l.PokemonID, l.GameID, l.Version, l.Area, l.Terrain, l.PokeAPIMethod,
			l.MinLevel, l.MaxLevel, l.Chance, l.Conditions)
		if err != nil {
			log.Printf("Failed to insert location for %d (%s): %v", pokemonID, l.Area, err)
		}
	}
}

// reportLocationCounts logs a per-game row count and fails loudly if any Gen 2-7
// game ended up with zero rows -- a silently-empty crawl is the realistic
// failure mode here, and it would otherwise look like "this game has no data".
func reportLocationCounts() error {
	rows, err := database.DB.Query(context.Background(), `
		SELECT g.id, g.title, g.generation, COUNT(pl.id)
		FROM games g
		LEFT JOIN pokemon_locations pl ON pl.game_id = g.id
		GROUP BY g.id, g.title, g.generation
		ORDER BY g.generation, g.id`)
	if err != nil {
		return err
	}
	defer rows.Close()

	var empty []string
	for rows.Next() {
		var id, gen, count int
		var title string
		if err := rows.Scan(&id, &title, &gen, &count); err != nil {
			return err
		}
		log.Printf("  gen %d  %-32s %6d rows", gen, title, count)
		if gen >= 2 && gen <= 7 && count == 0 {
			empty = append(empty, title)
		}
	}
	if len(empty) > 0 {
		return fmt.Errorf("no locations seeded for Gen 2-7 games: %v", empty)
	}
	return rows.Err()
}
```

- [ ] **Step 2: Create `backend/cmd/seed_locations/main.go`**

```go
package main

import (
	"log"

	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/services"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	if err := services.SeedLocations(); err != nil {
		log.Fatal("Failed to seed locations: ", err)
	}
}
```

- [ ] **Step 3: Verify it builds**

Run: `cd backend && go build ./... && go vet ./... && go test ./...`
Expected: clean.

- [ ] **Step 4: Run the migration, then the seed**

Run:
```bash
cd backend
go run ./cmd/migrate_locations/main.go
go run ./cmd/seed_locations/main.go
```
Expected: a per-game row-count table in the log with every Gen 2–7 game non-zero, and Gen 8/9 games at 0. The command exits non-zero if any Gen 2–7 game is empty.

This is a long crawl (~1025 requests at 50 ms plus latency). It is safe to re-run.

- [ ] **Step 5: Spot-check the data by hand**

Verify directly in SQL (via the Supabase console or psql):
```sql
SELECT version, area, terrain, min_level, max_level, chance, conditions
FROM pokemon_locations
WHERE pokemon_id = 129 -- Magikarp, appears in many games and waters
ORDER BY version, area
LIMIT 20;
```
Expected: fishing/surf terrain rows with plausible level ranges, and version values like `platinum`, `heartgold`.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/services/locations.go backend/cmd/seed_locations/main.go
git commit -m "feat(seed): add cmd/seed_locations to populate pokemon_locations"
```

---

### Task 4: Attach locations to routes

**Files:**
- Modify: `backend/internal/calc/routes.go` (add `Location`, extend `MethodCandidate` and `Route`, add `MatchLocations`)
- Modify: `backend/internal/api/dex.go:90-119` (`fetchMethodCandidates` SQL) and `:170-198` (`PokemonRouteHandler`)
- Modify: `backend/internal/calc/routes_test.go` (append tests)

**Interfaces:**
- Consumes: `pokemon_locations` (Task 1), populated data (Task 3)
- Produces:
  - `type Location struct { GameID int \`json:"-"\`; Area, Version, Terrain string; MinLevel, MaxLevel, Chance int; Conditions []string }`
  - `Route.Locations []Location \`json:"locations"\``
  - `func MatchLocations(r Route, locs []Location, max int) []Location`
  - `func fetchLocations(ctx context.Context, pokemonID int) ([]calc.Location, error)` in `api`

**An evolve route's locations belong to the ancestor, not the target.** A route with `Kind == "evolve"` describes hunting `EvolveFrom.PokemonID`, so its locations must be fetched for that Pokémon ID. Getting this wrong shows the target's locations under a route that hunts something else.

- [ ] **Step 1: Write the failing tests**

Append to `backend/internal/calc/routes_test.go`:

```go
func TestMatchLocationsTerrainRule(t *testing.T) {
	locs := []Location{
		{GameID: 4, Area: "route-210-area", Terrain: "grass", Chance: 15},
		{GameID: 4, Area: "lake-verity-area", Terrain: "surf", Chance: 60},
		{GameID: 4, Area: "friend-safari", Terrain: "friend_safari", Chance: 50},
		{GameID: 9, Area: "other-game-area", Terrain: "grass", Chance: 99},
	}

	// A terrain-restricted method takes only its own terrain, in its own game.
	radar := Route{GameID: 4, RequiresKind: "wild", RequiresTerrain: "grass"}
	got := MatchLocations(radar, locs, 5)
	if len(got) != 1 || got[0].Area != "route-210-area" {
		t.Fatalf("grass-restricted route: got %+v", got)
	}

	// A generic method (no terrain requirement) takes every terrain EXCEPT
	// friend_safari, mirroring computeAvailability in cmd/seed/main.go.
	generic := Route{GameID: 4, RequiresKind: "wild", RequiresTerrain: ""}
	got = MatchLocations(generic, locs, 5)
	if len(got) != 2 {
		t.Fatalf("generic route: want 2 (grass+surf, not friend_safari), got %+v", got)
	}
	// Ordered by chance descending.
	if got[0].Area != "lake-verity-area" {
		t.Errorf("want highest chance first, got %q", got[0].Area)
	}
}

func TestMatchLocationsNonWildKindsHaveNone(t *testing.T) {
	locs := []Location{{GameID: 4, Area: "route-210-area", Terrain: "grass", Chance: 15}}
	for _, kind := range []string{"egg", "static", "raid"} {
		r := Route{GameID: 4, RequiresKind: kind}
		if got := MatchLocations(r, locs, 5); len(got) != 0 {
			t.Errorf("kind %q: want no locations, got %+v", kind, got)
		}
	}
}

func TestMatchLocationsCaps(t *testing.T) {
	var locs []Location
	for i := 0; i < 20; i++ {
		locs = append(locs, Location{GameID: 4, Area: "a", Terrain: "grass", Chance: i})
	}
	r := Route{GameID: 4, RequiresKind: "wild"}
	if got := MatchLocations(r, locs, 5); len(got) != 5 {
		t.Fatalf("want cap of 5, got %d", len(got))
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/calc/ -run TestMatchLocations -v`
Expected: FAIL — `undefined: Location`, `undefined: MatchLocations`, and unknown fields `RequiresKind`/`RequiresTerrain`.

- [ ] **Step 3: Extend the types and add `MatchLocations`**

In `backend/internal/calc/routes.go`, add these two fields to `MethodCandidate`:

```go
	RequiresKind    string // 'wild' | 'static' | 'raid' | 'egg'
	RequiresTerrain string // "" means "any terrain"
```

Add these three fields to `Route`. `RequiresKind` **is** serialized: the frontend needs it to tell "this method has no map location by nature" (breeding, soft-resets) apart from "we have no data for this game", and deriving that from `method_name` in the UI would duplicate backend knowledge and drift on any rename. `RequiresTerrain` stays internal.

```go
	RequiresKind    string     `json:"requires_kind"`
	RequiresTerrain string     `json:"-"`
	Locations       []Location `json:"locations"`
```

In `computeRoute`, carry them through by adding to the returned `Route` literal:

```go
		RequiresKind:    c.RequiresKind,
		RequiresTerrain: c.RequiresTerrain,
```

Add the `Location` type and matcher:

```go
// Location is one place a Pokemon can be encountered, for a specific version.
// GameID is a matching input, not part of the API payload.
type Location struct {
	GameID     int      `json:"-"`
	Area       string   `json:"area"`
	Version    string   `json:"version"`
	Terrain    string   `json:"terrain"`
	MinLevel   int      `json:"min_level"`
	MaxLevel   int      `json:"max_level"`
	Chance     int      `json:"chance"`
	Conditions []string `json:"conditions"`
}

// MatchLocations selects the locations that apply to one route, capped at max
// and ordered by encounter chance descending (then area, for stability).
//
// The terrain rule is copied verbatim from computeAvailability in
// cmd/seed/main.go: an explicit requires_terrain matches that terrain exactly,
// while a generic method (no requirement) matches every terrain EXCEPT
// friend_safari, which is a dedicated pool rather than a real terrain.
//
// Non-wild methods (egg/static/raid) have no location: Masuda breeding and
// soft-resetting do not happen at a place on the map.
func MatchLocations(r Route, locs []Location, max int) []Location {
	if r.RequiresKind != "wild" {
		return nil
	}
	out := make([]Location, 0, len(locs))
	for _, l := range locs {
		if l.GameID != r.GameID {
			continue
		}
		if r.RequiresTerrain != "" {
			if l.Terrain != r.RequiresTerrain {
				continue
			}
		} else if l.Terrain == "friend_safari" {
			continue
		}
		out = append(out, l)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Chance != out[j].Chance {
			return out[i].Chance > out[j].Chance
		}
		return out[i].Area < out[j].Area
	})
	if len(out) > max {
		out = out[:max]
	}
	return out
}
```

`sort` is already imported in `routes.go`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && go test ./internal/calc/ -v`
Expected: PASS, including the pre-existing `TestEffectiveOddsParity`.

- [ ] **Step 5: Select the new columns in `fetchMethodCandidates`**

In `backend/internal/api/dex.go`, change the query in `fetchMethodCandidates` to add two columns:

```go
	rows, err := database.DB.Query(ctx, `
		SELECT hm.id, g.id, g.title, hm.method_name, g.base_odds,
		       hm.base_rolls, hm.charm_rolls, hm.avg_time_seconds, ug.has_shiny_charm,
		       hm.formula_type, hm.requires_kind, COALESCE(hm.requires_terrain, '')
		FROM method_availability ma
		JOIN hunt_methods hm ON ma.method_id = hm.id
		JOIN games g         ON g.id = ma.game_id
		JOIN user_games ug   ON ug.game_id = g.id
		WHERE ma.pokemon_id = $1 AND ug.user_id = $2
		ORDER BY g.generation ASC, g.id ASC
	`, pokemonID, userID)
```

and extend the `Scan` to match:

```go
		if err := rows.Scan(&c.MethodID, &c.GameID, &c.GameTitle, &c.MethodName, &c.BaseOdds,
			&c.BaseRolls, &c.CharmRolls, &c.AvgTimeSeconds, &c.HasShinyCharm, &c.FormulaType,
			&c.RequiresKind, &c.RequiresTerrain); err != nil {
			return nil, err
		}
```

- [ ] **Step 6: Add `fetchLocations` to `dex.go`**

Append near `fetchMethodCandidates`:

```go
// fetchLocations returns every stored location for one Pokemon, across all
// games. Callers filter to a route's game and terrain via calc.MatchLocations.
func fetchLocations(ctx context.Context, pokemonID int) ([]calc.Location, error) {
	rows, err := database.DB.Query(ctx, `
		SELECT game_id, area, version, terrain,
		       COALESCE(min_level, 0), COALESCE(max_level, 0), COALESCE(chance, 0),
		       COALESCE(conditions, '{}')
		FROM pokemon_locations
		WHERE pokemon_id = $1
	`, pokemonID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []calc.Location
	for rows.Next() {
		var l calc.Location
		if err := rows.Scan(&l.GameID, &l.Area, &l.Version, &l.Terrain,
			&l.MinLevel, &l.MaxLevel, &l.Chance, &l.Conditions); err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}
```

- [ ] **Step 7: Attach locations in `PokemonRouteHandler`**

In `backend/internal/api/dex.go`, immediately before `resp.Routes = routes` (currently line 197), insert:

```go
		// Attach locations. An evolve route describes hunting the ANCESTOR, so
		// its locations come from EvolveFrom.PokemonID, not the target.
		locCache := map[int][]calc.Location{}
		for i := range routes {
			srcID := pokemonID
			if routes[i].EvolveFrom != nil {
				srcID = routes[i].EvolveFrom.PokemonID
			}
			locs, ok := locCache[srcID]
			if !ok {
				var err error
				locs, err = fetchLocations(ctx, srcID)
				if err != nil {
					log.Printf("warn: locations for #%d: %v", srcID, err)
					locs = nil
				}
				locCache[srcID] = locs
			}
			routes[i].Locations = calc.MatchLocations(routes[i], locs, 5)
			if routes[i].Locations == nil {
				routes[i].Locations = []calc.Location{}
			}
		}
```

The `nil` → empty-slice normalization keeps the JSON as `[]` rather than `null`, matching how the handler already normalizes `DexStatusResponse`.

- [ ] **Step 8: Verify the whole backend**

Run: `cd backend && go build ./... && go vet ./... && go test ./...`
Expected: clean.

- [ ] **Step 9: Verify the live endpoint**

Start the API (`cd backend && go run ./cmd/api/main.go`), then with a valid token:
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/pokemon/129/route | jq '.routes[] | {method_name, game_title, locations}'
```
Expected: wild-method routes carry a non-empty `locations` array with `area`, level range, and `chance`; egg/static/raid routes carry `[]`.

- [ ] **Step 10: Commit**

```bash
git add backend/internal/calc/routes.go backend/internal/calc/routes_test.go backend/internal/api/dex.go
git commit -m "feat(api): attach encounter locations to routes"
```

---

### Task 5: Render locations in `RouteList`

**Files:**
- Modify: `frontend/src/types/models.ts:75-86`
- Modify: `frontend/src/features/routes/RouteList.tsx`
- Modify: `frontend/src/index.css` (append the new classes)

**Interfaces:**
- Consumes: `locations` on each route from the API (Task 4)
- Produces: location rows rendered under every route, in both the dex drawer and the New Hunt modal (both already share `RouteList` via `usePokemonRoute`)

Because `DexDrawer` and `NewHuntModal` both render `RouteList`, this one change covers both surfaces.

- [ ] **Step 1: Add the types**

In `frontend/src/types/models.ts`, add above `PokemonRoute`:

```ts
export interface RouteLocation {
	area: string;
	version: string;
	terrain: string;
	min_level: number;
	max_level: number;
	chance: number;
	conditions: string[];
}
```

and add this field to `PokemonRoute`:

```ts
	requires_kind?: string;
	locations?: RouteLocation[];
```

Both optional because the suggestions endpoint embeds a `Route` too and older cached responses may omit them.

- [ ] **Step 2: Add the display helpers and render them in `RouteList.tsx`**

In `frontend/src/features/routes/RouteList.tsx`, change the type import line to:

```ts
import type { PokemonRoute, RouteLocation } from "../../types/models";
```

Add these helpers below `routeKey`:

```ts
// PokeAPI area slugs are kebab-case and often carry a trailing "-area":
// "route-210-area" -> "Route 210". Deliberately not a curated name table.
function formatArea(slug: string): string {
	return slug
		.replace(/-area$/, "")
		.split("-")
		.map((w) => w.charAt(0).toUpperCase() + w.slice(1))
		.join(" ");
}

// "time-night" -> "Night", "season-spring" -> "Spring".
function formatCondition(c: string): string {
	const last = c.split("-").pop() ?? c;
	return last.charAt(0).toUpperCase() + last.slice(1);
}

function formatLevels(l: RouteLocation): string {
	if (!l.min_level && !l.max_level) return "";
	if (l.min_level === l.max_level) return `Lv ${l.min_level}`;
	return `Lv ${l.min_level}-${l.max_level}`;
}
```

Add the `Locations` component below `Row`:

Task 6 adds an empty-state branch to this same component, so it takes the whole route now rather than just the array.

```tsx
const Locations: React.FC<{ route: PokemonRoute }> = ({ route }) => {
	const locations = route.locations;
	if (!locations || locations.length === 0) return null;
	return (
		<div className="dex-route-locs">
			{locations.map((l) => {
				const parts = [formatLevels(l), l.chance ? `${l.chance}%` : ""]
					.concat(l.conditions.map(formatCondition))
					.filter(Boolean);
				return (
					<div className="dex-route-loc" key={`${l.version}-${l.area}-${l.min_level}-${l.chance}`}>
						<span className="dex-route-loc-area">{formatArea(l.area)}</span>
						{parts.length > 0 && (
							<span className="dex-route-loc-meta"> · {parts.join(" · ")}</span>
						)}
					</div>
				);
			})}
		</div>
	);
};
```

Then render it inside `Row`, replacing the left-hand `<div>` (currently lines 106-114) with:

```tsx
			<div>
				<div className="dex-route-name">{r.method_name}</div>
				{showGame && (
					<div className="dex-route-game">
						{r.evolve_from ? `${r.evolve_from.name} · ${r.game_title}` : r.game_title}
					</div>
				)}
				{r.evolve_from && <div className="dex-route-evo">↳ then evolve</div>}
				<Locations route={r} />
			</div>
```

- [ ] **Step 3: Add the styles**

Append to `frontend/src/index.css`:

```css
.dex-route-locs {
	margin-top: 6px;
	display: flex;
	flex-direction: column;
	gap: 2px;
}

.dex-route-loc {
	font-size: 11px;
	line-height: 1.4;
	color: var(--text-dim, #8b95a7);
}

.dex-route-loc-area {
	color: var(--text-muted, #b6c0d1);
}

.dex-route-loc-meta {
	opacity: 0.75;
}
```

If `--text-dim` / `--text-muted` are not the token names used in `src/palette.ts`, substitute the nearest existing dim-text tokens rather than introducing new ones.

- [ ] **Step 4: Verify the build**

Run: `cd frontend && PATH="/opt/homebrew/opt/node@20/bin:$PATH" npm run build`
Expected: `✓ built in ...`, no TypeScript errors.

- [ ] **Step 5: Verify visually**

Start both servers (`cd backend && go run ./cmd/api/main.go`, and `cd frontend && PATH="/opt/homebrew/opt/node@20/bin:$PATH" npm run dev`). Open the dex, click a Pokémon with Gen 2–7 availability (e.g. Magikarp), and confirm:
- wild routes show location lines like `Route 210 · Lv 20-24 · 15% · Night`
- Masuda / static routes show no location block
- a Gen 8/9 game's routes show no location block rather than a broken empty region

- [ ] **Step 6: Commit**

```bash
git add frontend/src/types/models.ts frontend/src/features/routes/RouteList.tsx frontend/src/index.css
git commit -m "feat(ui): show encounter locations under each route"
```

---

### Task 6: Empty state for games without location data

**Files:**
- Modify: `frontend/src/features/routes/RouteList.tsx`

**Interfaces:**
- Consumes: `RouteLocation[]`, `formatArea` (Task 5)
- Produces: no new exports

The spec requires that Gen 8/9, BDSP, LGPE and LA render an explicit "no location data" state. Without it, a data gap silently reads as "there is nowhere to find this", which is a worse lie than saying nothing.

- [ ] **Step 1: Add the empty state to the `Locations` component**

`Locations` already takes the whole route (Task 5). Replace its `return null` early-exit with a version that distinguishes "no location by nature" from "no data":

```tsx
const Locations: React.FC<{ route: PokemonRoute }> = ({ route }) => {
	const locations = route.locations;
	if (locations && locations.length > 0) {
		return (
			<div className="dex-route-locs">
				{locations.map((l) => {
					const parts = [formatLevels(l), l.chance ? `${l.chance}%` : ""]
						.concat(l.conditions.map(formatCondition))
						.filter(Boolean);
					return (
						<div className="dex-route-loc" key={`${l.version}-${l.area}-${l.min_level}-${l.chance}`}>
							<span className="dex-route-loc-area">{formatArea(l.area)}</span>
							{parts.length > 0 && (
								<span className="dex-route-loc-meta"> · {parts.join(" · ")}</span>
							)}
						</div>
					);
				})}
			</div>
		);
	}
	// Breeding, soft-resets and raids have no map location by nature -- say
	// nothing. Anything else with no rows is a genuine data gap (Gen 8/9, BDSP,
	// LGPE, LA) and must say so, rather than read as "nowhere to find it".
	//
	// requires_kind comes from the backend so this check cannot drift from the
	// method data; do not re-derive it from method_name.
	if (route.requires_kind && route.requires_kind !== "wild") return null;
	return <div className="dex-route-loc dex-route-loc-empty">No location data for this game yet</div>;
};
```

The call site in `Row` already passes `route={r}` from Task 5 and needs no change.

- [ ] **Step 2: Add the style**

Append to `frontend/src/index.css`:

```css
.dex-route-loc-empty {
	font-style: italic;
	opacity: 0.55;
}
```

- [ ] **Step 3: Verify the build**

Run: `cd frontend && PATH="/opt/homebrew/opt/node@20/bin:$PATH" npm run build`
Expected: `✓ built in ...`, no TypeScript errors.

- [ ] **Step 4: Verify visually**

Open a Pokémon available in both an old and a modern game (e.g. Pikachu). Confirm the Gen 2–7 routes show areas, the SV/SwSh routes show "No location data for this game yet", and a Masuda route shows nothing at all.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/features/routes/RouteList.tsx frontend/src/index.css
git commit -m "feat(ui): explicit empty state for games without location data"
```

---

### Task 7: Document the new command

**Files:**
- Modify: `CLAUDE.md` (the Backend commands block)
- Modify: `TASKS.md` (operational notes)

**Interfaces:**
- Consumes: everything above
- Produces: no code

- [ ] **Step 1: Add the commands to `CLAUDE.md`**

In the Backend commands block, add:

```bash
go run ./cmd/migrate_locations/main.go  # Create pokemon_locations (additive, safe to re-run)
go run ./cmd/seed_locations/main.go     # Seed Gen 2-7 encounter locations from PokeAPI
```

- [ ] **Step 2: Add to the `TASKS.md` operational notes**

Under "Operational notes (for re-seeding the shared Supabase DB)", add:

```markdown
- **`cmd/seed_locations` is independent of the seed order above.** It touches only
  `pokemon_locations` and never `hunt_methods`, so it can be re-run at any time
  without the `cmd/sync` truncation hazard. It exits non-zero if any Gen 2-7 game
  ends up with zero rows.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md TASKS.md
git commit -m "docs: document location migration and seed commands"
```

---

## Definition of Done

- `go build ./...`, `go vet ./...`, `go test ./...` all clean
- `PATH="/opt/homebrew/opt/node@20/bin:$PATH" npm run build` succeeds
- `cmd/seed_locations` completes and reports non-zero rows for every Gen 2–7 game
- `GET /api/pokemon/{id}/route` returns `locations` on wild routes, `[]` on egg/static/raid routes
- Evolve routes show the **ancestor's** locations
- Gen 8/9/BDSP/LGPE/LA routes show the explicit empty state, not a blank region
