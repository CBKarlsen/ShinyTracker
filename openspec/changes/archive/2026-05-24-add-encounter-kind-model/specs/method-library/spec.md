## REMOVED Requirements

### Requirement: Flag-Based Availability Rules
**Reason**: Boolean species flags (`is_legendary`, `is_mythical`) are only a proxy for how a Pokémon is encountered and produce incorrect availability at the edges (e.g. Rayquaza offered Soft Reset and Dynamax Adventures in Sword/Shield). Availability is now determined by the `encounter-kind-availability` capability, which records the actual encounter kind per `(pokemon, game)` and joins methods on the kind they consume.

**Migration**: Replace the `method_rules` flag conditions with encounter-kind records. Methods that previously used `always_true`, `not_legendary_or_mythical`, or `is_breedable` now declare `requires_kind` and match Pokémon that have that kind in the game. `is_legendary`/`is_mythical` may still be ingested for display purposes but no longer drive method availability.
