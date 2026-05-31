# Odds Correctness Pack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two incorrect shiny-odds numbers — Friend Safari rolls and the Poké Radar chain formula — so the method engine matches real game mechanics.

**Architecture:** Friend Safari is a pure seed-data edit (the existing `static` formula already reads the roll counts). Poké Radar is a formula replacement applied identically in the Go engine (`methods.go`, route ranking/ETA) and the TypeScript engine (`utils/odds.ts`, live displays); the Go unit tests encode the corrected breakpoints and are written test-first.

**Tech Stack:** Go (`backend/internal/calc`, `go test`), TypeScript (`frontend/src/utils`), JSON seed data.

**Spec:** `docs/superpowers/specs/2026-05-31-odds-correctness-pack-design.md`

---

## File Structure

- `backend/seeds/hunt_methods.json` — modify the `friend_safari_xy` entry (roll counts).
- `backend/internal/calc/methods.go` — modify the `radar_chain_gen4` case in `EffectiveOdds` (~line 49).
- `backend/internal/calc/methods_test.go` — modify radar test expectations (~lines 22-24, 58) and add a chain-1 case.
- `frontend/src/utils/odds.ts` — modify the `radar_chain_gen4` branch (~line 57) for parity.

No new files, no DDL, no API or component changes.

---

### Task 1: Friend Safari roll counts (data)

**Files:**
- Modify: `backend/seeds/hunt_methods.json` (entry `friend_safari_xy`, ~lines 151-161)

- [ ] **Step 1: Edit the roll counts**

In `backend/seeds/hunt_methods.json`, change the `friend_safari_xy` entry from:

```json
    "id": "friend_safari_xy",
    "games": [
      "X/Y"
    ],
    "method_name": "Friend Safari",
    "avg_time_seconds": 20,
    "base_rolls": 1,
    "charm_rolls": 0,
    "formula_type": "static",
    "requires_kind": "wild"
```

to (only `base_rolls` and `charm_rolls` change):

```json
    "id": "friend_safari_xy",
    "games": [
      "X/Y"
    ],
    "method_name": "Friend Safari",
    "avg_time_seconds": 20,
    "base_rolls": 5,
    "charm_rolls": 2,
    "formula_type": "static",
    "requires_kind": "wild"
```

- [ ] **Step 2: Verify the JSON is still valid**

Run: `python3 -m json.tool backend/seeds/hunt_methods.json > /dev/null && echo OK`
Expected: `OK` (no parse error)

- [ ] **Step 3: Sanity-check the resulting odds**

With `base_odds = 4096`, the `static` formula gives `floor(4096/5) = 819` (no charm) and `floor(4096/7) = 585` (charm). These are the intended ~1/819 / ~1/585 values. No command — confirm by reading the numbers.

- [ ] **Step 4: Commit**

```bash
git add backend/seeds/hunt_methods.json
git commit -m "Fix Friend Safari shiny odds: 5 base rolls, +2 charm (was full odds)

Friend Safari generates up to 4 extra PIDs (5 rolls total, ~1/819);
Shiny Charm stacks to 7 rolls (~1/585). Was incorrectly seeded at
1/4096. Takes effect after a cmd/seed re-run.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Poké Radar formula — Go engine (test-first)

**Files:**
- Modify: `backend/internal/calc/methods_test.go` (radar cases ~lines 22-24, default check ~line 58)
- Modify: `backend/internal/calc/methods.go` (`case "radar_chain_gen4"` ~line 49)

- [ ] **Step 1: Update the failing tests to the corrected expectations**

In `backend/internal/calc/methods_test.go`, replace the three radar table cases:

```go
		{"radar chain40", "radar_chain_gen4", map[string]any{"chain_length": 40}, false, 99},
		{"radar chain40 charm ignored", "radar_chain_gen4", map[string]any{"chain_length": 40}, true, 99},
		{"radar chain0", "radar_chain_gen4", map[string]any{"chain_length": 0}, false, 65536},
```

with (corrected values + a new chain-1 case):

```go
		{"radar chain40", "radar_chain_gen4", map[string]any{"chain_length": 40}, false, 200},
		{"radar chain40 charm ignored", "radar_chain_gen4", map[string]any{"chain_length": 40}, true, 200},
		{"radar chain1", "radar_chain_gen4", map[string]any{"chain_length": 1}, false, 7282},
		{"radar chain0", "radar_chain_gen4", map[string]any{"chain_length": 0}, false, 8192},
```

Then update the default-params check (~line 58) from:

```go
	// Radar default should be the chain-40 plateau, 99.
	if got := EffectiveOdds("radar_chain_gen4", DefaultParams("radar_chain_gen4"), base, false); got != 99 {
		t.Errorf("radar default = %d, want 99", got)
	}
