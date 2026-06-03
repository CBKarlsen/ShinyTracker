# Odds Fidelity Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add faithful Legends:Arceus (`pla_research`) and Ultra Wormhole (`ultra_wormhole`) shiny-odds formulas, fix phase-row collection corruption, and remove the dead ETA helper.

**Architecture:** Two new `formula_type`s implemented in parallel in the Go odds engine (`methods.go`) and its TS mirror (`odds.ts`), gated by a Go parity test. New seed rows in `hunt_methods.json`. Phase rows in `LogPhaseHandler` carry the parent's `game_id`, `encounter_count = 0`, and a new `'PHASE'` acquisition type (additive CHECK migration). Per-hunt parameters live in `hunt_parameters` JSONB; UI inputs added to `HuntParametersEditor`.

**Tech Stack:** Go (chi, pgx, `go test`), React 19 + TypeScript + Vite (Biome, `tsc`), PostgreSQL (Supabase), JSON/CSV seed tooling under `cmd/`.

**Spec:** `docs/superpowers/specs/2026-06-02-odds-fidelity-batch-design.md`

---

## File Structure

| File | Change | Task |
|---|---|---|
| `backend/internal/calc/methods.go` | `paramBool` helper, `pla_research` + `ultra_wormhole` cases, `DefaultParams` entries, comment fix | 1,2,3 |
| `backend/internal/calc/methods_test.go` | parity + default-param anchors for both formulas | 1,2 |
| `backend/internal/calc/odds.go` | delete dead `CalculateEstimatedTimeHours` | 4 |
| `frontend/src/utils/odds.ts` | mirror both formulas in `calculateOdds`, extend `PARAM_FORMULAS` + `defaultParamsFor`, anchor comment | 5 |
| `backend/seeds/hunt_methods.json` | replace `mass_outbreak_la` with 3 PLA rows + 1 wormhole row | 6 |
| `backend/schema.sql` + live DB | `acquisition_type` CHECK += `'PHASE'` | 7 |
| `backend/internal/api/hunts.go` | phase row: parent `game_id`, count 0, `PHASE` type | 8 |
| `frontend/src/components/ui/HuntParametersEditor.tsx` | PLA flag inputs + wormhole ring/distance inputs | 9 |
| `frontend/src/components/HistoricHunts.tsx` | optional `PHASE` label | 9 |
| re-seed + `cmd/audit_methods` | verify rows landed, availability non-empty | 10 |

Backend (Tasks 1-4, 6-8) → `backend-specialist`. Frontend (Tasks 5, 9) → `frontend-specialist`. Tasks 1-2 and 5 share the exact same constants and must use the anchors below verbatim. Task 10 is integration.

---

## Task 1: `pla_research` formula (Go)

**Files:**
- Modify: `backend/internal/calc/methods.go`
- Test: `backend/internal/calc/methods_test.go`

- [ ] **Step 1: Add the failing test cases**

In `methods_test.go`, add a new test function (PLA charm is +3, so it needs its own base):

```go
func TestEffectiveOddsPLA(t *testing.T) {
	plaBase := OddsConfig{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 3}
	cases := []struct {
		name    string
		params  map[string]any
		charm   bool
		want    int
	}{
		{"pla base", map[string]any{}, false, 4096},
		{"pla research10", map[string]any{"research_level": 10}, false, 2048},
		{"pla perfect", map[string]any{"research_level": 10, "dex_perfect": true}, false, 1024},
		{"pla charm only", map[string]any{}, true, 1024}, // base 1 + PLA charm 3 = 4 rolls -> 4096/4=1024
		{"pla MO", map[string]any{"mass_outbreak": true}, false, 157},
		{"pla MO+perfect", map[string]any{"mass_outbreak": true, "research_level": 10, "dex_perfect": true}, false, 141},
		{"pla MO+perfect+charm", map[string]any{"mass_outbreak": true, "research_level": 10, "dex_perfect": true}, true, 128},
		{"pla MMO", map[string]any{"massive_outbreak": true}, false, 315},
		{"pla MMO+perfect", map[string]any{"massive_outbreak": true, "research_level": 10, "dex_perfect": true}, false, 256},
		{"pla MMO+perfect+charm", map[string]any{"massive_outbreak": true, "research_level": 10, "dex_perfect": true}, true, 215},
		{"pla MO beats MMO when both set", map[string]any{"mass_outbreak": true, "massive_outbreak": true}, false, 157},
	}
	for _, c := range cases {
		got := EffectiveOdds("pla_research", c.params, plaBase, c.charm)
		if got != c.want {
			t.Errorf("%s: EffectiveOdds = %d, want %d", c.name, got, c.want)
		}
	}
}
```

