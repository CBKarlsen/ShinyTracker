-- gen5_corrections.sql
-- Generation 5 — Black/White (game_id=7), Black 2/White 2 (game_id=8).
-- Generated 2026-05-31 from a stable Gen 5 snapshot. DO NOT auto-run: review first (see gen5_report.md).
--
-- Three items:
--   A. Structural fix — Soft Reset charm_rolls bleed (S1): add a no-charm SR method for pre-Shiny-Charm
--      games and rewire game 7 (and all other pre-charm games) to it.  CROSS-GENERATIONAL IMPACT.
--   B. Coverage gap — 7 static legendaries missing encounter + SR rows (C1).
--   C. Coverage gap — Masuda Method entirely absent from Gen 5 (C2). Method_games wiring only;
--      mass method_availability rows belong in seed pipeline (NEEDS REVIEW).
--
-- KEYING NOTE: keyed on (pokemon_id, game_id, method_id) natural triple, not surrogate id.
-- All INSERTs are idempotent (ON CONFLICT DO NOTHING or NOT EXISTS guards).
--
-- Verified method IDs:
--   178  Soft Reset (charm_rolls=2) — current, shared across all games; needs no-charm sibling
--   165  Random Encounter, no charm (charm_rolls=0) — model for new no-charm SR
--   166  Random Encounter, with charm (charm_rolls=2)
--   162  Masuda Method (charm_rolls=2, base_rolls=6) — mapped to games 14/15
--   172  Masuda Method (charm_rolls=2, base_rolls=6) — mapped to game 17

-- ============================================================================
-- (A) STRUCTURAL FIX — Soft Reset charm_rolls bleed (CROSS-GENERATIONAL)
--
--     Problem: method 178 (Soft Reset) has charm_rolls=2 but is shared by ALL games including
--     those without the Shiny Charm (Gen 1–5 BW, and all pre-Gen-6 games).
--     Random Encounter correctly avoids this by using separate method IDs per charm tier.
--
--     Fix: add a no-charm Soft Reset method row and rewire pre-Shiny-Charm games to it.
--     The Shiny Charm was introduced in Gen 6 (X/Y). Pre-charm games: 1–12 (Gen 1–5).
--     Post-charm games (keep method 178): 13+ (Gen 6+).
--
--     ⚠ SCOPE WARNING: this affects ALL Gen 1–5 games (game_ids 1–12), not just Gen 5.
--     Run only after confirming no other game depends on charm_rolls=2 for SR in Gen 1–5.
--     The new method_id placeholder below must be replaced with the actual serial id assigned
--     by the DB after INSERT — the NOT EXISTS guard in step A2 uses the method name to find it.
--
--     Source: https://bulbapedia.bulbagarden.net/wiki/Shiny_Charm (introduced Gen 6)
-- ============================================================================

BEGIN;

-- A1. Insert no-charm Soft Reset method (mirror of method 165 / Random Encounter no-charm).
--     Only runs if a Soft Reset with charm_rolls=0 does not already exist.
INSERT INTO hunt_methods (method_name, base_rolls, charm_rolls, requires_kind, requires_terrain)
SELECT 'Soft Reset', 1, 0, 'static', NULL
WHERE NOT EXISTS (
  SELECT 1 FROM hunt_methods
  WHERE method_name = 'Soft Reset' AND charm_rolls = 0
);
-- Expect: 1 row inserted (0 if already present). Note the new id assigned — needed for A2/A3.

-- A2. Wire the no-charm Soft Reset to all pre-Shiny-Charm games (1–12 = Gen 1–5).
--     Replaces: nothing is removed here — method_games entries for method 178 on games 1–12
--     should be REMOVED after confirming A3 backfill, but that step is left for manual review.
INSERT INTO method_games (method_id, game_id)
SELECT hm.id, g.id
FROM hunt_methods hm
CROSS JOIN games g
WHERE hm.method_name = 'Soft Reset' AND hm.charm_rolls = 0
  AND g.id BETWEEN 1 AND 12
  AND NOT EXISTS (
    SELECT 1 FROM method_games mg2
    WHERE mg2.method_id = hm.id AND mg2.game_id = g.id
  );
