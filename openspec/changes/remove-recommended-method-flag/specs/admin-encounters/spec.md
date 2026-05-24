## MODIFIED Requirements

### Requirement: List encounters for a Pokémon
The system SHALL expose `GET /api/admin/encounters?pokemon_id=<id>` returning all encounter rows for that Pokémon across all games.

#### Scenario: Pokémon with encounters
- **WHEN** a valid `pokemon_id` is provided
- **THEN** the response is a JSON array of encounter rows including `id`, `game_id`, `game_title`, `method_name`, `base_rolls`, `charm_rolls`, `avg_time_seconds`

#### Scenario: Pokémon with no encounters
- **WHEN** a valid `pokemon_id` is provided but no encounters exist
- **THEN** the response is an empty JSON array

#### Scenario: Missing pokemon_id
- **WHEN** `pokemon_id` is omitted
- **THEN** the response is `400 Bad Request`

### Requirement: Create encounter
The system SHALL expose `POST /api/admin/encounters` accepting a JSON body with `pokemon_id`, `game_id`, `method_name`, `base_rolls`, `charm_rolls`, `avg_time_seconds`.

#### Scenario: Valid creation
- **WHEN** all required fields are provided and valid
- **THEN** a new encounter row is inserted and returned with its assigned `id`

#### Scenario: Duplicate encounter
- **WHEN** an encounter with the same `pokemon_id`, `game_id`, and `method_name` already exists
- **THEN** the response is `409 Conflict`
