## ADDED Requirements

### Requirement: DexNav formula
The system SHALL support the `dexnav_gen6` formula type. The odds scale based on `search_level` and `chain_length` provided in `hunt_parameters`.

#### Scenario: Search level bonus
- **WHEN** `search_level` is greater than 0
- **THEN** the base shiny rate is increased according to the DexNav search level thresholds

#### Scenario: Chain length bonus at 50
- **WHEN** `chain_length` is 50
- **THEN** a flat bonus of +5 rolls is applied

#### Scenario: Chain length bonus at 100
- **WHEN** `chain_length` is 100
- **THEN** a flat bonus of +10 rolls is applied
