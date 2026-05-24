## ADDED Requirements

### Requirement: Cumulative probability display
Each active hunt card SHALL compute and display the cumulative probability that the shiny would have been found by the current encounter count, using the formula `P = 1 - (1 - rolls/base_odds)^encounters`. When `has_shiny_charm` is true, `charm_rolls` SHALL be used instead of `base_rolls`.

#### Scenario: Hunt with method and game shows probability
- **WHEN** a hunt card has non-null `base_odds`, `base_rolls`, and `encounter_count > 0`
- **THEN** the card displays a percentage (e.g. "63%") representing cumulative probability

#### Scenario: Hunt without odds data shows no indicator
- **WHEN** a hunt card has null `base_odds` or null `base_rolls`
- **THEN** the odds section is omitted entirely from the card

#### Scenario: Shiny charm uses charm rolls
- **WHEN** `has_shiny_charm` is true and `charm_rolls` is non-null
- **THEN** the probability is computed using `charm_rolls` instead of `base_rolls`

### Requirement: Probability progress bar
The hunt card SHALL display a horizontal progress bar whose fill width corresponds to the cumulative probability percentage.

#### Scenario: Bar fills proportionally
- **WHEN** cumulative probability is 63%
- **THEN** the bar is filled to 63% of its total width

#### Scenario: Bar does not overflow
- **WHEN** cumulative probability reaches or exceeds 100%
- **THEN** bar fill is capped at 100% width

### Requirement: Luck label
The hunt card SHALL display a short contextual luck label based on the cumulative probability.

#### Scenario: Low cumulative probability shows lucky label
- **WHEN** cumulative probability is below 33%
- **THEN** label reads "running lucky"

#### Scenario: Mid cumulative probability shows average label
- **WHEN** cumulative probability is between 33% and 66%
- **THEN** label reads "about average"

#### Scenario: High cumulative probability shows warning label
- **WHEN** cumulative probability is between 67% and 90%
- **THEN** label reads "pushing your luck"

#### Scenario: Very high cumulative probability shows overdue label
- **WHEN** cumulative probability exceeds 90%
- **THEN** label reads "overdue"

### Requirement: Zero encounter fallback
When encounter count is zero, the odds section SHALL render with 0% probability and no luck label (since no hunting has occurred yet).

#### Scenario: Zero encounters shows 0%
- **WHEN** `encounter_count` is 0 and odds data is present
- **THEN** probability displays as "0%" and the bar is empty, with no luck label shown
