# Live chain tracking + Break-chain for streak methods

**Date:** 2026-06-02
**Status:** Approved (design)
**Scope:** `frontend/src` only — no backend, schema, or endpoint changes.

## Problem

Streak-based hunting methods (chain fishing, catch combos, SOS chains, Poké
Radar, DexNav) build a *consecutive chain* that raises shiny odds and **resets
to zero when broken**. In ShinyTracker today the odds for these methods are
derived directly from a hunt's lifetime `encounter_count`, so the current chain
and the lifetime total are the same number. When a player breaks a chain in the
game, there is no way to reset the odds while keeping the encounter total they
have invested.

Concretely: `chain_fishing_gen6` and `catch_combo_lgpe` read their chain length
straight from the live encounter counter; `radar_chain_gen4`, `sos_chain_gen7`,
and `dexnav_gen6` already read an optional `hunt_parameters.chain_length`, but it
is set once at hunt start and never tracked live.

## Goal

Give every streak method a **current chain** that is distinct from the
**lifetime encounter total**:

- `+1` advances both the encounter total and the current chain.
- A **Break chain** action resets the current chain to 0 while preserving the
  encounter total.
- Odds follow the current chain.

## Approach (chosen)

Frontend-driven, with the chain stored in the existing `hunt_parameters`
(JSONB) `chain_length` field. This reuses machinery that already exists:

- `PATCH /api/hunts/:id` (`UpdateHuntHandler`) already persists
  `hunt_parameters`.
- Three of the five streak formulas already read `huntParams.chain_length`.

No schema migration, no new endpoints, no backend deploy.

### Rejected alternative

A dedicated `chain_count` column on `user_hunts` plus `/hunts/:id/chain`
increment/break endpoints. Cleaner typed model and server-side atomic
increments, but requires a schema migration and backend work, and duplicates an
increment path that already flows through PATCH. Overkill for a single-user app.

## Data model

The current chain lives in `hunt_parameters.chain_length` (integer). No new
columns or tables. Legacy hunts with no `chain_length` key continue to work via
the encounters fallback (below) until their first `+1` or Break under the new
behavior populates the field.

## Streak-method definition

Introduce a single source of truth for "this method has a breakable chain":

```
STREAK_FORMULAS = [
  "chain_fishing_gen6",
  "catch_combo_lgpe",
  "sos_chain_gen7",
  "radar_chain_gen4",
  "dexnav_gen6",
]
isStreakMethod(formulaType): boolean
```

Lives alongside the existing `PARAM_FORMULAS` / `routeNeedsParams` in
`frontend/src/utils/odds.ts`. Used by both the odds calc and the UI to decide
whether to track a chain and render the chain controls.

## Odds calculation — `frontend/src/utils/odds.ts`

Make the two outliers read the chain from params with an encounters fallback, so
all five streak formulas behave identically:

- `chain_fishing_gen6`:
  `chain = max(0, min(huntParams.chain_length ?? encounters, 20))`
- `catch_combo_lgpe`:
  `combo = max(0, huntParams.chain_length ?? encounters)`

The `?? encounters` fallback is required: it keeps odds correct for legacy hunts
created before this feature (which have no `chain_length` key). Do **not** seed a
numeric `chain_length: 0` default for these methods in `defaultParamsFor` — an
explicit 0 would disable the fallback and pin legacy hunts at base odds. (This
matches the existing comment in `defaultParamsFor`.)

The Go engine `calc/methods.go` is **not** changed. It reads these counts from a
`"count"` param supplied by `DefaultParams` for route ranking only; its
divergence from the live-display path is already documented there and remains
acceptable.

## Increment & Break — data flow

Both actions apply **only** when `isStreakMethod(hunt.formula_type)` is true.
Non-streak hunts keep their exact current behavior.

Both must PATCH **full hunt state** — `encounter_count` + `status` +
`hunt_parameters` together — following the existing `HeroHunt.handleSaveParams`
pattern. This avoids a latent footgun: `UpdateHuntHandler` unconditionally writes
all three columns from the request body, so a partial PATCH (e.g. the bare
`updateEncounterCount` / `updateHuntParameters` helpers in `useHunts.ts`, which
send only one field) can zero `encounter_count` or `status`. The implementer
should route the new increment/break through a full-state PATCH and should not
reuse the partial helpers for streak hunts.

- **+1 (streak hunt):** `encounter_count += 1` **and**
  `hunt_parameters.chain_length = (current chain) + 1`, in one full-state PATCH.
  May remain debounced like today, as long as the flushed payload carries the
  updated `chain_length`.
- **Break chain:** `hunt_parameters.chain_length = 0`, `encounter_count`
  unchanged, `status` unchanged. Full-state PATCH, flushed immediately (not
  debounced) so the reset is never lost.

"Current chain" for the increment = `huntParams.chain_length ?? encounter_count`
(the same fallback used by the odds calc), so the first `+1`/Break on a legacy
hunt continues from its effective chain rather than jumping.

## UI

For streak hunts only:

- **`HeroHunt.tsx`** (big active-hunt card): show the current chain alongside the
  lifetime total (e.g. `Chain 7 · 1,204 total`), and a **Break chain** button
  near the `+1` control.
- **`HuntRow.tsx`** (compact list row): show the current chain next to the
  encounter total for consistency.

Non-streak hunts render exactly as today (no chain readout, no Break button).

## Cumulative odds — accepted approximation

The per-encounter "current odds" (`expected` denominator) stays exact: it is
driven by the current chain.

The cumulative-probability loops (in `HeroHunt.tsx` and `calcCumulativeOdds`)
iterate over the lifetime encounter total and apply the resolved
`hunt_parameters` — which now carry a single `chain_length` — to every past
encounter. After a chain has been broken, this treats all past encounters as if
at the current chain, making the cumulative curve an approximation rather than an
exact account of the broken history.

This is accepted. Exact cumulative odds would require storing per-encounter chain
history, which is out of scope (YAGNI).

## Out of scope

- No backend, schema, or migration changes.
- No new endpoints.
- No change to the Go route-ranking engine (`calc/methods.go`).
- No per-encounter chain-history storage; cumulative odds remain an
  approximation after a break.
- No change to non-streak methods.

## Resolving the current Dratini hunt

No manual database edit. Once shipped, open the Dratini (Pokémon Y, chain
fishing) hunt and click **Break chain**: `chain_length` resets to 0, the lifetime
encounter total is preserved, and the displayed odds drop back to base.
