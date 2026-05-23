## Context

All data curation (encounters, games, Pokémon availability) is done via seed scripts and direct SQL. The `users` table has no role column. Auth is HS256 JWT with `user_id` as the only claim. The frontend reads `userId` from localStorage (set at login). There are no external dependencies beyond what is already in use.

## Goals / Non-Goals

**Goals:**
- One migration (`is_admin` column) — no new tables
- Admin routes isolated in a new `admin.go` handler file
- AdminMiddleware reuses existing JWT parsing; adds a single DB check for `is_admin`
- Frontend admin section hidden from non-admin users via a profile endpoint
- All four management pages (Encounters, Games, Availability, Users) functional as CRUD

**Non-Goals:**
- Audit logging of admin actions
- Role hierarchy beyond a binary admin/non-admin flag
- Public-facing API versioning
- Bulk import UI (seed scripts remain for bulk operations)

## Decisions

### `is_admin` in users table, not a separate roles table
A separate roles table would be over-engineered for a single role. A boolean column is the simplest correct solution and trivially reversible.

*Alternative*: JWT claim `role: "admin"` — rejected because it requires re-issuing tokens after role change. DB check on every admin request is the correct authority.

### AdminMiddleware does a DB lookup per request
The middleware reads `X-User-ID` (already set by AuthMiddleware), queries `SELECT is_admin FROM users WHERE id = $1`, and rejects with 403 if false. Small overhead, but admin routes are low-traffic and correctness matters more than latency here.

*Alternative*: Embed `is_admin` in the JWT at login — rejected because changing a user's admin status would not take effect until token expiry.

### Separate `admin.go` handler file
Keeps the admin surface area isolated and easy to audit. All admin routes are under `/api/admin/` prefix and wrapped in both AuthMiddleware and AdminMiddleware.

### Frontend: expose `is_admin` via `GET /api/me`
Rather than decoding the JWT in the browser, add a lightweight `/api/me` endpoint returning `{ id, username, is_admin }`. The Sidebar reads this once on mount to decide whether to show the Admin section.

*Alternative*: Decode JWT in the browser — rejected because it couples the frontend to the JWT structure and `is_admin` isn't in the token anyway.

### Admin UI lives in `src/components/admin/`
A subfolder keeps admin components isolated. The admin shell (`Admin.tsx`) renders a secondary tab bar for the four sub-pages. Consistent with the existing card/table design tokens — no new UI library.

## Risks / Trade-offs

- **First admin bootstrap**: No admin exists after migration. → Mitigation: provide a one-time CLI command `go run ./cmd/make_admin/main.go <email>` to set `is_admin = true` by email.
- **Admin deleting a game with encounters**: Cascade deletes could wipe encounter data. → Mitigation: guard the delete endpoint — return 409 if any encounters reference the game; require the admin to remove encounters first.
- **DB check on every admin request**: Adds one query per admin API call. → Acceptable — admin usage is infrequent and the query hits the primary key index.

## Migration Plan

1. Run migration: `ALTER TABLE users ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT FALSE;`
2. Bootstrap first admin via CLI: `go run ./cmd/make_admin/main.go <email>`
3. Deploy backend with new routes and middleware.
4. Deploy frontend — Admin section only appears for users where `is_admin = true`.
5. Rollback: remove the column, revert backend/frontend — no data loss to non-admin rows.
