# Dex Completion Engine — Design (#1 Blocked Awareness + #2 Best Route)

**Date:** 2026-05-26
**Status:** Approved design, pending implementation plan
**Scope:** Turn the Shiny Living Dex from a passive checklist into a completion worktop: every missing cell tells you whether it's blocked, and the best way to get it across the games you own.

## Goal

For a living-dex completionist, answer two questions directly from the dex grid:

1. **Is this target blocked?** — shiny-locked everywhere, or not in any game I own.
2. **What's the cheapest path to it?** — the best method across my owned games (ranked by odds/ETA), including "hunt a pre-evolution, then evolve."

## Decisions locked during brainstorming

- **#1 scope:** both blocked signals — the derived "not in your games" *and* a curated shiny-lock dataset across all 9 generations.
- **#2 scope:** method ranking across owned games **plus** evolve-from hints (requires an evolution-lineage seed).
- **Interaction model:** **detail drawer** (Option A). Clicking a cell opens a right-side drawer over a dimmed grid; the caught toggle lives inside the drawer.
- **Architecture:** dedicated backend endpoints; odds computed server-side via the existing `calc/odds.go`, removing the duplicated client-side `getOddsForMethod`.
- **Drawer routes:** flat, uniform list ordered by odds (no "recommended" highlight yet — deferred). Pre-evolution routes get their own section labeled **"Hunt a pre-evolution"**. Every route is independently startable.

## Non-goals (YAGNI)

