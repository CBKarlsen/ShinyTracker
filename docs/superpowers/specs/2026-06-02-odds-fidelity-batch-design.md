# Odds Fidelity Batch — Design

**Date:** 2026-06-02
**Branch base:** `feat/chain-tracking`
**Status:** Draft for review

## Goal

Close the four highest-impact fidelity gaps a serious shiny hunter would hit, identified in the domain review:

- **A1** — Pokémon Legends: Arceus is modeled as plain `1/4096` static; real PLA odds stack additive rolls (research, perfect dex, mass outbreaks) and reach ~1/128.
- **A3** — `LogPhaseHandler` writes the phased shiny into the collection with no game, no method, and the *target's* encounter count, and labels it `HUNTED` — corrupting hunt history.
- **B1** — No Ultra Wormhole (USUM) hunting; distance×ring scaling is absent.
- **C3** — A dead `CalculateEstimatedTimeHours` helper uses base+charm rolls only, the original source of the "ETA ignores dynamic odds" smell. (The live estimate endpoint already routes through `EffectiveOdds`.)
- **C1** — Stale comment in `methods.go` claims TS lacks the SV sparkling term (TS has it); the Go↔TS parity test covers neither the divergence nor the new formulas.

Out of scope (deferred): A4 Dynamax `caught_before`, B2 dead `@sv-tera-raids`, B4 LGPE lure, B5 SwSh KO combo, D2/D3 features. Per-hunt *live-param* ETA (vs best-case preview) is explicitly out of scope.

## The odds engine, as it stands

Odds are computed twice, in parity:
- Go: `backend/internal/calc/methods.go` `EffectiveOdds(formulaType, params, base, hasCharm) int`
- TS: `frontend/src/utils/odds.ts` `calculateOdds(...) → {rolls, denominator}`

Both switch on `formula_type` (a column on `hunt_methods`, seeded from `backend/seeds/hunt_methods.json`). Most methods reduce to `floorDiv(base_rolls + bonus + charm_rolls)` where `floorDiv(r) = base_odds / r` (integer division). `DefaultParams(formulaType)` supplies best-case params for ranking/preview. `methods_test.go` asserts specific `1/N` denominators.

Any new formula must land in **all four**: `methods.go`, `odds.ts`, `hunt_methods.json` (seed rows), and `methods_test.go` (test cases) — plus the TS param plumbing (`PARAM_FORMULAS`, `defaultParamsFor`) and the param-editor UI.

---

## A1 — Legends: Arceus additive-rolls odds

### Mechanic (verified, RotomLabs/Serebii)
PLA literally rolls N independent 1/4096 PID checks; the additive-rolls model is exact here, not an approximation. Bonuses (each = +1 roll):

| Modifier | Rolls | Source param |
|---|---|---|
| Base | 1 | `base_rolls` |
| Research Level 10 | +1 | `research_level >= 10` |
| Perfect research | +2 | `dex_perfect = true` (stacks on top of Lv10) |
| Shiny Charm | +3 | `charm_rolls` (engine adds when `hasCharm`) |
| Mass Outbreak | +25 | `mass_outbreak = true` |
| Massive Mass Outbreak | +12 | `massive_outbreak = true` (weaker than MO) |

Charm is `+3` (published "+1 charm" rows secretly bundle the Lv10 prerequisite). MO and MMO are mutually exclusive in practice; if both flags set, take MO (the larger).

**Research stacking (the one contested point — decided):** Lv10 (+1) and Perfect (+2) **stack to +3** in the perfect case. This is deliberate: it reconciles RotomLabs/Serebii's published anchors exactly — MO+perfect+charm = `1+25+1+2+3 = 32` rolls → 1/128, which is the number those sources print. The alternative (Perfect supersedes Lv10 at +2) would not match. Document this in code next to the formula.

**MMO is per-encounter WORSE than MO, by design — do not "fix" it.** Verified across RotomLabs (Anubis datamine), Serebii, dotesports, Game8: MMO = +12 rolls (~1/315 base) vs MO = +25 (~1/158 base). MMO's real-world advantage is **spawn volume** — it produces many times more encounters per outbreak (waves of hordes), not better odds on any single spawn. Serebii states this explicitly. We therefore keep MMO's per-encounter odds lower and express its speed advantage purely through a lower `avg_time_seconds` on its seed row. A future reader seeing "Massive < regular" is looking at correct behavior.

