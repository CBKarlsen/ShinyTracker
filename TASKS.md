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
- **#4 Modern method odds** — first-class `hunt_parameters`/`formula_type` for SV Sparkling-Power + Mass-Outbreak chaining, Gen 7 SOS, ORAS DexNav, Gen 4/6 Poké Radar. Multiplicative stacking (SV best ≈ 1/512). Uses existing `hunt_parameters` JSONB — no DDL.
- **#5 Completion forecast** — project total encounters/hours to finish the chosen dex from remaining targets' best-route ETAs. Forward-looking counterpart to `Stats.tsx`.
- **#6 Acquisition provenance filters** — filter the dex by Hunted/Evolved/Traded/Manual (`acquisition_type` already exists, just not surfaced). "Self-caught dex" sub-goal. Small.
- **#7 Bulk import** — CSV/Home-export import to mark many owned shinies at once instead of clicking each cell.

---

## 🐞 Follow-ups / known issues

- **`hunt_parameters` dropped on curated hunts** — `CreateHuntHandler` (`backend/internal/api/hunts.go`) hard-sets `hunt_parameters = '{}'` for `hunt_method_id` hunts, so the modal's params editor is cosmetic for those. Fix needed before #4 (modern method odds) can persist params.
- **Masuda labeling** — Masuda still shows broadly for base forms (correct), but consider clearer labels for the evolve-from flow. Method-engine concern.
- **Forms / regional variants** — not representable (see #3). Larger data-model change.

---

## Operational notes (for re-seeding the shared Supabase DB)

- **Seed order matters:** `cmd/sync` truncates `hunt_methods` (cascading `method_availability` to 0). Always run **`cmd/seed` LAST**. Full rebuild: `apply_schema` → `cmd/sync` (slow PokeAPI crawl; populates `evolves_from_id`) → `cmd/seed` → `cmd/seed_shiny_locks`.
- `cmd/apply_schema` is destructive to the method tables (drops `hunt_methods`/`method_*`); `cmd/seed` rebuilds them.
- Health check: `go run ./cmd/audit_methods/main.go` (Section B = real availability inconsistencies).
