## 1. Database Schema

- [x] 1.1 Add `is_legendary` (boolean, default false) and `is_mythical` (boolean, default false) columns to the `pokemon` table in `backend/schema.sql`.

## 2. Backend Services

- [x] 2.1 Update `SyncPokemonData` in `backend/internal/services/pokeapi.go` to fetch the `/pokemon-species/` endpoint for each Pokémon.
- [x] 2.2 Parse `is_legendary` and `is_mythical` flags from the PokeAPI species response.
- [x] 2.3 Update the `INSERT INTO pokemon` database query in `SyncPokemonData` to save the new flags.

## 3. Seed Data Updates

- [x] 3.1 Update the `method_rules.json` file. Change the generic `always_true` condition on standard wild hunting methods (e.g. Random Encounter, Poké Radar) to a new condition like `not_legendary_or_mythical`.
- [x] 3.2 Update `backend/cmd/seed/main.go` rule engine `computeAvailability()` to properly evaluate the new `not_legendary_or_mythical` condition when inserting into `method_availability`.

## 4. Verification

- [x] 4.1 Apply the updated schema.sql to the database.
- [x] 4.2 Run `POST /api/sync` or manually trigger the `SyncPokemonData` service to populate the flags.
- [x] 4.3 Run the seeder and verify that `method_availability` no longer maps generic methods to Rayquaza and other legendaries.
