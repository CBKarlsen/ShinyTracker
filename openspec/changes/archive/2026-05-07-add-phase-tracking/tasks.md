## 1. Database Migration

- [x] 1.1 Create `backend/cmd/migrate_phases/main.go` that adds a `hunt_phases` table (`id uuid PK`, `hunt_id uuid FK user_hunts`, `pokemon_id int FK pokemon`, `encounter_count_at_phase int`, `created_at timestamptz`) and a `phase_count int NOT NULL DEFAULT 0` column to `user_hunts`
- [x] 1.2 Run the migration against the database and verify schema changes

## 2. Backend Models

- [x] 2.1 Add `HuntPhase` struct to `internal/models/models.go` with fields: `ID`, `HuntID`, `PokemonID`, `PokemonName`, `SpriteURL`, `EncounterCountAtPhase`, `CreatedAt`
- [x] 2.2 Add `PhaseCount int` and `Phases []HuntPhase` fields to the `Hunt` (or hunt response) struct

## 3. Backend API — Phase Log Endpoint

- [x] 3.1 Add `POST /api/hunts/{id}/phases` route in `internal/api/router.go`
- [x] 3.2 Implement `LogPhase` handler in `internal/api/hunts.go`: parse `pokemon_id` from body, verify hunt ownership and active status, run atomic transaction (insert `hunt_phases`, reset `encounter_count` to 0, increment `phase_count`)
- [x] 3.3 Upsert phase Pokémon into `user_collection` with `acquisition_type = 'HUNTED'` inside the same transaction
- [x] 3.4 Return updated hunt object (including phases array) in the response

## 4. Backend API — Hunts List Response

- [x] 4.1 Update the hunts list query in `handlers.go` (or `hunts.go`) to LEFT JOIN `hunt_phases` and populate `phase_count` and `phases` on each hunt response
- [x] 4.2 Verify that hunts with no phases return `phase_count: 0` and an empty `phases` array

## 5. Frontend — Data Types

- [x] 5.1 Add `HuntPhase` TypeScript type and update the `Hunt` type to include `phase_count: number` and `phases: HuntPhase[]`

## 6. Frontend — Log Phase Button

- [x] 6.1 Add a "Log Phase" button to the active hunt card in `Dashboard.tsx`
- [x] 6.2 On click, open a small Pokémon search/select modal (reuse or adapt `NewHuntModal` search) to choose the phase Pokémon
- [x] 6.3 On confirm, call `POST /api/hunts/:id/phases` with the selected `pokemon_id`
- [x] 6.4 On success, re-fetch hunt data so the card reflects the reset counter and new phase entry

## 7. Frontend — Phase Display on Hunt Card

- [x] 7.1 Show "Phase N" label on the hunt card when `phase_count > 0` (where N = `phase_count + 1`)
- [x] 7.2 Render the list of prior phases inline on the card: each showing the phase Pokémon sprite and encounter count at phase
