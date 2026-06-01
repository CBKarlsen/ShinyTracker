-- gen3_corrections.sql
-- Generation 3 — Ruby/Sapphire/Emerald (game_id=3), FireRed/LeafGreen (game_id=4).
-- Generated 2026-05-31 from a stable Gen 3 snapshot. DO NOT auto-run: review first (see gen3_report.md).
--
-- KEYING NOTE: keyed on the natural triple (pokemon_id, game_id, method_id / kind / terrain),
-- NOT the surrogate id (which renumbers on every reseed). All INSERTs are guarded with ON CONFLICT
-- DO NOTHING or NOT EXISTS, so re-running is safe (0 rows if already present).
--
-- Gen 3 method IDs (verified):
--   178 = Soft Reset  (requires_kind='static')
--   179 = Run Away    (requires_kind='wild')  ← mislabel of Random Encounter, see Section A
--   165 = Random Encounter (requires_kind='wild', charm_rolls=0) ← used by FRLG, correct for Gen 3
--
-- ============================================================================
-- (A) METHOD MISLABEL — RSE: "Run Away" (method_id=179) should be "Random Encounter"
--
--     All 152 RSE wild-encounter rows use method_id=179 ("Run Away") instead of a
--     Random Encounter method. The fix is to remap the method_games row for game_id=3
--     from method_id=179 to method_id=165 ("Random Encounter", charm_rolls=0, which is
--     the appropriate Gen-3/no-Shiny-Charm variant already used by FRLG).
--
--     Effect on method_availability: method_availability rows referencing method_id=179
--     must also be migrated to method_id=165.
--
--     ⚠ DURABLE FIX BELONGS IN THE SEED PIPELINE. method_availability is regenerated
--     on every reseed, so the UPDATE below will be overwritten unless the seed source
--     is also corrected. Fix the seed source (CSV / seeds JSON) to emit method_id=165
--     for RSE wild encounters, and remove 179 from method_games for game_id=3.
-- ============================================================================

BEGIN;

-- A1. Remap method_games: swap Run Away (179) → Random Encounter (165) for RSE.
--     Guard: only run if 179 is still present and 165 is not yet present for game_id=3.
INSERT INTO method_games (game_id, method_id)
SELECT 3, 165
WHERE EXISTS (SELECT 1 FROM method_games WHERE game_id = 3 AND method_id = 179)
  AND NOT EXISTS (SELECT 1 FROM method_games WHERE game_id = 3 AND method_id = 165);
-- Expect: 1 row inserted (0 if already present / already fixed).

-- A2. Migrate method_availability rows from Run Away (179) → Random Encounter (165) for RSE.
--     Idempotent: inserts new rows only if not already present, then removes the old ones.
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT pokemon_id, 165, game_id
FROM method_availability
WHERE game_id = 3 AND method_id = 179
ON CONFLICT DO NOTHING;
-- Expect: up to 152 rows inserted (0 if already migrated).

DELETE FROM method_availability
WHERE game_id = 3 AND method_id = 179
  AND EXISTS (
    SELECT 1 FROM method_availability ma2
    WHERE ma2.pokemon_id = method_availability.pokemon_id
      AND ma2.game_id = 3
      AND ma2.method_id = 165
  );
-- Expect: up to 152 rows deleted (0 if already removed).

-- A3. Remove Run Away from method_games for RSE once migration is complete.
DELETE FROM method_games
WHERE game_id = 3 AND method_id = 179
  AND NOT EXISTS (
    SELECT 1 FROM method_availability WHERE game_id = 3 AND method_id = 179
  );
-- Expect: 1 row deleted (0 if already removed or migration not yet complete).

COMMIT;


-- ============================================================================
-- (B) COVERAGE GAP — RSE: Regirock, Regice, Registeel, Latias, Latios
--
--     Five RSE-catchable legendaries have NO pokemon_game_encounter row for game_id=3
--     and NO method_availability row. All are static/roaming encounters in RSE and are
--     NOT shiny-locked in Gen 3 (locking began Gen 5).
--
--     Sources:
--       Regirock:  https://bulbapedia.bulbagarden.net/wiki/Regirock_(Pok%C3%A9mon)#Game_locations
--       Regice:    https://bulbapedia.bulbagarden.net/wiki/Regice_(Pok%C3%A9mon)#Game_locations
--       Registeel: https://bulbapedia.bulbagarden.net/wiki/Registeel_(Pok%C3%A9mon)#Game_locations
--       Latias:    https://bulbapedia.bulbagarden.net/wiki/Latias_(Pok%C3%A9mon)#Game_locations
--       Latios:    https://bulbapedia.bulbagarden.net/wiki/Latios_(Pok%C3%A9mon)#Game_locations
-- ============================================================================

BEGIN;

-- B1. Static encounter rows for RSE legendaries. PK is (pokemon_id, game_id, kind, terrain).
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 3, 'static', 'none'
FROM (VALUES
  (377), -- regirock
  (378), -- regice
  (379), -- registeel
  (380), -- latias  (version-dependent roamer; 'static' is the correct kind for SR bucket)
  (381)  -- latios  (version-dependent roamer)
) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 5 rows inserted (0 if already present).

-- B2. Soft Reset method rows for RSE legendaries (method_id=178, game_id=3).
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 3
FROM (VALUES (377),(378),(379),(380),(381)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 3
);
-- Expect: up to 5 rows inserted (0 if re-run).

COMMIT;


