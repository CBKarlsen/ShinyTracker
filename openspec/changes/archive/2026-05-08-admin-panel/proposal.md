## Why

Managing encounter methods, games, Pokémon availability, and users currently requires direct database access — there is no UI for the site owner to curate data. An admin panel removes that dependency and makes the site self-maintainable without developer tooling.

## What Changes

- Add `is_admin` boolean column to the `users` table; default `false`.
- Add admin-only API routes behind an admin middleware that checks `is_admin`.
- Add an **Admin** section to the sidebar (visible only to admin users) that routes to four management pages:
  - **Encounters** — search Pokémon, view/add/edit/delete encounter method rows per Pokémon + game.
  - **Games** — view/add/edit games (title, generation, base odds, breeding support).
  - **Availability** — for a selected Pokémon, view and toggle which games it is available in.
  - **Users** — view all registered users; promote/demote admin flag.
- No existing user-facing features are changed or broken.

## Capabilities

### New Capabilities

- `admin-auth`: `is_admin` flag on users; admin middleware rejecting non-admin requests with 403; login flow unchanged.
- `admin-encounters`: CRUD UI and API for encounter rows — search by Pokémon name, list encounters for that Pokémon, add/edit/delete rows.
- `admin-games`: CRUD UI and API for the games table — list all games, add new game, edit existing, delete (with guard if encounters reference it).
- `admin-availability`: UI and API to manage the `pokemon_availability` table — pick a Pokémon, toggle game availability checkboxes.
- `admin-users`: Read-only user list with ability to toggle `is_admin` on any account.

### Modified Capabilities

- None — all changes are additive.

## Impact

- **Schema**: One migration — `ALTER TABLE users ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT FALSE`.
- **Backend**: New file `internal/api/admin.go` with all admin handlers; new `AdminMiddleware` in `auth.go`; new admin route group in `router.go`.
- **Frontend**: New `src/components/admin/` directory with five components (shell + four pages); `Sidebar.tsx` conditionally shows Admin section based on decoded JWT or user profile endpoint.
- **No breaking changes** to existing routes or frontend pages.
