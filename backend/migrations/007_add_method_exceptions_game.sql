-- Add per-game scoping to method_exceptions so a manual include/exclude can
-- target a single game; game_id NULL = every game the method is mapped to.
-- Idempotent; safe to re-run. Does not touch user_hunts.

-- 1. Nullable game_id (FK to games, cascade with the game).
ALTER TABLE method_exceptions
    ADD COLUMN IF NOT EXISTS game_id INTEGER REFERENCES games(id) ON DELETE CASCADE;

-- 2. Replace the old (pokemon_id, method_id) unique with a three-column
--    NULLS NOT DISTINCT unique (PG15+), so rows with a NULL game_id still dedupe
--    instead of being treated as all-distinct.
ALTER TABLE method_exceptions DROP CONSTRAINT IF EXISTS method_exceptions_pokemon_id_method_id_key;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'method_exceptions_pokemon_method_game_key'
    ) THEN
        ALTER TABLE method_exceptions
            ADD CONSTRAINT method_exceptions_pokemon_method_game_key
            UNIQUE NULLS NOT DISTINCT (pokemon_id, method_id, game_id);
    END IF;
END $$;
