# Dynamax Adventures Eligibility — Design

**Date:** 2026-05-31
**Branch:** `hunt-method-corrections`
**Backlog item:** Method eligibility data pass — **Slice D (Dynamax Adventures)**
**Status:** approved design, pending implementation plan

## Problem

`dynamax_adventures_gen8` (the Max Lair method) is attached to only **14** species
in `method_availability` — the box legendaries already curated in
`backend/seeds/legendary_encounters.json`. In the real game, Dynamax Adventures in
Sword/Shield (Crown Tundra DLC) let you catch **38 cross-gen legendaries** as the
final boss, all at boosted shiny odds. The other 24 are missing, so the
method-aware odds engine (shipped 2026-05-31) has nothing to rank for them.

This slice adds DA raid eligibility for all 38 DA legendary bosses in Sword/Shield.
It is **data-only**: no code, no schema, no odds changes.

## Decisions (locked during brainstorming)

- **Legendary bosses only.** The 38 legendaries that appear as DA final bosses.
  The 9 Ultra Beasts that share the DA pool are **out of scope** (tracked follow-up).
- **No odds work.** DA shiny odds are a flat 1/300 (1/100 with Shiny Charm). The
  existing `dynamax_adventures_gen8` formula in `internal/calc` already returns
  exactly `charm ? 100 : 300`, so nothing in the odds engine changes.
- **DA-only entries for the 24 new species.** New `legendary_encounters.json`
  entries grant *only* the SwSh DA raid (`"default_games": []` +
  `"overrides": {"@swsh-dynamax": "raid"}`). This slice does **not** invent
  home-game static encounters for them — that is a separate, larger "legendary
  static coverage" slice.
- **No schema/DDL, no Go changes.** Purely `backend/seeds/legendary_encounters.json`
  plus a re-seed.

## Background: how this data flows

`cmd/seed` reads `legendary_encounters.json`. Each entry covers a game set =
`default_games` (assigned `default_kind`) plus the keys of `overrides` (each with
its own kind). Keys beginning with `@` are game-group aliases resolved by
`loadGameGroups()`; `@swsh-dynamax` expands to **Sword/Shield** with kind `raid`
(`seed/main.go` ~lines 276–296, 321–340). The curated `raid` row lands in
`pokemon_game_encounter`. `computeAvailability` then attaches the
`dynamax_adventures_gen8` method (which has `requires_kind = raid` and is mapped to
Sword/Shield via `method_games`) to every species with a SwSh `raid` row. No
`method_exceptions` are needed.

## The data: 38 DA legendary bosses

National-Dex IDs (these key the JSON). **14 already present** with the
`@swsh-dynamax` override (no change): 144 Articuno, 145 Zapdos, 146 Moltres,
150 Mewtwo, 249 Lugia, 250 Ho-Oh, 382 Kyogre, 383 Groudon, 384 Rayquaza,
487 Giratina, 643 Reshiram, 644 Zekrom, 716 Xerneas, 717 Yveltal.

**24 to ADD** (DA-only entries):

| Dex | Name | | Dex | Name | | Dex | Name |
|-----|------|-|-----|------|-|-----|------|
| 243 | Raikou | | 484 | Palkia | | 718 | Zygarde |
| 244 | Entei | | 485 | Heatran | | 785 | Tapu Koko |
| 245 | Suicune | | 488 | Cresselia | | 786 | Tapu Lele |
| 380 | Latias | | 641 | Tornadus | | 787 | Tapu Bulu |
| 381 | Latios | | 642 | Thundurus | | 788 | Tapu Fini |
| 480 | Uxie | | 645 | Landorus | | 791 | Solgaleo |
| 481 | Mesprit | | 646 | Kyurem | | 792 | Lunala |
| 482 | Azelf | | | | | 800 | Necrozma |
| 483 | Dialga | | | | | | |

New-entry shape (example):

```json
{
  "pokemon_id": 243,
  "name": "Raikou",
  "default_kind": "raid",
  "default_games": [],
  "overrides": { "@swsh-dynamax": "raid" }
}
```

