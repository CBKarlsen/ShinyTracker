# Pokémon Champions Correction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retarget the merged team builder from Scarlet/Violet to Pokémon Champions — Mega Evolution instead of Terastallization, Stat Points instead of EVs/IVs, and the Champions species pool.

**Architecture:** A correction, not a rewrite. The tables, `/api/me/teams` API, Swift client, `SnapshotStore` caching and UI shell are game-agnostic and stand. Three columns change, two team rules are added, the seeders re-point at PokeAPI's `champions` version group, and the Showdown bridge becomes import-only.

**Tech Stack:** Go 1.26 + chi + pgx (no ORM, `$1` placeholders) · Swift 6 / SwiftUI, iOS 26 · Swift Testing (`@Test`/`#expect`) · Postgres on Supabase.

## Global Constraints

From `docs/superpowers/specs/2026-08-16-champions-correction-design.md`. Every task implicitly includes these.

- **Stat Points: 66 total per Pokémon, 32 maximum per stat.** IVs do not exist in Champions.
- **No Terastallization.** Mega Evolution is the gimmick, and a Mega Stone is a **held item** — `item_slug` carries it. There is no `mega_stone` column and no `tera_type` column.
- **Team rules Champions enforces:** no two members of the same species; no two members holding the same item.
- **Every Pokémon is auto-levelled to 50** in battle.
- **The stat formula is NOT specified and must not be guessed.** See Task 10.
- **Every handler scopes by `user_id` from the token**, never a path or body parameter. RLS is enabled but bypassed by the `postgres` role, so these `WHERE` clauses are the only isolation.
- Go: raw SQL, `$1/$2` placeholders, `gofmt` clean, `go vet` clean.
- Swift: pure logic in `ShinyTrackerKit` (it has a test target); view models do not.
- No `Font.system(size:)`, no raw hex colours — `Typography` and `Palette` tokens only.

## Verified facts this plan depends on

Checked live on 2026-08-16 rather than assumed:

| Fact | Source |
|---|---|
| `pokedex/champions` — **208 species** | PokeAPI |
| `version-group/champions` exists, generation-ix | PokeAPI |
| `item-category/mega-stones` — **92 items** | PokeAPI |
| `champions` appears in move `version_group_details` | PokeAPI |
| 66 SP total, 32 per stat | Bulbapedia, game guides |
| EV→SP: 4 EVs for the first point in a stat, 8 per additional | Bulbapedia |
| `teams` and `team_members` hold **0 rows** in production | live query |

**The EV→SP conversion is self-verifying** and Task 5 pins it: 252 EVs (the per-stat cap) maps to exactly 32 SP (the per-stat cap), and a 252/252/4 spread to exactly 65 SP — the figure Bulbapedia states a fully-trained Pokémon arrives with. A conversion that reproduces the documented number is confirmed, not assumed.

## File Structure

**Create:**
- `backend/migrations/025_champions.sql` — the Champions game row and the three column changes
- `backend/cmd/seed_champions/main.go` — species pool + availability from the Champions Pokédex
- `ios/ShinyTrackerKit/Sources/ShinyTrackerKit/StatPoints.swift` — the SP type and EV→SP conversion
- `ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/StatPointsTests.swift`

**Modify:**
- `backend/schema.sql` · `backend/internal/api/teams.go` · `backend/internal/api/teams_test.go`
- `backend/cmd/seed_items/main.go` (add the `mega-stones` category)
- `backend/cmd/seed_moves/main.go` (read the `champions` version group)
- `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/Models.swift` · `ShowdownBridge.swift`
- `ios/ShinyTrackerAPI/Tests/ShinyTrackerAPITests/{DecodingTests,ShowdownBridgeTests}.swift`
- `ios/App/Teams/{MemberSheet,TeamEditorScreen,TeamsScreen,TeamsPreviewHarness}.swift`

**Delete:** `ShowdownBridge.paste(...)` and its round-trip test. The parser and `shared/showdown_pastes.json` stay — import is kept.

---

### Task 1: Schema

**Files:**
- Create: `backend/migrations/025_champions.sql`
- Modify: `backend/schema.sql`

**Interfaces:**
- Consumes: nothing
- Produces: `games` row for Champions; `team_members.stat_points JSONB`; `tera_type`, `evs`, `ivs` removed

- [ ] **Step 1: Write the migration**

`backend/migrations/025_champions.sql`:

```sql
-- Retarget the team builder from Scarlet/Violet to Pokemon Champions.
-- See docs/superpowers/specs/2026-08-16-champions-correction-design.md
--
-- Safe as a plain ALTER with no backfill: teams and team_members hold zero
-- rows (verified). That will not be true a second time.

-- Champions is generation-ix per PokeAPI's version-group/champions. base_odds
-- is irrelevant here — Champions has no wild encounters and no shiny hunting —
-- but the column is NOT NULL, so it takes the generation default.
INSERT INTO games (id, title, generation, base_odds)
VALUES (18, 'Pokemon Champions', 9, 4096)
ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title;

-- games.id is SERIAL; an explicit id leaves the sequence behind, so a later
-- plain INSERT would collide. Push it past the highest id in use.
SELECT setval(pg_get_serial_sequence('games', 'id'), (SELECT max(id) FROM games));

-- Champions replaces EVs and IVs with a single Stat Point pool: 66 total,
-- 32 max per stat. IVs do not exist — every Pokemon calculates as though it
-- had 31 in all stats — so there is nothing to migrate the ivs column into.
ALTER TABLE team_members ADD COLUMN IF NOT EXISTS stat_points JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE team_members DROP COLUMN IF EXISTS evs;
ALTER TABLE team_members DROP COLUMN IF EXISTS ivs;

-- Champions has no Terastallization. Its gimmick is Mega Evolution, and a Mega
-- Stone is a HELD ITEM — item_slug already carries it, so this column has no
-- replacement rather than a renamed one.
ALTER TABLE team_members DROP COLUMN IF EXISTS tera_type;
```

