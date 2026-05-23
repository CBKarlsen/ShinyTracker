## 1. Database & Migration

- [x] 1.1 Write migration SQL: `ALTER TABLE users ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT FALSE`
- [x] 1.2 Create `backend/cmd/make_admin/main.go` — CLI that sets `is_admin = true` for a user by email

## 2. Backend — Auth & Middleware

- [x] 2.1 Add `IsAdmin bool` field to `models.User`
- [x] 2.2 Add `AdminMiddleware` in `internal/api/auth.go` — reads `X-User-ID`, queries `is_admin`, returns 403 if false
- [x] 2.3 Add `GET /api/me` handler in `internal/api/handlers.go` returning `{ id, username, is_admin }`
- [x] 2.4 Register `GET /api/me` (auth required) and `/api/admin/*` route group (auth + admin) in `router.go`

## 3. Backend — Admin Handlers

- [x] 3.1 Create `internal/api/admin.go` with `AdminGetEncounters`, `AdminCreateEncounter`, `AdminUpdateEncounter`, `AdminDeleteEncounter`
- [x] 3.2 Add `AdminGetGames`, `AdminCreateGame`, `AdminUpdateGame`, `AdminDeleteGame` (with encounter-count guard) to `admin.go`
- [x] 3.3 Add `AdminGetAvailability`, `AdminSetAvailability` to `admin.go`
- [x] 3.4 Add `AdminGetUsers`, `AdminPatchUser` (with self-demote guard) to `admin.go`
- [x] 3.5 Register all admin routes in `router.go` under `/api/admin/` behind AdminMiddleware

## 4. Frontend — Auth & Sidebar

- [x] 4.1 Add `isAdmin` to `AuthContext` — fetch `GET /api/me` on mount, store result
- [x] 4.2 Update `Sidebar.tsx` to show an "Admin" section with four nav items when `isAdmin` is true

## 5. Frontend — Admin Shell

- [x] 5.1 Create `src/components/admin/Admin.tsx` — sub-tab bar (Encounters / Games / Availability / Users) and content router
- [x] 5.2 Add `"admin"` to the `Route` type in `App.tsx` and render `<Admin />` when active
- [x] 5.3 Add `"admin"` label to `Topbar.tsx` route labels

## 6. Frontend — Encounters Page

- [x] 6.1 Create `src/components/admin/AdminEncounters.tsx` — Pokémon search input using `/api/pokemon`
- [x] 6.2 Fetch and display encounter table for selected Pokémon via `GET /api/admin/encounters?pokemon_id=<id>`
- [x] 6.3 Implement add-encounter inline form (game select, method name, rolls, avg time, recommended checkbox)
- [x] 6.4 Implement edit-in-place for existing encounter rows
- [x] 6.5 Implement delete encounter row with confirmation

## 7. Frontend — Games Page

- [x] 7.1 Create `src/components/admin/AdminGames.tsx` — fetch and display all games via `GET /api/admin/games`
- [x] 7.2 Implement add-game form (title, generation, base odds, supports breeding toggle)
- [x] 7.3 Implement edit-in-place for game rows
- [x] 7.4 Implement delete game with error display when blocked by encounters

## 8. Frontend — Availability Page

- [x] 8.1 Create `src/components/admin/AdminAvailability.tsx` — Pokémon search input
- [x] 8.2 Fetch all games with availability flags via `GET /api/admin/availability?pokemon_id=<id>`
- [x] 8.3 Render checklist of games; on toggle call `PUT /api/admin/availability` immediately

## 9. Frontend — Users Page

- [x] 9.1 Create `src/components/admin/AdminUsers.tsx` — fetch and display all users via `GET /api/admin/users`
- [x] 9.2 Render admin toggle per user; call `PATCH /api/admin/users/{id}` on change
- [x] 9.3 Prevent self-demote: disable the toggle for the current user's own row with a tooltip