(`default_kind` is unused when `default_games` is empty; set to `"raid"` for
readability. The `@swsh-dynamax` override is what produces the SwSh raid row.)

Forms note: all bosses are base forms (Zygarde 50%, Giratina Altered,
Incarnate Tornadus/Thundurus/Landorus, base Kyurem, base Necrozma) — these are the
base species IDs already in the `pokemon` table, so no form handling is needed.

## Shiny-lock cross-check (must hold)

None of the 38 may be shiny-locked in Sword/Shield, or the route would be
suppressed. Verified against `backend/seeds/shiny_locks.json`: the only
`"Sword/Shield"` locks are Zacian, Zamazenta, Eternatus, Kubfu, Calyrex — none of
which is a DA boss. Several DA legends (e.g. 716, 785–788, 791, 792, 800, 483, 484,
487) appear in `shiny_locks.json` but only for their **home** games (X/Y, SM/USUM,
BDSP, etc.), which does not affect SwSh. The implementation must re-confirm no
`(da_legend_id, "Sword/Shield")` pair exists in `shiny_locks.json`.

## Re-seed procedure

The change is data-only but only takes effect after re-seeding the shared DB.
Per the seed-order rule, `cmd/seed` runs **last** (it rebuilds the method tables
from the JSON sources). For a routine data refresh of just this change:

```
cd backend && go run ./cmd/seed/main.go        # re-reads legendary_encounters.json
go run ./cmd/seed_shiny_locks/main.go          # locks (unchanged, safe to re-run)
```

## Validation & testing

No Go unit test (this is a data change). Validation steps:

1. **JSON well-formed:** `jq . backend/seeds/legendary_encounters.json` exits 0 and
   the entry count increased by 24 (to 38 entries carrying the `@swsh-dynamax`
   override).
2. **Seed runs clean:** `go run ./cmd/seed/main.go` completes with no
   `unknown game-group alias` / invalid-kind fatals and passes its existing
   invariant checks.
3. **Coverage assertion (post-seed):** the count of SwSh `method_availability` rows
   for the `dynamax_adventures_gen8` method equals **38**. Spot-check a previously
   missing legend (e.g. Necrozma #800) now has the DA route in SwSh.
4. **No regressions:** `go run ./cmd/audit_methods/main.go` Section B does not gain
   new inconsistencies attributable to these 38 (raid rows are backed by
   `pokemon_availability` for SwSh; if any of the 24 lack a SwSh availability row,
   that surfaces in Section B and must be reconciled — see Risks).

## Risks / edge cases

- **`pokemon_availability` backing.** `method_availability` rows should be backed by
  a `pokemon_availability` row for the same `(pokemon, game)` (audit Section B). If
  any of the 24 DA legends is not listed as available in Sword/Shield in
  `pokemon_availability`, the new raid row will flag in Section B. The
  implementation must check and, if needed, add the SwSh availability entries (the
  seed's `reconcileAvailability` may already back-fill availability from encounter
  rows — verify which, and rely on it rather than hand-adding if so).
- **Empty `default_games`.** Confirm the seed loader tolerates `"default_games": []`
  (iterates zero times, applies the override). If the loader rejects empty
  default_games, fall back to listing `"Sword/Shield"` directly with
  `"default_kind": "raid"` and no alias — functionally identical for this slice.

## Out of scope

- The **9 Ultra Beasts** in the DA pool (793–799, 805, 806) — follow-up slice.
- **Home-game static encounters** for the 24 (their pre-SwSh availability) —
  separate "legendary static coverage" slice.
- The **"native vs. requires-other-version-host"** nuance — a future
  `hunt_parameters` detail, not an availability gate (all 38 are obtainable in both
  versions via hosting).
- **DLC-ownership gating** of the DA method (no schema field exists).
- Method eligibility slices **A** (Gen 8/9 overworld spawns), **B** (Poké Radar
  over-broad), **C** (ORAS fishing) — separate specs.

## Sources

DA boss list + shiny-lock status from the `shiny-hunt-expert` (Game8, RotomLabs,
Serebii, Dexerto, pokemon.com). 38 legendaries; none shiny-locked in DA; flat
1/300 → 1/100-with-charm odds.