- [ ] **Step 2: Mirror the column changes in `backend/schema.sql`**

In the `team_members` block, delete the `tera_type`, `evs` and `ivs` lines and add:

```sql
    -- Champions' unified Stat Points: 66 total, 32 per stat. Read and written
    -- as a whole spread, never queried per stat. The caps cannot be expressed
    -- as a cheap CHECK over JSONB and are enforced in the handler and client.
    stat_points  JSONB NOT NULL DEFAULT '{}'::jsonb,
```

`schema.sql` is the full-DDL source of truth — a migration not reflected there means a fresh database is wrong.

- [ ] **Step 3: Validate the DDL without applying it**

There is no scratch database and `psql` is not installed. Do not attempt a connection. Verify by reading against the existing `team_members` block, and note in your report that validation is deferred to Task 4, which applies it.

- [ ] **Step 4: Commit**

```bash
git add backend/migrations/025_champions.sql backend/schema.sql
git commit -m "feat(db): Champions game row, stat_points, drop tera_type/evs/ivs"
```

---

### Task 2: Go validation — Stat Points and the two team rules

**Files:**
- Modify: `backend/internal/api/teams.go`
- Test: `backend/internal/api/teams_test.go`

**Interfaces:**
- Consumes: schema from Task 1
- Produces: `statPointsValid(map[string]int) bool`; `championsGameID` const; `TeamMemberPayload.StatPoints`; `validateMembers` enforcing duplicate-species and duplicate-item

- [ ] **Step 1: Write the failing tests**

Replace `TestEVSpreadValid` and `TestIVSpreadValid` in `backend/internal/api/teams_test.go` with:

```go
func TestStatPointsValid(t *testing.T) {
	cases := []struct {
		name string
		sp   map[string]int
		want bool
	}{
		{"empty is fine", map[string]int{}, true},
		{"exactly 66 total", map[string]int{"atk": 32, "spe": 32, "hp": 2}, true},
		{"67 is over the pool", map[string]int{"atk": 32, "spe": 32, "hp": 3}, false},
		{"33 in one stat", map[string]int{"atk": 33}, false},
		{"32 in one stat is the cap", map[string]int{"atk": 32}, true},
		{"negative", map[string]int{"atk": -1}, false},
		{"unknown stat key", map[string]int{"luck": 4}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := statPointsValid(tc.sp); got != tc.want {
				t.Errorf("statPointsValid(%v) = %v, want %v", tc.sp, got, tc.want)
			}
		})
	}
}

// Champions forbids two members of the same species and two members holding
// the same item. Neither rule exists in Scarlet/Violet, so neither was in the
// original builder.
func TestValidateMembersTeamRules(t *testing.T) {
	member := func(slot, pokemonID int, item *string) TeamMemberPayload {
		return TeamMemberPayload{
			Slot: slot, PokemonID: pokemonID, Nature: "jolly",
			AbilitySlug: "rough-skin", ItemSlug: item, Level: 50,
			StatPoints: map[string]int{}, Moves: []string{},
		}
	}
	band, orb := "choice-band", "life-orb"

	cases := []struct {
		name    string
		members []TeamMemberPayload
		wantErr bool
	}{
		{"distinct species and items", []TeamMemberPayload{
			member(1, 445, &band), member(2, 892, &orb)}, false},
		{"duplicate species", []TeamMemberPayload{
			member(1, 445, &band), member(2, 445, &orb)}, true},
		{"duplicate item", []TeamMemberPayload{
			member(1, 445, &band), member(2, 892, &band)}, true},
		{"two members holding nothing is fine", []TeamMemberPayload{
			member(1, 445, nil), member(2, 892, nil)}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			msg := validateMembers(tc.members)
			if (msg != "") != tc.wantErr {
				t.Errorf("validateMembers = %q, wantErr %v", msg, tc.wantErr)
			}
		})
	}
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd backend && go test ./internal/api/ -run 'TestStatPointsValid|TestValidateMembersTeamRules'`
Expected: FAIL — `undefined: statPointsValid`

- [ ] **Step 3: Replace the EV/IV validators with the SP validator**

In `backend/internal/api/teams.go`, delete `evSpreadValid` and `ivSpreadValid` and add:

```go
// maxStatPointTotal and maxStatPointPerStat are Champions' caps. They replace
// Scarlet/Violet's 508/252 EVs and its 0-31 IVs entirely — Champions has no
// IVs at all, every Pokemon calculating as though it had 31 in every stat.
const (
	maxStatPointTotal   = 66
	maxStatPointPerStat = 32
)

// statPointsValid enforces the pool and the per-stat cap.
//
// Enforced here as well as in the Swift model and the UI: the database cannot
// express "sum of JSONB values <= 66" cheaply, and a spread that breaks the cap
// is one the game will not accept.
func statPointsValid(sp map[string]int) bool {
	total := 0
	for stat, value := range sp {
		if !validStats[stat] || value < 0 || value > maxStatPointPerStat {
			return false
		}
		total += value
	}
	return total <= maxStatPointTotal
}
```

