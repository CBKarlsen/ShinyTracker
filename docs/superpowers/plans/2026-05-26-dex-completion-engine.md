# Dex Completion Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Shiny Living Dex show, for every missing Pokémon, whether it's blocked (shiny-locked everywhere / not in your games) and the best route to obtain it across the games you own.

**Architecture:** Two new authenticated endpoints — `GET /api/dex/status` (bulk grid coloring) and `GET /api/pokemon/{id}/route` (per-Pokémon drawer data). All odds math runs server-side through `internal/calc`, with the rankable logic extracted into pure, unit-tested functions in `internal/calc/routes.go`. New data: a `shiny_locks` table (curated JSON seed) and a `pokemon.evolves_from_id` column (seeded during the existing PokeAPI crawl). The frontend `Collection` grid fetches dex status for four cell states and opens a detail drawer that fetches and renders routes.

**Tech Stack:** Go 1.26, chi, pgx (raw SQL), Go's built-in `testing`; React 19 + TypeScript + Vite, Biome.

**Reference spec:** `docs/superpowers/specs/2026-05-26-dex-completion-engine-design.md`

**Conventions:** No ORM — raw SQL with `$1/$2`. Seeds are idempotent (`ON CONFLICT`). No frontend test framework — verify with `npm run build` + `npm run lint` + manual/Playwright. Backend pure logic IS tested with `go test`. Commit after each task.

---

## File Structure

**Backend**
- `backend/schema.sql` — add `shiny_locks` table + `pokemon.evolves_from_id` column (MODIFY)
- `backend/internal/calc/routes.go` — pure, testable route/lock logic (CREATE)
- `backend/internal/calc/routes_test.go` — unit tests for the above (CREATE)
- `backend/internal/api/dex.go` — `DexStatusHandler` + `PokemonRouteHandler` + a shared candidate-fetch helper (CREATE)
- `backend/internal/api/router.go` — register the two routes (MODIFY)
- `backend/internal/services/pokeapi.go` — capture `evolves_from_species` (MODIFY)
- `backend/cmd/seed/main.go` — persist `evolves_from_id` (MODIFY)
- `backend/seeds/shiny_locks.json` — curated lock data (CREATE)
- `backend/cmd/seed_shiny_locks/main.go` — idempotent lock seeder (CREATE)

**Frontend**
- `frontend/src/types/models.ts` — add `DexStatus` / `PokemonRoute` types (MODIFY)
- `frontend/src/components/Collection.tsx` — fetch dex status, four cell states, open drawer (MODIFY)
- `frontend/src/components/DexDrawer.tsx` — the detail drawer (CREATE)
- `frontend/src/components/NewHuntModal.tsx` — accept a `prefill` prop (MODIFY)
- `frontend/src/App.tsx` — pass prefill state through to the modal (MODIFY)

---

## Task 1: Schema — shiny_locks table + evolves_from_id column

**Files:**
- Modify: `backend/schema.sql`

- [ ] **Step 1: Add the table and column to `schema.sql`**

Add after the `pokemon_availability` table block (around line 61):

```sql
-- shiny_locks: per-game shiny locks (Pokemon that cannot be encountered shiny
-- in a given game — box legendaries, gift starters, Meltan/Melmetal, etc.).
-- "Locked everywhere" is DERIVED (locked in every game it is available in),
-- not stored. Seeded from seeds/shiny_locks.json (idempotent).
CREATE TABLE IF NOT EXISTS shiny_locks (
    pokemon_id INTEGER REFERENCES pokemon(id) ON DELETE CASCADE,
    game_id    INTEGER REFERENCES games(id)   ON DELETE CASCADE,
    PRIMARY KEY (pokemon_id, game_id)
);
```

Add immediately after the `pokemon` table block (around line 19), so the column exists before anything references it:

```sql
-- evolves_from_id: single-parent pre-evolution pointer (PokeAPI evolves_from_species).
-- Walking this upward yields a Pokemon's full pre-evolution line. Used for
-- "hunt a pre-evolution, then evolve" route suggestions.
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS evolves_from_id INTEGER REFERENCES pokemon(id);
```

- [ ] **Step 2: Apply the schema**

Run: `cd backend && go run ./cmd/apply_schema/main.go`
Expected: `Schema applied successfully!`

- [ ] **Step 3: Verify the table and column exist**