-- Expect: up to 12 rows (0 if already wired).

-- A3. Migrate existing method_availability rows for SR in pre-charm games (1–12) from
--     method 178 to the new no-charm SR method id.
--     ⚠ NEEDS REVIEW before running — affects Gen 1–4 rows already audited.
--     Uncomment only after verifying the new method_id is correct.
--
-- UPDATE method_availability
-- SET method_id = (SELECT id FROM hunt_methods WHERE method_name = 'Soft Reset' AND charm_rolls = 0 LIMIT 1)
-- WHERE method_id = 178 AND game_id BETWEEN 1 AND 12;
-- -- Expect: 4 rows for Gen 5 (Reshiram/Zekrom x2 games) + Gen 1–4 SR rows.

COMMIT;


-- ============================================================================
-- (B) COVERAGE GAP — Gen 5 static legendaries missing encounter + SR rows (C1)
--
--     7 static legendaries have neither pokemon_game_encounter nor method_availability rows.
--     They are NOT shiny-locked (confirmed: Bulbapedia Gen 5 shiny lock list).
--     Soft Reset is the canonical method.
--
--     Per-game availability (Bulbapedia):
--       Cobalion (638)  — BW (Mistralton Cave) + B2W2 (same)
--       Terrakion (639) — BW (Victory Road) + B2W2 (same)
--       Virizion  (640) — BW (Pinwheel Forest) + B2W2 (Rumination Field)
--       Tornadus  (641) — BW only (roaming; SR via reset after trigger)
--       Thundurus (642) — BW only (roaming; SR via reset after trigger)
--       Kyurem    (646) — BW (Giant Chasm) + B2W2 (same)
--       Landorus  (645) — B2W2 only (Abundant Shrine, requires Tornadus+Thundurus transfer)
--
--     NOT added (intentionally absent — shiny-locked or event-only):
--       Victini (494)  — Liberty Garden event; shiny-locked in all distributions
--       Keldeo  (647)  — event-distributed only; shiny-locked
--       Meloetta(648)  — event-distributed only; shiny-locked
--       Genesect(649)  — event-distributed only; shiny-locked
--
--     ⚠ DURABLE FIX BELONGS IN SEED PIPELINE — method_availability is regenerated on re-seed.
--     This SQL is for review / one-off stable DB only. See gen5_report.md for context.
--
--     SR method to use: once item A above is resolved, these rows should use the no-charm SR
--     method for game 7 (BW) and method 178 for game 8 (B2W2 has Shiny Charm).
--     For now, method 178 is used for both pending the A-series fix.
--
--     Source: https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
-- ============================================================================

BEGIN;

-- B1. Pokemon_game_encounter rows — kind='static', terrain='none' (mirrors Reshiram/Zekrom).