- [ ] **Step 4: Retarget the game constant**

Replace the `scarletVioletGameID` const:

```go
// championsGameID is the game this builder targets. Champions is the official
// competitive hub and the venue for VGC 2026; it draws its roster from Pokemon
// HOME rather than from any single mainline game.
const championsGameID = 18
```

Update its use in `CreateTeamHandler`. Grep for `scarletVioletGameID` and make sure none remains.

- [ ] **Step 5: Drop the Tera type set**

Delete `validTeraTypes` and the `TeraType` field from `TeamMemberPayload`. Champions has no Terastallization; the Mega Stone lives in `ItemSlug`.

Rename `TeamMemberPayload.EVs`/`IVs` to a single field:

```go
	StatPoints  map[string]int `json:"stat_points"`
```

- [ ] **Step 6: Add the two team rules to `validateMembers`**

Inside `validateMembers`, alongside the existing slot and cap checks:

```go
	// Champions' team rules. Neither exists in the mainline games, so neither
	// was in the original Scarlet/Violet builder.
	species := map[int]bool{}
	items := map[string]bool{}
	for _, m := range members {
		if species[m.PokemonID] {
			return "a team cannot hold two of the same species"
		}
		species[m.PokemonID] = true

		// Two members holding nothing is fine; two holding the SAME item is not.
		if m.ItemSlug != nil && *m.ItemSlug != "" {
			if items[*m.ItemSlug] {
				return "two Pokemon cannot hold the same item"
			}
			items[*m.ItemSlug] = true
		}
	}
```

Replace the `evSpreadValid`/`ivSpreadValid` calls in the per-member loop with a single `statPointsValid(m.StatPoints)` check returning `"stat points exceed the 66 pool or the 32 per-stat cap"`.

- [ ] **Step 7: Update the SQL in `loadTeams` and `insertMembers`**

Both name columns positionally. Replace `evs, ivs` with `stat_points` and remove `tera_type` from the SELECT column list, the `Scan` targets, the INSERT column list and its placeholders. **The SELECT's column order and its Scan targets are positionally coupled** — pgx matches by position, not name, so a column removed from one and not the other loads silently into the wrong variable.

- [ ] **Step 8: Run the tests**

Run: `cd backend && go test ./internal/api/ -v -run 'TestStatPointsValid|TestValidateMembersTeamRules'`
Expected: PASS, 11 subtests

- [ ] **Step 9: Full gate**

Run: `cd backend && gofmt -l ./internal ./cmd && go build ./... && go vet ./... && go test ./...`
Expected: gofmt silent, everything passes

- [ ] **Step 10: Commit**

```bash
git add backend/internal/api/teams.go backend/internal/api/teams_test.go
git commit -m "feat(api): Stat Points and Champions team rules replace EV/IV validation"
```

---

### Task 3: Champions seeding

**Files:**
- Create: `backend/cmd/seed_champions/main.go`
- Modify: `backend/cmd/seed_items/main.go`, `backend/cmd/seed_moves/main.go`, `backend/CLAUDE.md`

**Interfaces:**
- Consumes: the Champions game row from Task 1
- Produces: `pokemon_availability` rows for game 18; `pokemon_moves` rows for game 18; Mega Stones in `items`

- [ ] **Step 1: Write the species-pool seeder**

`backend/cmd/seed_champions/main.go`:

```go
// cmd/seed_champions populates pokemon_availability for Pokemon Champions from
// PokeAPI's champions Pokedex.
//
// RUNBOOK: run after migrations/025_champions.sql. Safe to re-run — the write
// is an idempotent upsert on the (pokemon_id, game_id) pair.
//
// The Champions roster is NOT a mainline game's dex. Pokemon arrive through
// Pokemon HOME from the core series and Pokemon GO, limited to species that
// exist in Champions, and the pool GROWS IN BATCHES alongside new Regulation
// Sets — so this seeder is not a one-time run.
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

const championsGameID = 18

var httpClient = &http.Client{Timeout: 30 * time.Second}

type pokedexResponse struct {
	PokemonEntries []struct {
		PokemonSpecies struct {
			Name string `json:"name"`
		} `json:"pokemon_species"`
	} `json:"pokemon_entries"`
}

func main() { os.Exit(run()) }

func run() int {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Print(err)
		return 1
	}
	defer database.CloseDB()

	resp, err := httpClient.Get("https://pokeapi.co/api/v2/pokedex/champions")
	if err != nil {
		log.Printf("fetch champions pokedex: %v", err)
		return 1
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		log.Printf("fetch champions pokedex: status %d", resp.StatusCode)
		return 1
	}

	var dex pokedexResponse
	if err := json.NewDecoder(resp.Body).Decode(&dex); err != nil {
		log.Printf("decode champions pokedex: %v", err)
		return 1
	}

	seeded, missing := 0, 0
	for _, entry := range dex.PokemonEntries {
		name := entry.PokemonSpecies.Name
		// The pokedex names SPECIES; our pokemon table is keyed on the PokeAPI
		// pokemon name, which matches for every default form. A species whose
		// default form is suffixed will not match, and is reported rather than
		// silently skipped.
		var pokemonID int
		err := database.DB.QueryRow(context.Background(),
			`SELECT id FROM pokemon WHERE name = $1`, name).Scan(&pokemonID)
		if err != nil {
			log.Printf("no pokemon row for champions species %q", name)
			missing++
			continue
		}

		if _, err := database.DB.Exec(context.Background(),
			`INSERT INTO pokemon_availability (pokemon_id, game_id)
			 VALUES ($1, $2) ON CONFLICT DO NOTHING`,
			pokemonID, championsGameID); err != nil {
			log.Printf("upsert availability for %q: %v", name, err)
			missing++
			continue
		}
		seeded++
	}

	log.Printf("seeded %d champions species (%d unmatched)", seeded, missing)
	if seeded == 0 {
		// ponytail: nothing seeded means the pokedex fetch or the name join is
		// broken, not that Champions has no roster. Exit non-zero so a script
		// or a human notices.
		return 1
	}
	fmt.Println("done")
	return 0
}
```

