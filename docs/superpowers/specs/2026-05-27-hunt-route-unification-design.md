# Hunt Route Unification — Design

**Date:** 2026-05-27
**Status:** Approved design, pending implementation plan
**Branch:** `worktree-dex-completion-engine`
**Scope:** Make the New Hunt modal and the dex detail drawer present the **same routes from the same data**, via a shared presentational component, so they look identical and never disagree.

## Problem

The dex `DexDrawer` and the `NewHuntModal` both answer "how do I hunt this Pokémon?" but diverge:

- **Different data sources.** The drawer uses `GET /api/pokemon/{id}/route` (server-ranked routes, evolve-from suggestions, blocked states, server odds/ETA). The modal uses `GET /api/hunt-methods` (raw methods) plus client-side `getOddsForMethod` and a **hardcoded `getBaseOdds` heuristic** that guesses 8192/4096 from the game title.
- **Consequences:** the two can show different routes for the same Pokémon (e.g. the drawer showed Blastoise routes while the modal said "not available"); the modal can't show evolve-from routes; odds math is duplicated and the modal's base-odds guess can drift from `games.base_odds`.

## Goal

One route data contract and one route-rendering component, used by both surfaces. The modal keeps its distinct shell (search, custom method, hunt parameters, Start); the drawer stays a launcher into that shell.

## Decisions locked during brainstorming

- **Approach A — shared presentational component, separate shells.** Extract a `<RouteList>` from the drawer's route rendering; both surfaces fetch `/api/pokemon/{id}/route` and render it. Not a fully-shared interactive unit (rejected Approach B as over-coupling; rejected visual-only Approach C as leaving the data mismatch).
- **Evolve routes are startable in the modal**, and starting one begins a hunt for the **pre-evolution** (the ancestor) with its method. This also fixes the previously-deferred imperfect evolve-prefill.
- The drawer remains a launcher: its route click opens the modal prefilled; the modal is the single hunt-commit surface.

## Non-goals (YAGNI)

- No fully-shared interactive unit (no params editing or hunt creation inside the drawer).
- No change to the search step, custom-method flow, or `HuntParametersEditor` internals.
- No backend hunt-creation changes — `POST /api/hunts` is unchanged.

## Backend changes

The drawer's `calc.Route` lacks the two fields the modal needs to start a hunt and drive the params editor: the hunt-method id and `formula_type`. Add them, sourced from the existing candidate query.

1. **`calc.MethodCandidate`** (`internal/calc/routes.go`): add `MethodID int` and `FormulaType string`.
2. **`calc.Route`**: add `MethodID int json:"method_id"` and `FormulaType string json:"formula_type"`. `computeRoute` copies both from the candidate. `RankDirectRoutes` and `BestRoute` therefore carry them; for an evolve route, they are the **ancestor's** method id + formula_type (because `BestRoute` is computed from the ancestor's candidates).
3. **`fetchMethodCandidates`** (`internal/api/dex.go`): extend the SELECT to `hm.id` and `hm.formula_type` and the `Scan` to the new fields. Column order stays aligned with `MethodCandidate`.

No SQL logic or status logic changes; the route handler's shape is otherwise unchanged.

## Frontend changes

### New shared units (`frontend/src/features/routes/`)

- **`usePokemonRoute(pokemonId)`** — hook that fetches `GET /api/pokemon/{id}/route` and returns `{ status, routes, loading, error }`. Replaces the drawer's inline fetch and the modal's `/api/hunt-methods` fetch.
- **`<RouteList>`** — presentational. Props: `routes: PokemonRoute[]`, `selectedKey?: string`, `onRouteClick: (route: PokemonRoute) => void`. Renders the two sections ("Routes in your games" / "Hunt a pre-evolution") and the route cards exactly as the drawer does today, highlighting `selectedKey`. A route's key is `` `${kind}-${game_id}-${method_id}` ``. No fetching, no Start button — the parent decides what a click means.

### Types (`frontend/src/types/models.ts`)

`PokemonRoute` gains `method_id: number` and `formula_type: string` (matching the extended backend `Route`).

### DexDrawer (`frontend/src/components/DexDrawer.tsx`)

- Use `usePokemonRoute` instead of the inline fetch.
- Render `<RouteList onRouteClick={(route) => onStartHunt(route, pokemon)} />` (no persistent selection).
- `onStartHunt` now passes the full `route` (carrying `method_id`, `formula_type`, and `evolve_from`) up so the modal can be prefilled exactly. Blocked-state messages and Mark-as-caught are unchanged.

### NewHuntModal (`frontend/src/components/NewHuntModal.tsx`)

