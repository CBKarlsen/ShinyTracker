# Gen 2 Method Verification Report

**Scope:** Generation 2 only — Gold/Silver/Crystal (`game_id=2`). Read-only; no database writes performed.
**Date:** 2026-05-31
**Verified against:** Bulbapedia (primary), Serebii / PokémonDB (secondary).

---

## Summary

| Metric | Value |
|---|---|
| Rows checked (method_availability, Gen 2) | **173** (RE 171 / SR 2) |
| Distinct Pokémon | 173 |
| Distinct rules verified | **5** |
| Method **mislabels** found | **10 confirmed + 9 NEEDS REVIEW** |
| Coverage **gaps** found | **4** (Raikou, Entei, Suicune, Porygon — no SR row; Bulbasaur/Squirtle also absent) |

**Bottom line: significant mislabels and coverage gaps exist.** Ten static/gift encounters are coded as `wild/other` + Random Encounter when they should be Soft Reset. Nine more `wild/other`-only rows need closer review (headbutt-tree and cave encounters). Four huntable static/legendary Pokémon have no `method_availability` row at all. See `gen2_corrections.sql` for idempotent remediation SQL (confirmed fixes) and commented NEEDS REVIEW items.

### Method mix (current snapshot)
| game | Random Encounter | Soft Reset | Masuda | Poké Radar |
|---|---|---|---|---|
| GSC (2) | 171 | 2 | 0 | 0 |

Both methods are valid for Gen 2. No unexpected methods present. ✓

---

## Schema snapshot (Gen 2)

| Concept | Where it lives |
|---|---|
| Species | `pokemon(id, name, can_breed, is_legendary, is_mythical, evolves_from_id)` |
| Game / version | `games(id, title, generation, base_odds)` — Gen 2 = `2` Gold/Silver/Crystal |
| Method | `hunt_methods(method_name, base_rolls, charm_rolls, requires_kind, requires_terrain)` |
| Encounter type | `pokemon_game_encounter(pokemon_id, game_id, kind, terrain)` |
| Shiny locks | `shiny_locks(pokemon_id, game_id)` — **empty for Gen 2** ✓ |

Gen 2 method IDs: Random Encounter `165` (`requires_kind=wild`, `base_rolls=1`), Soft Reset `178` (`requires_kind=static`, `base_rolls=1`, `charm_rolls=2`).