- [ ] **Step 2: Add Mega Stones to the item seeder**

In `backend/cmd/seed_items/main.go`, append `"mega-stones"` to `heldItemCategories` with a comment:

```go
	// Mega Stones. Champions' battle gimmick is Mega Evolution and the stone is
	// a held item, so these belong in the same picker as Choice Band. 92 entries.
	"mega-stones",
```

- [ ] **Step 3: Point the moveset seeder at Champions**

In `backend/cmd/seed_moves/main.go`, find where it filters `version_group_details` by version group and add `champions` alongside the existing groups, mapping it to `championsGameID` (18). Read the file first — it currently handles Platinum and Scarlet/Violet, and the mapping is per-game.

- [ ] **Step 4: Build and vet**

Run: `cd backend && gofmt -w ./cmd && go build ./... && go vet ./...`
Expected: no output

- [ ] **Step 5: Document the runbook order**

Add to `backend/CLAUDE.md`'s seed list:

```bash
go run ./cmd/seed_champions/main.go   # Champions species pool (after migration 025)
```

Note in the same list that `cmd/seed_items` and `cmd/seed_moves` must be re-run after 025 to pick up Mega Stones and Champions movesets.

- [ ] **Step 6: Commit**

```bash
git add backend/cmd/seed_champions/ backend/cmd/seed_items/main.go backend/cmd/seed_moves/main.go backend/CLAUDE.md
git commit -m "feat(backend): seed the Champions roster, Mega Stones and Champions movesets"
```

---

### Task 4: Apply to production

Operational only — no code, no commit. Separated so a reviewer can reject the schema without rejecting a live write.

- [ ] **Step 1: Confirm the tables are still empty**

```sql
SELECT (SELECT count(*) FROM teams) AS teams, (SELECT count(*) FROM team_members) AS members;
```
Expected: `0, 0`. **If either is non-zero, STOP** — the plain-ALTER assumption no longer holds and the migration needs a data plan.

- [ ] **Step 2: Apply migration 025**

Apply via Supabase's `apply_migration` so it lands in the migration ledger.

- [ ] **Step 3: Verify the shape**

```sql
SELECT column_name FROM information_schema.columns
WHERE table_name = 'team_members' AND column_name IN ('stat_points','evs','ivs','tera_type');
```
Expected: exactly one row, `stat_points`.

```sql
SELECT id, title, generation FROM games WHERE id = 18;
```
Expected: `18, Pokemon Champions, 9`.

- [ ] **Step 4: Seed**

```bash
cd backend
go run ./cmd/seed_champions   # the roster
go run ./cmd/seed_items       # re-run: picks up Mega Stones
go run ./cmd/seed_moves       # re-run: picks up Champions movesets
```

- [ ] **Step 5: Verify the data**

```sql
SELECT
  (SELECT count(*) FROM pokemon_availability WHERE game_id = 18)      AS roster,
  (SELECT count(*) FROM pokemon_moves WHERE game_id = 18)             AS move_rows,
  (SELECT count(*) FROM items WHERE slug LIKE '%ite' OR slug LIKE '%itex' OR slug LIKE '%itey') AS mega_stones;
```
Expected: roster near 208 (some species may not match a `pokemon` row — the seeder reports how many), move_rows in the tens of thousands, mega_stones near 92.

- [ ] **Step 6: No commit** — this task changes no files.

---

### Task 5: Kit — StatPoints and the EV→SP conversion

**Files:**
- Create: `ios/ShinyTrackerKit/Sources/ShinyTrackerKit/StatPoints.swift`
- Create: `ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/StatPointsTests.swift`
- Modify: `ios/ShinyTrackerKit/Sources/ShinyTrackerKit/StatSpread.swift`

**Interfaces:**
- Consumes: `Stat`, `StatSpread` (existing)
- Produces: `struct StatPoints`, `StatPoints.total`, `StatPoints.subscript(Stat)`, `StatPoints.zero`, `StatPoints.maxTotal`, `StatPoints.maxPerStat`, `StatPoints.capped(_:for:)`, `StatPoints.fromEVs(_:)`

- [ ] **Step 1: Write the failing tests**

`ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/StatPointsTests.swift`:

```swift
import Testing
@testable import ShinyTrackerKit

@Test func theCapsAreSixtySixAndThirtyTwo() {
    #expect(StatPoints.maxTotal == 66)
    #expect(StatPoints.maxPerStat == 32)
}

/// The documented HOME conversion: 4 EVs buy the first point in a stat, 8 buy
/// each additional one.
@Test func evsConvertAtFourThenEight() {
    #expect(StatPoints.fromEVs(StatSpread(hp: 0))[.hp] == 0)
    #expect(StatPoints.fromEVs(StatSpread(hp: 3))[.hp] == 0)
    #expect(StatPoints.fromEVs(StatSpread(hp: 4))[.hp] == 1)
    #expect(StatPoints.fromEVs(StatSpread(hp: 11))[.hp] == 1)
    #expect(StatPoints.fromEVs(StatSpread(hp: 12))[.hp] == 2)
}

/// This is the check that confirms the conversion rather than assuming it.
/// 252 EVs is the per-stat maximum in the mainline games and it lands exactly
/// on 32, the per-stat maximum in Champions. If the rate were wrong these two
/// independently-documented numbers would not meet.
@Test func maxEVsInOneStatLandsExactlyOnTheStatCap() {
    #expect(StatPoints.fromEVs(StatSpread(atk: 252))[.atk] == 32)
}

/// And a fully-trained 252/252/4 spread lands on exactly 65 — the figure
/// Bulbapedia states a transferred, fully-EV-trained Pokemon arrives with.
@Test func aFullyTrainedSpreadLandsOnSixtyFive() {
    let sp = StatPoints.fromEVs(StatSpread(atk: 252, spd: 4, spe: 252))
    #expect(sp.total == 65)
}

@Test func cappedClampsPerStatAndAgainstTheRemainingPool() {
    var sp = StatPoints.zero
    sp[.atk] = 32
    sp[.spe] = 32
    // 64 spent, 2 left in the pool — asking for 30 in HP yields 2.
    #expect(sp.capped(30, for: .hp) == 2)
    // And a single stat can never exceed 32 even with the whole pool free.
    #expect(StatPoints.zero.capped(50, for: .hp) == 32)
    #expect(StatPoints.zero.capped(-5, for: .hp) == 0)
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd ios/ShinyTrackerKit && swift test --filter StatPointsTests`
Expected: FAIL — `cannot find 'StatPoints' in scope`

- [ ] **Step 3: Implement `StatPoints.swift`**

