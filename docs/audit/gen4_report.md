# Gen 4 Method Verification — Pilot Report

**Scope:** Generation 4 only — Diamond/Pearl/Platinum (`game_id=5`) and HeartGold/SoulSilver (`game_id=6`). BDSP excluded (Gen 8). Read-only; no database writes performed.
**Date:** 2026-05-31
**Verified against:** Bulbapedia (primary), Serebii / PokémonDB (secondary).

> ℹ️ Data gathering was delegated to a Sonnet subagent to keep the orchestrator's context (and token cost) lean. Findings reflect a **stable Gen 4 snapshot** taken after the reseed sources were closed (verified identical across repeated reads). Note: other generations were still being written during the audit — **fully quiesce seeding before auditing Gens 1–3, 5–9.**

---

## Summary

| Metric | Value |
|---|---|
| Rows checked (method_availability, Gen 4) | **737** (DPPt 512 / HGSS 225) |
| Distinct Pokémon | DPPt 288 / HGSS 225 |
| Distinct rules verified | **4** (+ 1 shiny-lock exception) |
| Method **mislabels** found | **0** ✅ |
| Coverage **gaps** found | **1** (8 DPPt static legendaries missing a hunt method) |

**Bottom line: every assigned Gen 4 method is correct.** The only issue is missing rows for 8 DPPt legendaries (suggested INSERTs in `gen4_corrections.sql`, clearly separated — they *add* coverage rather than fix an error).

### Method mix (stable snapshot)
| game | Random Encounter | Poké Radar | Soft Reset | Masuda |
|---|---|---|---|---|
| DPPt (5) | 287 | 224 | 1 | 0 |
| HGSS (6) | 220 | 0 | 5 | 0 |

Poké Radar correctly appears only in DPPt. ✓

---

## Schema reading (Phase 1)

No single "encounters" table. The method assignment under audit lives in **`method_availability(id, pokemon_id, method_id, game_id)`** — one row = "this Pokémon can be shiny-hunted with this method in this game."

| Concept | Where it lives |
|---|---|
| Species | `pokemon(id, name, can_breed, is_legendary, is_mythical, evolves_from_id)` |
| Game / version | `games(id, title, generation, base_odds)` — Gen 4 = `5` DPPt, `6` HGSS |
| Method | `hunt_methods(method_name, base_rolls, charm_rolls, requires_kind, requires_terrain)` |
| Encounter type | `pokemon_game_encounter(pokemon_id, game_id, kind ∈ wild/static/raid/egg, terrain ∈ grass/surf/fishing/other/none)` |
| Odds inputs | `hunt_methods.base_rolls / charm_rolls` + `games.base_odds` (8192 for Gen 4) |
| Location | **Not stored** — only `kind`/`terrain` abstractions exist |
| Shiny locks | `shiny_locks(pokemon_id, game_id)` — **empty for Gen 4** |

Gen 4 method IDs (verified): DPPt — Poké Radar `163`, Random Encounter `164`, Soft Reset `178`; HGSS — Random Encounter `164`, Soft Reset `178`.

---

## Rules verified (once each, reused across rows)

