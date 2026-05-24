## Why

Method availability is currently derived from coarse boolean flags (`is_legendary`, `is_breedable`) plus a 585-row hand-maintained `method_exceptions` patch list. Flags are only a proxy for *how* a Pokémon is encountered, so they break at the edges: Rayquaza shows Soft Reset and Dynamax Adventures in Sword/Shield because the `always_true` rules attach those methods to every Pokémon in the listed games, ignoring that Rayquaza is a raid encounter there (not soft-resettable). The model also never consults `pokemon_availability`, so methods can appear in games where a Pokémon isn't legally obtainable. The exception list cannot scale and cannot be trusted to be correct.

## What Changes

- Introduce an **encounter-kind** model: each `(pokemon, game)` pair carries one or more kinds (`wild`, `static`, `raid`, `egg`) recorded in a new `pokemon_game_encounter` table.
- Each hunt method declares the kind it consumes (`requires_kind`); `method_availability` is recomputed as a join on `(game_id, kind)` instead of flag matching.
- **`wild`** and **`egg`** kinds are auto-derived (PokeAPI `/encounters` + egg groups), so the bulk of the dex needs no manual curation.
- **`static`** and **`raid`** kinds are curated via a compact `legendary_encounters.json` keyed by Pokémon, using `default_kind` + a `default_games` list + per-game `overrides`. Reusable game-group aliases (e.g. `@swsh-dynamax`) avoid repetition. (Curation lists games directly rather than leaning on `pokemon_availability`, which only covers Switch-era games.)
- Add **seed invariant checks** that fail the seed if availability is internally inconsistent (e.g. a Soft Reset row without a `static` encounter, Masuda without `egg`).
- **BREAKING**: Remove the flag-based `method_rules` table and shrink `method_exceptions` to the curated legendary file. The `computeAvailability` seed step is rewritten.

## Capabilities

### New Capabilities
- `encounter-kind-availability`: Defines encounter kinds per `(pokemon, game)`, how methods declare the kind they consume, how `method_availability` is computed as a kind/game join, the derivation of `wild`/`egg`, the curated `static`/`raid` format with game-group aliases, and seed-time invariant checks.

### Modified Capabilities
- `method-library`: Removes the "Flag-Based Availability Rules" requirement (`is_legendary`/`is_mythical` conditions) — superseded by kind-based availability.
- `game-specific-methods`: Method-to-game mapping is retained but is no longer sufficient on its own; availability additionally requires an encounter-kind match for the specific Pokémon.

## Impact

- **Schema**: new `pokemon_game_encounter` table; `hunt_methods.requires_kind` column; drop `method_rules`; `method_exceptions` repurposed/curated.
- **Backend seed**: `cmd/seed/main.go` `computeAvailability` rewritten; new derivation step for `wild`/`egg`; new `legendary_encounters.json` + `game_groups.json` loaders; invariant checks.
- **PokeAPI sync**: `internal/services/pokeapi.go` extended to capture wild encounters and egg groups.
- **API**: `GET /api/hunt-methods` (per-Pokémon) and `/api/methods` continue to read `method_availability` — no contract change, only more accurate data.
- **Seeds**: `method_rules.json` removed; `method_exceptions.json` replaced by `legendary_encounters.json` + `game_groups.json`.
- **Admin**: optional read-only availability matrix to spot-check curated legendaries.
