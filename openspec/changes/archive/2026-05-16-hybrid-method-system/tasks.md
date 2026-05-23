## 1. Database Migration

- [x] 1.1 Create `cmd/migrate_custom_method/main.go` that runs `ALTER TABLE user_hunts ADD COLUMN IF NOT EXISTS custom_method_name TEXT`
- [x] 1.2 Add a CHECK constraint: `(hunt_method_id IS NOT NULL) != (custom_method_name IS NOT NULL)` — exactly one must be set
- [x] 1.3 Run the migration against the dev/Supabase database

## 2. Backend — Custom Hunt Method

- [x] 2.1 Update `CreateHunt` handler in `hunts.go` to accept `custom_method_name` in the request body alongside `hunt_method_id`
- [x] 2.2 Add validation: reject requests where both fields are set or neither is set (400)
- [x] 2.3 Update the `INSERT INTO user_hunts` query to include `custom_method_name`
- [x] 2.4 Update the `SELECT` query in `GetHunts` to return `custom_method_name` alongside `method_name` from the join
- [x] 2.5 Update the `Hunt` response struct in `models.go` to include `CustomMethodName *string`

## 3. Backend — CSV Import Endpoint

- [x] 3.1 Add `POST /api/admin/encounters/import` route in `router.go` (admin-auth protected)
- [x] 3.2 Implement `ImportHuntMethods` handler in `admin.go` that reads CSV from the request body
- [x] 3.3 Parse CSV rows with columns: `pokemon_id, game_id, method_name, base_rolls, charm_rolls, avg_time_seconds, is_recommended`
- [x] 3.4 For each row, attempt an upsert with `ON CONFLICT (pokemon_id, game_id, method_name) DO NOTHING`; record `inserted`, `skipped`, or `error` status
- [x] 3.5 Return a JSON array of `{row_number, status, message}` for every row processed
- [x] 3.6 Return 400 if the CSV has no data rows

## 4. Frontend — NewHuntModal Custom Method

- [x] 4.1 Add a "Use custom method" entry at the bottom of the method list in `NewHuntModal.tsx`
- [x] 4.2 When selected, show a text input for the custom method name below the method list
- [x] 4.3 Disable the confirm button when custom method is selected but the input is empty
- [x] 4.4 On confirm, send `custom_method_name` instead of `hunt_method_id` in the POST body

## 5. Frontend — Dashboard Custom Hunt Display

- [x] 5.1 Update the active hunt card in `Dashboard.tsx` to display `custom_method_name` when `hunt_method_id` is null
- [x] 5.2 Show "Custom method — no odds data" in place of the odds/ETA row for custom hunts

## 6. Frontend — Admin CSV Import UI

- [x] 6.1 Add a "CSV Import" section to `AdminEncounters.tsx` with a textarea and an Import button
- [x] 6.2 On import, POST the textarea contents to `POST /api/admin/encounters/import`
- [x] 6.3 Render the results in a table with columns: row number, status (color-coded), message
- [x] 6.4 Replace results table on each subsequent import run
