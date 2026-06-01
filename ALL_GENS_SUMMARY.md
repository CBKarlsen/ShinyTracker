# Shiny-Hunt Method Audit & Remediation — All Generations

**Scope:** all 17 games / 9 generations. **Read-only audit → seed-source fixes → verified via live re-seed.**
Branch: `chore/method-data-audit`. Per-gen audit detail in `genN_report.md`; original one-off fix specs in `genN_corrections.sql` (superseded where noted below).

> Status legend: ✅ accurate · ◑ partially fixed (gaps remain) · ❌ known-wrong / open · ⏸ not yet audited

---

## What was fixed and verified this session

1. **Shiny-locks — corrected & completed across all games.** Removed false positives (BDSP Dialga/Palkia/Giratina; SV Archaludon/Hydrapple), added missing locks (ORAS K/G/R+Deoxys; LGPE birds+Mewtwo; 10 PLA legendaries; SV Loyal Three/Terapagos/Treasures of Ruin/event+Indigo-Disk Paradoxes; XY roaming birds; SwSh Glastrier/Spectrier). All verified against Bulbapedia.
2. **Systemic lock enforcement.** `computeAvailability` now excludes any `(pokemon, game)` in `shiny_locks`; `cmd/seed` self-seeds locks before deriving; invariant guard asserts zero huntable-but-locked. Retired the per-case `method_exceptions` workaround.
3. **Gen 3 RSE** wild method remapped off the bogus "Run Away" onto real Random Encounter.
4. **Masuda Method** wired for Gen 5/6/7 (961 rows; BW charm_rolls=0, others=2; LGPE correctly excluded) + fixed a latent egg-derivation ordering bug.
5. **Friend Safari (XY)** de-bloated 348→185 (real FS species only) with Random Encounter + Poké Radar restored for the rest of the Kalos dex.
6. **BDSP** seeded from ~9 → 325 huntable species (full national-dex availability, DPPt-proxy wild + Grand Underground, Random/Poké Radar/Soft Reset/Masuda, 12 static legendaries).

`method_availability`: 6,877 → **9,011**, fully reproducible from a clean seed.

---

## Current per-generation status

| Gen | Game(s) | Methods | Shiny-locks | Status |
|---|---|---|---|---|
| 1 | RBY | Soft Reset (4 rows) | n/a | ❌ Shinies don't exist in Gen 1 — these 4 rows are bogus; RBY should be non-huntable. |
| 2 | GSC | Random, Soft Reset | ✅ (none needed) | ◑ ~10 gift/static species still mislabeled Random instead of Soft Reset (Eevee, starters, Snorlax, Lapras…); legendary beasts missing. |
| 3 | RSE / FRLG | Random, Soft Reset | ✅ | ◑ "Run Away" mislabel fixed. Residual: some gift/fossil statics still Random; a few legendary coverage gaps (Regis/Lati@s/beasts). |
| 4 | DPPt / HGSS | Poké Radar, Random, Soft Reset | ✅ | ✅ Clean (pilot). DPPt legendary statics now covered. |
| 5 | BW / B2W2 | Masuda, Random, Soft Reset | ✅ | ◑ Masuda complete. Residual: not all Unova static legendaries have Soft Reset; SR charm-roll bleed (odds). |
| 6 | XY | Chain Fishing, Friend Safari, Masuda, Poké Radar, Random | ✅ | ✅ Friend Safari fixed; full method set. |
| 6 | ORAS | Chain Fishing, DexNav, Masuda | ✅ | ◑ **No Random Encounter, no Soft Reset** — ORAS legendaries (Regis etc.) and non-DexNav species lack a route. |
| 7 | SM / USUM | Masuda, SOS Chaining | ✅ | ❌ **No Random Encounter, no Soft Reset.** Non-SOS species + static legendaries/Ultra Beasts have no hunt route. Ultra Wormhole method absent from catalog. |
| 7 | LGPE | Catch Combo | ✅ | ✅ Correct. |
| 8 | SwSh | Dynamax Adventures, KO Method, Masuda, Run Away | ✅ | ✅ "KO Method" verified legitimate (catch-count rerolls). |
| 8 | BDSP | Masuda, Poké Radar, Random, Soft Reset | ✅ | ✅ Fully seeded this session. |
| 8 | PLA | Mass Outbreak | ✅ (all legendaries locked) | ✅ Correct. |
| 9 | SV | Mass Outbreak, Masuda, Random, Sandwich | ✅ | ✅ Methods valid, locks accurate, 0 huntable-but-locked. |
| — | all | — | — | ⏸ **Odds unverified** (base_odds × base_rolls × charm_rolls). Methods-only audit; odds were the deferred phase. |

---

## Remaining work (prioritized)

1. **Gen 7 SM/USUM** — add Random Encounter + Soft Reset (static legendaries/UBs); consider an Ultra Wormhole method. *Biggest method gap.*
2. **Gen 6 ORAS** — add Random Encounter + Soft Reset for legendaries.
3. **Gen 2 / Gen 3** — fix the "wild/other"-driven gift/static mislabels (move to `legendary_encounters.json` static) and backfill missing legendaries. Root cause is the overloaded `wild/other` encounter bucket in the PokeAPI mapper.
4. **Gen 1** — exclude RBY from hunting (drop the 4 Soft Reset rows; no shiny mechanic exists).
5. **Odds verification phase** — validate `base_odds`/`base_rolls`/`charm_rolls` per method/game, incl. the Soft Reset `charm_rolls=2` bleed for pre-Gen-5 games (Shiny Charm didn't exist until Gen 5/B2W2).
6. **Minor:** PokeAPI gives ~5 XY Friend-Safari species spurious grass-route encounters (encounter-data accuracy, not logic). RLS still disabled on all tables (security advisory).

---

## Process notes
- All durable fixes live in the **seed source** (`backend/seeds/*.json`, `cmd/seed`, `cmd/seed_availability_legacy`) — a re-seed regenerates `method_availability`/`pokemon_game_encounter`/`shiny_locks` deterministically, so SQL-only patches would be wiped.
- Run order: `cmd/seed_availability_legacy` → `cmd/seed` (now self-seeds shiny_locks before deriving). The `friend_safari` terrain required a one-time `ALTER` on the live DB (applied).
- Audit gathering was delegated to per-gen subagents; domain claims were verified against Bulbapedia/Serebii, and two sub-agent findings were caught and corrected on review (XY starters *not* locked; Treasures of Ruin *are* locked).
