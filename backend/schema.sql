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

-- Base stats (migration 014): six columns rather than a child table, since
-- every Pokemon has exactly one of each and the Dex screen always wants all
-- six together. Nullable: NULL means "not seeded yet", not a real 0.
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS hp INTEGER;
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS attack INTEGER;
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS defense INTEGER;
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS special_attack INTEGER;
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS special_defense INTEGER;
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS speed INTEGER;

-- abilities / pokemon_abilities / moves / pokemon_moves (migration 014):
-- abilities and moves are reference tables upserted on their PokeAPI slug
-- (same stable-key pattern as hunt_methods, migration 011) rather than
-- truncated, because pokemon_abilities/pokemon_moves reference their ids.
-- The 18x18 type chart itself is intentionally NOT stored here -- it is
-- static data that belongs on the client.
CREATE TABLE IF NOT EXISTS abilities (
    id     SERIAL PRIMARY KEY,
    slug   TEXT NOT NULL UNIQUE, -- PokeAPI name, e.g. "static"
    name   TEXT NOT NULL,        -- display name, e.g. "Static"
    effect TEXT                  -- short effect text (PokeAPI short_effect, en)
);

-- Both FKs CASCADE: pokemon and abilities are both reference data, so this
-- reference-to-reference join does not fall under the "FK from user data
-- must never CASCADE" rule (that rule is about user_hunts -> reference data).
CREATE TABLE IF NOT EXISTS pokemon_abilities (
    pokemon_id INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    ability_id INTEGER NOT NULL REFERENCES abilities(id) ON DELETE CASCADE,
    slot       INTEGER NOT NULL, -- PokeAPI slot numbering: 1/2 = regular, 3 = hidden
    is_hidden  BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (pokemon_id, slot)
);

CREATE TABLE IF NOT EXISTS moves (
    id           SERIAL PRIMARY KEY,
    slug         TEXT NOT NULL UNIQUE,
    name         TEXT NOT NULL,
    type         TEXT NOT NULL, -- plain text; joined only against the client-side type chart
    damage_class TEXT NOT NULL CHECK (damage_class IN ('physical', 'special', 'status')),
    power        INTEGER, -- NULL for status moves / variable-power moves
    accuracy     INTEGER, -- NULL for moves that bypass the accuracy check
    pp           INTEGER NOT NULL,
    effect       TEXT     -- short effect text (PokeAPI short_effect, en)
);

-- pokemon_moves: moveset differs by game, so game_id is a required dimension
-- (do not flatten to one row per pokemon+move). method is normalized in the
-- seeder from PokeAPI's move-learn-method vocabulary ("machine" -> "tm").
-- Only Diamond/Pearl/Platinum (version_group "platinum") and Scarlet/Violet
-- (version_group "scarlet-violet") are seeded so far -- see cmd/seed_moves.
-- Adding another game is additive: no schema change required.
CREATE TABLE IF NOT EXISTS pokemon_moves (
    id         SERIAL PRIMARY KEY,
    pokemon_id INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    move_id    INTEGER NOT NULL REFERENCES moves(id) ON DELETE CASCADE,
    game_id    INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    method     TEXT NOT NULL CHECK (method IN ('level-up', 'tm', 'egg', 'tutor')),
    level      INTEGER, -- level-up only; NULL for tm/egg/tutor
    UNIQUE NULLS NOT DISTINCT (pokemon_id, move_id, game_id, method, level)
);

CREATE INDEX IF NOT EXISTS idx_pokemon_moves_pokemon_game ON pokemon_moves (pokemon_id, game_id);

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
    -- Stable key from hunt_methods.json ("id" field). cmd/seed upserts on this
    -- so `id` stays constant across re-seeds; user_hunts.hunt_method_id
    -- depends on that (see migrations/011_add_hunt_methods_slug.sql).
    slug TEXT NOT NULL UNIQUE,
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
-- is re-applied (upserted) every run. hunt_methods itself is no longer
-- truncated each seed (ids are stable via the slug column), so this table
-- persists across runs too rather than being cascade-cleared.
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

-- Per-game, per-version wild encounter locations (Gen 2-7, seeded from PokeAPI
-- by cmd/seed_locations). Distinct from pokemon_game_encounter, which stores the
-- derived encounter KIND; this stores the raw WHERE facts.
--
-- The version column exists because the games table groups versions (versionMap
-- maps diamond/pearl/platinum onto one row). That grouping is correct for odds
-- and methods but wrong for locations: Platinum rebuilt much of Sinnoh's
-- encounter tables and D/P exclusives differ from each other.
CREATE TABLE IF NOT EXISTS pokemon_locations (
    id             SERIAL PRIMARY KEY,
    pokemon_id     INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    game_id        INTEGER NOT NULL REFERENCES games(id)   ON DELETE CASCADE,
    version        TEXT    NOT NULL,   -- PokeAPI version name, e.g. 'platinum'
    area           TEXT    NOT NULL,   -- PokeAPI slug, e.g. 'route-210-area'
    terrain        TEXT    NOT NULL,   -- from services.terrainForMethod
    pokeapi_method TEXT    NOT NULL,   -- 'walk', 'surf', 'old-rod', ...
    min_level      INTEGER,
    max_level      INTEGER,
    chance         INTEGER,            -- percent, per encounter slot
    conditions     TEXT[]              -- 'time-night', 'season-spring', ...
);

