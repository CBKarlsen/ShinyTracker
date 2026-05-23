## ADDED Requirements

### Requirement: List all games (admin)
The system SHALL expose `GET /api/admin/games` returning all games including `supports_breeding`.

#### Scenario: Games exist
- **WHEN** the endpoint is called
- **THEN** the response is a JSON array of all games with fields: `id`, `title`, `generation`, `base_odds`, `supports_breeding`

### Requirement: Create game
The system SHALL expose `POST /api/admin/games` accepting `title`, `generation`, `base_odds`, `supports_breeding`.

#### Scenario: Valid creation
- **WHEN** all required fields are provided
- **THEN** a new game row is inserted and returned with its assigned `id`

#### Scenario: Duplicate title
- **WHEN** a game with the same `title` already exists
- **THEN** the response is `409 Conflict`

### Requirement: Update game
The system SHALL expose `PUT /api/admin/games/{id}` accepting any subset of updatable fields.

#### Scenario: Valid update
- **WHEN** a valid game `id` and at least one field are provided
- **THEN** the game is updated and the updated row is returned

#### Scenario: Unknown game
- **WHEN** the game `id` does not exist
- **THEN** the response is `404 Not Found`

### Requirement: Delete game (guarded)
The system SHALL expose `DELETE /api/admin/games/{id}`. If any encounters reference the game, the delete SHALL be rejected.

#### Scenario: Game with no encounters
- **WHEN** a valid game `id` is provided and no encounters reference it
- **THEN** the game is deleted and the response is `200 OK`

#### Scenario: Game with existing encounters
- **WHEN** encounters exist for the game
- **THEN** the response is `409 Conflict` with a message indicating encounters must be removed first

### Requirement: Games admin page
The admin games page SHALL list all games in a table and allow the admin to add, edit, and delete games.

#### Scenario: Add game
- **WHEN** the admin fills in the add-game form and submits
- **THEN** the new game appears in the table

#### Scenario: Edit game
- **WHEN** the admin edits a game's fields and saves
- **THEN** the row updates in place

#### Scenario: Delete blocked by encounters
- **WHEN** the admin attempts to delete a game that has encounters
- **THEN** an error message is shown explaining encounters must be removed first
