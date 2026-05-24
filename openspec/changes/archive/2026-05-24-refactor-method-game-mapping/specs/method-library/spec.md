## MODIFIED Requirements

### Requirement: Methods API endpoint
The system SHALL expose `GET /api/methods` returning all encounter methods. An optional `?game_id=<id>` query parameter SHALL filter results to a single game using strict game-method joins instead of generation matching.

#### Scenario: Fetch all methods
- **WHEN** a request is made to `GET /api/methods` with no query params
- **THEN** the response is a JSON array of all encounters with fields: `id`, `game_id`, `game_title`, `method_name`, `base_rolls`, `charm_rolls`, `avg_time_seconds`, `is_recommended`

#### Scenario: Filter by game
- **WHEN** a request is made with `?game_id=<id>`
- **THEN** the response contains only encounters strictly mapped to that game via the method_games join table

#### Scenario: Unknown game_id
- **WHEN** `game_id` is provided but does not match any game
- **THEN** the response is an empty JSON array (not an error)
