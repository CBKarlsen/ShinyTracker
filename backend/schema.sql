-- Execute this script in your Supabase SQL Editor

CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username TEXT UNIQUE NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pokemon (
    id INTEGER PRIMARY KEY, -- PokeAPI ID
    name TEXT NOT NULL,
    sprite_url TEXT,
    types JSONB DEFAULT '[]'::jsonb,
    can_breed BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS games (
    id SERIAL PRIMARY KEY,
    title TEXT NOT NULL,
    generation INTEGER NOT NULL,
    base_odds INTEGER NOT NULL DEFAULT 4096
);

CREATE TABLE IF NOT EXISTS user_games (
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
    has_shiny_charm BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (user_id, game_id)
);

CREATE TABLE IF NOT EXISTS hunt_methods (
    id SERIAL PRIMARY KEY,
    generation INTEGER NOT NULL,
    method_name TEXT NOT NULL,
    avg_time_seconds INTEGER NOT NULL,
    base_rolls INTEGER NOT NULL DEFAULT 1,
    charm_rolls INTEGER NOT NULL DEFAULT 0,
    formula_type TEXT NOT NULL DEFAULT 'static',
    is_recommended BOOLEAN DEFAULT FALSE,
    UNIQUE (generation, method_name)
);

CREATE TABLE IF NOT EXISTS method_rules (
    id SERIAL PRIMARY KEY,
    method_id INTEGER REFERENCES hunt_methods(id) ON DELETE CASCADE,
    generation INTEGER NOT NULL,
    condition TEXT NOT NULL -- e.g. "is_breedable" or "always_true"
);

CREATE TABLE IF NOT EXISTS method_exceptions (
    id SERIAL PRIMARY KEY,
    pokemon_id INTEGER REFERENCES pokemon(id) ON DELETE CASCADE,
    method_id INTEGER REFERENCES hunt_methods(id) ON DELETE CASCADE,
    generation INTEGER NOT NULL,
    include BOOLEAN NOT NULL, -- true to manually add, false to manually exclude
    UNIQUE (pokemon_id, method_id, generation)
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
    generation INTEGER NOT NULL,
    UNIQUE (pokemon_id, method_id, generation)
);

CREATE TABLE IF NOT EXISTS user_hunts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
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
