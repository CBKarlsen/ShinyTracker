# Shiny-Hunt Method Audit — All Generations (Cross-Gen Summary)

**Date:** 2026-05-31 · **Scope:** all 17 games / 9 generations · **Read-only** (no DB writes).
**Coverage:** 6,877 `method_availability` rows audited = 100% of the table (4+173+301+737+516+539+698+1,640+2,269).
Per-generation detail lives in `genN_report.md` / `genN_corrections.sql` (N = 1–9). Gathering was delegated to Sonnet subagents (one per gen) to keep cost down.

> Data was **stable** throughout this audit. Earlier-session "reseed" alarms were traced to garbled MCP responses caused by firing duplicate concurrent queries — not the database changing. Running one distinct query at a time resolved it.

---

## Verdict by generation

| Gen | Games | Rows | Method mislabels | Shiny-lock errors | Coverage gaps | Headline |
|---|---|---|---|---|---|---|
| 1 | RBY | 4 | n/a | 0 | n/a | **No shinies exist in Gen 1** — all 4 SR rows are invalid (seed artifact) |
| 2 | GSC | 173 | 10 | 0 | 3 | 10 statics/gifts mislabeled Random→Soft Reset; beasts missing |
| 3 | RSE/FRLG | 301 | 152 | 0 | 8 | RSE wild rows use "Run Away" instead of Random Encounter |
| 4 | DPPt/HGSS | 737 | 0 ✅ | 0 | 8 | Clean (pilot); only DPPt legendary backfill |
| 5 | BW/B2W2 | 516 | 0 | 0 | 8+ | Masuda not wired; SR charm-bleed; 7 legendaries missing |
| 6 | XY/ORAS | 539 | structural | **9** | many | Friend Safari over-assigned to whole dex; ORAS locks absent |
| 7 | SM/USUM/LGPE | 698 | 0 | 4 (missing) | 4 | Clean methods; LGPE locks & Ultra Wormhole missing |
| 8 | SwSh/BDSP/PLA | 1,640 | ~562 | 14 | severe | "KO Method" mislabel in SwSh; BDSP under-seeded; lock errors |
| 9 | SV | 2,269 | 0 ✅ | 7 | 6 | Clean methods; lock list needs 3 removals + 4 additions |

---

## Cross-cutting root causes (fix once, fixes many)

These recurring patterns point at the **seed pipeline**, not one-off data entry — consistent with the project's known seed/sync fragility.

1. **Shiny-lock table is unreliable** — the single highest-value correctness problem.
   - *Huntable-but-locked* (Pokémon in `shiny_locks` that still have a hunt method): Xerneas, Yveltal (XY); Giratina (BDSP).
   - *Locked-but-not-recorded* (genuinely shiny-locked, missing from `shiny_locks`, some still huntable): Kyogre/Groudon/Rayquaza (ORAS — table has **zero** ORAS rows); XY gift starters + Lapras; LGPE birds + Mewtwo; 10 PLA legendaries; SV Loyal Three + Terapagos.
   - *Wrongly locked* (not actually locked): Dialga/Palkia (BDSP); archaludon/hydrapple/gouging-fire (SV).

2. **Method-in-game validity** — methods assigned to games that never had them:
   - Gen 3 RSE: "Run Away" used as the wild method (should be Random Encounter).
   - Gen 8 SwSh: "KO Method" (a Legends-Arceus mechanic) is the wild method for all 562 SwSh wild Pokémon — should be Shiny Mark/Brilliant Aura/Random.
   - (BDSP DexNav, flagged earlier, is **not** present in the current snapshot — resolved.)

3. **Masuda Method not wired** to Gens 5, 6, 7 (and sparse elsewhere) via `method_games` — breedable Pokémon can't be Masuda-hunted there despite the mechanic existing.

4. **Soft Reset shares one method row with `charm_rolls=2`** across all 17 games. The Shiny Charm doesn't exist before Gen 5 (and only B2W2 in Gen 5), so this inflates odds for every pre-charm static hunt. Needs a no-charm variant. (Odds concern — out of strict method-correctness scope, but pervasive.)

5. **"wild/other" encounter bucket is overloaded** — gifts, static blockers, headbutt trees and indoor encounters all share it, so the "wild → Random" derivation mislabels statics/gifts (drives the Gen 2 & Gen 3 mislabels).

6. **Severe under-seeding in spots** — BDSP (game 15) has only 9 Pokémon with encounter rows (<3% coverage); Random Encounter is entirely absent from Gen 6 and from SM/USUM; many legendaries lack encounter+method rows across Gens 2/3/5/6/7/9.

7. **Missing methods in the catalog** — Ultra Wormhole (Gen 7 USUM legendary hunt) doesn't exist in `hunt_methods` at all.

---

## What's genuinely clean
- **Gen 4** (the pilot) — 0 method mislabels.
- **Gen 9 method assignments** — 0 mislabels (only lock-table fixes).
- **PLA (Gen 8) method rows** — all 224 Mass Outbreak rows valid.
- **Gen 7 structural checks** — 0 violations (gaps only).

---

## Suggested priority order for fixes
1. **Shiny-lock corrections** (root cause 1) — small, high-confidence, directly user-visible; per-gen `corrections.sql` files have the safe DELETE/INSERTs. Do this first.
2. **Method-in-game mislabels** (root cause 2) — Gen 3 "Run Away" and Gen 8 "KO Method" remaps; these are method_games/catalog rename decisions, best done in the seed source.
3. **Seed-pipeline structural fixes** (roots 2–6) — Friend Safari restriction, Masuda wiring, charm-roll split, "wild/other" disambiguation, BDSP reseed. These belong in the seed data/code, **not** ad-hoc SQL, because re-seeds regenerate these tables.
4. **Coverage backfills** — legendaries missing encounter+method rows; do via seed source.

⚠️ **Apply nothing blind.** Every `corrections.sql` is keyed on the natural triple `(pokemon_id, game_id, method_id)` and idempotent, but the durable fixes for roots 2–6 belong in the seed pipeline since re-seeding will overwrite manual SQL. Review per-gen files before running anything.
