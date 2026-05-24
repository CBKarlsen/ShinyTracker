## MODIFIED Requirements

### Requirement: Admin can upload a CSV of hunt methods
The system SHALL expose `POST /api/admin/encounters/import` accepting a CSV body (content-type `text/csv` or multipart) with columns `pokemon_id,game_id,method_name,base_rolls,charm_rolls,avg_time_seconds`. An `is_recommended` column, if present, SHALL be ignored. Each row SHALL be upserted independently; failures on individual rows SHALL NOT roll back successful rows.

#### Scenario: All rows valid
- **WHEN** the admin uploads a CSV where every row has valid, non-conflicting data
- **THEN** all rows are inserted and the response is a JSON array where every entry has `status: "inserted"`

#### Scenario: Duplicate row skipped
- **WHEN** a CSV row matches an existing `(pokemon_id, game_id, method_name)` combination
- **THEN** that row's entry in the response has `status: "skipped"` and the existing DB row is unchanged

#### Scenario: Legacy is_recommended column ignored
- **WHEN** the uploaded CSV still includes an `is_recommended` column
- **THEN** the importer processes the row normally and ignores the `is_recommended` value

#### Scenario: Malformed row reported
- **WHEN** a CSV row has a missing required column or a non-numeric value where a number is expected
- **THEN** that row's entry in the response has `status: "error"` and a `message` describing the problem; other rows are processed normally

#### Scenario: Empty CSV rejected
- **WHEN** the uploaded CSV has no data rows (header only or completely empty)
- **THEN** the response SHALL be `400 Bad Request`

#### Scenario: Non-admin access denied
- **WHEN** a non-admin user calls the import endpoint
- **THEN** the response SHALL be `403 Forbidden`
