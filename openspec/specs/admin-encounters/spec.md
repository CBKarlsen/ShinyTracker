# admin-encounters Specification

## Purpose
Defines the admin Encounters page and its API. In the rules-based model, hunt
methods are GLOBAL definitions and a Pokémon's available methods are derived into
`method_availability` (see `cmd/seed`). The admin surface is therefore a
read-only per-Pokémon view of derived availability, plus edit/delete that act on
the global method definition. There is no per-Pokémon create or CSV import.

## Requirements

### Requirement: List a Pokémon's available methods
The system SHALL expose `GET /api/admin/hunt-methods?pokemon_id=<id>` returning
the methods available to that Pokémon (derived from `method_availability`),
joined to the games it is available in.

#### Scenario: Pokémon with available methods
- **WHEN** a valid `pokemon_id` is provided
- **THEN** the response is a JSON array of rows including `id` (the global method id), `pokemon_id`, `game_id`, `game_title`, `method_name`, `base_rolls`, `charm_rolls`, `avg_time_seconds`, `formula_type`

#### Scenario: Pokémon with no available methods
- **WHEN** a valid `pokemon_id` is provided but no methods are available
- **THEN** the response is an empty JSON array

#### Scenario: Missing pokemon_id
- **WHEN** `pokemon_id` is omitted
- **THEN** the response is `400 Bad Request`

### Requirement: Update a global method
The system SHALL expose `PUT /api/admin/hunt-methods/{id}` accepting a JSON body with any subset of `method_name`, `base_rolls`, `charm_rolls`, `avg_time_seconds`, `formula_type`, `requires_terrain`. The update applies to the GLOBAL method and therefore affects every Pokémon and game it is available for.

#### Scenario: Valid update
- **WHEN** a valid method `id` and at least one field are provided
- **THEN** the method is updated and the response is `200 OK`

#### Scenario: Unknown method
- **WHEN** the method `id` does not exist
- **THEN** the response is `404 Not Found`

### Requirement: Delete a global method
The system SHALL expose `DELETE /api/admin/hunt-methods/{id}` removing the global method definition (and, by cascade, its availability rows).

#### Scenario: Valid deletion
- **WHEN** a valid method `id` is provided
- **THEN** the method is deleted and the response is `200 OK`

#### Scenario: Unknown method
- **WHEN** the method `id` does not exist
- **THEN** the response is `404 Not Found`

### Requirement: Encounters admin page
The admin encounters page SHALL allow the admin to search for a Pokémon by name and view its available methods in a read-only table, with inline edit and delete acting on the global method. The page SHALL make clear that edits/deletes affect the global method definition. There is no add-row form or CSV import.

#### Scenario: Search and load
- **WHEN** the admin types a Pokémon name and selects from results
- **THEN** the table populates with that Pokémon's available methods

#### Scenario: Edit a method inline
- **WHEN** the admin clicks edit on a row, modifies a field, and saves
- **THEN** the row updates in place and the change persists to the global method

#### Scenario: Delete a method
- **WHEN** the admin clicks delete on a row and confirms
- **THEN** the row is removed and the global method is deleted
