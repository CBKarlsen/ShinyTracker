## Context

ShinyTracker allows users to create hunts with specific methods (e.g., SV Outbreak Defeats, Gen 4 PokeRadar). Some methods have dynamic odds based on parameters that change during the hunt. For example, an SV outbreak gets higher odds at 30 and 60 defeats. Currently, the UI in `HeroHunt.tsx` shows a placeholder to edit method parameters, but the API and frontend state are not wired to persist or recalculate odds dynamically during the hunt.

## Goals / Non-Goals

**Goals:**
- Enable users to dynamically update `hunt_parameters` for an active hunt directly from the `HeroHunt` UI.
- Update the `PATCH /api/hunts/:id` endpoint to accept and save `hunt_parameters`.
- Ensure the frontend recalculates and displays the correct updated odds based on the new parameters.

**Non-Goals:**
- Creating new hunting methods.
- Refactoring the entire `calculateOdds` utility beyond making it correctly consume the dynamically updated parameters.

## Decisions

1. **Backend API Update**:
   - The existing `PATCH /api/hunts/:id` endpoint will be modified. The request struct will be updated to optionally accept `HuntParameters json.RawMessage`. 
   - The SQL `UPDATE` query will be modified to also update `hunt_parameters` if provided. *Alternative considered*: A dedicated `PUT /api/hunts/:id/parameters` endpoint. *Rationale*: Since we already have a `PATCH` endpoint for updating hunt status and encounters, extending it minimizes route bloat and allows atomic updates of encounters and parameters if needed.

2. **Frontend UI Integration**:
   - `HeroHunt.tsx` will introduce a small inline form or dropdown to adjust the specific `hunt_parameters` relevant to the active `formula_type` (e.g., an input for `outbreak_defeats`).
   - We will reuse or adapt the parameter inputs currently implemented for `NewHuntModal` to ensure consistency.

3. **Frontend State Updates**:
   - Upon a successful `PATCH` request, the frontend will update the `hunt` object in its local state. Because `HeroHunt` derives expected values and odds from the `hunt` object (including `hunt.hunt_parameters` mapped to `base_odds`/`base_rolls`), updating this object will automatically trigger a re-render with the new odds. Note: Ensure `calculateOdds` accurately processes the parameters dynamically on the frontend.

## Risks / Trade-offs

- [Risk] **Invalid JSON payload for parameters** → Mitigation: The backend will parse it as `json.RawMessage` and database schema allows JSONB. We will ensure the frontend strictly sends the defined parameter shapes (e.g., `{"defeats": 60}`).
- [Risk] **Recalculating odds fails to reflect on UI** → Mitigation: Ensure the React state update replaces the whole `hunt` object so child components (`OddsCurve`, `TimerDisplay`, etc.) reactively update.
