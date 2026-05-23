## Why

The dashboard is the most-visited screen but hunt cards only show a raw encounter count — no context for whether that number is lucky, expected, or overdue. Adding live odds and a luck indicator gives hunters the emotional feedback that makes shiny hunting meaningful.

## What Changes

- Each active hunt card on the Dashboard displays a cumulative probability bar (how likely you'd have found it by now)
- A short luck label ("running lucky", "about average", "overdue") contextualises the number
- The exact cumulative % is shown numerically alongside the bar
- Hunt cards without odds data (no method/game attached) gracefully omit the indicator

## Capabilities

### New Capabilities
- `hunt-odds-display`: Compute and render per-hunt cumulative shiny probability and luck status on the dashboard hunt card

### Modified Capabilities
<!-- none — this is additive; no existing spec-level requirements change -->

## Impact

- `frontend/src/components/Dashboard.tsx` — add odds calculation and UI to hunt card
- No backend changes — all required data (`base_rolls`, `charm_rolls`, `base_odds`, `has_shiny_charm`, `encounter_count`) is already returned by `GET /api/hunts`
- No new dependencies
