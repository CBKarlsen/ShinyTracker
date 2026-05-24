## Why

After cleaning up the method availability logic to correctly exclude legendary and mythical Pokémon from standard wild encounters, these Pokémon now have almost no valid hunting methods attached to them in the app (e.g. Rayquaza). Legendary Pokémon are almost exclusively hunted via "Soft Resetting" (Static Encounters) or "Run Away" encounters. We need to introduce these methods to the database and provide visual distinction in the UI to reflect the unique nature of these hunts.

## What Changes

- Add new methods "Soft Reset (Static)" and "Run Away" to the `hunt_methods.json` seeder data.
- Update `method_rules.json` to assign these new methods to the `is_legendary` condition (and `always_true` for non-legendary statics if desired, but primarily we will map them via `is_legendary`).
- Update the Frontend UI (Method Library sidebar and Hunt views) to visually distinguish methods when hunting a Legendary (e.g., displaying a "Legendary" badge or distinct styling).

## Capabilities

### New Capabilities
- `legendary-methods`: Defines the data and UX requirements for legendary-specific hunting techniques.

### Modified Capabilities
- `method-library`: Update the UI requirements for method rows to render a visual badge if the selected Pokémon is a legendary.

## Impact

- **Database/Seeds**: New method definitions in `hunt_methods.json` and new rules in `method_rules.json`.
- **API**: The `GET /api/methods` and `GET /api/hunt-methods` endpoints will naturally return the new methods due to the backend rule engine.
- **Frontend**: Minor UX/UI updates to the Method Library widget to support legendary styling or badges.
