-- legendary_gap_corrections.sql
-- One-off idempotent SQL to apply the legendary static-encounter coverage gaps
-- to the LIVE DB immediately, without waiting for a full re-seed.
--
-- Background: method_availability is derived from pokemon_game_encounter on every
-- re-seed. The DURABLE fix is already applied to backend/seeds/legendary_encounters.json.
-- This file provides the equivalent direct-DB patch for immediate effect.
--
-- Keying: (pokemon_id, game_id, kind, terrain) for pokemon_game_encounter (natural PK).
--         method_availability uses NOT EXISTS guard keyed on (pokemon_id, method_id, game_id).
--         method_id for "Soft Reset" is resolved by name — never hardcoded — because
--         serial IDs renumber on every reseed.
--
-- DO NOT run a full reseed after applying this patch until the seed source is confirmed
-- to cover the same rows (it now does, on this branch). A reseed will regenerate
-- method_availability deterministically from the updated seed source.
--
-- Sections:
--   A  Sword/Shield (Crown Tundra) static legendaries
--   B  BDSP / Ramanas Park static legendaries
--   C  HGSS static legendaries (Kanto birds, Mewtwo, beasts, Lati@s)
--   D  Black 2/White 2 static legendaries (Regis, lake trio, Heatran, Regigigas,
--      Cresselia, Lati@s)
--   E  Black/White + Black 2/White 2 — Kyurem (Giant Chasm)

BEGIN;

-- ============================================================================
-- A  Sword/Shield (game title = 'Sword/Shield', Crown Tundra DLC)
--    Pokémon: 894 Regieleki, 895 Regidrago, 377 Regirock, 378 Regice,
--             379 Registeel, 486 Regigigas, 638 Cobalion, 639 Terrakion,
--             640 Virizion.
--    All are static encounters; none are shiny-locked in SwSh.
--    Source: https://bulbapedia.bulbagarden.net/wiki/Crown_Tundra
-- ============================================================================

-- A1. Static encounter rows for SwSh.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, g.id, 'static', 'none'
FROM (VALUES (894),(895),(377),(378),(379),(486),(638),(639),(640)) AS v(pid)
CROSS JOIN games g
WHERE g.title = 'Sword/Shield'
ON CONFLICT DO NOTHING;
-- Expect: up to 9 rows inserted (0 on re-run or if already present).

-- A2. Soft Reset method rows for SwSh.
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, hm.id, g.id
FROM (VALUES (894),(895),(377),(378),(379),(486),(638),(639),(640)) AS v(pid)
CROSS JOIN hunt_methods hm
CROSS JOIN games g
WHERE hm.method_name = 'Soft Reset'
  AND g.title = 'Sword/Shield'
  AND NOT EXISTS (
    SELECT 1 FROM method_availability ma
    WHERE ma.pokemon_id = v.pid
      AND ma.method_id = hm.id
      AND ma.game_id = g.id)
  AND NOT EXISTS (
    SELECT 1 FROM shiny_locks sl
    WHERE sl.pokemon_id = v.pid AND sl.game_id = g.id);
-- Expect: up to 9 rows inserted. Shiny-lock guard prevents accidental insertion
-- if a pokemon is later found to be locked.

-- ============================================================================
-- B  BDSP / Ramanas Park (game title = 'Brilliant Diamond/Shining Pearl')
--    Pokémon: 144 Articuno, 145 Zapdos, 146 Moltres, 150 Mewtwo,
--             243 Raikou, 244 Entei, 245 Suicune,
--             249 Lugia, 250 Ho-Oh,
--             380 Latias, 381 Latios,
--             382 Kyogre, 383 Groudon, 384 Rayquaza.
--    All available via Ramanas Park static encounters; none shiny-locked in BDSP.
--    Source: https://bulbapedia.bulbagarden.net/wiki/Ramanas_Park
-- ============================================================================

-- B1. Static encounter rows for BDSP.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, g.id, 'static', 'none'
FROM (VALUES (144),(145),(146),(150),(243),(244),(245),(249),(250),(380),(381),(382),(383),(384)) AS v(pid)
CROSS JOIN games g
WHERE g.title = 'Brilliant Diamond/Shining Pearl'
ON CONFLICT DO NOTHING;
-- Expect: up to 14 rows inserted.

