-- 008_add_profiles.sql
--
-- Additive groundwork for Supabase Auth migration.
-- Creates the `profiles` table that maps Supabase user UUIDs (JWT sub) to
-- app-level user metadata. Does NOT drop or alter the existing `users` table —
-- that happens in the atomic swap step.
--
-- id mirrors auth.users.id. No hard FK to auth.users is declared here so this
-- file can be applied via the Supabase SQL Editor (or go run ./cmd/migrate_*)
-- without needing cross-schema (auth.*) permissions.
--
-- Idempotent: safe to run multiple times.

CREATE TABLE IF NOT EXISTS profiles (
    id          uuid        PRIMARY KEY,            -- = auth.users.id / JWT sub
    username    text,
    is_admin    boolean     NOT NULL DEFAULT false,
    created_at  timestamptz NOT NULL DEFAULT now()
);
