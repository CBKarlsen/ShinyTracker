# Gen 1 Method Verification — Audit Report

**Scope:** Generation 1 only — Red/Blue/Yellow (`game_id=1`). Read-only; no database writes performed.
**Date:** 2026-05-31
**Verified against:** Bulbapedia (primary), PokémonDB (secondary).

---

## Summary

| Metric | Value |
|---|---|
| Rows checked (method_availability, Gen 1) | **4** |
| Distinct Pokémon | **4** |
| Distinct methods | **1** (Soft Reset, method_id=178) |
| Method **mislabels** found | **0** (at face value — see decisive rule below) |
| Coverage **gaps** found | **0** |
| **Conceptual validity of all 4 rows** | **INVALID** — shiny Pokémon do not exist in Generation 1 |

**Bottom line: the 4 method_availability rows for game_id=1 are technically consistent with the encounter data (static encounters → Soft Reset), but they are fundamentally incorrect because shininess as a mechanic did not exist in Red/Blue/Yellow.** Soft-Resetting in RBY cannot produce a shiny Pokémon. All 4 rows should be removed (see recommendation).

---

## The Decisive Rule — Shiny Pokémon Are a Gen 2 Invention

> "Shiny Pokémon were introduced in Generation II."
> — [Bulbapedia: Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon)

In Red, Blue, and Yellow, individual Pokémon have no shiny status. The shiny mechanic is encoded in the IVs / DVs of a Pokémon, a concept that only became meaningful when Gold and Silver introduced the display logic for it in 1999. Soft-resetting a legendary encounter in RBY yields no shiny outcome whatsoever — the concept does not exist in the game engine.

This is not a borderline case or a regional exception; it is an absolute, generation-wide rule with zero exceptions. There is no in-game shiny hunt possible in Generation 1.

Source: [Bulbapedia — Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon) ("Shiny Pokémon were introduced in Generation II.")

---

## Schema Reading (Phase 1)

| Concept | Where it lives |
|---|---|
| Species | `pokemon(id, name, can_breed, is_legendary, is_mythical, evolves_from_id)` |
| Game / version | `games(id, title, generation, base_odds)` — Gen 1 = `1` (Red/Blue/Yellow) |
| Method | `hunt_methods(id, method_name, requires_kind, requires_terrain)` |
| Encounter type | `pokemon_game_encounter(pokemon_id, game_id, kind ∈ wild/static/raid/egg, terrain ∈ grass/surf/fishing/other/none)` |
| Method routing | `method_games(method_id, game_id)` — only method_id=178 (Soft Reset) mapped to game_id=1 |
| Shiny locks | `shiny_locks(pokemon_id, game_id)` — **empty for Gen 1** (0 rows) |

Gen 1 method ID in use: Soft Reset = `178`.

Note: `shiny_locks` being empty for game_id=1 does not mean shinies are obtainable here — it means the lock table was never populated for this generation, presumably because the seed logic assumed Gen 1 would be excluded once the conceptual rule was applied.

---

## Actual Data State (Confirmed)

The brief estimated ~190 Random Encounter rows for game_id=1. The actual stable snapshot contains **4 rows only**:

### method_availability rows for game_id=1

| id | pokemon_id | name | is_legendary | method_id | method_name |
|---|---|---|---|---|---|
| 46716 | 144 | articuno | true | 178 | Soft Reset |
| 44366 | 145 | zapdos | true | 178 | Soft Reset |
| 40632 | 146 | moltres | true | 178 | Soft Reset |
| 41451 | 150 | mewtwo | true | 178 | Soft Reset |

### How these rows arose

`pokemon_game_encounter` for game_id=1 contains `static/none` rows for pokemon_id 144, 145, 146, and 150 — the three legendary birds and Mewtwo. The seed pipeline's rule "static encounter → Soft Reset method" fired correctly by its own logic, producing these 4 rows. The pipeline simply has no guard for the Gen 1 shiny-impossibility rule.

No other Pokémon in `pokemon_game_encounter` for game_id=1 carries a `static` encounter kind; wild/grass/surf/fishing/egg entries for other Gen 1 species do not map to any method in `method_games` for game_id=1, so they produce no `method_availability` rows.

