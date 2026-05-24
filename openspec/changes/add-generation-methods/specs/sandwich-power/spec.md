## ADDED Requirements

### Requirement: Sandwich Power formula
The system SHALL support the `sandwich_power_sv` formula type. The odds scale based on the `sparkling_power` provided in `hunt_parameters`.

#### Scenario: Sparkling Power 1
- **WHEN** `sparkling_power` is 1
- **THEN** 1 additional roll is added to the base rolls

#### Scenario: Sparkling Power 2
- **WHEN** `sparkling_power` is 2
- **THEN** 2 additional rolls are added to the base rolls

#### Scenario: Sparkling Power 3
- **WHEN** `sparkling_power` is 3
- **THEN** 3 additional rolls are added to the base rolls
