# Gen 9 Method Verification Report

**Scope:** Generation 9 — Scarlet/Violet (`game_id=17`). Read-only audit; no database writes performed.
**Date:** 2026-05-31
**Verified against:** Bulbapedia (primary), Serebii / PokémonDB (secondary).

---

## Summary

| Metric | Value |
|---|---|
| Rows checked (method_availability, Gen 9) | **2,269** (Random 650 / Masuda 319 / Mass Outbreak 650 / Sandwich 650) |
| Distinct Pokémon with any method | **696** |
| Distinct rules verified | **6** |
| Method **mislabels** found | **0** ✅ |
| **Shiny-lock false positives** (in `shiny_locks`, not actually locked) | **3** — Archaludon, Hydrapple, Gouging Fire |
| **Shiny-lock missing entries** (locked in reality, absent from DB) | **4** — Okidogi, Munkidori, Fezandipiti, Terapagos |
| Coverage **gaps** found | **6** Pokémon with no hunt method (Treasures of Ruin + Walking Wake/Iron Leaves) |

**Bottom line:** every assigned method is correct (no mislabels). Issues are confined to the `shiny_locks` table (3 false positives, 4 missing entries) and 6 coverage gaps for obtainable legendaries/raid-exclusives. Corrections in `gen9_corrections.sql`.

---

## Schema reading (Phase 1)

Same schema as Gen 4 (see `gen4_report.md`). Gen 9 specifics:

| Concept | Value |
|---|---|
| Game | `games.id = 17` (Scarlet/Violet) |
| Base odds | 1/4096 (Gen 6+ standard) |
| Method IDs (game 17) | Random Encounter `161`, Masuda `162`, Mass Outbreak `167`, Sandwich Hunting `170`, Soft Reset `178` |
| Shiny Charm | Exists in SV; adds +2 rolls to all methods |
| Shiny locks | `shiny_locks(pokemon_id, game_id)` — 7 entries for game 17 at audit time |

Note: Soft Reset (method 178) is wired to game 17 via `method_games` but has **zero** `method_availability` rows for game 17. It is available as a method ID but unused in the current seed output.

---

## Rules verified (once each, reused across rows)