- [ ] **Step 2: Run the test, verify it fails**

Run: `cd backend && go test ./internal/calc/ -run TestEffectiveOddsPLA -v`
Expected: FAIL — `pla_research` is unknown so every case returns the static fallback `4096/(rolls)` for `rolls=base+charm` only (no outbreak/research bonus), so most cases mismatch.

- [ ] **Step 3: Add the `paramBool` helper**

In `methods.go`, directly below `paramInt`:

```go
// paramBool reads a boolean param, tolerating bool. Missing/!bool -> false.
func paramBool(params map[string]any, key string) bool {
	v, ok := params[key]
	if !ok {
		return false
	}
	b, ok := v.(bool)
	return ok && b
}
```

- [ ] **Step 4: Add the `pla_research` case**

In `EffectiveOdds`, add a case to the `switch t` (before `default`):

```go
	case "pla_research":
		// Legends: Arceus additive rolls. Research Lv10 (+1) and Perfect (+2)
		// STACK (matches RotomLabs' published 1/128 for MO+perfect+charm = 32
		// rolls). Mass Outbreak (+25) and Massive Mass Outbreak (+12) are
		// mutually exclusive; MO wins if both flags are set. MMO is intentionally
		// worse per-encounter than MO — its real advantage is spawn volume, which
		// lives in avg_time_seconds, not here. PLA charm is +3 (base.CharmRolls).
		rolls := base.BaseRolls
		if paramInt(params, "research_level", 0) >= 10 {
			rolls++
		}
		if paramBool(params, "dex_perfect") {
			rolls += 2
		}
		if paramBool(params, "mass_outbreak") {
			rolls += 25
		} else if paramBool(params, "massive_outbreak") {
			rolls += 12
		}
		return floorDiv(rolls + charmRolls)
```

- [ ] **Step 5: Add `DefaultParams` entry**

In `DefaultParams`, add before `default`:

```go
	case "pla_research":
		// Best realistic non-charm case: Mass Outbreak + Perfect research.
		return map[string]any{"research_level": 10, "dex_perfect": true, "mass_outbreak": true}
```

- [ ] **Step 6: Run the test, verify it passes**

Run: `cd backend && go test ./internal/calc/ -run TestEffectiveOddsPLA -v`
Expected: PASS (all 11 cases).

- [ ] **Step 7: Commit**

```bash
git -C /Users/casper/Fritidsprosjekt/ShinyTracker add backend/internal/calc/methods.go backend/internal/calc/methods_test.go
git -C /Users/casper/Fritidsprosjekt/ShinyTracker commit -m "feat(odds): pla_research formula for Legends:Arceus additive rolls"
```

---

## Task 2: `ultra_wormhole` formula (Go)

**Files:**
- Modify: `backend/internal/calc/methods.go`
- Test: `backend/internal/calc/methods_test.go`

- [ ] **Step 1: Add the failing test cases**

In `methods_test.go`:

