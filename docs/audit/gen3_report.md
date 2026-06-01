# Gen 3 Method Verification Report

**Scope:** Generation 3 — Ruby/Sapphire/Emerald (`game_id=3`) and FireRed/LeafGreen (`game_id=4`).
**Date:** 2026-05-31
**Verified against:** Bulbapedia (primary), Serebii / PokémonDB (secondary).

> Read-only audit; no database writes performed. Data confirmed stable across repeated reads within this session.

---

## Summary

| Metric | Value |
|---|---|
| Rows checked (method_availability, Gen 3) | **301** (RSE 155 / FRLG 146) |
| Distinct Pokémon | RSE 155 / FRLG 146 |
| Distinct rules verified | **5** |
| Method **mislabels** found | **1** (all 152 RSE wild-encounter rows use "Run Away" instead of "Random Encounter") |
| Invalid methods present | **0** (no Masuda, no charm-boosted methods, no Gen 4+ mechanics) |
| Shiny locks (games 3/4) | **0** — correct; locking began Gen 5 |
| Coverage **gaps** found | **2 significant** (Regis + Lati@s in RSE; roaming beasts in FRLG) + **2 secondary** (starters/fossils/gifts missing Soft Reset in both games) |

**Bottom line:** RSE's entire wild-encounter pool carries the wrong method name ("Run Away" instead of "Random Encounter"). FRLG is correctly labeled but shares the secondary gap of starters/fossils/gifts lacking Soft Reset. Five RSE legendaries (Regirock, Regice, Registeel, Latias, Latios) and three FRLG roamers (Raikou, Entei, Suicune) have no encounter row and no hunt method at all.

### Method mix (stable snapshot)

| game | Run Away (179) | Random Encounter (165) | Soft Reset (178) | Masuda |
|---|---|---|---|---|
| RSE (3) | 152 | 0 | 3 | 0 |
| FRLG (4) | 0 | 142 | 4 | 0 |

RSE uses "Run Away" (method_id=179) in place of "Random Encounter". FRLG uses the correct method (165). No Masuda present in either game. ✓

---

## Schema reading (Phase 1)

Same structural layout as Gen 4 (see `gen4_report.md`). Gen 3 method IDs confirmed via `method_games`:

| game | method_id | method_name | base_rolls | charm_rolls | requires_kind |
|---|---|---|---|---|---|
| RSE (3) | 178 | Soft Reset | 1 | 2 | static |
| RSE (3) | 179 | Run Away | 1 | 2 | wild |
| FRLG (4) | 165 | Random Encounter | 1 | 0 | wild |
| FRLG (4) | 178 | Soft Reset | 1 | 2 | static |

`games.base_odds = 8192` for both Gen 3 games — correct (1/8192, no Shiny Charm in Gen 3).

---

## Rules verified (once each)

