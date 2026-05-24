## ADDED Requirements

### Requirement: Flag-Based Availability Rules
The system SHALL evaluate boolean flags (`is_legendary`, `is_mythical`) to determine method availability for a specific Pokémon.

#### Scenario: Rule explicitly excludes legendaries
- **WHEN** a method rule condition is set to exclude legendaries (e.g. `not_legendary_or_mythical`)
- **THEN** it does not generate an availability record if the Pokémon has `is_legendary` or `is_mythical` set to true

#### Scenario: Rule explicitly requires legendaries
- **WHEN** a method rule condition is set to require legendaries (e.g. `is_legendary`)
- **THEN** it only generates availability records for Pokémon with `is_legendary` set to true

#### Scenario: Pokemon API Sync captures flags
- **WHEN** the system synchronizes Pokémon data with PokeAPI
- **THEN** it extracts the `is_legendary` and `is_mythical` fields from the `/pokemon-species` endpoint and persists them in the database
