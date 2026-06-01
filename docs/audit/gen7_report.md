# Gen 7 Method Verification Report

**Scope:** Generation 7 — Sun/Moon (`game_id=11`), Ultra Sun/Ultra Moon (`game_id=12`), Let's Go Pikachu/Eevee (`game_id=13`). Read-only audit; no database writes performed.
**Date:** 2026-05-31
**Verified against:** Bulbapedia (primary), Serebii / PokémonDB (secondary).

---

## Summary

| Metric | Value |
|---|---|
| Rows audited (method_availability, Gen 7) | **698** (SM 236 / USUM 338 / LGPE 124) |
| Distinct Pokémon with method rows | SM 236 / USUM 338 / LGPE 124 |
| Method **mislabels** found | **0** ✅ |
| Cross-game method **misplacements** found | **0** ✅ |
| Shiny-lock conflicts (locked + huntable) | **0** ✅ |
| Masuda-on-non-breedable violations | **0** ✅ |
| **Coverage gaps** found | **4** (see below) |

**Bottom line: every assigned Gen 7 method row is correct.** All structural checks pass. The issues are four coverage gaps — missing methods and missing encounter data — not incorrect assignments.

### Method mix (stable snapshot)
| game | SOS Chaining | Catch Combo | Soft Reset | Random Encounter | Masuda Method |
|---|---|---|---|---|---|
| SM (11) | 236 | 0 | 0 | 0 | 0 |
| USUM (12) | 338 | 0 | 0 | 0 | 0 |
| LGPE (13) | 0 | 124 | 0 | 0 | 0 |

SOS Chaining correctly absent from LGPE. Catch Combo correctly absent from SM/USUM. ✓

---

## Schema reading (Phase 1)

Method assignment under audit lives in **`method_availability(id, pokemon_id, method_id, game_id)`**.

| Concept | Where it lives |
|---|---|
| Species | `pokemon(id, name, can_breed, is_legendary, is_mythical, evolves_from_id)` |
| Game / version | `games(id, title, generation, base_odds, supports_breeding)` |
| Method | `hunt_methods(id, method_name, base_rolls, charm_rolls, requires_kind, requires_terrain)` |
| Encounter type | `pokemon_game_encounter(pokemon_id, game_id, kind ∈ wild/static/egg, terrain)` |
| Shiny locks | `shiny_locks(pokemon_id, game_id)` |
| Method-to-game binding | `method_games(game_id, method_id)` |

Gen 7 method IDs verified:
- SM/USUM — SOS Chaining `168`, Soft Reset `178` (both in `method_games` for 11/12)
- LGPE — Catch Combo `174` (in `method_games` for 13)
- Random Encounter with `charm_rolls=2`: IDs `161` (Gen 9) and `166` (Gen 5 BW2); **no Gen 7-specific instance exists**
- Masuda Method: IDs `162` and `172` (both `base_rolls=6, charm_rolls=2, requires_kind=egg`); **neither mapped to games 11/12**
- Ultra Wormhole: **does not exist** in `hunt_methods` catalog

---

## Rules verified (once each, reused across rows)

