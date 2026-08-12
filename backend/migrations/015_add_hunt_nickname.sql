-- 015_add_hunt_nickname.sql
--
-- Optional nickname for a catch (e.g. a fresh manual catch or a completed
-- hunt), same idea as nuzlocke_encounters_logged.nickname but for
-- user_hunts. Nullable with no default: NULL means "no nickname set", never
-- coerced to an empty string by the API layer.
--
-- Purely additive, safe to re-run.
ALTER TABLE user_hunts ADD COLUMN IF NOT EXISTS nickname TEXT;
