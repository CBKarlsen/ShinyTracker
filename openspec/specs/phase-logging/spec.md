# phase-logging Specification

## Purpose
Defines logging a phase during an active hunt, adding the phased Pokemon to the user's collection, and returning phase history in the hunts API.

## Requirements

### Requirement: User can log a phase during an active hunt
The system SHALL provide a `POST /api/hunts/:id/phases` endpoint that records a phase for the given hunt. The request body SHALL include `pokemon_id` (the phase Pokémon). On success the system SHALL atomically: insert a `hunt_phases` row capturing the current encounter count and phase Pokémon, reset the hunt's `encounter_count` to 0, and increment the hunt's `phase_count` by 1.

#### Scenario: Valid phase log
- **WHEN** a user sends `POST /api/hunts/:id/phases` with a valid `pokemon_id` for an active hunt they own
- **THEN** a `hunt_phases` row is inserted with `pokemon_id`, `encounter_count_at_phase` equal to the hunt's current count, and `created_at` timestamp; `user_hunts.encounter_count` is set to 0; `user_hunts.phase_count` is incremented by 1; HTTP 200 is returned with the updated hunt object

#### Scenario: Phase on non-existent or completed hunt
- **WHEN** a user sends `POST /api/hunts/:id/phases` for a hunt that does not exist or has status `completed`
- **THEN** HTTP 404 or 400 is returned and no rows are mutated

#### Scenario: Phase logged by wrong user
- **WHEN** a user sends `POST /api/hunts/:id/phases` for a hunt owned by a different user
- **THEN** HTTP 404 is returned (hunt not visible to requester)

### Requirement: Phase Pokémon is added to the user's shiny collection
The system SHALL upsert the phase Pokémon into `user_collection` with `acquisition_type = 'HUNTED'` when a phase is logged.

#### Scenario: Phase Pokémon not yet in collection
- **WHEN** a phase is logged for a Pokémon the user does not yet own
- **THEN** a new `user_collection` row is created for that Pokémon

#### Scenario: Phase Pokémon already in collection
- **WHEN** a phase is logged for a Pokémon the user already owns
- **THEN** the upsert is a no-op; existing collection row is unchanged

### Requirement: Phase history is returned in the hunts API response
The GET `/api/hunts` response SHALL include `phase_count` (integer) and `phases` (array) for each hunt. Each element in `phases` SHALL contain `id`, `pokemon_id`, `pokemon_name`, `sprite_url`, `encounter_count_at_phase`, and `created_at`.

#### Scenario: Hunt with two logged phases
- **WHEN** a user fetches their hunts and one hunt has two phase records
- **THEN** that hunt's response object includes `phase_count: 2` and a `phases` array with two entries in chronological order

#### Scenario: Hunt with no phases
- **WHEN** a user fetches their hunts and a hunt has no phase records
- **THEN** that hunt's response object includes `phase_count: 0` and an empty `phases` array
