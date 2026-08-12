-- 017 — Nuzlocke: per-version timelines, and damage class on boss moves.
--
-- Purely additive: ADD COLUMN IF NOT EXISTS plus one constraint swap, all
-- guarded, so re-running is a no-op. No data is destroyed and no id changes,
-- which matters because nuzlocke_encounters_logged and nuzlocke_boss_progress
-- reference nuzlocke_timeline_entries(id) (see 013's header).
--
-- ── Why `version` ──
--
-- games.id 5 is the single row "Diamond/Pearl/Platinum", and the three
-- versions genuinely disagree about both halves of a Nuzlocke:
--
--   * Encounter tables differ. pokemon_locations already models this — it has
--     3,996 platinum rows against 3,905 each for diamond and pearl, keyed by
--     its own `version` column.
--   * Trainers differ, and not slightly. In Platinum Fantina is the THIRD gym;
--     in D/P she is the fifth. Gardenia leads with Turtwig/Cherrim/Roserade in
--     Platinum and Cherubi/Turtwig in D/P. Cyrus gains a Celestic Ruins battle
--     and his final fight moves to the Distortion World. Cynthia is *weaker*
--     in Platinum (Garchomp 62, Togekiss) than in D/P (Garchomp 66, Gastrodon).
--
-- Seeding one timeline against game_id 5 therefore serves Diamond and Pearl
-- players a Platinum run and calls it theirs. The column is scoped to the
-- Nuzlocke tables on purpose: splitting the games row itself would ripple
-- through hunts, availability and the odds engine, all of which are correct
-- treating the three versions as one game.
--
-- `version` reuses pokemon_locations' vocabulary verbatim ('platinum',
-- 'diamond', 'pearl', …) so a timeline stop and the encounter table it is
-- derived from can be joined on equal terms.
--
-- ── Why `damage_class` ──
--
-- nuzlocke_boss_moves.power alone cannot answer "is this move a threat".
-- moves.power is NULL for every variable-power damaging move — Grass Knot,
-- Metal Burst, Dragon Rage, Electro Ball, Counter, Endeavor, Fissure and ~20
-- others — so a `power > 0` test reads Gardenia's Grass Knot and Byron's
-- Bastiodon's Metal Burst as harmless. That is precisely backwards for the
-- client's party-coverage warning, which exists to say what will hurt you.
-- damage_class is the honest key, and moves.damage_class already carries it.

BEGIN;

-- ── nuzlocke_timeline_entries.version ──

ALTER TABLE nuzlocke_timeline_entries
    ADD COLUMN IF NOT EXISTS version TEXT NOT NULL DEFAULT 'platinum';

-- The 13 pre-existing rows were extracted from the design prototype and are
-- Platinum-shaped, so the DEFAULT backfills them correctly. Drop the default
-- afterwards: every future insert names its version explicitly, and a silent
-- 'platinum' on a Johto timeline would be worse than a NOT NULL violation.
ALTER TABLE nuzlocke_timeline_entries ALTER COLUMN version DROP DEFAULT;

-- Swap UNIQUE (game_id, slug) for UNIQUE (game_id, version, slug): the same
-- slug ('gym3') must be able to mean Fantina in Platinum and Maylene in
-- Diamond. cmd/seed_nuzlocke upserts on this key, so it changes with it.
ALTER TABLE nuzlocke_timeline_entries
    DROP CONSTRAINT IF EXISTS nuzlocke_timeline_entries_game_id_slug_key;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'nuzlocke_timeline_entries_game_version_slug_key'
    ) THEN
        ALTER TABLE nuzlocke_timeline_entries
            ADD CONSTRAINT nuzlocke_timeline_entries_game_version_slug_key
            UNIQUE (game_id, version, slug);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_nuzlocke_timeline_game_version
    ON nuzlocke_timeline_entries (game_id, version, sort_order);

-- ── nuzlocke_runs.version ──

-- Which version's timeline this run follows. Fixed at creation: a run that
-- switched version mid-playthrough would have its logged encounters pointing
-- at timeline entries that are no longer on its route.
ALTER TABLE nuzlocke_runs
    ADD COLUMN IF NOT EXISTS version TEXT NOT NULL DEFAULT 'platinum';

ALTER TABLE nuzlocke_runs ALTER COLUMN version DROP DEFAULT;

-- ── nuzlocke_boss_moves.damage_class ──

-- 'status' is the safe default for the backfill: it under-claims (a move
-- wrongly marked status is left out of a coverage warning) rather than
-- over-claims (inventing a threat that isn't there). cmd/seed_nuzlocke fills
-- the real value from moves.damage_class on the next re-seed.
ALTER TABLE nuzlocke_boss_moves
    ADD COLUMN IF NOT EXISTS damage_class TEXT NOT NULL DEFAULT 'status';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'nuzlocke_boss_moves_damage_class_check'
    ) THEN
        ALTER TABLE nuzlocke_boss_moves
            ADD CONSTRAINT nuzlocke_boss_moves_damage_class_check
            CHECK (damage_class IN ('physical', 'special', 'status'));
    END IF;
END $$;

COMMIT;
