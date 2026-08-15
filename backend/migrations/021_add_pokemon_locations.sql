-- Additive: creates pokemon_locations and its indexes. Safe to re-run.
-- Was cmd/migrate_locations, which spelled the same DDL as a Go string slice.

CREATE TABLE IF NOT EXISTS pokemon_locations (
    id             SERIAL PRIMARY KEY,
    pokemon_id     INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    game_id        INTEGER NOT NULL REFERENCES games(id)   ON DELETE CASCADE,
    version        TEXT    NOT NULL,
    area           TEXT    NOT NULL,
    terrain        TEXT    NOT NULL,
    pokeapi_method TEXT    NOT NULL,
    min_level      INTEGER,
    max_level      INTEGER,
    chance         INTEGER,
    conditions     TEXT[]
);

CREATE INDEX IF NOT EXISTS idx_pokemon_locations_pokemon_game
    ON pokemon_locations (pokemon_id, game_id);

CREATE INDEX IF NOT EXISTS idx_pokemon_locations_game_area
    ON pokemon_locations (game_id, area);

ALTER TABLE pokemon_locations ENABLE ROW LEVEL SECURITY;
