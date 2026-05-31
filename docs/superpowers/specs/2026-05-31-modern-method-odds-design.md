# Modern Method Odds — Design

**Date:** 2026-05-31
**Branch:** `worktree-dex-completion-engine` (based on `hunt-method-corrections`)
**Backlog item:** TASKS.md #4 — Modern method odds
**Status:** approved design, pending implementation plan

## Problem

The odds engine is naive: shiny probability is `base_odds / total_rolls`, where
`total_rolls = base_rolls + (charm ? charm_rolls : 0)`. It never varies with any
per-hunt parameter. So the modern chaining/boosting methods — which is how a
living-dex completionist actually fills most of the current-gen dex — all show the
same flat full-odds number regardless of chain length, KO count, or sandwich level.

This feature makes the engine **formula- and parameter-aware**, covering all five
modern methods, while keeping the existing `static` behaviour unchanged.

## Decisions (locked during brainstorming)

- **Coverage:** all five methods, across **two formula kinds** (additive-rolls +
  direct-probability).
- **Parameter lifecycle:** the user declares a hunt's **steady-state config at
  creation** (e.g. "Sandwich Lv3 + Outbreak 60+", "SOS chain 31+"); it is
  **editable later** on the active hunt. One odds/ETA figure per hunt — no live
  per-encounter chain counter in this pass.
- **ETA realism:** each method carries a **realistic `avg_time`** so chaining
  methods don't unfairly dominate route ranking (per-method realism factor).
- **Architecture:** a **code registry** in `internal/calc` is the single source of
  truth; the backend **serves each method's parameter schema** and the frontend
  renders a **generic, data-driven form**. No Go↔TS duplication.
- **No new DDL:** `hunt_methods.formula_type` and `user_hunts.hunt_parameters`
  (JSONB) already exist.

## Architecture

A **formula registry** keyed by the `formula_type` string on `hunt_methods`. Each
entry bundles:

1. a **parameter schema** — an array of `{key,label,type,min,max,options,help,default}`,
2. a **compute function** — `(params, base OddsConfig, hasCharm) → (denominator int, prob float64)`,
3. a **realistic `avg_time`** default.

Two formula *kinds* sit behind a common interface:

- **Kind 1 — additive-rolls:** `R = 1 + bonus(params) + (charm ? charmRolls : 0)`,
  then `P = 1 − (1 − 1/baseOdds)^R`. Reuses the existing rolls model.
- **Kind 2 — direct-probability:** `P = g(params)` computed directly; charm handled
  per-method.

## The registry (verified math)

Math sourced from the `shiny-hunt-expert` agent (Bulbapedia / Smogon / community
consensus; see Sources). `baseOdds = 4096` for Gen 6+ methods, `8192` for
Gen 4 HGSS/Pt Radar.

| `formula_type` | Kind | Params (schema) | Compute | `avg_time` |
|---|---|---|---|---|
| `static` (default) | 1 | none | `R = base_rolls + charm` (unchanged) | existing |
| `sv_outbreak_sandwich` | 1 | `outbreakKo` int (30→+1, 60→+2); `sparklingLevel` 0–3 (→ +level) | `R = 1 + obRolls + sparkRolls + charm(+2)`; max R8 ≈ **1/512** | 20 s |
| `swsh_brilliant` | 1 | `koCount` int (50/100/200/300/500 → +1…+5) | `R = 1 + briRolls + charm(+2)`; max R8 ≈ 1/512 | 40 s |
| `gen7_sos` | 1 | `chainLength` int (11/21/31 → +1/+2/+3, cap +3) | `R = 1 + sosRolls + charm(+2)`; max R6 ≈ 1/683 | 25 s |
| `radar_chain` | 2 | `chainLength` int 0–40 | `P = ⌈65535 / (8200 − 200·chain)⌉ / 65536`; chain 0 ≈ 1/8192, chain 40 ≈ **1/200**; **charm ignored** | 120 s (≈30 s/patch ÷ ~5% chain-40 hold rate) |
| `oras_dexnav` | 2 | `searchLevel` int; `dexnavChain` int (0/50/100) | composite: search-level direct term + small PID fallback; charm feeds iteration count `n` | 45 s |

Breakpoint detail:

- **SV outbreak rolls:** 0–29 → +0, 30–59 → +1, 60+ → +2. **Sparkling Power:**
  Lv1/2/3 → +1/+2/+3. The famous **1/512** = base(1) + outbreak60(+2) +
  sandwichLv3(+3) + charm(+2) = R8.
- **SwSh Brilliant:** KO 0–49 → +0, 50–99 → +1, 100–199 → +2, 200–299 → +3,
  300–499 → +4, 500+ → +5. (Per-species "caught or battled" count.)