- No modeling of evolution items/levels/conditions — a suggestion just names the ancestor to hunt; the player handles the evolve.
- No "recommended route" highlighting yet (flat list now; revisit later).
- No bulk import (that is a separate feature, #7).
- No regional-forms-as-targets (separate large project, #3-forms).

## Data model & seeds

### Shiny locks (new table + curated seed)

```sql
CREATE TABLE IF NOT EXISTS shiny_locks (
    pokemon_id INTEGER REFERENCES pokemon(id) ON DELETE CASCADE,
    game_id    INTEGER REFERENCES games(id)   ON DELETE CASCADE,
    PRIMARY KEY (pokemon_id, game_id)
);
```

- Seeded from a new `backend/seeds/shiny_locks.json` (curated per game across all 9 gens — box legendaries, gift starters, Meltan/Melmetal, etc.), applied by a new `cmd/seed_shiny_locks` tool using `ON CONFLICT DO NOTHING` (idempotent, follows the `legendary_encounters.json` curation pattern).
- **"Locked everywhere" is derived, not stored:** a Pokémon is locked-everywhere when it has ≥1 `pokemon_availability` row **and** every game in its availability has a matching `shiny_locks` row.

### Evolution lineage (new column + seed)

```sql
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS evolves_from_id INTEGER REFERENCES pokemon(id);
```

- Single nullable parent pointer per species (PokeAPI `evolves_from_species`). Branching only occurs going forward, so a column suffices — no join table.
- Captured by **extending the existing `cmd/seed`** PokeAPI crawl (it already hits PokeAPI), to avoid a second full fetch. Walking `evolves_from_id` upward yields the full pre-evo line (Magikarp → Gyarados).

## Backend endpoints

Both endpoints are authenticated (`X-User-ID`) and compute odds via `calc/odds.go`.

### `GET /api/dex/status` — bulk grid coloring

Returns two ID sets for the authenticated user:

```json
{ "not_in_your_games": [251, 385], "locked_everywhere": [716, 643] }
```

- **`locked_everywhere`** (global): available in ≥1 game and shiny-locked in **all** of them.
- **`not_in_your_games`**: has availability somewhere, but **zero** owned games (`pokemon_availability ∩ user_games` empty).
- **Precedence:** locked-everywhere wins over not-in-your-games.
- Caught status is **not** included — the grid keeps deriving it client-side from `/api/hunts` as today.
- Implemented as two set queries; cheap enough to run on Collection load.

### `GET /api/pokemon/{id}/route` — per-Pokémon drawer data

```json
{
  "status": "available",
  "routes": [
    {"kind":"direct","game_id":34,"game_title":"Scarlet","method_name":"Masuda","odds":683,"eta_hours":7.2},
    {"kind":"evolve","game_id":34,"game_title":"Scarlet","method_name":"Random Encounter",
     "odds":683,"eta_hours":3.1,"evolve_from":{"pokemon_id":129,"name":"magikarp"}}
  ]
}
```

- `status`: `available` | `not_in_your_games` | `locked_everywhere`.
- **Direct routes:** the existing `GetHuntMethodsHandler` query (`method_availability ∩ user_games`), extended to join `games.base_odds` and `user_games.has_shiny_charm`, run through `calc/odds.go` for `{odds, eta_hours}`. Ranked ascending by odds.
- **Evolve routes:** walk `evolves_from_id` up; for each ancestor compute *its* best direct route in owned games; include it when the target has no direct route **or** the ancestor's odds beat the target's. Only included when the ancestor has a real route in an owned game (no dead-end suggestions). Tagged with `evolve_from`.
- Direct and evolve routes are both ordered by odds within their respective sections; no cross-section "best" flag.

### Consolidation

The frontend's duplicate `getOddsForMethod` is removed once both endpoints return server-computed odds — `calc/odds.go` becomes the single source of truth for odds math.

## Frontend

### Grid cell states (`Collection.tsx`)

On load, fetch `/api/dex/status` alongside the existing pokemon + hunts fetches. Each cell renders one of four states (precedence: caught > locked > not-in-games > missing):

- **Caught** — gold ring (unchanged).
- **Missing (huntable)** — dim (unchanged).
- **🔒 Locked everywhere** — red hatch overlay.
- **🚫 Not in your games** — greyed.

If `/api/dex/status` fails, the grid still renders caught/missing with no overlays plus a non-blocking notification.

### Detail drawer (new component)

Clicking any cell opens a right-side drawer (reusing the existing `.scrim` / `.drawer` pattern) and fetches `/api/pokemon/{id}/route`.

- **Header:** shiny sprite, name, `#id · Generation N`, status badge (Missing / 🔒 Shiny-locked / 🚫 Not in your games).
- **`available`:**
  - **Routes (in your games):** flat list ordered by odds; each shows method, game (+ "with Shiny Charm" when applicable), `1/N` odds, `~Xh` ETA, and an inline **▸ Start this hunt** link.
  - **Hunt a pre-evolution:** ancestor sprite + its route + `↳ then evolve into {target}` + its own start link.
  - **Mark as caught** at the bottom.
- **`locked_everywhere`:** explanation + which games it's locked in; only **Mark as caught** (no routes).
- **`not_in_your_games`:** lists the games it *is* huntable in + nudge to add one; **Mark as caught**.
- **Data-gap case** (status `available` but `routes` empty): show *"Available in {game}, but no hunt method recorded yet"* + **Mark as caught**.

### Actions

- **Start this hunt** → opens the existing `NewHuntModal` prefilled with the chosen Pokémon, game, and method, so the user still confirms and can set hunt parameters before the hunt is created. (Reuses the modal's existing creation path rather than a new endpoint.)
- **Mark as caught** → existing `POST /api/hunts/manual` (`MANUAL_OVERRIDE`), works for blocked cells too.

## Error handling & edge cases

- `dex/status` failure → grid degrades gracefully (no overlays), non-blocking notification.
- `route` failure → inline error in drawer; **Mark as caught** stays usable.
- Data gap (available, no method) → explicit drawer message, not mislabeled as not-in-your-games.
- Evolve routes never suggest an ancestor that is itself unobtainable in owned games.

## Verification

No test framework configured; verify by:

- `go build ./...` passes.
- Run `cmd/seed_shiny_locks` and the evolution seed against the DB; spot-check `shiny_locks` and `pokemon.evolves_from_id`.
- `npm run lint` and `npm run build` pass.
- Manual pass via dev server / Playwright: confirm the four cell states; open the drawer for a missing / locked / not-in-your-games / data-gap Pokémon; start a hunt; mark caught and confirm the cell updates.

## Affected files

**Backend**
- `backend/schema.sql` — `shiny_locks` table, `pokemon.evolves_from_id` column.
- `backend/seeds/shiny_locks.json` — new curated lock data.
- `backend/cmd/seed_shiny_locks/main.go` — new seed tool.
- `backend/cmd/seed/main.go` + `backend/internal/services/pokeapi.go` — capture `evolves_from_species` and populate `evolves_from_id` during the existing crawl.
- `backend/internal/api/router.go` — register `/api/dex/status` and `/api/pokemon/{id}/route`.
- `backend/internal/api/handlers.go` — new handlers; extend the hunt-methods query with `base_odds` + charm.
- `backend/internal/calc/odds.go` — reused (single source of truth for odds).

**Frontend**
- `frontend/src/components/Collection.tsx` — fetch dex status, four cell states, open drawer on click.
- New drawer component under `frontend/src/components/` (or `features/`).
- Remove duplicated `getOddsForMethod` once routes are server-computed.
