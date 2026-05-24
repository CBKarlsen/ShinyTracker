## Why

The "recommended method" feature is structurally broken: `is_recommended` is a single boolean on the `hunt_methods` row, so it is shared by every Pokemon that uses that method. Poké Radar is flagged recommended for *all* Gen 4 wild Pokemon, including water/fishing-only species like Dratini where Poké Radar is invalid — surfacing it as the recommended method with a misleading 1/65536 starting figure. One global flag can never express a per-Pokemon recommendation, so the feature produces wrong guidance and adds surface area across schema, seed, API, and four frontend components for negative value.

## What Changes

- **BREAKING**: Remove the `is_recommended` column from the `hunt_methods` table.
- Remove `is_recommended` from the seed model and `seeds/hunt_methods.json` entries.
- Remove `is_recommended` from API responses (`GET /api/hunt-methods`, `GET /api/methods`, admin encounter list/create/update) and from the admin CSV import column set.
- Remove the "Recommended"/"★ Best" badge from the Method Library and Odds Calculator, and the recommended checkbox/column from the admin encounters UI.
- Replace `NewHuntModal`'s "auto-select the recommended method" behavior with a deterministic fallback (first method in the returned, generation-ordered list).
- Drop the now-obsolete migration helper (`cmd/migrate_recommended`) and `migrations/002_add_is_recommended.sql` from the active path; add a migration to drop the column.

Out of scope (documented follow-up): Poké Radar will still *appear* in Dratini's method list because `method_availability` is computed only at encounter-`kind` granularity (`wild` vs `static`/`raid`/`egg`) and cannot distinguish grass from surf/fishing. Fixing that requires finer encounter sub-kinds and is tracked separately.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `method-library`: `GET /api/methods` response no longer includes `is_recommended`; the Method Library no longer renders a "Recommended" badge.
- `admin-encounters`: admin encounter list/create endpoints no longer accept or return `is_recommended`.
- `admin-csv-import`: the import CSV column set no longer includes `is_recommended`.

## Impact

- **Schema**: `backend/schema.sql` (`hunt_methods.is_recommended`); new drop-column migration.
- **Backend**: `cmd/seed/main.go` (struct + INSERT), `seeds/hunt_methods.json`, `internal/api/handlers.go` (`HuntMethodDetail`, `MethodDetail`, two queries), `internal/api/admin.go` (list/create/import/update + required CSV columns), `cmd/migrate_recommended`, `migrations/002_add_is_recommended.sql`.
- **Frontend**: `types/models.ts`, `components/NewHuntModal.tsx` (default-method selection), `components/MethodLibrary.tsx`, `components/OddsCalculator.tsx`, `components/admin/AdminEncounters.tsx`, badge styles in `index.css`.
- **API consumers**: any client reading `is_recommended` must stop relying on it (breaking).
