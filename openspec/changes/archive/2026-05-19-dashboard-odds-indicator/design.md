## Context

The dashboard hunt card currently displays: Pokemon sprite, name, game, method, encounter count, and a +1 button. The `GET /api/hunts` response already includes `base_rolls`, `charm_rolls`, `base_odds`, `has_shiny_charm`, and `encounter_count` — everything needed to compute cumulative odds client-side. The backend `internal/calc/odds.go` confirms the formula used: effective rolls × base odds.

## Goals / Non-Goals

**Goals:**
- Show cumulative probability (how likely you'd have found it by now) on each active hunt card
- Show a visual progress bar for that probability
- Show a short contextual luck label
- Gracefully handle hunts with no odds data (no method or game)

**Non-Goals:**
- Backend changes of any kind
- Showing odds on completed hunts (Historic page)
- Exact ETA calculation (that's already in the Odds Calculator)
- Animated or real-time updating odds (updates on encounter increment is sufficient)

## Decisions

### Odds formula: cumulative geometric probability
`P = 1 - (1 - effectiveOdds)^encounters`

Where `effectiveOdds = 1 / (base_odds / rolls)` — i.e. rolls / base_odds gives the per-encounter probability.

With shiny charm: use `charm_rolls` instead of `base_rolls` when `has_shiny_charm` is true.

**Why not use the backend?** All data is already in the response. A round-trip for a pure math operation would add latency and complexity for no gain.

### Luck label thresholds
| Cumulative % | Label |
|---|---|
| < 33% | "running lucky" |
| 33–66% | "about average" |
| 67–90% | "pushing your luck" |
| > 90% | "overdue" |

These match the intuitive feel of geometric distribution quartiles. At 50% cumulative you're statistically "due"; past 90% you're genuinely unlucky.

### No data fallback
If `base_odds` or `base_rolls` is null (hunt has no method/game), omit the odds section entirely — no placeholder, no zero bar. A missing indicator is less confusing than a misleading one.

## Risks / Trade-offs

- [Inaccuracy for multi-roll methods] Some methods have variable rolls per encounter (e.g. chain fishing, DexNav). The stored `base_rolls`/`charm_rolls` is an average. The cumulative % will be approximate, not exact. → Acceptable for a motivational indicator; exact math lives in the Odds Calculator.
- [Cluttered card] Adding three new elements (%, bar, label) to an already-dense card risks visual noise. → Keep the odds section compact: single row with bar + two text values.
