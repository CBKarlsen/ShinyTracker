# Sword/Shield + Legends: Arceus Overworld Eligibility — Design

**Date:** 2026-05-31
**Branch:** `gen89-overworld-eligibility`
**Backlog item:** Method eligibility — **Slice A, games 2 & 3 (Sword/Shield, Legends: Arceus)**
**Status:** approved design, pending implementation plan

## Problem

Like Scarlet/Violet, **Sword/Shield** and **Legends: Arceus** have zero PokeAPI wild
encounter rows, so their wild-kind methods attach to **0** species (audit Section A:
SwSh **133** missing, LA **213** missing). This applies the SV mechanism to both games.

## Approach (identical to the shipped SV slice)

Reuse the game-keyed `backend/seeds/overworld_species.json` and the existing
`seedOverworldSpecies` step (shipped in the SV slice). Add two new game keys; the
loader inserts `kind='wild'` rows (guarded against legendaries/mythicals); the existing
derivation attaches each game's wild methods; `reconcileAvailability` backs
`pokemon_availability`. **No code or schema changes** — data only. See
`docs/superpowers/specs/2026-05-31-sv-overworld-eligibility-design.md` for the mechanism.

## Per-game detail

### Sword/Shield
- **Wild methods attached:** **KO Method** and **Run Away** (both `requires_kind=wild`,
  `formula_type=static`). Breedable species also keep Masuda (egg) as today.
- **Source:** the **Galar regional dex** — base Galar Pokédex + Isle of Armor +
  Crown Tundra dexes, unioned to unique National-Dex numbers (~400).
- **Exclusions:** legendaries/mythicals. The 38 Dynamax Adventure legendaries are
  already handled as `raid` (slice D) and must NOT also get wild rows; the box legends
  Zacian/Zamazenta/Eternatus and DLC statics (Kubfu, Calyrex, Glastrier, Spectrier,
  Regis, Galarian birds, Keldeo, Cosmog) are static/shiny-locked, not wild. The
  seed-time `NOT (is_legendary OR is_mythical)` guard is the backstop.

### Legends: Arceus
- **Wild method attached:** **Mass Outbreak** (`requires_kind=wild`,
  `formula_type=static`). Note LA's outbreak odds are *not* modeled (catalogued as
  static/full-odds) — this pass is **eligibility only**, consistent with prior slices.
- **Source:** the **Hisui Pokédex** (~242), unioned to unique National-Dex numbers.
- **Exclusions:** the Hisui static/legendary set — Arceus, the Lake trio, Origin
  Dialga/Palkia, Heatran/Cresselia/Regigigas, the noble Pokémon and Legendary/Mythical
  encounters that are scripted statics, not wild spawns. Guard backstops as above.

## Data sourcing

Web-source both regional dexes (Bulbapedia "List of Pokémon by Galar / Isle of Armor /
Crown Tundra Pokédex number" and "…Hisui Pokédex number", or the matching PokeAPI
pokédex endpoints `galar`/`isle-of-armor`/`crown-tundra`/`hisui`). Emit National-Dex
numbers, union + de-dupe per game, omit legendaries/mythicals. **User reviews both
lists before seeding.**

## Validation & testing

Per game, post-seed:
- SwSh `method_availability` for KO Method and Run Away each ≈ the seeded SwSh count
  (was 0); LA Mass Outbreak ≈ seeded LA count (was 0).
- Audit Section A: SwSh "missing" drops from 133; LA from 213 (residual =
  evolve-only/legendary species without a wild row — expected).
- Audit Sections B and C remain clean.
- Spot-check: a known SwSh wild species (e.g. Wooloo #831) shows KO Method + Run Away;
  a known Hisui wild species (e.g. Bidoof #399) shows Mass Outbreak in LA.

## Risks

- **Dex-membership proxy** over-attaches to evolve-only species (accepted; trimmable
  later via `method_exceptions`). Under-attachment (a wild species missing from a list)
  is the more visible miss — lists should err toward dex completeness.
- **DA-legend double-attachment in SwSh:** prevented by the legendary guard (the 38 DA
  bosses are `is_legendary`, so they can never get a curated wild row even if a dex list
  includes them).

## Out of scope

- Method eligibility slices **B** (Poké Radar over-broad) and **C** (ORAS fishing).
- LA's distinct outbreak/mass-outbreak odds modeling, BDSP, DLC-ownership gating.
- The 9 DA Ultra Beasts; home-game statics for the 24 DA legends.

## Sources

Galar (base + Isle of Armor + Crown Tundra) and Hisui regional dexes, web-sourced
during implementation; legendary/mythical flags from the existing `pokemon` table.
