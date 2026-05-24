## ADDED Requirements

### Requirement: Odds data is returned by the hunts API
The GET `/api/hunts` response SHALL include `base_rolls`, `charm_rolls`, `avg_time_seconds`, `base_odds`, and `has_shiny_charm` for each hunt where an encounter record exists. Fields SHALL be null for hunts with no `encounter_id`.

#### Scenario: Hunt with an encounter record
- **WHEN** a hunt has a non-null `encounter_id`
- **THEN** the response includes non-null `base_rolls`, `charm_rolls`, `avg_time_seconds`, `base_odds`, and `has_shiny_charm`

#### Scenario: Manual acquisition hunt
- **WHEN** a hunt has a null `encounter_id`
- **THEN** `base_rolls`, `charm_rolls`, `avg_time_seconds`, `base_odds`, and `has_shiny_charm` are null in the response

### Requirement: Hunt card displays expected encounter count
The hunt card SHALL display the computed expected encounter count when odds data is available. Expected encounters = `floor(base_odds / (base_rolls + (has_shiny_charm ? charm_rolls : 0)))`.

#### Scenario: Odds data available
- **WHEN** a hunt card has non-null odds data
- **THEN** the card shows the expected encounter count (e.g., "Expected: ~819 encounters")

#### Scenario: No odds data
- **WHEN** odds data is null (manual acquisition)
- **THEN** the expected count is not displayed

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
