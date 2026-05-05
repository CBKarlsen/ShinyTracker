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
    types JSONB DEFAULT '[]'::jsonb
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

CREATE TABLE IF NOT EXISTS encounters (
    id SERIAL PRIMARY KEY,
    pokemon_id INTEGER REFERENCES pokemon(id) ON DELETE CASCADE,
    game_id INTEGER REFERENCES games(id) ON DELETE CASCADE,
    method_name TEXT NOT NULL,
    avg_time_seconds INTEGER NOT NULL,
    base_rolls INTEGER NOT NULL DEFAULT 1,
    charm_rolls INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS user_hunts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    pokemon_id INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    encounter_id INTEGER REFERENCES encounters(id) ON DELETE CASCADE,
    acquisition_type VARCHAR NOT NULL DEFAULT 'HUNTED' CHECK (acquisition_type IN ('HUNTED', 'EVOLVED', 'MANUAL_OVERRIDE', 'TRADED')),
    encounter_count INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'active', -- 'active' or 'completed'
    hunt_parameters JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
