# Modern Method Odds — Design (v2)

**Date:** 2026-05-31
**Branch:** `worktree-dex-completion-engine` (based on `hunt-method-corrections`)
**Backlog item:** TASKS.md #4 — Modern method odds
**Status:** approved design, pending implementation plan

> **v2 note:** the original v1 of this spec assumed the feature was greenfield.
> Reading the code showed a working **TypeScript odds engine already exists**
> (`frontend/src/utils/odds.ts`) and the dashboard already does live params +
> odds. This v2 corrects scope to match reality: **backend-only this pass** —
> port the existing TS engine to Go so route ranking is method-aware, and fix
> the create-path param-persistence bug.

## Problem

Shiny odds are computed **client-side** by `calculateOdds()` in
`frontend/src/utils/odds.ts`, which already branches on `formula_type` and reads
`hunt_parameters`. The Go side does **not**: `internal/calc` computes a flat
`base_odds / total_rolls` and ignores `formula_type` entirely. Two concrete
consequences:

1. **Route ranking is wrong.** `GET /api/pokemon/{id}/route` (the dex blocked-state
   drawer and best-route list) ranks every method as flat full-odds, so an SV Mass
   Outbreak ranks identically to a random encounter. The "best route" is therefore
   not actually the best.
2. **Params don't persist on creation.** `CreateHuntHandler`
   (`internal/api/hunts.go:154`) hard-sets `hunt_parameters = '{}'` for curated
   hunts, discarding whatever the New Hunt modal's params editor sent. (Editing an
   existing hunt via `UpdateHuntHandler` already persists params correctly.)

This feature makes the **Go engine method-aware by porting the TS formulas**, wires
it into route ranking, and fixes the create-path persistence bug. The TS engine and
the frontend params editor are otherwise left as-is.

## Decisions (locked during brainstorming)

- **Backend-only this pass.** Port the formula logic to Go and integrate it into
  route ranking + fix param persistence. The existing frontend
  `HuntParametersEditor` and `utils/odds.ts` are **not** refactored now.
- **Go mirrors `utils/odds.ts` exactly.** The shipped TS numbers are the contract,
  so client (dashboard live odds) and server (route ranking) agree. We do **not**
  substitute the expert's idealized numbers, even where they differ.
- **Outbreak + sandwich stack.** Per the chosen modeling, `outbreak_defeats_sv` is
  extended to also read `sparkling_power` (additive rolls) so the headline
  outbreak+sandwich stack is representable in one hunt. Because this is backend-only,
  the **Go** formula gains the `sparkling_power` term now; syncing the same term into
  `utils/odds.ts` (and surfacing the field in the outbreak editor) is a tracked
  frontend follow-up.
- **Coverage:** all **8** dynamic `formula_type`s already present in the seed (see
  table), not the 5 from v1.
- **Parameter lifecycle:** steady-state config; one odds/ETA per hunt. Editing
  already works via `UpdateHuntHandler`.
- **ETA realism:** route ranking uses each method's **default "best realistic"
  params** (registry constant) so the ranked odds reflect the method's achievable
  potential; per-method `avg_time` (already in the seed) keeps ETA honest.
- **No new DDL.** `hunt_methods.formula_type` and `user_hunts.hunt_parameters`
  already exist and are already seeded.

## Architecture

Add a method-aware odds function to `internal/calc` that mirrors
`calculateOdds()` in `utils/odds.ts`:

```
calc.EffectiveOdds(formulaType string, params map[string]any, base OddsConfig, hasCharm bool)
    -> (denominator int)
```

