# Modern Method Odds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Go odds engine method-aware by porting `frontend/src/utils/odds.ts` to Go, wire it into route ranking so the dex best-route reflects modern methods, and fix the create-path bug that discards hunt parameters.

**Architecture:** A new `internal/calc/methods.go` exposes `EffectiveOdds(formulaType, params, base, hasCharm) int` and `DefaultParams(formulaType) map[string]any`, mirroring `calculateOdds()` in `utils/odds.ts` branch-for-branch (the shipped TS numbers are the contract). `routes.go::computeRoute` calls `EffectiveOdds` with each method's default best params. `hunts.go` stops overriding `hunt_parameters` to `{}` on curated creates.

**Tech Stack:** Go 1.x (stdlib `testing`, pgx), no new deps, no DDL. Reference implementation: `frontend/src/utils/odds.ts`.

**Spec:** `docs/superpowers/specs/2026-05-31-modern-method-odds-design.md`

**Working directory:** the `worktree-dex-completion-engine` worktree. All `go` commands run from `backend/`.

---

## Task 1: Port the odds formulas to Go (`EffectiveOdds`)

Port every branch of `calculateOdds()` (`frontend/src/utils/odds.ts:9-114`) to Go.
Param keys and arithmetic must match the TS exactly. Note: `outbreak_defeats_sv`
gains a `sparkling_power` term that the TS does not yet have (see spec — tracked
follow-up to sync TS).

**Files:**
- Create: `backend/internal/calc/methods.go`
- Test: `backend/internal/calc/methods_test.go`

- [ ] **Step 1: Write the failing test**

Create `backend/internal/calc/methods_test.go`:

```go
package calc

import "testing"

// Parity targets computed directly from frontend/src/utils/odds.ts.
func TestEffectiveOddsParity(t *testing.T) {
	base := OddsConfig{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2}
	cases := []struct {
		name    string
		formula string
		params  map[string]any
		charm   bool
		want    int
	}{
		{"static no charm", "static", nil, false, 4096},
		{"static charm", "static", nil, true, 1365},
		{"outbreak d60+pw3+charm", "outbreak_defeats_sv", map[string]any{"defeated_count": 60, "sparkling_power": 3}, true, 512},
		{"outbreak d30 no charm", "outbreak_defeats_sv", map[string]any{"defeated_count": 30}, false, 2048},
		{"sandwich pw3 no charm", "sandwich_power_sv", map[string]any{"sparkling_power": 3}, false, 1024},
		{"sos chain31 no charm", "sos_chain_gen7", map[string]any{"chain_length": 31}, false, 315},
		{"sos chain10 no charm", "sos_chain_gen7", map[string]any{"chain_length": 10}, false, 4096},
		{"radar chain40", "radar_chain_gen4", map[string]any{"chain_length": 40}, false, 99},
		{"radar chain40 charm ignored", "radar_chain_gen4", map[string]any{"chain_length": 40}, true, 99},
		{"radar chain0", "radar_chain_gen4", map[string]any{"chain_length": 0}, false, 65536},
		{"dynamax no charm", "dynamax_adventures_gen8", nil, false, 300},
		{"dynamax charm", "dynamax_adventures_gen8", nil, true, 100},
		{"dexnav sl200 ch100", "dexnav_gen6", map[string]any{"search_level": 200, "chain_length": 100}, false, 12},
		{"unknown falls back to static", "no_such_formula", nil, false, 4096},
	}
	for _, c := range cases {
		got := EffectiveOdds(c.formula, c.params, base, c.charm)
		if got != c.want {
			t.Errorf("%s: EffectiveOdds = %d, want %d", c.name, got, c.want)
		}
	}
}

// catch_combo and chain_fishing read the live count, fed via the "count" param.
func TestEffectiveOddsCountDriven(t *testing.T) {
	base := OddsConfig{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2}
	if got := EffectiveOdds("catch_combo_lgpe", map[string]any{"count": 31}, base, false); got != 341 {
		t.Errorf("catch_combo combo31 = %d, want 341", got)
	}
	if got := EffectiveOdds("chain_fishing_gen6", map[string]any{"count": 20}, base, false); got != 99 {
		t.Errorf("chain_fishing chain20 = %d, want 99", got)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && go test ./internal/calc/ -run TestEffectiveOdds -v`
Expected: FAIL — `undefined: EffectiveOdds`.

- [ ] **Step 3: Write the implementation**

Create `backend/internal/calc/methods.go`. Mirrors `utils/odds.ts`. `catch_combo_lgpe`
and `chain_fishing_gen6` read the live count in TS; in Go we read it from a `"count"`
param (the route layer passes the default; the dashboard keeps using TS for live odds):