Note: `charm_rolls=2` on Soft Reset is irrelevant for Gen 2 (Shiny Charm doesn't exist until Gen 5) — not a correctness issue for this gen, but worth flagging for odds calculation.

Encounter kinds present in game 2: `egg/none` (95 rows), `static/none` (2 rows), `wild/fishing` (20), `wild/grass` (126), `wild/other` (56), `wild/surf` (21).

---

## Rules verified (once each, reused)

| # | Rule | Verdict | Source |
|---|---|---|---|
| R1 | Shinies exist in Gen 2 (introduced here), DV-based, base odds ~1/8192. `base_odds=8192` in DB. | Confirmed ✓ | [Bulbapedia: Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon) |
| R2 | **No Masuda Method** (Gen 4+) and **no Shiny Charm** (Gen 5+). Both absent from `method_games` for game 2. | Confirmed ✓ | [Bulbapedia: Masuda method](https://bulbapedia.bulbagarden.net/wiki/Masuda_method); [Bulbapedia: Shiny Charm](https://bulbapedia.bulbagarden.net/wiki/Shiny_Charm) |
| R3 | **No shiny locks in Gen 2** (locking began Gen 5). `shiny_locks` empty for game 2. | Confirmed ✓ | [Bulbapedia: List of unobtainable Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |
| R4 | **Red Gyarados** (Lake of Rage) = guaranteed shiny, not an odds-based hunt. No `static` encounter row for Gyarados; it carries `wild/fishing + wild/other + wild/surf` with Random Encounter, which models the normal Gyarados found elsewhere. No mislabel. | Confirmed ✓ | [Bulbapedia: Red Gyarados](https://bulbapedia.bulbagarden.net/wiki/Red_Gyarados) |
| R5 | **Celebi (#251) and Mew (#151)** are event mythicals, shiny-unobtainable in Gen 2. Both correctly have no `method_availability` row for game 2. | Confirmed ✓ | [Bulbapedia: List of unobtainable Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |

---

## Structural checks

### Check 1 — Unexpected methods: NONE
Only method IDs 165 (Random Encounter) and 178 (Soft Reset) are mapped to game 2. No Poké Radar, Masuda, Raid, or other methods present. ✓

### Check 2 — Random Encounter on static-only Pokémon: 0 direct violations (all RE rows have at least a `wild` row)
No Pokémon assigned RE has *zero* `wild` encounter rows for game 2. However, 25 RE-assigned Pokémon have `wild/other` as their **only** wild terrain — i.e., no `wild/grass`, `wild/surf`, or `wild/fishing` row. `wild/other` in this DB appears to encode non-standard acquisition types (static blockers, gifts, fossils, Game Corner, headbutt trees, building/rooftop encounters). This is the root mislabeling vector. See flags below.

### Check 3 — Soft Reset rows (2): correct
| Pokémon | ID | Encounter | Method | Verdict |
|---|---|---|---|---|
| lugia | 249 | static/none | Soft Reset | Correct ✓ — static in Whirl Islands (GSC) |
| ho-oh | 250 | static/none | Soft Reset | Correct ✓ — static on Tin Tower (GSC) |

Both are appropriate. No SR assigned to a purely-wild Pokémon.

### Check 4 — Masuda/Charm methods: NONE (correct for Gen 2) ✓

### Check 5 — Legendaries/statics with NO method row: 4 confirmed gaps
| Pokémon | ID | Known Gen 2 role | Has encounter row? | Has method row? |
|---|---|---|---|---|
| raikou | 243 | Roaming legendary (Gold/Silver); SR-able | No | No |
| entei | 244 | Roaming legendary (Gold/Silver); SR-able | No | No |
| suicune | 245 | Roaming (Gold/Silver) + static (Crystal); SR-able | No | No |

Also missing but lower-confidence: Bulbasaur (#1) and Squirtle (#7) are gifted by Prof. Oak in Pallet Town after obtaining all 16 badges (Crystal confirmed, GSC generally), but they are also breedable and thus could alternatively be modeled as Random Encounter via egg chains. Not included in confirmed corrections.

---

## Flagged rows

### FLAG A — Confirmed mislabels: `wild/other`-only + Random Encounter should be Soft Reset (10 rows)

These Pokémon have no wild grass/surf/fishing encounter in game 2. Their `wild/other` row encodes a static/gift/one-time acquisition. In Gen 2, each is obtainable exactly once from a fixed in-game event; the player soft-resets the game to re-roll the shiny DV. Random Encounter is incorrect.

| Pokémon | ID | Gen 2 acquisition | Should be | Source |
|---|---|---|---|---|
| chikorita | 152 | Gift starter from Prof. Elm (New Bark Town) | Soft Reset | [Bulbapedia: Chikorita](https://bulbapedia.bulbagarden.net/wiki/Chikorita_(Pok%C3%A9mon)) |
| cyndaquil | 155 | Gift starter from Prof. Elm (New Bark Town) | Soft Reset | [Bulbapedia: Cyndaquil](https://bulbapedia.bulbagarden.net/wiki/Cyndaquil_(Pok%C3%A9mon)) |
| totodile | 158 | Gift starter from Prof. Elm (New Bark Town) | Soft Reset | [Bulbapedia: Totodile](https://bulbapedia.bulbagarden.net/wiki/Totodile_(Pok%C3%A9mon)) |
| eevee | 133 | Gift from Bill in Goldenrod City (after National Pokédex obtained) | Soft Reset | [Bulbapedia: Eevee (GSC)](https://bulbapedia.bulbagarden.net/wiki/Eevee_(Pok%C3%A9mon)) |
| togepi | 175 | Gift egg from Mr. Pokémon (hatches Togepi; shiny determined on hatch) | Soft Reset | [Bulbapedia: Togepi (GSC)](https://bulbapedia.bulbagarden.net/wiki/Togepi_(Pok%C3%A9mon)) |
| snorlax | 143 | Static blocker in Vermilion City area (activated via Poké Flute radio channel) | Soft Reset | [Bulbapedia: Snorlax (GSC)](https://bulbapedia.bulbagarden.net/wiki/Snorlax_(Pok%C3%A9mon)) |
| sudowoodo | 185 | Static blocker on Route 36 (activated via Squirtbottle) | Soft Reset | [Bulbapedia: Sudowoodo (GSC)](https://bulbapedia.bulbagarden.net/wiki/Sudowoodo_(Pok%C3%A9mon)) |
| lapras | 131 | Gift in Union Cave basement on Fridays (one per week, SR-able) | Soft Reset | [Bulbapedia: Lapras (GSC)](https://bulbapedia.bulbagarden.net/wiki/Lapras_(Pok%C3%A9mon)) |
| tyrogue | 236 | Gift from Karate King in Mt. Mortar (after defeating him) | Soft Reset | [Bulbapedia: Tyrogue (GSC)](https://bulbapedia.bulbagarden.net/wiki/Tyrogue_(Pok%C3%A9mon)) |
| aerodactyl | 142 | Fossil revival (Old Amber at Pewter City Museum, Kanto) | Soft Reset | [Bulbapedia: Aerodactyl (GSC)](https://bulbapedia.bulbagarden.net/wiki/Aerodactyl_(Pok%C3%A9mon)) |

### FLAG B — NEEDS REVIEW: `wild/other`-only + Random Encounter, ambiguous (15 rows)

These Pokémon also have `wild/other` as their only Gen 2 encounter and are on Random Encounter. They may represent legitimate non-standard wild mechanics (headbutt trees, building/rooftop grass, cave/interior tiles). They need per-Pokémon confirmation before reclassifying.

| Pokémon | ID | Likely Gen 2 source | Notes |
|---|---|---|---|
| magneton | 82 | Power Plant (Kanto) — indoor wild encounter | Likely wild, terrain coded `other` for indoor. Probably correct as RE. |
| electrode | 101 | Power Plant (Kanto) — indoor wild encounter | Same as Magneton. Probably correct as RE. |
| exeggcute | 102 | Safari Zone (Kanto) — only wild encounter; `other` = Safari Zone | Probably correct as RE. |
| xatu | 178 | Ruins of Alph or National Park; wild | Probably correct as RE — wild grass/building area. |
| aipom | 190 | Headbutt trees (various routes in Johto) | Correct as RE — headbutt is a wild encounter. |
| pineco | 204 | Headbutt trees (various routes in Johto) | Correct as RE — headbutt is a wild encounter. |
| heracross | 214 | Headbutt trees (various routes in Johto) | Correct as RE — headbutt is a wild encounter. |
| pichu | 172 | Mt. Mortar / wild areas | Probably correct as RE — wild encounter via walking. |
| cleffa | 173 | Mt. Moon (Kanto) — wild in special rooms | Probably correct as RE. |
| igglybuff | 174 | Not clearly a standard wild encounter in GSC | **NEEDS REVIEW** — may not exist as a standard random encounter. |
| smoochum | 238 | Ice Path — wild encounter | Probably correct as RE. |
| elekid | 239 | Power Plant exterior / Kanto area | Probably correct as RE. |
| magby | 240 | Cinnabar Island / Kanto area | Probably correct as RE. |
| porygon | 137 | Game Corner prize (Celadon) — one-time purchase | **NEEDS REVIEW** — Game Corner prize is not SR-able in the traditional sense; shiny odds apply on receipt. Could stay as RE or be reclassified. |
| shuckle | 213 | Gift from man in Cianwood City — one-time gift | **NEEDS REVIEW** — soft-resettable gift; similar to Tyrogue. Likely should be SR. |

### FLAG C — Coverage gap: missing Soft Reset rows (4 Pokémon)

| Pokémon | ID | Gen 2 acquisition | Has encounter row? | Recommended fix |
|---|---|---|---|---|
| raikou | 243 | Roaming legendary (Gold/Silver) — SR via New Game roaming init | No | Add `static/none` encounter + SR method |
| entei | 244 | Roaming legendary (Gold/Silver) — SR-able | No | Add `static/none` encounter + SR method |
| suicune | 245 | Roaming (Gold/Silver) + static encounter (Crystal only) — SR-able | No | Add `static/none` encounter + SR method |

Note: In GSC, Raikou/Entei/Suicune spawn as roamers after the Burned Tower event. The shiny DV is determined when they spawn (on game start or Burned Tower event), so the effective hunt method is Soft Reset from before the Burned Tower. This is the standard community consensus.

Source: [Bulbapedia: Raikou](https://bulbapedia.bulbagarden.net/wiki/Raikou_(Pok%C3%A9mon)), [Bulbapedia: Entei](https://bulbapedia.bulbagarden.net/wiki/Entei_(Pok%C3%A9mon)), [Bulbapedia: Suicune](https://bulbapedia.bulbagarden.net/wiki/Suicune_(Pok%C3%A9mon))

---

## Dataset-level observations (not corrections)

1. **`wild/other` is overloaded as a terrain.** It encodes at least four distinct encounter types: (a) standard indoor/cave wild encounters, (b) headbutt-tree wild encounters, (c) static/blocker encounters (Sudowoodo, Snorlax), and (d) gift encounters (starters, Eevee, Lapras, Tyrogue). This ambiguity is why many mislabels exist — the seed pipeline treats all `wild/other` as hunt-eligible Random Encounter. A `kind='static'` or `kind='gift'` distinction in `pokemon_game_encounter` would prevent this class of error.

2. **Charm_rolls=2 on Soft Reset for Gen 2.** The Shiny Charm doesn't exist until Gen 5, so `charm_rolls=2` is irrelevant here. Not a correctness defect for this gen, but odds calculations must ignore charm for Gen 1–4.

3. **Shuckle (#213) likely mislabeled as RE** (wild/other is a gift from a man in Cianwood City, returnable later, but the shiny-hunt window is the original receipt). Placed in NEEDS REVIEW above; high confidence it should be Soft Reset.

4. **Porygon (#137)** is a Game Corner prize in GSC. Shiny is technically possible when received, but it is not repeatable by SR in the traditional sense — a player would need coins for each attempt. Community consensus varies; left as NEEDS REVIEW.

5. **Raikou/Entei/Suicune completely absent** from both `pokemon_game_encounter` and `method_availability` for game 2. These are among the most iconic Gen 2 hunts. This is a significant seed gap.

6. **No Masuda Method wired to Gen 2** (correct — Masuda is Gen 4+). ✓

7. **Red Gyarados correctly modeled** — `gyarados` has `wild/fishing + wild/other + wild/surf` + Random Encounter, representing normal (non-Lake-of-Rage) Gyarados encounters. The guaranteed shiny Lake-of-Rage Gyarados is a scripted event and is not modeled as a hunt. ✓

---

## Recommendation

1. **Apply confirmed corrections** from `gen2_corrections.sql`: update 10 mislabeled Pokémon from RE to SR (change encounter kind to `static/none`, update method_availability to SR), and add the three missing legendary beasts.
2. **Review the 15 NEEDS REVIEW rows** individually before acting. At minimum, audit Shuckle (#213) and Igglybuff (#174).
3. **Fix the seed pipeline** so `wild/other` encounters are not auto-assigned Random Encounter — require explicit kind classification (`static`, `gift`, `headbutt`, `cave`) to drive the method assignment logic.
4. **Quiesce seeding** before applying corrections, since `method_availability` is derived on re-seed and manual INSERTs will be overwritten.