The `method_games` table maps only Soft Reset (178) to game_id=1 — Random Encounter is not wired to Gen 1, which explains why the earlier estimate of ~190 Random Encounter rows was incorrect.

---

## Option Analysis — Two Paths Forward

### Option A: Delete all game_id=1 method rows + exclude RBY from hunting (RECOMMENDED)

Remove the 4 `method_availability` rows for game_id=1. Optionally also remove the `pokemon_game_encounter` static rows (pokemon_id 144/145/146/150, game_id=1) and unmap Soft Reset from `method_games` for game_id=1 to prevent re-seeding from regenerating them.

**Pros:**
- Correct. A user cannot shiny-hunt in RBY — presenting Soft Reset for Articuno implies otherwise.
- Prevents confusing UI states (e.g., a hunt card showing "Soft Reset — Red/Blue/Yellow" with odds of 1/8192, which is meaningless).
- Aligns with how every major Pokémon resource (Bulbapedia, Serebii, Smogon) describes Gen 1.

**Cons:**
- If the app supports Living Dex tracking for Pokémon obtained via trade or Pal Park transfer from later gens, Gen 1 species could be "sourced" from RBY but would need to be logged under a later-gen hunt. This is a mild UX nuance, not a reason to keep invalid hunt methods in Gen 1.

### Option B: Keep rows but relabel them as "Transfer / Trade" acquisition only

Retain game_id=1 entries but strip the Soft Reset hunt method and replace with a non-hunt acquisition type (e.g., `TRADED` or `MANUAL_OVERRIDE` in `user_hunts.acquisition_type`). The game would appear in the Living Dex game selector but with no huntable methods.

**Pros:**
- Preserves Gen 1 as a game-of-origin for transfer tracking.

**Cons:**
- Requires UI work to differentiate "no hunt possible" from "no method seeded yet."
- The 4 Soft Reset rows still need to be deleted regardless.
- Adds complexity for an edge case (transfer-tracking is already handled by `acquisition_type`).

### Recommendation: Option A

Delete the 4 rows and prevent re-seeding. Shiny hunting in Gen 1 is not a real activity; the rows are a seeding artefact. If Living Dex trade/transfer tracking for Gen 1 Pokémon is needed, that is best handled through the existing `acquisition_type` mechanism (TRADED / MANUAL_OVERRIDE) on `user_hunts`, not by keeping method rows for a generation where shininess is mechanically impossible.

---

## Verification Results

### Method mislabels: 0 (but all 4 rows are conceptually invalid)

At the schema level, each row correctly follows the seeding rule: static encounter → Soft Reset. There are no wrong method types relative to encounter kinds within the Gen 1 data itself. The error is upstream: the game should not have any huntable methods at all.

### Coverage gaps: 0

No Pokémon that should have a method is missing one. Mew (pokemon_id=151) has no `pokemon_game_encounter` row for game_id=1 and correctly has no `method_availability` row.

---

## Dataset-Level Observations (Not Corrections)

1. **`games.base_odds = 8192` for game_id=1.** The odds field is populated even though no shiny hunt is valid. Harmless unless the odds-display UI reads it for Gen 1 hunts — which, after Option A is applied, it will never do.
2. **`shiny_locks` empty for Gen 1.** This table being empty is not wrong per se (it is designed to flag specific Pokémon in games where shinies *do* exist but certain species are locked). It does not need populating; the correct fix is removing the method rows entirely.
3. **Seed pipeline has no generation guard.** The rule "static encounter → Soft Reset" fires for Gen 1 without checking whether shininess is possible in that generation. A simple `WHERE g.generation > 1` guard in the method-seeding query would prevent this class of error from recurring.
4. **RLS disabled on all audited tables** (noted from Gen 4 audit; still applicable). See Gen 4 report for details.

---

## Recommendation Before Taking Action

1. Confirm the 4 rows are a seeding artefact and not an intentional product decision (e.g., "show Gen 1 for transfer documentation purposes").
2. If confirmed artefact: run the `gen1_corrections.sql` NEEDS-REVIEW block (after the owner approves it), then add a generation > 1 guard to the seed pipeline so it does not regenerate on the next run.
3. No other Gen 1 action items exist — there are no mislabels, no coverage gaps among valid rows, and no shiny-lock entries needed.