CREATE INDEX IF NOT EXISTS idx_pokemon_locations_pokemon_game
    ON pokemon_locations (pokemon_id, game_id);
-- Reverse lookup (area -> species). Unused today; the nuzlocke slice needs it.
CREATE INDEX IF NOT EXISTS idx_pokemon_locations_game_area
    ON pokemon_locations (game_id, area);

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
    -- ON DELETE SET NULL, emphatically NOT CASCADE. This column used to be
    -- declared CASCADE, which would have been silent user data loss: cmd/seed
    -- prunes hunt_methods rows that disappear from hunt_methods.json, and under
    -- CASCADE each prune would delete every hunt using that method. A hunt is
    -- the user's data; a method is reference data, and losing the second must
    -- never destroy the first. Losing the link degrades the hunt to "no method"
    -- (loadHuntsForUser LEFT JOINs), which is recoverable; losing the hunt is not.
    --
    -- NOTE: this constraint does not exist on production. It was declared here
    -- but never applied, which is why re-seeds silently orphaned every hunt for
    -- months without anything catching it. Applying it requires first clearing
    -- the existing dangling values. Until then this file overstates what the
    -- database actually enforces.
    hunt_method_id INTEGER REFERENCES hunt_methods(id) ON DELETE SET NULL,
    custom_method_name TEXT,
    -- Optional, user-supplied name for the catch (migrations/015). NULL means
    -- "no nickname set" — the API layer never coerces this to "": PATCHing an
    -- empty string is how a nickname is cleared, and the UPDATE folds it to NULL.
    nickname TEXT,
    acquisition_type VARCHAR NOT NULL DEFAULT 'HUNTED' CHECK (acquisition_type IN ('HUNTED', 'EVOLVED', 'MANUAL_OVERRIDE', 'TRADED', 'PHASE')),
    encounter_count INTEGER NOT NULL DEFAULT 0,
    phase_count INTEGER NOT NULL DEFAULT 0,
    total_time_seconds INTEGER NOT NULL DEFAULT 0,
    -- One-way latch (migration 012): flips true the first time a PATCH sends
    -- total_time_seconds explicitly. Once true, the server never derives
    -- total_time_seconds for this hunt again — see UpdateHuntHandler /
    -- calc.DecideTotalTime. Keeps a hunt migrated to a client that owns its
    -- own elapsed time from being double-counted by a later PATCH that omits
    -- the field (e.g. the web frontend).
    client_owns_time BOOLEAN NOT NULL DEFAULT false,
    status TEXT NOT NULL DEFAULT 'active', -- 'active' or 'completed'
    hunt_parameters JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_method_xor CHECK (NOT (hunt_method_id IS NOT NULL AND custom_method_name IS NOT NULL))
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Nuzlocke mode (migrations/013_add_nuzlocke.sql)
--
-- Reference: the seeded Platinum route timeline (global, shared by every
-- user). Seeded from seeds/nuzlocke_platinum.json by cmd/seed_nuzlocke,
-- upserted on (game_id, slug) so ids stay stable across re-seeds — the same
-- pattern hunt_methods uses via its slug column (migrations/011).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS nuzlocke_timeline_entries (
    id          SERIAL PRIMARY KEY,
    game_id     INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    slug        TEXT NOT NULL,
    kind        TEXT NOT NULL CHECK (kind IN ('location', 'boss')),
    name        TEXT NOT NULL,
    sort_order  INTEGER NOT NULL,
    place       TEXT,
    boss_title  TEXT,
    level_cap   INTEGER,
    UNIQUE (game_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_timeline_entries_game_order
    ON nuzlocke_timeline_entries (game_id, sort_order);

CREATE TABLE IF NOT EXISTS nuzlocke_encounter_pool (
    id                 SERIAL PRIMARY KEY,
    timeline_entry_id  INTEGER NOT NULL REFERENCES nuzlocke_timeline_entries(id) ON DELETE CASCADE,
    pokemon_id         INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    sort_order         INTEGER NOT NULL,
    UNIQUE (timeline_entry_id, pokemon_id)
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_encounter_pool_entry
    ON nuzlocke_encounter_pool (timeline_entry_id);

CREATE TABLE IF NOT EXISTS nuzlocke_boss_pokemon (
    id                 SERIAL PRIMARY KEY,
    timeline_entry_id  INTEGER NOT NULL REFERENCES nuzlocke_timeline_entries(id) ON DELETE CASCADE,
    pokemon_id         INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    level              INTEGER NOT NULL,
    ability            TEXT NOT NULL,
    sort_order         INTEGER NOT NULL,
    UNIQUE (timeline_entry_id, sort_order)
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_boss_pokemon_entry
    ON nuzlocke_boss_pokemon (timeline_entry_id);

CREATE TABLE IF NOT EXISTS nuzlocke_boss_moves (
    id               SERIAL PRIMARY KEY,
    boss_pokemon_id  INTEGER NOT NULL REFERENCES nuzlocke_boss_pokemon(id) ON DELETE CASCADE,
    name             TEXT NOT NULL,
    type             TEXT NOT NULL,
    power            INTEGER NOT NULL DEFAULT 0,
    sort_order       INTEGER NOT NULL,
    UNIQUE (boss_pokemon_id, sort_order)
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_boss_moves_boss_pokemon
    ON nuzlocke_boss_moves (boss_pokemon_id);

-- User data: a run over the timeline. FKs back to the reference tables above
-- are ON DELETE SET NULL, never CASCADE — same reasoning as
-- user_hunts.hunt_method_id (see its comment above): losing/re-slugging a
-- reference row must never delete a user's run, logged encounter, or boss
-- progress.
CREATE TABLE IF NOT EXISTS nuzlocke_runs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL,
    game_id             INTEGER REFERENCES games(id) ON DELETE SET NULL,
    dupes_clause        BOOLEAN NOT NULL DEFAULT TRUE,
    battle_style        TEXT NOT NULL DEFAULT 'set' CHECK (battle_style IN ('set', 'shift')),
    nicknames_required  BOOLEAN NOT NULL DEFAULT TRUE,
    status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'ended')),
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at            TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_runs_user
    ON nuzlocke_runs (user_id);

CREATE TABLE IF NOT EXISTS nuzlocke_encounters_logged (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id             UUID NOT NULL REFERENCES nuzlocke_runs(id) ON DELETE CASCADE,
    timeline_entry_id  INTEGER REFERENCES nuzlocke_timeline_entries(id) ON DELETE SET NULL,
    pokemon_id         INTEGER REFERENCES pokemon(id) ON DELETE SET NULL,
    nickname           TEXT,
    status             TEXT NOT NULL CHECK (status IN ('caught', 'missed', 'fainted', 'ran')),
    nature             TEXT,
    is_boxed           BOOLEAN NOT NULL DEFAULT FALSE,
    is_dupe            BOOLEAN NOT NULL DEFAULT FALSE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (run_id, timeline_entry_id)
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_encounters_logged_run
    ON nuzlocke_encounters_logged (run_id);

CREATE TABLE IF NOT EXISTS nuzlocke_boss_progress (
    id                 SERIAL PRIMARY KEY,
    run_id             UUID NOT NULL REFERENCES nuzlocke_runs(id) ON DELETE CASCADE,
    timeline_entry_id  INTEGER REFERENCES nuzlocke_timeline_entries(id) ON DELETE SET NULL,
    beaten             BOOLEAN NOT NULL DEFAULT TRUE,
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (run_id, timeline_entry_id)
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_boss_progress_run
    ON nuzlocke_boss_progress (run_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- Row Level Security (default-deny)
--
-- Supabase auto-exposes every public table over its PostgREST API. Enabling RLS
-- with NO policies denies the anon/authenticated roles all access, closing that
-- hole. The backend connects as the `postgres` role, which owns these tables and
-- has BYPASSRLS, so the Go API and seed/migrate tools are unaffected. FORCE is
-- intentionally omitted so the owner stays exempt as a second safety layer.
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE pokemon                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE games                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE pokemon_availability    ENABLE ROW LEVEL SECURITY;
ALTER TABLE pokemon_game_encounter  ENABLE ROW LEVEL SECURITY;
ALTER TABLE shiny_locks             ENABLE ROW LEVEL SECURITY;
ALTER TABLE hunt_methods            ENABLE ROW LEVEL SECURITY;
ALTER TABLE method_games            ENABLE ROW LEVEL SECURITY;
ALTER TABLE method_availability     ENABLE ROW LEVEL SECURITY;
ALTER TABLE method_exceptions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE pokemon_locations       ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles                ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_games              ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_hunts              ENABLE ROW LEVEL SECURITY;
ALTER TABLE hunt_phases             ENABLE ROW LEVEL SECURITY;
ALTER TABLE abilities               ENABLE ROW LEVEL SECURITY;
ALTER TABLE pokemon_abilities       ENABLE ROW LEVEL SECURITY;
ALTER TABLE moves                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE pokemon_moves           ENABLE ROW LEVEL SECURITY;

ALTER TABLE nuzlocke_timeline_entries  ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_encounter_pool    ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_boss_pokemon      ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_boss_moves        ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_runs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_encounters_logged ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_boss_progress     ENABLE ROW LEVEL SECURITY;
