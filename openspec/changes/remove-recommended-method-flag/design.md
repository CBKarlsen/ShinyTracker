## Context

`is_recommended` is a `BOOLEAN` column on `hunt_methods` (schema.sql:42). Because a method row is shared by every Pokemon that can use it (availability is derived through `method_availability`), the flag is inherently method-global. The seed sets `Poké Radar.is_recommended = true`, so every Gen 4 wild Pokemon — including water/fishing-only species like Dratini, where Poké Radar is invalid — surfaces Poké Radar as "recommended". The frontend then displays its chain-0 odds (1/65536 via the `radar_chain_gen4` formula) as if it were the suggested method.

The flag flows through: schema → `seeds/hunt_methods.json` → `cmd/seed/main.go` → API DTOs (`HuntMethodDetail`, `MethodDetail`, admin DTOs) → frontend types and four components. `NewHuntModal.tsx:103` also uses it to pick a default method.

## Goals / Non-Goals

**Goals:**
- Remove `is_recommended` end-to-end: schema column, seed, API contracts, admin CRUD/CSV, and frontend UI.
- Keep `NewHuntModal` working with a deterministic default-method selection that no longer depends on the flag.
- Provide a forward migration that drops the column without requiring a full reseed.

**Non-Goals:**
- Distinguishing wild encounter sub-kinds (grass vs surf vs fishing) so Poké Radar stops being *listed* for Dratini. That is a separate, larger change tracked as follow-up.
- Building a replacement recommendation engine (e.g. derived from best achievable odds/ETA). Not in scope; we remove the broken feature rather than rebuild it now.

## Decisions

- **Remove rather than fix per-Pokemon.** Making recommendation per-Pokemon would require new curation data and a recommendation model. The flag delivers negative value today (wrong guidance), so removal is the smaller, safer change. Alternative considered: move `is_recommended` onto `method_availability` (per Pokemon+game) — rejected as scope creep with no data to populate it correctly.
- **Default method in NewHuntModal = first entry of the generation-ordered list** returned by `GET /api/hunt-methods` (already `ORDER BY g.generation ASC, g.id ASC`). Deterministic and dependency-free. Alternative: lowest-ETA method — rejected as a new computation better suited to the future recommendation work.
- **Forward migration drops the column** (`ALTER TABLE hunt_methods DROP COLUMN IF EXISTS is_recommended`). The legacy add-column migration (`002_add_is_recommended.sql`) and `cmd/migrate_recommended` are retired since reseeding from the updated schema also produces a column-free table.
- **Admin CSV import**: drop `is_recommended` from the required column set. Existing CSVs that still include the column should not hard-fail on the extra header — the importer ignores unknown columns (verify during implementation).

## Risks / Trade-offs

- **Breaking API change** for any external consumer reading `is_recommended` → mitigation: this is an internal app with a single known frontend; remove the field from both sides in the same change.
- **Stale CSV templates** still listing the column → mitigation: update the admin UI's example/template string and accept (ignore) the extra column on import for backward compatibility.
- **Loss of the "Best/Recommended" badge UX** → accepted; the badge was misleading. Method rows still show name, rolls, and avg time.

## Migration Plan

1. Apply schema change (drop column) via a new `migrations/00X_drop_is_recommended.sql` against the running DB.
2. Deploy backend (DTOs/queries no longer reference the column) and frontend together to avoid a window where the frontend expects a field the API stopped sending.
3. Rollback: re-add the column with `DEFAULT FALSE` and redeploy prior binaries; no data loss since the flag carried no user-generated state.
