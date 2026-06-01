-- gen6_corrections.sql
-- Generation 6 — X/Y (game_id=9), OmegaRuby/AlphaSapphire (game_id=10).
-- Generated 2026-05-31 from a stable Gen 6 snapshot. DO NOT auto-run: review first (see gen6_report.md).
--
-- Gen 6 method IDs (verified):
--   Friend Safari  = 173  (game 9 only)
--   Chain Fishing  = 175  (games 9, 10)
--   DexNav         = 169  (game 10 only)
--   Soft Reset     = 178  (games 9, 10)
--
-- KEYING NOTE: all operations keyed on natural triple (pokemon_id, method_id, game_id).
-- DELETEs are guarded with EXISTS; INSERTs use ON CONFLICT DO NOTHING or NOT EXISTS guards.

-- ============================================================================
-- (A) METHOD CORRECTIONS — shiny-locked Pokémon with huntable method rows
--     These are confirmed bugs: the Pokémon is in shiny_locks (or is known-locked
--     per Bulbapedia) and must not appear as a huntable target.
-- ============================================================================

BEGIN;

-- A1. XY (game 9): Xerneas + Yveltal — in shiny_locks AND have Soft Reset rows.
--     Source: https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
DELETE FROM method_availability
WHERE game_id = 9 AND method_id = 178 AND pokemon_id IN (716, 717);
-- Expected: 2 rows deleted. (xerneas=716, yveltal=717)

-- A2. ORAS (game 10): Kyogre + Groudon + Rayquaza — shiny-locked, have Soft Reset rows.
--     Source: https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
DELETE FROM method_availability
WHERE game_id = 10 AND method_id = 178 AND pokemon_id IN (382, 383, 384);
-- Expected: 3 rows deleted. (kyogre=382, groudon=383, rayquaza=384)

-- A3. XY (game 9): Kanto gift starters + Lapras — gift-locked in XY, have Friend Safari rows.
--     Bulbasaur(1)/Charmander(4)/Squirtle(7) are given by Prof. Sycamore (shiny-locked gift).
--     Lapras(131) is a weekly gift in XY (shiny-locked).
--     Source: https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
DELETE FROM method_availability
WHERE game_id = 9 AND method_id = 173 AND pokemon_id IN (1, 4, 7, 131);
-- Expected: 4 rows deleted.

COMMIT;

-- ============================================================================
-- (B) shiny_locks TABLE ADDITIONS
--     The shiny_locks table is missing all ORAS entries and several XY entries.
--     These INSERTs add the confirmed locks. Idempotent (ON CONFLICT DO NOTHING).
--
--     ⚠ DURABLE FIX BELONGS IN THE SEED PIPELINE — shiny_locks may be regenerated
--     on re-seed. Add these to the seed source so they survive.
--
--     Sources:
--       XY:   https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
--       ORAS: https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
-- ============================================================================

BEGIN;

-- B1. XY (game 9) missing locks.
--     Kanto starters (1/4/7) and Lapras (131) are gift-locked.
--     NOTE: The roaming bird lock in XY is for the specific bird the player picks in
--     Pokémon Village — the other two do not appear in-game. The mechanic is complex
--     (only 1 of 3 is encountered and it IS shiny-locked). All three IDs are included
--     here as NEEDS REVIEW — confirm which form the lock applies to before running.
INSERT INTO shiny_locks (pokemon_id, game_id)
SELECT v.pid, 9
FROM (VALUES
  (1),   -- bulbasaur  — gift starter, shiny-locked
  (4),   -- charmander — gift starter, shiny-locked
  (7),   -- squirtle   — gift starter, shiny-locked
  (131)  -- lapras     — weekly gift, shiny-locked
) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expected: up to 4 rows inserted.

-- B1b. NEEDS REVIEW: Roaming birds in XY — one of the three is chosen by the player
--      and is shiny-locked. Confirm which of 144/145/146 is the valid lock target.
-- INSERT INTO shiny_locks (pokemon_id, game_id)
-- SELECT v.pid, 9 FROM (VALUES (144),(145),(146)) AS v(pid) ON CONFLICT DO NOTHING;

-- B2. ORAS (game 10) locks — all missing (zero entries in shiny_locks for game 10).
INSERT INTO shiny_locks (pokemon_id, game_id)
SELECT v.pid, 10
FROM (VALUES
  (382),  -- kyogre    — story-forced, shiny-locked
  (383),  -- groudon   — story-forced, shiny-locked
  (384),  -- rayquaza  — Delta Episode, shiny-locked
  (386),  -- deoxys    — story event, shiny-locked
  (380),  -- latias    — gift with Soul Dew (story), shiny-locked
  (381)   -- latios    — gift with Soul Dew (story), shiny-locked
           -- Note: Eon Ticket version of Latias/Latios is SR-able; gift version is locked.
           -- If both variants use the same pokemon_id, this entry NEEDS REVIEW.
) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expected: up to 6 rows inserted.

