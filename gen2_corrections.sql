-- gen2_corrections.sql
-- Generation 2 — Gold/Silver/Crystal (game_id=2).
-- Generated 2026-05-31 from a stable Gen 2 snapshot. DO NOT auto-run: review first (see gen2_report.md).
--
-- AUDIT RESULT: 10 confirmed mislabels (static/gift Pokémon assigned Random Encounter via wild/other),
-- 3 coverage gaps (legendary beasts with no encounter or method row), and 15 NEEDS REVIEW rows
-- (left as commented blocks below).
--
-- KEYING: keyed on the natural triple (pokemon_id, game_id, method_id) and (pokemon_id, game_id, kind, terrain),
-- NOT surrogate ids. All statements are idempotent (ON CONFLICT DO NOTHING or NOT EXISTS guards).
--
-- METHOD IDs (Gen 2, game_id=2):
--   165 = Random Encounter (requires_kind=wild)
--   178 = Soft Reset    (requires_kind=static)
--
-- ⚠ DURABLE FIX BELONGS IN THE SEED PIPELINE. method_availability is derived from encounter data
-- and is regenerated on every re-seed. Manual INSERTs/UPDATEs will be overwritten on the next seed run.
-- Prefer fixing the encounter records in the seed source (CSV / seeds JSON) so they survive.
-- The SQL below is provided for review / one-off application only.

-- ============================================================================
-- (A) CONFIRMED MISLABELS — 10 static/gift Pokémon coded as wild/other + Random Encounter
--
--     Fix: (1) update their pokemon_game_encounter row from wild/other → static/none
--          (2) replace their method_availability RE row with SR
--
--     The ON CONFLICT DO NOTHING / NOT EXISTS guards make re-running safe.
-- ============================================================================

BEGIN;

-- A1. Update encounter kind: wild/other → static/none for confirmed static/gift Pokémon
--     (pokemon_id, game_id, kind='wild', terrain='other') → kind='static', terrain='none'
--
--     Pokémon: Chikorita(152), Cyndaquil(155), Totodile(158)
--              Eevee(133), Togepi(175), Snorlax(143), Sudowoodo(185),
--              Lapras(131), Tyrogue(236), Aerodactyl(142)
--     Source: Bulbapedia — each confirmed as gift/static encounter in GSC.

UPDATE pokemon_game_encounter
SET kind = 'static', terrain = 'none'
WHERE game_id = 2
  AND kind = 'wild'
  AND terrain = 'other'
  AND pokemon_id IN (152, 155, 158, 133, 175, 143, 185, 131, 236, 142);
-- Chikorita(152): gift starter from Prof. Elm — https://bulbapedia.bulbagarden.net/wiki/Chikorita_(Pok%C3%A9mon)
-- Cyndaquil(155): gift starter from Prof. Elm — https://bulbapedia.bulbagarden.net/wiki/Cyndaquil_(Pok%C3%A9mon)
-- Totodile(158):  gift starter from Prof. Elm — https://bulbapedia.bulbagarden.net/wiki/Totodile_(Pok%C3%A9mon)
-- Eevee(133):     gift from Bill in Goldenrod City — https://bulbapedia.bulbagarden.net/wiki/Eevee_(Pok%C3%A9mon)
-- Togepi(175):    gift egg from Mr. Pokémon (shiny on hatch) — https://bulbapedia.bulbagarden.net/wiki/Togepi_(Pok%C3%A9mon)
-- Snorlax(143):   static blocker, Vermilion area — https://bulbapedia.bulbagarden.net/wiki/Snorlax_(Pok%C3%A9mon)
-- Sudowoodo(185): static blocker, Route 36 — https://bulbapedia.bulbagarden.net/wiki/Sudowoodo_(Pok%C3%A9mon)
-- Lapras(131):    weekly gift in Union Cave basement — https://bulbapedia.bulbagarden.net/wiki/Lapras_(Pok%C3%A9mon)
-- Tyrogue(236):   gift from Karate King, Mt. Mortar — https://bulbapedia.bulbagarden.net/wiki/Tyrogue_(Pok%C3%A9mon)
-- Aerodactyl(142): fossil revival, Pewter Museum — https://bulbapedia.bulbagarden.net/wiki/Aerodactyl_(Pok%C3%A9mon)

-- A2. Remove the incorrect Random Encounter (method_id=165) rows for these 10 Pokémon
DELETE FROM method_availability
WHERE game_id = 2
  AND method_id = 165
  AND pokemon_id IN (152, 155, 158, 133, 175, 143, 185, 131, 236, 142);

-- A3. Insert the correct Soft Reset (method_id=178) rows for these 10 Pokémon
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 2
FROM (VALUES (152),(155),(158),(133),(175),(143),(185),(131),(236),(142)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 2
);
-- Expect: up to 10 rows inserted (0 if re-run after first application).

