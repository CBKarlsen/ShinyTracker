-- Add a terrain dimension to wild encounters so terrain-specific methods
-- (Poké Radar = grass, Chain Fishing = fishing) only attach to the right
-- Pokemon. Idempotent; safe to re-run. Does not touch user_hunts.

-- 1. terrain column on pokemon_game_encounter (default 'none' for non-wild kinds
--    and any pre-existing rows; the re-sync repopulates wild rows per terrain).
ALTER TABLE pokemon_game_encounter
    ADD COLUMN IF NOT EXISTS terrain TEXT NOT NULL DEFAULT 'none';

-- Constrain terrain values (added separately so re-runs don't error).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'pokemon_game_encounter_terrain_check'
    ) THEN
        ALTER TABLE pokemon_game_encounter
            ADD CONSTRAINT pokemon_game_encounter_terrain_check
            CHECK (terrain IN ('grass','surf','fishing','other','none'));
    END IF;
END $$;

-- 2. Widen the primary key to include terrain so a Pokemon can have multiple
--    wild terrains (grass + surf + fishing) in one game. Drop-then-add is
--    idempotent: re-running rebuilds the same composite PK harmlessly.
ALTER TABLE pokemon_game_encounter DROP CONSTRAINT IF EXISTS pokemon_game_encounter_pkey;
ALTER TABLE pokemon_game_encounter
    ADD PRIMARY KEY (pokemon_id, game_id, kind, terrain);

-- 3. Optional terrain restriction on methods (NULL = any terrain).
ALTER TABLE hunt_methods
    ADD COLUMN IF NOT EXISTS requires_terrain TEXT;
