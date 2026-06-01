-- gen8_corrections.sql
-- Generation 8 — Sword/Shield (game_id=14), Brilliant Diamond/Shining Pearl (game_id=15),
--               Legends: Arceus (game_id=16).
-- Generated 2026-05-31 from a stable Gen 8 snapshot. DO NOT auto-run: review first (see gen8_report.md).
--
-- KEYING NOTE: keyed on natural triples (pokemon_id, game_id, method_id) or
-- (pokemon_id, game_id) for shiny_locks. INSERTs guarded with NOT EXISTS / ON CONFLICT DO NOTHING.
--
-- Gen 8 method IDs (verified):
--   171 = Dynamax Adventures (game 14)
--   172 = Masuda Method (games 14, 15)
--   176 = KO Method (game 14 — mislabeled, see Section A)
--   177 = Mass Outbreak (game 16)
--   178 = Soft Reset (games 14, 15)
--   179 = Run Away (games 14, 15)
--
-- ============================================================================
-- SECTION A — METHOD MISLABEL: KO Method in SwSh (game 14)
--
--   ISSUE: hunt_methods id=176 "KO Method" is wired as the wild-encounter
--   method for all 562 SwSh wild Pokémon.  KO Method is a Legends: Arceus
--   mechanic, not a Sword/Shield one.  The SwSh equivalent is the "Shiny Mark"
--   / "Brilliant Aura" encounter boost (or simply Random Encounter at base odds).
--
--   RESOLUTION OPTIONS (choose one before running anything here):
--     Option A1: Rename hunt_methods id=176 from "KO Method" to the correct
--                SwSh label (e.g. "Shiny Mark" or "Random Encounter").
--                Effect: all 562 rows update automatically — no method_availability
--                changes needed.
--     Option A2: Add a new hunt_methods row for SwSh wild encounters, migrate
--                the 562 method_availability rows to the new id, then decide
--                whether to repurpose or delete id=176.
--
--   ⚠ NEEDS-REVIEW — do NOT run until the team decides on the label/approach.
--   The SQL below illustrates Option A1 only (simplest). It is commented out.
--
-- -- A1. Rename KO Method to the agreed SwSh wild-encounter label:
-- UPDATE hunt_methods
-- SET method_name = 'Shiny Mark'   -- replace with chosen label
-- WHERE id = 176 AND method_name = 'KO Method';
-- -- Expect: 1 row updated. Verify with: SELECT * FROM hunt_methods WHERE id = 176;
-- ============================================================================


-- ============================================================================
-- SECTION B — SHINY_LOCKS CORRECTIONS (safe, small, targeted)
-- ============================================================================

BEGIN;

-- B1. Remove incorrect shiny locks for BDSP (game 15).
--     Dialga(483) and Palkia(484) are NOT shiny-locked in BDSP — they are
--     Soft-Resettable at Spear Pillar.
--     Source: https://bulbapedia.bulbagarden.net/wiki/Shiny_Pokémon#Brilliant_Diamond_and_Shining_Pearl
DELETE FROM shiny_locks
WHERE game_id = 15 AND pokemon_id IN (483, 484);
-- Expect: 2 rows deleted (Dialga, Palkia).
-- Re-run safe: deletes 0 rows if already removed.

-- B2. Remove incorrect shiny lock for Giratina in BDSP (game 15).
--     Giratina(487) is obtainable via Turnback Cave static encounter and is
--     NOT shiny-locked. It already has a Soft Reset row in method_availability(15)
--     — the shiny_locks entry directly contradicts that.
DELETE FROM shiny_locks
WHERE game_id = 15 AND pokemon_id = 487;
-- Expect: 1 row deleted (Giratina-altered).