-- ============================================================================
-- (B) COVERAGE GAP — Legendary beasts with no encounter or method row
--
--     Raikou(243), Entei(244), Suicune(245) are completely absent from both
--     pokemon_game_encounter and method_availability for game_id=2.
--     In GSC, their shiny DV is determined at spawn (Burned Tower event), making
--     Soft Reset the canonical hunt method.
--     Source: https://bulbapedia.bulbagarden.net/wiki/Raikou_(Pok%C3%A9mon)
--             https://bulbapedia.bulbagarden.net/wiki/Entei_(Pok%C3%A9mon)
--             https://bulbapedia.bulbagarden.net/wiki/Suicune_(Pok%C3%A9mon)
--
--     ⚠ Same seed-pipeline caveat as gen4_corrections.sql: these will be overwritten on re-seed.
-- ============================================================================

-- B1. Add static encounter rows for the three legendary beasts
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 2, 'static', 'none'
FROM (VALUES (243),(244),(245)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Raikou(243), Entei(244), Suicune(245)
-- Expect: up to 3 rows inserted (0 if already present).

-- B2. Add Soft Reset method rows for the three legendary beasts
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 2
FROM (VALUES (243),(244),(245)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 2
);
-- Expect: up to 3 rows inserted (0 if re-run).

COMMIT;

-- ============================================================================
-- (C) NEEDS REVIEW — not applied; review before acting
--
--     These Pokémon have wild/other as their only Gen 2 encounter + Random Encounter.
--     Most are likely correct (headbutt trees, indoor/cave), but some may warrant
--     reclassification. Uncomment individual blocks after manual verification.
-- ============================================================================

-- NEEDS REVIEW: Shuckle (#213) — gift from man in Cianwood City.
-- High confidence this should be Soft Reset (one-time gift, like Tyrogue).
-- Uncomment after verifying community consensus.
-- BEGIN;
-- UPDATE pokemon_game_encounter SET kind='static', terrain='none'
--   WHERE game_id=2 AND pokemon_id=213 AND kind='wild' AND terrain='other';
-- DELETE FROM method_availability WHERE game_id=2 AND pokemon_id=213 AND method_id=165;
-- INSERT INTO method_availability (pokemon_id, method_id, game_id)
--   SELECT 213, 178, 2 WHERE NOT EXISTS (
--     SELECT 1 FROM method_availability WHERE pokemon_id=213 AND method_id=178 AND game_id=2);
-- -- Source: https://bulbapedia.bulbagarden.net/wiki/Shuckle_(Pok%C3%A9mon)
-- COMMIT;

-- NEEDS REVIEW: Igglybuff (#174) — wild/other only in Gen 2.
-- Not a clearly documented standard wild encounter in GSC. Verify before acting.
-- BEGIN;
-- -- If confirmed as wild encounter, no change needed.
-- -- If confirmed as gift/static, apply same pattern as section A above.
-- -- Source: https://bulbapedia.bulbagarden.net/wiki/Igglybuff_(Pok%C3%A9mon)
-- COMMIT;

-- NEEDS REVIEW: Porygon (#137) — Game Corner prize in Celadon City (GSC).
-- Shiny is possible on receipt but is not traditionally SR-able (requires coins per attempt).
-- Community may treat as RE (odds apply) or SR. No change proposed until consensus confirmed.
-- Source: https://bulbapedia.bulbagarden.net/wiki/Porygon_(Pok%C3%A9mon)

-- NEEDS REVIEW: The following are believed correct as Random Encounter (wild/other = headbutt/cave/indoor)
-- but should be spot-checked:
--   Magneton(82) — Power Plant (Kanto, indoor wild)
--   Electrode(101) — Power Plant (Kanto, indoor wild)
--   Exeggcute(102) — Safari Zone (Kanto)
--   Xatu(178) — Ruins of Alph / National Park area
--   Aipom(190) — headbutt trees
--   Pineco(204) — headbutt trees
--   Heracross(214) — headbutt trees
--   Pichu(172) — Mt. Mortar / wild area
--   Cleffa(173) — Mt. Moon (Kanto) wild
--   Smoochum(238) — Ice Path
--   Elekid(239) — Power Plant area
--   Magby(240) — Cinnabar Island area
-- No corrections proposed for these without further confirmation.

-- ============================================================================
-- (D) NOT ADDED — event mythicals correctly absent
--     Mew(151) and Celebi(251) are shiny-unobtainable in Gen 2 (event-only, no legitimate
--     in-game shiny encounter). No method_availability rows for game 2. Correct as-is.
--     Source: https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
-- ============================================================================
