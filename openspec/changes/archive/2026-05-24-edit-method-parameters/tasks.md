## 1. Backend Updates

- [x] 1.1 Update `PATCH /api/hunts/:id` endpoint in `backend/internal/api/hunts.go` to accept optional `hunt_parameters`.
- [x] 1.2 Modify the SQL `UPDATE` statement in `UpdateHuntHandler` to update `hunt_parameters`.
- [x] 1.3 Verify backend response includes the correctly serialized `hunt_parameters`.

## 2. Frontend UI Implementation

- [x] 2.1 Extract parameter inputs (e.g., from `MethodPreview.tsx`) into a reusable `HuntParametersEditor` component.
- [x] 2.2 Integrate the parameter editing UI into `HeroHunt.tsx` under the "Edit Method Parameters" toggle, replacing the placeholder text.
- [x] 2.3 Implement the save handler in `HeroHunt.tsx` to dispatch the PATCH request to `/api/hunts/:id` with the updated parameters.

## 3. State & Calculation Updates

- [x] 3.1 Upon successful save, update the local `hunt` state in the parent component (e.g., `Dashboard.tsx`) with the returned data from the API.
- [x] 3.2 Verify that the `calculateOdds` utility dynamically computes the new expected denominator correctly based on the updated `hunt_parameters`.
- [x] 3.3 Ensure the UI (encounter progress, expected counts, and time estimates) immediately reflects the updated odds.
