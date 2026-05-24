## Why

Users currently cannot edit hunt parameters dynamically during an active hunt. The UI for "Edit Method Parameters" exists on `HeroHunt.tsx` for methods like `outbreak_defeats_sv` and `radar_chain_gen4`, but it lacks the API integration to persist these changes. This change wires up the frontend to update the backend state so odds remain accurate as a user's chain or outbreak level progresses.

## What Changes

- Implement the UI inputs for method parameters in `HeroHunt.tsx` replacing the placeholder message.
- Wire the frontend to send an update to the backend API (e.g. `PUT /api/hunts/:id`) to patch `hunt_parameters`.
- Update the frontend state upon successful save to immediately recalculate and display the correct shiny odds based on the new parameters.

## Capabilities

### New Capabilities
- `edit-hunt-parameters`: Capability to dynamically update the `hunt_parameters` JSON field on active hunts.

### Modified Capabilities
- `hunt-odds-display`: Must accurately reflect dynamically updated method parameters in real-time.

## Impact

- Frontend: `HeroHunt.tsx` requires new form components or inputs for parameter editing.
- Backend: Requires an endpoint to update an existing hunt's properties (specifically `hunt_parameters`), if not fully featured already.
- State: Redux/Context or local state must properly incorporate the updated parameters for odds calculation.
