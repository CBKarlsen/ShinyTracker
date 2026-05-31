# Odds Correctness Pack — Design

**Date:** 2026-05-31
**Status:** Approved (design)
**Sub-project:** 1 of 5 in the "expert-flagged fixes" decomposition (see TASKS.md follow-ups). Successor sub-projects: 2 PLA research-level odds, 3 shiny-lock audit (+ lock-note surfacing), 4 living-dex scope selector, 5 completion forecast.

## Problem

The `shiny-hunt-expert` review found two **incorrect odds numbers** in the method engine. Wrong numbers erode trust in the whole odds engine faster than missing methods do, and both of these are visible to any hunter who knows the method. Both were web-verified against Bulbapedia/Smogon before this spec.

1. **Friend Safari (X/Y, Gen 6)** is seeded at full odds (`base_rolls: 1, charm_rolls: 0`), i.e. 1/4096. The real mechanic generates up to 4 extra personality values → **5 total rolls** (~1/819), and the Shiny Charm stacks to **7 rolls** (~1/585). The method is currently shown as ~8× worse than reality.

2. **Poké Radar (Gen 4, D/P/Pt)** uses a linear approximation `denom = round(65536 − 1635.925·chain)` clamped at 99. This is wrong at both ends:
   - **chain 0 → 1/65536** — absurd; a hunter at chain 0 is at the game's base **1/8192**.
   - **chain 40 → 1/99** — too generous; the real plateau is **1/200**.

## Scope

In scope (this sub-project, odds/calc/seed layer only — **no DDL, no frontend, no new endpoints**):
- Fix Friend Safari rolls (data).
- Replace the Poké Radar formula in both the TS and Go odds engines with the exact mechanic, and update the Go tests.

Explicitly **out of scope** (deferred to later sub-projects, per the decomposition):
- Surfacing the shiny-lock `_note` in the UI → **sub-project 3** (the note is not stored in the DB; adding a column + persistence + API + frontend belongs with the audit that rewrites every note).
- PLA research-level/outbreak-clear odds → sub-project 2.
- Per-encounter Poké Radar "shiny patch ring" factor (28–88% by distance ring). The app models every method as a single shiny-check denominator; adding ring modeling here would be inconsistent with all other methods. YAGNI.

## Verified mechanics (sources)

- Friend Safari: 5 rolls (no charm) / 7 rolls (charm). Charm **does** stack. The "1/512" community figure is a myth (no clean roll count). — Bulbapedia (Friend Safari), Smogon Friend Safari shiny-rate data thread.
- Poké Radar (D/P/Pt only — HGSS has no Radar): `numerator = ceil(65535 / (8200 − chain×200))`, rate = `numerator / 65536`. Chain 0 → 8/65536 = **1/8192**. Chain 40 (cap) → 328/65536 ≈ **1/200**. No Shiny Charm in Gen 4 (`charm_rolls = 0`). — Bulbapedia (Poké Radar), Smogon DPP Poké Radar guide.

## Design

### Fix 1 — Friend Safari rolls (data only)

`backend/seeds/hunt_methods.json`, entry `friend_safari_xy`:

```
base_rolls:  1 → 5
charm_rolls: 0 → 2
formula_type: "static"   (unchanged — the static formula already reads base/charm rolls)
```

No code change. `calc.EffectiveOdds`'s `static` branch and `utils/odds.ts`'s `static` branch both already compute `denom = floor(baseOdds / (baseRolls + (charm ? charmRolls : 0)))`. After the edit: no charm → `floor(4096/5) = 819`; charm → `floor(4096/7) = 585`.

**Deploy dependency:** `base_rolls`/`charm_rolls` are persisted to the DB at seed time, so this value only takes effect after a `cmd/seed` re-run against the shared Supabase DB. Per the operational notes in TASKS.md, `cmd/seed` must run LAST in any rebuild.

### Fix 2 — Poké Radar formula (both engines + Go tests)

Replace the formula in **both** engines. They must stay in parity (the TS engine is the source of truth for live displays; the Go engine drives route ranking/ETA).

**`frontend/src/utils/odds.ts`** — `radar_chain_gen4` branch (currently ~line 57):

```ts
if (type === "radar_chain_gen4") {
  const paramChain = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
  const chain = Math.max(0, Math.min(paramChain, 40));
  // Bulbapedia: numerator = ceil(65535 / (8200 - 200*chain)); rate = numerator / 65536.
  // chain 0 -> 1/8192 (base Gen 4 odds); chain 40 (cap) -> 1/200.
  const numerator = Math.ceil(65535 / (8200 - 200 * chain));
  denominator = Math.round(65536 / numerator);
  // Shiny Charm did not exist in Gen 4.
  rolls = 1;
}
```

**`backend/internal/calc/methods.go`** — `case "radar_chain_gen4"` (currently ~line 49):

```go
case "radar_chain_gen4":
    // Bulbapedia: numerator = ceil(65535 / (8200 - 200*chain)); rate = numerator / 65536.
    // chain 0 -> 1/8192 (base Gen 4 odds); chain 40 (cap) -> 1/200. No charm in Gen 4.
    chain := max(0, min(paramInt(params, "chain_length", 0), 40))
    numerator := int(math.Ceil(65535.0 / float64(8200-200*chain)))
    return int(math.Round(65536.0 / float64(numerator)))
```

`DefaultParams("radar_chain_gen4")` stays `{"chain_length": 40}` — now the honest 1/200 plateau.

**Note:** the Go formula now ignores `base.BaseOdds` for radar (it computes the absolute 1/N rate directly, as the old code did). That is intentional and unchanged in spirit — Radar odds are defined independently of the per-game base odds.

### Tests (TDD)

`backend/internal/calc/methods_test.go` — update expectations to the corrected values, run to confirm red, then apply the formula fix to go green:

| Test | Old expected | New expected |
|------|-------------|-------------|
| `radar chain40` | 99 | 200 |
| `radar chain40 charm ignored` | 99 | 200 |
| `radar chain0` | 65536 | 8192 |
| `radar default` (DefaultParams) | 99 | 200 |

Update the inline comment "Radar default should be the chain-40 plateau, 99." → "…, 200."

Add one new case to document the corrected base-odds behavior:
| `radar chain1` | — | 7282 | (`ceil(65535/8000)=9`, `round(65536/9)=7282`) |

Verification command: `go test ./internal/calc/`. The TS side has no test runner; parity is verified by inspection against the Go expected values above.

## Risks / edge cases

- **Division guard:** `8200 − 200·chain` is minimized at chain 40 → 200 (never 0/negative because chain is clamped to ≤40). Safe.
- **TS/Go drift:** the two engines are edited together with identical breakpoints; the Go test values double as the TS spec.
- **Stale DB:** Friend Safari fix is invisible until a re-seed. Radar fix is code-only and lands on redeploy. Call this out in the PR/checklist so the re-seed isn't forgotten.

## Deliverables

1. `hunt_methods.json` Friend Safari → 5/2.
2. `utils/odds.ts` + `methods.go` radar formula replaced (exact Bulbapedia mechanic).
3. `methods_test.go` updated + passing (`go test ./internal/calc/` green).
4. PR note: re-run `cmd/seed` against Supabase for the Friend Safari value to take effect.
