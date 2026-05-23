## ADDED Requirements

### Requirement: List encounters for a Pokémon
The system SHALL expose `GET /api/admin/encounters?pokemon_id=<id>` returning all encounter rows for that Pokémon across all games.

#### Scenario: Pokémon with encounters
- **WHEN** a valid `pokemon_id` is provided
- **THEN** the response is a JSON array of encounter rows including `id`, `game_id`, `game_title`, `method_name`, `base_rolls`, `charm_rolls`, `avg_time_seconds`, `is_recommended`

#### Scenario: Pokémon with no encounters
- **WHEN** a valid `pokemon_id` is provided but no encounters exist
- **THEN** the response is an empty JSON array

#### Scenario: Missing pokemon_id
- **WHEN** `pokemon_id` is omitted
- **THEN** the response is `400 Bad Request`

### Requirement: Create encounter
The system SHALL expose `POST /api/admin/encounters` accepting a JSON body with `pokemon_id`, `game_id`, `method_name`, `base_rolls`, `charm_rolls`, `avg_time_seconds`, `is_recommended`.

#### Scenario: Valid creation
- **WHEN** all required fields are provided and valid
- **THEN** a new encounter row is inserted and returned with its assigned `id`

#### Scenario: Duplicate encounter
- **WHEN** an encounter with the same `pokemon_id`, `game_id`, and `method_name` already exists
- **THEN** the response is `409 Conflict`

### Requirement: Update encounter
The system SHALL expose `PUT /api/admin/encounters/{id}` accepting a JSON body with any subset of updatable fields.

#### Scenario: Valid update
- **WHEN** a valid encounter `id` and at least one field are provided
- **THEN** the encounter is updated and the updated row is returned

#### Scenario: Unknown encounter
- **WHEN** the encounter `id` does not exist
- **THEN** the response is `404 Not Found`

### Requirement: Delete encounter
The system SHALL expose `DELETE /api/admin/encounters/{id}` removing the encounter row.

#### Scenario: Valid deletion
- **WHEN** a valid encounter `id` is provided
- **THEN** the row is deleted and the response is `200 OK`

#### Scenario: Unknown encounter
- **WHEN** the encounter `id` does not exist
- **THEN** the response is `404 Not Found`

### Requirement: Encounters admin page
The admin encounters page SHALL allow the admin to search for a Pokémon by name, view its current encounter rows in a table, and add, edit, or delete rows inline. The page SHALL also include a CSV import section (see `admin-csv-import`) that operates independently of the per-Pokémon search flow.

#### Scenario: Search and load
- **WHEN** the admin types a Pokémon name and selects from results
- **THEN** the encounter table populates with that Pokémon's current rows

#### Scenario: Add new encounter
- **WHEN** the admin fills in the add-row form and submits
- **THEN** the new encounter appears in the table without a page reload

#### Scenario: Edit existing encounter
- **WHEN** the admin clicks edit on a row, modifies a field, and saves
- **THEN** the row updates in place

#### Scenario: Delete encounter
- **WHEN** the admin clicks delete on a row and confirms
- **THEN** the row is removed from the table

#### Scenario: CSV import section is visible without selecting a Pokémon
- **WHEN** the admin visits the encounters page
- **THEN** the CSV import section SHALL be visible and usable regardless of whether a Pokémon has been searched