```go
func TestEffectiveOddsWormhole(t *testing.T) {
	base := OddsConfig{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2}
	cases := []struct {
		name   string
		params map[string]any
		want   int
	}{
		{"ring4 5000ly", map[string]any{"wormhole_ring_type": 4, "wormhole_distance_ly": 5000}, 3},
		{"ring4 2000ly", map[string]any{"wormhole_ring_type": 4, "wormhole_distance_ly": 2000}, 8},
		{"ring3 5000ly", map[string]any{"wormhole_ring_type": 3, "wormhole_distance_ly": 5000}, 5},
		{"ring2 5000ly", map[string]any{"wormhole_ring_type": 2, "wormhole_distance_ly": 5000}, 10},
		{"ring1 any", map[string]any{"wormhole_ring_type": 1, "wormhole_distance_ly": 9999}, 100},
		{"ring4 0ly", map[string]any{"wormhole_ring_type": 4, "wormhole_distance_ly": 0}, 100},
		{"default params best case", DefaultParams("ultra_wormhole"), 3},
	}
	for _, c := range cases {
		// Charm must not affect wormhole; test both to prove it.
		for _, charm := range []bool{false, true} {
			got := EffectiveOdds("ultra_wormhole", c.params, base, charm)
			if got != c.want {
				t.Errorf("%s (charm=%v): EffectiveOdds = %d, want %d", c.name, charm, got, c.want)
			}
		}
	}
}
```

- [ ] **Step 2: Run, verify it fails**

Run: `cd backend && go test ./internal/calc/ -run TestEffectiveOddsWormhole -v`
Expected: FAIL — unknown formula falls back to static (returns 1365/4096), not the percent lookup.

- [ ] **Step 3: Add the `ultra_wormhole` case**

In `EffectiveOdds`, before `default`:

```go
	case "ultra_wormhole":
		// USUM Ultra Warp Ride (non-legendary). Shiny percent scales with distance
		// (capped at 5000 ly, k<=9) and ring rarity; Shiny Charm has NO effect.
		// Legendary wormhole encounters are soft-resets and use "static", not this.
		ring := paramInt(params, "wormhole_ring_type", 4)
		k := max(0, min(paramInt(params, "wormhole_distance_ly", 0)/500-1, 9))
		percent := 1
		switch ring {
		case 2:
			percent = min(10, 1+1*k)
		case 3:
			percent = min(19, 1+2*k)
		case 4:
			percent = min(36, 1+4*k)
		default: // ring 1 (or unknown): flat 1%
			percent = 1
		}
		if percent < 1 {
			percent = 1
		}
		return int(math.Round(100.0 / float64(percent)))
```

- [ ] **Step 4: Add `DefaultParams` entry**

```go
	case "ultra_wormhole":
		return map[string]any{"wormhole_ring_type": 4, "wormhole_distance_ly": 5000}
```

- [ ] **Step 5: Run, verify it passes**

Run: `cd backend && go test ./internal/calc/ -run TestEffectiveOddsWormhole -v`
Expected: PASS.

- [ ] **Step 6: Run the full calc suite (no regressions)**

Run: `cd backend && go test ./internal/calc/ -v`
Expected: PASS for all existing tests + the two new ones.

- [ ] **Step 7: Commit**

```bash
git -C /Users/casper/Fritidsprosjekt/ShinyTracker add backend/internal/calc/methods.go backend/internal/calc/methods_test.go
git -C /Users/casper/Fritidsprosjekt/ShinyTracker commit -m "feat(odds): ultra_wormhole formula for USUM Ultra Warp Ride"
```

---

## Task 3: Fix the stale parity comment (C1)

**Files:** Modify: `backend/internal/calc/methods.go`

- [ ] **Step 1: Replace the comment**

Replace the `EffectiveOdds` doc comment (currently lines ~23-28) with:

```go
// EffectiveOdds returns the integer "1 / N" denominator for a method. It mirrors
// calculateOdds() in frontend/src/utils/odds.ts. Known intentional divergence:
// catch_combo_lgpe/chain_fishing_gen6 read their count from the "count" param in
// Go (route ranking supplies it via DefaultParams) but from the live encounter
// counter in TS. Both engines now add the SV sparkling term. ultra_wormhole and
// pla_research are also mirrored in both. Unknown formulas behave as "static".
```

- [ ] **Step 2: Verify it still builds**

Run: `cd backend && go build ./... && go test ./internal/calc/`
Expected: build clean, tests PASS.

- [ ] **Step 3: Commit**

