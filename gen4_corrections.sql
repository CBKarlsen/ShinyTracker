-- gen4_corrections.sql
-- Generation 4 — Diamond/Pearl/Platinum (game_id=5), HeartGold/SoulSilver (game_id=6).
-- Generated 2026-05-31 from a STABLE Gen 4 snapshot. DO NOT auto-run: review first (see gen4_report.md).
--
-- RESULT OF AUDIT: zero method MISLABELS were found. Every assigned Gen 4 method is correct,
-- so there are NO corrective UPDATE statements. The only item is a COVERAGE GAP (missing rows)
-- for 8 DPPt static legendaries, provided below as optional, idempotent INSERTs.
--
-- KEYING NOTE: keyed on the natural triple (pokemon_id, method_id, game_id), NOT the surrogate
-- method_availability.id (which renumbers on every reseed and was observed to be unreliable this
-- session). INSERTs are guarded with NOT EXISTS, so re-running is safe (0 rows if already present).
--
-- Gen 4 method IDs (verified): game 5 Soft Reset = 178.

-- ============================================================================
-- (A) METHOD CORRECTIONS (UPDATEs): NONE.
--     All Poké Radar / Random Encounter / Masuda / Soft Reset assignments verified correct.
-- ============================================================================


-- ============================================================================
-- (B) COVERAGE GAP — DPPt static legendaries with no hunt entry.
--
--     IMPORTANT: the gap is at the ENCOUNTER level, not just the method level. These 8 have
--     NO pokemon_game_encounter row for game 5 at all (encounter = '(none)'), whereas Giratina
--     (#487) has 'static/none' + Soft Reset. So the backfill must add BOTH the static encounter
--     row AND the method row to mirror Giratina's (consistent) shape.
--
--     ⚠ DURABLE FIX BELONGS IN THE SEED PIPELINE. method_availability is derived from encounter
--     data and is regenerated on every re-seed (this DB was observed reseeding mid-session), so
--     these manual INSERTs will be overwritten on the next seed run. Prefer adding the encounter
--     rows to the seed source (CSV / seeds JSON) so they survive. The SQL below is provided for
--     review / a one-off stable DB only. Confirm the gap is unintentional before running.
--
--     They are static encounters and are NOT shiny-locked in Gen 4 (locking began Gen V), so
--     Soft Reset is the canonical method.  Source: https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon
--     Pokémon: Uxie(480) Mesprit(481) Azelf(482) Dialga(483) Palkia(484)
--              Heatran(485) Regigigas(486) Cresselia(488)
-- ============================================================================

BEGIN;

-- B1. Static encounter rows (mirror Giratina's 'static/none'). PK is (pokemon_id,game_id,kind,terrain).
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, 5, 'static', 'none'
FROM (VALUES (480),(481),(482),(483),(484),(485),(486),(488)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 8 rows inserted (0 if already present).

-- B2. Soft Reset method rows (method_id 178 = Soft Reset, game 5). Guarded for idempotency.
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, 178, 5
FROM (VALUES (480),(481),(482),(483),(484),(485),(486),(488)) AS v(pid)
WHERE NOT EXISTS (
  SELECT 1 FROM method_availability ma
  WHERE ma.pokemon_id = v.pid AND ma.method_id = 178 AND ma.game_id = 5
);
-- Expect: up to 8 rows inserted (0 if re-run).

COMMIT;

-- Note: event mythicals Darkrai(491)/Shaymin(492)/Arceus(493) are intentionally NOT added —
-- they are shiny-unobtainable in Gen 4 and correctly have no huntable method.