### Formulas `pla_research` / `pla_mass_outbreak` / `pla_massive_outbreak`
The outbreak is determined by *which method you chose*, not a per-hunt parameter — so it is encoded in the `formula_type`, not in `hunt_parameters`. (Revised during code review: a single `pla_research` formula meant `defaultParamsFor` could not pre-select the outbreak, so picking "Mass Outbreak" silently started at 1/4096.) All three share a `plaResearchRolls` helper for the research bonus:
```
research = base_rolls
         + (research_level >= 10 ? 1 : 0)
         + (dex_perfect ? 2 : 0)
pla_research          -> floorDiv(research + 0  + charm)
pla_mass_outbreak     -> floorDiv(research + 25 + charm)
pla_massive_outbreak  -> floorDiv(research + 12 + charm)
                         // floorDiv = base_odds / rolls, integer division; charm = +3 if hasCharm
```

`hunt_parameters` keys (user-set, none derived from the encounter counter):
`research_level` (int, 0 or 10), `dex_perfect` (bool). No outbreak flags — the outbreak lives in the formula_type.

### Seed rows (`hunt_methods.json`, games `["Legends: Arceus"]`)
Replace the current implicit static + `mass_outbreak_la` with three rows (all `base_rolls 1, charm_rolls 3`), each with its own `formula_type` and `avg_time_seconds`:
- `pla_full_odds` — "Wild / Static", `formula_type pla_research`, `avg_time_seconds 30, requires_kind wild`.
- `pla_mass_outbreak` — "Mass Outbreak", `formula_type pla_mass_outbreak`, `avg_time_seconds 15`.
- `pla_massive_outbreak` — "Massive Mass Outbreak", `formula_type pla_massive_outbreak`, `avg_time_seconds 8`. Lower per-encounter time than MO captures MMO's spawn-volume advantage: worse per-spawn odds, but you churn through far more spawns, so ETA still favors it.

`charm.go` already lists game 16 (Legends: Arceus) as charm-available — no change.

### Test anchors (floorDiv, base 4096)
base→4096, Lv10→2048, perfect(4 rolls)→1024, charm-only(4 rolls)→1024, MO(26)→157, MO+perfect(29)→141, MO+perfect+charm(32)→128, MMO(13)→315, MMO+perfect(16)→256, MMO+perfect+charm(19)→215.
("perfect" rows include the Lv10 +1 since they stack: perfect = base1 + lv10 1 + perfect 2 = 4 rolls. "charm only" = base1 + charm3 = 4 rolls → 1024. Exact-geometric values differ by ≤1, e.g. MO=158 vs floor 157; we use floorDiv for consistency with every other method and the existing test style.)

---

## B1 — Ultra Wormhole (USUM)

### Mechanic
Two distinct cases. **Distance scaling applies only to non-legendary wormhole Pokémon** caught via Ultra Warp Ride. Wormhole *legendaries* are normal soft-reset encounters (handled by the existing `static` method, not this formula).

Non-legendary shiny percent:
```
k = clamp(floor(distance_ly / 500) - 1, 0, 9)
percent = ring_type == 1 ? 1
        : ring_type == 2 ? min(10, 1 + 1*k)
        : ring_type == 3 ? min(19, 1 + 2*k)
        :                  min(36, 1 + 4*k)   // ring_type 4
```
Shiny Charm has **no effect** on wormhole rate. Distance benefit hard-caps at 5000 LY (k=9); no 10000+ tier.

### Formula `ultra_wormhole`
Returns `round(100 / percent)` as the `1/N` denominator. Ignores `base_rolls`/`charm_rolls`/charm entirely.

`hunt_parameters` keys (user-set): `wormhole_ring_type` (1–4, default 4), `wormhole_distance_ly` (int, default 0).

### Seed row (`hunt_methods.json`, games `["Ultra Sun/Ultra Moon"]`)
- `ultra_warp_ride_usum` — method_name "Ultra Warp Ride", `base_rolls 1, charm_rolls 2, formula_type ultra_wormhole, avg_time_seconds 60, requires_kind static`.

Gate to USUM only via `seeds/method_exceptions.json` if availability derivation doesn't already scope it.

### Test anchors
Type1 any→100; Type2@5000(k9)→10; Type3@5000→5 (5.26→5); Type4@5000→3 (2.78→3); Type4@2000(k3,13%)→8; k0 all types→100.

### `DefaultParams`
`ultra_wormhole → {wormhole_ring_type: 4, wormhole_distance_ly: 5000}` (best case, ~1/3).
`pla_research → {research_level: 10, dex_perfect: true, mass_outbreak: true}` (best non-charm, ~1/141; charm added by engine when applicable).

---

## A3 — Phase row integrity

`LogPhaseHandler` (`hunts.go:280-287`) currently inserts the phase collection row as:
`hunt_method_id NULL, game_id NULL (omitted), acquisition_type 'HUNTED', encounter_count = <target's count>, hunt_parameters '{}'`.

