-- Competitive team builder, sub-project 1. Scarlet/Violet only.
-- See docs/superpowers/specs/2026-08-16-sv-team-builder-design.md

-- Held items. Seeded from PokeAPI by cmd/seed_items.
-- No effect data on purpose: Choice Band's x1.5 belongs to the damage calculator,
-- where it can be tested against a reference. An unused column now is a guess the
-- calculator would have to unpick.
CREATE TABLE IF NOT EXISTS items (
    slug        TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    sprite_url  TEXT,
    description TEXT
);

CREATE TABLE IF NOT EXISTS teams (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    -- Always 17 (Scarlet/Violet) today. Stored anyway: adding it later means a
    -- migration over live rows with no correct default.
    game_id    INTEGER NOT NULL REFERENCES games(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_teams_user ON teams (user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS team_members (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id      UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    slot         SMALLINT NOT NULL CHECK (slot BETWEEN 1 AND 6),
    pokemon_id   INTEGER NOT NULL REFERENCES pokemon(id),
    nickname     TEXT,
    nature       TEXT NOT NULL,
    ability_slug TEXT NOT NULL,
    item_slug    TEXT REFERENCES items(slug),
    tera_type    TEXT,
    level        SMALLINT NOT NULL DEFAULT 50 CHECK (level BETWEEN 1 AND 100),
    -- Read and written as a whole spread, never queried per stat — same reasoning
    -- that put hunt_parameters in JSONB. The 508 total cannot be expressed as a
    -- cheap CHECK over JSONB, so it is enforced in the handler and the client.
    evs          JSONB NOT NULL DEFAULT '{}'::jsonb,
    ivs          JSONB NOT NULL DEFAULT '{}'::jsonb,
    moves        TEXT[] NOT NULL DEFAULT '{}',
    UNIQUE (team_id, slot)
);

CREATE INDEX IF NOT EXISTS idx_team_members_team ON team_members (team_id, slot);

ALTER TABLE items        ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams        ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_members ENABLE ROW LEVEL SECURITY;