-- BW (game_id=7): Cobalion, Terrakion, Virizion, Tornadus, Thundurus, Kyurem
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 7, 'static', 'none'
FROM (VALUES (638),(639),(640),(641),(642),(646)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 6 rows (0 if already present).

-- B2W2 (game_id=8): Cobalion, Terrakion, Virizion, Kyurem, Landorus
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 8, 'static', 'none'
FROM (VALUES (638),(639),(640),(645),(646)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 5 rows (0 if already present).

-- B2. Method_availability rows — Soft Reset (method 178) for now.
--     TODO: once item A resolves, split game 7 to no-charm SR and keep game 8 on method 178.

-- BW (game_id=7): Cobalion, Terrakion, Virizion, Tornadus, Thundurus, Kyurem
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 7
FROM (VALUES (638),(639),(640),(641),(642),(646)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 7
);
-- Expect: up to 6 rows (0 if re-run).

-- B2W2 (game_id=8): Cobalion, Terrakion, Virizion, Kyurem, Landorus
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 8
FROM (VALUES (638),(639),(640),(645),(646)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 8
);
-- Expect: up to 5 rows (0 if re-run).

COMMIT;


-- ============================================================================
-- (C) COVERAGE GAP — Masuda Method absent from Gen 5 (C2) — NEEDS REVIEW
--
--     The Masuda Method is entirely absent from method_games for games 7/8.
--     Gen 5 introduced the boosted Masuda rate (6× rolls = base_rolls 6).
--     232 breedable Pokémon in BW and 272 in B2W2 have no Masuda row.
--
--     CHARM SPLIT REQUIRED:
--       Game 7 (BW)   — no Shiny Charm → needs Masuda method with charm_rolls=0
--       Game 8 (B2W2) — has Shiny Charm → can use existing charm_rolls=2 Masuda method
--
--     Existing Masuda methods (both have charm_rolls=2):
--       id 162 — currently wired to games 14, 15 (Sword/Shield, BDSP)
--       id 172 — currently wired to game 17 (Scarlet/Violet)
--
--     RECOMMENDED APPROACH:
--       1. Create a new no-charm Masuda method (base_rolls=6, charm_rolls=0, requires_kind='egg')
--          for BW (game 7) and any other pre-charm games needing Masuda.
--       2. Wire the no-charm Masuda to game 7 via method_games.
--       3. Wire an existing charm Masuda (e.g. id 162) to game 8 via method_games.
--       4. Drive the method_availability mass-insert (232 + 272 rows) from the seed pipeline,
--          not ad-hoc SQL, so it survives re-seeds.
--
--     The method_games wiring below is provided as reference SQL.
--     The mass method_availability INSERT is intentionally NOT provided here — it must come
--     from the seed pipeline to survive re-seeds.
--
--     Source: https://bulbapedia.bulbagarden.net/wiki/Masuda_method
-- ============================================================================

-- C1. NEEDS REVIEW — Create no-charm Masuda method for BW (game 7) and other pre-charm games.
--     Uncomment and run only after deciding the policy.
--
-- INSERT INTO hunt_methods (method_name, base_rolls, charm_rolls, requires_kind, requires_terrain)
-- SELECT 'Masuda Method', 6, 0, 'egg', NULL
-- WHERE NOT EXISTS (
--   SELECT 1 FROM hunt_methods
--   WHERE method_name = 'Masuda Method' AND charm_rolls = 0
-- );

-- C2. NEEDS REVIEW — Wire no-charm Masuda to game 7 (BW).
--
-- INSERT INTO method_games (method_id, game_id)
-- SELECT hm.id, 7
-- FROM hunt_methods hm
-- WHERE hm.method_name = 'Masuda Method' AND hm.charm_rolls = 0
-- ON CONFLICT DO NOTHING;

-- C3. NEEDS REVIEW — Wire charm Masuda (id 162) to game 8 (B2W2).
--
-- INSERT INTO method_games (method_id, game_id)
-- VALUES (162, 8)
-- ON CONFLICT DO NOTHING;

-- C4. NEEDS REVIEW — Mass method_availability insert (232 BW + 272 B2W2 breedable Pokémon).
--     Drive from seed pipeline, not here. Sketch only:
--
-- -- BW (game 7, no-charm Masuda):
-- INSERT INTO method_availability (pokemon_id, method_id, game_id)
-- SELECT ma_wild.pokemon_id,
--        (SELECT id FROM hunt_methods WHERE method_name = 'Masuda Method' AND charm_rolls = 0),
--        7
-- FROM method_availability ma_wild
-- JOIN pokemon p ON p.id = ma_wild.pokemon_id
-- WHERE ma_wild.game_id = 7 AND p.can_breed = true
-- ON CONFLICT DO NOTHING;
--
-- -- B2W2 (game 8, charm Masuda id 162):
-- INSERT INTO method_availability (pokemon_id, method_id, game_id)
-- SELECT ma_wild.pokemon_id, 162, 8
-- FROM method_availability ma_wild
-- JOIN pokemon p ON p.id = ma_wild.pokemon_id
-- WHERE ma_wild.game_id = 8 AND p.can_breed = true
-- ON CONFLICT DO NOTHING;