-- B3. Add missing PLA (game 16) shiny locks.
--     ALL legendaries and mythicals in Legends: Arceus are shiny-locked.
--     Current shiny_locks(16) only has: Dialga(483), Palkia(484), Arceus(493), Enamorus(905).
--     Missing: Uxie(480), Mesprit(481), Azelf(482), Heatran(485), Regigigas(486),
--              Giratina-altered(487), Cresselia(488), Manaphy(490), Darkrai(491),
--              Shaymin-land(492).
--     Source: https://bulbapedia.bulbagarden.net/wiki/Shiny_Pokémon#Legends:_Arceus
--     Note: None of these have encounter or method rows in game 16, so the
--     practical effect on hunt availability is nil — this is a data-hygiene fix.
INSERT INTO shiny_locks (pokemon_id, game_id)
SELECT v.pid, 16
FROM (VALUES (480),(481),(482),(485),(486),(487),(488),(490),(491),(492)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 10 rows inserted (0 if re-run or already present).
-- Pokémon: Uxie, Mesprit, Azelf, Heatran, Regigigas, Giratina-altered,
--          Cresselia, Manaphy, Darkrai, Shaymin-land.

COMMIT;


-- ============================================================================
-- SECTION C — COVERAGE GAPS (NEEDS-REVIEW blocks)
--
--   These are missing rows rather than wrong rows. Because method_availability
--   is regenerated on every re-seed, SQL-only fixes will be overwritten.
--   Prefer fixing the seed source (CSV / seeds JSON). The SQL below is
--   provided for one-off reference only.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- C1. SwSh (game 14): Regieleki and Regidrago missing Soft Reset.
--     Both are obtainable via static encounter in Crown Tundra DLC and are
--     NOT shiny-locked. Soft Reset (method_id=178) is the correct method.
--     Source: https://bulbapedia.bulbagarden.net/wiki/Regieleki / Regidrago
--
--     ⚠ NEEDS-REVIEW: confirm they have pokemon_game_encounter rows for game 14
--     first (at audit time they had 0 encounter rows — add encounter row before
--     method row).
--
-- -- C1a. Add static encounter rows for Regieleki(894) and Regidrago(895) in SwSh:
-- INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
-- SELECT v.pid, 14, 'static', 'none'
-- FROM (VALUES (894),(895)) AS v(pid)
-- ON CONFLICT DO NOTHING;
--
-- -- C1b. Add Soft Reset method rows:
-- INSERT INTO method_availability (pokemon_id, method_id, game_id)
-- SELECT v.pid, 178, 14
-- FROM (VALUES (894),(895)) AS v(pid)
-- WHERE NOT EXISTS (
--   SELECT 1 FROM method_availability ma
--   WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 14
-- );
-- -- Expect: 2 rows inserted.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- C2. BDSP (game 15): Dialga(483) and Palkia(484) missing encounter + Soft Reset.
--     After Section B1 removes their wrong shiny_locks entries, they need:
--       - static encounter rows in pokemon_game_encounter
--       - Soft Reset method rows in method_availability
--     Both are at Spear Pillar and are not shiny-locked in BDSP.
--     Source: https://bulbapedia.bulbagarden.net/wiki/Spear_Pillar
--
--     ⚠ NEEDS-REVIEW: part of the larger BDSP full-reseed effort (Section D).
--     Do not apply in isolation — wait for the full BDSP seed.
--
-- -- C2a. Add static encounter rows:
-- INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
-- SELECT v.pid, 15, 'static', 'none'
-- FROM (VALUES (483),(484)) AS v(pid)
-- ON CONFLICT DO NOTHING;
--
-- -- C2b. Add Soft Reset method rows:
-- INSERT INTO method_availability (pokemon_id, method_id, game_id)
-- SELECT v.pid, 178, 15
-- FROM (VALUES (483),(484)) AS v(pid)
-- WHERE NOT EXISTS (
--   SELECT 1 FROM method_availability ma
--   WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 15
-- );
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- C3. BDSP (game 15): Full reseed required.
--
--     At audit time game 15 has only 9 Pokémon with encounter rows (8 egg + 1
--     static) out of ~300+ expected. This is a seeding gap, not a SQL-patch
--     problem. The following changes belong in the seed pipeline:
--
--       1. Add all BDSP wild encounters (grass, surf, fishing) to
--          pokemon_game_encounter with appropriate kind/terrain.
--       2. Register Poké Radar (method_id=163) in method_games for game 15.
--       3. Seed method_availability for:
--            - Random Encounter (wild grass/surf/fishing)
--            - Poké Radar (wild grass, post-game)
--            - Soft Reset (static legendaries — see also C2)
--       4. Remove Run Away (method_id=179) from method_games(15) if BDSP does
--          not have an overworld Run Away shiny mechanic (under review).
--
--     ⚠ NO SQL PROVIDED HERE — bulk encounter data must come from the seed
--     source (PokeAPI / CSV). See gen8_report.md Finding F6.
-- ----------------------------------------------------------------------------

-- ============================================================================
-- End of gen8_corrections.sql
-- ============================================================================
