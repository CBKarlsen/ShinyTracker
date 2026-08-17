-- Retarget the team builder from Scarlet/Violet to Pokemon Champions.
-- See docs/superpowers/specs/2026-08-16-champions-correction-design.md
--
-- Safe as a plain ALTER with no backfill: teams and team_members hold zero
-- rows (verified). That will not be true a second time.

-- Champions is generation-ix per PokeAPI's version-group/champions. base_odds
-- is irrelevant here — Champions has no wild encounters and no shiny hunting —
-- but the column is NOT NULL, so a value must be supplied. 4096 is a neutral
-- placeholder that happens to match the table's DEFAULT.
-- Assumes production's games id sequence: id 18 is free there. This is NOT
-- replay-safe against a from-scratch rebuild — SeedGames creates only 16 games,
-- so a rebuilt database gives id 18 to some other title and the DO UPDATE would
-- rename it to Champions instead of failing.
INSERT INTO games (id, title, generation, base_odds)
VALUES (18, 'Pokemon Champions', 9, 4096)
ON CONFLICT (id) DO UPDATE SET title = EXCLUDED.title;

-- games.id is SERIAL; an explicit id leaves the sequence behind, so a later
-- plain INSERT would collide. Push it past the highest id in use.
SELECT setval(pg_get_serial_sequence('games', 'id'), (SELECT max(id) FROM games));

-- Champions replaces EVs and IVs with a single Stat Point pool: 66 total,
-- 32 max per stat. IVs do not exist — every Pokemon calculates as though it
-- had 31 in all stats — so there is nothing to migrate the ivs column into.
ALTER TABLE team_members ADD COLUMN IF NOT EXISTS stat_points JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE team_members DROP COLUMN IF EXISTS evs;
ALTER TABLE team_members DROP COLUMN IF EXISTS ivs;

-- Champions has no Terastallization. Its gimmick is Mega Evolution, and a Mega
-- Stone is a HELD ITEM — item_slug already carries it, so this column has no
-- replacement rather than a renamed one.
ALTER TABLE team_members DROP COLUMN IF EXISTS tera_type;