-- B2b. NEEDS REVIEW: Cosplay Pikachu in ORAS — shiny-locked but uses pokemon_id=25 (pikachu).
--      Pikachu (#25) in ORAS also appears via DexNav (legitimate hunt). The lock is specific
--      to the gift form. The shiny_locks table cannot distinguish variants — add only if the
--      table is intended to block ALL pikachu hunts in ORAS (it isn't). Recommend leaving out.
-- INSERT INTO shiny_locks (pokemon_id, game_id) VALUES (25, 10) ON CONFLICT DO NOTHING;

COMMIT;

-- ============================================================================
-- (C) COVERAGE GAP — non-locked ORAS static legendaries with no encounter/method rows.
--
--     IMPORTANT: same caveat as Gen 4 — these gaps are at the ENCOUNTER level.
--     The backfill must add pokemon_game_encounter rows AND method_availability rows.
--     ⚠ DURABLE FIX BELONGS IN THE SEED PIPELINE.
--
--     Confirmed non-locked Soft Reset targets in ORAS (game 10):
--       Regirock(377), Regice(378), Registeel(379)  — Desert Ruins / Island Cave / Ancient Tomb
--
--     NEEDS REVIEW before running:
--       Latias(380) / Latios(381) via Eon Ticket — non-gift roaming encounter is SR-able,
--         but the story-gift version is locked (same pokemon_id). If encounter row distinguishes
--         them, add encounter + Soft Reset. If not, omit to avoid presenting a locked encounter
--         as huntable.
--       Lugia(249) / Ho-Oh(250) — Sea Mauville item required; verify availability.
--       Inter-gen legendaries via Soaring/Dimensional Rift (Dialga 483, Palkia 484,
--         Giratina-altered 487, Reshiram 643, Zekrom 644, Kyurem 646, Cobalion 638,
--         Terrakion 639, Virizion 640, Cresselia 488, Heatran 485) — all SR-able post-game;
--         add to seed source after confirming availability.
--
--     Sources:
--       Regis: https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon_Omega_Ruby_and_Alpha_Sapphire
-- ============================================================================

BEGIN;

-- C1. Static encounter rows for confirmed non-locked ORAS legendaries.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 10, 'static', 'none'
FROM (VALUES (377),(378),(379)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expected: up to 3 rows inserted (regirock/regice/registeel).

-- C2. Soft Reset method rows for the same (method_id=178, game_id=10).
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 10
FROM (VALUES (377),(378),(379)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 10
);
-- Expected: up to 3 rows inserted.

COMMIT;

-- ============================================================================
-- (D) COVERAGE GAP — Mewtwo in XY (game 9)
--
--     Mewtwo (#150) is a static encounter in Pokémon Village (XY), is NOT shiny-locked,
--     has no pokemon_game_encounter or method_availability row for game 9.
--     Mirroring the treatment of Giratina in Gen 4, it should have static/none + Soft Reset.
--
--     Source: https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9mon_Village
-- ============================================================================

BEGIN;

-- D1. Static encounter row for Mewtwo in XY.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
VALUES (150, 9, 'static', 'none')
ON CONFLICT DO NOTHING;
-- Expected: 1 row inserted.

-- D2. Soft Reset method row for Mewtwo in XY (method_id=178, game_id=9).
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT 150, 178, 9
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = 150 AND ma.method_id = 178 AND ma.game_id = 9
);
-- Expected: 1 row inserted.

COMMIT;

-- ============================================================================
-- (E) PIPELINE GAPS — not addressable by one-off SQL (noted for seed work)
--
--     E1. Random Encounter (XY): ~270 wild Pokémon have no Random Encounter method.
--         Friend Safari (method 173) is currently the only wild method in game 9,
--         covering 348 species — the vast majority incorrectly. The correct approach:
--           - Replace Friend Safari over-assignment with Random Encounter for the
--             ~270 Pokémon that are wild-catchable in XY but NOT in Friend Safari.
--           - Restrict Friend Safari to the ~130 species actually available there.
--           - Add Poké Radar (method 163) for ~120 grass-encounter species
--             (requires adding method_games entry for game 9, method 163).
--           - Add Horde Encounter if a method ID exists for Gen 6 Horde.
--         This is a seeding pipeline rewrite, not a one-off SQL fix.
--
--     E2. Masuda Method (both games): Masuda exists in Gen 6 (6× odds).
--         Not wired to games 9 or 10. Coverage policy decision required.
--         If adding: insert method_games rows for (game_id IN (9,10), method_id=172)
--         and add method_availability rows for all can_breed=true Pokémon in each game.
--
--     E3. base_odds verification: Gen 6 halved base shiny odds to 1/4096.
--         Verify games.base_odds = 4096 for game_id IN (9,10). If still 8192, update:
--           UPDATE games SET base_odds = 4096 WHERE id IN (9, 10);
--         (Read-only audit — not executed here.)
-- ============================================================================
