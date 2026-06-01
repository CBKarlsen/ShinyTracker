# Gen 5 Method Verification Report

**Scope:** Generation 5 only — Black/White (`game_id=7`) and Black 2/White 2 (`game_id=8`). Read-only; no database writes performed.
**Date:** 2026-05-31
**Verified against:** Bulbapedia (primary), Serebii / PokémonDB (secondary).

---

## Summary

| Metric | Value |
|---|---|
| Rows checked (method_availability, Gen 5) | **516** (BW 236 / B2W2 280) |
| Distinct Pokémon | BW 236 / B2W2 280 |
| Distinct rules verified | **5** (+ 1 structural / schema observation) |
| Method **mislabels** found | **1** (Soft Reset charm_rolls bleed-through into BW — structural) |
| Coverage **gaps** found | **2** (SR: 9 static legendaries missing; Masuda: 0 method rows in either game) |

**Bottom line:** The two assigned Random Encounter method IDs are correct (charm split is right). Soft Reset is structurally misconfigured — method 178 carries `charm_rolls=2` but is shared across all games including those without the Shiny Charm (BW has no Shiny Charm; B2W2 does). The Masuda Method is entirely absent from both Gen 5 games despite Gen 5 being the generation that boosted Masuda to 6× — 232 breedable Pokémon in BW and 272 in B2W2 have no Masuda row. Nine static legendaries lack both encounter rows and SR method rows.

### Method mix (stable snapshot)
| game | Random Encounter | Soft Reset | Masuda |
|---|---|---|---|
| BW (7) | 234 | 2 | 0 |
| B2W2 (8) | 278 | 2 | 0 |

---

## Schema reading (Phase 1)

Same schema as Gen 4 (confirmed). Key tables:

| Concept | Where it lives |
|---|---|
| Species | `pokemon(id, name, can_breed, is_legendary, is_mythical, evolves_from_id)` |
| Game / version | `games(id, title, generation, base_odds)` — Gen 5 = `7` BW, `8` B2W2 |
| Method | `hunt_methods(id, method_name, base_rolls, charm_rolls, requires_kind, requires_terrain)` |
| Encounter type | `pokemon_game_encounter(pokemon_id, game_id, kind ∈ wild/static/egg, terrain)` |
| Method→game mapping | `method_games(method_id, game_id)` — controls which methods appear per game |
| Shiny locks | `shiny_locks(pokemon_id, game_id)` — empty for Gen 5 (see findings) |

**Gen 5 method IDs (verified):**
| game_id | Method | method_id | base_rolls | charm_rolls |
|---|---|---|---|---|
| 7 (BW) | Random Encounter | 165 | 1 | **0** ✓ |
| 7 (BW) | Soft Reset | 178 | 1 | **2** ✗ (no charm in BW) |
| 8 (B2W2) | Random Encounter | 166 | 1 | 2 ✓ |
| 8 (B2W2) | Soft Reset | 178 | 1 | 2 ✓ |

---

## Rules verified (once each, reused across rows)

