# "Hunt Next" Panel — Design

**Date:** 2026-05-31
**Status:** Approved (design)
**Relates to:** living-dex completionist persona; backlog #5 (completion forecast) is a sibling, not a dependency.

## Problem

The living dex (`frontend/src/components/Collection.tsx`) is browse-driven: a 1025-cell grid the user scans by hand, clicking a cell to open `DexDrawer` and see that Pokémon's routes. Nothing surfaces *who to hunt next* — the user must already know who to click. A completionist wants the app to recommend the best next targets.

## Solution overview

Add a **"Hunt next" recommendation panel** at the top of the Collection page: a ranked strip of the top 12 huntable-missing Pokémon, each card showing the best route's odds/ETA, the game + method, a "constrained availability" badge, and a one-click **Start**. Clicking a card body opens the existing `DexDrawer` for full route options.

Ranking is computed **server-side** in a new endpoint that reuses the existing Go `calc` odds engine, so the panel's odds can never drift from the drawer's (this codebase has a documented history of TS/Go odds drift; ranking in Go avoids reintroducing it).

## Ranking model (the core of the feature)

Pool = the user's **huntable-missing** Pokémon:
- not owned (no `completed` hunt),
- not already in an `active` hunt,
- available in ≥1 of the user's games (`pokemon_availability` ∩ `user_games`),
- with at least one non-locked huntable (pokemon, game) pair (drop `shiny_locks` rows).

Sort order (ascending on each key, in priority order):
1. **Best-route denominator** — lowest 1/X first (best odds). Computed from the Pokémon's best *direct* route via `calc.RankDirectRoutes`.
2. **`huntable_game_count`** — number of the user's games in which the Pokémon is huntable (non-locked). Fewer first → "grab the limited-availability ones first."
3. **`pokemon_id`** — National Dex order, as a stable final tiebreak.

Odds/ETA use the same best-case `DefaultParams` the drawer already uses (consistency with existing displays). Charm status is per-game via `user_games.has_shiny_charm` (already in `fetchMethodCandidates`).

### Scope decision: direct routes only (v1)

v1 ranks by each Pokémon's best **direct** route. Pokémon with no direct method (evolve-only, e.g. Hydreigon via a Masuda Deino) are **omitted from the panel** — they remain fully reachable through the grid + drawer (which already computes evolve routes). Full direct+evolve parity is a deferred enhancement, not a v1 requirement. Documented so the omission is intentional, not a bug.

## Backend — `GET /api/dex/suggestions`

New handler in `backend/internal/api/dex.go`, registered in the router alongside `GET /api/dex/status`. Query param `limit` (default 12, clamp to a sane max e.g. 50).

**Implementation strategy — one bulk pass, not N queries:**

1. **One query** returns all direct method candidates for the huntable-missing pool, with the same columns as `fetchMethodCandidates` (`hm.id, g.id, g.title, hm.method_name, g.base_odds, hm.base_rolls, hm.charm_rolls, hm.avg_time_seconds, ug.has_shiny_charm, hm.formula_type`) plus `pokemon_id`, `p.name`, `p.sprite_url`. Joins `method_availability → hunt_methods → games → user_games`, filtered by:
   - `ug.user_id = $1`
   - `pokemon_id NOT IN (completed hunt pokemon_ids for the user)`
   - `pokemon_id NOT IN (active hunt pokemon_ids for the user)`
   - `LEFT JOIN shiny_locks sl ON sl.pokemon_id = ma.pokemon_id AND sl.game_id = ma.game_id WHERE sl.pokemon_id IS NULL` (exclude locked pairs)
2. **Group rows by `pokemon_id` in Go.** For each group:
   - run existing `calc.RankDirectRoutes(candidates)` → best route is index 0 (odds, ETA, method, game).
   - `huntable_game_count` = count of distinct `game_id` in the group.
3. **Sort** the per-Pokémon results with a pure comparator: denominator ASC → huntable_game_count ASC → pokemon_id ASC.
4. **Truncate** to `limit`, also compute `total_huntable` = total groups before truncation.
5. Encode the response.

Reuses `calc.MethodCandidate`, `calc.RankDirectRoutes`, `calc.Route` unchanged. The comparator + grouping is the only new pure logic and is the unit-test target.

