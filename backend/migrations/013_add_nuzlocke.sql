-- 013_add_nuzlocke.sql
--
-- Nuzlocke mode: a locked playthrough of one game's Platinum-seeded route
-- timeline (locations with their wild encounter pools, and boss trainers
-- with their squads/movesets/level caps), plus the user's run over it.
--
-- Reference tables (nuzlocke_timeline_entries / _encounter_pool /
-- _boss_pokemon / _boss_moves) hold the seeded Platinum timeline itself —
-- global, shared by every user. Seeded from seeds/nuzlocke_platinum.json by
-- cmd/seed_nuzlocke, which upserts on (game_id, slug) rather than
-- truncate+reinsert, so a re-seed never orphans a run's FKs the way
-- hunt_methods used to before migrations/011_add_hunt_methods_slug.sql (see
-- that file's history) — timeline_entry_id stays stable across re-seeds.
--
-- User tables (nuzlocke_runs / _encounters_logged / _boss_progress) are the
-- run itself. Every FK from a user table back to the reference timeline is
-- ON DELETE SET NULL, never CASCADE, for the same reason
-- user_hunts.hunt_method_id is SET NULL (schema.sql) — losing/re-slugging a
-- reference row must never delete a user's logged encounter or boss
-- progress out from under them.
--
-- Purely additive: CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS
-- throughout, safe to re-run.

-- ── Reference: the seeded route timeline ───────────────────────────────────

CREATE TABLE IF NOT EXISTS nuzlocke_timeline_entries (
    id          SERIAL PRIMARY KEY,
    game_id     INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    -- Stable key from the seed JSON ("slug"), e.g. 'starter', 'rival1'.
    -- cmd/seed_nuzlocke upserts on (game_id, slug), so this id stays constant
    -- across re-seeds — user tables below reference it directly.
    slug        TEXT NOT NULL,
    kind        TEXT NOT NULL CHECK (kind IN ('location', 'boss')),
    name        TEXT NOT NULL,
    -- A boss and a location are both points on one ordered timeline; this is
    -- the explicit order (the prototype relied on JS array position, which
    -- SQL rows have no equivalent of).
    sort_order  INTEGER NOT NULL,
    place       TEXT,    -- boss only, e.g. 'Oreburgh Gym'
    boss_title  TEXT,    -- boss only, e.g. 'Gym Leader · Rock'
    level_cap   INTEGER, -- boss only
    UNIQUE (game_id, slug)
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_timeline_entries_game_order
    ON nuzlocke_timeline_entries (game_id, sort_order);

-- A location's possible wild encounters (national dex ids).
CREATE TABLE IF NOT EXISTS nuzlocke_encounter_pool (
    id                 SERIAL PRIMARY KEY,
    timeline_entry_id  INTEGER NOT NULL REFERENCES nuzlocke_timeline_entries(id) ON DELETE CASCADE,
    pokemon_id         INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    sort_order         INTEGER NOT NULL,
    UNIQUE (timeline_entry_id, pokemon_id)
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_encounter_pool_entry
    ON nuzlocke_encounter_pool (timeline_entry_id);

-- A boss's squad members.
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

-- One squad member's moveset.
CREATE TABLE IF NOT EXISTS nuzlocke_boss_moves (
    id               SERIAL PRIMARY KEY,
    boss_pokemon_id  INTEGER NOT NULL REFERENCES nuzlocke_boss_pokemon(id) ON DELETE CASCADE,
    name             TEXT NOT NULL,
    type             TEXT NOT NULL,
    power            INTEGER NOT NULL DEFAULT 0, -- 0 = status move, matches the prototype's p:0
    sort_order       INTEGER NOT NULL,
    UNIQUE (boss_pokemon_id, sort_order)
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_boss_moves_boss_pokemon
    ON nuzlocke_boss_moves (boss_pokemon_id);

-- ── User data: a run over the timeline ──────────────────────────────────────

-- user_id is a plain UUID (Supabase Auth sub), same convention as
-- user_hunts/user_games — no FK to a local users table.
CREATE TABLE IF NOT EXISTS nuzlocke_runs (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL,
    -- SET NULL, not CASCADE: a run belongs to its owner, not to the games row.
    game_id             INTEGER REFERENCES games(id) ON DELETE SET NULL,
    -- House rules, stored as columns rather than JSONB: this is a small, fixed
    -- set the prototype already models explicitly (rules.dupes/style/nick),
    -- not an open-ended extension point like user_hunts.hunt_parameters.
    dupes_clause        BOOLEAN NOT NULL DEFAULT TRUE,
    battle_style        TEXT NOT NULL DEFAULT 'set' CHECK (battle_style IN ('set', 'shift')),
    nicknames_required  BOOLEAN NOT NULL DEFAULT TRUE,
    -- 'ended' archives a run; runs are never deleted (PATCH ends, never DELETE).
    status              TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'ended')),
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at            TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_runs_user
    ON nuzlocke_runs (user_id);

-- The logged encounter at one location for one run — the prototype's
-- run.slots[locationKey]. One row per (run, location); a run's party/box/
-- grave are all derived from these rows' status/is_boxed rather than stored
-- separately, same as the prototype derives them from run.slots.
CREATE TABLE IF NOT EXISTS nuzlocke_encounters_logged (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    -- Same-table user data: CASCADE is correct here (deleting a run should
    -- delete its own logged encounters).
    run_id             UUID NOT NULL REFERENCES nuzlocke_runs(id) ON DELETE CASCADE,
    -- Reference data: SET NULL, never CASCADE (see file header).
    timeline_entry_id  INTEGER REFERENCES nuzlocke_timeline_entries(id) ON DELETE SET NULL,
    pokemon_id         INTEGER REFERENCES pokemon(id) ON DELETE SET NULL,
    nickname           TEXT,
    status             TEXT NOT NULL CHECK (status IN ('caught', 'missed', 'fainted', 'ran')),
    nature             TEXT,
    -- Only meaningful when status = 'caught': alive-in-party vs boxed.
    is_boxed           BOOLEAN NOT NULL DEFAULT FALSE,
    -- Computed and stored at log time (species already caught elsewhere in
    -- this run) rather than re-derived on every read, so toggling the dupes
    -- clause mid-run doesn't retroactively relabel earlier catches.
    is_dupe            BOOLEAN NOT NULL DEFAULT FALSE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (run_id, timeline_entry_id)
);

CREATE INDEX IF NOT EXISTS idx_nuzlocke_encounters_logged_run
    ON nuzlocke_encounters_logged (run_id);

-- Beaten toggle per boss per run.
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

-- ── RLS (default-deny, matches every other table — see schema.sql footer) ──

ALTER TABLE nuzlocke_timeline_entries  ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_encounter_pool    ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_boss_pokemon      ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_boss_moves        ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_runs              ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_encounters_logged ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuzlocke_boss_progress     ENABLE ROW LEVEL SECURITY;
