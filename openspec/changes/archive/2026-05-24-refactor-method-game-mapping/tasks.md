## 1. Database Schema

- [x] 1.1 Add `method_games` join table to `backend/schema.sql` (mapping `method_id` to `game_id`).
- [x] 1.2 Remove the `generation` column from `hunt_methods` in `backend/schema.sql` to enforce the new schema.

## 2. Seed Data Updates

- [x] 2.1 Update `backend/seeds/hunt_methods.json` format to replace `generation` with a `games` string array containing target game titles.
- [x] 2.2 Update `backend/cmd/seed/main.go` to parse the new `games` array from JSON.
- [x] 2.3 Update `backend/cmd/seed/main.go` to populate the `method_games` table by joining the game titles to `games.id`.
- [x] 2.4 Update `backend/cmd/seed/main.go` to insert into `hunt_methods` without the `generation` field.

## 3. Backend API Updates

- [x] 3.1 Update `GetMethodsHandler` in `handlers.go` to join `method_games` instead of matching `generation`.
- [x] 3.2 Update `GetHuntMethodsHandler` in `handlers.go` to join `method_games` instead of matching `generation`.

## 4. Verification

- [x] 4.1 Run the backend seeder and verify no errors.
- [x] 4.2 Start the backend API and verify `GET /api/methods` only returns the expected methods for specific games (e.g., SOS Chaining only for Sun/Moon/US/UM, Catch Combo only for Let's Go).
