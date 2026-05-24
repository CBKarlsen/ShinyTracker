# hunt-odds-display Specification

## Purpose
Defines the odds data returned by the hunts API and how the hunt card displays expected encounter count and time (replacing the progress bar).

## Requirements

### Requirement: Odds data is returned by the hunts API
The GET `/api/hunts` response SHALL include `base_rolls`, `charm_rolls`, `avg_time_seconds`, `base_odds`, and `has_shiny_charm` for each hunt where an encounter record exists. Fields SHALL be null for hunts with no `encounter_id`.

#### Scenario: Hunt with an encounter record
- **WHEN** a hunt has a non-null `encounter_id`
- **THEN** the response includes non-null `base_rolls`, `charm_rolls`, `avg_time_seconds`, `base_odds`, and `has_shiny_charm`

#### Scenario: Manual acquisition hunt
- **WHEN** a hunt has a null `encounter_id`
- **THEN** `base_rolls`, `charm_rolls`, `avg_time_seconds`, `base_odds`, and `has_shiny_charm` are null in the response

### Requirement: Hunt card displays expected encounter count
The hunt card SHALL display the computed expected encounter count when odds data is available. Expected encounters = the denominator produced by the odds calculator function based on `base_odds`, `formula_type`, and the current `hunt_parameters`. The display SHALL immediately recalculate when `hunt_parameters` change.

#### Scenario: Odds data available
- **WHEN** a hunt card has non-null odds data
- **THEN** the card shows the expected encounter count (e.g., "~819 expected")

#### Scenario: No odds data
- **WHEN** odds data is null (manual acquisition)
- **THEN** the expected count is not displayed

#### Scenario: Parameters updated
- **WHEN** a user updates the method parameters (e.g., defeats from 30 to 60)
- **THEN** the expected encounter count immediately updates to reflect the new odds

### Requirement: Hunt card displays expected time
The hunt card SHALL display the estimated total hunt time in hours when odds data is available. Expected time = `(expected_encounters × avg_time_seconds) / 3600`, rounded to one decimal place.

#### Scenario: Expected time calculated
- **WHEN** a hunt card has non-null odds data
- **THEN** the card shows estimated time (e.g., "Expected: ~4.2 h")

### Requirement: Progress bar is removed
The linear progress bar showing `(encounter_count / 4096) × 100%` SHALL be removed from hunt cards.

#### Scenario: Hunt card rendered
- **WHEN** any active hunt card is displayed
- **THEN** no LinearProgress component is rendered
