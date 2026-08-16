# Domain Review — Odds Engine & Method Seeds

**Scope:** shiny-mechanics accuracy review of `internal/calc`, `seeds/hunt_methods.json`, and
`frontend/src/utils/odds.ts`. Complements `ALL_GENS_SUMMARY.md`, which audited *methods and
locks*; this pass covers the deferred **odds** phase.

**Verification basis:** Bulbapedia roll tables per generation.

> Status legend: ❌ wrong number shown to users · ◑ gap · ⏸ product decision

---

## ✅ 1. `radar_chain_gen4` served three different mechanics — FIXED 2026-08-10

> **This finding's original text was wrong in its numbers and in its prescribed fix, and has been
> replaced with the verified version below.** The original claimed the correct mid-chain values
> were 1/1365 and 1/819 (those are `4096/3` and `4096/5` — roll-model numbers pasted into a
> patch-curve table), and prescribed scaling the Gen 4 curve by `base_odds / 8192`. That scaling
> is wrong: XY and BDSP do not share Gen 4's curve at all. Verified against Bulbapedia's datamined
> per-chain tables and cross-checked against Serebii.

**Files:** `internal/calc/methods.go` · `frontend/src/utils/odds.ts` · `seeds/hunt_methods.json`

One `formula_type` was seeded for three games with three genuinely different mechanics:

| game | mechanic | chain 0 | cap (chain 40) |
|---|---|---|---|
| DPPt | `ceil(65535/(8200-200c))` integer curve | 1/8192 | 1/200 |
| X/Y | linear sparkle denominator `8100-200c`, composed with the ordinary wild roll | 1/2721 | **1/100** |
| BDSP | 41-entry lookup table with discontinuities at chain 30 and 36 | 1/4096 | **1/99** |

**Gen 4 was correct all along** and needed no numeric change. Its numerator matches Bulbapedia
row for row, and at chain 0 it is 8/65536 — exactly the Gen 4 base rate. The curve *subsumes*
`base_odds`; not reading it is correct by design, not an oversight. Only XY reads `base_odds`.

Resolution: split into `radar_chain_gen4` (DPPt), `radar_chain_xy`, and `radar_chain_bdsp`. Every
BDSP radar ETA had been ~2× too pessimistic. Anchors for all three now live in
`shared/odds_anchors.json` and are asserted by `internal/calc/anchors_test.go`.

**One inference, flagged:** Bulbapedia states XY's sparkle rate but never states how it composes
with the ordinary wild roll. The implementation uses
`pSparkle + (1 - pSparkle) * rolls/base_odds` — a radar encounter is still a wild encounter, and
this matches the existing `dexnav_gen6` composition. Sparkle-only would differ ~3× at chain 0.

---

## ✅ 2. Radar branch discarded the Shiny Charm — FIXED 2026-08-10, opposite of as written

> The original text said "**BDSP** — incorrect, the charm does affect Radar chains." **That is
> backwards.** The engine was right to discard it and the *seed* was wrong.

Bulbapedia, Shiny Charm: *"In Brilliant Diamond and Shining Pearl only, the Shiny Charm only
affects breeding"*, and *"the internal code explicitly disables the Shiny Charm for other
encounter types"* — datamined, not lore. The in-game item description is itself erroneous, which
is likely how this got into the seed.

Resolution: charm is inert in `radar_chain_gen4` (no charm exists in Gen 4) and in
`radar_chain_bdsp` (breeding-only), and applies in `radar_chain_xy`. See finding 9 — the same
BDSP error was present on two much more heavily used method rows.

---

## ✅ 3. `soft_reset_lgpe` has `charm_rolls: 0` — FIXED 2026-08-10 (now 2)

**File:** `seeds/hunt_methods.json`

The Shiny Charm exists in Let's Go and applies to static/soft-reset encounters. Compare
`catch_combo_lgpe`, which correctly carries `charm_rolls: 2`. Anyone soft-resetting the birds or
Mewtwo with the charm is quoted 1/4096 instead of 1/1365.

---

## ✅ 4. No Lure term for Let's Go — FIXED 2026-08-10 (`lure_active` param, +1 roll)

**Files:** `seeds/hunt_methods.json` · both odds engines · hunt-parameter UI

The canonical LGPE best case is **1/273** — catch combo 31+ (12 rolls) + Shiny Charm (2) +
Lure (1) = 15 rolls against 4096. Without a Lure term the app tops out at 4096/14 = 1/292.

