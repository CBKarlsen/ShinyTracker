## Context

Currently, the rule engine maps hunting methods to Pokémon via `method_rules.json` and explicit overrides in `method_exceptions.json`. For methods like "Random Encounter" or "Poké Radar", the rule is currently `always_true`, meaning it applies to all Pokémon in the game. However, legendary and mythical Pokémon are virtually never available through these generic wild encounters; they are hunted via Soft Resets (Static) or specialized mechanics like Dynamax Adventures.

## Goals / Non-Goals

**Goals:**
- Store `is_legendary` and `is_mythical` metadata in the `pokemon` table.
- Modify the `SyncPokemonData` service to fetch these flags from the PokeAPI `/pokemon-species/` endpoint during the sync pipeline.
- Define a method rule condition (e.g., `not_legendary_or_mythical`) to easily exclude them from methods where they cannot appear.

**Non-Goals:**
- Manually compiling encounter tables for every game and every route. (We are simply adding top-level flag filters).
- Exposing the `is_legendary` flag visually in the frontend UI at this time.

## Decisions

**Decision 1: Fetching flags from PokeAPI species endpoint**
*Rationale:* The `/pokemon-species/{id}` endpoint provides `is_legendary` and `is_mythical`. This requires an additional HTTP request per Pokémon during sync. Since syncing is done as a background job and is mostly static, the performance cost of N extra API calls is negligible and acceptable.

**Decision 2: Updating the `pokemon` table schema**
*Rationale:* We need these flags for rapid querying during the calculation of `method_availability`. Storing them directly in the `pokemon` table avoids complex joins with a hypothetical metadata table.

**Decision 3: `method_rules.json` Condition Language**
*Rationale:* We will add a condition evaluator for `not_legendary_or_mythical`. If a rule has this condition, it evaluates to `true` ONLY if `p.is_legendary = false AND p.is_mythical = false`.

## Risks / Trade-offs

- **Risk:** PokeAPI rate limits during the sync script due to querying the species endpoint for all ~1000+ Pokémon.
- **Mitigation:** The sync script already throttles or handles requests decently. If needed, we can implement a slight delay or concurrent workers with a rate limiter.

- **Risk:** Some sub-legendaries or ultra beasts might not be strictly classified as "legendary" in PokeAPI.
- **Mitigation:** We can still use `method_exceptions.json` to surgically remove those edge cases from specific games.
