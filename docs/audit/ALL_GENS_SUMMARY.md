# Shiny-Hunt Method Audit & Remediation — All Generations

**Scope:** all 17 games / 9 generations. **Read-only audit → seed-source fixes → verified via live re-seed.**
Branch: `chore/method-data-audit`. Per-gen audit detail in `genN_report.md`; original one-off fix specs in `genN_corrections.sql` (superseded where noted below).

> Status legend: ✅ accurate · ◑ partially fixed (gaps remain) · ❌ known-wrong / open · ⏸ not yet audited

---

## What was fixed and verified this session

1. **Shiny-locks — corrected & completed across all games.** Removed false positives (BDSP Dialga/Palkia/Giratina; SV Archaludon/Hydrapple), added missing locks (ORAS K/G/R+Deoxys; ~~LGPE birds+Mewtwo~~; 10 PLA legendaries; SV Loyal Three/Terapagos/Treasures of Ruin/event+Indigo-Disk Paradoxes; XY roaming birds; SwSh Glastrier/Spectrier). All verified against Bulbapedia.

   **Correction, 2026-08-15:** the LGPE entry above is wrong and the data is right. `seeds/shiny_locks.json` contains **zero** Let's Go entries, and says so explicitly: the legendary birds and Mewtwo are soft-resettable in Let's Go Pikachu/Eevee and are *not* locked there. That matches Bulbapedia. The claim here appears to have been written before the decision was walked back, and never updated — do not "fix" the seed to match this line.
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
| 1 | RBY | — | n/a | ✅ **Removed** — RBY dropped from the tracker (no shiny mechanic before Gen 2). Out of seed; `generation >= 2` guard prevents reintroduction. |
| 2 | GSC | Random, Soft Reset | ✅ | ✅ 10 gift/static mislabels fixed (Eevee/starters/Snorlax/Lapras/etc. → Soft Reset); legendary beasts added. Minor: a few lower-confidence gifts (Shuckle/Igglybuff/Porygon) left as NEEDS REVIEW. |
| 3 | RSE / FRLG | Random, Soft Reset | ✅ | ◑ "Run Away" fixed; Lati@s + beasts added (RSE/FRLG). Residual: RSE/FRLG starter/fossil gifts (Treecko/fossils/Kanto starters) still Random — were NEEDS-REVIEW in audit, not yet confirmed. |
| 4 | DPPt / HGSS | Poké Radar, Random, Soft Reset | ✅ | ✅ Clean (pilot). DPPt legendary statics now covered. |
| 5 | BW / B2W2 | Masuda, Random, Soft Reset | ✅ | ◑ Masuda complete. Residual: not all Unova static legendaries have Soft Reset; SR charm-roll bleed (odds). |
| 6 | XY | Chain Fishing, Friend Safari, Masuda, Poké Radar, Random | ✅ | ✅ Friend Safari fixed; full method set. |
| 6 | ORAS | Chain Fishing, DexNav, Masuda, Random, Soft Reset | ✅ | ✅ Wild coverage widened via RSE→ORAS proxy + ORAS additions (Random/DexNav 235). All 19 Soaring/Mirage legendaries added (Soft Reset). Residual: Eon-Ticket Lati@s same-id nuance (left unlocked). |
| 7 | SM / USUM | Masuda, SOS Chaining, Random, Soft Reset | ✅ | ✅ Random + Soft Reset (UBs/Type:Null/Zygarde/Necrozma). All 37 USUM Ultra Wormhole legendaries added (Soft Reset; incl. Kyogre/Groudon/Rayquaza/Xerneas/Yveltal — locked elsewhere, huntable here). |
| 7 | LGPE | Catch Combo | ✅ | ✅ Correct. |
| 8 | SwSh | Dynamax Adventures, KO Method, Masuda, Run Away | ✅ | ✅ "KO Method" verified legitimate (catch-count rerolls). |
| 8 | BDSP | Masuda, Poké Radar, Random, Soft Reset | ✅ | ✅ Fully seeded this session. |
| 8 | PLA | Mass Outbreak | ✅ (all legendaries locked) | ✅ Correct. |
| 9 | SV | Mass Outbreak, Masuda, Random, Sandwich | ✅ | ✅ Methods valid, locks accurate, 0 huntable-but-locked. |
| — | all | — | — | ⏸ **Odds unverified** (base_odds × base_rolls × charm_rolls). Methods-only audit; odds were the deferred phase. |

---

## Remaining work (prioritized)

1. **Gen 3 RSE/FRLG starter/fossil gifts** — confirm + flip the remaining NEEDS-REVIEW gift/fossil mislabels (Treecko/Torchic/Mudkip, Lileep/Anorith, Kanto starters, Omanyte/Kabuto) from Random → Soft Reset.
2. **Odds — Shiny Charm availability guard: DONE.** Audited the odds engine (`calc.EffectiveOdds` — per-formula chaining logic is sound and Bulbapedia-aligned). Fixed the charm bleed: charm now only applies in games where it exists (B2W2 + Gen 6+, ids 8–17) — enforced at the toggle API, in route/dex odds, in `GetOddsHandler` (now formula-aware), and mirrored in the frontend (toggle hidden + odds gated). **Friend Safari: CLOSED, no change** (see `docs/audit/ODDS_DOMAIN_REVIEW.md` finding 6). `base_rolls 5` → 1/819.2 is correct; with the charm (`charm_rolls: 2`, 7 rolls) it is 1/585. The commonly-cited ~1/512 is an early-Gen-6 community estimate that predates the roll model being understood, and has been repeated since — it is not a with-charm figure and not an alternative base value. Do not "correct" 1/819 to 1/512. Residual odds item: the frontend `odds.ts` ↔ backend `EffectiveOdds` parity has one known divergence noted in code (outbreak sparkling-power term).
3. **Optional polish** — Eon-Ticket Lati@s encounter-level granularity; dedicated Mirage-Spot / Ultra-Wormhole methods (distinct odds vs plain Soft Reset); same-region wild proxies for any other sparse-data gens; Gen 3 RSE/FRLG starter/fossil gifts.
3. **Gen 2 / Gen 3** — fix the "wild/other"-driven gift/static mislabels (move to `legendary_encounters.json` static) and backfill missing legendaries. Root cause is the overloaded `wild/other` encounter bucket in the PokeAPI mapper.
4. **Gen 1** — exclude RBY from hunting (drop the 4 Soft Reset rows; no shiny mechanic exists).
5. **Odds verification phase** — validate `base_odds`/`base_rolls`/`charm_rolls` per method/game, incl. the Soft Reset `charm_rolls=2` bleed for pre-Gen-5 games (Shiny Charm didn't exist until Gen 5/B2W2).
6. **Minor:** PokeAPI gives ~5 XY Friend-Safari species spurious grass-route encounters (encounter-data accuracy, not logic). RLS still disabled on all tables (security advisory).

---

## Process notes
- All durable fixes live in the **seed source** (`backend/seeds/*.json`, `cmd/seed`, `cmd/seed_availability_legacy`) — a re-seed regenerates `method_availability`/`pokemon_game_encounter`/`shiny_locks` deterministically, so SQL-only patches would be wiped.
- Run order: `cmd/seed_availability_legacy` → `cmd/seed` (now self-seeds shiny_locks before deriving). The `friend_safari` terrain required a one-time `ALTER` on the live DB (applied).
- Audit gathering was delegated to per-gen subagents; domain claims were verified against Bulbapedia/Serebii, and two sub-agent findings were caught and corrected on review (XY starters *not* locked; Treasures of Ruin *are* locked).