-- B2. Soft Reset method rows for BDSP.
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, hm.id, g.id
FROM (VALUES (144),(145),(146),(150),(243),(244),(245),(249),(250),(380),(381),(382),(383),(384)) AS v(pid)
CROSS JOIN hunt_methods hm
CROSS JOIN games g
WHERE hm.method_name = 'Soft Reset'
  AND g.title = 'Brilliant Diamond/Shining Pearl'
  AND NOT EXISTS (
    SELECT 1 FROM method_availability ma
    WHERE ma.pokemon_id = v.pid
      AND ma.method_id = hm.id
      AND ma.game_id = g.id)
  AND NOT EXISTS (
    SELECT 1 FROM shiny_locks sl
    WHERE sl.pokemon_id = v.pid AND sl.game_id = g.id);
-- Expect: up to 14 rows inserted. Shiny-lock guard is redundant for these
-- specific Pokémon (BDSP locks were already corrected) but is kept for safety.

-- ============================================================================
-- C  HeartGold/SoulSilver (game title = 'HeartGold/SoulSilver')
--    Pokémon: 144 Articuno, 145 Zapdos, 146 Moltres (post-game Seafoam/Power Plant),
--             150 Mewtwo (Cerulean Cave),
--             243 Raikou, 244 Entei, 245 Suicune (roaming beasts, modelled as static),
--             380 Latias (roaming HG), 381 Latios (roaming SS, modelled as static).
--    None are shiny-locked in Gen 4.
--    Source: https://bulbapedia.bulbagarden.net/wiki/HeartGold_and_SoulSilver
--    Note: Lugia(249) and Ho-Oh(250) are already seeded for HGSS; not repeated here.
-- ============================================================================

-- C1. Static encounter rows for HGSS.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, g.id, 'static', 'none'
FROM (VALUES (144),(145),(146),(150),(243),(244),(245),(380),(381)) AS v(pid)
CROSS JOIN games g
WHERE g.title = 'HeartGold/SoulSilver'
ON CONFLICT DO NOTHING;
-- Expect: up to 9 rows inserted.

-- C2. Soft Reset method rows for HGSS.
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, hm.id, g.id
FROM (VALUES (144),(145),(146),(150),(243),(244),(245),(380),(381)) AS v(pid)
CROSS JOIN hunt_methods hm
CROSS JOIN games g
WHERE hm.method_name = 'Soft Reset'
  AND g.title = 'HeartGold/SoulSilver'
  AND NOT EXISTS (
    SELECT 1 FROM method_availability ma
    WHERE ma.pokemon_id = v.pid
      AND ma.method_id = hm.id
      AND ma.game_id = g.id)
  AND NOT EXISTS (
    SELECT 1 FROM shiny_locks sl
    WHERE sl.pokemon_id = v.pid AND sl.game_id = g.id);
-- Expect: up to 9 rows inserted.

-- ============================================================================
-- D  Black 2/White 2 (game title = 'Black 2/White 2')
--    Pokémon: 377 Regirock, 378 Regice, 379 Registeel (Underground Ruins),
--             480 Uxie, 481 Mesprit, 482 Azelf (post-game Unova lakes),
--             485 Heatran (Reversal Mountain),
--             486 Regigigas (Twist Mountain),
--             488 Cresselia (Marvelous Bridge, roaming, modelled as static),
--             380 Latias, 381 Latios (roaming, modelled as static).
--    None are shiny-locked in Gen 5.
--    Source: https://bulbapedia.bulbagarden.net/wiki/Black_2_and_White_2
-- ============================================================================

-- D1. Static encounter rows for B2W2.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, g.id, 'static', 'none'
FROM (VALUES (377),(378),(379),(480),(481),(482),(485),(486),(488),(380),(381)) AS v(pid)
CROSS JOIN games g
WHERE g.title = 'Black 2/White 2'
ON CONFLICT DO NOTHING;
-- Expect: up to 11 rows inserted.

