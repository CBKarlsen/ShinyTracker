# admin-availability Specification

## Purpose
Defines admin management of per-game Pokemon availability (get and set) and the Availability admin page.

## Requirements

### Requirement: Get availability for a Pokémon
The system SHALL expose `GET /api/admin/availability?pokemon_id=<id>` returning all games with a flag indicating whether the Pokémon is available in each.

#### Scenario: Pokémon with partial availability
- **WHEN** a valid `pokemon_id` is provided
- **THEN** the response is a JSON array of all games, each with `game_id`, `game_title`, and `available: bool`

### Requirement: Set availability
The system SHALL expose `PUT /api/admin/availability` accepting `{ pokemon_id, game_id, available: bool }` and upserting or deleting the corresponding `pokemon_availability` row.

#### Scenario: Mark as available
- **WHEN** `available: true` is sent for a pokemon_id + game_id pair
- **THEN** a row is inserted into `pokemon_availability` (or ignored if already present)

#### Scenario: Mark as unavailable
- **WHEN** `available: false` is sent
- **THEN** the row is deleted from `pokemon_availability` (no-op if not present)

#### Scenario: Missing fields
- **WHEN** `pokemon_id` or `game_id` is missing
- **THEN** the response is `400 Bad Request`

### Requirement: Availability admin page
The admin availability page SHALL allow the admin to search for a Pokémon by name, then display a checklist of all games with toggles for availability.

#### Scenario: Search and load
- **WHEN** the admin selects a Pokémon
- **THEN** the checklist shows all games with checked state reflecting current availability

#### Scenario: Toggle availability
- **WHEN** the admin checks or unchecks a game
- **THEN** the change is persisted immediately via `PUT /api/admin/availability`
