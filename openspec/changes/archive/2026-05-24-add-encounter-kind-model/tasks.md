## 1. Schema

- [x] 1.1 Add `pokemon_game_encounter (pokemon_id INT, game_id INT, kind TEXT)` table to `schema.sql` with a CHECK constraint on `kind IN ('wild','static','raid','egg')` and a PK/unique on `(pokemon_id, game_id, kind)`
- [x] 1.2 Add `requires_kind TEXT` column to `hunt_methods` (NOT NULL, same CHECK enum)
- [x] 1.3 Add a `cmd/apply_schema` / migration step that creates the new table + column without dropping `user_hunts` data

## 2. Method definitions

- [x] 2.1 Add `requires_kind` to every entry in `seeds/hunt_methods.json` (wild: Random Encounter, SOS Chaining, Poké Radar, DexNav, Friend Safari, Catch Combo, Chain Fishing, Mass Outbreak, Sandwich Hunting, Paldea/Kitakami/Terarium Outbreak; static: Soft Reset; raid: Dynamax Adventures, KO Method; egg: Masuda Method, Run Away as applicable)
- [x] 2.2 Update the `hunt_methods` seed loader in `cmd/seed/main.go` to read and persist `requires_kind`

## 3. Auto-derived kinds (wild, egg)

- [x] 3.1 Extend `internal/services/pokeapi.go` to fetch `/pokemon/{id}/encounters` and capture (version → game) wild encounters
- [x] 3.2 Extend the species fetch to capture `egg_groups` and persist a breedable flag (exclude `no-eggs`/`undiscovered`)
- [x] 3.3 Add a seed step that inserts `wild` records from captured encounters (version→game mapping reuses existing logic)
- [x] 3.4 Add a seed step that inserts `egg` records by joining breedable species with `pokemon_availability`

## 4. Curated kinds (static, raid)

- [x] 4.1 Create `seeds/game_groups.json` with alias → game-list entries (e.g. `@swsh-dynamax`)
- [x] 4.2 Create `seeds/legendary_encounters.json` with entries `{pokemon_id, name, default_kind, default_games, overrides}`; seed an initial set of legendaries including Rayquaza
- [x] 4.3 Implement a loader: covered games = `default_games` ∪ `overrides` keys; expand group aliases; resolve kind per game (explicit override wins over group, default otherwise); skip `none`; insert `static`/`raid` records

## 5. Availability computation

- [x] 5.1 Rewrite `computeAvailability` in `cmd/seed/main.go` to build `method_availability` via the join `pokemon_game_encounter ⋈ hunt_methods ON requires_kind ⋈ method_games ON game_id`
- [x] 5.2 Update the seed `TRUNCATE` list and orchestration to populate encounter kinds before computing availability
- [x] 5.3 Remove `method_rules` usage from the seed and stop loading `seeds/method_rules.json`

## 6. Invariant checks

- [x] 6.1 After computing availability, assert no `method_availability` row lacks a matching `pokemon_game_encounter` (kind+game); fail with non-zero exit listing offenders
- [x] 6.2 Assert every `hunt_methods.requires_kind` is set and within the enum; fail otherwise
- [x] 6.3 Validate `legendary_encounters.json` references only known game titles and defined `@`-aliases (validated against the `games` table); fail otherwise

## 7. Cleanup & deprecation

- [x] 7.1 Drop the `method_rules` table from `schema.sql` and remove `seeds/method_rules.json`
- [x] 7.2 Repurpose/remove `seeds/method_exceptions.json` (migrate any still-needed entries into curated kinds or a general `encounter_overrides.json`)
- [x] 7.3 Remove flag-based availability code paths; keep `is_legendary`/`is_mythical` ingestion only for display

## 8. Verification

- [x] 8.1 Re-seed and confirm Rayquaza in Sword/Shield offers Dynamax Adventures only (no Soft Reset, no Random Encounter)
- [x] 8.2 Confirm Rayquaza offers Soft Reset in Ruby/Sapphire/Emerald and ORAS
- [x] 8.3 Spot-check a common wild Pokémon (wild + egg methods) and a breed-only Pokémon against expected methods
- [ ] 8.4 (Optional) Add a read-only admin availability matrix (per Pokémon: method × game) for spot-checking curated legendaries