```go
package calc

import "math"

// paramInt reads an integer param, tolerating float64 (JSON numbers decode to
// float64 through map[string]any) and int. Missing/!numeric -> fallback.
func paramInt(params map[string]any, key string, fallback int) int {
	v, ok := params[key]
	if !ok {
		return fallback
	}
	switch n := v.(type) {
	case int:
		return n
	case int64:
		return int(n)
	case float64:
		return int(n)
	}
	return fallback
}

// EffectiveOdds returns the integer "1 / N" denominator for a method, mirroring
// calculateOdds() in frontend/src/utils/odds.ts. Unknown formulas behave as "static".
func EffectiveOdds(formulaType string, params map[string]any, base OddsConfig, hasCharm bool) int {
	if params == nil {
		params = map[string]any{}
	}
	t := formulaType
	if t == "" {
		t = "static"
	}
	charmRolls := 0
	if hasCharm {
		charmRolls = base.CharmRolls
	}
	floorDiv := func(rolls int) int {
		if rolls <= 0 {
			rolls = 1
		}
		return base.BaseOdds / rolls
	}

	switch t {
	case "radar_chain_gen4":
		chain := clampInt(paramInt(params, "chain_length", 0), 0, 40)
		den := int(math.Round(65536 - 1635.925*float64(chain)))
		if den < 99 {
			den = 99
		}
		return den

	case "catch_combo_lgpe":
		combo := maxInt(0, paramInt(params, "count", 0))
		extra := 0
		switch {
		case combo >= 31:
			extra = 11
		case combo >= 21:
			extra = 7
		case combo >= 11:
			extra = 3
		}
		return floorDiv(base.BaseRolls + extra + charmRolls)

	case "outbreak_defeats_sv":
		defeats := maxInt(0, paramInt(params, "defeated_count", 0))
		extra := 0
		switch {
		case defeats >= 60:
			extra = 2
		case defeats >= 30:
			extra = 1
		}
		// New term (not yet in TS): sandwich Sparkling Power stacks additively.
		extra += sparklingRolls(paramInt(params, "sparkling_power", 0))
		return floorDiv(base.BaseRolls + extra + charmRolls)

	case "sos_chain_gen7":
		chain := maxInt(0, paramInt(params, "chain_length", 0)) % 255
		extra := 0
		switch {
		case chain >= 31:
			extra = 12
		case chain >= 21:
			extra = 8
		case chain >= 11:
			extra = 4
		}
		return floorDiv(base.BaseRolls + extra + charmRolls)

	case "dexnav_gen6":
		searchLevel := maxInt(0, paramInt(params, "search_level", 0))
		chain := maxInt(0, paramInt(params, "chain_length", 0))
		tt := 0.0
		if searchLevel > 0 {
			tt += float64(minInt(searchLevel, 100)) * 6
		}
		if searchLevel > 100 {
			tt += float64(minInt(searchLevel-100, 100)) * 2
		}
		if searchLevel > 200 {
			tt += float64(searchLevel-200) * 1
		}
		probDexNav := 0.0
		if searchLevel > 0 {
			probDexNav = tt / 10000
		}
		extra := 0
		if chain > 0 && chain%100 == 0 {
			extra = 10
		} else if chain > 0 && chain%50 == 0 {
			extra = 5
		}
		rolls := base.BaseRolls + extra + charmRolls
		probStandard := float64(rolls) / float64(base.BaseOdds)
		totalProb := probDexNav + (1-probDexNav)*probStandard
		if totalProb <= 0 {
			return base.BaseOdds
		}
		return int(math.Round(1 / totalProb))

	case "sandwich_power_sv":
		extra := sparklingRolls(paramInt(params, "sparkling_power", 0))
		return floorDiv(base.BaseRolls + extra + charmRolls)

	case "dynamax_adventures_gen8":
		if hasCharm {
			return 100
		}
		return 300

	case "chain_fishing_gen6":
		chain := clampInt(paramInt(params, "count", 0), 0, 20)
		return floorDiv(base.BaseRolls + chain*2 + charmRolls)

	default: // "static" and any unknown formula
		return floorDiv(base.BaseRolls + charmRolls)
	}
}

func sparklingRolls(power int) int {
	switch power {
	case 1:
		return 1
	case 2:
		return 2
	case 3:
		return 3
	}
	return 0
}

func clampInt(v, lo, hi int) int { return maxInt(lo, minInt(v, hi)) }
func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd backend && go test ./internal/calc/ -run TestEffectiveOdds -v`
Expected: PASS (both test functions).

- [ ] **Step 5: Commit**

```bash
git add backend/internal/calc/methods.go backend/internal/calc/methods_test.go
git commit -m "Add method-aware EffectiveOdds engine (Go port of utils/odds.ts)"
```

---

## Task 2: Add `DefaultParams` for route ranking

