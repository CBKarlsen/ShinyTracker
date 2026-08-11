-- 011_add_hunt_methods_slug.sql
--
-- hunt_methods had no stable identifier: ids came from a SERIAL sequence and
-- cmd/seed TRUNCATEd + reinserted the table on every run, so ids drifted on
-- every re-seed. hunt_methods.json already carries a stable per-row string
-- key (its "id" field), but it was only used in-process (seedMethods'
-- methodIDMap) and never persisted, so nothing could upsert on it. cmd/seed
-- now upserts hunt_methods on that key instead of truncating, so this column
-- is what makes ids stable going forward.
--
-- Every existing hunt_methods row today has an id from whatever the last
-- reseed happened to assign, and every user_hunts.hunt_method_id in
-- production was already found pointing at a since-deleted id (11/11 hunts
-- checked when this was diagnosed) — there is no FK enforcing that column on
-- production to have caught it. Nothing currently depends on today's ids
-- being meaningful, so on first apply we truncate hunt_methods (cascading
-- into method_games and method_availability, both already fully rebuilt by
-- every cmd/seed run) instead of trying to backfill slugs onto rows that
-- don't reliably map back to hunt_methods.json entries. The next cmd/seed
-- run repopulates everything with slugs and, from then on, stable ids.
-- This TRUNCATE is safe ONLY because that data was already broken — do not
-- reuse this pattern for a migration touching a table with valid production
-- references.
--
-- Idempotent: the truncate only fires once (guarded on the slug column not
-- existing yet), and every statement after it is a safe no-op to re-run.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'hunt_methods'
          AND column_name = 'slug'
    ) THEN
        TRUNCATE TABLE hunt_methods CASCADE;
    END IF;
END $$;

ALTER TABLE hunt_methods ADD COLUMN IF NOT EXISTS slug TEXT;

-- Safe to make NOT NULL immediately: the table is empty right after the
-- truncate above, and every row cmd/seed inserts afterward always sets slug.
ALTER TABLE hunt_methods ALTER COLUMN slug SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS hunt_methods_slug_key ON hunt_methods (slug);