### Response DTO

```go
type HuntSuggestion struct {
    PokemonID         int        `json:"pokemon_id"`
    Name              string     `json:"name"`
    SpriteURL         string     `json:"sprite_url"`
    Denominator       int        `json:"denominator"`
    ETASeconds        int        `json:"eta_seconds"`
    MethodName        string     `json:"method_name"`
    GameID            int        `json:"game_id"`
    GameTitle         string     `json:"game_title"`
    HuntableGameCount int        `json:"huntable_game_count"`
    Route             calc.Route `json:"route"` // enough for one-click Start
}

type HuntSuggestionsResponse struct {
    TotalHuntable int              `json:"total_huntable"`
    Suggestions   []HuntSuggestion `json:"suggestions"`
}
```

`Denominator`, `ETASeconds`, `MethodName`, `GameID`/`GameTitle` are projected from the best `calc.Route` for convenience; `Route` carries the full object so the frontend can Start without another fetch.

## Frontend — `<HuntNextPanel>`

New component rendered at the top of `Collection.tsx`, above the generation grid.

- **Fetch:** `GET /api/dex/suggestions` (with auth header) on mount. Add to the page's existing load; failures show a non-blocking error and hide the panel (the grid still works).
- **Types:** add `HuntSuggestion` + `HuntSuggestionsResponse` to `frontend/src/types/models.ts` (mirror the Go DTO; `route: PokemonRoute`-compatible shape).
- **Card content:** sprite, name, `game_title · method_name`, **1/{denominator}**, formatted ETA, and a `huntable_game_count` badge — styled prominently ("only 1 game") when the count is 1, muted ("N games") otherwise.
- **Start button:** calls the existing `onStartHunt(pokemon, route)` prop already threaded through `Collection` — reuses the live start flow, no new logic. (Construct the minimal `Pokemon` from the suggestion fields.)
- **Card body click:** opens the existing `DexDrawer` via the existing `drawerId` state — full direct+evolve routes, Mark-caught, etc.
- **States:** loading skeleton (12 placeholder cards); empty (`total_huntable === 0`) → celebratory "No huntable targets left — your dex is complete or the rest are blocked 🎉".
- **"See all suggested ▸":** rendered but inert/deferred — the affordance for the future grid-sort follow-on. (Out of scope for v1; do not wire grid sorting.)

The panel reflects ownership/hunt changes on the next page load; live re-ranking after a Start/Mark-caught within the same session is not required for v1 (the started Pokémon simply remains until reload — acceptable).

## Out of scope (YAGNI / deferred)

- Evolve-route parity in the ranking (direct only — see scope decision).
- User-sortable toggle (ETA / odds / dex) — hybrid endpoint reserved for if/when this is added.
- Grid "Suggested" sort (the "A" follow-on) — affordance left, not built.
- Live in-session re-ranking after Start/Mark-caught.
- Pagination / "load more" beyond top-12.

## Testing

- **Go unit test** (`backend/internal/calc` or a small `_test.go` next to the handler logic) for the ranking comparator + grouping: given a set of per-Pokémon best routes with mixed denominators / game counts / dex ids, assert the exact output order, including tie cases (equal odds → fewer games first; equal odds & games → lower dex id first). This is the parity-critical, pure-logic core.
- Endpoint/SQL is verified manually against the dev DB (no API test harness exists in the repo); the spec's filter list is the manual checklist.
- Frontend: `npm run build` clean; manual smoke of panel render, Start, drawer-open, and empty state.

## Files touched

- `backend/internal/api/dex.go` — new handler + DTOs + bulk query + grouping/sort (consider extracting the comparator to `calc` for testability).
- `backend/internal/api/router.go` — register `GET /api/dex/suggestions`.
- `backend/internal/calc/` — (likely) a small exported comparator/helper + its unit test.
- `frontend/src/components/HuntNextPanel.tsx` — new component.
- `frontend/src/components/Collection.tsx` — render the panel; pass `onStartHunt` and drawer-open handlers.
- `frontend/src/types/models.ts` — `HuntSuggestion`, `HuntSuggestionsResponse`.

No DDL. No changes to the odds formulas.
