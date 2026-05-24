## MODIFIED Requirements

### Requirement: Method Library sidebar widget
The left sidebar SHALL render a Method Library panel below the Odds Calculator panel, defaulting to collapsed. The UI SHALL visually distinguish methods if the currently selected Pokémon is a legendary or mythical.

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

#### Scenario: Legendary hunt styling
- **WHEN** the user is viewing methods for a Pokémon where `is_legendary` or `is_mythical` is true
- **THEN** the Method Library panel displays a "Legendary Hunt" badge or visual distinction

#### Scenario: No methods for selected game
- **WHEN** the selected game has no encounter methods
- **THEN** the list shows a "No methods found" empty state message
