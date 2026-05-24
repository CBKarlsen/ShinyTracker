## MODIFIED Requirements

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
