# ShinyTracker — Living-Dex Completionist Backlog

Feature backlog organized around the **living-dex completionist** persona (a hunter whose goal is owning every shiny). Ranking comes from the `shiny-hunt-expert` agent's analysis. Work top-down; each item links its spec/plan where one exists.

**Branch:** all shipped work below is on `worktree-dex-completion-engine` (based on `hunt-method-corrections`, since `master` predates the rules-based method engine).

Status: ✅ shipped · 🔜 next · ⏳ backlog · 🐞 follow-up

---

## ✅ Shipped

- **#1 Blocked awareness** — dex grid shows 🔒 shiny-locked-everywhere and 🚫 not-in-your-games states.
- **#2 Best-route drawer** — click a Pokémon → ranked routes (direct + "hunt a pre-evolution") with odds/ETA, Start, Mark-caught. `GET /api/dex/status` + `GET /api/pokemon/{id}/route`.
  - Spec: `docs/superpowers/specs/2026-05-26-dex-completion-engine-design.md` · Plan: `docs/superpowers/plans/2026-05-26-dex-completion-engine.md`
- **Hunt-route unification** — New Hunt modal and the drawer now render the same routes from one endpoint via a shared `usePokemonRoute` hook + `<RouteList>`. Evolve "Start" hunts the ancestor.
  - Spec: `docs/superpowers/specs/2026-05-27-hunt-route-unification-design.md` · Plan: `docs/superpowers/plans/2026-05-27-hunt-route-unification.md`
- **Egg/Masuda base-form fix** — `deriveEggEncounters` now gated on `evolves_from_id IS NULL` (eggs only hatch base forms).
- **#4 Modern method odds (backend)** — Go odds engine is now method-aware: `calc.EffectiveOdds` ports `frontend/src/utils/odds.ts` (8 dynamic `formula_type`s), and `computeRoute` ranks routes via `EffectiveOdds`+`DefaultParams`, so the best-route drawer reflects SV outbreak/sandwich, SOS, Radar, DexNav, etc. instead of flat odds. The curated-hunt create path now persists `hunt_parameters` (the `hunts.go` `{}` override is gone). No DDL.
  - Spec: `docs/superpowers/specs/2026-05-31-modern-method-odds-design.md` · Plan: `docs/superpowers/plans/2026-05-31-modern-method-odds.md`

---

## 🔜 Next up

