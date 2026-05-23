## Why

The dashboard currently calculates odds statically using the base odds and static roll modifiers, which is inaccurate for dynamic hunting methods. Methods like PokéRadar or SV Outbreaks dynamically scale their odds based on the number of encounters or chain length (e.g., 60+ defeats, chain of 40), meaning the dashboard currently presents incorrect target odds and completion curves for these methods.

## What Changes

- Update the dashboard's ActiveHuntCard and OddsCurve components to use the `calculateOdds()` utility instead of static mathematical assumptions.
- Pass current encounter count and hunt parameters to the dynamic odds function to calculate real-time live odds.
- Ensure the odds curve correctly reflects the changing denominator as encounters increase.

## Capabilities

### New Capabilities
- `dynamic-dashboard-odds`: Ensures the main dashboard hunt cards calculate and present dynamic probabilities matching the specific `formula_type` of each hunt method.

### Modified Capabilities

## Impact

- **Affected Code**: `frontend/src/features/dashboard/ActiveHuntCard.tsx` and any child components rendering the odds curve.
- **Dependencies**: Relies on the existing `calculateOdds` utility in `frontend/src/utils/odds.ts`.
- **System**: Improves data accuracy in the UI; no database schema or backend changes required.
