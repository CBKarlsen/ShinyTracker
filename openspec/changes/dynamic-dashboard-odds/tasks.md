## 1. UI Refactoring

- [x] 1.1 Import `calculateOdds` in `ActiveHuntCard.tsx`
- [x] 1.2 Update the active hunt cards to calculate and display the live odds based on the current formula type, encounter count, and specific hunt parameters
- [x] 1.3 Remove the static `base_odds / rolls` calculation

## 2. Dynamic Odds Curve

- [x] 2.1 Update the `OddsCurve` subcomponent to compute dynamic probabilities using `calculateOdds` across encounters
- [x] 2.2 Re-render the SVG graph correctly charting the cumulative probability step-by-step
- [x] 2.3 Verify styling and layout aren't broken by the updated math