| # | Rule | Verdict | Source |
|---|---|---|---|
| R1 | **No Masuda Method in Gen 3** (introduced Gen 4) | Confirmed — Masuda absent from `method_games` for games 3/4 | [Bulbapedia: Masuda method](https://bulbapedia.bulbagarden.net/wiki/Masuda_method) |
| R2 | **No Shiny Charm in Gen 3** (introduced Gen 5) | `base_odds=8192`, `charm_rolls` on method_id 178/179 is non-zero but irrelevant while charm is absent — flagged as a method-definition concern, not a Gen 3 error | [Bulbapedia: Shiny Charm](https://bulbapedia.bulbagarden.net/wiki/Shiny_Charm) |
| R3 | **No shiny locks in Gen 3** (locking began Gen 5) | Confirmed — `shiny_locks` empty for games 3/4 | [Bulbapedia: Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon) |
| R4 | **Valid Gen 3 hunt methods:** Random Encounter (wild), Soft Reset (static/gift/legendary) | RSE uses "Run Away" (id=179) instead of "Random Encounter" — mislabel confirmed | [Bulbapedia: Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon) |
| R5 | **RSE/FRLG event mythicals** (Mew, Celebi, Jirachi, Deoxys, Lugia/Ho-Oh via Navel Rock) not obtainable via normal gameplay | Correctly absent from `method_availability`; Lugia/Ho-Oh noted separately | [Bulbapedia: List of unobtainable Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |

---

## Verification results

### FLAG 1 — Method mislabel: RSE uses "Run Away" instead of "Random Encounter" (152 rows)

All 152 RSE wild-encounter rows are assigned method_id=179 ("Run Away") rather than a "Random Encounter" method. "Run Away" is not a recognised shiny-hunt method; it appears to be a seeding artefact. All 152 Pokémon were confirmed to have valid `wild` encounter rows in `pokemon_game_encounter` for game_id=3, so the encounter data is correct — only the method label is wrong.

FRLG has no such issue: its 142 wild-encounter rows all use method_id=165 ("Random Encounter"). ✓

**Correct fix:** map RSE wild encounters to an appropriate "Random Encounter" method_id (e.g. 165, which has `charm_rolls=0` — appropriate for Gen 3 / no Shiny Charm).

### FLAG 2 — RSE coverage gap: Regirock, Regice, Registeel, Latias, Latios (5 legendaries)

These five RSE-catchable legendaries have **no** `pokemon_game_encounter` row for game_id=3 and **no** `method_availability` row. None are shiny-locked in Gen 3 (R3).

| Pokémon | id | RSE encounter | Correct method | Notes |
|---|---|---|---|---|
| Regirock | 377 | static (Sealed Chamber) | Soft Reset | — |
| Regice | 378 | static (Island Cave) | Soft Reset | — |
| Registeel | 379 | static (Ancient Tomb) | Soft Reset | — |
| Latias | 380 | static/roamer (RSE — version-dependent) | Soft Reset | roamer → SR is correct |
| Latios | 381 | static/roamer (RSE — version-dependent) | Soft Reset | roamer → SR is correct |

**Fix requires:** add `static/none` encounter row to `pokemon_game_encounter` (game_id=3) + Soft Reset method_availability row for each.

### FLAG 3 — FRLG coverage gap: Raikou, Entei, Suicune (3 roaming legendaries)

These three FRLG roaming legendaries (which one appears depends on starter choice) have **no** `pokemon_game_encounter` row for game_id=4 and **no** `method_availability` row. All three are shiny-huntable via Soft Reset in FRLG (roamers can be SR'd from the overworld encounter, same bucket as other statics).

| Pokémon | id | FRLG encounter | Correct method |
|---|---|---|---|
| Raikou | 243 | roamer (starter-dependent) | Soft Reset |
| Entei | 244 | roamer (starter-dependent) | Soft Reset |
| Suicune | 245 | roamer (starter-dependent) | Soft Reset |

**Fix requires:** add `static/none` encounter row + Soft Reset method_availability row for each in game_id=4.

### FLAG 4 — RSE starters/fossils/gifts: missing Soft Reset (secondary gap)

Treecko (252), Torchic (255), Mudkip (258), Lileep (345), Anorith (347), Castform (351), and Beldum (374) are all received as gifts or from fossils in RSE. Each has `wild/other` + `egg/none` encounter rows but **no** `static` encounter row and **no** Soft Reset method. The `wild/other` row is what drives their current "Run Away" assignment, which is incorrect for gift-only encounters.

- Starters (Treecko/Torchic/Mudkip) and Beldum are pure gifts — no wild encounter exists.
- Fossils (Lileep/Anorith) are revived from items — no wild encounter exists.
- Castform is a gift from the Weather Institute.
- Wynaut (360) has genuine wild encounters (Emerald) and a "Run Away" label — lower priority than the gifts.

**Fix requires:** add `static/none` encounter rows + Soft Reset method_availability for gifts. Remove "Run Away" assignment from pure-gift Pokémon that have no real wild encounter (the `wild/other` rows appear to be seeding artefacts — NEEDS REVIEW).

### FLAG 5 — FRLG starters/fossils: missing Soft Reset (secondary gap)

Bulbasaur (1), Charmander (4), Squirtle (7), Omanyte (138), and Kabuto (140) are assigned Random Encounter (165) in FRLG via `wild/other` encounter rows, but are received as gifts or from fossils — no wild encounter exists in FRLG. No Soft Reset row is present.

**Fix requires:** same pattern as FLAG 4 — add `static/none` encounter rows + Soft Reset. Remove/review the `wild/other` encounter rows that incorrectly drive Random Encounter assignment (NEEDS REVIEW).

---

## Observations (not corrections)

1. **"Run Away" method (id=179)** exists only in `method_games` for RSE (game_id=3). Its `charm_rolls=2` is harmless while Shiny Charm is absent, but the name is misleading. If RSE is re-seeded to use a proper "Random Encounter" method, method_id=179 should be removed from `method_games` for game_id=3.

2. **Soft Reset (178) charm_rolls=2** affects both Gen 3 games via the shared method definition. Odds calculations should guard against applying the charm bonus when `game_id` is pre-Gen 5. This is a display/calculation concern, not a method assignment error.

3. **FRLG Random Encounter uses method_id=165**, which has `charm_rolls=0` — correctly set for a pre-charm game. ✓

4. **Lugia (249) / Ho-Oh (250) in FRLG** (Navel Rock) and **Deoxys (386)** (Birth Island) are absent from both `pokemon_game_encounter` and `method_availability` for game_id=4. These are event-only in FRLG (Lugia/Ho-Oh require a Nintendo event ticket; Deoxys = Birth Island ticket). Whether to include them is a policy decision — they are technically shiny-huntable via SR if you have the event item. Marked NEEDS REVIEW in corrections SQL.

5. **Jirachi (385) / Mew (151) / Celebi (251)** are correctly absent — Jirachi is a bonus disc event, Mew/Celebi were not legitimately available in Gen 3 retail.

6. **RLS disabled** on all tables (inherited observation from Gen 4 audit) — anyone with the anon key can read/write.

---

## Recommendation before applying corrections

1. Decide the **"Run Away" vs "Random Encounter" fix strategy**: either remap the `method_games` entry for game_id=3 from method_id=179 to an appropriate Random Encounter method (e.g. 165), or add a new Gen-3-specific Random Encounter method. Remapping is simpler and avoids re-seeding `method_availability`.
2. Audit the `wild/other` encounter rows for pure-gift Pokémon (starters, fossils, Beldum, Castform in both games) — if they are seeding artefacts from a Masuda derivation pass, they should be removed and replaced with `static/none` rows.
3. Decide coverage policy for FRLG event legendaries (Lugia/Ho-Oh, Deoxys) before adding hunt entries.
4. Key any DB writes on the natural triple `(pokemon_id, game_id, method_id)` — the surrogate `id` renumbers on every reseed.
