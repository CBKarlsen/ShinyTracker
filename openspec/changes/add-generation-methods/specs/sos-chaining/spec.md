## ADDED Requirements

### Requirement: SOS Chaining formula
The system SHALL support the `sos_chain_gen7` formula type. The odds dynamically scale based on the `chain_length` provided in `hunt_parameters`.

#### Scenario: Chain length 0-10
- **WHEN** `chain_length` is between 0 and 10
- **THEN** 0 additional rolls are added to the base rolls

#### Scenario: Chain length 11-20
- **WHEN** `chain_length` is between 11 and 20
- **THEN** 4 additional rolls are added to the base rolls

#### Scenario: Chain length 21-30
- **WHEN** `chain_length` is between 21 and 30
- **THEN** 8 additional rolls are added to the base rolls

#### Scenario: Chain length 31 or greater
- **WHEN** `chain_length` is 31 or greater
- **THEN** 12 additional rolls are added to the base rolls
