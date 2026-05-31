# Scarlet/Violet Wild/Overworld Eligibility — Design

**Date:** 2026-05-31
**Branch:** `gen89-overworld-eligibility` (stacked on `dynamax-adventures-eligibility`)
**Backlog item:** Method eligibility data pass — **Slice A, game 1 of 3 (Scarlet/Violet)**
**Status:** approved design, pending implementation plan

## Problem

Scarlet/Violet has **zero** wild encounter rows (PokeAPI provides no Gen 9 encounter
data), so the three SV wild-kind methods — Random Encounter, Sandwich Hunting, and the
Mass Outbreak methods (`outbreak_defeats_sv`) — attach to **0** species in
`method_availability`. Audit Section A shows **412** SV species "available but no
method." The modern-method odds engine shipped earlier has nothing to rank for SV.

This slice makes SV overworld-spawnable species huntable via those wild methods by
seeding curated `wild` encounter rows for SV, sourced from the SV regional dex. It is
**data + a small method-catalog change**; no schema/DDL.

## Decisions (locked during brainstorming)

- **One game per slice.** This spec covers **Scarlet/Violet** only. Sword/Shield and
  Legends: Arceus are separate specs.
- **Reuse `kind = 'wild'`.** SV overworld spawns are wild encounters; the three SV
  methods already declare `requires_kind = wild`. No new encounter `kind`, no DDL.
- **Collapse the three area-outbreak methods into one.** Paldea/Kitakami/Terarium
  Mass Outbreak (all `outbreak_defeats_sv`) become a single "Mass Outbreak" method for
  SV. Area doesn't affect shiny odds or dex completion; this also prevents three
  duplicate same-odds outbreak routes per species.
- **Source = SV regional-dex membership (proxy).** Paldea + Kitakami + Blueberry dex
  IDs, web-sourced, treated as "wild-available." ~90% accurate; evolve-only
  over-attachments are accepted now and trimmed later with `method_exceptions`.
- **Exclude legendaries/mythicals** from the wild source — in SV they are
  static/shiny-locked encounters, not wild spawns.

## Architecture & data flow

1. **New seed file** `backend/seeds/overworld_species.json`, **game-keyed** so the
   SwSh and LA slices can reuse the same loader later:
   ```json
   { "Scarlet/Violet": [906, 909, 915, 921, ...] }
   ```
   Values are National-Dex IDs from the three SV regional dexes, with
   legendaries/mythicals omitted.

2. **New seed step** in `cmd/seed` (after the curated static/raid step, before
   `computeAvailability` / `reconcileAvailability`): for each game key, resolve the
   game ID, then insert `wild` rows guarded against legendaries:
   ```sql
   INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
   SELECT p.id, $gameID, 'wild', 'none'
   FROM pokemon p
   WHERE p.id = ANY($ids) AND NOT (p.is_legendary OR p.is_mythical)
   ON CONFLICT DO NOTHING
   ```
   (`pokemon.is_legendary` / `is_mythical` already exist — used by the seed's
   legendary wild-purge.)

3. **Existing derivation unchanged.** `computeAvailability` joins these new `wild`
   rows against the SV wild methods (Random Encounter, Sandwich Hunting, Mass
   Outbreak) via `method_games`, attaching all three to each seeded species.
   `reconcileAvailability` ensures `pokemon_availability` backing (these are already
   listed available in SV, so likely a no-op).

4. **Method-catalog change** in `backend/seeds/hunt_methods.json`: remove the
   Paldea/Kitakami/Terarium Mass Outbreak entries; add one "Mass Outbreak" entry
   (`requires_kind: wild`, `formula_type: outbreak_defeats_sv`, `avg_time_seconds`
   carried over, mapped to Scarlet/Violet). Random Encounter and Sandwich Hunting are
   unchanged. `HuntParametersEditor` keys on `formula_type`, so the params UI is
   unaffected.

## Seed-order placement

The new step runs inside the existing `cmd/seed` flow (which already truncates and
rebuilds the method tables). It must run **before** `computeAvailability` so the wild
rows are visible to the derivation, and after the legendary wild-purge so the purge
can't remove curated rows (the legendary guard in the insert makes ordering moot for
legendaries, but the dependency on `computeAvailability` is real). Respects the
"`cmd/seed` runs last" operational rule.

## Error handling / edge cases

- **Unknown game title** in `overworld_species.json` → log a warning and skip that
  key (matches the existing seeder's tolerance for unrecognized titles).
- **Legendary/mythical in the list** → filtered by the `NOT (is_legendary OR
  is_mythical)` guard; it can never create a wild row.
- **Dex IDs not in `pokemon`** (forms, IDs > 1025) → the `p.id = ANY(...)` join drops
  them silently.
- **Re-runnable:** `ON CONFLICT DO NOTHING` keeps the step idempotent across re-seeds.

## Validation & testing

Data change — no Go unit test. Validation:

1. **JSON well-formed:** `jq . backend/seeds/overworld_species.json` exits 0; the
   Scarlet/Violet array length matches the curated count.
2. **Seed runs clean:** `go run ./cmd/seed/main.go` completes; no
   `unknown game-group alias` / invalid-kind fatals; invariant checks pass; the
   "Mass Outbreak" collapse leaves exactly one SV `outbreak_defeats_sv` method.
3. **Coverage assertions (post-seed):**
   - SV `method_availability` rows for Random Encounter, Sandwich Hunting, and Mass
     Outbreak each ≈ the seeded-species count (was 0).
   - Audit Section A "Scarlet/Violet … missing" drops sharply from 412 (residual =
     evolve-only/legendary species with no wild row, which is expected).
   - Audit Sections B and C remain clean (no new inconsistencies; orphans = 0).
   - Spot-check a known wild species (Lechonk #915) shows Random Encounter, Sandwich
     Hunting, and Mass Outbreak in SV via `GET /api/pokemon/915/route`.
4. **No duplicate outbreak routes:** a SV species returns one Mass Outbreak route, not
   three.

## Risks

- **Dex-list accuracy.** The regional-dex proxy over-attaches wild methods to
  evolve-only species (e.g., species in the dex obtained only by evolving). Accepted
  for this pass; a follow-up `method_exceptions` exclude list can trim them. Under-
  attachment (a wild species missing from the sourced list) is the more visible miss —
  the list should err toward completeness of the three dexes.
- **Method-collapse and existing hunts.** `cmd/seed` already rebuilds `hunt_methods`
  from scratch each run (SERIAL IDs regenerate), so removing two method rows is
  consistent with existing behavior; this slice introduces no new instability there.

## Out of scope

- **Sword/Shield** and **Legends: Arceus** overworld eligibility (slice A, games 2–3).
- **Per-area outbreak granularity** (Paldea/Kitakami/Terarium) — deliberately collapsed.
- **DLC-ownership gating** (Teal Mask / Indigo Disk) — no schema field exists.
- **Fully-accurate wild curation** — this is the dex-membership proxy; per-species
  wild verification and `method_exceptions` trimming are a later refinement.

## Sources

SV regional dex lists (Paldea / Kitakami / Blueberry) to be web-sourced during
implementation from Bulbapedia/Serebii; legendary/mythical flags from the existing
`pokemon` table. Outbreak/sandwich odds already modeled by `outbreak_defeats_sv` /
`sandwich_power_sv` (shipped 2026-05-31).