-- D2. Soft Reset method rows for B2W2.
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, hm.id, g.id
FROM (VALUES (377),(378),(379),(480),(481),(482),(485),(486),(488),(380),(381)) AS v(pid)
CROSS JOIN hunt_methods hm
CROSS JOIN games g
WHERE hm.method_name = 'Soft Reset'
  AND g.title = 'Black 2/White 2'
  AND NOT EXISTS (
    SELECT 1 FROM method_availability ma
    WHERE ma.pokemon_id = v.pid
      AND ma.method_id = hm.id
      AND ma.game_id = g.id)
  AND NOT EXISTS (
    SELECT 1 FROM shiny_locks sl
    WHERE sl.pokemon_id = v.pid AND sl.game_id = g.id);
-- Expect: up to 11 rows inserted.

-- ============================================================================
-- E  Kyurem — Black/White + Black 2/White 2 (Giant Chasm static)
--    Pokémon: 646 Kyurem.
--    Not shiny-locked in Gen 5.
--    Source: https://bulbapedia.bulbagarden.net/wiki/Giant_Chasm
-- ============================================================================

-- E1. Static encounter rows for BW and B2W2.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT 646, g.id, 'static', 'none'
FROM games g
WHERE g.title IN ('Black/White', 'Black 2/White 2')
ON CONFLICT DO NOTHING;
-- Expect: up to 2 rows inserted.

-- E2. Soft Reset method rows for BW and B2W2.
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT 646, hm.id, g.id
FROM hunt_methods hm
CROSS JOIN games g
WHERE hm.method_name = 'Soft Reset'
  AND g.title IN ('Black/White', 'Black 2/White 2')
  AND NOT EXISTS (
    SELECT 1 FROM method_availability ma
    WHERE ma.pokemon_id = 646
      AND ma.method_id = hm.id
      AND ma.game_id = g.id)
  AND NOT EXISTS (
    SELECT 1 FROM shiny_locks sl
    WHERE sl.pokemon_id = 646 AND sl.game_id = g.id);
-- Expect: up to 2 rows inserted.

-- ============================================================================
-- NEEDS-REVIEW items (not included above):
--
--   RSE/FRLG Lugia(249)/Ho-Oh(250) via Navel Rock — event-only (ticket required
--     at a past event); shiny hunting requires having obtained the Mystic Ticket /
--     Aurasphere Ticket via a Nintendo event. Availability is game-content but
--     practically inaccessible. Left out pending owner decision on event-gated
--     encounters.
--
--   FRLG Deoxys(386) via Birth Island — event-only (Aurora Ticket); same
--     reasoning as above. Note: ORAS Deoxys IS shiny-locked and must NOT be added.
--
--   HGSS roaming Raikou/Entei — in HGSS the beasts are encountered by running
--     into them in the overworld (roaming). The tracker models roaming as static
--     (Soft Reset), which is a reasonable simplification. Included in Section C.
--
--   BDSP Dialga(483)/Palkia(484) — already covered by existing seed data
--     (overrides include "Brilliant Diamond/Shining Pearl": "static"). Their
--     incorrect shiny_locks rows were corrected separately in gen8_corrections.sql
--     Section B1/B2. Not repeated here.
-- ============================================================================

-- ============================================================================
-- F  LGPE shiny-lock corrections — Articuno(144), Zapdos(145), Moltres(146),
--    Mewtwo(150) in Let's Go Pikachu/Eevee.
--
--    Background: Bulbapedia and documented SR hunts confirm these four are NOT
--    shiny-locked in LGPE. Only the partner Pikachu/Eevee and Mew are locked.
--    The seed source (backend/seeds/shiny_locks.json) has been corrected on
--    branch chore/method-data-audit; this section brings the live DB into sync
--    without waiting for a full re-seed.
--
--    IMPORTANT — LGPE huntability caveat: removing these lock rows is correct
--    but does NOT automatically surface a huntable method, because the
--    soft_reset_static method in hunt_methods.json does not include
--    'Let's Go Pikachu/Eevee'. Until LGPE is added to that method (or a
--    dedicated LGPE static method is introduced), these Pokémon will appear
--    unlocked but without a viable hunt method in the UI. See investigation
--    notes in the commit message for next steps.
--
--    Safe to re-run (DELETE WHERE is idempotent; does nothing if rows are absent).
-- ============================================================================