### Fix
1. **Add `'PHASE'` to the `acquisition_type` CHECK** (`schema.sql:137`) via additive migration. New set: `('HUNTED','EVOLVED','MANUAL_OVERRIDE','TRADED','PHASE')`.
2. The phase row inherits the **parent hunt's `game_id`**, sets `encounter_count = 0`, `acquisition_type = 'PHASE'`. (A phase shiny appeared once, mid-hunt; 0 is the honest "encounters spent specifically on it.")
3. Capture the parent's `game_id` in the same `SELECT` that already reads `encounter_count, status` (add the column), then pass it into the collection INSERT.

Migration applied as additive `ALTER TABLE` (drop+recreate the CHECK constraint). Code tolerant either way: the INSERT only writes `'PHASE'` after the constraint allows it — apply migration first.

Frontend: any place that filters/labels by `acquisition_type` (Collection, Historic) should treat `PHASE` like an owned shiny but may label it "Phase". Audit `frontend/src` for `acquisition_type` switches; minimal change is to ensure `PHASE` is not dropped from the collection view.

---

## C3 — Remove the dead ETA helper

`CalculateEstimatedTimeHours` in `odds.go` has zero callers (the estimate endpoint and route ranking both use `EffectiveOdds`). It computes ETA from base+charm rolls only — a correctness trap. **Delete it.** The two new formulas automatically get correct ETA via their `DefaultParams` entries feeding the existing `EffectiveOdds` path in `handlers.go`. If a test references it, delete that too.

---

## C1 — Parity comment + test coverage

1. Update the `EffectiveOdds` doc comment (`methods.go:23-28`): TS *does* now add the SV sparkling term; remove the stale "(TS doesn't yet)" claim. Keep the note that `catch_combo_lgpe`/`chain_fishing_gen6` read `count` in Go vs live encounters in TS.
2. Add `pla_research` and `ultra_wormhole` cases to `methods_test.go` using the anchors above.
3. The parity test is Go-only; a true Go/TS drift wouldn't be caught. Mitigation for this batch: hand-mirror the same anchor cases as a small Vitest-free assertion is out of scope (no test runner in frontend). Instead, document the shared anchors in a comment block in `odds.ts` next to the new branches so the next editor has the same target numbers. (A shared fixture is a separate follow-up.)

---

## Components & boundaries

| Unit | Responsibility | Touches |
|---|---|---|
| `methods.go` | Go odds: add 2 formula cases + DefaultParams + comment | backend-specialist |
| `methods_test.go` | Anchor assertions for new formulas | backend-specialist |
| `odds.go` | Delete dead helper | backend-specialist |
| `hunts.go` | Phase row: game_id + count 0 + PHASE type | backend-specialist |
| `schema.sql` + live migration | acquisition_type CHECK += PHASE | backend-specialist |
| `hunt_methods.json` / `method_exceptions.json` | seed PLA + wormhole methods; re-seed | backend-specialist + data re-seed |
| `odds.ts` | TS odds: 2 branches + PARAM_FORMULAS + defaultParamsFor + anchor comment | frontend-specialist |
| `HuntParametersEditor` + NewHuntModal | inputs for PLA flags + wormhole ring/distance | frontend-specialist |
| Collection/Historic | tolerate `PHASE` acquisition_type | frontend-specialist |

Backend and frontend odds changes share the same constants and must be implemented together; dispatch them in parallel against this spec, then run the parity test and `code-reviewer`.

## Data / re-seed

`hunt_methods.json` edits require re-seeding. **Seed order matters** (known footgun): `cmd/seed` must run LAST or `method_availability`/`hunt_methods` end up empty. Re-seed plan: run the method seed, then `cmd/audit_methods` to confirm PLA + USUM rows landed and availability is non-empty. Live DB writes go through the established seed tooling, not ad-hoc SQL.

## Testing

- `go test ./internal/calc/...` — parity + new anchors pass.
- `go build ./...` and `npm run build` (tsc) clean.
- Manual: create a PLA hunt with Mass Outbreak + Perfect → preview shows ~1/141 (1/128 with charm); a USUM wormhole hunt at ring 4 / 5000 ly → ~1/3; log a phase → collection row has the parent game, count 0, `PHASE` type.
- `npm run lint` (Biome) clean.

## Risks

- **Wormhole denominator < 4 collides with display assumptions.** `calcCumulativeOdds` and luck labels assume `1/N` with N≫1. Verify a denominator of 3 doesn't break the cumulative-probability loop or ETA (it shouldn't: `1 - 1/3` is valid). Note in implementation.
- **Live CHECK-constraint migration** must precede the first `PHASE` insert. Apply migration, then deploy code.
- **Re-seed wiping method_availability** if seed order is wrong — follow the documented order.
