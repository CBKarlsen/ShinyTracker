-- gen7_corrections.sql
-- Generation 7 — Sun/Moon (game_id=11), Ultra Sun/Ultra Moon (game_id=12),
--                Let's Go Pikachu/Eevee (game_id=13).
-- Generated 2026-05-31 from a stable Gen 7 snapshot. DO NOT auto-run: review first (see gen7_report.md).
--
-- RESULT OF AUDIT: zero method MISLABELS and zero cross-game misplacements found.
-- Every assigned Gen 7 method row is correct. All issues below are COVERAGE GAPS.
--
-- KEYING NOTE: keyed on natural triples (pokemon_id, game_id, method_id) or
-- (pokemon_id, game_id) — never on surrogate id, which renumbers on reseed.
-- All INSERTs are guarded with ON CONFLICT DO NOTHING or NOT EXISTS for idempotency.
--
-- Gen 7 method IDs (verified):
--   SOS Chaining = 168  (games 11, 12)
--   Catch Combo  = 174  (game 13)
--   Soft Reset   = 178  (games 11, 12 — in method_games, but 0 rows generated)
--   Masuda       = 172  (used for Gen 8; shape matches Gen 7; reuse proposed below)
--   Random Encounter with charm_rolls=2: no Gen 7-specific ID exists yet (see Gap 2)

-- ============================================================================
-- (A) METHOD CORRECTIONS (UPDATEs): NONE.
--     All SOS Chaining / Catch Combo / Soft Reset assignments verified correct.
--     No misplaced methods, no Masuda-on-non-breedable, no shiny-lock violations.
-- ============================================================================


-- ============================================================================
-- (B) GAP 1 — SM/USUM: Static encounters missing → Soft Reset rows never generated.
--
--     pokemon_game_encounter has ZERO kind='static' rows for games 11 and 12.
--     Soft Reset (178) IS registered in method_games for both games, but the seed
--     engine cannot derive method_availability rows without encounter source rows.
--
--     ⚠ DURABLE FIX BELONGS IN THE SEED PIPELINE. method_availability is regenerated
--     on every re-seed, so these manual INSERTs will be overwritten. Prefer adding
--     encounter rows to the seed source CSV / seeds JSON. SQL below is a one-off
--     reference only; confirm completeness before running.
--
--     Cases confirmed huntable (not shiny-locked) in SM/USUM per Bulbapedia:
--       Type: Null (772)       — gift in both SM and USUM; Soft Reset valid
--       Zygarde (718)          — cell collection gift; Soft Reset valid
--       Nihilego (793)         — Ultra Beast; not locked; SM+USUM
--       Buzzwole (794)         — Ultra Beast; not locked; SM+USUM
--       Pheromosa (795)        — Ultra Beast; not locked; SM+USUM
--       Xurkitree (796)        — Ultra Beast; not locked; SM+USUM
--       Celesteela (797)       — Ultra Beast; not locked; SM+USUM
--       Kartana (798)          — Ultra Beast; not locked; SM+USUM
--       Guzzlord (799)         — Ultra Beast; not locked; SM+USUM
--       Necrozma (800)         — LOCKED in SM; huntable via Ultra Wormhole in USUM only
--       Poipole (803)          — NEEDS REVIEW: gift UB in USUM; shiny-lock status uncertain
--
--     Sources:
--       https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon
--       https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
-- ============================================================================

BEGIN;

-- B1. Static encounter rows for confirmed-huntable SM Pokémon (game 11).
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 11, 'static', 'none'
FROM (VALUES
  (718),  -- Zygarde
  (772),  -- Type: Null
  (793),  -- Nihilego
  (794),  -- Buzzwole
  (795),  -- Pheromosa
  (796),  -- Xurkitree
  (797),  -- Celesteela
  (798),  -- Kartana
  (799)   -- Guzzlord
) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 9 rows inserted (0 if already present).
-- NOTE: Necrozma(800) intentionally omitted for game 11 — shiny-locked in SM.
-- NOTE: Poipole(803) omitted — NEEDS REVIEW for SM availability and shiny-lock status.

-- B2. Soft Reset method rows for the above SM Pokémon (method 178, game 11).
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 11
FROM (VALUES
  (718), (772), (793), (794), (795), (796), (797), (798), (799)
) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 11
);
-- Expect: up to 9 rows inserted (0 if re-run).

-- B3. Static encounter rows for confirmed-huntable USUM Pokémon (game 12).
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 12, 'static', 'none'
FROM (VALUES
  (718),  -- Zygarde
  (772),  -- Type: Null
  (793),  -- Nihilego
  (794),  -- Buzzwole
  (795),  -- Pheromosa
  (796),  -- Xurkitree
  (797),  -- Celesteela
  (798),  -- Kartana
  (799),  -- Guzzlord
  (800)   -- Necrozma — huntable in USUM (not shiny-locked)
) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 10 rows inserted (0 if already present).
-- NOTE: Poipole(803) omitted — NEEDS REVIEW for shiny-lock status in USUM.

-- B4. Soft Reset method rows for the above USUM Pokémon (method 178, game 12).
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 12
FROM (VALUES
  (718), (772), (793), (794), (795), (796), (797), (798), (799), (800)
) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 12
);
-- Expect: up to 10 rows inserted (0 if re-run).

COMMIT;