Run:
```bash
cd backend && go run ./cmd/inspect_db/main.go 2>/dev/null | grep -i "shiny_locks\|evolves_from" || \
psql "$DATABASE_URL" -c "\d shiny_locks" -c "\d pokemon" 2>/dev/null | grep -i "evolves_from\|shiny_locks"
```
Expected: `shiny_locks` table and `evolves_from_id` column both reported. (If `inspect_db` doesn't print these, use the `psql` fallback.)

- [ ] **Step 4: Commit**

```bash
cd backend && git add schema.sql
git commit -m "Add shiny_locks table and pokemon.evolves_from_id column"
```

---

## Task 2: Pure route/lock logic in `internal/calc` (TDD)

This is the testable core: odds-per-route computation, ranking, locked-everywhere derivation, and the evolve-route inclusion rule. No DB — pure functions.

**Files:**
- Create: `backend/internal/calc/routes.go`
- Test: `backend/internal/calc/routes_test.go`

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/calc/routes_test.go`:

```go
package calc

import "testing"

func TestComputeRouteOddsWithAndWithoutCharm(t *testing.T) {
	// base_odds 4096, base_rolls 1, charm_rolls 2
	noCharm := computeRoute(MethodCandidate{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2, HasShinyCharm: false})
	if noCharm.Odds != 4096 {
		t.Fatalf("no-charm odds = %d, want 4096", noCharm.Odds)
	}
	withCharm := computeRoute(MethodCandidate{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2, HasShinyCharm: true})
	if withCharm.Odds != 1365 { // 4096 / (1+2)
		t.Fatalf("charm odds = %d, want 1365", withCharm.Odds)
	}
}

func TestRankDirectRoutesSortsAscendingByOdds(t *testing.T) {
	cands := []MethodCandidate{
		{GameID: 1, MethodName: "Wild", BaseOdds: 4096, BaseRolls: 1},
		{GameID: 2, MethodName: "Masuda", BaseOdds: 4096, BaseRolls: 6},
	}
	routes := RankDirectRoutes(cands)
	if len(routes) != 2 {
		t.Fatalf("got %d routes, want 2", len(routes))
	}
	if routes[0].MethodName != "Masuda" {
		t.Fatalf("best route = %q, want Masuda (better odds)", routes[0].MethodName)
	}
	if routes[0].Kind != "direct" {
		t.Fatalf("kind = %q, want direct", routes[0].Kind)
	}
}

func TestIsLockedEverywhere(t *testing.T) {
	if !IsLockedEverywhere([]int{3, 5}, []int{3, 5}) {
		t.Fatal("available in {3,5}, locked in {3,5} should be locked everywhere")
	}
	if IsLockedEverywhere([]int{3, 5}, []int{3}) {
		t.Fatal("available in {3,5} but locked only in {3} should NOT be locked everywhere")
	}
	if IsLockedEverywhere(nil, []int{3}) {
		t.Fatal("no availability should NOT be locked everywhere")
	}
}

func TestShouldIncludeEvolveRoute(t *testing.T) {
	ancestor := Route{Odds: 683}
	if !ShouldIncludeEvolveRoute(nil, ancestor) {
		t.Fatal("no target routes -> evolve route should be included")
	}
	worse := []Route{{Odds: 500}}
	if ShouldIncludeEvolveRoute(worse, ancestor) {
		t.Fatal("ancestor odds 683 worse than target best 500 -> should NOT include")
	}
	better := []Route{{Odds: 4096}}
	if !ShouldIncludeEvolveRoute(better, ancestor) {
		t.Fatal("ancestor odds 683 beats target best 4096 -> should include")
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && go test ./internal/calc/ -run 'Route|Locked|Evolve' -v`
Expected: FAIL — `undefined: computeRoute`, `undefined: MethodCandidate`, etc.

- [ ] **Step 3: Write the implementation**

Create `backend/internal/calc/routes.go`:

```go
package calc

import "sort"

// MethodCandidate is one huntable method for a Pokemon in a specific game,
// before odds are computed.
type MethodCandidate struct {
	GameID         int
	GameTitle      string
	MethodName     string
	BaseOdds       int
	BaseRolls      int
	CharmRolls     int
	HasShinyCharm  bool
	AvgTimeSeconds int
}

// EvolveFrom identifies the pre-evolution to hunt for an "evolve" route.
type EvolveFrom struct {
	PokemonID int    `json:"pokemon_id"`
	Name      string `json:"name"`
}

// Route is a computed, rankable way to obtain a shiny.
type Route struct {
	Kind       string      `json:"kind"` // "direct" or "evolve"
	GameID     int         `json:"game_id"`
	GameTitle  string      `json:"game_title"`
	MethodName string      `json:"method_name"`
	Odds       int         `json:"odds"` // denominator: 1 / Odds
	ETAHours   float64     `json:"eta_hours"`
	EvolveFrom *EvolveFrom `json:"evolve_from,omitempty"`
}

// computeRoute turns a candidate into a Route (Kind/EvolveFrom set by callers).
func computeRoute(c MethodCandidate) Route {
	totalRolls := c.BaseRolls
	if c.HasShinyCharm {
		totalRolls += c.CharmRolls
	}
	if totalRolls <= 0 {
		totalRolls = 1
	}
	odds := c.BaseOdds / totalRolls
	if odds < 1 {
		odds = 1
	}
	eta := CalculateEstimatedTimeHours(OddsConfig{
		BaseOdds:       c.BaseOdds,
		BaseRolls:      c.BaseRolls,
		CharmRolls:     c.CharmRolls,
		HasShinyCharm:  c.HasShinyCharm,
		AvgTimeSeconds: c.AvgTimeSeconds,
	})
	return Route{
		GameID:     c.GameID,
		GameTitle:  c.GameTitle,
		MethodName: c.MethodName,
		Odds:       odds,
		ETAHours:   eta,
	}
}

// RankDirectRoutes computes direct routes and sorts them ascending by odds.
func RankDirectRoutes(cands []MethodCandidate) []Route {
	routes := make([]Route, 0, len(cands))
	for _, c := range cands {
		r := computeRoute(c)
		r.Kind = "direct"
		routes = append(routes, r)
	}
	sort.SliceStable(routes, func(i, j int) bool { return routes[i].Odds < routes[j].Odds })
	return routes
}

// BestRoute returns the lowest-odds candidate as an evolve route for the given
// ancestor, plus ok=false when the ancestor has no candidates.
func BestRoute(cands []MethodCandidate, from EvolveFrom) (Route, bool) {
	ranked := RankDirectRoutes(cands)
	if len(ranked) == 0 {
		return Route{}, false
	}
	r := ranked[0]
	r.Kind = "evolve"
	r.EvolveFrom = &from
	return r, true
}

// IsLockedEverywhere reports whether a Pokemon is shiny-locked in every game it
// is available in. Returns false when there is no availability.
func IsLockedEverywhere(availGames, lockedGames []int) bool {
	if len(availGames) == 0 {
		return false
	}
	locked := make(map[int]bool, len(lockedGames))
	for _, g := range lockedGames {
		locked[g] = true
	}
	for _, g := range availGames {
		if !locked[g] {
			return false
		}
	}
	return true
}

// ShouldIncludeEvolveRoute decides whether to surface an evolve route: include
// it when the target has no direct route, or the ancestor's odds beat the
// target's best (targetRoutes must be sorted ascending by odds).
func ShouldIncludeEvolveRoute(targetRoutes []Route, ancestorBest Route) bool {
	if len(targetRoutes) == 0 {
		return true
	}
	return ancestorBest.Odds < targetRoutes[0].Odds
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && go test ./internal/calc/ -run 'Route|Locked|Evolve' -v`
Expected: PASS (all 4 tests).

- [ ] **Step 5: Commit**

```bash
cd backend && git add internal/calc/routes.go internal/calc/routes_test.go
git commit -m "Add pure route ranking + lock derivation logic with tests"
```

---

## Task 3: Capture evolves_from during the PokeAPI crawl

The existing seed already fetches every Pokémon from PokeAPI. PokeAPI exposes the parent on the **species** endpoint (`evolves_from_species`), which maps by name to a Pokémon id.

**Files:**
- Modify: `backend/internal/services/pokeapi.go`
- Modify: `backend/cmd/seed/main.go`

- [ ] **Step 1: Read the current fetch/seed flow**

Run: `cd backend && grep -n "evolves_from\|species\|func.*Fetch\|EvolvesFrom\|type.*Pokemon" internal/services/pokeapi.go cmd/seed/main.go`
Expected: confirms there is no `evolves_from` handling yet, and shows the Pokémon struct + where rows are upserted. Read those line ranges before editing.

- [ ] **Step 2: Add `EvolvesFromID` to the fetched Pokémon model**

In `internal/services/pokeapi.go`, add a field to the struct the fetcher returns for each Pokémon (the one already carrying `ID`, `Name`, `Types`, `SpriteURL`):

```go
EvolvesFromID *int // nil when the species has no pre-evolution
```

In the per-Pokémon fetch, after the existing species/detail fetch, decode `evolves_from_species` from the species JSON and resolve its name to an id:

```go
// speciesResp is the decoded /pokemon-species/{id} payload.
// Add this field to whatever struct already decodes the species response:
//   EvolvesFromSpecies *struct {
//       Name string `json:"name"`
//       URL  string `json:"url"`
//   } `json:"evolves_from_species"`
//
// The species URL ends in /pokemon-species/{id}/. Parse that trailing id —
// it equals the National Dex id for base-form species, which is what we store.
if speciesResp.EvolvesFromSpecies != nil {
	if id := idFromSpeciesURL(speciesResp.EvolvesFromSpecies.URL); id > 0 {
		p.EvolvesFromID = &id
	}
}
```

Add the small helper at the bottom of `pokeapi.go`:

```go
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
```

Ensure `strings` and `strconv` are imported in `pokeapi.go`.

- [ ] **Step 3: Persist `evolves_from_id` in the seed upsert**

In `cmd/seed/main.go`, find the Pokémon upsert (`INSERT INTO pokemon ... ON CONFLICT ...`) and add the new column. Because the parent may not exist yet when a child is inserted, write `evolves_from_id` in a **second pass after all Pokémon are inserted** so the FK always resolves:

```go
// After the main pokemon upsert loop, backfill parent pointers.
for _, p := range pokemons {
	if p.EvolvesFromID == nil {
		continue
	}
	if _, err := database.DB.Exec(context.Background(),
		`UPDATE pokemon SET evolves_from_id = $2 WHERE id = $1`,
		p.ID, *p.EvolvesFromID); err != nil {
		log.Printf("warn: evolves_from for #%d -> #%d: %v", p.ID, *p.EvolvesFromID, err)
	}
}
```

(Use the same slice variable the seed already iterates; if it streams instead of collecting, collect parent pairs into a `[][2]int` during the main loop and run this backfill afterward.)

- [ ] **Step 4: Build**

Run: `cd backend && go build ./...`
Expected: builds clean.

- [ ] **Step 5: Run the seed and verify parents populated**

Run: `cd backend && go run ./cmd/seed/main.go`
Then verify a known line (Gyarados #130 evolves from Magikarp #129):
```bash
psql "$DATABASE_URL" -c "SELECT id, name, evolves_from_id FROM pokemon WHERE id IN (129,130);"
```
Expected: row #130 has `evolves_from_id = 129`; #129 has NULL.

- [ ] **Step 6: Commit**

```bash
cd backend && git add internal/services/pokeapi.go cmd/seed/main.go
git commit -m "Seed pokemon.evolves_from_id from PokeAPI species data"
```

---

## Task 4: Shiny-lock seed data + seeder

The lock dataset is curated, like `legendary_encounters.json`. Locks are keyed by Pokémon and the games where the shiny is locked.

**Files:**
- Create: `backend/seeds/shiny_locks.json`
- Create: `backend/cmd/seed_shiny_locks/main.go`

- [ ] **Step 1: Inspect the games table for stable keys**

Run: `cd backend && go run ./cmd/print_games/main.go`
Expected: a list of `id` / `title`. Use the **exact titles** as the JSON keys below (the seeder maps title → id, matching `seed_availability`'s approach).

- [ ] **Step 2: Create the seed file**

Create `backend/seeds/shiny_locks.json`. Structure: each entry is a Pokémon id with the list of game titles where its shiny is locked. Starter set of well-established global locks (expand per the checklist in Step 3):

```json
{
  "_comment": "pokemon_id -> list of game titles where the shiny form is locked. Titles must match the games table exactly.",
  "locks": [
    { "pokemon_id": 716, "games": ["Pokémon X", "Pokémon Y"] },
    { "pokemon_id": 717, "games": ["Pokémon X", "Pokémon Y"] },
    { "pokemon_id": 718, "games": ["Pokémon X", "Pokémon Y"] },
    { "pokemon_id": 808, "games": ["Pokémon: Let's Go, Pikachu!", "Pokémon: Let's Go, Eevee!"] },
    { "pokemon_id": 809, "games": ["Pokémon: Let's Go, Pikachu!", "Pokémon: Let's Go, Eevee!"] }
  ]
}
```

- [ ] **Step 3: Expand the dataset (curation sub-task)**

This is real data work, not a placeholder — cover these well-documented lock categories, using the exact game titles from Step 1. Mark each line item done as you add it:
  - [ ] Box legendaries in their origin games (e.g. Xerneas/Yveltal/Zygarde XY; Cosmog→Solgaleo/Lunala SM/USUM; Zacian/Zamazenta SwSh; Koraidon/Miraidon SV).
  - [ ] Gift starters where the gift is shiny-locked (per game).
  - [ ] Story/gift mythicals and event-locked species (Meltan/Melmetal #808/#809; others as applicable).
  - [ ] Static story encounters that are shiny-locked in the relevant game only.

Source against Bulbapedia / Serebii "shiny-locked" lists per game. A Pokémon huntable shiny in *any* game it appears in must NOT be listed for that game.

- [ ] **Step 4: Write the seeder**

Create `backend/cmd/seed_shiny_locks/main.go` (mirrors `seed_availability`'s connect + title→id map pattern):

```go
package main

import (
	"context"
	"encoding/json"
	"log"
	"os"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

type lockEntry struct {
	PokemonID int      `json:"pokemon_id"`
	Games     []string `json:"games"`
}
type lockFile struct {
	Locks []lockEntry `json:"locks"`
}

func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	path := "seeds/shiny_locks.json"
	if len(os.Args) > 1 {
		path = os.Args[1]
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		log.Fatalf("read %q: %v", path, err)
	}
	var lf lockFile
	if err := json.Unmarshal(raw, &lf); err != nil {
		log.Fatalf("parse %q: %v", path, err)
	}

	// title -> id
	rows, err := database.DB.Query(context.Background(), "SELECT id, title FROM games")
	if err != nil {
		log.Fatal("fetch games:", err)
	}
	gameID := map[string]int{}
	for rows.Next() {
		var id int
		var title string
		if err := rows.Scan(&id, &title); err == nil {
			gameID[title] = id
		}
	}
	rows.Close()

	inserted, skipped := 0, 0
	for _, e := range lf.Locks {
		for _, title := range e.Games {
			gid, ok := gameID[title]
			if !ok {
				log.Printf("warn: unknown game title %q (pokemon #%d) — skipped", title, e.PokemonID)
				skipped++
				continue
			}
			ct, err := database.DB.Exec(context.Background(),
				`INSERT INTO shiny_locks (pokemon_id, game_id) VALUES ($1, $2)
				 ON CONFLICT DO NOTHING`,
				e.PokemonID, gid)
			if err != nil {
				log.Printf("warn: insert lock #%d/%s: %v", e.PokemonID, title, err)
				continue
			}
			if ct.RowsAffected() > 0 {
				inserted++
			} else {
				skipped++
			}
		}
	}
	log.Printf("shiny_locks seeded: %d inserted, %d skipped", inserted, skipped)
}
```

- [ ] **Step 5: Build, run, verify**

Run:
```bash
cd backend && go build ./... && go run ./cmd/seed_shiny_locks/main.go
psql "$DATABASE_URL" -c "SELECT pokemon_id, count(*) FROM shiny_locks GROUP BY pokemon_id ORDER BY pokemon_id;"
```
Expected: seeder logs an insert count with no `unknown game title` warnings; the query lists the locked Pokémon.

- [ ] **Step 6: Commit**

```bash
cd backend && git add seeds/shiny_locks.json cmd/seed_shiny_locks/main.go
git commit -m "Add shiny_locks seed data and idempotent seeder"
```

---

## Task 5: `GET /api/dex/status` endpoint

**Files:**
- Create: `backend/internal/api/dex.go`
- Modify: `backend/internal/api/router.go`

- [ ] **Step 1: Write the handler**

Create `backend/internal/api/dex.go`:

```go
package api

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/casper/shinytracker/internal/database"
)

type DexStatusResponse struct {
	NotInYourGames  []int `json:"not_in_your_games"`
	LockedEverywhere []int `json:"locked_everywhere"`
}

// DexStatusHandler returns, for the authenticated user, the Pokemon that are
// locked everywhere (globally) and the ones not available in any owned game.
func DexStatusHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	if userID == "" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	ctx := context.Background()

	// Available somewhere, but zero owned-game availability.
	notInGames, err := queryIntColumn(ctx, `
		SELECT pa.pokemon_id
		FROM pokemon_availability pa
		GROUP BY pa.pokemon_id
		HAVING COUNT(*) FILTER (
			WHERE pa.game_id IN (SELECT game_id FROM user_games WHERE user_id = $1)
		) = 0
	`, userID)
	if err != nil {
		http.Error(w, "Failed to compute dex status", http.StatusInternalServerError)
		return
	}

	// Available in >=1 game and locked in all of them (global).
	lockedEverywhere, err := queryIntColumn(ctx, `
		SELECT pa.pokemon_id
		FROM pokemon_availability pa
		LEFT JOIN shiny_locks sl
		  ON sl.pokemon_id = pa.pokemon_id AND sl.game_id = pa.game_id
		GROUP BY pa.pokemon_id
		HAVING COUNT(*) = COUNT(sl.pokemon_id)
	`)
	if err != nil {
		http.Error(w, "Failed to compute dex status", http.StatusInternalServerError)
		return
	}

	resp := DexStatusResponse{NotInYourGames: notInGames, LockedEverywhere: lockedEverywhere}
	if resp.NotInYourGames == nil {
		resp.NotInYourGames = []int{}
	}
	if resp.LockedEverywhere == nil {
		resp.LockedEverywhere = []int{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// queryIntColumn runs a query whose first column is an int and returns all values.
func queryIntColumn(ctx context.Context, sql string, args ...any) ([]int, error) {
	rows, err := database.DB.Query(ctx, sql, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []int
	for rows.Next() {
		var v int
		if err := rows.Scan(&v); err != nil {
			return nil, err
		}
		out = append(out, v)
	}
	return out, rows.Err()
}
```

> Note: the `locked_everywhere` query takes no user arg by design — it's a global property. The imports above are exactly what `DexStatusHandler` + `queryIntColumn` need; Task 6 adds `strconv`, `chi`, and `internal/calc` when its handler is appended to this file. `PokemonRouteHandler` is referenced by the router in Step 2 — stub it (`func PokemonRouteHandler(w http.ResponseWriter, r *http.Request) {}`) if you build Task 5 before Task 6, then replace the stub in Task 6.

- [ ] **Step 2: Register the route**

In `backend/internal/api/router.go`, inside the authenticated group (after the `r.Get("/hunt-methods", ...)` line at 47), add:

```go
			r.Get("/dex/status", DexStatusHandler)
			r.Get("/pokemon/{id}/route", PokemonRouteHandler)
```

(Both registered now so Task 6 only adds the handler body. `PokemonRouteHandler` must exist for the build to pass — implement Task 6 in the same working session, or temporarily stub it: `func PokemonRouteHandler(w http.ResponseWriter, r *http.Request) {}`.)

- [ ] **Step 3: Build**

Run: `cd backend && go build ./...`
Expected: builds clean (with Task 6's handler present or stubbed).

- [ ] **Step 4: Manual smoke test**

Run the API (`go run ./cmd/api/main.go`), then with a valid token:
```bash
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/dex/status | head -c 300
```
Expected: JSON with `not_in_your_games` and `locked_everywhere` arrays. With Xerneas (#716) locked in all its games, `716` appears in `locked_everywhere`.

- [ ] **Step 5: Commit**

```bash
cd backend && git add internal/api/dex.go internal/api/router.go
git commit -m "Add GET /api/dex/status for grid blocked-state coloring"
```

---

## Task 6: `GET /api/pokemon/{id}/route` endpoint

**Files:**
- Modify: `backend/internal/api/dex.go`

- [ ] **Step 1: Extend the imports, then add the candidate-fetch helper**

First update the import block in `backend/internal/api/dex.go` to add the three new imports Task 6 needs:

```go
import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/casper/shinytracker/internal/calc"
	"github.com/casper/shinytracker/internal/database"
	"github.com/go-chi/chi/v5"
)
```

Then append the helper. This reuses the exact join from `GetHuntMethodsHandler`, extended with `g.base_odds` and `ug.has_shiny_charm`:

```go
// fetchMethodCandidates returns the huntable methods for a Pokemon in the
// user's owned games, with the data needed to compute odds.
func fetchMethodCandidates(ctx context.Context, userID string, pokemonID int) ([]calc.MethodCandidate, error) {
	rows, err := database.DB.Query(ctx, `
		SELECT g.id, g.title, hm.method_name, g.base_odds,
		       hm.base_rolls, hm.charm_rolls, hm.avg_time_seconds, ug.has_shiny_charm
		FROM method_availability ma
		JOIN hunt_methods hm ON ma.method_id = hm.id
		JOIN games g         ON g.id = ma.game_id
		JOIN user_games ug   ON ug.game_id = g.id
		WHERE ma.pokemon_id = $1 AND ug.user_id = $2
		ORDER BY g.generation ASC, g.id ASC
	`, pokemonID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var cands []calc.MethodCandidate
	for rows.Next() {
		var c calc.MethodCandidate
		if err := rows.Scan(&c.GameID, &c.GameTitle, &c.MethodName, &c.BaseOdds,
			&c.BaseRolls, &c.CharmRolls, &c.AvgTimeSeconds, &c.HasShinyCharm); err != nil {
			return nil, err
		}
		cands = append(cands, c)
	}
	return cands, rows.Err()
}
```

- [ ] **Step 2: Implement the handler (replace any stub)**

```go
type PokemonRouteResponse struct {
	Status string       `json:"status"` // available | not_in_your_games | locked_everywhere
	Routes []calc.Route `json:"routes"`
}

// PokemonRouteHandler returns blocked status + ranked routes (direct + evolve)
// for one Pokemon, scoped to the authenticated user's owned games.
func PokemonRouteHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	if userID == "" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}
	pokemonID, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, "id must be an integer", http.StatusBadRequest)
		return
	}
	ctx := context.Background()

	// Availability + locks for status.
	availGames, err := queryIntColumn(ctx,
		`SELECT game_id FROM pokemon_availability WHERE pokemon_id = $1`, pokemonID)
	if err != nil {
		http.Error(w, "Failed to load availability", http.StatusInternalServerError)
		return
	}
	lockedGames, err := queryIntColumn(ctx,
		`SELECT game_id FROM shiny_locks WHERE pokemon_id = $1`, pokemonID)
	if err != nil {
		http.Error(w, "Failed to load locks", http.StatusInternalServerError)
		return
	}
	ownedGames, err := queryIntColumn(ctx,
		`SELECT game_id FROM user_games WHERE user_id = $1`, userID)
	if err != nil {
		http.Error(w, "Failed to load games", http.StatusInternalServerError)
		return
	}

	resp := PokemonRouteResponse{Routes: []calc.Route{}}
	switch {
	case calc.IsLockedEverywhere(availGames, lockedGames):
		resp.Status = "locked_everywhere"
	case len(availGames) > 0 && !anyOwned(availGames, ownedGames):
		resp.Status = "not_in_your_games"
	default:
		resp.Status = "available"
	}

	if resp.Status == "available" {
		direct, err := fetchMethodCandidates(ctx, userID, pokemonID)
		if err != nil {
			http.Error(w, "Failed to load routes", http.StatusInternalServerError)
			return
		}
		routes := calc.RankDirectRoutes(direct)

		// Evolve routes: walk ancestors, include the better/only ones.
		ancestors, err := fetchAncestors(ctx, pokemonID)
		if err != nil {
			http.Error(w, "Failed to load evolution line", http.StatusInternalServerError)
			return
		}
		for _, anc := range ancestors {
			cands, err := fetchMethodCandidates(ctx, userID, anc.PokemonID)
			if err != nil || len(cands) == 0 {
				continue
			}
			best, ok := calc.BestRoute(cands, anc)
			if ok && calc.ShouldIncludeEvolveRoute(routes, best) {
				routes = append(routes, best)
			}
		}
		resp.Routes = routes
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// anyOwned reports whether any availability game is in the owned set.
func anyOwned(avail, owned []int) bool {
	set := make(map[int]bool, len(owned))
	for _, g := range owned {
		set[g] = true
	}
	for _, g := range avail {
		if set[g] {
			return true
		}
	}
	return false
}

// fetchAncestors returns the pre-evolution line (nearest first) for a Pokemon.
func fetchAncestors(ctx context.Context, pokemonID int) ([]calc.EvolveFrom, error) {
	rows, err := database.DB.Query(ctx, `
		WITH RECURSIVE line AS (
			SELECT id, evolves_from_id FROM pokemon WHERE id = $1
			UNION ALL
			SELECT p.id, p.evolves_from_id
			FROM pokemon p JOIN line ON p.id = line.evolves_from_id
		)
		SELECT p.id, p.name
		FROM line JOIN pokemon p ON p.id = line.id
		WHERE line.id <> $1
	`, pokemonID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []calc.EvolveFrom
	for rows.Next() {
		var e calc.EvolveFrom
		if err := rows.Scan(&e.PokemonID, &e.Name); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
```

- [ ] **Step 3: Build**

Run: `cd backend && go build ./...`
Expected: builds clean; `calc`, `strconv`, `chi` imports from Task 5 are now all used.

- [ ] **Step 4: Manual verification across the three states**

With the API running and a token for a user who owns, say, Scarlet/Violet:
```bash
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/pokemon/130/route   # Gyarados: available, has direct + maybe evolve
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/pokemon/716/route   # Xerneas: locked_everywhere, no routes
curl -s -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/pokemon/495/route   # Snivy (if not in owned games): not_in_your_games
```
Expected: statuses as annotated; Gyarados routes sorted ascending by `odds`; any evolve route carries `evolve_from`.

- [ ] **Step 5: Commit**

```bash
cd backend && git add internal/api/dex.go
git commit -m "Add GET /api/pokemon/{id}/route with ranked direct + evolve routes"
```

---

## Task 7: Frontend — dex status fetch + four cell states

**Files:**
- Modify: `frontend/src/types/models.ts`
- Modify: `frontend/src/components/Collection.tsx`

- [ ] **Step 1: Add types**

In `frontend/src/types/models.ts`, add:

```ts
export interface DexStatus {
	not_in_your_games: number[];
	locked_everywhere: number[];
}

export interface PokemonRoute {
	kind: "direct" | "evolve";
	game_id: number;
	game_title: string;
	method_name: string;
	odds: number;
	eta_hours: number;
	evolve_from?: { pokemon_id: number; name: string };
}

export interface PokemonRouteResponse {
	status: "available" | "not_in_your_games" | "locked_everywhere";
	routes: PokemonRoute[];
}
```

- [ ] **Step 2: Fetch dex status in Collection**

In `Collection.tsx`, add state and extend the existing `Promise.all` fetch (lines 37–42). Add:

```tsx
const [blocked, setBlocked] = useState<{ locked: Set<number>; notInGames: Set<number> }>(
	{ locked: new Set(), notInGames: new Set() },
);
```

Add a third request to the `Promise.all`:

```tsx
const [pokeRes, huntsRes, statusRes] = await Promise.all([
	fetch("http://localhost:8080/api/pokemon?limit=all"),
	fetch("http://localhost:8080/api/hunts", {
		headers: { Authorization: `Bearer ${token}` },
	}),
	fetch("http://localhost:8080/api/dex/status", {
		headers: { Authorization: `Bearer ${token}` },
	}),
]);
```

After setting `caughtIds`, parse status (degrade gracefully — the grid must still render if this fails):

```tsx
if (statusRes.ok) {
	const s: import("../types/models").DexStatus = await statusRes.json();
	setBlocked({
		locked: new Set(s.locked_everywhere),
		notInGames: new Set(s.not_in_your_games),
	});
}
```

- [ ] **Step 3: Compute and render the four cell states**

Replace the cell render (lines 274–289) so each cell resolves one state with precedence caught > locked > not-in-games > missing, and clicking opens the drawer instead of toggling directly:

```tsx
{cellsInGen.map((p) => {
	const caught = caughtIds.has(p.id);
	const state = caught
		? "caught"
		: blocked.locked.has(p.id)
			? "locked"
			: blocked.notInGames.has(p.id)
				? "notgames"
				: "missing";
	return (
		<div
			key={p.id}
			className={`dex-cell ${state}`}
			onClick={() => setDrawerId(p.id)}
			title={p.name}
		>
			<img
				src={`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${caught ? "shiny/" : ""}${p.id}.png`}
				alt={p.name}
				loading="lazy"
			/>
		</div>
	);
})}
```

Add `const [drawerId, setDrawerId] = useState<number | null>(null);` with the other state. (The drawer itself, plus its `onCaughtChange` callback that mutates `caughtIds`, is wired in Task 8.)

- [ ] **Step 4: Add cell-state styles**

In the stylesheet that defines `.dex-cell` (search: `grep -rn "dex-cell" frontend/src`), add the two new states alongside the existing `.caught` / `.uncaught` rules:

```css
.dex-cell.locked { background: repeating-linear-gradient(45deg,#2a1d1d,#2a1d1d 4px,#3a2424 4px,#3a2424 8px); opacity: .7; }
.dex-cell.notgames { filter: grayscale(1); opacity: .45; }
```

(Keep `.missing` mapped to the current uncaught styling — if the existing class is `.uncaught`, either add `missing` to that selector or rename consistently. Match whatever the file already uses.)

- [ ] **Step 5: Verify build + lint**

Run: `cd frontend && npm run lint && npm run build`
Expected: both pass. (A transient "drawerId set but unused" can occur until Task 8 consumes it — if lint flags it, proceed directly into Task 8 in the same session.)

- [ ] **Step 6: Commit**

```bash
cd frontend && git add src/types/models.ts src/components/Collection.tsx src/index.css
git commit -m "Add dex status fetch and four grid cell states; click opens drawer"
```

(Adjust the CSS path in `git add` to wherever `.dex-cell` lives.)

---

## Task 8: Frontend — detail drawer

**Files:**
- Create: `frontend/src/components/DexDrawer.tsx`
- Modify: `frontend/src/components/Collection.tsx`

- [ ] **Step 1: Build the drawer component**

Create `frontend/src/components/DexDrawer.tsx`. It fetches the route on open, renders the three statuses + the data-gap case, and exposes mark-caught / remove and start-hunt callbacks. Visual structure follows the approved mockup (header + flat **Routes** list + **Hunt a pre-evolution** section + actions):

```tsx
import type React from "react";
import { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";
import { useNotification } from "../context/NotificationContext";
import type { Pokemon, PokemonRouteResponse, PokemonRoute } from "../types/models";

interface Props {
	pokemon: Pokemon;
	caught: boolean;
	onClose: () => void;
	onCaughtChange: (pokemonId: number, caught: boolean) => void;
	onStartHunt: (route: PokemonRoute, pokemon: Pokemon) => void;
}

const DexDrawer: React.FC<Props> = ({ pokemon, caught, onClose, onCaughtChange, onStartHunt }) => {
	const { token } = useAuth();
	const { showError } = useNotification();
	const [data, setData] = useState<PokemonRouteResponse | null>(null);
	const [loading, setLoading] = useState(true);
	const [error, setError] = useState(false);

	useEffect(() => {
		let active = true;
		setLoading(true);
		setError(false);
		fetch(`http://localhost:8080/api/pokemon/${pokemon.id}/route`, {
			headers: { Authorization: `Bearer ${token}` },
		})
			.then((r) => (r.ok ? r.json() : Promise.reject()))
			.then((d: PokemonRouteResponse) => active && setData(d))
			.catch(() => active && setError(true))
			.finally(() => active && setLoading(false));
		return () => {
			active = false;
		};
	}, [pokemon.id, token]);

	const markCaught = async () => {
		onCaughtChange(pokemon.id, true); // optimistic
		try {
			const res = await fetch("http://localhost:8080/api/hunts/manual", {
				method: "POST",
				headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
				body: JSON.stringify({ pokemon_id: pokemon.id }),
			});
			if (!res.ok) throw new Error();
		} catch {
			onCaughtChange(pokemon.id, false); // rollback
			showError("Failed to mark as caught.");
		}
	};

	const removeCaught = async () => {
		onCaughtChange(pokemon.id, false); // optimistic
		try {
			const res = await fetch(`http://localhost:8080/api/hunts/manual/${pokemon.id}`, {
				method: "DELETE",
				headers: { Authorization: `Bearer ${token}` },
			});
			if (!res.ok) throw new Error();
		} catch {
			onCaughtChange(pokemon.id, true); // rollback
			showError("Failed to remove from dex.");
		}
	};

	const direct = data?.routes.filter((r) => r.kind === "direct") ?? [];
	const evolve = data?.routes.filter((r) => r.kind === "evolve") ?? [];

	return (
		<div className="scrim" onClick={onClose}>
			<div className="drawer" onClick={(e) => e.stopPropagation()} style={{ width: 360, padding: 0 }}>
				<div className="dex-drawer-head">
					<img
						src={`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${caught ? "shiny/" : ""}${pokemon.id}.png`}
						alt={pokemon.name}
						width={60}
						height={60}
					/>
					<div>
						<div className="dex-drawer-name">{pokemon.name}</div>
						<div className="dex-drawer-dex">#{pokemon.id}</div>
						<span className={`dex-badge ${caught ? "b-caught" : data?.status ?? ""}`}>
							{caught
								? "✓ Caught"
								: data?.status === "locked_everywhere"
									? "🔒 Shiny-locked"
									: data?.status === "not_in_your_games"
										? "🚫 Not in your games"
										: "● Missing"}
						</span>
					</div>
				</div>

				<div style={{ padding: 16 }}>
					{loading && <div className="t-mono">Loading routes…</div>}
					{error && <div className="t-mono">Couldn't load routes — you can still mark it caught.</div>}

					{!loading && !error && data && (
						<>
							{data.status === "available" && direct.length === 0 && evolve.length === 0 && (
								<div className="t-mono" style={{ marginBottom: 12 }}>
									Available in your games, but no hunt method recorded yet.
								</div>
							)}

							{direct.length > 0 && (
								<RouteSection label="Routes in your games" routes={direct}
									onStart={(r) => onStartHunt(r, pokemon)} />
							)}
							{evolve.length > 0 && (
								<RouteSection label="Hunt a pre-evolution" routes={evolve}
									onStart={(r) => onStartHunt(r, pokemon)} />
							)}

							{data.status === "locked_everywhere" && (
								<div className="t-mono">
									Shiny-locked in every game it appears in. Obtain it by trading or transferring from Pokémon HOME.
								</div>
							)}
							{data.status === "not_in_your_games" && (
								<div className="t-mono">Not available in any game you own. Add a game to your library, or trade for it.</div>
							)}
						</>
					)}

					<div style={{ marginTop: 16 }}>
						{caught ? (
							<button className="btn danger" style={{ width: "100%" }} onClick={removeCaught}>Remove from dex</button>
						) : (
							<button className="btn ghost" style={{ width: "100%" }} onClick={markCaught}>Mark as caught</button>
						)}
					</div>
				</div>
			</div>
		</div>
	);
};

const RouteSection: React.FC<{ label: string; routes: PokemonRoute[]; onStart: (r: PokemonRoute) => void }> = ({ label, routes, onStart }) => (
	<div style={{ marginBottom: 14 }}>
		<div className="t-label" style={{ marginBottom: 8 }}>{label}</div>
		{routes.map((r, i) => (
			<div key={`${r.kind}-${r.game_id}-${r.method_name}-${i}`} className="dex-route">
				<div>
					<div className="dex-route-name">{r.method_name}</div>
					<div className="dex-route-game">
						{r.evolve_from ? `${r.evolve_from.name} · ${r.game_title}` : r.game_title}
					</div>
					{r.evolve_from && <div className="dex-route-evo">↳ then evolve</div>}
				</div>
				<div style={{ textAlign: "right" }}>
					<div className="dex-route-odds">1 / {r.odds.toLocaleString()}</div>
					<div className="dex-route-eta">~{r.eta_hours.toFixed(1)} h</div>
					<button className="dex-route-start" onClick={() => onStart(r)}>▸ Start</button>
				</div>
			</div>
		))}
	</div>
);

export default DexDrawer;
```

- [ ] **Step 2: Add drawer styles**

In the same stylesheet as the cell states, add minimal classes (`dex-drawer-head`, `dex-drawer-name`, `dex-drawer-dex`, `dex-badge`, `dex-route`, `dex-route-name/game/evo/odds/eta/start`) following the existing dark/gold tokens (`--ink-*`, `--bg-*`, `--line-*`, `--gold`, `--font-mono`). Use the approved mockup (`/.superpowers/brainstorm/.../drawer-v2.html`) as the visual reference for spacing/colors.

- [ ] **Step 3: Mount the drawer in Collection**

In `Collection.tsx`, render the drawer when `drawerId` is set, and provide the caught-mutation callback (replacing the old inline toggle + remove-confirm flow, since the drawer now owns those actions):

```tsx
{drawerId !== null && (() => {
	const p = pokemon.find((x) => x.id === drawerId);
	if (!p) return null;
	return (
		<DexDrawer
			pokemon={p}
			caught={caughtIds.has(p.id)}
			onClose={() => setDrawerId(null)}
			onCaughtChange={(id, isCaught) => {
				setCaughtIds((prev) => {
					const next = new Set(prev);
					if (isCaught) next.add(id);
					else next.delete(id);
					return next;
				});
			}}
			onStartHunt={(route, poke) => {
				setDrawerId(null);
				onStartHunt?.(poke, route); // wired in Task 9
			}}
		/>
	);
})()}
```

Add `import DexDrawer from "./DexDrawer";`. The old `handleToggle`, `confirmRemove`, and `removeTarget` modal can be removed — the drawer supersedes them.

- [ ] **Step 4: Verify build + lint**

Run: `cd frontend && npm run lint && npm run build`
Expected: both pass. (`onStartHunt` is threaded through in Task 9; until then, make it optional in Collection's props so the build passes.)

- [ ] **Step 5: Manual check**

Start backend + `npm run dev`. Open Collection:
- A missing Pokémon (e.g. Gyarados) → drawer shows ranked routes + a "Hunt a pre-evolution" section when applicable.
- Xerneas → 🔒 badge, lock explanation, no routes.
- A Pokémon not in your owned games → 🚫 badge.
- Mark as caught → cell flips to the shiny sprite + gold ring; Remove reverts it.

- [ ] **Step 6: Commit**

```bash
cd frontend && git add src/components/DexDrawer.tsx src/components/Collection.tsx src/index.css
git commit -m "Add dex detail drawer: routes, blocked states, mark-caught"
```

---

## Task 9: Wire "Start this hunt" prefill + remove duplicated odds

**Files:**
- Modify: `frontend/src/components/NewHuntModal.tsx`
- Modify: `frontend/src/App.tsx`
- Modify: `frontend/src/components/Collection.tsx`
- Modify: `frontend/src/features/new-hunt/MethodPreview.tsx` (+ `NewHuntModal.tsx`) — drop `getOddsForMethod`

- [ ] **Step 1: Add a `prefill` prop to NewHuntModal**

Extend `Props` (line 9):

```tsx
interface Props {
	open: boolean;
	onClose: () => void;
	onGoToGames?: () => void;
	prefill?: { pokemon: Pokemon; gameId: number; methodName: string } | null;
}
```

Add an effect that, when the modal opens with `prefill`, selects the Pokémon and advances to the method step, preselecting the matching method once `huntMethods` loads:

```tsx
useEffect(() => {
	if (open && prefill) {
		setSelectedPokemon(prefill.pokemon);
		setStep(2);
	}
}, [open, prefill]);

useEffect(() => {
	if (prefill && huntMethods.length > 0) {
		const m = huntMethods.find(
			(hm) => hm.game_id === prefill.gameId && hm.method_name === prefill.methodName,
		);
		if (m) setSelectedMethod(m);
	}
}, [prefill, huntMethods]);
```

(Confirm the step number for the method screen and the `HuntMethod` fields `game_id` / `method_name` against the current modal; adjust if they differ.)

- [ ] **Step 2: Lift prefill state to App and pass a starter to Collection**

In `App.tsx`, add state and pass it both ways:

```tsx
const [huntPrefill, setHuntPrefill] = useState<{ pokemon: Pokemon; gameId: number; methodName: string } | null>(null);
const [huntOpen, setHuntOpen] = useState(false);
```

Render `<NewHuntModal open={huntOpen} prefill={huntPrefill} onClose={() => { setHuntOpen(false); setHuntPrefill(null); }} ... />`, and pass to the Collection tab:

```tsx
onStartHunt={(pokemon, route) => {
	setHuntPrefill({ pokemon, gameId: route.game_id, methodName: route.method_name });
	setHuntOpen(true);
}}
```

(For an `evolve` route, prefill with the ancestor instead — the route's `game_id`/`method_name` belong to the ancestor's hunt; pass `route.evolve_from` to resolve the ancestor `Pokemon`. If resolving the ancestor object is awkward here, prefill Pokémon + game only and let the user pick the method — note this as the chosen simplification.)

- [ ] **Step 3: Add the `onStartHunt` prop to Collection**

In `Collection.tsx` props:

```tsx
const Collection: React.FC<{ onStartHunt?: (pokemon: Pokemon, route: PokemonRoute) => void }> = ({ onStartHunt }) => {
```

(This is already referenced in Task 8 Step 3.)

- [ ] **Step 4: Remove the duplicated client-side odds**

Now that the drawer gets server-computed odds, delete `getOddsForMethod` from `NewHuntModal.tsx` (line ~121) and its usages, and the prop passed into `MethodPreview`. If `MethodPreview` still needs to display odds for the *new-hunt* flow, have it consume the server value (extend `/api/hunt-methods` to also return `g.base_odds` + charm and compute via the same path, or call `/api/pokemon/{id}/route`). Keep `frontend/src/utils/odds.ts` only if other screens still use it — otherwise remove it too.

> If decoupling `MethodPreview` from `getOddsForMethod` balloons scope, limit this task to deleting the duplication that the drawer made redundant and leave a follow-up note; do not break the new-hunt flow.

- [ ] **Step 5: Verify build + lint**

Run: `cd frontend && npm run lint && npm run build`
Expected: both pass, no unused-symbol warnings.

- [ ] **Step 6: End-to-end manual check**

Backend + `npm run dev`. From Collection, open a missing Pokémon → click **▸ Start** on a route → NewHuntModal opens with that Pokémon, game, and method preselected → confirm the hunt starts and appears on the Dashboard.

- [ ] **Step 7: Commit**

```bash
cd frontend && git add -A
git commit -m "Wire drawer Start-hunt prefill into NewHuntModal; drop duplicated odds calc"
```

---

## Final verification

- [ ] Backend: `cd backend && go build ./... && go test ./internal/calc/ -v` — all green.
- [ ] Frontend: `cd frontend && npm run lint && npm run build` — both pass.
- [ ] Seeds re-runnable: re-run `cmd/seed_shiny_locks` and confirm it reports rows skipped (idempotent), not errors.
- [ ] Manual sweep: four cell states render; drawer works for available / locked / not-in-games / data-gap; mark-caught + start-hunt round-trips succeed.
```
