## Context

The left sidebar already renders a `Stats` component. The existing `internal/calc/odds.go` already contains `ShinyOdds()` and ETA logic used by active-hunt cards. The `encounters` table holds all method data (game, method name, base/charm rolls, avg time, is_recommended). No new data needs to be stored — this is purely a read/reference feature.

## Goals / Non-Goals

**Goals:**
- Add `GET /api/methods` — returns all encounters, optionally filtered by `?game_id=`
- Add `GET /api/odds` — accepts `encounter_id` + `shiny_charm=true/false`, returns computed odds fraction, percentage, and ETA
- Add `OddsCalculator` sidebar widget: game selector → method selector → charm toggle → live odds display
- Add `MethodLibrary` sidebar widget: game filter → scrollable table of methods with rolls and timing
- Wire both into `Sidebar.tsx` below the existing `Stats` panel

**Non-Goals:**
- Saving or persisting calculator state between sessions
- Comparing multiple methods side-by-side in the same view
- Any schema changes — all data is already in `encounters`
- Modifying how existing hunt cards display odds

## Decisions

### Reuse `calc/odds.go` for the API endpoint
The `ShinyOdds()` function already computes the fraction and expected value. The new `/api/odds` handler calls it directly rather than duplicating logic in the frontend.

*Alternative considered*: Do the math in the browser (send rolls to frontend, compute there). Rejected because the calc logic is already tested Go code and keeping it server-side avoids drift.

### Single `/api/methods` endpoint with optional `?game_id` filter
Rather than separate endpoints per game, one endpoint with an optional query param keeps the API surface small and lets the Method Library load all methods on mount, then re-fetch or client-filter when the user changes the game picker.

*Alternative considered*: Client-side filtering after loading all methods once. Viable, but the `encounters` table can be large (~1025 Pokémon × multiple games), so server-side filtering avoids sending a large payload for a single-game view. We'll load all on mount and re-filter server-side on game change.

### Collapsible sections in the sidebar
Both widgets are wrapped in a collapsible `<details>` / chevron toggle so the sidebar doesn't become overwhelming. Default state: collapsed.

*Alternative considered*: Always-expanded. Rejected because sidebar real estate is limited and Stats is the primary widget.

### No persistent state
Calculator inputs reset on page reload. This is intentional — the tool is a quick-reference, not a planning workspace. If the user wants to save a comparison they can start a hunt.

## Risks / Trade-offs

- **Stale method data**: The `encounters` table must be seeded correctly. If a game's methods are missing, the calculator will show no options. → Mitigation: existing seed scripts handle this; no new risk introduced.
- **ETA quality**: `avg_time_seconds` is an estimate from community data. The UI should label ETAs as estimates, not guarantees.
- **Sidebar length**: Adding two panels increases sidebar height on small screens. → Mitigation: both panels default to collapsed; users expand only what they need.

## Migration Plan

1. Deploy backend with two new routes (additive, no breaking changes).
2. Deploy frontend with updated `Sidebar.tsx` and new components.
3. No DB migrations required.
4. Rollback: remove the two new routes and revert `Sidebar.tsx` — no data impact.
