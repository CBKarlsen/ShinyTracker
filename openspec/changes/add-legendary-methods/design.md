## Context

With `is_legendary` filtering actively blocking standard wild hunt methods, legendary Pokémon currently have very few or zero hunting methods assigned to them. We need to introduce the standard historically accurate methods for hunting legendaries: "Soft Resetting" (Static Encounter) and "Run Away". We also want to provide visual distinction in the frontend so users know this is a special "Legendary Hunt".

## Goals / Non-Goals

**Goals:**
- Add "Soft Reset (Static)" and "Run Away" to the `hunt_methods.json` seeder.
- Map these new methods primarily to legendary Pokémon using the `is_legendary` rule condition, while potentially keeping them available broadly if they apply to static non-legendaries (e.g. Snorlax). For simplicity, we will map them using `always_true` but they will naturally become the *only* standard methods available for legendaries. Wait, actually, if they are just standard methods, legendaries will get them. We will use `always_true` for them so that both Snorlax and Rayquaza can use Soft Resetting.
- Update the frontend `MethodList` or `OddsCalculator` UI to detect if the active Pokémon is a legendary (via the `pokemon` API response) and display a special "Legendary Hunt" badge next to the method list.

**Non-Goals:**
- Creating custom legendary-specific UI views entirely divorced from the standard hunting UI. A simple badge or visual highlight is sufficient.

## Decisions

**Decision 1: "Soft Reset" and "Run Away" as global methods**
*Rationale:* Even though we are adding these specifically to fix the legendary gap, Soft Resetting is a valid method for static encounters (like Sudowoodo or Snorlax) across all generations. Therefore, their condition in `method_rules.json` will be `always_true`. Because legendaries are blocked from random encounters via `not_legendary_or_mythical`, Soft Resetting will naturally become their primary/only wild method.

**Decision 2: UI Badge Logic**
*Rationale:* To power the UI badge, the frontend needs to know if the selected Pokémon is a legendary. The `GET /api/pokemon` and `GET /api/pokemon/:id` endpoints must be updated to return the `is_legendary` and `is_mythical` flags so the frontend React components can consume them and render the badge conditionally.

## Risks / Trade-offs

- **Risk:** "Run Away" method might not be viable in every single game for every static encounter.
- **Mitigation:** We can restrict "Run Away" to games where it is historically known to work (e.g., Brilliant Diamond/Shining Pearl for Shaymin/Darkrai, Sword/Shield Regis) by explicitly defining the `games` array in `hunt_methods.json`, or leave it generic and let users self-select. We will restrict it to modern games where it is popular.
