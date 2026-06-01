-- Execute this script in your Supabase SQL Editor
-- Note: the former `users` table (custom-auth era) was dropped by
-- migrations/009_drop_users_fks.sql. Identity is now Supabase Auth only.

CREATE TABLE IF NOT EXISTS pokemon (
    id INTEGER PRIMARY KEY, -- PokeAPI ID
    name TEXT NOT NULL,
    sprite_url TEXT,
    types JSONB DEFAULT '[]'::jsonb,
    can_breed BOOLEAN NOT NULL DEFAULT TRUE,
    is_legendary BOOLEAN NOT NULL DEFAULT FALSE,
    is_mythical BOOLEAN NOT NULL DEFAULT FALSE
);

-- evolves_from_id: single-parent pre-evolution pointer (PokeAPI evolves_from_species).
-- Walking this upward yields a Pokemon's full pre-evolution line. Used for
-- "hunt a pre-evolution, then evolve" route suggestions.
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS evolves_from_id INTEGER REFERENCES pokemon(id);

CREATE TABLE IF NOT EXISTS games (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    generation INTEGER NOT NULL,
    base_odds INTEGER NOT NULL DEFAULT 4096
);

-- user_games: user_id is a plain UUID (Supabase Auth sub); no FK to a local
-- users table since that table was dropped in migration 009.
CREATE TABLE IF NOT EXISTS user_games (
    user_id UUID,
    game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
    has_shiny_charm BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (user_id, game_id)
);

CREATE TABLE IF NOT EXISTS hunt_methods (
    id SERIAL PRIMARY KEY,
    method_name TEXT NOT NULL,
    avg_time_seconds INTEGER NOT NULL,
    base_rolls INTEGER NOT NULL DEFAULT 1,
    charm_rolls INTEGER NOT NULL DEFAULT 0,
    formula_type TEXT NOT NULL DEFAULT 'static',
    -- The encounter kind this method consumes. A method is only valid for a
    -- Pokemon in a game when that Pokemon has a matching pokemon_game_encounter row.
    requires_kind TEXT NOT NULL DEFAULT 'wild' CHECK (requires_kind IN ('wild','static','raid','egg')),
    -- Optional terrain restriction for wild methods (grass/surf/fishing/other).
    -- NULL means the method matches any terrain.
    requires_terrain TEXT
);

CREATE TABLE IF NOT EXISTS method_games (
    method_id INTEGER REFERENCES hunt_methods(id) ON DELETE CASCADE,
    game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
    PRIMARY KEY (method_id, game_id)
);

-- pokemon_availability: legal availability per game (which games a Pokemon can be obtained in).
CREATE TABLE IF NOT EXISTS pokemon_availability (
    pokemon_id INTEGER REFERENCES pokemon(id) ON DELETE CASCADE,
    game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
    PRIMARY KEY (pokemon_id, game_id)
);

-- shiny_locks: per-game shiny locks (Pokemon that cannot be encountered shiny
-- in a given game — box legendaries, gift starters, Meltan/Melmetal, etc.).
-- "Locked everywhere" is DERIVED (locked in every game it is available in),
-- not stored. Seeded from seeds/shiny_locks.json (idempotent).
CREATE TABLE IF NOT EXISTS shiny_locks (
    pokemon_id INTEGER REFERENCES pokemon(id) ON DELETE CASCADE,
    game_id    INTEGER REFERENCES games(id)   ON DELETE CASCADE,
    PRIMARY KEY (pokemon_id, game_id)
);

-- pokemon_game_encounter: the encounter kind(s) a Pokemon has in a game.
-- wild/egg are auto-derived (PokeAPI encounters / breedable egg groups);
-- static/raid are curated via seeds/legendary_encounters.json.
-- terrain refines `wild` rows (grass/surf/fishing/other) so terrain-specific
-- methods (e.g. Poké Radar = grass, Chain Fishing = fishing) only attach to the
-- right Pokemon; non-wild kinds use 'none'. method_availability is computed by
-- joining this to hunt_methods on requires_kind (+ optional requires_terrain).
CREATE TABLE IF NOT EXISTS pokemon_game_encounter (
    pokemon_id INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('wild','static','raid','egg')),
    terrain TEXT NOT NULL DEFAULT 'none' CHECK (terrain IN ('grass','surf','fishing','other','none','friend_safari')),
    PRIMARY KEY (pokemon_id, game_id, kind, terrain)
);

-- Manual corrections applied on top of the derived method_availability.
-- game_id scopes the exception to one game; NULL = every game the method is
-- mapped to (via method_games). Seeded from seeds/method_exceptions.json, which
-- is re-applied each run because this table is cascade-truncated with hunt_methods.
CREATE TABLE IF NOT EXISTS method_exceptions (
    id SERIAL PRIMARY KEY,
    pokemon_id INTEGER REFERENCES pokemon(id) ON DELETE CASCADE,
    method_id INTEGER REFERENCES hunt_methods(id) ON DELETE CASCADE,
    game_id INTEGER REFERENCES games(id) ON DELETE CASCADE, -- NULL = all games this method is mapped to
    include BOOLEAN NOT NULL, -- true to manually add, false to manually exclude
    UNIQUE NULLS NOT DISTINCT (pokemon_id, method_id, game_id)
);

-- We don't define method_availability as a true SQL view that evaluates JS strings here,
-- because SQL can't dynamically evaluate text rules like "is_breedable" natively easily 
-- without custom functions. Instead, we'll implement the "view" resolution logic in Go backend,
-- OR we implement a simplified SQL view if the conditions are simple enough.
-- For now, we will create a materialized view or regular table that we refresh in the seeder.
CREATE TABLE IF NOT EXISTS method_availability (
    id SERIAL PRIMARY KEY,
    pokemon_id INTEGER REFERENCES pokemon(id) ON DELETE CASCADE,
    method_id INTEGER REFERENCES hunt_methods(id) ON DELETE CASCADE,
    game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
    UNIQUE (pokemon_id, method_id, game_id)
);

-- profiles: Supabase Auth user metadata, keyed by the Supabase user UUID.
-- id mirrors auth.users.id (the JWT sub claim from Supabase access tokens).
-- No hard FK to auth.users is declared here so this DDL can be applied with
-- the app's existing tooling without cross-schema permission issues.
-- Populated during the Supabase Auth swap step; the existing users table is
-- NOT touched here.
CREATE TABLE IF NOT EXISTS profiles (
    id          uuid        PRIMARY KEY,            -- = auth.users.id / JWT sub
    username    text,
    is_admin    boolean     NOT NULL DEFAULT false,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- user_hunts: user_id is a plain UUID (Supabase Auth sub); no FK to a local
-- users table since that table was dropped in migration 009.
CREATE TABLE IF NOT EXISTS user_hunts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    pokemon_id INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
    hunt_method_id INTEGER REFERENCES hunt_methods(id) ON DELETE CASCADE,
    custom_method_name TEXT,
    acquisition_type VARCHAR NOT NULL DEFAULT 'HUNTED' CHECK (acquisition_type IN ('HUNTED', 'EVOLVED', 'MANUAL_OVERRIDE', 'TRADED')),
    encounter_count INTEGER NOT NULL DEFAULT 0,
    phase_count INTEGER NOT NULL DEFAULT 0,
    total_time_seconds INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active', -- 'active' or 'completed'
    hunt_parameters JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_method_xor CHECK (NOT (hunt_method_id IS NOT NULL AND custom_method_name IS NOT NULL))
);