### Shiny-lock accuracy audit
The curated lock dataset (`backend/seeds/shiny_locks.json`, 28 entries) is a ~50-60% starter set and needs verification before it's trusted.
- **How:** web-verified audit against Bulbapedia/Serebii per-game shiny-lock lists. Produce a diff (remove / fix / add) for review, then re-run `go run ./cmd/seed_shiny_locks/main.go`.
- **Verify (suspect entries):** Tapu Koko/Lele/Bulu/Fini (#785-788) — likely soft-resettable in SM/USUM, may be wrong; Necrozma SM-only (#800); Cosmog (#789).
- **Find missing locks:** gift starters (often locked across many games), most Gen 3-5 story legendaries, ORAS legendaries, etc.
- Ask Claude: "run the shiny-lock audit."

---

## ⏳ Backlog (persona's remaining wants)

- **#3 Living-dex scope selector** — let users complete a *game's* regional dex or the National dex (denominator recompute). Scope toggle is small (S). **Forms-as-targets** (Alolan/Galarian/Hisuian, Unown) is large (L) — backend caps at 1025 base species; a shiny Alolan Raichu can't be represented. Scope deliberately.
- **#5 Completion forecast** — project total encounters/hours to finish the chosen dex from remaining targets' best-route ETAs. Forward-looking counterpart to `Stats.tsx`.
- **#6 Acquisition provenance filters** — filter the dex by Hunted/Evolved/Traded/Manual (`acquisition_type` already exists, just not surfaced). "Self-caught dex" sub-goal. Small.
- **#7 Bulk import** — CSV/Home-export import to mark many owned shinies at once instead of clicking each cell.

---

## 🐞 Follow-ups / known issues

- ✅ **TS/Go odds drift on outbreak+sandwich — FIXED.** `utils/odds.ts` `outbreak_defeats_sv` now adds the `sparkling_power` term and the outbreak editor has a Sparkling Power field; `HuntRow` threads `hunt_parameters`. Dashboard live-odds match the route drawer's 1/512. (spec/plan `docs/superpowers/*/2026-05-31-outbreak-sandwich-odds-consistency*`).
- **`GetOddsHandler` (`GET /odds`) is UNUSED by the frontend** — every odds display computes client-side via `utils/odds.ts`; nothing fetches `/odds`. Left as-is (dead but harmless; only special-cases dynamax). Route through `calc.EffectiveOdds` or delete if it's ever revived.
- **Radar chain-0 quirk** — `radar_chain_gen4` returns 1/65536 at chain 0 (TS formula `65536 − 1635.925·chain`), mirrored in Go for parity. Revisit whether the base should track the game's 1/8192.
- **Method eligibility data** — web-source which species are huntable via each method per game and seed into `method_availability` / `method_exceptions`. Decomposed into slices:
  - ✅ **Slice D (Dynamax Adventures)** — all 38 DA legendary bosses seeded as SwSh raids in `legendary_encounters.json` (spec/plan `docs/superpowers/*/2026-05-31-dynamax-adventures-eligibility*`). Live in DB.
  - ✅ **Slice A — Gen 8/9 overworld spawns** — COMPLETE across SV/SwSh/LA. Reuses `kind=wild` + game-keyed `seeds/overworld_species.json` + `seedOverworldSpecies` step, no DDL.
    - ✅ **Scarlet/Violet** — 650 regional-dex species (legendaries + Walking Wake/Iron Leaves excluded) seeded as `wild`; Random Encounter / Sandwich Hunting / Mass Outbreak now attach (650 each). 3 area outbreaks collapsed into one. SV "available but no method" 412→43. (spec/plan `docs/superpowers/*/2026-05-31-sv-overworld-eligibility*`).
    - ✅ **Sword/Shield + Legends: Arceus** — Galar tri-dex (568) + Hisui (225) species seeded as `wild`; KO Method / Run Away attach in SwSh (562 each), Mass Outbreak in LA (224). Section-A gaps SwSh 133→20, LA 213→2. (spec/plan `docs/superpowers/*/2026-05-31-swsh-la-overworld-eligibility*`).
  - ❌ **Slice B — Poké Radar over-broad: DROPPED.** shiny-hunt-expert confirmed Radar draws from the full route grass table, so attaching it to all grass species is correct; an exclude list would wrongly remove chainable swarm/Trophy-Garden species. No change warranted.
  - ✅ **Slice C — ORAS fishing** — `seeds/fishing_species.json` (20-species rod roster) + `seedFishingSpecies` step seed `terrain='fishing'` wild rows; Chain Fishing 0→20 and DexNav 108→127 in ORAS; Section-A gap 36→30. (spec/plan `docs/superpowers/*/2026-05-31-oras-fishing-eligibility*`).

  **Eligibility pass status: A (SV/SwSh/LA) ✅, B dropped, C ✅, D ✅. Remaining deferred items only: the 9 DA Ultra Beasts; home-game static coverage for the 24 DA legends; per-species wild-curation refinement of the dex-membership proxies via `method_exceptions`.**
  - ⏳ Also deferred: the 9 DA Ultra Beasts; home-game static coverage for the 24 DA legends.
- **Masuda labeling** — Masuda still shows broadly for base forms (correct), but consider clearer labels for the evolve-from flow. Method-engine concern.
- **Forms / regional variants** — not representable (see #3). Larger data-model change.

---

## Operational notes (for re-seeding the shared Supabase DB)

- **Seed order matters:** `cmd/sync` truncates `hunt_methods` (cascading `method_availability` to 0). Always run **`cmd/seed` LAST**. Full rebuild: `apply_schema` → `cmd/sync` (slow PokeAPI crawl; populates `evolves_from_id`) → `cmd/seed` → `cmd/seed_shiny_locks`.
- `cmd/apply_schema` is destructive to the method tables (drops `hunt_methods`/`method_*`); `cmd/seed` rebuilds them.
- Health check: `go run ./cmd/audit_methods/main.go` (Section B = real availability inconsistencies).
- **`cmd/seed_locations` is independent of the seed order above.** It touches only
  `pokemon_locations` and never `hunt_methods`, so it can be re-run at any time
  without the `cmd/sync` truncation hazard. It exits non-zero if any Gen 2-7 game
  ends up with zero rows.