| # | Rule | Verdict | Source |
|---|---|---|---|
| R1 | **SOS Chaining** requires `kind=wild`; only valid in SM/USUM | Confirmed — all 574 SOS rows have a wild encounter; none in LGPE | [Bulbapedia: SOS Battle](https://bulbapedia.bulbagarden.net/wiki/SOS_Battle) |
| R2 | **Catch Combo** requires `kind=wild`; only valid in LGPE; not SM/USUM | Confirmed — 124 Catch Combo rows, all wild, all in game 13 only | [Bulbapedia: Catch Combo](https://bulbapedia.bulbagarden.net/wiki/Catch_combo) |
| R3 | **Soft Reset** for static encounters; SM/USUM support it (`method_games` entry exists) | Confirmed in `method_games`; 0 rows generated because no static encounters seeded | [Bulbapedia: Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon) |
| R4 | **LGPE shiny locks**: Articuno(144), Zapdos(145), Moltres(146), Mewtwo(150) | Static encounters exist; zero method rows (correct); zero shiny_lock rows (gap — see Gap 4) | [Bulbapedia: LGPE Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon#Generation_VII) |
| R5 | **SM/USUM shiny locks**: Tapus(785–788), Cosmog(789), Solgaleo(791), Lunala(792) locked in SM; same + no Necrozma in USUM lock list | Confirmed present in `shiny_locks` for game 11; USUM lacks Necrozma (800) in lock list — correct, Necrozma is huntable via Ultra Wormhole in USUM | [Bulbapedia: List of unobtainable Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |
| R6 | **No Random Encounter** in LGPE (overworld spawns, not random encounters) | Confirmed — Random Encounter absent from `method_games` for game 13 and from `method_availability` | [Bulbapedia: LGPE](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon:_Let%27s_Go,_Pikachu!_and_Let%27s_Go,_Eevee!) |
| R7 | **No breeding** in LGPE (`supports_breeding=false`) | Confirmed in `games` table | Ibid. |

---

## Verification results

### Method mislabels / misplacements: none

All structural checks returned **zero** violations:
- SOS Chaining on Pokémon with no wild encounter — **0**
- SOS Chaining in LGPE (game 13) — **0**
- Catch Combo in SM/USUM (games 11/12) — **0**
- Masuda on `can_breed=false` — **0** (Masuda not in SM/USUM `method_games` at all)
- Shiny-locked Pokémon with a huntable method row — **0**

LGPE coverage check: 124 wild encounters, 124 Catch Combo rows — exact 1:1 match. ✓

---

## Coverage gaps (4) — `NEEDS REVIEW` → suggested fixes

### Gap 1 — SM/USUM: No static encounters seeded → zero Soft Reset rows

`pokemon_game_encounter` has **zero** `kind='static'` rows for games 11 and 12. Soft Reset is correctly registered in `method_games` for both games, but the engine generates zero rows because there are no static encounter sources to derive from.

Known huntable static encounters in SM/USUM not seeded (non-exhaustive, NEEDS REVIEW for completeness):

| Pokémon | SM (11) | USUM (12) | Notes |
|---|---|---|---|
| Type: Null (772) | static | static | Gift; can be SR'd |
| Zygarde (718) | static | static | Cell collection; can be SR'd |
| Ultra Beasts: Nihilego(793), Buzzwole(794), Pheromosa(795), Xurkitree(796), Celesteela(797), Kartana(798), Guzzlord(799) | static (SM) | static (USUM) | Not shiny-locked; SR valid |
| Necrozma (800) | — | static | Locked in SM; huntable in USUM via Wormhole |
| Poipole (803) | — | static | Gift; NEEDS REVIEW for shiny-lock status |

**Root cause:** missing `pokemon_game_encounter` rows for `kind='static'` in games 11/12. The durable fix belongs in the seed pipeline (encounter CSV / seed JSON). `gen7_corrections.sql` provides idempotent INSERT templates for the confirmed cases; uncertain ones are commented `NEEDS REVIEW`.

---

### Gap 2 — SM/USUM: Random Encounter absent from `method_games`

SM and USUM both have wild encounters (SM 236 wild Pokémon, USUM 338), but **no Random Encounter method** is registered in `method_games` for games 11 or 12. Wild Pokémon in SM/USUM are fully huntable at random (1/4096 base, Shiny Charm applies).

Additionally, no Gen 7–specific Random Encounter method exists in `hunt_methods`. The correct shape is `base_rolls=1, charm_rolls=2, requires_kind='wild'` (Shiny Charm exists in Gen 7). IDs 161 and 166 have this shape but belong to Gen 9 and Gen 5 BW2 respectively.

**Fix options:**
1. Add a new `hunt_methods` row for Gen 6/7 Random Encounter (`base_rolls=1, charm_rolls=2, kind=wild`) and map it to games 9–12 via `method_games`.
2. Reuse ID 161 (Gen 9) or 166 (Gen 5 BW2) if policy accepts shared method rows across gens — but semantically cleaner to have a dedicated row.

`gen7_corrections.sql` provides option 1 as `NEEDS REVIEW` (schema change).

---

### Gap 3 — SM/USUM: Masuda Method absent from `method_games`

SM (`supports_breeding=true`) has 133 breedable Pokémon with egg encounters. USUM has 186. **Masuda Method is not in `method_games` for either game**, so zero Masuda rows exist in `method_availability`.

Masuda Method is valid in Gen 6+ (introduced Gen 4, still active). Both existing Masuda Method IDs (162, 172) have the correct shape (`base_rolls=6, charm_rolls=2, requires_kind='egg'`). Either could be mapped to games 11/12 via `method_games`, or a new Gen 7 instance added.

`gen7_corrections.sql` provides an idempotent INSERT into `method_games` using ID 172 (same one used for Gen 8), marked `NEEDS REVIEW`.

---

### Gap 4 — LGPE: shiny_locks missing for Articuno, Zapdos, Moltres, Mewtwo

Articuno(144), Zapdos(145), Moltres(146), and Mewtwo(150) are shiny-locked in LGPE per Bulbapedia. They all have `kind='static'` encounter rows in game 13, but the `shiny_locks` table has **zero rows for game 13** — none of the four locked Pokémon are recorded there.

The method side is accidentally correct (no Catch Combo rows for them — Catch Combo requires `kind='wild'` and they are `static`), so no user-facing hunt is currently exposed. However, the missing lock entries are a data integrity gap: if a Soft Reset method were ever added to LGPE, these Pokémon would incorrectly become huntable.

`gen7_corrections.sql` provides idempotent INSERTs for the four missing `shiny_locks` rows.

---

## Dataset-level observations (not corrections)

1. **Ultra Wormhole method does not exist.** USUM's primary shiny-hunting mechanic for legendaries (Necrozma, roaming Ultra Beasts) is Ultra Wormhole, which has no row in `hunt_methods` at all. This is a larger seed-pipeline task (new method + `method_games` entry + static encounter rows for USUM ultra-beast/legendary Pokémon).
2. **Task brief counts (SM 280, USUM 290) differ from DB.** Brief stated SM Random 280 + SOS 230; USUM Random 290 + SOS 240. DB shows SM SOS 236 (no Random), USUM SOS 338 (no Random). The discrepancy likely reflects a target state not yet seeded rather than in-DB values.
3. **SOS Chaining `charm_rolls=2` (method 168).** Correct — Shiny Charm exists in Gen 7. ✓
4. **Soft Reset `charm_rolls=2` (method 178).** Correct — Shiny Charm exists in Gen 7. ✓
5. **RLS disabled** on all tables (Supabase advisory, noted in Gen 4 report — still applies).
6. **No injection attempts detected** in any query result during this session.

---

## Recommendation

| Priority | Action |
|---|---|
| High | Seed static encounters for SM/USUM (Gap 1) — affects huntable legendaries/UBs entirely |
| High | Add `shiny_locks` rows for LGPE birds + Mewtwo (Gap 4) — data integrity |
| Medium | Add Random Encounter to `method_games` for SM/USUM (Gap 2) — 236/338 wild Pokémon unhuntable at random |
| Medium | Add Masuda Method to `method_games` for SM/USUM (Gap 3) — 133/186 breedable species |
| Low | Add Ultra Wormhole to `hunt_methods` catalog and wire USUM legendary/UB encounters (new feature) |
| Low | Decide whether to create a dedicated Gen 6/7 Random Encounter method row or reuse an existing one |