-- F1. Remove the incorrect shiny_locks rows for LGPE birds + Mewtwo.
DELETE FROM shiny_locks
WHERE game_id = (SELECT id FROM games WHERE title = 'Let''s Go Pikachu/Eevee')
  AND pokemon_id IN (144, 145, 146, 150);
-- Expect: 4 rows deleted on first run, 0 on subsequent runs.

-- ============================================================================
-- G  LGPE dedicated Soft Reset (static) method
--    Let's Go Pikachu/Eevee: Articuno(144), Zapdos(145), Moltres(146), Mewtwo(150).
--
--    Background: the generic soft_reset_static method in hunt_methods.json does
--    NOT include LGPE because in LGPE the Shiny Charm boosts only Catch Combo
--    (wild) encounters, NOT static soft-reset encounters. Reusing soft_reset_static
--    (which has charm_rolls=2) would over-count the odds for LGPE statics.
--    A dedicated method with base_rolls=1, charm_rolls=0 is therefore required.
--
--    This section:
--      G1. Inserts the hunt_methods row (idempotent: no-op if already present,
--          identified by method_name='Soft Reset', requires_kind='static',
--          base_rolls=1, charm_rolls=0 — the combination is unique to this method).
--      G2. Inserts the method_games mapping to LGPE.
--      G3. Inserts method_availability rows for every (pokemon, LGPE) pair that
--          has a static encounter row and is NOT shiny-locked in LGPE — generic
--          join, no hardcoded pokemon_ids.
--
--    Safe to re-run: all inserts are guarded with NOT EXISTS / ON CONFLICT.
-- ============================================================================

-- G1. Insert the LGPE-specific static Soft Reset method if not already present.
INSERT INTO hunt_methods (method_name, avg_time_seconds, base_rolls, charm_rolls, formula_type, requires_kind, requires_terrain)
SELECT 'Soft Reset', 30, 1, 0, 'static', 'static', NULL
WHERE NOT EXISTS (
    SELECT 1 FROM hunt_methods
    WHERE method_name = 'Soft Reset'
      AND requires_kind = 'static'
      AND base_rolls = 1
      AND charm_rolls = 0);
-- Expect: 1 row inserted on first run, 0 on re-run.

-- G2. Map the new method to Let's Go Pikachu/Eevee (idempotent via PRIMARY KEY).
INSERT INTO method_games (method_id, game_id)
SELECT hm.id, g.id
FROM hunt_methods hm
CROSS JOIN games g
WHERE hm.method_name = 'Soft Reset'
  AND hm.requires_kind = 'static'
  AND hm.base_rolls = 1
  AND hm.charm_rolls = 0
  AND g.title = 'Let''s Go Pikachu/Eevee'
ON CONFLICT DO NOTHING;
-- Expect: 1 row inserted on first run, 0 on re-run.

-- G3. Derive method_availability for every LGPE static encounter not shiny-locked.
--     Joins pokemon_game_encounter (kind='static', LGPE) to the new method via
--     method_games — mirrors the computeAvailability logic exactly.
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT DISTINCT pge.pokemon_id, hm.id, pge.game_id
FROM pokemon_game_encounter pge
JOIN games g ON g.id = pge.game_id
    AND g.title = 'Let''s Go Pikachu/Eevee'
JOIN hunt_methods hm ON hm.method_name = 'Soft Reset'
    AND hm.requires_kind = 'static'
    AND hm.base_rolls = 1
    AND hm.charm_rolls = 0
    AND hm.requires_kind = pge.kind
