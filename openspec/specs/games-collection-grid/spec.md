## Requirements

### Requirement: Games displayed as card grid grouped by generation
The system SHALL render the games collection as a responsive card grid where games are grouped under labeled generation headers, sorted in ascending generation order.

#### Scenario: Games grouped by generation
- **WHEN** the Games tab loads successfully
- **THEN** each generation with at least one game SHALL have a labeled section header
- **THEN** game cards SHALL appear under their respective generation header

#### Scenario: Responsive grid layout
- **WHEN** the viewport is narrow (mobile)
- **THEN** cards SHALL display 2 per row
- **WHEN** the viewport is medium or wider
- **THEN** cards SHALL display 3–4 per row

### Requirement: Owned vs. unowned games are visually distinct
The system SHALL clearly distinguish owned games from unowned games without requiring the user to read text labels.

#### Scenario: Owned game appearance
- **WHEN** a game is in the user's owned list
- **THEN** its card SHALL display at full opacity with a colored border

#### Scenario: Unowned game appearance
- **WHEN** a game is not in the user's owned list
- **THEN** its card SHALL be visually dimmed (reduced opacity)

### Requirement: Click-to-own interaction on game card
The system SHALL allow users to toggle game ownership by clicking the game card.

#### Scenario: Adding a game to collection
- **WHEN** the user clicks an unowned game card
- **THEN** the game SHALL be added to the user's collection
- **THEN** the card SHALL immediately update to the owned appearance (optimistic update)

#### Scenario: Removing a game from collection
- **WHEN** the user clicks an owned game card
- **THEN** the game SHALL be removed from the user's collection
- **THEN** the card SHALL immediately update to the unowned appearance (optimistic update)
- **THEN** if the game had Shiny Charm, the charm status SHALL also be cleared

### Requirement: Shiny Charm toggle on owned game cards
The system SHALL provide a Shiny Charm toggle within each owned game card.

#### Scenario: Charm button visible on owned cards
- **WHEN** a game is owned
- **THEN** a Shiny Charm icon button SHALL be visible and enabled on the card

#### Scenario: Charm button disabled on unowned cards
- **WHEN** a game is not owned
- **THEN** the Shiny Charm icon button SHALL be disabled

#### Scenario: Toggling charm on
- **WHEN** the user clicks the Shiny Charm button on an owned game that does not have the charm
- **THEN** the charm status SHALL be set to true and the button SHALL reflect the active state

#### Scenario: Toggling charm off
- **WHEN** the user clicks the Shiny Charm button on an owned game that has the charm
- **THEN** the charm status SHALL be set to false and the button SHALL reflect the inactive state