Route ranking has no per-hunt params, so it needs each method's achievable-best
config to rank methods by their realistic potential.

**Files:**
- Modify: `backend/internal/calc/methods.go`
- Test: `backend/internal/calc/methods_test.go`

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/calc/methods_test.go`:

```go
func TestDefaultParamsDriveBestOdds(t *testing.T) {
	base := OddsConfig{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2}
	// With default best params + charm, outbreak should reach the 1/512 stack.
	if got := EffectiveOdds("outbreak_defeats_sv", DefaultParams("outbreak_defeats_sv"), base, true); got != 512 {
		t.Errorf("outbreak default+charm = %d, want 512", got)
	}
	// Radar default should be the chain-40 plateau, 99.
	if got := EffectiveOdds("radar_chain_gen4", DefaultParams("radar_chain_gen4"), base, false); got != 99 {
		t.Errorf("radar default = %d, want 99", got)
	}
	// Static has no params.
	if dp := DefaultParams("static"); len(dp) != 0 {
		t.Errorf("static default params = %v, want empty", dp)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && go test ./internal/calc/ -run TestDefaultParams -v`
Expected: FAIL — `undefined: DefaultParams`.

- [ ] **Step 3: Write the implementation**

Append to `backend/internal/calc/methods.go`:

```go
// DefaultParams returns each method's achievable-best parameters, used for
// route ranking (where no per-hunt params exist yet). avg_time keeps ETA honest.
func DefaultParams(formulaType string) map[string]any {
	switch formulaType {
	case "outbreak_defeats_sv":
		return map[string]any{"defeated_count": 60, "sparkling_power": 3}
	case "sandwich_power_sv":
		return map[string]any{"sparkling_power": 3}
	case "sos_chain_gen7":
		return map[string]any{"chain_length": 31}
	case "radar_chain_gen4":
		return map[string]any{"chain_length": 40}
	case "dexnav_gen6":
		return map[string]any{"search_level": 200, "chain_length": 100}
	case "catch_combo_lgpe":
		return map[string]any{"count": 31}
	case "chain_fishing_gen6":
		return map[string]any{"count": 20}
	default: // static, dynamax_adventures_gen8 (no params)
		return map[string]any{}
	}
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd backend && go test ./internal/calc/ -run TestDefaultParams -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/internal/calc/methods.go backend/internal/calc/methods_test.go
git commit -m "Add DefaultParams for method-aware route ranking"
```

---

## Task 3: Wire `EffectiveOdds` into route ranking (`computeRoute`)

Replace the inline `base_odds / total_rolls` in `computeRoute` with a call to
`EffectiveOdds`, so the dex best-route ranks modern methods correctly. The `static`
path must stay numerically identical (existing `routes_test.go` must still pass).

**Files:**
- Modify: `backend/internal/calc/routes.go:39-67` (the `computeRoute` function)
- Test: `backend/internal/calc/routes_test.go`

- [ ] **Step 1: Write the failing test**

Append to `backend/internal/calc/routes_test.go`:

```go
func TestRankUsesEffectiveOddsForModernMethods(t *testing.T) {
	cands := []MethodCandidate{
		{GameID: 1, MethodName: "Random Encounter", FormulaType: "static", BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2},
		{GameID: 1, MethodName: "Paldea Mass Outbreak", FormulaType: "outbreak_defeats_sv", BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2, HasShinyCharm: true},
	}
	routes := RankDirectRoutes(cands)
	if routes[0].MethodName != "Paldea Mass Outbreak" {
		t.Fatalf("best route = %q, want the outbreak (better effective odds)", routes[0].MethodName)
	}
	if routes[0].Odds != 512 {
		t.Fatalf("outbreak odds = %d, want 512 (default best params + charm)", routes[0].Odds)
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd backend && go test ./internal/calc/ -run TestRankUsesEffectiveOdds -v`
Expected: FAIL — outbreak odds is 4096 (flat), not 512, so the static random
encounter (charm → 1365) wrongly ranks first.

- [ ] **Step 3: Modify `computeRoute`**

In `backend/internal/calc/routes.go`, replace the odds/ETA block inside
`computeRoute` (currently lines ~40-66). Replace this:

```go
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
```

with this:

```go
func computeRoute(c MethodCandidate) Route {
	base := OddsConfig{
		BaseOdds:       c.BaseOdds,
		BaseRolls:      c.BaseRolls,
		CharmRolls:     c.CharmRolls,
		HasShinyCharm:  c.HasShinyCharm,
		AvgTimeSeconds: c.AvgTimeSeconds,
	}
	odds := EffectiveOdds(c.FormulaType, DefaultParams(c.FormulaType), base, c.HasShinyCharm)
	if odds < 1 {
		odds = 1
	}
	// ETA: expected encounters (= odds denominator) * avg_time.
	eta := float64(odds) * float64(c.AvgTimeSeconds) / 3600.0
```

Leave the rest of `computeRoute` (the `return Route{...}` with `Odds: odds, ETAHours: eta`) unchanged.

- [ ] **Step 4: Run the full calc suite to verify it passes and nothing regressed**

Run: `cd backend && go test ./internal/calc/ -v`
Expected: PASS — the new test passes AND every existing `routes_test.go` test still
passes (static methods: 4096 / 1365 / Masuda ranking all unchanged).

- [ ] **Step 5: Verify the whole backend still builds**

Run: `cd backend && go build ./...`
Expected: no output, exit 0.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/calc/routes.go backend/internal/calc/routes_test.go
git commit -m "Rank routes by method-aware EffectiveOdds; keep static behavior identical"
```

---

## Task 4: Fix `hunt_parameters` persistence on curated hunt creation

`CreateHuntHandler` discards the client's params for curated hunts. Remove the
override so the decoded `req.HuntParameters` (handled at lines 125-129) is inserted.

**Files:**
- Modify: `backend/internal/api/hunts.go:144-154` (the `hasCurated` branch)

- [ ] **Step 1: Read the current curated branch**

Confirm `backend/internal/api/hunts.go` lines 144-154 read:

```go
	} else if hasCurated {
		// Validating pokemonID and GameID are provided
		if req.PokemonID == 0 || req.GameID == 0 {
			http.Error(w, "pokemon_id and game_id required", http.StatusBadRequest)
			return
		}
		pokemonID = req.PokemonID
		gameID = &req.GameID
		huntMethodID = &req.HuntMethodID
		customMethodName = nil
		huntParameters = json.RawMessage(`{}`)
	} else {
```

- [ ] **Step 2: Remove the override line**

Delete exactly this line from the `hasCurated` branch:

```go
		huntParameters = json.RawMessage(`{}`)
```

The `huntParameters` value set at lines 125-129 (`req.HuntParameters` if non-empty,
else `{}`) now flows through to the INSERT for curated hunts too.

- [ ] **Step 3: Verify it builds**

Run: `cd backend && go build ./...`
Expected: no output, exit 0. (`json` is still imported/used elsewhere in the file.)

- [ ] **Step 4: Manual round-trip verification**

Start the API (`cd backend && go run ./cmd/api/main.go`) against the dev DB, then with
a valid token create a curated hunt with non-empty params and confirm they persist:

```bash
# Replace $TOKEN, $UID, and the ids with real values; pick a curated hunt_method_id.
curl -s -X POST http://localhost:8080/api/hunts \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"hunt_method_id":<id>,"pokemon_id":129,"game_id":<gid>,"hunt_parameters":{"defeated_count":60}}' | jq .hunt_parameters
```

Expected: `{"defeated_count":60}` (not `{}`).

- [ ] **Step 5: Commit**

```bash
git add backend/internal/api/hunts.go
git commit -m "Persist hunt_parameters on curated hunt creation (fix hunts.go override)"
```

---

## Task 5: Update docs and record follow-ups

**Files:**
- Modify: `TASKS.md`

- [ ] **Step 1: Mark #4 shipped and record the follow-ups**

In `TASKS.md`, move **#4 Modern method odds** from Backlog to the Shipped section
with a one-line summary, and add these follow-ups to the "Follow-ups / known issues"
section:

```markdown
- **TS/Go odds drift on outbreak+sandwich** — Go `EffectiveOdds` adds a
  `sparkling_power` term to `outbreak_defeats_sv`; `frontend/src/utils/odds.ts` does
  not yet. Sync TS + surface the sparkling field in the outbreak editor so the
  dashboard's live odds match the route ranking for stacked outbreak hunts.
- **Radar chain-0 quirk** — `radar_chain_gen4` returns 1/65536 at chain 0 (TS
  formula `65536 − 1635.925·chain`); mirrored in Go for parity. Revisit whether the
  base should track the game's 1/8192.
- **Method eligibility data (NEXT)** — web-source which species are huntable via each
  method per game and seed into `method_availability` / `method_exceptions`.
```

- [ ] **Step 2: Commit**

```bash
git add TASKS.md
git commit -m "Mark #4 modern method odds shipped; record TS-sync + eligibility follow-ups"
```

---

## Final verification

- [ ] Run the full calc test suite: `cd backend && go test ./internal/calc/ -v` → all PASS.
- [ ] Build everything: `cd backend && go build ./...` → exit 0.
- [ ] Confirm a curated hunt persists params (Task 4 Step 4) → params round-trip.
- [ ] Open a dex route for a Pokémon with an SV outbreak method and confirm the
      outbreak now ranks ahead of plain random encounters in the best-route list.