- **Step 2 data:** replace the `/api/hunt-methods` fetch with `usePokemonRoute(selectedPokemon.id)`.
- **Route list:** replace the `opt-row` list with `<RouteList routes={routes} selectedKey={selectedKey} onRouteClick={setSelectedRoute} />`. Selection state becomes a `PokemonRoute` (not a `HuntMethod`).
- **Delete** `getOddsForMethod` and `getBaseOdds` (odds now come from the route). Remove `calculateOdds`/`utils/odds.ts` if no remaining references (verify with a repo grep; keep only if still used elsewhere).
- **Blocked states:** drive the empty/blocked messaging from `status` (`available` / `not_in_your_games` / `locked_everywhere`) — consistent with the drawer. Keep a lightweight `/api/user/{id}/games` count only for the "you haven't added any games yet" onboarding prompt.
- **Params:** `HuntParametersEditor` is fed by `selectedRoute.formula_type`.
- **Start:** `POST /api/hunts` (unchanged endpoint) with `hunt_method_id = selectedRoute.method_id`, `game_id = selectedRoute.game_id`, `method_name = selectedRoute.method_name`, `hunt_parameters`, and `pokemon_id = selectedRoute.evolve_from ? selectedRoute.evolve_from.pokemon_id : selectedPokemon.id`. For an evolve route, show a one-line note ("You'll hunt {ancestor}, then evolve into {target}").
- **Custom method:** unchanged — stays as the modal-only row below `<RouteList>`, posting `custom_method_name`.
- **Prefill:** the prefill prop becomes `{ pokemon: Pokemon; route: PokemonRoute } | null` (was `{ pokemon, gameId, methodName }`). On open with prefill, set `selectedPokemon = prefill.pokemon` (the target, for the header/context), preselect `selectedRoute = prefill.route` by key, and jump to step 2 — no more matching by `game_id`+`method_name`. The route's `evolve_from` still drives the actual hunt Pokémon on Start.

### MethodPreview (`frontend/src/features/new-hunt/MethodPreview.tsx`)

- Take the selected `PokemonRoute` instead of a `HuntMethod`. Display odds from `route.odds` and ETA from `route.eta_hours` (drop `getBaseOdds`/`getOddsForMethod` props). Continue rendering `HuntParametersEditor` from `route.formula_type`.

## Data flow

```
usePokemonRoute(id) ── GET /api/pokemon/{id}/route ──▶ { status, routes[] }
        │                                routes[]: { kind, method_id, game_id,
        │                                  game_title, method_name, formula_type,
        ▼                                  odds, eta_hours, evolve_from? }
   <RouteList> (both surfaces)
        │ onRouteClick(route)
        ├─ DexDrawer:  onStartHunt(route, pokemon) ─▶ open modal prefilled
        └─ NewHuntModal: setSelectedRoute(route) ─▶ params + Start
                                                   │
                       POST /api/hunts (hunt_method_id = route.method_id,
                         pokemon_id = ancestor for evolve else target)
```

## Error handling

- `usePokemonRoute` failure: drawer shows its existing inline error (Mark-as-caught still works); modal shows an error in step 2 with Cancel available.
- Blocked statuses render the same messaging in both surfaces.
- Custom-method start path is unaffected by route-fetch errors.

## Testing / verification

No frontend test framework; backend logic is `go test`-able.

- **Backend:** extend `internal/calc/routes_test.go` to assert `computeRoute` copies `MethodID`/`FormulaType`, and that `BestRoute` carries the ancestor's `MethodID`/`FormulaType`. `go build ./...` + `go test ./internal/calc/...` pass.
- **Frontend:** `npm run build` passes; lint not materially worse than baseline. Manual pass: searching a Pokémon in the modal shows the same routes (and odds) as its drawer; an evolve-only Pokémon (e.g. Blastoise) in the modal offers "hunt Squirtle" and starting it creates a Squirtle hunt; locked/not-in-your-games statuses render in the modal; custom method still starts; the drawer's route click opens the modal correctly prefilled.

## Affected files

**Backend**
- `backend/internal/calc/routes.go` — add `MethodID`/`FormulaType` to `MethodCandidate` and `Route`; `computeRoute` copies them.
- `backend/internal/calc/routes_test.go` — assertions for the new fields.
- `backend/internal/api/dex.go` — `fetchMethodCandidates` SELECT/Scan add `hm.id`, `hm.formula_type`.

**Frontend**
- `frontend/src/features/routes/usePokemonRoute.ts` — new hook (CREATE).
- `frontend/src/features/routes/RouteList.tsx` — new shared component (CREATE).
- `frontend/src/types/models.ts` — `PokemonRoute` gains `method_id`, `formula_type`.
- `frontend/src/components/DexDrawer.tsx` — use hook + `<RouteList>`; pass full route up.
- `frontend/src/components/NewHuntModal.tsx` — step 2 on route data + `<RouteList>`; delete `getOddsForMethod`/`getBaseOdds`; status-driven blocked states; start via `method_id`/ancestor.
- `frontend/src/features/new-hunt/MethodPreview.tsx` — consume the selected `PokemonRoute`.
- `frontend/src/App.tsx` — `huntPrefill` state becomes `{ pokemon, route } | null`; the Collection `onStartHunt(pokemon, route)` handler stores the route directly.
- `frontend/src/utils/odds.ts` — remove if no longer referenced.