JOIN method_games mg ON mg.method_id = hm.id AND mg.game_id = pge.game_id
WHERE NOT EXISTS (
    SELECT 1 FROM shiny_locks sl
    WHERE sl.pokemon_id = pge.pokemon_id AND sl.game_id = pge.game_id)
  AND NOT EXISTS (
    SELECT 1 FROM method_availability ma
    WHERE ma.pokemon_id = pge.pokemon_id
      AND ma.method_id = hm.id
      AND ma.game_id = pge.game_id)
  AND pge.kind = 'static';
-- Expect: rows for the 4 un-locked statics (144, 145, 146, 150 after Section F
-- removed their shiny_locks rows). 0 rows for shiny-locked partner Pikachu(25)/
-- Eevee(133) and Mew(151) because those remain in shiny_locks for LGPE.

-- ============================================================================
-- H  BDSP Darkrai/Shaymin/Arceus shiny-lock correction
--    Pokémon: 491 Darkrai (Newmoon Island), 492 Shaymin (Flower Paradise),
--             493 Arceus (Hall of Origin).
--
--    Background: these three were previously marked shiny-locked in BDSP on the
--    (incorrect) assumption they were event-distribution-only without a SR target.
--    Bulbapedia confirms all three are soft-resettable static encounters in BDSP,
--    gated behind event items (Member Card / Oak's Letter / Azure Flute).
--    They ARE locked in Legends: Arceus — those rows are retained.
--
--    Durable fix: backend/seeds/shiny_locks.json has been corrected (BDSP removed
--    from each entry's games array); backend/seeds/legendary_encounters.json has
--    been updated to include BDSP static encounter entries for all three.
--    After a re-seed, computeAvailability will derive Soft Reset for them in BDSP.
--
--    This section brings the live DB into sync without a full re-seed.
--    Safe to re-run: DELETE WHERE is idempotent; ON CONFLICT / NOT EXISTS guards
--    on all INSERTs prevent duplicates.
-- ============================================================================

-- H1. Remove the incorrect BDSP shiny_locks rows for Darkrai, Shaymin, Arceus.
DELETE FROM shiny_locks
WHERE game_id = (SELECT id FROM games WHERE title = 'Brilliant Diamond/Shining Pearl')
  AND pokemon_id IN (491, 492, 493);
-- Expect: 3 rows deleted on first run, 0 on subsequent runs.

-- H2. Insert BDSP static encounter rows for Darkrai, Shaymin, Arceus.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, g.id, 'static', 'none'
FROM (VALUES (491),(492),(493)) AS v(pid)
CROSS JOIN games g
WHERE g.title = 'Brilliant Diamond/Shining Pearl'
ON CONFLICT DO NOTHING;
-- Expect: up to 3 rows inserted.

-- H3. Derive Soft Reset method_availability for Darkrai, Shaymin, Arceus in BDSP.
--     Shiny-lock guard included for safety (rows removed in H1, so the guard
--     fires clean; it also future-proofs against accidental re-insertion).
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, hm.id, g.id
FROM (VALUES (491),(492),(493)) AS v(pid)
CROSS JOIN hunt_methods hm
CROSS JOIN games g
WHERE hm.method_name = 'Soft Reset'
  AND g.title = 'Brilliant Diamond/Shining Pearl'
  AND NOT EXISTS (
    SELECT 1 FROM method_availability ma
    WHERE ma.pokemon_id = v.pid
      AND ma.method_id = hm.id
      AND ma.game_id = g.id)
  AND NOT EXISTS (
    SELECT 1 FROM shiny_locks sl
    WHERE sl.pokemon_id = v.pid AND sl.game_id = g.id);
-- Expect: up to 3 rows inserted (one per Pokémon, for the Soft Reset method
-- that maps to BDSP). Pokémon remain locked in Legends: Arceus — those
-- shiny_locks rows are untouched and will suppress Soft Reset in PLA.

-- ============================================================================
-- I  Batch of web-verified legendary corrections (2026-06-01)
--    Mirrors Parts A and B of the seed-source updates on branch
--    chore/method-data-audit; see legendary_encounters.json + shiny_locks.json.
--
--    Static encounter additions (Part A):
--      144/145/146 Kanto birds    → Diamond/Pearl/Platinum (Pal Park transfers, Route 144/145/146)
--      151 Mew                    → Ruby/Sapphire/Emerald (Faraway Island, Mystic Ticket event)
--      249 Lugia                  → Ruby/Sapphire/Emerald (Navel Rock, Mystic Ticket),
--                                   FireRed/LeafGreen (Navel Rock, Mystic Ticket),
--                                   Omega Ruby/Alpha Sapphire (Sea Mauville / Diving event)
--      250 Ho-Oh                  → Ruby/Sapphire/Emerald (Navel Rock, Mystic Ticket),
--                                   FireRed/LeafGreen (Navel Rock, Mystic Ticket),
--                                   Omega Ruby/Alpha Sapphire (Sea Mauville / Diving event)
--      251 Celebi                 → Gold/Silver/Crystal (GS Ball event static)
--      380 Latias                 → Omega Ruby/Alpha Sapphire (roaming/static in ORAS)
--      381 Latios                 → Omega Ruby/Alpha Sapphire (roaming/static in ORAS)
--      386 Deoxys                 → Ruby/Sapphire/Emerald (Birth Island, Aurora Ticket),
--                                   FireRed/LeafGreen (Birth Island, Aurora Ticket)
--                                   NOTE: ORAS Deoxys is shiny-locked — NOT added here.
--      485 Heatran                → Omega Ruby/Alpha Sapphire (Scorched Slab)
--      486 Regigigas              → Omega Ruby/Alpha Sapphire (Island Cave / Sealed Chamber)
--      491 Darkrai                → Diamond/Pearl/Platinum (Newmoon Island, Member Card)
--      492 Shaymin                → Diamond/Pearl/Platinum (Flower Paradise, Oak's Letter)
--      493 Arceus                 → Diamond/Pearl/Platinum (Hall of Origin, Azure Flute)
--      641/642/645 Forces of Nature → Black/White (Abundant Shrine / Route 7 roaming,
--                                   modelled as static)
--
--    Under-lock additions (Part B):
--      151 Mew      → Brilliant Diamond/Shining Pearl (Poke Ball Plus gift, locked)
--      385 Jirachi  → Brilliant Diamond/Shining Pearl (Mystery Gift, locked)
--      494 Victini  → Black/White (Liberty Garden static, hardcoded non-shiny)
--      905 Enamorus → Scarlet/Violet (Snacksworth gift in Indigo Disk, locked)
--
--    Safety: the shiny-lock guard in I2 prevents method_availability rows being
--    written for the under-locked (pokemon, game) pairs added in I3.
--    Consistency: Mew RSE (huntable) and Mew BDSP (locked) are different games —
--    both correct and non-conflicting.
--
--    NOT run here (already applied to live DB via MCP session on 2026-06-01).
--    DO NOT run again unless re-seeding from scratch.
-- ============================================================================

-- I1. Static encounter rows.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, g.id, 'static', 'none'
FROM (VALUES
    -- Kanto birds → DPPt
    (144, 'Diamond/Pearl/Platinum'),
    (145, 'Diamond/Pearl/Platinum'),
    (146, 'Diamond/Pearl/Platinum'),
    -- Mew → RSE
    (151, 'Ruby/Sapphire/Emerald'),
    -- Lugia → RSE, FRLG, ORAS
    (249, 'Ruby/Sapphire/Emerald'),
    (249, 'FireRed/LeafGreen'),
    (249, 'Omega Ruby/Alpha Sapphire'),
    -- Ho-Oh → RSE, FRLG, ORAS
    (250, 'Ruby/Sapphire/Emerald'),
    (250, 'FireRed/LeafGreen'),
    (250, 'Omega Ruby/Alpha Sapphire'),
    -- Celebi → GSC
    (251, 'Gold/Silver/Crystal'),
    -- Latias, Latios → ORAS
    (380, 'Omega Ruby/Alpha Sapphire'),
    (381, 'Omega Ruby/Alpha Sapphire'),
    -- Deoxys → RSE, FRLG  (ORAS is shiny-locked, excluded)
    (386, 'Ruby/Sapphire/Emerald'),
    (386, 'FireRed/LeafGreen'),
    -- Heatran, Regigigas → ORAS
    (485, 'Omega Ruby/Alpha Sapphire'),
    (486, 'Omega Ruby/Alpha Sapphire'),
    -- Darkrai, Shaymin → DPPt (Arceus DPPt excluded: Azure Flute never officially distributed)
    (491, 'Diamond/Pearl/Platinum'),
    (492, 'Diamond/Pearl/Platinum'),
    -- Forces of Nature → BW
    (641, 'Black/White'),
    (642, 'Black/White'),
    (645, 'Black/White')
) AS v(pid, gtitle)
JOIN games g ON g.title = v.gtitle
ON CONFLICT DO NOTHING;
-- Expect: up to 22 rows inserted (0 on re-run). [Arceus DPPt removed: Azure Flute unreleased]

-- I2. Soft Reset method_availability for the static additions above.
--     Shiny-lock guard prevents rows for 151-BDSP, 385-BDSP, 494-BW, 905-SV.
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, hm.id, g.id
FROM (VALUES
    (144, 'Diamond/Pearl/Platinum'),
    (145, 'Diamond/Pearl/Platinum'),
    (146, 'Diamond/Pearl/Platinum'),
    (151, 'Ruby/Sapphire/Emerald'),
    (249, 'Ruby/Sapphire/Emerald'),
    (249, 'FireRed/LeafGreen'),
    (249, 'Omega Ruby/Alpha Sapphire'),
    (250, 'Ruby/Sapphire/Emerald'),
    (250, 'FireRed/LeafGreen'),
    (250, 'Omega Ruby/Alpha Sapphire'),
    (251, 'Gold/Silver/Crystal'),
    (380, 'Omega Ruby/Alpha Sapphire'),
    (381, 'Omega Ruby/Alpha Sapphire'),
    (386, 'Ruby/Sapphire/Emerald'),
    (386, 'FireRed/LeafGreen'),
    (485, 'Omega Ruby/Alpha Sapphire'),
    (486, 'Omega Ruby/Alpha Sapphire'),
    (491, 'Diamond/Pearl/Platinum'),
    (492, 'Diamond/Pearl/Platinum'),
    (641, 'Black/White'),
    (642, 'Black/White'),
    (645, 'Black/White')
) AS v(pid, gtitle)
JOIN games g ON g.title = v.gtitle
CROSS JOIN hunt_methods hm
WHERE hm.method_name = 'Soft Reset'
  AND NOT EXISTS (
    SELECT 1 FROM method_availability ma
    WHERE ma.pokemon_id = v.pid
      AND ma.method_id = hm.id
      AND ma.game_id = g.id)
  AND NOT EXISTS (
    SELECT 1 FROM shiny_locks sl
    WHERE sl.pokemon_id = v.pid AND sl.game_id = g.id)
  AND EXISTS (
    SELECT 1 FROM method_games mg
    WHERE mg.method_id = hm.id AND mg.game_id = g.id);
-- Expect: up to 22 rows inserted. The lock guard keeps 151-BDSP, 385-BDSP,
-- 494-BW, and 905-SV method-less as required. 0 rows on re-run.

-- I3. Under-lock additions: insert missing shiny_locks rows.
INSERT INTO shiny_locks (pokemon_id, game_id)
SELECT v.pid, g.id
FROM (VALUES
    -- Mew — Poke Ball Plus gift in BDSP, hardcoded non-shiny
    (151, 'Brilliant Diamond/Shining Pearl'),
    -- Jirachi — Mystery Gift in BDSP, hardcoded non-shiny
    (385, 'Brilliant Diamond/Shining Pearl'),
    -- Victini — Liberty Garden encounter in BW, engine-locked non-shiny
    (494, 'Black/White'),
    -- Enamorus — Snacksworth gift (Indigo Disk) in SV, hardcoded non-shiny
    (905, 'Scarlet/Violet')
) AS v(pid, gtitle)
JOIN games g ON g.title = v.gtitle
ON CONFLICT DO NOTHING;
-- Expect: up to 4 rows inserted (0 on re-run or if already present).

COMMIT;
