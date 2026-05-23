## Why

The app cannot be published while large gaps in curated hunt methods exist — users get stuck when no method is available for their Pokémon/game combo, and the owner has no efficient way to bulk-populate missing methods. Both problems must be solved together: users need an escape hatch now, and the owner needs tooling to close the data gap efficiently.

## What Changes

- **Custom method option in hunt creation**: Users can type a free-text method name when no curated method covers their Pokémon/game combo. The hunt is created as a plain counter with no odds calculation.
- **CSV bulk import for admin**: A new upload endpoint and UI in the admin encounters page lets the owner paste or upload a CSV of hunt methods and insert them all at once, replacing the current per-row form and terminal seed scripts.
- **No odds/ETA for custom methods**: Custom hunts track encounter count only. The "fastest method" recommendation feature continues to rely exclusively on curated methods with full data.

## Capabilities

### New Capabilities

- `custom-hunt-method`: A user-defined free-text method attached to a hunt when no curated encounter row is selected. Stored on the hunt record; no `encounter_id` foreign key. Counter still increments normally.
- `admin-csv-import`: A CSV upload flow in the admin encounters panel that parses rows and bulk-inserts hunt methods, with per-row conflict reporting.

### Modified Capabilities

- `admin-encounters`: Existing admin encounters page gains a CSV import section alongside the existing per-row add form.

## Impact

- **Backend**: New `POST /api/admin/encounters/import` endpoint; `user_hunts` table needs to allow `encounter_id` to be NULL when a custom method is used, and store `custom_method_name` for display.
- **Frontend**: `NewHuntModal` gains a "Use custom method" option at the bottom of the method list; `AdminEncounters` gains a CSV upload/preview UI.
- **Database**: `user_hunts.encounter_id` must become nullable (if not already); add `custom_method_name TEXT` column.
- **No breaking changes** to existing hunt or encounter APIs.
