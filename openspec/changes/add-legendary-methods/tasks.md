## 1. Seed Data Updates

- [x] 1.1 Add "Soft Reset (Static)" to `hunt_methods.json`. Assign it an `id` of `soft_reset_static`, an average time of ~30-40 seconds, and map it to a broad set of games (or all core games).
- [x] 1.2 Add "Run Away" to `hunt_methods.json`. Assign it an `id` of `run_away`, an average time of ~30-40 seconds, and map it to relevant games (e.g. Brilliant Diamond/Shining Pearl, Sword/Shield).
- [x] 1.3 Update `method_rules.json` to assign `soft_reset_static` and `run_away` with the condition `"always_true"`.

## 2. API Updates

- [x] 2.1 Update `GetPokemonHandler` in `backend/internal/api/handlers.go` to select and return `is_legendary` and `is_mythical` flags in the JSON response.
- [x] 2.2 Update `GetPokemonByIDHandler` in `backend/internal/api/handlers.go` to select and return `is_legendary` and `is_mythical` flags in the JSON response.

## 3. Frontend Updates

- [x] 3.1 Update the `Pokemon` interface in `frontend/src/types/index.ts` to include `is_legendary` and `is_mythical`.
- [x] 3.2 Update `frontend/src/components/MethodList.tsx` (or wherever the Method Library sidebar is rendered) to conditionally display a "Legendary Hunt" badge if the active Pokémon has `is_legendary` or `is_mythical` set to true.

## 4. Verification

- [x] 4.1 Run the database seeder (`cd backend && go run ./cmd/seed`) to apply the new methods.
- [x] 4.2 Verify in the frontend that selecting a legendary Pokémon (e.g., Rayquaza) shows "Soft Reset (Static)" and the Legendary badge.
