-- 014_add_stats_abilities_moves.sql
--
-- Adds base stats, abilities, and movesets so the iOS Dex species-detail
-- screen (docs/design/hunt-prototype.dc.html / mobile-app.dc.html) has data
-- to show. The 18x18 type chart itself is static client-side data and is
-- deliberately NOT stored here.
--
-- Purely additive (IF NOT EXISTS throughout) and safe to re-run. Nothing here
-- touches user_hunts or any other user-data table.
--
-- Numbering note: migration 013 is in concurrent use on another branch for
-- Nuzlocke tables; this one is 014 to avoid colliding with it.

-- Base stats: six columns on `pokemon`, mirroring PokeAPI's per-stat rows
-- (hp/attack/defense/special-attack/special-defense/speed) flattened onto the
-- species row rather than a child table, because every Pokemon has exactly
-- one of each stat (no per-game or per-form variance to model) and the Dex
-- screen always wants all six together. Nullable with no default: NULL means
-- "not seeded yet", distinct from a real (if unlikely) 0 base stat.
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS hp INTEGER;
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS attack INTEGER;
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS defense INTEGER;
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS special_attack INTEGER;
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS special_defense INTEGER;
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS speed INTEGER;

-- abilities: reference table, natural key = PokeAPI ability slug (e.g.
-- "static"). Seeded in full (~373 rows) and upserted on slug, never
-- truncated -- same stable-key pattern hunt_methods uses (migration 011),
-- for the same reason: pokemon_abilities rows reference abilities.id.
CREATE TABLE IF NOT EXISTS abilities (
    id     SERIAL PRIMARY KEY,
    slug   TEXT NOT NULL UNIQUE, -- PokeAPI name, e.g. "static"
    name   TEXT NOT NULL,        -- display name, e.g. "Static"
    effect TEXT                  -- short effect text (PokeAPI short_effect, en)
);

-- pokemon_abilities: which ability slots a species has. slot follows
-- PokeAPI's numbering (1/2 = regular slots, 3 = hidden ability); is_hidden is
-- stored redundantly for a cheap filter without a slot-number convention
-- leaking into callers. Both FKs CASCADE: this is a reference-to-reference
-- join (pokemon and abilities are both reference data, not user data), so it
-- does not fall under the "never CASCADE" rule -- that rule is about FKs
-- from user data (user_hunts) into reference data.
CREATE TABLE IF NOT EXISTS pokemon_abilities (
    pokemon_id INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    ability_id INTEGER NOT NULL REFERENCES abilities(id) ON DELETE CASCADE,
    slot       INTEGER NOT NULL,
    is_hidden  BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (pokemon_id, slot)
);

-- moves: reference table, natural key = PokeAPI move slug (e.g.
-- "thunderbolt"). Seeded in full (~937 rows) and upserted on slug for the
-- same reason as abilities. `type` is stored as plain text (not an enum/FK)
-- because the type chart is intentionally client-side data -- this column is
-- only ever displayed/filtered against a client-side chart, never joined
-- against a server-side type table.
CREATE TABLE IF NOT EXISTS moves (
    id           SERIAL PRIMARY KEY,
    slug         TEXT NOT NULL UNIQUE,
    name         TEXT NOT NULL,
    type         TEXT NOT NULL,
    damage_class TEXT NOT NULL CHECK (damage_class IN ('physical', 'special', 'status')),
    power        INTEGER, -- NULL for status moves / variable-power moves
    accuracy     INTEGER, -- NULL for moves that bypass the accuracy check
    pp           INTEGER NOT NULL,
    effect       TEXT     -- short effect text (PokeAPI short_effect, en)
);

-- pokemon_moves: the moveset join, scoped per game. Moveset differs by game
-- (and the Dex itself is per-game), so game_id is a required dimension here,
-- not an afterthought -- do not flatten this to one row per (pokemon, move).
-- method is our own vocabulary (level-up/tm/egg/tutor), normalized in the
-- seeder from PokeAPI's move-learn-method names (PokeAPI's "machine" method
-- covers both TMs and TRs/HMs and is normalized to "tm").
-- level is level-up-only and NULL otherwise; the UNIQUE constraint uses NULLS
-- NOT DISTINCT (same technique as method_exceptions, migration 007) so two
-- NULL-level tm rows for the same move/game still collide as duplicates
-- instead of comparing distinct.
-- Only Diamond/Pearl/Platinum (PokeAPI version_group "platinum") and
-- Scarlet/Violet (version_group "scarlet-violet") are seeded so far -- see
-- cmd/seed_moves. Additional games are additive: add a version_group mapping
-- in the seeder and re-run it, no schema change required.
CREATE TABLE IF NOT EXISTS pokemon_moves (
    id         SERIAL PRIMARY KEY,
    pokemon_id INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    move_id    INTEGER NOT NULL REFERENCES moves(id) ON DELETE CASCADE,
    game_id    INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    method     TEXT NOT NULL CHECK (method IN ('level-up', 'tm', 'egg', 'tutor')),
    level      INTEGER,
    UNIQUE NULLS NOT DISTINCT (pokemon_id, move_id, game_id, method, level)
);

CREATE INDEX IF NOT EXISTS idx_pokemon_moves_pokemon_game ON pokemon_moves (pokemon_id, game_id);

-- Default-deny RLS, matching every other table in schema.sql (see the block
-- at the bottom of that file for the rationale). The backend connects as the
-- `postgres` role, which owns these tables and has BYPASSRLS.
ALTER TABLE abilities         ENABLE ROW LEVEL SECURITY;
ALTER TABLE pokemon_abilities ENABLE ROW LEVEL SECURITY;
ALTER TABLE moves             ENABLE ROW LEVEL SECURITY;
ALTER TABLE pokemon_moves     ENABLE ROW LEVEL SECURITY;
