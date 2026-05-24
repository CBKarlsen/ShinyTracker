## MODIFIED Requirements

### Requirement: Explicit Method to Game Mapping
The system SHALL map hunting methods to specific games via a join table, rather than inferring availability from generation numbers. Game mapping alone SHALL NOT make a method available for a Pokémon: the method is offered only when the Pokémon additionally has the method's required encounter kind in that game (see the `encounter-kind-availability` capability).

#### Scenario: Method exclusive to specific games
- **WHEN** a method like "SOS Chaining" is mapped exclusively to "Sun", "Moon", "Ultra Sun", and "Ultra Moon"
- **THEN** it does not appear as an option for "Let's Go Pikachu" despite sharing the same generation

#### Scenario: Method available in all games of a generation
- **WHEN** a method like "Random Encounter" is mapped to all games in Generation 7
- **THEN** it appears for all those games in which the target Pokémon has the required encounter kind

#### Scenario: Game-mapped method excluded when kind is absent
- **WHEN** a method is mapped to a game but the target Pokémon has no encounter-kind record matching the method's required kind in that game
- **THEN** the method is not offered for that Pokémon in that game