It branches on `formulaType` exactly as the TS does, reading the same param keys
(`chain_length`, `defeated_count`, `sparkling_power`, `search_level`). `computeRoute`
in `routes.go` calls it (passing each formula's **default best params**) instead of
the inline `base_odds / total_rolls`. The `static` path is unchanged, so existing
behaviour and the existing `routes_test.go` assertions still hold.

A small companion `calc.DefaultParams(formulaType) map[string]any` supplies the
ranking defaults (the achievable-best config per method).

## The registry — canonical formulas (mirror of `utils/odds.ts`)

`baseOdds` is the game's denominator (`4096` modern). Param keys match the TS engine
and the existing `HuntParametersEditor`. **These are the shipped TS numbers, which
are the contract** — note several differ from textbook/expert values.

| `formula_type` | Param(s) | Rolls / denominator (exactly as TS) | Ranking default |
|---|---|---|---|
| `static` | none | `rolls = base_rolls + (charm?charm_rolls:0)`; `den = ⌊base/rolls⌋` | — |
| `outbreak_defeats_sv` | `defeated_count`; **+`sparkling_power` (new)** | extra = (defeats≥60→2, ≥30→1) **+ (power 1/2/3→1/2/3)**; `rolls = base_rolls+extra+charm`; `den=⌊base/rolls⌋` | defeats 60, power 3 |
| `sandwich_power_sv` | `sparkling_power` 0–3 | extra = power(1/2/3→1/2/3); `den=⌊base/rolls⌋` | power 3 |
| `sos_chain_gen7` | `chain_length` (mod 255) | extra = (≥31→12, ≥21→8, ≥11→4); `den=⌊base/rolls⌋` | chain 31 |
| `radar_chain_gen4` | `chain_length` 0–40 | `den = max(99, round(65536 − 1635.925·chain))`; `rolls=1`; **charm ignored** | chain 40 |
| `dexnav_gen6` | `search_level`, `chain_length` | composite (search-level term `t/10000` + standard rolls term); `den = round(1/totalProb)`; see TS lines 73–94 | search 200, chain 100 |
| `catch_combo_lgpe` | `chain_length`* | extra = (≥31→11, ≥21→7, ≥11→3); `den=⌊base/rolls⌋` | combo 31 |
| `chain_fishing_gen6` | `chain_length`* | extra = `min(chain,20)·2`; `den=⌊base/rolls⌋` | chain 20 |
| `dynamax_adventures_gen8` | none | `den = charm ? 100 : 300`; `rolls=1` | — |

\* `catch_combo_lgpe` and `chain_fishing_gen6` currently read the live `encounters`
count in TS, not a named param. For **ranking** we feed the default via the same
chain param; the Go port must accept an explicit count so ranking is deterministic
(documented in the plan).

## Backend changes

- **Port the engine:** new `calc.EffectiveOdds` + `calc.DefaultParams` in a new file
  `internal/calc/methods.go`, mirroring `utils/odds.ts` branch-for-branch. Table tests
  assert parity with the TS numbers.
- **Wire ranking:** `routes.go::computeRoute` calls `EffectiveOdds(c.FormulaType,
  DefaultParams(c.FormulaType), …)` for the `Odds`/`ETAHours` it returns. Static path
  unchanged. `MethodCandidate.FormulaType` already exists and is already populated by
  `dex.go::fetchMethodCandidates`.
- **Fix persistence (`hunts.go:154`):** delete the
  `huntParameters = json.RawMessage('{}')` override in the curated branch so the
  decoded `req.HuntParameters` (already handled at lines 125–129) is the value
  inserted. Add a minimal guard: if the body's params aren't a JSON object, fall back
  to `{}` (never 500).
- **Stacking term:** the Go `outbreak_defeats_sv` branch adds the `sparkling_power`
  extra rolls (TS does not yet — tracked follow-up).

## Frontend changes

**None this pass.** `utils/odds.ts`, `HuntParametersEditor`, `MethodPreview`,
`HeroHunt`, and `OddsCurve` already render params and live odds client-side. Once
`hunts.go:154` is fixed, curated-hunt params persist and the existing editor stops
being cosmetic on reload.

## Seeding

**No seed changes required** — all 8 `formula_type`s and their `avg_time`/games are
already in `seeds/hunt_methods.json`. (If the audit later shows a method tagged
`static` that should be dynamic, that's a data fix, out of scope here.)

## Error handling & edge cases

- Unknown `formula_type` → `static` fallback (matches TS `type || "static"`; never 500).
- Missing/invalid params → the Go branches clamp/default exactly as TS
  (`Math.max(0, …)`, `Math.min(…, cap)`).
- Denominator floored to ≥ 1 for display; `radar`/`dexnav`/`dynamax` set `rolls = 1`
  and compute the denominator directly, as TS does.

## Testing

Table-driven tests in `internal/calc/methods_test.go` (the package already runs under
`go test ./internal/calc/`), asserting **parity with `utils/odds.ts`** at sample
points:

- `static`: base 4096, rolls 1, charm 2 → 4096 (no charm) / 1365 (charm). (Existing.)
- `outbreak_defeats_sv`: defeats 60 + power 3 + charm(2) + base(1) → ⌊4096/8⌋ = 512.
- `sandwich_power_sv`: power 3, no charm → ⌊4096/4⌋ = 1024.
- `sos_chain_gen7`: chain 31, no charm → ⌊4096/13⌋ = 315.
- `radar_chain_gen4`: chain 40 → 99; chain 0 → 65536 (a latent quirk in the TS
  formula — mirrored for parity, flagged as a follow-up); charm makes no difference.
- `catch_combo_lgpe`: combo 31, no charm → ⌊4096/12⌋ = 341.
- `chain_fishing_gen6`: chain 20, no charm → ⌊4096/41⌋ = 99.
- `dynamax_adventures_gen8`: 300 (no charm) / 100 (charm).
- `dexnav_gen6`: search 200/chain 100 produces a denominator well below 4096.
- Ranking test: a candidate slice mixing `static` and `outbreak_defeats_sv` ranks the
  outbreak ahead via `EffectiveOdds`.
- Handler regression: `hunt_parameters` round-trips on a **curated** hunt create
  (guards the `hunts.go:154` fix).

(Exact expected integers are pinned in the plan after computing each against the TS
formula; any that differ from the above are corrected there.)

## Out of scope / explicit next steps

- **Method eligibility data (the next task):** *which* Pokémon are huntable via each
  method, per game — a **web-sourced data-population pass** (Bulbapedia/Serebii)
  feeding `method_availability` / `method_exceptions`. Tracked separately.
- **TS engine sync:** add the `sparkling_power` term to `outbreak_defeats_sv` in
  `utils/odds.ts` and surface the field in the outbreak editor, so client live-odds
  matches the Go ranking for stacked outbreak hunts.
- **A-vs-B form refactor:** optionally replace the bespoke `HuntParametersEditor` with
  a served-schema generic form later. Not now.
- **Live per-encounter chain counter**, **forms/regional variants** — unchanged from
  the dex-completion backlog.

## Sources

The Go port's contract is `frontend/src/utils/odds.ts`. Domain background (where it
agrees) from the `shiny-hunt-expert`: Bulbapedia (Brilliant Pokémon, Poké Radar),
Smogon/community SOS & sandwich-stacking references, mrnbayoh ORAS DexNav analysis.
