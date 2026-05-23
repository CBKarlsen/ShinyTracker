## Why

Shiny hunters frequently encounter unexpected shinies while hunting for a target Pokémon — these "phases" are a core part of the hunting experience and a meaningful measure of effort. Without phase tracking, the app can't accurately represent a multi-phase hunt or capture the full story of how a shiny was eventually found.

## What Changes

- Introduce a `phases` concept: a phase is a shiny Pokémon encountered during a hunt that was not the target.
- A hunt can accumulate one or more phases before the target is found.
- Each phase records which Pokémon was found, at what encounter count, and optionally a note.
- The active hunt card shows the current phase number and a log of past phases.
- When a user logs a phase, the encounter counter resets to 0 and the phase count increments.
- Completing a hunt (finding the target) closes the hunt normally; any phases remain in history.
- Phase Pokémon are also added to the user's shiny collection (they are real shinies).

## Capabilities

### New Capabilities

- `phase-logging`: Ability to log a phase during an active hunt — records the phase Pokémon, encounter count at time of phase, and increments the phase number. Resets the encounter counter.

### Modified Capabilities

- `hunt-active-timer`: Active hunt card must now display the current phase number and a summary of logged phases.

## Impact

- **Backend**: New `hunt_phases` table; new POST endpoint to log a phase; PATCH hunt endpoint or hunt response must include phase data.
- **Frontend**: Active hunt card gains a "Log Phase" button; phase history shown inline.
- **Database**: Schema addition (`hunt_phases` table linked to `user_hunts`).
- **Collection**: Phase shinies should be added to the user's collection (same as completing a hunt).
