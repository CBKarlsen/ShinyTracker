## Why

Currently, hunting methods like "Poké Radar", "SOS Chaining", or standard "Random Encounters" can incorrectly appear as valid hunting methods for Legendary and Mythical Pokémon. Because these Pokémon are exclusively hunted via Static Encounters or specific post-game modes (like Dynamax Adventures), we need a scalable way to filter out standard methods for them. Fetching these flags from PokeAPI and persisting them in our database will allow us to create highly accurate method rules.

## What Changes

- Update the database schema (`pokemon` table) to include boolean flags for `is_legendary` and `is_mythical`.
- Update the `SyncPokemonData` service to fetch `is_legendary` and `is_mythical` from PokeAPI (`pokemon-species` endpoint) and save them to the database.
- Update `backend/seeds/method_rules.json` to leverage these new flags (e.g., exclude `is_legendary` and `is_mythical` from standard wild methods like "Random Encounter" or "Poké Radar").

## Capabilities

### New Capabilities
- None

### Modified Capabilities
- `method-library`: Update method availability logic to evaluate Pokémon metadata flags (`is_legendary`, `is_mythical`).

## Impact

- **Database**: `pokemon` table requires schema migration.
- **Backend Service**: PokeAPI syncing requires an additional fetch to the `/pokemon-species/` endpoint to get legendary/mythical flags.
- **Seed Data**: `method_rules.json` and `method_exceptions.json` will need adjusting.
- **Frontend**: None directly, but the UI will display more accurate method lists for legendary Pokémon.
