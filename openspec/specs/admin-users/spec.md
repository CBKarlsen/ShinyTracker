# admin-users Specification

## Purpose
Defines the admin user-management surface: listing users, toggling the admin flag, and the Users admin page.

## Requirements

### Requirement: List all users
The system SHALL expose `GET /api/admin/users` returning all registered users.

#### Scenario: Users exist
- **WHEN** the endpoint is called by an admin
- **THEN** the response is a JSON array with `id`, `username`, `email`, `is_admin`, `created_at` for each user

### Requirement: Toggle admin flag
The system SHALL expose `PATCH /api/admin/users/{id}` accepting `{ is_admin: bool }` to promote or demote a user.

#### Scenario: Promote user to admin
- **WHEN** `{ "is_admin": true }` is sent for a valid user id
- **THEN** that user's `is_admin` is set to TRUE

#### Scenario: Demote admin to user
- **WHEN** `{ "is_admin": false }` is sent for a valid user id
- **THEN** that user's `is_admin` is set to FALSE

#### Scenario: Admin cannot demote themselves
- **WHEN** the requesting admin sends `{ "is_admin": false }` for their own user id
- **THEN** the response is `400 Bad Request` to prevent accidental self-lockout

#### Scenario: Unknown user
- **WHEN** the user `id` does not exist
- **THEN** the response is `404 Not Found`

### Requirement: Users admin page
The admin users page SHALL display a table of all users showing username, email, join date, and admin status, with a toggle to promote or demote each user.

#### Scenario: View user list
- **WHEN** the admin navigates to the Users page
- **THEN** all registered users are shown in a table

#### Scenario: Toggle admin status
- **WHEN** the admin clicks the admin toggle for a user
- **THEN** the change is persisted and the row reflects the new status

#### Scenario: Self-demote blocked
- **WHEN** the admin attempts to remove their own admin flag
- **THEN** an error message is shown and no change is made