- **SOS:** 0–10 → +0, 11–20 → +1, 21–30 → +2, 31+ → +3 (cap).
- **Radar** breaks the rolls model entirely — direct per-patch probability, no
  charm effect, no stacking. Note the ~5% chain-40 *hold* rate is what the
  inflated `avg_time` (~120 s) accounts for, not the headline odds — this keeps
  Radar's optimistic 1/200 from unfairly winning route ranking.
- **DexNav** breaks the rolls model — a search-level-driven direct term plus a PID
  fallback; charm feeds the iteration count multiplicatively. If the full
  composite proves fiddly, a `searchLevel → approxOdds` lookup table is an
  acceptable implementation of the same `formula_type`.

## Backend changes

- **Fix the gate (`internal/api/hunts.go:154`):** remove the
  `huntParameters = json.RawMessage('{}')` override for curated hunts. Instead,
  **validate** the incoming `hunt_parameters` against the method's schema — clamp
  to range / snap to breakpoints, reject clearly out-of-range input as `400`.
  This bug currently wipes any params on curated hunts and gates the whole feature.
- **Engine:** add `calc.EffectiveOdds(formulaType string, params, base OddsConfig, hasCharm bool) (denominator int, prob float64)`.
  `routes.go::computeRoute` calls it instead of the inline `base_odds / total_rolls`.
  `CalculateEstimatedTimeHours` is rephrased in terms of `prob` and `avg_time`.
- **Route ranking (pre-hunt):** the dex/route drawer ranks routes before a hunt
  exists, so it uses each method's **default "best realistic" params** from the
  registry to show achievable odds. Realism stays honest via `avg_time`.
- **Schema endpoint:** the method list and `GET /api/pokemon/{id}/route` responses
  gain a `params_schema` so the frontend form is data-driven. (`formula_type` is
  already returned.)

## Frontend changes

- **`<MethodParamsForm schema value onChange>`** — one generic component rendering
  number inputs / selects / steppers from `params_schema`, with breakpoint hints
  ("next boost at 60").
- **NewHuntModal** — when the chosen method has a non-empty schema, show the form
  plus a **live odds/ETA preview** that recomputes as params change.
- **Active hunt (Dashboard)** — an editable params section; on change → `PATCH`
  `hunt_parameters` → odds display updates (steady-state, editable-later model).
- **RouteList** already renders `odds` / `eta_hours`; it just reflects the new
  numbers.

## Seeding

Upsert the five methods as `hunt_methods` rows with the correct `formula_type`,
realistic `avg_time`, and `method_games` mappings to the right titles
(SV→SV, SwSh→SwSh, SOS→Gen 7 SM/USUM, Radar→Gen 4 HGSS/Pt + Gen 6 XY,
DexNav→ORAS). Idempotent `ON CONFLICT` upsert. Respect the seed-order rule:
`cmd/seed` runs **last** (it rebuilds the method tables).

## Error handling & edge cases

- Unknown `formula_type` → fall back to `static` (never 500).
- Missing / invalid params → registry defaults, or clamp to range.
- Direct-probability `P` clamped to ≤ 1; displayed denominator floored to ≥ 1
  (matches the current `1 / N` display contract).
- A method with an empty schema behaves exactly as today (`static`).

## Testing

Table-driven tests in `internal/calc` (the package already has `routes_test.go`):

- `sv_outbreak_sandwich`: R8 stack → ~512; Sandwich Lv3 alone → ~1024;
  outbreak 60 alone → ~1366.
- `swsh_brilliant`: KO 500 + charm → ~512.
- `gen7_sos`: chain 31 + charm → ~683; chain 0 → full odds.
- `radar_chain`: chain 0 → ~8192; chain 40 → ~200; charm makes no difference.
- `oras_dexnav`: low vs high search level produce increasing odds.
- Handler test: `hunt_parameters` now round-trips on a **curated** hunt
  (regression guard for the hunts.go:154 fix).

## Out of scope / explicit next step

- **Method eligibility data (the next task):** *which* Pokémon are huntable via
  each method, per game, must be researched and seeded **after** this engine
  lands — e.g. SOS-only species, Radar-incompatible species, which species can
  appear in SV/SwSh outbreaks, ORAS DexNav availability. This is a **web-sourced
  data-population pass** (Bulbapedia/Serebii per-method species lists) feeding
  `method_availability` / `method_exceptions`, and is tracked separately from this
  odds-engine work.
- **Live per-encounter chain counter** on the dashboard (we chose steady-state
  config instead).
- **Forms/regional variants** as method targets (the 1025-species cap, see #3).

## Sources

- VGC — SV mass outbreaks & shiny odds
- ScreenRant — SV shiny rates by method
- GameFAQs — SV sandwich + outbreak stacking
- RotomLabs — SwSh shiny rates
- Bulbapedia — Brilliant Pokémon (KO rolls)
- Player.One — SOS chaining rates
- Bulbapedia — Poké Radar
- mrnbayoh — ORAS DexNav shiny probability analysis