-- ============================================================================
-- (C) GAP 2 — SM/USUM: Random Encounter absent from method_games.
--
--     SM has 236 and USUM has 338 wild-encounter Pokémon with no Random Encounter
--     method in method_games for games 11 or 12. Wild Pokémon are fully huntable
--     at random (1/4096, Shiny Charm applies → charm_rolls=2).
--
--     No Gen 7-specific Random Encounter row exists in hunt_methods; IDs 161 and
--     166 share the correct shape (base_rolls=1, charm_rolls=2, kind=wild) but
--     belong to Gen 9 and Gen 5 BW2 respectively.
--
--     Two options — pick ONE:
--       Option A: reuse ID 161 (Gen 9) — simpler, but cross-gen sharing
--       Option B: INSERT a new hunt_methods row dedicated to Gen 6/7
--                 then map it — cleaner semantics
--
--     BOTH blocks are provided below; run only one. Both are NEEDS REVIEW.
--
--     Source: https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon#Generation_VI
-- ============================================================================

-- -- OPTION A: reuse existing Random Encounter ID 161 (NEEDS REVIEW — cross-gen sharing)
-- BEGIN;
-- INSERT INTO method_games (game_id, method_id)
-- VALUES (11, 161), (12, 161)
-- ON CONFLICT DO NOTHING;
-- -- method_availability rows will be generated on next re-seed via the engine.
-- -- If populating manually for a stable DB:
-- -- INSERT INTO method_availability (pokemon_id, method_id, game_id)
-- -- SELECT pge.pokemon_id, 161, pge.game_id
-- -- FROM pokemon_game_encounter pge
-- -- WHERE pge.game_id IN (11, 12) AND pge.kind = 'wild'
-- -- ON CONFLICT DO NOTHING;
-- COMMIT;

-- -- OPTION B: new Gen 6/7-specific Random Encounter row (NEEDS REVIEW — schema change)
-- BEGIN;
-- INSERT INTO hunt_methods (method_name, base_rolls, charm_rolls, requires_kind, requires_terrain)
-- VALUES ('Random Encounter', 1, 2, 'wild', NULL)
-- RETURNING id;  -- note the new id, substitute <NEW_ID> below
-- INSERT INTO method_games (game_id, method_id) VALUES (9, <NEW_ID>) ON CONFLICT DO NOTHING;   -- X/Y
-- INSERT INTO method_games (game_id, method_id) VALUES (10, <NEW_ID>) ON CONFLICT DO NOTHING;  -- ORAS
-- INSERT INTO method_games (game_id, method_id) VALUES (11, <NEW_ID>) ON CONFLICT DO NOTHING;  -- SM
-- INSERT INTO method_games (game_id, method_id) VALUES (12, <NEW_ID>) ON CONFLICT DO NOTHING;  -- USUM
-- COMMIT;


-- ============================================================================
-- (D) GAP 3 — SM/USUM: Masuda Method absent from method_games.
--
--     SM has 133 and USUM has 186 breedable Pokémon with egg encounters.
--     Masuda Method (introduced Gen 4, valid Gen 7) has zero rows in method_games
--     for games 11 or 12. Method ID 172 (base_rolls=6, charm_rolls=2, kind=egg)
--     is already used for Gen 8 and has the correct Gen 7 shape.
--
--     NEEDS REVIEW: confirm this is an intentional omission or an oversight before
--     applying. If approved, wire method 172 to games 11 and 12.
--
--     Source: https://bulbapedia.bulbagarden.net/wiki/Masuda_method
-- ============================================================================

-- -- Masuda Method for SM/USUM (NEEDS REVIEW)
-- BEGIN;
-- INSERT INTO method_games (game_id, method_id)
-- VALUES (11, 172), (12, 172)
-- ON CONFLICT DO NOTHING;
-- -- method_availability rows will be generated on next re-seed.
-- -- If populating manually for a stable DB:
-- -- INSERT INTO method_availability (pokemon_id, method_id, game_id)
-- -- SELECT pge.pokemon_id, 172, pge.game_id
-- -- FROM pokemon_game_encounter pge
-- -- JOIN pokemon p ON p.id = pge.pokemon_id
-- -- WHERE pge.game_id IN (11, 12) AND pge.kind = 'egg' AND p.can_breed = true
-- -- ON CONFLICT DO NOTHING;
-- COMMIT;


-- ============================================================================
-- (E) GAP 4 — LGPE: shiny_locks missing for Articuno, Zapdos, Moltres, Mewtwo.
--
--     The shiny_locks table has zero rows for game 13. Articuno(144), Zapdos(145),
--     Moltres(146), and Mewtwo(150) are confirmed shiny-locked in LGPE per Bulbapedia.
--     They have static encounter rows in game 13 but are not in shiny_locks.
--
--     The method side is accidentally safe (Catch Combo requires kind='wild'; these
--     are static-only so no Catch Combo row is generated). However, the missing lock
--     entries are a data integrity gap: adding Soft Reset to LGPE would expose them
--     as huntable without this fix.
--
--     These INSERTs are low-risk and confirmed correct; the only NEEDS REVIEW is
--     whether any additional LGPE Pokémon are shiny-locked (Meltan/Melmetal are
--     event-only and have no encounter rows, so no action needed for them).
--
--     Source: https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon#Generation_VII
-- ============================================================================

BEGIN;

INSERT INTO shiny_locks (pokemon_id, game_id)
VALUES
  (144, 13),  -- Articuno — shiny-locked in LGPE
  (145, 13),  -- Zapdos   — shiny-locked in LGPE
  (146, 13),  -- Moltres  — shiny-locked in LGPE
  (150, 13)   -- Mewtwo   — shiny-locked in LGPE
ON CONFLICT DO NOTHING;
-- Expect: 4 rows inserted (0 if re-run).

COMMIT;

-- Note: Meltan(808) and Melmetal(809) are event-only in LGPE and have no
-- encounter rows — intentionally NOT added here.