```swift
import Foundation

/// Pokemon Champions' unified stat allocation, replacing both EVs and IVs.
///
/// 66 points across six stats, at most 32 in any one. IVs do not exist in
/// Champions at all — every Pokemon calculates as though it had 31 in every
/// stat — so there is no second spread to model.
public struct StatPoints: Codable, Equatable, Sendable {
    public var hp: Int
    public var atk: Int
    public var def: Int
    public var spa: Int
    public var spd: Int
    public var spe: Int

    public init(hp: Int = 0, atk: Int = 0, def: Int = 0, spa: Int = 0, spd: Int = 0, spe: Int = 0) {
        self.hp = hp; self.atk = atk; self.def = def
        self.spa = spa; self.spd = spd; self.spe = spe
    }

    public static let maxTotal = 66
    public static let maxPerStat = 32
    public static let zero = StatPoints()

    public subscript(stat: Stat) -> Int {
        get {
            switch stat {
            case .hp: hp
            case .atk: atk
            case .def: def
            case .spa: spa
            case .spd: spd
            case .spe: spe
            }
        }
        set {
            switch stat {
            case .hp: hp = newValue
            case .atk: atk = newValue
            case .def: def = newValue
            case .spa: spa = newValue
            case .spd: spd = newValue
            case .spe: spe = newValue
            }
        }
    }

    public var total: Int { Stat.allCases.reduce(0) { $0 + self[$1] } }

    /// The largest legal value for `stat`, given what the other five already
    /// spend. Clamping here rather than validating afterwards is what makes an
    /// illegal spread unreachable from the UI.
    public func capped(_ value: Int, for stat: Stat) -> Int {
        let spentElsewhere = total - self[stat]
        return max(0, min(value, Self.maxPerStat, Self.maxTotal - spentElsewhere))
    }

    /// Converts a mainline EV spread, as Pokemon HOME does on transfer: 4 EVs
    /// buy the first point in a stat, 8 buy each additional one.
    ///
    /// Used for importing an existing Scarlet/Violet team. The rate is not a
    /// guess — 252 EVs (the mainline per-stat cap) lands exactly on 32
    /// (Champions' per-stat cap), and a 252/252/4 spread lands exactly on the
    /// 65 points a fully-trained transfer is documented to arrive with.
    public static func fromEVs(_ evs: StatSpread) -> StatPoints {
        var points = StatPoints.zero
        for stat in Stat.allCases {
            let ev = evs[stat]
            guard ev >= 4 else { continue }
            points[stat] = min(Self.maxPerStat, 1 + (ev - 4) / 8)
        }
        return points
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `cd ios/ShinyTrackerKit && swift test --filter StatPointsTests`
Expected: PASS, 5 tests

- [ ] **Step 5: Remove the now-meaningless IV default**

In `StatSpread.swift`, delete `static let maxIVs` and the test `maxIVsAreThirtyOneNotZero`. `StatSpread` stays — the Showdown parser still produces EV and IV spreads from a paste, and `fromEVs` consumes the EV one. Add a note on `StatSpread` that it models a *mainline* spread, kept for paste import, and that Champions itself uses `StatPoints`.

**Careful:** `ShowdownPaste.parse` uses `.maxIVs` as the base for an `IVs:` line. Replace that base with a locally-defined all-31 spread inside `ShowdownPaste`, so parsing a paste still defaults omitted IVs to 31 — that is a fact about the *paste format*, not about Champions.

- [ ] **Step 6: Run the whole Kit suite**

Run: `cd ios/ShinyTrackerKit && swift test`
Expected: PASS. The count drops by one (the removed IV test) and rises by five.

- [ ] **Step 7: Commit**

```bash
git add ios/ShinyTrackerKit/
git commit -m "feat(kit): StatPoints with the HOME EV conversion, pinned to the documented 65"
```

---

### Task 6: Swift API models

**Files:**
- Modify: `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/Models.swift`
- Test: `ios/ShinyTrackerAPI/Tests/ShinyTrackerAPITests/DecodingTests.swift`

**Interfaces:**
- Consumes: the API shape from Task 2
- Produces: `TeamMember.statPoints: [String: Int]`, with `evs`, `ivs` and `teraType` removed

- [ ] **Step 1: Write the failing decode test**

Replace the existing team decode test's JSON in `DecodingTests.swift`:

```swift
@Test func decodesATeamWithMembers() throws {
    let json = """
        {"id":"aaaaaaaa-0000-4000-8000-00000000aaaa","name":"Reg M-A core","game_id":18,
         "members":[
           {"slot":1,"pokemon_id":445,"nickname":null,"nature":"jolly",
            "ability_slug":"rough-skin","item_slug":"garchompite",
            "level":50,"stat_points":{"atk":32,"spe":32,"spd":2},
            "moves":["earthquake","dragon-claw"]}]}
        """
    let team = try JSONDecoder().decode(Team.self, from: Data(json.utf8))
    #expect(team.gameID == 18)
    #expect(team.members[0].statPoints["atk"] == 32)
    #expect(team.members[0].statPoints.values.reduce(0, +) == 66)
    // A Mega Stone is just a held item — there is no separate field for it.
    #expect(team.members[0].itemSlug == "garchompite")
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios/ShinyTrackerAPI && swift test --filter decodesATeamWithMembers`
Expected: FAIL — `value of type 'TeamMember' has no member 'statPoints'`

- [ ] **Step 3: Update `TeamMember`**

In `Models.swift`, replace the `evs`, `ivs` and `teraType` properties with:

```swift
    /// Champions' unified allocation: 66 points, 32 per stat. Crosses the wire
    /// as `[String: Int]` keyed by `Stat.rawValue`, the same closed set the
    /// JSONB column holds. There is no IV spread — Champions has no IVs.
    public let statPoints: [String: Int]
```

and update `CodingKeys`: drop `teraType`/`evs`/`ivs`, add `case statPoints = "stat_points"`.

**Do not add `keyDecodingStrategy`** — the file header explains why at length, and 44 of the existing mappings are not snake↔camel.

- [ ] **Step 4: Run the API suite**

Run: `cd ios/ShinyTrackerAPI && swift test`
Expected: PASS. Some existing tests will need their fixture JSON updated the same way — do that rather than deleting them.

- [ ] **Step 5: Commit**

```bash
git add ios/ShinyTrackerAPI/
git commit -m "feat(api-client): TeamMember carries stat_points; tera_type and IVs removed"
```

---

### Task 7: ShowdownBridge becomes import-only

**Files:**
- Modify: `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/ShowdownBridge.swift`
- Modify: `ios/ShinyTrackerAPI/Tests/ShinyTrackerAPITests/ShowdownBridgeTests.swift`

**Interfaces:**
- Consumes: `StatPoints.fromEVs` (Task 5), `TeamMember.statPoints` (Task 6)
- Produces: `ShowdownBridge.member(...)` returning a `TeamMember` with converted stat points; `ShowdownBridge.paste(...)` **removed**

- [ ] **Step 1: Write the failing conversion test**

Add to `ShowdownBridgeTests.swift`:

```swift
/// A pasted Scarlet/Violet set converts to a Champions member: EVs become stat
/// points at the HOME rate, IVs are discarded because Champions has none, and
/// the Tera type is dropped because Champions has no Terastallization.
@Test func aPastedSVSetConvertsToChampionsShape() throws {
    let parsed = try ShowdownPaste.parse("""
        Garchomp @ Rocky Helmet
        Ability: Rough Skin
        Tera Type: Steel
        EVs: 252 Atk / 4 SpD / 252 Spe
        Jolly Nature
        IVs: 0 SpA
        - Earthquake
        """)
    let member = ShowdownBridge.member(
        parsed[0], slot: 1, speciesIDs: ["garchomp": 445],
        abilitySlugs: ["roughskin": "rough-skin"],
        itemSlugs: ["rockyhelmet": "rocky-helmet"],
        moveSlugs: ["earthquake": "earthquake"])

    #expect(member?.statPoints["atk"] == 32)
    #expect(member?.statPoints["spe"] == 32)
    #expect(member?.statPoints["spd"] == 1)
    #expect(member?.statPoints.values.reduce(0, +) == 65)
    #expect(member?.nature == "jolly")
    #expect(member?.itemSlug == "rocky-helmet")
}
```

Adjust the argument labels to match the real `member(...)` signature — read it first.

- [ ] **Step 2: Run to verify it fails**

Run: `cd ios/ShinyTrackerAPI && swift test --filter aPastedSVSetConvertsToChampionsShape`
Expected: FAIL

- [ ] **Step 3: Convert in `member(...)`**

Replace the EV/IV clamping with:

```swift
        // Champions has no EVs and no IVs. A pasted mainline spread converts at
        // Pokemon HOME's own rate; the paste's IV line is discarded entirely,
        // because every Champions Pokemon calculates as though it had 31.
        let points = StatPoints.fromEVs(set.evs)
```

and build `statPoints` from it, keyed by `Stat.rawValue`. Drop the `teraType` argument and the Tera-type set.

`fromEVs` already clamps per stat, but a paste can carry an over-cap spread (`ShowdownPaste` does not validate), so clamp the **total** to 66 afterwards, spending in `Stat.allCases` order — the same order `cappedEV` used.

- [ ] **Step 4: Delete `paste(...)` and its round-trip test**

Remove `ShowdownBridge.paste(...)` and the tests `exportedMemberRoundTrips` and `slugFallbackStillRoundTrips`.

**Why, so nobody restores it by reflex:** the Showdown paste format encodes EVs, IVs and Tera types. Champions has none of the three. Exporting a Champions team as a paste produces a set that misrepresents itself — a reader would see an EV spread the team does not have. Import is well-defined in one direction only, so only import is kept.

`ShowdownPaste.export` in `ShinyTrackerKit` stays — it is the parser's inverse, it is fixture-pinned, and it is what makes the parser's round-trip test meaningful.

- [ ] **Step 5: Run the suite**

Run: `cd ios/ShinyTrackerAPI && swift test`
Expected: PASS with a lower count — two round-trip tests removed, one conversion test added.

- [ ] **Step 6: Commit**

```bash
git add ios/ShinyTrackerAPI/
git commit -m "feat(api-client): Showdown import converts EVs to stat points; export removed"
```

---

### Task 8: MemberSheet — the SP editor

**Files:**
- Modify: `ios/App/Teams/MemberSheet.swift`

**Interfaces:**
- Consumes: `StatPoints` (Task 5), `TeamMember.statPoints` (Task 6)
- Produces: a member sheet that cannot build an illegal spread

- [ ] **Step 1: Replace the EV block with an SP block**

The existing EV editor is the model to follow — it is structurally correct and only the numbers change:

- `@State var evs: StatSpread` → `@State var statPoints: StatPoints`
- `cappedEV` → `statPoints.capped(_:for:)` from Task 5
- The block title's remaining count reads `max(0, StatPoints.maxTotal - statPoints.total)` — keep the `max(0, ...)`, it exists because legacy rows could render negative
- The `Slider` range becomes `0...Double(StatPoints.maxPerStat)` with `step: 1`. **One point is a meaningful unit** in Champions, unlike 4 EVs, so do not carry the `step: 4` across.
- Keep the `Slider`'s own `.accessibilityLabel` and `.accessibilityValue("\(statPoints[stat])")`. **Do not wrap the row in `.accessibilityElement(children: .combine)`** — that flattens the slider and removes its adjustable action, which was a real bug in the SV version.

- [ ] **Step 2: Delete the IV editor entirely**

Remove the IV `Stepper` block and its state. Champions has no IVs; an editor for them edits nothing.

- [ ] **Step 3: Delete the Tera Type picker**

Remove the picker and its 19-value list. A Mega Stone is chosen in the **item** picker, which already exists — nothing replaces the Tera control.

- [ ] **Step 4: Remove the computed-stats block**

Delete the "Stats at level N" display and its `StatCalculator` call.

**This is deliberate and temporary.** `StatCalculator` implements the mainline Gen 3+ formula, which takes an EV term and an IV term. How 66 stat points map onto displayed stats in Champions is **not established**, and "1 SP ≈ 8 EVs" is a community approximation rather than a source. Showing a number derived from the wrong formula is worse than showing none, in an app whose value is being right about mechanics. Task 10 reinstates it once anchors exist.

Leave `StatCalculator` in `ShinyTrackerKit` — it is still correct for the mainline games and is used nowhere else that breaks.

- [ ] **Step 5: Fix the level field**

Champions auto-levels every Pokemon to 50. Replace the level `Stepper` with a static row reading `Level 50 · set by the game`, and keep sending `level: 50`.

- [ ] **Step 6: Build**

Run:
```bash
cd ios && xcodegen generate && xcodebuild -project ShinyTracker.xcodeproj \
  -scheme ShinyTracker -destination 'generic/platform=iOS Simulator' -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Commit**

```bash
git add ios/App/Teams/MemberSheet.swift
git commit -m "feat(ios): stat point editor replaces EV/IV; Tera picker and computed stats removed"
```

---

### Task 9: Team rules in the UI, and the harness

**Files:**
- Modify: `ios/App/Teams/TeamEditorScreen.swift`, `ios/App/Teams/TeamsScreen.swift`, `ios/App/Teams/TeamsPreviewHarness.swift`, `ios/App/Teams/ImportPasteSheet.swift`

**Interfaces:**
- Consumes: everything above
- Produces: a UI that refuses an illegal team before saving

- [ ] **Step 1: Surface the two team rules in the editor**

The server rejects a duplicate species or a duplicate item with a 400. The editor should say so **before** the user hits Save, the way the stat-point cap is unreachable rather than merely rejected.

In `TeamEditorScreen`, compute from `slots`:
- a set of `pokemonID`s used more than once
- a set of `itemSlug`s used more than once (ignoring nil and `""`)

Mark the offending slots inline and disable Save while either set is non-empty, with a message naming the rule broken. Use `Palette.danger` for the marker and give it an `accessibilityLabel` — do not signal it by colour alone.

- [ ] **Step 2: Update the preview harness fixtures**

In `TeamsPreviewHarness.swift`, the `seeded` fixture's JSON carries `evs`, `ivs` and `tera_type`. Replace with `stat_points`, and change `game_id` to 18. A fixture that no longer matches the decoder is a harness that fails to render.

- [ ] **Step 3: Update the import sheet's warning copy**

`ImportPasteSheet` reports unresolvable species. Add a line to its result summary when any set carried EVs, saying they were converted to stat points — a user pasting an SV team should be told their spread was transformed, not silently reinterpreted.

- [ ] **Step 4: Build and check the harness renders**

```bash
cd ios && xcodegen generate && xcodebuild -project ShinyTracker.xcodeproj \
  -scheme ShinyTracker -destination 'generic/platform=iOS Simulator' -configuration Debug build
xcrun simctl launch booted com.casperkarlsen.shinytracker -teamsPreview seeded
```
Expected: build succeeds; the Teams tab shows the seeded team with stat points and no Tera row.

- [ ] **Step 5: Full verification**

```bash
cd backend && gofmt -l ./internal ./cmd && go build ./... && go vet ./... && go test ./...
cd ../ios/ShinyTrackerKit && swift test
cd ../ShinyTrackerAPI && swift test
cd .. && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

- [ ] **Step 6: Commit**

```bash
git add ios/App/Teams/
git commit -m "feat(ios): surface Champions team rules; harness fixtures on the Champions shape"
```

---

### Task 10: BLOCKED — stat anchors and the computed-stats display

**This task cannot start until the owner supplies data.** It is listed so the gap is tracked rather than forgotten, and so nobody reinstates the stat display by guessing.

**What is missing:** how 66 stat points map onto a Pokémon's displayed stats in Champions. The mainline Gen 3+ formula takes an EV term and an IV term; Champions has neither. "1 SP ≈ 8 EVs" is a community approximation, and substituting it would produce numbers that are close, wrong, and unfalsifiable.

**What unblocks it:** stats read off real Pokémon in Champions. For each anchor, all of: species, base stats, nature, the full stat-point spread, and the six displayed stats at level 50. **Six to ten anchors covering a raised nature, a lowered nature, a neutral nature, 0 points in a stat, and 32 points in a stat** are enough to determine the formula and catch a wrong one.

**When it arrives:**

- [ ] Write `shared/champions_stat_anchors.json` in the shape of `shared/odds_anchors.json` — the fixture is the source of truth, and if an implementation disagrees with it, the implementation is wrong.
- [ ] Write a failing test in `ShinyTrackerKitTests` that loads the fixture by walking up from `#filePath`, exactly as `OddsAnchorsTests` does.
- [ ] Derive the formula from the anchors and implement `ChampionsStatCalculator` in `ShinyTrackerKit`.
- [ ] Reinstate the "Stats at level 50" block in `MemberSheet`, driven by it.
- [ ] Commit.

Until then the builder ships without computed stats, which is the honest state.

---

## Self-Review

**Spec coverage.** Every section maps to a task: Mega Evolution replacing Tera (1, 2, 3, 8) · Stat Points replacing EVs/IVs (1, 2, 5, 6, 8) · the Champions species pool (1, 3, 4) · the two team rules (2, 9) · level 50 auto-set (8) · Showdown import-only with EV conversion (7) · the stat formula deferred to anchors (10) · production migration in the zero-row window (4).

**Placeholders:** none. Task 10 is explicitly and deliberately blocked, with the exact data needed to unblock it named — that is a tracked gap, not a placeholder.

**Type consistency:** `Stat.rawValue` (`hp/atk/def/spa/spd/spe`) remains the single key vocabulary across Go's `validStats`, the `stat_points` JSONB, Swift's `StatPoints`, and the harness fixtures. `StatPoints.maxTotal`/`maxPerStat` (66/32) are defined in Task 5 and used in Tasks 8 and 9; Go's `maxStatPointTotal`/`maxStatPointPerStat` in Task 2 carry the same values. `championsGameID` is 18 in Go (Task 2), in the seeder (Task 3) and in the harness fixtures (Task 9). `StatPoints.fromEVs` is defined in Task 5 and consumed only in Task 7.

**One deliberate asymmetry worth stating:** `ShowdownPaste.export` survives in `ShinyTrackerKit` while `ShowdownBridge.paste` is deleted. The former is the parser's inverse and exists to make the round-trip test meaningful; the latter converted a *Champions team* into a paste, which is the direction that misrepresents.
