## Why

Currently, hunting methods in ShinyTracker are mapped to entire generations (e.g., Generation 7) rather than specific games. This causes a major architectural flaw where game-specific methods bleed into unrelated games within the same generation. For example, SOS Chaining (exclusive to Sun/Moon) appears in Let's Go Pikachu/Eevee, and Catch Combos appear in Sun/Moon. This change restructures the database to map methods to specific games directly, resolving these inaccuracies.

## What Changes

- Create a `method_games` join table to explicitly map methods to games.
- **BREAKING**: Modify `GetMethodsHandler` and `GetHuntMethodsHandler` to join on `method_games` rather than matching `generation`.
- Update the seeder to construct `method_games` and map methods only to the specific games they appear in.

## Capabilities

### New Capabilities
- `game-specific-methods`: Maps hunting methods to specific games instead of generations.

### Modified Capabilities
- `method-library`: Modifies the API to filter methods by exact game inclusion instead of generation.

## Impact

- **Database**: Adds `method_games` table. Modifies `method_availability` computation logic to respect `method_games`.
- **API**: Updates `GET /api/methods` and `GET /api/hunt-methods` to use the new join table.
- **Data Integrity**: Significantly improves the accuracy of available hunting methods across all generations.
