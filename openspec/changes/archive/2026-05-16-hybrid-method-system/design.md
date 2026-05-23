## Context

ShinyTracker's hunt system currently requires a `hunt_method_id` foreign key pointing to a curated `hunt_methods` row. When a Pokémon/game combination has no curated method, users cannot create a hunt at all. The `hunt_method_id` column in `user_hunts` is already nullable in the schema — the constraint is purely in application logic and the frontend modal.

Separately, the owner populates hunt methods one row at a time via the admin UI or by running `go run ./cmd/seed_fulldex/main.go` from the terminal. Neither workflow scales to 1025+ Pokémon across multiple games.

## Goals / Non-Goals

**Goals:**
- Allow users to start a hunt with a free-text method name when no curated method exists, without odds/ETA calculations.
- Give the admin a CSV upload flow in the existing encounters admin page to bulk-insert hunt methods without touching the terminal.

**Non-Goals:**
- Odds/ETA calculations for custom methods (no `base_rolls`, `charm_rolls`, `avg_time_seconds` data).
- User-editable method library (users cannot share or persist custom methods beyond their own hunt record).
- Replacing the existing per-row add form in the admin — CSV import is additive.

## Decisions

### 1. Store `custom_method_name` on `user_hunts`, keep `hunt_method_id` nullable

**Decision**: Add `custom_method_name TEXT` to `user_hunts`. A hunt has either `hunt_method_id` (curated) OR `custom_method_name` (user-defined), never both. The backend enforces this with a CHECK constraint.

**Alternative considered**: Reuse `hunt_parameters` JSONB to store the custom name. Rejected because it makes querying and display more complex, and `hunt_parameters` is an opaque blob.

**Alternative considered**: Insert a synthetic `hunt_methods` row when users define custom methods. Rejected because it pollutes the curated method table and makes admin data quality harder to maintain.

### 2. CSV import: parse server-side, return per-row results

**Decision**: The admin uploads a CSV (or pastes text); the backend parses it, attempts an upsert per row, and returns a JSON array of `{row, status: "inserted"|"skipped"|"error", message}`. The frontend shows a preview table before confirming.

**Alternative considered**: Parse CSV client-side and fire individual POST requests. Rejected because it is slower for large files and error handling across N requests is hard to surface clearly.

**CSV column order**: `pokemon_id,game_id,method_name,base_rolls,charm_rolls,avg_time_seconds,is_recommended` — matches the existing `hunt_methods` seed format in `FullDexMethods.csv`.

### 3. No migration framework — raw SQL migration script

**Decision**: Add a `cmd/migrate_custom_method/main.go` that runs `ALTER TABLE user_hunts ADD COLUMN IF NOT EXISTS custom_method_name TEXT, ADD CONSTRAINT ...`. Consistent with existing migration pattern in the repo.

## Risks / Trade-offs

- **CHECK constraint requires migration** → If the migration hasn't run, the backend returns a DB error on any hunt insert. Mitigation: document migration as a prerequisite; backend returns a clear 500 with a logged message if the column is missing.
- **Custom hunts show "—" for odds** → Users may be confused why some hunts have no ETA. Mitigation: display "Custom method — no odds data" explicitly in the dashboard card.
- **CSV import partial failures** → A malformed row stops that row but should not roll back the rest. Mitigation: parse each row independently in a loop; wrap each upsert in its own try; accumulate results and return all at once.

## Migration Plan

1. Run `go run ./cmd/migrate_custom_method/main.go` against the live DB (adds column + check constraint).
2. Deploy updated backend binary.
3. Deploy updated frontend build.
4. No rollback needed for the column addition (`ADD COLUMN IF NOT EXISTS` is safe). If rolling back the binary, old frontend simply won't show the custom method option; existing data is unaffected.