A Lure is active for effectively the whole hunt in practice. Suggest a boolean
`lure_active` hunt parameter (`+1` roll) on `catch_combo_lgpe`. Note the Lure also raises
encounter rate, so it belongs in `avg_time_seconds` reasoning too.

---

## ◑ 5. Masuda Method missing for DPPt / HGSS

**File:** `seeds/hunt_methods.json`

Masuda debuted in Diamond/Pearl. The seed grants it to Gen 5–9 and BDSP but not to Gen 4, so
Gen 4 breeders see only Random / Poké Radar / Soft Reset.

**Important:** Gen 4 Masuda is **5 rolls (1/1638)**, not the 6 used everywhere else — the sixth
roll arrived in Gen 5. A new `masuda_method_gen4` entry is needed rather than adding the Gen 4
games to an existing row.

```json
{
  "id": "masuda_method_gen4",
  "games": ["Diamond/Pearl/Platinum", "HeartGold/SoulSilver"],
  "method_name": "Masuda Method",
  "avg_time_seconds": 45,
  "base_rolls": 5,
  "charm_rolls": 0,
  "formula_type": "static",
  "requires_kind": "egg"
}
```

`charm_rolls: 0` — no Shiny Charm in Gen 4.

---

## ✅ 6. Friend Safari — close the open item as "no change"

`ALL_GENS_SUMMARY.md` § Remaining work item 2 flags `base_rolls 5 → ~1/819 vs commonly-cited
~1/512` as needing confirmation.

**The seeded value is correct.** 5 rolls against 4096 = 1/819.2 (1/585 with charm). The 1/512
figure is an early-Gen-6 community estimate that predates the roll model being understood and
has been repeated since. Record this in the seed entry, or it will get "fixed" later.

---

## ⏸ 7. `run_away` (SwSh) duplicates `random_encounter`

**File:** `seeds/hunt_methods.json`

Identical parameters: `static`, `base_rolls: 1`, `charm_rolls: 2`. Mechanically honest — fleeing
to force overworld respawns changes encounter *rate*, not odds — but listing it as a separate
method implies a shiny benefit it does not confer. Either fold it into Random Encounter, or keep
it and let the entire difference live in `avg_time_seconds`, which is where it actually is.

---

## 🔴 8. The odds engine exists twice — and a Swift client makes it three

**Files:** `internal/calc/methods.go` · `frontend/src/utils/odds.ts`

Every formula is implemented in both, with comments in each describing how they mirror one
another and where they intentionally diverge. Finding 1 is what that costs: a bug present in
both copies reads as consensus, and parity tests pass while both are wrong.

With a native iOS client planned this stops being a style question. Odds must compute on-device
(offline counting means the app cannot ask the server for the current mid-chain odds), so there
will be a third implementation held in agreement by hand.

**Extract a shared fixture set before the Swift version is written:** a JSON file of
`(formula_type, params, base_odds, base_rolls, charm_rolls, has_charm) → denominator` anchors in
the repo, consumed by `methods_test.go`, a TS test, and a Swift test alike. The anchors become the
source of truth rather than three implementations policing each other. Several anchors already
exist as prose comments in `odds.ts` (the PLA and ultra-wormhole blocks) and can seed it directly.

Fix findings 1–4 first, so the fixture is generated from corrected values.

---

## ✅ 9. BDSP Shiny Charm is breeding-only — FIXED 2026-08-10 (found while fixing 1–2)

**File:** `seeds/hunt_methods.json`

Not in the original review. Surfaced while verifying finding 2, and larger than it: the same
BDSP charm error was on the two most heavily used BDSP method rows, not just the Radar.

- `random_encounter_bdsp` — was `charm_rolls: 2`, now `0`.
- The shared `soft_reset_static` row included BDSP among ~7 games; BDSP is now split out as
  `soft_reset_bdsp` with `charm_rolls: 0`, leaving the other games untouched.
- `masuda_method_gen8` correctly **keeps** `charm_rolls: 2` — breeding is the one thing the BDSP
  charm does affect.

That was a 3× overstatement on ordinary BDSP wild and soft-reset hunts. Rows carry a `_note`
recording why, since `charm_rolls: 0` on a Gen 8 game otherwise reads as a mistake.

---

## Verified correct — do not "simplify"