| # | Rule | Verdict | Source |
|---|---|---|---|
| R1 | **Random Encounter** (1/8192) for wild encounters; no Shiny Charm in BW (method 165, charm_rolls=0), Shiny Charm in B2W2 (method 166, charm_rolls=2) | Confirmed — split is correct | [Bulbapedia: Shiny Charm](https://bulbapedia.bulbagarden.net/wiki/Shiny_Charm) |
| R2 | **Soft Reset** for static/legendary encounters | Confirmed correct in principle; see S1 for charm flaw | [Bulbapedia: Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon) |
| R3 | **Reshiram & Zekrom are NOT shiny-locked** in Black/White — SR is valid | Confirmed ✓ (both have static encounter + SR in both games) | [Bulbapedia: List of unobtainable Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |
| R4 | **Masuda Method exists in Gen 5** (boosted to 6× in Gen 5 from 5× in Gen 4); valid for breedable Pokémon only | Confirmed — but entirely absent from method_games for games 7/8 | [Bulbapedia: Masuda method](https://bulbapedia.bulbagarden.net/wiki/Masuda_method) |
| R5 | **Gen 5 shiny lock list** (Bulbapedia): Reshiram/Zekrom are NOT locked in BW/B2W2 (SR-able); Kyurem is NOT locked (SR-able); Cobalion/Terrakion/Virizion/Tornadus/Thundurus/Landorus are NOT locked (SR-able); Victini IS event-locked (Liberty Garden event Victini is shiny-locked); event mythicals Keldeo/Meloetta/Genesect are event-distributed and shiny-locked in distribution, not in-game huntable | Confirmed — no conflicting rows in DB | [Bulbapedia: List of unobtainable Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |

---

## Verification results

### Mislabels / structural issues

#### S1 — Soft Reset carries charm_rolls=2 in BW (no Shiny Charm exists in BW)

Method 178 (Soft Reset) is a **single shared method row** used by all games 1–12, 14, 15, 17. Its `charm_rolls=2` was presumably set for games that have the Shiny Charm, but it bleeds into every pre-Shiny-Charm game including BW.

The Random Encounter design **correctly** avoids this problem by using two separate method IDs: 165 (charm_rolls=0) for BW and 166 (charm_rolls=2) for B2W2. Soft Reset has no equivalent split — method 178 is a single row shared by both.

**Impact:** When the odds calculator applies charm_rolls to BW Soft Reset hunts (Reshiram/Zekrom in game 7), it will show inflated odds. With the Shiny Charm equipped, the app would incorrectly calculate ~1/2731 instead of 1/8192 for BW SR hunts.

**Note:** This is a cross-generational schema issue — the same problem affects every game prior to Gen 6 (when the Shiny Charm was introduced) that uses method 178. The Gen 5 audit surfaces it clearly because BW (no charm) and B2W2 (has charm) are adjacent games using the same SR method.

**Suggested fix:** Add a no-charm Soft Reset method row (base_rolls=1, charm_rolls=0) and wire it to pre-charm games via method_games, mirroring the Random Encounter split. See `gen5_corrections.sql` section A.

---

### Coverage gaps

#### C1 — Nine static legendaries missing encounter rows and SR method rows

Only Reshiram (643) and Zekrom (644) have `pokemon_game_encounter` rows and `method_availability` rows in Gen 5. Nine additional static legendaries are in-game catchable and shiny-huntable via Soft Reset but have neither an encounter row nor a method row:

| Pokémon | id | Available in | SR-able? | Lock status | Notes |
|---|---|---|---|---|---|
| Cobalion | 638 | BW + B2W2 | Yes | Not locked | Static in Mistralton Cave (BW) / same (B2W2) |
| Terrakion | 639 | BW + B2W2 | Yes | Not locked | Static in Victory Road |
| Virizion | 640 | BW + B2W2 | Yes | Not locked | Static in Pinwheel Forest / Rumination Field |
| Tornadus (Incarnate) | 641 | BW only | Yes | Not locked | Roaming in BW; SR with Liberty Ticket trigger |
| Thundurus (Incarnate) | 642 | BW only | Yes | Not locked | Roaming in BW |
| Kyurem | 646 | BW + B2W2 | Yes | Not locked | Static in Giant Chasm |
| Landorus (Incarnate) | 645 | BW + B2W2 (unlockable) | Yes | Not locked | Requires Tornadus + Thundurus at Abundant Shrine (B2W2 via transfer) |
| Victini | 494 | BW (event Liberty Garden) | No | **Shiny-locked** — Liberty Garden Victini is shiny-locked in all distributions | Should NOT get a SR row |
| Keldeo / Meloetta / Genesect | 647/648/649 | Event only | No | Shiny-locked in all Gen 5 distributions | Should NOT get SR rows |

**Gap count:** 7 SR-able static legendaries have zero encounter or method rows (Cobalion, Terrakion, Virizion, Tornadus, Thundurus, Kyurem, Landorus). Victini and the three event mythicals are intentionally absent.

**Note on Tornadus/Thundurus:** These are roaming Pokémon in BW — they appear in the overworld and trigger a random battle rather than a fixed static battle. The `kind='static'` label is a slight approximation, but SR is still the canonical hunt method (start the game → trigger the encounter → reset if not shiny). Including them as `static/none` is consistent with how Cresselia/Mesprit were modeled in Gen 4.

**Note on Landorus:** Available in B2W2 via the Abundant Shrine after transferring Tornadus + Thundurus via Poké Transfer. Only relevant for game 8.

See `gen5_corrections.sql` section C for suggested encounter + SR method INSERTs.

#### C2 — Masuda Method entirely absent from Gen 5

No Masuda method is wired to game 7 or game 8 via `method_games`. Existing Masuda method rows (ids 162, 172) are mapped only to games 14/15 (Sword/Shield, BDSP) and 17 (Scarlet/Violet) — all Gen 8+.

Gen 5 introduced the boosted Masuda rate (6× from Gen 5 onward; Gen 4 was 5×). Both BW and B2W2 support Masuda.

**Shiny Charm note:** The existing Masuda method rows both carry `charm_rolls=2`. The same charm-split problem as SR applies: a BW Masuda method should use charm_rolls=0; a B2W2 Masuda method can use charm_rolls=2. The correct approach is a pair of Masuda method IDs — one per game — mirroring the Random Encounter split.

**Scale of gap:**
| game | Breedable Pokémon with any method row | Missing Masuda rows |
|---|---|---|
| BW (7) | 232 | 232 |
| B2W2 (8) | 272 | 272 |

This is a policy/seeding decision. `gen5_corrections.sql` section C2 provides the method_games wiring needed once the correct Masuda method IDs (no-charm for game 7, charm for game 8) are established. The mass `method_availability` INSERT for 232+272 Pokémon is flagged as NEEDS REVIEW and not provided as bulk SQL — it should be driven by the seed pipeline.

---

## Dataset-level observations (not corrections)

1. **Shiny_locks table is empty for Gen 5.** The DB records no shiny locks for games 7/8. This is partially correct (most Gen 5 shinies are obtainable) but Victini, Keldeo, Meloetta, and Genesect are shiny-locked in all Gen 5 distributions and should ideally have `shiny_locks` rows to prevent the UI from suggesting they are huntable. Currently they simply have no `method_availability` row — which achieves the same effect (no hunt option shown) but the intent is implicit rather than explicit.

2. **No Pokémon on Random Encounter have a static-only encounter** — zero mislabels of this type (confirmed by query).

3. **No non-breedable Pokémon are on Soft Reset** beyond the expected legendaries — zero mislabels of this type.

4. **No post-Gen-5 Pokémon appear in games 7/8** — national dex scope looks correct.

5. **Soft Reset charm_rolls=2 shared across all pre-Gen-6 games** (1–12) is a broader architectural issue surfaced by this audit. A schema fix (split method or per-game-method charm override) would benefit the entire Gen 1–5 range, not just Gen 5.

---

## Recommendation before scaling to other generations

1. Decide the **Soft Reset charm split policy** — add a no-charm SR method (charm_rolls=0) for pre-Gen-6 games, mirroring the Random Encounter split. This fixes BW Reshiram/Zekrom odds immediately and will benefit Gen 1–4 SR rows already in the DB.
2. Add **encounter + SR rows for 7 missing static legendaries** (Cobalion, Terrakion, Virizion, Tornadus, Thundurus, Kyurem, Landorus) in the appropriate games. Prefer seed source; `gen5_corrections.sql` section C provides idempotent reference SQL.
3. Decide **Masuda coverage policy for Gen 5** — wire two Masuda method IDs (no-charm for game 7, charm for game 8) via method_games, then drive the `method_availability` mass-insert from the seed pipeline.
4. Optionally add explicit `shiny_locks` rows for Victini/Keldeo/Meloetta/Genesect in games 7/8 to make the lock intent explicit rather than relying on the absence of method rows.
