-- 018 — Nuzlocke: starter-conditional boss squads.
--
-- Purely additive, guarded, idempotent. No data destroyed, no id renumbering:
-- nuzlocke_encounters_logged and nuzlocke_boss_progress reference
-- nuzlocke_timeline_entries(id), which this does not touch.
--
-- ── Why ──
--
-- A rival's team depends on the player's starter. In Platinum, Barry takes the
-- starter that beats yours — pick Piplup and he has Turtwig — and it is NOT
-- only that slot which changes: his other slots differ too, carrying Roselia
-- where another variant has Ponyta or Buizel. One roster per checkpoint
-- therefore shows two out of three players a team they will never fight.
--
-- ── Shape ──
--
-- `starter` on a squad member is the player's starter species that member
-- applies to, or '' for "every starter" — which is the overwhelming majority of
-- rows, since only rival battles vary at all. A run reads
-- `starter = '' OR starter = <the run's starter>`.
--
-- '' rather than NULL deliberately: this column is part of a UNIQUE key, and
-- Postgres treats NULLs as distinct by default, which would silently permit the
-- duplicate rows the key exists to prevent. An empty string compares normally.

BEGIN;

ALTER TABLE nuzlocke_boss_pokemon
    ADD COLUMN IF NOT EXISTS starter TEXT NOT NULL DEFAULT '';

-- Slot 4 can now legitimately exist three times for one boss — once per starter
-- — so the slot alone is no longer unique. It stays unique *within* a starter,
-- which is what actually must not collide.
ALTER TABLE nuzlocke_boss_pokemon
    DROP CONSTRAINT IF EXISTS nuzlocke_boss_pokemon_timeline_entry_id_sort_order_key;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'nuzlocke_boss_pokemon_entry_slot_starter_key'
    ) THEN
        ALTER TABLE nuzlocke_boss_pokemon
            ADD CONSTRAINT nuzlocke_boss_pokemon_entry_slot_starter_key
            UNIQUE (timeline_entry_id, sort_order, starter);
    END IF;
END $$;

-- Which starter this run's player picked. '' means unrecorded — every run
-- created before this migration, and any game whose timeline has no
-- starter-conditional squads at all.
ALTER TABLE nuzlocke_runs
    ADD COLUMN IF NOT EXISTS starter TEXT NOT NULL DEFAULT '';

COMMIT;