```

to:

```go
	// Radar default should be the chain-40 plateau, 200.
	if got := EffectiveOdds("radar_chain_gen4", DefaultParams("radar_chain_gen4"), base, false); got != 200 {
		t.Errorf("radar default = %d, want 200", got)
	}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd backend && go test ./internal/calc/`
Expected: FAIL — the radar cases report `got 65536/99, want 8192/200` because the formula hasn't been changed yet.

- [ ] **Step 3: Replace the radar formula**

In `backend/internal/calc/methods.go`, replace the `radar_chain_gen4` case:

```go
	case "radar_chain_gen4":
		// 65536 = Gen 4 RNG range; 1635.925 step lands exactly on 1/99 at the chain-40 cap.
		chain := max(0, min(paramInt(params, "chain_length", 0), 40))
		den := int(math.Round(65536 - 1635.925*float64(chain)))
		if den < 99 {
			den = 99
		}
		return den
```

with:

```go
	case "radar_chain_gen4":
		// Bulbapedia: numerator = ceil(65535 / (8200 - 200*chain)); rate = numerator / 65536.
		// chain 0 -> 1/8192 (base Gen 4 odds); chain 40 (cap) -> 1/200. No Shiny Charm in Gen 4.
		chain := max(0, min(paramInt(params, "chain_length", 0), 40))
		numerator := int(math.Ceil(65535.0 / float64(8200-200*chain)))
		return int(math.Round(65536.0 / float64(numerator)))
```

(`math` is already imported in this file.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd backend && go test ./internal/calc/`
Expected: PASS (`ok  .../internal/calc`)

- [ ] **Step 5: Commit**

```bash
git add backend/internal/calc/methods.go backend/internal/calc/methods_test.go
git commit -m "Fix Poke Radar shiny formula (Go): exact Bulbapedia mechanic

Replaces linear approximation (1/65536 at chain 0, 1/99 at chain 40)
with ceil(65535/(8200-200*chain))/65536: chain 0 = base 1/8192,
chain 40 cap = 1/200. Tests updated to corrected breakpoints.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Poké Radar formula — TypeScript engine (parity)

**Files:**
- Modify: `frontend/src/utils/odds.ts` (`radar_chain_gen4` branch ~line 57)

The frontend has no test runner; parity is verified by matching the Go test breakpoints (chain 0 → 8192, chain 1 → 7282, chain 40 → 200).

- [ ] **Step 1: Replace the radar branch**

In `frontend/src/utils/odds.ts`, replace:

```ts
	if (type === "radar_chain_gen4") {
		const paramChain = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const chain = Math.max(0, Math.min(paramChain, 40));
		// Capped at 40. formula: 1 / round(65536 - 1640 * chain)
		// Yields 1/99 at chain 40. We use 1635.925 as the step to land exactly on 99.
		denominator = Math.max(99, Math.round(65536 - 1635.925 * chain));
		// Shiny Charm doesn't apply to Gen 4 Pokeradar
		rolls = 1;
	} else if (type === "catch_combo_lgpe") {
```

with:

```ts
	if (type === "radar_chain_gen4") {
		const paramChain = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const chain = Math.max(0, Math.min(paramChain, 40));
		// Bulbapedia: numerator = ceil(65535 / (8200 - 200*chain)); rate = numerator / 65536.
		// chain 0 -> 1/8192 (base Gen 4 odds); chain 40 (cap) -> 1/200.
		const numerator = Math.ceil(65535 / (8200 - 200 * chain));
		denominator = Math.round(65536 / numerator);
		// Shiny Charm doesn't apply to Gen 4 Pokeradar
		rolls = 1;
	} else if (type === "catch_combo_lgpe") {
```

- [ ] **Step 2: Verify the build/lint passes**

Run: `cd frontend && npm run build`
Expected: build succeeds (tsc + vite, no type errors).

- [ ] **Step 3: Spot-check parity by inspection**

Confirm the formula matches Go for the three breakpoints: chain 0 → `ceil(65535/8200)=8`, `round(65536/8)=8192`; chain 1 → `ceil(65535/8000)=9`, `round(65536/9)=7282`; chain 40 → `ceil(65535/200)=328`, `round(65536/328)=200`. No command — confirm by reading the arithmetic.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/utils/odds.ts
git commit -m "Fix Poke Radar shiny formula (TS): parity with Go engine

Same exact Bulbapedia mechanic as the Go change: chain 0 = 1/8192,
chain 40 cap = 1/200. Keeps live displays in sync with route ranking.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation note (not a code task)

The Friend Safari fix (Task 1) only takes effect once `cmd/seed` is re-run against the shared Supabase DB (`base_rolls`/`charm_rolls` are persisted at seed time). The radar fix (Tasks 2-3) is code-only and lands on the next deploy. Call this out in the PR description so the re-seed isn't forgotten. Per TASKS.md operational notes, `cmd/seed` must run LAST in any rebuild sequence.
