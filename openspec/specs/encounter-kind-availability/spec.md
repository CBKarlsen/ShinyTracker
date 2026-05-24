# encounter-kind-availability Specification

## Purpose
TBD - created by archiving change add-encounter-kind-model. Update Purpose after archive.
## Requirements
### Requirement: Encounter Kinds per Pokémon and Game
The system SHALL record, for each `(pokemon, game)` pair, one or more encounter kinds drawn from the closed set `wild`, `static`, `raid`, `egg`. Each kind describes how the Pokémon can be obtained in that game and is stored independently of any hunting method.

#### Scenario: A Pokémon has different kinds in different games
- **WHEN** Rayquaza (#384) is recorded as `static` in Ruby/Sapphire/Emerald and as `raid` in Sword/Shield
- **THEN** both facts are stored as separate encounter-kind records keyed by Pokémon and game

#### Scenario: A Pokémon has multiple kinds in one game
- **WHEN** a Pokémon is both a wild spawn and breedable in Scarlet/Violet
- **THEN** it has both a `wild` and an `egg` encounter-kind record for Scarlet/Violet

#### Scenario: Invalid kind is rejected
- **WHEN** an encounter-kind record is created with a kind outside the closed set
- **THEN** the seed fails with a non-zero exit and an error naming the offending Pokémon and kind

### Requirement: Methods Declare a Consumed Kind
Each hunt method SHALL declare exactly one encounter kind it consumes (`requires_kind`). A method is only valid for a Pokémon in a game when that Pokémon has the method's required kind in that game.

#### Scenario: Soft Reset requires a static encounter
- **WHEN** a Pokémon has no `static` encounter-kind record in a game
- **THEN** Soft Reset is not offered for that Pokémon in that game, regardless of legendary status

#### Scenario: Dynamax Adventures requires a raid encounter
- **WHEN** Rayquaza has a `raid` record in Sword/Shield but no `static` record there
- **THEN** Dynamax Adventures is offered and Soft Reset is not, for Rayquaza in Sword/Shield

#### Scenario: Masuda Method requires an egg encounter
- **WHEN** a Pokémon has an `egg` encounter-kind record in a game
- **THEN** Masuda Method is offered for that Pokémon in that game

### Requirement: Availability Computed as a Kind and Game Join
The system SHALL compute `method_availability` by joining encounter-kind records to methods on matching kind and to `method_games` on matching game. No boolean species flag SHALL be used to determine availability.

#### Scenario: Availability requires both kind and game mapping
- **WHEN** a method requires `wild`, a Pokémon has a `wild` record in a game, and the method is mapped to that game via `method_games`
- **THEN** a `method_availability` row is created for that Pokémon, method, and game

#### Scenario: Method not mapped to the game is excluded
- **WHEN** a Pokémon has the required kind in a game but the method is not mapped to that game
- **THEN** no `method_availability` row is created

#### Scenario: Pokémon unavailable in a game gets no methods
- **WHEN** a Pokémon has no encounter-kind records for a game
- **THEN** no methods are offered for that Pokémon in that game

### Requirement: Automatic Derivation of Wild and Egg Kinds
The system SHALL derive `wild` and `egg` encounter-kind records automatically rather than by manual curation.

#### Scenario: Wild kind derived from PokeAPI encounters
- **WHEN** PokeAPI reports a wild encounter for a non-legendary Pokémon in a version belonging to game G
- **THEN** a `wild` encounter-kind record is created for that Pokémon and game G

#### Scenario: Legendaries are excluded from wild derivation
- **WHEN** a Pokémon has `is_legendary` or `is_mythical` set to true
- **THEN** no `wild` encounter-kind record is auto-derived for it (PokeAPI reports its stationary encounter as a location), and its kinds come exclusively from curated `static`/`raid` records

#### Scenario: Egg kind derived from breedable egg groups
- **WHEN** a Pokémon's species belongs to a breedable egg group (not `no-eggs`/`undiscovered`) and its line is available in game G
- **THEN** an `egg` encounter-kind record is created for that Pokémon and game G

#### Scenario: Non-breedable Pokémon gets no egg kind
- **WHEN** a Pokémon belongs to the `undiscovered` egg group
- **THEN** no `egg` encounter-kind record is created for it in any game

### Requirement: Curated Static and Raid Encounters
The system SHALL source `static` and `raid` encounter-kind records from a curated file keyed by Pokémon. Each entry SHALL list the games it covers via a `default_kind` applied to a `default_games` list, plus optional per-game `overrides`. The covered game set is the union of `default_games` and the `overrides` keys; curation SHALL NOT depend on `pokemon_availability` (which only covers Switch-era games). An override value of `none` SHALL suppress a game otherwise pulled in by a group alias.

#### Scenario: Default kind applied across listed games
- **WHEN** a curated entry sets `default_kind` to `static` with `default_games` including Ruby/Sapphire/Emerald and Omega Ruby/Alpha Sapphire
- **THEN** a `static` encounter-kind record is created for each of those games

#### Scenario: Override sets a different kind for a specific game
- **WHEN** a curated entry has `default_kind` `static` and an override of `raid` for Sword/Shield
- **THEN** the Sword/Shield record is `raid` while the `default_games` remain `static`

#### Scenario: None override suppresses a record
- **WHEN** a group alias pulls in a game and an override sets that game to `none`
- **THEN** no encounter-kind record is created for that Pokémon in that game

#### Scenario: Unknown game is rejected
- **WHEN** a curated entry references a game title that does not exist in the `games` table
- **THEN** the seed fails with an error naming the Pokémon and game

### Requirement: Reusable Game-Group Aliases
The system SHALL support named game-group aliases (prefixed with `@`) that expand to a list of games, usable as keys in curated overrides. An explicit single-game override SHALL take precedence over a group override for the same game.

#### Scenario: Group alias expands to its games
- **WHEN** a curated override uses `@swsh-dynamax` mapped to `["Sword/Shield"]`
- **THEN** the override applies to Sword/Shield as if listed explicitly

#### Scenario: Explicit override wins over group override
- **WHEN** an entry has both a group override covering game G and an explicit override for game G
- **THEN** the explicit per-game value is used for game G

#### Scenario: Unknown alias is rejected
- **WHEN** a curated override references an `@`-prefixed alias not defined in the game-groups file
- **THEN** the seed fails with an error naming the unknown alias

### Requirement: Seed-Time Invariant Checks
The seed SHALL validate computed availability and fail with a non-zero exit when an invariant is violated, rather than producing inconsistent data silently.

#### Scenario: Availability without a matching encounter kind
- **WHEN** a `method_availability` row exists whose method's required kind has no corresponding encounter-kind record for that Pokémon and game
- **THEN** the seed fails and reports the offending row

#### Scenario: Method missing a required kind
- **WHEN** a hunt method has no `requires_kind` or an invalid one
- **THEN** the seed fails and reports the offending method