```bash
git -C /Users/casper/Fritidsprosjekt/ShinyTracker add backend/internal/calc/methods.go
git -C /Users/casper/Fritidsprosjekt/ShinyTracker commit -m "docs(odds): correct stale TS-parity comment in EffectiveOdds"
```

---

## Task 4: Delete the dead ETA helper (C3)

**Files:** Modify: `backend/internal/calc/odds.go`

- [ ] **Step 1: Confirm there are no callers**

Run: `cd backend && grep -rn "CalculateEstimatedTimeHours" --include="*.go" .`
Expected: only the definition in `internal/calc/odds.go`. (If any other caller appears, STOP and route that caller through `EffectiveOdds` instead — do not delete.)

- [ ] **Step 2: Delete the function**

Remove `CalculateEstimatedTimeHours` from `odds.go` (lines 11-23). Leave the `OddsConfig` struct — it is used by `EffectiveOdds` and callers. The file should be just the `OddsConfig` struct after this.

- [ ] **Step 3: Verify build + tests**

Run: `cd backend && go build ./... && go test ./...`
Expected: build clean, all tests PASS (nothing referenced the deleted function).

- [ ] **Step 4: Commit**

```bash
git -C /Users/casper/Fritidsprosjekt/ShinyTracker add backend/internal/calc/odds.go
git -C /Users/casper/Fritidsprosjekt/ShinyTracker commit -m "refactor(odds): drop dead CalculateEstimatedTimeHours (ETA uses EffectiveOdds)"
```

---

## Task 5: Mirror both formulas in TypeScript (`odds.ts`)

**Files:** Modify: `frontend/src/utils/odds.ts`

> No frontend test runner exists; verification is `tsc` (via `npm run build`) + the anchor numbers, which MUST match Task 1/2 exactly.

- [ ] **Step 1: Extend `PARAM_FORMULAS`**

Both new formulas need the param editor, so add them to `PARAM_FORMULAS`:

```ts
export const PARAM_FORMULAS = [
	"outbreak_defeats_sv",
	"radar_chain_gen4",
	"sos_chain_gen7",
	"dexnav_gen6",
	"sandwich_power_sv",
	"pla_research",
	"ultra_wormhole",
] as const;
```

- [ ] **Step 2: Add `defaultParamsFor` entries**

In `defaultParamsFor`, add cases above `default` (these are user-set, not encounter-derived, so seed sensible starting values):

```ts
		case "pla_research":
			// research_level/dex_perfect/outbreak flags are all user-set.
			return { research_level: 0, dex_perfect: false, mass_outbreak: false, massive_outbreak: false };
		case "ultra_wormhole":
			return { wormhole_ring_type: 4, wormhole_distance_ly: 0 };
```

- [ ] **Step 3: Add the `pla_research` branch in `calculateOdds`**

After the `chain_fishing_gen6` branch, before the closing `return`:

```ts
	} else if (type === "pla_research") {
		// Legends: Arceus additive rolls. Anchors (charmRolls=3, floorDiv):
		// base 4096 | research10 2048 | perfect 1024 | charm-only 1024 |
		// MO 157 | MO+perfect 141 | MO+perfect+charm 128 |
		// MMO 315 | MMO+perfect 256 | MMO+perfect+charm 215.
		// Lv10 (+1) and Perfect (+2) STACK. MO (+25) and MMO (+12) are exclusive; MO wins.
		let extraRolls = 0;
		const research = typeof huntParams.research_level === "number" ? huntParams.research_level : 0;
		if (research >= 10) extraRolls += 1;
		if (huntParams.dex_perfect === true) extraRolls += 2;
		if (huntParams.mass_outbreak === true) extraRolls += 25;
		else if (huntParams.massive_outbreak === true) extraRolls += 12;
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = Math.floor(baseOdds / rolls);
	} else if (type === "ultra_wormhole") {
		// USUM Ultra Warp Ride (non-legendary). Distance (cap 5000ly, k<=9) x ring rarity.
		// Shiny Charm has NO effect. Anchors: ring4@5000 ->3, ring4@2000 ->8,
		// ring3@5000 ->5, ring2@5000 ->10, ring1 ->100, ring4@0 ->100.
		const ring = typeof huntParams.wormhole_ring_type === "number" ? huntParams.wormhole_ring_type : 4;
		const dist = typeof huntParams.wormhole_distance_ly === "number" ? huntParams.wormhole_distance_ly : 0;
		const k = Math.max(0, Math.min(Math.floor(dist / 500) - 1, 9));
		let percent = 1;
		if (ring === 2) percent = Math.min(10, 1 + 1 * k);
		else if (ring === 3) percent = Math.min(19, 1 + 2 * k);
		else if (ring === 4) percent = Math.min(36, 1 + 4 * k);
		else percent = 1;
		if (percent < 1) percent = 1;
		denominator = Math.round(100 / percent);
		rolls = 1;
	}
```

