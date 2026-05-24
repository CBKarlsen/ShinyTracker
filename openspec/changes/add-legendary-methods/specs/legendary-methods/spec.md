## ADDED Requirements

### Requirement: Legendary Hunting Methods
The system SHALL support specific hunting methods historically used for legendaries, such as "Soft Reset (Static)" and "Run Away", ensuring they apply to all relevant games via the `always_true` condition (which defaults as the primary methods for legendaries due to exclusions elsewhere).

#### Scenario: Soft Reset (Static) is available
- **WHEN** a user searches for methods available for a legendary Pokémon like Rayquaza
- **THEN** "Soft Reset (Static)" is listed as an available method

#### Scenario: Run Away is available
- **WHEN** a user searches for methods available for a legendary Pokémon in supported modern titles
- **THEN** "Run Away" is listed as an available method