| # | Rule | Verdict | Source |
|---|---|---|---|
| R1 | **Poké Radar** works only in tall grass; **not** surf, fishing, or caves; DPPt-only | Confirmed — no violations in DB | [Bulbapedia: Poké Radar](https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9_Radar) |
| R2 | **Random Encounter / full odds** (1/8192) for wild grass/surf/fishing with no special method | Confirmed | [Bulbapedia: Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon) |
| R3 | **Soft Reset** for static/gift/legendary; Gen 4 legendaries are **not** shiny-locked (locking began Gen V) | Confirmed | [Bulbapedia: Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon); [PokémonDB](https://pokemondb.net/pokebase/126011/which-legends-are-shiny-locked) |
| R4 | **Masuda Method** valid in Gen 4 for breeding-obtainable Pokémon only | Confirmed | [Bulbapedia: Masuda method](https://bulbapedia.bulbagarden.net/wiki/Masuda_method) |
| R3-exc | Event mythicals (Darkrai, Shaymin, Arceus, Mew, Manaphy…) are shiny-**unobtainable** in Gen 4 | Confirmed — **correctly have no huntable method** in the DB | [Bulbapedia: Unobtainable Shiny list](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |
| R5 | **Red Gyarados** (Lake of Rage, HGSS) is a **guaranteed shiny**, not a hunt | Verified — **not mislabeled** (HGSS Gyarados = normal wild Random Encounter, correct) | [Bulbapedia: Red Gyarados](https://bulbapedia.bulbagarden.net/wiki/Red_Gyarados) |

---

## Verification results

### Method mislabels: none
All three rule categories returned **zero** rows on the stable snapshot:
- **Poké Radar on non-grass** — 0 (all 224 DPPt Radar rows have a `wild`+`grass` encounter).
- **Masuda on non-breedable** — 0 (Masuda isn't assigned in Gen 4 at all — see observations).
- **Random Encounter on a static-only Pokémon** — 0.

Spot-confirmations: Magikarp (#129) and Gyarados (#130) are on **Random Encounter** in both games (the earlier Poké-Radar reading was a transient reseed artifact). The nine event mythicals (Mew, Celebi, Jirachi, Deoxys, Phione, Manaphy, Darkrai, Shaymin, Arceus) have **no** `method_availability` row in games 5/6 — correct.

### Coverage gap (1) — `NEEDS REVIEW` → suggested INSERTs

In DPPt, only **Giratina** carries a Soft Reset entry. These 8 catchable static legendaries have **no hunt method** despite a `static` encounter and not being shiny-locked in Gen 4:

| Pokémon | Game | Encounter | Current method | Should be | Source |
|---|---|---|---|---|---|
| uxie (480) | DPPt | static / none | (none) | Soft Reset | R3 |
| mesprit (481) | DPPt | static / none | (none) | Soft Reset | R3 |
| azelf (482) | DPPt | static / none | (none) | Soft Reset | R3 |
| dialga (483) | DPPt | static / none | (none) | Soft Reset | R3 |
| palkia (484) | DPPt | static / none | (none) | Soft Reset | R3 |
| heatran (485) | DPPt | static / none | (none) | Soft Reset | R3 |
| regigigas (486) | DPPt | static / none | (none) | Soft Reset | R3 |
| cresselia (488) | DPPt | static / none | (none) | Soft Reset | R3 |

The asymmetry with Giratina (which *does* have Soft Reset) strongly suggests an unintentional seeding gap. **The gap is at the encounter level** — these 8 have no `pokemon_game_encounter` row for DPPt at all (Giratina has `static/none`), so a backfill must add the static encounter row *and* the Soft Reset method row. Because `method_availability` is regenerated on every re-seed, **the durable fix belongs in the seed source (CSV / seeds JSON), not ad-hoc SQL.** `gen4_corrections.sql` provides idempotent INSERTs for both tables as a reference / one-off, with that caveat noted inline.

---

## Dataset-level observations (not corrections)

1. **No Masuda Method wired to Gen 4.** `method_games` maps only Poké Radar/Random/Soft Reset to games 5–6, so no breedable Pokémon can be Masuda-hunted in Gen 4 even though Gen 4 introduced the method. Coverage policy to decide before scaling.
2. **Soft Reset method carries `charm_rolls=2`.** The Shiny Charm doesn't exist until Gen 5 — irrelevant to method correctness, but relevant when you compute odds.
3. **RLS disabled on all 13 tables** (Supabase advisory) — anyone with the anon key can read/write every row. Plausibly how the earlier uncontrolled reseeds reached the DB. Worth fixing before exposure.

---

## Session integrity notes (earlier in session, resolved for Gen 4)

- **Reseed loop:** a truncate-and-reseed ran repeatedly mid-session, renumbering serial PKs and churning method assignments (counts swung 771→737, PK floor drifted, the whole method mix flipped between reads). It produced spurious intermediate "flags" that the final stable snapshot does not corroborate. After you closed the reseed sources, **Gen 4 stabilised** and this report reflects that state.
- **Surrogate `id` is not a safe key:** `id`↔Pokémon associations shuffled between identical reads. Any future corrections should key on `(pokemon_id, game_id, method_id)`, idempotently.
- **Prompt-injection attempts:** three fake "out-of-band user feedback" blobs arrived embedded in Supabase query output, pushing unconfirmed bulk writes across all gens. **Not executed.** (None in the final re-audit.)

---

## Recommendation before scaling to Gens 1–9
1. Fully quiesce the seed/sync job (other gens still being written).
2. Decide whether to backfill the 8 DPPt legendary encounters + Soft Reset rows (the only Gen 4 action item) — ideally via the seed source so it survives re-seeds.
3. Decide the Masuda-coverage policy for Gen 4+.
4. Run any DB work only against a confirmed-stable snapshot; key on the natural triple, never `id`.