- [ ] **Step 4: Type-check**

Run: `cd frontend && npm run build`
Expected: `tsc -b` clean, Vite build succeeds.

- [ ] **Step 5: Spot-check anchors by hand**

Confirm by reading the branch: ring4/5000 → k=9 → percent 36 → round(100/36)=3 ✓; PLA MO+perfect+charm → rolls 1+25+1+2+3=32 → floor(4096/32)=128 ✓. (These MUST equal the Go test anchors.)

- [ ] **Step 6: Commit**

```bash
git -C /Users/casper/Fritidsprosjekt/ShinyTracker add frontend/src/utils/odds.ts
git -C /Users/casper/Fritidsprosjekt/ShinyTracker commit -m "feat(odds): mirror pla_research and ultra_wormhole in TS calculateOdds"
```

---

## Task 6: Seed rows for PLA + Ultra Wormhole

**Files:** Modify: `backend/seeds/hunt_methods.json`

- [ ] **Step 1: Remove the old `mass_outbreak_la` row**

Find and delete the existing `mass_outbreak_la` object in the array (search `"mass_outbreak_la"`). Also remove any implicit/static Legends:Arceus row if one is hardcoded for that game in the seed (search `"Legends: Arceus"`).

- [ ] **Step 2: Add the four new rows**

Insert these objects into the `hunt_methods.json` array (match the existing field style; `requires_terrain` omitted where not applicable):

```json
  {
    "id": "pla_full_odds",
    "games": ["Legends: Arceus"],
    "method_name": "Wild / Static",
    "avg_time_seconds": 30,
    "base_rolls": 1,
    "charm_rolls": 3,
    "formula_type": "pla_research",
    "requires_kind": "wild"
  },
  {
    "id": "pla_mass_outbreak",
    "games": ["Legends: Arceus"],
    "method_name": "Mass Outbreak",
    "avg_time_seconds": 15,
    "base_rolls": 1,
    "charm_rolls": 3,
    "formula_type": "pla_research",
    "requires_kind": "wild"
  },
  {
    "id": "pla_massive_outbreak",
    "games": ["Legends: Arceus"],
    "method_name": "Massive Mass Outbreak",
    "avg_time_seconds": 8,
    "base_rolls": 1,
    "charm_rolls": 3,
    "formula_type": "pla_research",
    "requires_kind": "wild"
  },
  {
    "id": "ultra_warp_ride_usum",
    "games": ["Ultra Sun/Ultra Moon"],
    "method_name": "Ultra Warp Ride",
    "avg_time_seconds": 60,
    "base_rolls": 1,
    "charm_rolls": 2,
    "formula_type": "ultra_wormhole",
    "requires_kind": "static"
  }
```

> Confirm the exact game string for USUM matches the `games` table title (grep the seed for an existing USUM row, e.g. `"Ultra Sun/Ultra Moon"`, and reuse that exact spelling). If the catalog uses a different separator, match it.

- [ ] **Step 3: Validate JSON**

Run: `cd backend && python3 -m json.tool seeds/hunt_methods.json > /dev/null && echo OK`
Expected: `OK` (no JSON syntax error).

- [ ] **Step 4: Commit** (seeding the live DB happens in Task 10)

