## 1. Backend — Methods API

- [x] 1.1 Add `GetMethods` handler in `internal/api/handlers.go` — query `encounters` joined with `games`, support optional `?game_id` filter, return JSON array
- [x] 1.2 Register `GET /api/methods` route in `internal/api/router.go`

## 2. Backend — Odds API

- [x] 2.1 Add `GetOdds` handler in `internal/api/handlers.go` — look up encounter by `encounter_id`, call `calc.ShinyOdds()`, return fraction, percentage, expected_encounters, eta_hours
- [x] 2.2 Register `GET /api/odds` route in `internal/api/router.go`

## 3. Frontend — Odds Calculator Component

- [x] 3.1 Create `src/components/OddsCalculator.tsx` — game dropdown, method dropdown (populated after game selection), Shiny Charm checkbox
- [x] 3.2 Fetch available games from existing `/api/games` endpoint to populate the game dropdown
- [x] 3.3 Fetch methods from `/api/methods?game_id=<id>` when game changes, populate method dropdown
- [x] 3.4 Fetch odds from `/api/odds?encounter_id=<id>&shiny_charm=<bool>` when method or charm changes
- [x] 3.5 Display computed odds fraction, percentage, and ETA; label ETA as an estimate

## 4. Frontend — Method Library Component

- [x] 4.1 Create `src/components/MethodLibrary.tsx` — game filter dropdown, scrollable method list
- [x] 4.2 Fetch all methods from `/api/methods` on mount; re-fetch with `?game_id=<id>` when filter changes
- [x] 4.3 Render each method row: name, base rolls, charm rolls, avg time (formatted), "Recommended" badge if applicable
- [x] 4.4 Show empty state message when no methods are returned

## 5. Frontend — Sidebar Integration

- [x] 5.1 Add collapsible Odds Calculator panel to `src/components/Sidebar.tsx` below Stats, defaulting to collapsed
- [x] 5.2 Add collapsible Method Library panel to `src/components/Sidebar.tsx` below Odds Calculator, defaulting to collapsed
- [x] 5.3 Style both panels consistently with the existing sidebar design tokens
