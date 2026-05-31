# ORAS Fishing Eligibility — Design

**Date:** 2026-05-31
**Branch:** `oras-fishing-eligibility` (off `master`)
**Backlog item:** Method eligibility — **Slice C (ORAS fishing terrain gap)**
**Status:** approved design, pending implementation plan

> Slice B (Poké Radar over-broad) was **investigated and dropped**: the
> shiny-hunt-expert confirmed Poké Radar draws from the full route grass table, so
> attaching it to all grass species is correct — an exclude list would remove
> legitimately chainable swarm/Trophy-Garden species and degrade accuracy. No work.

## Problem

Omega Ruby/Alpha Sapphire has **zero** `terrain='fishing'` wild encounter rows (PokeAPI
provides ORAS grass/other terrain but no fishing classification). Consequences:

1. **Chain Fishing** (`chain_fishing_gen6`, `requires_kind=wild`,
   `requires_terrain=fishing`, mapped to X/Y **and ORAS**) attaches to **0** ORAS
   species, despite ORAS being fishable.
2. **DexNav** (`dexnav_gen6`, `requires_kind=wild`, terrain-any, ORAS-only) misses the
   ~39 fishing-only species that have no wild row at all.

This slice seeds curated `terrain='fishing'` wild rows for ORAS's rod roster, fixing
both. ORAS already has grass/other wild data, so this is purely the fishing gap.

## Decisions (locked during brainstorming)

- **New curated source + seed step**, mirroring the SV `seedOverworldSpecies` pattern:
  `seeds/fishing_species.json` (game-keyed) + a `seedFishingSpecies` step that inserts
  `kind='wild', terrain='fishing'` (legendary-guarded). Does **not** refactor the
  existing `seedOverworldSpecies` (which seeds `terrain='none'`).
- **Game-keyed file** so other games' fishing rosters can be added later without new code.
- **No DDL.** Reuses `kind='wild'` + the existing `terrain` column and derivation.
- **ORAS only this slice.** X/Y already has 39 fishing rows from PokeAPI; other games
  out of scope.

## Architecture & data flow

1. **New seed file** `backend/seeds/fishing_species.json`:
   ```json
   { "Omega Ruby/Alpha Sapphire": [60, 129, 320, ...] }
   ```
   National-Dex IDs of species catchable via Old/Good/Super Rod anywhere in ORAS.

2. **New seed step** `seedFishingSpecies(ctx)` in `cmd/seed`, placed immediately after
   `seedOverworldSpecies(ctx)` (before `reconcileAvailability`). Identical to
   `seedOverworldSpecies` except the inserted `terrain` is `'fishing'`:
   ```sql
   INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
   SELECT p.id, $1, 'wild', 'fishing'
   FROM pokemon p
   WHERE p.id = ANY($2::int[]) AND NOT (p.is_legendary OR p.is_mythical)
   ON CONFLICT DO NOTHING
   ```

3. **Existing derivation** attaches Chain Fishing (matches `terrain='fishing'`) and
   DexNav (terrain-any) to these species; `reconcileAvailability` backs availability
   (most are already available in ORAS via grass/surf, so largely a no-op).

## The data

ORAS rod roster (Old/Good/Super Rod, all routes/areas), web-sourced National-Dex IDs
(~20–30). Expected members include: Magikarp/Gyarados (129/130), Tentacool/Tentacruel
(72/73), Wailmer/Wailord (320/321), Carvanha/Sharpedo (318/319), Luvdisc (370),
Corsola (222), Chinchou/Lanturn (170/171), Clamperl line (366), Relicanth (369),
Barboach/Whiscash (339/340), Goldeen/Seaking (118/119), Horsea/Seadra/Kingdra
(116/117), Staryu/Starmie (120/121), Remoraid/Octillery (223/224), Feebas (349),
Basculin if present. Final list verified during implementation; **user reviews before
seeding**. Legendaries (none are fished in ORAS) are guarded out regardless.

## Validation & testing

Data + tiny code. Validation:
1. `jq` valid; the ORAS array unique, in-range 1–1025, ~20–30 IDs.
2. `go build ./... && go vet ./cmd/seed/` clean (new function compiles).
3. Post-seed: ORAS `chain_fishing_gen6` `method_availability` rows = roster count (was
   **0**); `dexnav_gen6` ORAS coverage rises from 108; audit Section A ORAS drops from
   **36**; Sections B/C clean.
4. Spot-check: Magikarp #129 shows **Chain Fishing + DexNav** in ORAS via
   `GET /api/pokemon/129/route`.

## Risks

- Roster accuracy: small, well-documented list; under-inclusion (missing a fished
  species) is the main risk — err toward completeness across all rods/routes.
- A fished species that also has a grass/surf ORAS row already has DexNav; adding the
  fishing row additionally grants Chain Fishing (different terrain → no conflict).

## Out of scope

- X/Y and other-game fishing rosters (X/Y already covered by PokeAPI).
- Surf-terrain gaps; non-fishing ORAS coverage.
- DexNav/Chain-Fishing odds modeling (already handled by their formulas).

## Sources

ORAS fishing roster web-sourced during implementation (Bulbapedia/Serebii ORAS route
fishing tables). Legendary flags from the `pokemon` table.