| # | Rule | Verdict | Source |
|---|---|---|---|
| R1 | **Random Encounter** (1/4096) for wild overworld Pokémon | Confirmed — all 650 rows have a `wild` encounter row in game 17; 0 violations | [Bulbapedia: Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon) |
| R2 | **Mass Outbreak** requires wild-spawnable species | Confirmed — all 650 rows have a `wild` encounter; 0 violations | [Bulbapedia: Mass Outbreak](https://bulbapedia.bulbagarden.net/wiki/Mass_Outbreak_(Scarlet_and_Violet)) |
| R3 | **Sandwich Hunting** (Sparkling Power) requires wild-spawnable species | Confirmed — all 650 rows have a `wild` encounter; 0 violations | [Bulbapedia: Picnic sandwiches](https://bulbapedia.bulbagarden.net/wiki/Sparkling_Power) |
| R4 | **Masuda Method** valid only for `can_breed=true` Pokémon | Confirmed — all 319 Masuda rows have `can_breed=true`; 0 violations | [Bulbapedia: Masuda method](https://bulbapedia.bulbagarden.net/wiki/Masuda_method) |
| R4a | Masuda assigned only to base-form (`evolves_from_id IS NULL`) Pokémon | Confirmed — all 319 Masuda rows are base-form; the 342 breedable non-base-forms correctly have no Masuda row | Design intent (eggs hatch base forms only) |
| R5 | **Shiny locks (base SV):** Koraidon & Miraidon locked; Treasures of Ruin, Paradox Pokémon, box legendaries NOT locked | Koraidon/Miraidon correctly in `shiny_locks` with 0 methods; Treasures of Ruin correctly absent from `shiny_locks` | [Bulbapedia: List of unobtainable Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |
| R6 | **Shiny locks (DLC):** Ogerpon, Loyal Three (Okidogi/Munkidori/Fezandipiti), Bloodmoon Ursaluna (not in DB), Terapagos, Pecharunt locked | Ogerpon/Pecharunt correctly in `shiny_locks`; Loyal Three and Terapagos **missing** from `shiny_locks` | [Bulbapedia: Teal Mask / Indigo Disk locked list](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |

---

## Verification results

### Method mislabels: none

All four rule-category checks returned **zero** violations:
- **Random Encounter on non-wild** — 0 (all 650 rows backed by a `wild` encounter).
- **Mass Outbreak on non-wild** — 0 (all 650 rows backed by a `wild` encounter).
- **Sandwich Hunting on non-wild** — 0 (all 650 rows backed by a `wild` encounter).
- **Masuda on can_breed=false** — 0.

### Issue 1 — Shiny-lock false positives (3 Pokémon)

These three Pokémon are in `shiny_locks` for game 17 but are **not** shiny-locked in Scarlet/Violet:

| Pokémon | ID | In `shiny_locks` | Methods assigned | Correct status | Source |
|---|---|---|---|---|---|
| archaludon | 1018 | YES (wrong) | Random, Mass Outbreak, Sandwich | NOT locked — huntable wild | Bulbapedia: Archaludon |
| hydrapple | 1019 | YES (wrong) | Random, Mass Outbreak, Sandwich | NOT locked — huntable wild | Bulbapedia: Hydrapple |
| gouging-fire | 1020 | YES (wrong) | Random, Mass Outbreak, Sandwich | NOT locked — huntable wild Paradox | Bulbapedia: Gouging Fire |

All three have `wild` encounter rows and 3 correctly-assigned hunt methods. The methods are right; the lock entry is the error. **Fix: DELETE these 3 rows from `shiny_locks`.**

Note: the hunt methods on these three are correct and should be **kept**.

### Issue 2 — Missing shiny-lock entries (4 Pokémon)

These Pokémon are shiny-locked in the DLC but absent from `shiny_locks`. None has any `method_availability` row, so there is no huntable-method conflict — but the lock record is missing and they would appear huntable in any UI check that relies on `shiny_locks` presence.

| Pokémon | ID | In `shiny_locks` | Methods | Correct status | Source |
|---|---|---|---|---|---|
| okidogi | 1014 | NO (missing) | 0 | LOCKED — Teal Mask static | Bulbapedia: Loyal Three |
| munkidori | 1015 | NO (missing) | 0 | LOCKED — Teal Mask static | Bulbapedia: Loyal Three |
| fezandipiti | 1016 | NO (missing) | 0 | LOCKED — Teal Mask static | Bulbapedia: Loyal Three |
| terapagos | 1024 | NO (missing) | 0 | LOCKED — Indigo Disk static | Bulbapedia: Terapagos |

**Fix: INSERT 4 rows into `shiny_locks`.**

### Issue 3 — Coverage gaps (6 Pokémon with no hunt method)

These non-locked Pokémon have no `pokemon_game_encounter` row and no `method_availability` row for game 17, despite being obtainable and shiny-huntable in SV:

#### 3a. Treasures of Ruin (static encounters)
Wo-Chien, Chien-Pao, Ting-Lu, and Chi-Yu are static overworld encounters (interact with shrine tablets). They are **not** shiny-locked. Correct method: Soft Reset (method 178).

| Pokémon | ID | Encounters game 17 | Methods game 17 | Should be |
|---|---|---|---|---|
| wo-chien | 1001 | (none) | (none) | static/none + Soft Reset |
| chien-pao | 1002 | (none) | (none) | static/none + Soft Reset |
| ting-lu | 1003 | (none) | (none) | static/none + Soft Reset |
| chi-yu | 1004 | (none) | (none) | static/none + Soft Reset |

#### 3b. Tera Raid exclusives (Walking Wake, Iron Leaves)
Walking Wake (1009) and Iron Leaves (1010) are obtainable only via Tera Raids (special events). They are **not** shiny-locked. The DB has no `raid` encounter kind currently used for these in game 17. Soft Reset is the closest semantically-appropriate method in the current method set (no dedicated Tera Raid method exists).

| Pokémon | ID | Encounters game 17 | Methods game 17 | Should be |
|---|---|---|---|---|
| walking-wake | 1009 | (none) | (none) | static/none + Soft Reset (NEEDS REVIEW — raid-only) |
| iron-leaves | 1010 | (none) | (none) | static/none + Soft Reset (NEEDS REVIEW — raid-only) |

**Note:** If a dedicated Tera Raid method is added in future, these should be migrated. For now Soft Reset mirrors the pattern used for other static/legendary encounters.

---

## Dataset-level observations (not corrections)

1. **Soft Reset has 0 rows for game 17.** Method 178 is wired to game 17 via `method_games` but no `method_availability` rows use it. The 6 coverage-gap Pokémon above would be the first to use it if the gap is filled.
2. **Masuda coverage is correct by design.** 319 Masuda rows cover all base-form breedable Pokémon in game 17. Non-base-form breedable Pokémon (342) correctly have no Masuda row (eggs hatch base forms). No gaps, no violations.
3. **Paradox Pokémon (can_breed=false) correctly have no Masuda.** 33 non-breedable Pokémon have 0 Masuda rows — correct.
4. **Bloodmoon Ursaluna not in DB.** The alternate form is not represented as a separate Pokémon row; base Ursaluna (901) is present with 3 wild methods. If the form is added, it should be shiny-locked (Indigo Disk static, locked).
5. **Oinkologne-female form gap.** Only `oinkologne-male` (916) is in the DB. Female form (`oinkologne` / oinkologne-female) is a separate entry in some Pokémon data sources — worth checking if it should be a separate row.
6. **RLS advisory** (inherited from Gen 4 note) — Supabase advisors flag RLS as disabled; worth addressing before production exposure.

---

## Session integrity notes

No reseeding was observed during this audit session. The Gen 9 snapshot was stable across all reads. No prompt-injection content was detected in query results.

---

## Recommendation (action priority)

1. **High — DELETE 3 false-positive shiny-lock rows** (Archaludon, Hydrapple, Gouging Fire). These make huntable Pokémon appear locked.
2. **High — INSERT 4 missing shiny-lock rows** (Loyal Three + Terapagos). These make locked Pokémon appear unlocked.
3. **Medium — Add static encounter + Soft Reset for Treasures of Ruin** (4 Pokémon). Huntable, non-locked, currently invisible to the hunt system.
4. **Low / NEEDS REVIEW — Add encounter + method for Walking Wake / Iron Leaves.** Raid-only; decide whether Soft Reset is the right approximation or whether a Tera Raid method should be added first.
5. **Durable fix belongs in the seed pipeline** — `method_availability` and `pokemon_game_encounter` are regenerated on re-seed. SQL in `gen9_corrections.sql` is idempotent for a one-off; the seed source (CSV / JSON) needs updating for persistence.
