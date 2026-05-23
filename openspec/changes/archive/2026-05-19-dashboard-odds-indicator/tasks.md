## 1. Odds Calculation

- [x] 1.1 Add a `calcCumulativeOdds(encounters, baseOdds, rolls)` helper in Dashboard.tsx that returns `1 - (1 - rolls/baseOdds)^encounters`
- [x] 1.2 Add a `getLuckLabel(pct)` helper that returns the correct label string based on thresholds from design.md
- [x] 1.3 Add a `getEffectiveRolls(hunt)` helper that selects `charm_rolls` when `has_shiny_charm` is true, else `base_rolls`

## 2. Hunt Card UI

- [x] 2.1 In the hunt card render, compute cumulative % using the helpers — skip the odds section entirely if `base_odds` or effective rolls are null
- [x] 2.2 Add the probability bar (filled div inside a track div, width capped at 100%)
- [x] 2.3 Add the percentage text and luck label in a single compact row below the bar
- [x] 2.4 Handle the zero-encounter edge case: show 0% and empty bar, omit the luck label

## 3. Polish

- [x] 3.1 Style the bar and label to match the existing card design (use existing CSS vars — `--gold`, `--ink-3`, `--bg-3`)
- [x] 3.2 Verify the odds section updates correctly after a +1 increment (optimistic update path)