```bash
git -C /Users/casper/Fritidsprosjekt/ShinyTracker add backend/seeds/hunt_methods.json
git -C /Users/casper/Fritidsprosjekt/ShinyTracker commit -m "feat(seed): PLA outbreak tiers + USUM Ultra Warp Ride methods"
```

---

## Task 7: `acquisition_type` CHECK migration (PHASE)

**Files:** Modify: `backend/schema.sql`; apply additive migration to live Supabase DB.

- [ ] **Step 1: Update `schema.sql`**

At `backend/schema.sql:137`, change the CHECK to include `'PHASE'`:

```sql
    acquisition_type VARCHAR NOT NULL DEFAULT 'HUNTED' CHECK (acquisition_type IN ('HUNTED', 'EVOLVED', 'MANUAL_OVERRIDE', 'TRADED', 'PHASE')),
```

- [ ] **Step 2: Write the additive migration SQL**

The migration drops and recreates the constraint. The constraint name is auto-generated (`user_hunts_acquisition_type_check` by Postgres convention). Migration:

```sql
ALTER TABLE user_hunts DROP CONSTRAINT IF EXISTS user_hunts_acquisition_type_check;
ALTER TABLE user_hunts ADD CONSTRAINT user_hunts_acquisition_type_check
  CHECK (acquisition_type IN ('HUNTED', 'EVOLVED', 'MANUAL_OVERRIDE', 'TRADED', 'PHASE'));
```

- [ ] **Step 3: Apply to the live DB BEFORE deploying Task 8 code**

Apply via the project's normal DB access (Supabase MCP `apply_migration`, name `add_phase_acquisition_type`, or the same path used for prior schema changes). Verify:

```sql
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'user_hunts_acquisition_type_check';
```
Expected: the definition lists `'PHASE'`.

> ORDERING GATE: Task 8's INSERT writes `'PHASE'`. This migration MUST be applied to the live DB before that code runs, or the insert fails the CHECK.

- [ ] **Step 4: Commit the schema doc**

```bash
git -C /Users/casper/Fritidsprosjekt/ShinyTracker add backend/schema.sql
git -C /Users/casper/Fritidsprosjekt/ShinyTracker commit -m "feat(schema): allow PHASE acquisition_type"
```

---

## Task 8: Phase row integrity in `LogPhaseHandler`

**Files:** Modify: `backend/internal/api/hunts.go`

- [ ] **Step 1: Capture the parent hunt's `game_id`**

In `LogPhaseHandler`, the ownership `SELECT` (around line 245) currently reads `encounter_count, status`. Add `game_id`:

```go
	var currentCount int
	var huntStatus string
	var parentGameID int
	err := database.DB.QueryRow(context.Background(),
		`SELECT encounter_count, status, game_id FROM user_hunts WHERE id = $1 AND user_id = $2`,
		huntID, userID).Scan(&currentCount, &huntStatus, &parentGameID)
```

- [ ] **Step 2: Fix the phase collection INSERT**

Replace the "Add phase pokemon to collection" INSERT (around lines 281-287) with one that carries `game_id`, sets `encounter_count = 0`, and uses `'PHASE'`:

```go
	// Add phase pokemon to collection as its own completed entry. It carries the
	// parent hunt's game, encounter_count 0 (a phase appeared once, mid-hunt), and
	// the PHASE acquisition type so it is distinguishable from a deliberate hunt.
	if _, err := tx.Exec(context.Background(),
		`INSERT INTO user_hunts (user_id, pokemon_id, game_id, hunt_method_id, acquisition_type, encounter_count, status, hunt_parameters)
		 VALUES ($1, $2, $3, NULL, 'PHASE', 0, 'completed', '{}')`,
		userID, req.PokemonID, parentGameID); err != nil {
		http.Error(w, "Failed to add phase pokemon to collection", http.StatusInternalServerError)
		return
	}
```

- [ ] **Step 3: Build**

Run: `cd backend && go build ./...`
Expected: clean.

- [ ] **Step 4: Manual smoke test**

Start the API (`go run ./cmd/api/main.go`), and from the running frontend (or curl with a valid token) log a phase on an active hunt. Then query:

```sql
SELECT pokemon_id, game_id, encounter_count, acquisition_type, status
FROM user_hunts WHERE acquisition_type = 'PHASE' ORDER BY created_at DESC LIMIT 1;
```
Expected: one row with the parent's `game_id`, `encounter_count = 0`, `acquisition_type = 'PHASE'`, `status = 'completed'`.

- [ ] **Step 5: Commit**

```bash
git -C /Users/casper/Fritidsprosjekt/ShinyTracker add backend/internal/api/hunts.go
git -C /Users/casper/Fritidsprosjekt/ShinyTracker commit -m "fix(hunts): phase rows carry parent game, count 0, PHASE acquisition_type"
```

---

## Task 9: Param editor inputs + PHASE label (frontend)

**Files:** Modify: `frontend/src/components/ui/HuntParametersEditor.tsx`, `frontend/src/components/HistoricHunts.tsx`

- [ ] **Step 1: Add the `pla_research` input block**

In `HuntParametersEditor.tsx`, add before the closing `</div>` of the container (after the `sandwich_power_sv` block), following the existing label/checkbox style:

```tsx
			{formulaType === "pla_research" && (
				<>
					<div className="t-label" style={{ marginBottom: 6 }}>
						Research
					</div>
					<div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
						<label style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}>
							<input
								type="checkbox"
								checked={huntParams.research_level >= 10}
								onChange={(e) =>
									setHuntParams({ ...huntParams, research_level: e.target.checked ? 10 : 0 })
								}
							/>{" "}
							Research Lv.10
						</label>
						<label style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}>
							<input
								type="checkbox"
								checked={huntParams.dex_perfect === true}
								onChange={(e) =>
									setHuntParams({ ...huntParams, dex_perfect: e.target.checked })
								}
							/>{" "}
							Perfect research
						</label>
					</div>
					<div className="t-label" style={{ marginBottom: 6, marginTop: 10 }}>
						Outbreak
					</div>
					<div style={{ display: "flex", gap: 12 }}>
						<label style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}>
							<input
								type="radio"
								name="pla_outbreak"
								checked={!huntParams.mass_outbreak && !huntParams.massive_outbreak}
								onChange={() =>
									setHuntParams({ ...huntParams, mass_outbreak: false, massive_outbreak: false })
								}
							/>{" "}
							None
						</label>
						<label style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}>
							<input
								type="radio"
								name="pla_outbreak"
								checked={huntParams.mass_outbreak === true}
								onChange={() =>
									setHuntParams({ ...huntParams, mass_outbreak: true, massive_outbreak: false })
								}
							/>{" "}
							Mass Outbreak
						</label>
						<label style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}>
							<input
								type="radio"
								name="pla_outbreak"
								checked={huntParams.massive_outbreak === true}
								onChange={() =>
									setHuntParams({ ...huntParams, massive_outbreak: true, mass_outbreak: false })
								}
							/>{" "}
							Massive Mass Outbreak
						</label>
					</div>
				</>
			)}
			{formulaType === "ultra_wormhole" && (
				<div style={{ display: "flex", gap: 16 }}>
					<div>
						<div className="t-label" style={{ marginBottom: 6 }}>
							Ring Type (rarity)
						</div>
						<select
							className="input"
							style={{ padding: "4px 8px" }}
							value={huntParams.wormhole_ring_type || 4}
							onChange={(e) =>
								setHuntParams({ ...huntParams, wormhole_ring_type: parseInt(e.target.value) || 4 })
							}
						>
							<option value={1}>1 ring</option>
							<option value={2}>2 rings</option>
							<option value={3}>3 rings</option>
							<option value={4}>4 rings</option>
						</select>
					</div>
					<div>
						<div className="t-label" style={{ marginBottom: 6 }}>
							Distance (light-years)
						</div>
						<input
							type="number"
							min={0}
							max={9999}
							className="input"
							style={{ width: 90, padding: "4px 8px" }}
							value={huntParams.wormhole_distance_ly || 0}
							onChange={(e) =>
								setHuntParams({ ...huntParams, wormhole_distance_ly: parseInt(e.target.value) || 0 })
							}
						/>
					</div>
				</div>
			)}
```