Checked against Bulbapedia and found accurate:

- **PLA roll stacking** — research 10 (+1) and Perfect (+2) stack; charm +3; MO +25, MMO +12.
  MO + perfect + charm = 32 rolls → 1/128. MMO correctly *worse* per-encounter than MO.
- **SV outbreak + sandwich** — additive; 60 defeats (+2) + Sparkling 3 (+3) + charm (+2) = 8
  rolls → 1/512.
- **Chain fishing** — 1 + 2×20 + charm = 41–43 rolls → ~1/100.
- **SOS chaining** — 5 / 9 / 13 rolls at chains 11 / 21 / 31, with the `% 255` wrap.
- **Catch combo tiers** — +3 / +7 / +11.
- **Dynamax Adventures** — 1/300 → 1/100 with charm.
- **DexNav** — the `/100` correction is right; search level 200 → 0.08% forced-shiny per check.
- **Per-game `base_odds`** — 8192 for Gen 2–5, 4096 from Gen 6.
- **Charm availability gate** — B2W2 + Gen 6 onward.
- **Streak handling in `odds.ts`** — returning `{}` from `defaultParamsFor` for streak formulas
  so the live encounter fallback survives is correct and subtle; the explanatory comment should
  be preserved through any refactor.
- **`shiny_locks.json`** — the most accurate lock table outside Bulbapedia. The BDSP
  Darkrai / Shaymin / Arceus entries (event-item statics, soft-resettable, *not* locked) are a
  distinction most trackers get wrong.

---

## Status

**Done 2026-08-10:** findings 1, 2, 3, 4, 6, 9, and the fixture half of 8
(`shared/odds_anchors.json` + `internal/calc/anchors_test.go`, asserted in Go and verified
against the TS engine).

**Corrected 2026-08-15 — this section had been wrong on three counts.** It was written in
the *same commit* (`b2c7659`) that shipped the fixes it described as pending, and was never
revisited. Verified against the live database, not against this document:

- ~~"the live DB still needs a re-seed"~~ — **it does not.** All 35 `hunt_methods` rows were
  diffed field-by-field against `seeds/hunt_methods.json`: 0 differences, 0 missing, 0
  orphans. `method_games` and `method_availability` reflect the corrected values too.
- ~~Finding 5 still open~~ — **done.** `masuda_method_gen4` (5 rolls, not 6) is live with 194
  DPPt and 163 HGSS `method_availability` rows. It shipped in the same commit.
- ~~Finding 8's remaining half still open~~ — **done.** `ShinyTrackerKit`'s
  `OddsAnchorsTests.swift` reads `shared/odds_anchors.json` directly. All three engines are
  now anchored to the fixture rather than to each other.

**Still open:**

1. Finding 7 — `run_away` product decision, no user-visible defect.
2. **New, found 2026-08-15:** 60 `(pokemon, game)` pairs are legally available, not
   shiny-locked, and have zero `pokemon_game_encounter` row, so no method at all. This is
   the "BDSP Ramanas Park" gap generalised — it also covers DPPt Arceus, HGSS Azelf, ORAS
   Jirachi, the BW/B2W2 event legendaries, SM/USUM Magearna and Marshadow, SwSh Keldeo and
   all nine transferable Ultra Beasts, SV Meloetta, and PLA Phione. Underlying question is a
   product one: should "available in this game" mean *huntable here* or *dex-completable
   here via transfer*? The data currently conflates the two.
3. **New, found 2026-08-15:** GSC and RSE/FRLG have **no egg-kind method row at all**. Masuda
   did not exist before Gen 4 and no plain "Breeding" method was ever seeded for them, so
   the 15 baby Pokémon (Pichu, Cleffa, Igglybuff, Tyrogue, Elekid, Magby, Azurill, Wynaut,
   Bonsly, Mime Jr., Happiny, Munchlax, Mantyke, Budew, Chingling) have correct
   `kind='egg'` encounter rows and no way to hunt them. Fix is one seed row —
   `breeding_pregen4`, `static`, `base_rolls: 1`, `charm_rolls: 0`, `requires_kind: 'egg'`.

Nothing here touches the hunt flow, live chain handling, or the lock table.

> **A note on this section's history.** It claimed work was pending that had already
> shipped, and a reader acting on it would have re-seeded a database that was already
> correct. If you fix something listed here, update this section in a *later* commit than
> the fix, or it will happen again.
