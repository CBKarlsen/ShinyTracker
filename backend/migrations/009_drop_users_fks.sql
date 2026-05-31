-- 009_drop_users_fks.sql
--
-- Supabase Auth swap — drop FK constraints that point at the old `users` table
-- and remove test data that was created under the old auth scheme.
--
-- user_hunts.user_id and user_games.(user_id, game_id PK) both had an FK to
-- users(id).  Those FKs would prevent inserts from real Supabase UUIDs (which
-- are not in our `users` table).  We drop the constraints, keeping the columns
-- as plain UUIDs; identity is now enforced solely by the Supabase JWT.
--
-- Truncates user-scoped test data and drops the now-obsolete `users` table.
--
-- Idempotent: DROP CONSTRAINT / DROP TABLE use IF EXISTS; TRUNCATE is safe to
-- re-run (it will just be a no-op on already-empty tables).

-- 1. Drop the FK from user_hunts.user_id → users(id)
ALTER TABLE user_hunts
    DROP CONSTRAINT IF EXISTS user_hunts_user_id_fkey;

-- 2. Drop the composite PK on user_games (it included user_id which FK'd users).
--    Re-add the PK without the FK so the table still has a proper primary key.
ALTER TABLE user_games
    DROP CONSTRAINT IF EXISTS user_games_pkey;

ALTER TABLE user_games
    DROP CONSTRAINT IF EXISTS user_games_user_id_fkey;

ALTER TABLE user_games
    ADD PRIMARY KEY (user_id, game_id);

-- 3. Wipe test data tied to the old users table.
TRUNCATE TABLE hunt_phases CASCADE;
TRUNCATE TABLE user_hunts  CASCADE;
TRUNCATE TABLE user_games  CASCADE;

-- 4. Drop the old custom-auth users table.
DROP TABLE IF EXISTS users;
