## 1. Schema & migration

- [x] 1.1 Add `migrations/00X_drop_is_recommended.sql` with `ALTER TABLE hunt_methods DROP COLUMN IF EXISTS is_recommended;` (created `005_drop_is_recommended.sql`)
- [x] 1.2 Remove the `is_recommended BOOLEAN DEFAULT FALSE` column from `backend/schema.sql` (hunt_methods)
- [x] 1.3 Apply the migration against the running database and confirm the column is gone (applied 005; `SELECT is_recommended` now errors with "column does not exist")

## 2. Seed & retired tooling

- [x] 2.1 Remove the `IsRecommended` struct field and the `is_recommended` column from the INSERT in `backend/cmd/seed/main.go`
- [x] 2.2 Remove `is_recommended` keys from every entry in `backend/seeds/hunt_methods.json`
- [x] 2.3 Delete `backend/cmd/migrate_recommended/` and `backend/migrations/002_add_is_recommended.sql`
- [x] 2.4 Update `CLAUDE.md` command list to drop the `migrate_recommended` reference (also dropped stale `is_recommended` from the schema doc)

## 3. Backend API

- [x] 3.1 In `internal/api/handlers.go`: remove `IsRecommended` from `HuntMethodDetail` and `MethodDetail`, drop `hm.is_recommended` from the queries (lines ~294, ~408), and remove it from the row `Scan` calls
- [x] 3.2 In `internal/api/admin.go`: remove `is_recommended` from the list query/Scan, the create INSERT + DTO, the update `COALESCE` clause + DTO, and drop it from the required CSV column set
- [x] 3.3 In `internal/api/admin.go` CSV import: ignore an `is_recommended` column if present (do not error on the extra header)

## 4. Frontend

- [x] 4.1 Remove `is_recommended` from `frontend/src/types/models.ts`
- [x] 4.2 In `NewHuntModal.tsx`: replace the `find((e) => e.is_recommended)` default-method selection with the first method in the generation-ordered list (removed the featured "Recommended" card; all methods now render in one list)
- [x] 4.3 Remove the "★ Best" badge from `MethodLibrary.tsx` and the `is_recommended` field on its local type (also removed the now-empty table column header)
- [x] 4.4 Remove the " ★" recommended marker from `OddsCalculator.tsx` and its local `is_recommended` field
- [x] 4.5 In `admin/AdminEncounters.tsx`: remove the `is_recommended` checkbox, table column, edit handling, CSV-template example string, and field from local types/initial state (fixed empty-row colSpan 8→7)
- [x] 4.6 Remove the `.reco-badge` and `.reco` card styles from `frontend/src/index.css` (re-added a neutral `.tag-badge` for the unrelated AdminUsers "you" tag that reused `.reco-badge`)

## 5. Verify

- [x] 5.1 Reseed locally (`go run ./cmd/seed/main.go`) and confirm it succeeds with no `is_recommended` references (3483 availability records, invariant checks passed)
- [x] 5.2 `npm run build` (frontend) passes; all backend packages touched by this change build (`cmd/seed`, `internal/...`, `cmd/api`). NOTE: `go build ./...` fails only on PRE-EXISTING duplicate `func main()` in root scratch files (`check_charmander.go`, `inspect_pikachu.go`, `migrate.go`, `update_json.go`) and `cmd/apply_schema` — unrelated to this change
- [ ] 5.3 Open New Hunt for Dratini: confirm no method is badged "recommended" and a sensible default method is preselected — PENDING: needs running app
- [ ] 5.4 Confirm admin encounters list, create, update, and CSV import still work without the column — PENDING: needs running app (see note below re: admin.go schema mismatch)
