## Context

ShinyTracker tracks active Pokémon shiny hunts. Hunters frequently encounter unexpected shinies ("phases") while hunting a target — each phase resets the encounter counter and increments the phase number. Currently the app has no way to record these events. The hunt model stores a single encounter count and no phase history.

The backend uses raw SQL (pgx), no ORM. The frontend uses optimistic updates with a 1.5 s debounce for encounter increments.

## Goals / Non-Goals

**Goals:**
- Store a log of phases per hunt (which Pokémon, at what encounter count, when)
- Expose phase data in the hunts API response
- Let the frontend log a phase via a new API action
- Reset the encounter counter server-side when a phase is logged
- Add phase Pokémon to the user's shiny collection (they are real shinies)
- Display phase count and phase history on the active hunt card

**Non-Goals:**
- Phases on completed/historic hunts (retroactive data entry)
- Tracking encounter methods or game context for the phase Pokémon (out of scope for v1)
- Editing or deleting individual phase records
- Phase odds calculations

## Decisions

### 1. New `hunt_phases` table (vs. JSONB in `user_hunts`)

A dedicated `hunt_phases` table with rows per phase is preferred over storing phase data as JSONB in `user_hunts`.

**Rationale**: Structured rows are queryable, type-safe, and composable. JSONB would require application-side parsing, make queries harder, and break the no-ORM pattern's reliance on `$1/$2` placeholders.

**Alternatives considered**: Appending to a JSONB `phases` column on `user_hunts` — rejected because it adds migration complexity for future querying and complicates encounter count lookups.

### 2. Server-side counter reset on phase log

When a phase is logged via `POST /api/hunts/:id/phases`, the backend atomically:
1. Inserts a `hunt_phases` row with `encounter_count_at_phase` = current `encounter_count`
2. Resets `user_hunts.encounter_count` to 0
3. Increments `user_hunts.phase_count` (denormalized for fast display)

**Rationale**: Keeping the reset atomic prevents race conditions with the debounced frontend PATCH. Denormalizing `phase_count` avoids a COUNT query on every hunt fetch.

**Alternatives considered**: Client-side reset + separate PATCH — rejected because it creates a two-step operation that can fail mid-way.

### 3. Phase Pokémon added to collection via existing `user_collection` upsert

On phase log, the backend upserts the phase Pokémon into the user's collection using the same path as hunt completion (`acquisition_type = 'HUNTED'`).

**Rationale**: Phases are real shinies. Reusing the existing collection upsert keeps the collection logic in one place.

### 4. Frontend debounce interaction

The "Log Phase" button triggers a full round-trip (no optimistic update). On success, the hunt card re-fetches hunt data, which returns the reset counter and updated phase list.

**Rationale**: A phase log involves multiple state changes (counter reset + new phase row). Optimistic updates for this compound action would require rolling back several pieces of state on failure — complexity not justified for an infrequent action.

## Risks / Trade-offs

- **Race condition between phase log and debounced encounter PATCH**: If the user taps "Log Phase" just as a debounced PATCH is in-flight, the PATCH may increment an already-reset counter. Mitigation: the debounce is 1.5 s; a phase log is user-intentional. Acceptable for v1; can add a version/etag check later.
- **Denormalized `phase_count`**: Must be kept in sync. Mitigation: only one code path mutates it (the phase log endpoint).
- **Collection duplicate**: If the phase Pokémon is already in the collection, the upsert is a no-op. This is correct behavior.

## Migration Plan

1. Add `hunt_phases` table and `phase_count` column to `user_hunts` via a migration script (`cmd/migrate_phases/main.go`).
2. Existing hunts get `phase_count = 0` (default).
3. No data backfill needed — phases are forward-only.
4. Deploy backend, then frontend.
