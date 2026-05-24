## Context

Currently, the `hunt_methods` table has a `generation` column. When mapping methods to games, the application joins `games` and `hunt_methods` on `generation`. This causes methods that are exclusive to certain games (like Let's Go Pikachu's Catch Combos or Sun/Moon's SOS Chaining) to bleed into all games within the same generation.

## Goals / Non-Goals

**Goals:**
- Decouple hunting method selection from pure `generation` matching.
- Associate hunting methods explicitly with the specific `games` they appear in.
- Update the seeder and APIs to consume the new mapping structure without breaking existing hunts.

**Non-Goals:**
- Overhauling the `method_availability` rules engine. The engine will remain the same, but it will evaluate availability based on specific game maps rather than broad generation sweeps.

## Decisions

- **Join Table**: Introduce a `method_games` join table mapping `method_id` to `game_id`. This enables robust SQL joins and maintains referential integrity.
- **Seeder Schema Updates**: The `hunt_methods.json` seed file will be updated to replace `"generation": X` with an array of `"games": ["Sun", "Moon", ...]`. The backend seeder will map these titles to `games.id` and populate `method_games`.
- **API Updates**: Both `GetMethodsHandler` and `GetHuntMethodsHandler` will join through `method_games` ensuring strict mapping. The SQL views/queries will match `method_games.game_id = games.id`.

## Risks / Trade-offs

- **Risk**: Dropping `generation` from `hunt_methods` might require widespread query updates across the backend.
  - **Mitigation**: We will drop the `generation` column from `hunt_methods` because it's no longer the source of truth, and update the specific `handlers.go` endpoints. We can also fetch the generation from the joined `games` table if the UI needs it for grouping.
