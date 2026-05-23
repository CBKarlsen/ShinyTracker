## ADDED Requirements

### Requirement: is_admin flag on users
The `users` table SHALL have an `is_admin` BOOLEAN column, NOT NULL, defaulting to FALSE.

#### Scenario: New user registration
- **WHEN** a new user registers
- **THEN** their `is_admin` is FALSE by default

#### Scenario: Existing users after migration
- **WHEN** the migration runs
- **THEN** all existing users have `is_admin = FALSE`

### Requirement: Admin middleware
The system SHALL reject requests to any `/api/admin/*` route from non-admin users with HTTP 403, even if they hold a valid JWT.

#### Scenario: Non-admin user accesses admin route
- **WHEN** a valid JWT is presented but the user's `is_admin` is FALSE
- **THEN** the response is `403 Forbidden`

#### Scenario: Admin user accesses admin route
- **WHEN** a valid JWT is presented and the user's `is_admin` is TRUE
- **THEN** the request proceeds to the handler

#### Scenario: Unauthenticated request to admin route
- **WHEN** no JWT is presented
- **THEN** the response is `401 Unauthorized` (from AuthMiddleware, before AdminMiddleware)

### Requirement: Profile endpoint
The system SHALL expose `GET /api/me` (auth required) returning `{ id, username, is_admin }`.

#### Scenario: Admin user fetches profile
- **WHEN** an admin user calls `GET /api/me`
- **THEN** the response includes `"is_admin": true`

#### Scenario: Regular user fetches profile
- **WHEN** a non-admin user calls `GET /api/me`
- **THEN** the response includes `"is_admin": false`

### Requirement: Bootstrap CLI
The system SHALL provide a CLI command (`cmd/make_admin`) that sets `is_admin = true` for a user identified by email.

#### Scenario: Promoting first admin
- **WHEN** `go run ./cmd/make_admin/main.go <email>` is executed with a valid email
- **THEN** that user's `is_admin` is set to TRUE and a success message is printed

#### Scenario: Unknown email
- **WHEN** the email does not match any user
- **THEN** an error is printed and no changes are made

### Requirement: Admin sidebar section
The frontend sidebar SHALL show an "Admin" navigation section containing links to the four admin pages, visible only when the current user's `is_admin` is TRUE.

#### Scenario: Admin user views sidebar
- **WHEN** `GET /api/me` returns `is_admin: true`
- **THEN** the Admin section is visible in the sidebar

#### Scenario: Regular user views sidebar
- **WHEN** `GET /api/me` returns `is_admin: false`
- **THEN** no Admin section is visible
