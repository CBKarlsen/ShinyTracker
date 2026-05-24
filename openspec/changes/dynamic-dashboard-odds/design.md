## Context

Currently, the `ActiveHuntCard` component and `OddsCurve` subcomponent calculate odds using a simplified static equation: `1 - (1 - rolls / baseOdds)^encounters`. However, we recently introduced `calculateOdds` in `src/utils/odds.ts` which handles specific logic for `outbreak_defeats_sv`, `radar_chain_gen4`, `catch_combo_lgpe`, etc. The dashboard must be updated to use this dynamic calculator to show correct odds and ETA expectations.

## Goals / Non-Goals

**Goals:**
- Replace static odds math in `OddsCurve` with the central `calculateOdds` function.
- Display the true dynamic denominator (the "Live Odds") directly in the hunt card based on the current encounter count.

**Non-Goals:**
- Altering the backend hunt model or database schema.
- Changing how the `calculateOdds` utility works internally.

## Decisions

- **Decision 1:** Calculate live odds inside the `ActiveHuntCard` render cycle using `calculateOdds(hunt.formula_type, hunt.encounter_count, hunt.has_shiny_charm, hunt.base_odds, hunt.base_rolls, hunt.charm_rolls, hunt.hunt_parameters)`.
- **Decision 2:** Update `OddsCurve` to chart the correct dynamic probability curve instead of assuming static rolls. Since `calculateOdds` returns a static probability for an entire chain (which isn't strictly how probability accumulates incrementally if odds change mid-chain), we will chart probability by iterating `calculateOdds` for each step `n` from `1` to `MAX_W`.

## Risks / Trade-offs

- **Risk**: Performance overhead of calling `calculateOdds` hundreds of times to draw the SVG `OddsCurve`.
- **Mitigation**: The SVG width is relatively small, so rendering ~200-300 points is well within React/SVG performance limits. If it gets slow, we can memoize the path generation or sample fewer points.
