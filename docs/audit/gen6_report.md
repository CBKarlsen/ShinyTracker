# Gen 6 Method Verification Report

**Scope:** Generation 6 — X/Y (`game_id=9`) and OmegaRuby/AlphaSapphire (`game_id=10`). Read-only audit; no database writes performed.
**Date:** 2026-05-31
**Verified against:** Bulbapedia (primary).

---

## Summary

| Metric | Value |
|---|---|
| Rows checked (method_availability, Gen 6) | **539** (XY 389 / ORAS 150) |
| Distinct Pokémon | XY 350 / ORAS 130 |
| Method-in-game structural violations | **0** ✓ |
| Shiny-lock **conflicts** (locked Pokémon with huntable method rows) | **5** (game 9: 2 / game 10: 3) |
| Shiny-lock table **gaps** (species that should be listed but aren't) | **severe** — ORAS has zero entries; XY missing starters/Lapras/birds |
| Friend Safari **over-assignment** (used as catch-all for 348 species) | **1 structural problem** |
| Coverage **gaps** (unlocked catchable Pokémon with no method) | **multiple** (see below) |
| Chain Fishing integrity | **0 violations** ✓ |
| Masuda wired to Gen 6 | **No** (coverage gap to decide) |

### Method mix (actual DB state)
| game | Friend Safari | Chain Fishing | Soft Reset | DexNav |
|---|---|---|---|---|
| XY (9) | 348 | 39 | 2 | 0 |
| ORAS (10) | 0 | 20 | 3 | 127 |

**Note:** The prompt's stated counts (XY: Random 270 + Poké Radar 180 + Friend Safari 150; ORAS: Random 260 + DexNav 200) do not match the live DB. Random Encounter and Poké Radar have **zero rows in Gen 6**. Friend Safari is used as the sole wild method for game 9, covering 348 species — far more than the ~130 species actually available in Friend Safari.

---

## Schema reading (Phase 1)

Same schema as Gen 4 audit. Method IDs confirmed for Gen 6:

| Method | ID | game_id(s) |
|---|---|---|
| Friend Safari | 173 | 9 only |
| Chain Fishing | 175 | 9, 10 |
| Soft Reset | 178 | 9, 10 |
| DexNav | 169 | 10 only |

No Random Encounter, Poké Radar, Horde, or Masuda entries exist in `method_games` for games 9 or 10. These methods are entirely absent from Gen 6.

---

## Rules verified

| # | Rule | Verdict | Source |
|---|---|---|---|
| R1 | **Method-in-game:** Poké Radar / Friend Safari XY-only; DexNav ORAS-only | No cross-game violations found ✓ | [Bulbapedia: Friend Safari](https://bulbapedia.bulbagarden.net/wiki/Friend_Safari) / [DexNav](https://bulbapedia.bulbagarden.net/wiki/DexNav) |
| R2 | **Chain Fishing** valid for `wild/fishing` encounters only | All 39 (XY) + 20 (ORAS) rows have `wild/fishing` ✓ | [Bulbapedia: Chain Fishing](https://bulbapedia.bulbagarden.net/wiki/Fishing#Chain_fishing) |
| R3 | **Friend Safari** covers only ~130 specific species in type-themed zones | 348 rows assigned — over-assigned by ~218 species; starters/fossils/mythicals present | [Bulbapedia: Friend Safari](https://bulbapedia.bulbagarden.net/wiki/Friend_Safari) |
| R4 | **DexNav** works for wild-encounterable Pokémon in Hoenn (grass/cave/surf/fishing) | No static-only or legendary violations found ✓ (starters appear via hidden/gift encounters tagged `wild/other`) | [Bulbapedia: DexNav](https://bulbapedia.bulbagarden.net/wiki/DexNav) |
| R5 | **Shiny locks — XY:** Xerneas, Yveltal, Zygarde, roaming bird (one of 144/145/146), gift Kanto starters (1/4/7), gift Lapras (131) | Xerneas+Yveltal have Soft Reset **despite being locked**; starters+Lapras have Friend Safari **despite being locked**; Zygarde correctly has no method | [Bulbapedia: Unobtainable Shiny](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |
| R6 | **Shiny locks — ORAS:** Kyogre, Groudon, Rayquaza, Deoxys, gift Latias/Latios (Soul Dew), Cosplay Pikachu, event mythicals | Kyogre+Groudon+Rayquaza have Soft Reset **despite being locked**; Deoxys/Latias/Latios have no method (correct outcome, wrong reason — no encounter row) | [Bulbapedia: Unobtainable Shiny](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |
| R7 | **Non-locked ORAS statics** (Regis 377/378/379, Eon Ticket Latios/Latias, Lugia/Ho-Oh, inter-gen legendaries) should have Soft Reset | None have encounter or method rows — **coverage gap** | [Bulbapedia: ORAS](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon_Omega_Ruby_and_Alpha_Sapphire) |
| R8 | **Masuda Method** valid for breedable Pokémon in Gen 6 (6× odds; exists from Gen 4 onward) | Not wired to Gen 6 at all — coverage gap to decide | [Bulbapedia: Masuda method](https://bulbapedia.bulbagarden.net/wiki/Masuda_method) |

---

## Findings

### F1 — Shiny-lock conflicts: Soft Reset on locked XY legendaries (game 9)

Xerneas (#716) and Yveltal (#717) appear in **both** `shiny_locks` (game 9) **and** `method_availability` with Soft Reset. They cannot be legitimately shiny-hunted in XY; Soft Reset rows must be deleted.

| Pokémon | pokemon_id | game_id | Conflict |
|---|---|---|---|
| xerneas | 716 | 9 | in shiny_locks AND has Soft Reset |
| yveltal | 717 | 9 | in shiny_locks AND has Soft Reset |

### F2 — Shiny-lock conflicts: Soft Reset on locked ORAS legendaries (game 10)

Kyogre (#382), Groudon (#383), and Rayquaza (#384) are shiny-locked in ORAS but have Soft Reset method rows. The `shiny_locks` table has zero rows for game 10 — the lock constraint is entirely missing.

| Pokémon | pokemon_id | game_id | Conflict |
|---|---|---|---|
| kyogre | 382 | 10 | shiny-locked in ORAS, has Soft Reset |
| groudon | 383 | 10 | shiny-locked in ORAS, has Soft Reset |
| rayquaza | 384 | 10 | shiny-locked in ORAS, has Soft Reset |

### F3 — Friend Safari over-assignment (game 9)

Friend Safari is assigned to **348 distinct species** in game 9, acting as a catch-all wild hunt method. The actual Friend Safari in XY contains only ~130 specific species organized by Safari type-zone. Species confirmed in this over-assignment that cannot appear in Friend Safari:

- **Gift-only starters:** Bulbasaur (#1), Charmander (#4), Squirtle (#7) — received as gifts from Prof. Sycamore, not wild encounters.
- **Lapras (#131)** — weekly gift in XY, not a wild Friend Safari species.
- **All multi-gen starters** appearing via `wild/other` terrain (Totodile, Cyndaquil, Chikorita, Treecko, Torchic, Mudkip, Turtwig, Chimchar, Piplup, Snivy, Tepig, Oshawott) — these are gifts/events in XY, not Friend Safari Pokémon.
- Many other species whose `wild/other` terrain tag in game 9 reflects gift/static availability rather than Friend Safari membership.

The correct fix is to replace the Friend Safari catch-all with: (a) a proper Random Encounter method for true wild Pokémon, (b) Friend Safari only for the ~130 species actually in the Safari, and (c) Poké Radar for grass-type species that appear via chaining. This is a **seed-data structural problem** and belongs in the seeding pipeline, not a one-off SQL fix. The corrections file provides DELETE statements for confirmed bad rows and notes the pipeline gap.

### F4 — shiny_locks table incomplete for Gen 6

**Game 9 (XY) missing locks:**
| Pokémon | pokemon_id | Reason locked |
|---|---|---|
| bulbasaur | 1 | Gift starter, shiny-locked |
| charmander | 4 | Gift starter, shiny-locked |
| squirtle | 7 | Gift starter, shiny-locked |
| lapras | 131 | Weekly gift, shiny-locked |
| articuno / zapdos / moltres | 144/145/146 | Roaming bird (the one you don't pick) appears as static encounter but the one picked is shiny-locked |

**Game 10 (ORAS) — zero entries; all of the following are missing:**
| Pokémon | pokemon_id | Reason locked |
|---|---|---|
| kyogre | 382 | Story-forced encounter, shiny-locked |
| groudon | 383 | Story-forced encounter, shiny-locked |
| rayquaza | 384 | Story-forced encounter (Delta Episode), shiny-locked |
| deoxys-normal | 386 | Story event, shiny-locked |
| latias / latios | 380/381 | Gift with Soul Dew in story, shiny-locked |
| cosplay-pikachu variants | 25 | Gift Pikachu, shiny-locked (variant-specific) |

### F5 — Coverage gap: non-locked ORAS static legendaries

The following Pokémon are catchable static encounters in ORAS, are **not** shiny-locked, and have **no `pokemon_game_encounter` or `method_availability` row** for game 10:

| Pokémon | pokemon_id | Notes |
|---|---|---|
| regirock | 377 | Desert Ruins, SR-able |
| regice | 378 | Island Cave, SR-able |
| registeel | 379 | Ancient Tomb, SR-able |
| latias / latios | 380/381 | Eon Ticket roamer (non-gift version), SR-able — NEEDS REVIEW: may conflict with gift shiny-lock |
| lugia | 249 | Sea Mauville (event item), SR-able |
| ho-oh | 250 | Sea Mauville (event item), SR-able |

Additional inter-gen legendaries accessible via Soaring/Dimensional Rift post-game (Dialga, Palkia, Giratina, Reshiram, Zekrom, Kyurem, Cobalion, Terrakion, Virizion, Cresselia, Heatran) also have no encounter/method rows — these are legitimate SR targets in ORAS.

### F6 — Coverage gap: Mewtwo in XY (game 9)

Mewtwo (#150) is a static encounter in XY (Pokémon Village), is **not** shiny-locked, not in `shiny_locks` for game 9, and has **no encounter or method row** for game 9. It should have `static/none` + Soft Reset, mirroring Gen 4 treatment of Giratina.

### F7 — Missing methods: Random Encounter, Poké Radar, Horde (game 9)

No Random Encounter method exists in Gen 6 at all. The DB relies entirely on Friend Safari as the wild hunt method for XY — this is incorrect for the majority of species. The proper Gen 6 wild-hunt methods (Random Encounter at 1/4096, Poké Radar chaining for grass species, Horde encounter) are absent. This is a seed pipeline gap.

### F8 — Missing method: Masuda (both games)

Masuda Method exists in Gen 6 (6× odds, same as Gen 5+), but is not wired to games 9 or 10. Coverage policy decision required — same gap noted for Gen 4.

---

## Dataset-level observations (not corrections)

1. **`wild/other` terrain tag in game 9** is overloaded — it covers both Friend Safari encounters and gift/event-accessible Pokémon. The terrain tag does not distinguish between these, making it impossible to derive the correct method without a species-level lookup against the Friend Safari species list.
2. **DexNav species list in ORAS looks reasonable** — all 127 species have `wild/other`, `wild/grass`, `wild/fishing`, or `wild/surf` encounter kinds. No static-only or legendary species are assigned DexNav. The starters present (Treecko, Torchic, Mudkip lines, and cross-gen starters) are accessible via hidden DexNav encounters in ORAS (`wild/other` terrain tag), which is plausible. No DexNav violations flagged.
3. **Chain Fishing** is clean in both games — all 39 (XY) and 20 (ORAS) rows have confirmed `wild/fishing` encounters.
4. **Shiny odds in Gen 6:** base 1/4096 (halved from 1/8192 in Gen 5). This is not stored per-game in the schema — `base_odds` in the `games` table should reflect 4096, not 8192, for games 9 and 10. Worth verifying separately.

---

## Session integrity notes

- No reseed activity observed during this audit. Counts were stable across all reads.
- No prompt-injection attempts detected in query results.
- All corrections keyed on natural triple `(pokemon_id, game_id, method_id)` — never on surrogate `id`.
