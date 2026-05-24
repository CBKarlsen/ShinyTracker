## ADDED Requirements

### Requirement: Explicit Method to Game Mapping
The system SHALL map hunting methods to specific games via a join table, rather than inferring availability from generation numbers.

#### Scenario: Method exclusive to specific games
- **WHEN** a method like "SOS Chaining" is mapped exclusively to "Sun", "Moon", "Ultra Sun", and "Ultra Moon"
- **THEN** it does not appear as an option for "Let's Go Pikachu" despite sharing the same generation

#### Scenario: Method available in all games of a generation
- **WHEN** a method like "Random Encounter" is mapped to all games in Generation 7
- **THEN** it appears for all those games