-- ============================================================================
-- (C) COVERAGE GAP — FRLG: Raikou, Entei, Suicune (roaming legendaries)
--
--     Three FRLG roaming legendaries (which one appears depends on starter choice)
--     have NO pokemon_game_encounter row for game_id=4 and NO method_availability row.
--     All are shiny-huntable via Soft Reset in FRLG. NOT shiny-locked in Gen 3 (R3).
--
--     Sources:
--       Raikou:  https://bulbapedia.bulbagarden.net/wiki/Raikou_(Pok%C3%A9mon)#Game_locations
--       Entei:   https://bulbapedia.bulbagarden.net/wiki/Entei_(Pok%C3%A9mon)#Game_locations
--       Suicune: https://bulbapedia.bulbagarden.net/wiki/Suicune_(Pok%C3%A9mon)#Game_locations
-- ============================================================================

BEGIN;

-- C1. Static encounter rows for FRLG roaming beasts.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 4, 'static', 'none'
FROM (VALUES
  (243), -- raikou
  (244), -- entei
  (245)  -- suicune
) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 3 rows inserted (0 if already present).

-- C2. Soft Reset method rows for FRLG roaming beasts (method_id=178, game_id=4).
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 4
FROM (VALUES (243),(244),(245)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 4
);
-- Expect: up to 3 rows inserted (0 if re-run).

COMMIT;


-- ============================================================================
-- (D) COVERAGE GAP — RSE starters/fossils/gifts: missing Soft Reset
--
--     NEEDS REVIEW — lower confidence. These Pokémon are received as gifts or from
--     fossils in RSE (no wild encounter exists), but currently have only 'wild/other'
--     and 'egg/none' encounter rows driving a "Run Away" (wild) assignment.
--     The 'wild/other' rows appear to be seeding artefacts (Masuda derivation pass).
--
--     Action required before running:
--       1. Confirm 'wild/other' rows are artefacts and should be removed.
--       2. Confirm each is a pure-gift/fossil encounter in RSE (no wild route encounter).
--
--     Pokémon: Treecko(252) Torchic(255) Mudkip(258) — starters (gift from Prof. Birch)
--              Lileep(345) Anorith(347) — fossils (Root/Claw Fossil)
--              Castform(351) — gift (Weather Institute)
--              Beldum(374)   — gift (Steven's house post-E4)
-- ============================================================================

-- D1. Static encounter rows for RSE gifts/fossils.
-- ⚠ NEEDS REVIEW: confirm wild/other rows are artefacts before adding static rows.
/*
BEGIN;
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 3, 'static', 'none'
FROM (VALUES
  (252), -- treecko  (starter)
  (255), -- torchic  (starter)
  (258), -- mudkip   (starter)
  (345), -- lileep   (fossil)
  (347), -- anorith  (fossil)
  (351), -- castform (gift)
  (374)  -- beldum   (gift)
) AS v(pid)
ON CONFLICT DO NOTHING;
COMMIT;
*/

-- D2. Soft Reset method rows for RSE gifts/fossils (method_id=178, game_id=3).
-- ⚠ NEEDS REVIEW: only run after confirming gift-only status and adding static encounter rows.
/*
BEGIN;
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 3
FROM (VALUES (252),(255),(258),(345),(347),(351),(374)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 3
);
COMMIT;
*/


-- ============================================================================
-- (E) COVERAGE GAP — FRLG starters/fossils: missing Soft Reset
--
--     NEEDS REVIEW — lower confidence. Same pattern as Section D but for FRLG.
--     Currently assigned Random Encounter (165) via 'wild/other' encounter rows,
--     but are received as gifts or from fossils — no wild encounter exists in FRLG.
--
--     Pokémon: Bulbasaur(1) Charmander(4) Squirtle(7) — starters (gift from Oak)
--              Omanyte(138) Kabuto(140) — fossils (Dome/Helix Fossil)
-- ============================================================================

-- E1. Static encounter rows for FRLG gifts/fossils.
-- ⚠ NEEDS REVIEW: confirm wild/other rows are artefacts before adding static rows.
/*
BEGIN;
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 4, 'static', 'none'
FROM (VALUES
  (1),   -- bulbasaur (starter)
  (4),   -- charmander (starter)
  (7),   -- squirtle  (starter)
  (138), -- omanyte   (fossil)
  (140)  -- kabuto    (fossil)
) AS v(pid)
ON CONFLICT DO NOTHING;
COMMIT;
*/

-- E2. Soft Reset method rows for FRLG gifts/fossils (method_id=178, game_id=4).
-- ⚠ NEEDS REVIEW: only run after confirming gift-only status and adding static encounter rows.
/*
BEGIN;
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 4
FROM (VALUES (1),(4),(7),(138),(140)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 4
);
COMMIT;
*/


-- ============================================================================
-- (F) NEEDS REVIEW — FRLG event legendaries: Lugia, Ho-Oh
--
--     Lugia(249) and Ho-Oh(250) are obtained via Navel Rock (Nintendo event ticket).
--     They are technically shiny-huntable via Soft Reset if you have the event item.
--     NOT shiny-locked in Gen 3. Policy decision: include as huntable or exclude as event?
--
--     Deoxys(386) (Birth Island) intentionally excluded — event-only, considered unobtainable
--     for standard hunts. Jirachi(385), Mew(151), Celebi(251) correctly absent.
-- ============================================================================

-- F1. NEEDS REVIEW — uncomment only if policy decision is to include Lugia/Ho-Oh.
/*
BEGIN;
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
VALUES
  (249, 4, 'static', 'none'), -- lugia (Navel Rock)
  (250, 4, 'static', 'none')  -- ho-oh (Navel Rock)
ON CONFLICT DO NOTHING;

INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 4
FROM (VALUES (249),(250)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 4
);
COMMIT;
*/
