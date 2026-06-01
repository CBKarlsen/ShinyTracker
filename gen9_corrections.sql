-- gen9_corrections.sql
-- Generation 9 — Scarlet/Violet (game_id=17).
-- Generated 2026-05-31 from a stable Gen 9 snapshot. DO NOT auto-run: review first (see gen9_report.md).
--
-- RESULT OF AUDIT: zero method MISLABELS. Issues are in the shiny_locks table and coverage gaps.
-- Three sections below:
--   (A) DELETE false-positive shiny-lock rows  — HIGH priority
--   (B) INSERT missing shiny-lock rows          — HIGH priority
--   (C) INSERT coverage-gap encounter + method rows — MEDIUM/LOW priority
--
-- KEYING NOTE: keyed on natural keys (pokemon_id, game_id) for shiny_locks and
-- (pokemon_id, method_id, game_id) for method_availability. NOT the surrogate id.
-- All DELETEs and INSERTs are idempotent / safe to re-run.
--
-- Gen 9 method IDs: Random Encounter=161, Masuda=162, Mass Outbreak=167,
--                   Sandwich Hunting=170, Soft Reset=178  (game_id=17).

-- ============================================================================
-- (A) SHINY-LOCK FALSE POSITIVES — DELETE.
--
--     These three Pokémon are in shiny_locks for game 17 but are NOT shiny-locked
--     in Scarlet/Violet. They are huntable wild Pokémon with correctly assigned
--     method rows (Random Encounter, Mass Outbreak, Sandwich Hunting).
--     The hunt method rows are CORRECT and should NOT be touched.
--     Source: https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
--
--     archaludon  (1018) — Indigo Disk wild Pokémon, NOT locked
--     hydrapple   (1019) — Indigo Disk wild Pokémon, NOT locked
--     gouging-fire(1020) — Paradox Pokémon, NOT locked
-- ============================================================================

BEGIN;

DELETE FROM shiny_locks
WHERE game_id = 17
  AND pokemon_id IN (1018, 1019, 1020);
-- Expect: 3 rows deleted (0 if already removed).

-- ============================================================================
-- (B) MISSING SHINY-LOCK ENTRIES — INSERT.
--
--     These four Pokémon are shiny-locked in the DLC but absent from shiny_locks.
--     None has any method_availability row (no huntable-method conflict), but the
--     missing lock record means they appear huntable in any UI lock-check.
--     Source: https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
--
--     okidogi    (1014) — Teal Mask, static encounter, shiny-locked
--     munkidori  (1015) — Teal Mask, static encounter, shiny-locked
--     fezandipiti(1016) — Teal Mask, static encounter, shiny-locked
--     terapagos  (1024) — Indigo Disk, static encounter, shiny-locked
-- ============================================================================

INSERT INTO shiny_locks (pokemon_id, game_id)
SELECT v.pid, 17
FROM (VALUES (1014),(1015),(1016),(1024)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM shiny_locks sl
  WHERE sl.pokemon_id = v.pid AND sl.game_id = 17
);
-- Expect: up to 4 rows inserted (0 if re-run).

COMMIT;

-- ============================================================================
-- (C) COVERAGE GAPS — static legendaries with no encounter or hunt method.
--
--     IMPORTANT: the gap is at BOTH the encounter level AND the method level.
--     None of these six Pokémon has a pokemon_game_encounter row for game 17,
--     so method_availability cannot be derived. Both tables need backfilling.
--
--     ⚠ DURABLE FIX BELONGS IN THE SEED PIPELINE. method_availability is
--     regenerated on every re-seed. The SQL below is idempotent for a one-off
--     stable DB; add these rows to the seed source (CSV / seeds JSON) for
--     permanence. Confirm intent before running.
--
--     Sub-section C1: Treasures of Ruin — static shrine encounters, NOT locked.
--       wo-chien (1001), chien-pao (1002), ting-lu (1003), chi-yu (1004)
--       Correct method: Soft Reset (id=178).
--       Source: https://bulbapedia.bulbagarden.net/wiki/Treasures_of_Ruin
--
--     Sub-section C2: Tera Raid exclusives — obtainable only via special raids, NOT locked.
--       walking-wake (1009), iron-leaves (1010)
--       No dedicated Tera Raid method exists in the DB. Soft Reset is used as the
--       closest approximation (requires_kind='static'). NEEDS REVIEW if a Tera Raid
--       method is added later.
--       Source: https://bulbapedia.bulbagarden.net/wiki/Walking_Wake
--               https://bulbapedia.bulbagarden.net/wiki/Iron_Leaves
-- ============================================================================

BEGIN;

-- C1a. Static encounter rows for Treasures of Ruin.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 17, 'static', 'none'
FROM (VALUES (1001),(1002),(1003),(1004)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 4 rows inserted (0 if already present).

-- C1b. Soft Reset method rows for Treasures of Ruin.
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 17
FROM (VALUES (1001),(1002),(1003),(1004)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 17
);
-- Expect: up to 4 rows inserted (0 if re-run).

-- C2a. Encounter rows for Walking Wake and Iron Leaves.
--      Using 'static'/'none' as the closest available kind (raid not a separate kind in schema).
--      NEEDS REVIEW: if a 'raid' kind or Tera Raid method is added, migrate these.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 17, 'static', 'none'
FROM (VALUES (1009),(1010)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 2 rows inserted (0 if already present).

-- C2b. Soft Reset method rows for Walking Wake and Iron Leaves.
--      NEEDS REVIEW — see note above.
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 17
FROM (VALUES (1009),(1010)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 17
);
-- Expect: up to 2 rows inserted (0 if re-run).

COMMIT;

-- Note: Koraidon(1007), Miraidon(1008), Ogerpon(1017), Pecharunt(1025) are correctly
-- in shiny_locks with 0 method rows — intentionally not touched.
-- Note: Bloodmoon Ursaluna is absent from the pokemon table entirely; not addressed here.
