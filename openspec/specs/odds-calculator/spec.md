# odds-calculator Specification

## Purpose
Defines the odds API endpoint and the Odds Calculator sidebar widget.

## Requirements

### Requirement: Odds API endpoint
The system SHALL expose `GET /api/odds?encounter_id=<id>&shiny_charm=<bool>` returning computed shiny odds for a given encounter method.

#### Scenario: Valid encounter with charm
- **WHEN** a request is made with a valid `encounter_id` and `shiny_charm=true`
- **THEN** the response includes `fraction` (e.g. "1/1365"), `percentage` (e.g. "0.073%"), `expected_encounters` (integer), and `eta_hours` (float, one decimal)

#### Scenario: Valid encounter without charm
- **WHEN** a request is made with a valid `encounter_id` and `shiny_charm=false`
- **THEN** the response includes correct odds computed using `base_rolls` only

#### Scenario: Unknown encounter ID
- **WHEN** a request is made with an `encounter_id` that does not exist in the database
- **THEN** the response is `404 Not Found`

#### Scenario: Missing encounter_id parameter
- **WHEN** `encounter_id` is omitted from the request
- **THEN** the response is `400 Bad Request`

### Requirement: Odds Calculator sidebar widget
The left sidebar SHALL render an Odds Calculator panel below the Stats panel, defaulting to collapsed.

#### Scenario: Panel is collapsed by default
- **WHEN** the sidebar is first rendered
- **THEN** the Odds Calculator panel is collapsed and its inputs are not visible

#### Scenario: User expands and selects a game
- **WHEN** the user expands the panel and selects a game from the dropdown
- **THEN** the method dropdown is populated with encounter methods available for that game

#### Scenario: User selects a method
- **WHEN** the user selects a method
- **THEN** the widget calls `GET /api/odds` and displays the resulting odds fraction, percentage, and ETA

#### Scenario: User toggles Shiny Charm
- **WHEN** the user toggles the Shiny Charm checkbox
- **THEN** the widget re-fetches odds and updates the displayed values

#### Scenario: No method available
- **WHEN** the selected game has no encounter methods in the database
- **THEN** the method dropdown shows "No methods available" and odds are not displayed