- [ ] **Step 2: Add a PHASE label in HistoricHunts**

PHASE rows already pass the existing `acquisition_type !== "MANUAL_OVERRIDE"` filter (HistoricHunts.tsx:56), so they display. Add a small label so a phased shiny is identifiable. Near where the row renders acquisition info, add:

```tsx
{h.acquisition_type === "PHASE" && (
	<span className="chip" style={{ fontSize: 11 }}>Phase</span>
)}
```

> Read the surrounding JSX first and place this consistently with how other per-row chips/labels are rendered; reuse an existing chip class if `chip` isn't the right token.

- [ ] **Step 3: Type-check + lint**

Run: `cd frontend && npm run build && npm run lint`
Expected: `tsc` clean, Biome clean.

- [ ] **Step 4: Manual UI check**

In the running app, start a new Legends:Arceus hunt → the param editor shows Research checkboxes + Outbreak radios; selecting Mass Outbreak + Perfect shows odds near 1/141 (1/128 with charm). Start a USUM Ultra Warp Ride hunt → ring/distance inputs show; ring 4 @ 5000 shows ~1/3.

- [ ] **Step 5: Commit**

```bash
git -C /Users/casper/Fritidsprosjekt/ShinyTracker add frontend/src/components/ui/HuntParametersEditor.tsx frontend/src/components/HistoricHunts.tsx
git -C /Users/casper/Fritidsprosjekt/ShinyTracker commit -m "feat(ui): PLA research/outbreak + Ultra Wormhole hunt params; PHASE label"
```

---

## Task 10: Re-seed, audit, full verification

**Files:** none (operational)

- [ ] **Step 1: Re-seed methods in the correct order**

Seed order is a known footgun: `cmd/seed` truncates `hunt_methods` and must run LAST, or `method_availability` ends up empty. Run the method-seed tooling that ingests `hunt_methods.json` (e.g. `go run ./cmd/seed_methods/main.go`), then any availability seed, ending with `cmd/seed` only if the established pipeline requires it. Follow the documented seed order exactly.

- [ ] **Step 2: Audit method coverage**

Run: `cd backend && go run ./cmd/audit_methods/main.go`
Expected: PLA rows (`pla_full_odds`, `pla_mass_outbreak`, `pla_massive_outbreak`) and `ultra_warp_ride_usum` present; `method_availability` non-empty; no new "available but no method" regressions for Legends:Arceus / USUM.

- [ ] **Step 3: Verify the new methods resolve odds via the live API**

With the API running, hit the estimate endpoint for a PLA mass-outbreak method id and a wormhole method id; confirm the returned denominator/ETA is sane (PLA MO best-case ≈ 1/141; wormhole best-case ≈ 1/3).

- [ ] **Step 4: Full build + test sweep**

```bash
cd backend && go build ./... && go test ./...
cd ../frontend && npm run build && npm run lint
```
Expected: all green.

- [ ] **Step 5: Code review**

Dispatch `code-reviewer` on the full branch diff (correctness, security, idiom) before considering the batch done. Address findings.

---

## Self-Review Notes

- **Spec coverage:** A1 → Tasks 1,6,9; B1 → Tasks 2,6,9; A3 → Tasks 7,8,9; C3 → Task 4; C1 → Tasks 1,2,3. All five spec items have tasks.
- **Anchor consistency:** Go anchors (Task 1/2) and TS branch (Task 5) use identical constants; the "charm only = 1024" correction is called out so the +3 PLA charm isn't accidentally tested at the Gen5 1365 value.
- **Ordering gate:** Task 7 (live CHECK migration) must precede Task 8 deploy; Task 10 re-seed must follow Task 6 and respect seed order. Both gates are stated in-task.
- **Wormhole sub-4 denominator risk:** denominators of 3 are valid in `calcCumulativeOdds` (`1 - 1/3` is fine) and ETA; no special handling required, confirmed in spec risks.
