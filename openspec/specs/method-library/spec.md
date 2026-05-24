# method-library Specification

## Purpose
Defines the methods API endpoint and the Method Library sidebar widget for browsing encounter methods by game.
## Requirements
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

### Requirement: Method Library sidebar widget
The left sidebar SHALL render a Method Library panel below the Odds Calculator panel, defaulting to collapsed.

#### Scenario: Panel is collapsed by default
- **WHEN** the sidebar is first rendered
- **THEN** the Method Library panel is collapsed and its content is not visible

#### Scenario: User expands the panel
- **WHEN** the user expands the Method Library panel
- **THEN** the widget fetches all methods from `GET /api/methods` and displays them in a scrollable list grouped by game

#### Scenario: User filters by game
- **WHEN** the user selects a game from the filter dropdown
- **THEN** the widget re-fetches with `?game_id=<id>` and shows only that game's methods

#### Scenario: Method row content
- **WHEN** a method row is displayed
- **THEN** it shows the method name, base rolls, charm rolls, avg time per encounter (formatted as seconds or minutes), and a "Recommended" badge if `is_recommended` is true

#### Scenario: No methods for selected game
- **WHEN** the selected game has no encounter methods
- **THEN** the list shows a "No methods found" empty state message

