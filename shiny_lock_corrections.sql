-- shiny_lock_corrections.sql
-- CONSOLIDATED shiny-lock corrections across all generations.
-- Generated 2026-05-31. Read-only audit output — DO NOT auto-run; review first.
--
-- PROVENANCE: consolidated from the per-generation audits (gen6/gen7/gen8/gen9_corrections.sql)
-- and then INDEPENDENTLY RE-VERIFIED against Bulbapedia / PokémonDB before inclusion here.
-- Gens 1–5 contributed nothing: Gen 1–4 predate the shiny-lock mechanic (began Gen V) and
-- Gen 5's locks were already correct.
--
-- ⚠ VERIFICATION CORRECTION vs the sub-agent findings:
--   The Gen 6 audit flagged the XY gift starters (Bulbasaur/Charmander/Squirtle) and gift
--   Lapras as shiny-locked. That is INCORRECT — XY starters and the Lapras gift are NOT
--   shiny-locked (the selection screen merely doesn't reveal shininess).
--   Sources: https://pokemondb.net/pokebase/237551 ,  https://x.com/Kaphotics/status/1457961562585534466
--   They are therefore EXCLUDED from the executable sections below (see Section 3 note).
--
-- KEYING: every statement keys on natural keys — (pokemon_id, game_id) for shiny_locks,
-- (pokemon_id, game_id, method_id) for method_availability — never the surrogate id.
-- All statements are idempotent (guarded / ON CONFLICT DO NOTHING). Re-running is safe.
--
-- ⚠ DURABILITY: shiny_locks is regenerated on re-seed. For a permanent fix, also add these
-- locks/removals to the seed source. This file is correct for a one-off run on the stable DB.
--
-- Game ids: 9=X/Y, 10=ORAS, 13=Let's Go P/E, 15=BDSP, 16=Legends Arceus, 17=Scarlet/Violet.
-- Soft Reset method_id = 178.

-- ============================================================================
-- SECTION 1 — HUNTABLE-BUT-LOCKED: remove method rows from genuinely shiny-locked Pokémon.
--   (These Pokémon are already in shiny_locks but still carry a Soft Reset hunt row.)
-- ============================================================================

BEGIN;

-- 1A. X/Y (game 9): Xerneas(716), Yveltal(717) are shiny-locked but have Soft Reset rows.
--     Source: https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
DELETE FROM method_availability
WHERE game_id = 9 AND method_id = 178 AND pokemon_id IN (716, 717);
-- Expect: 2 rows deleted.

-- 1B. ORAS (game 10): Kyogre(382), Groudon(383), Rayquaza(384) are shiny-locked but have
--     Soft Reset rows. (Rayquaza: Delta Episode lock — well established; one Bulbapedia table
--     auto-read showed it as obtainable-shiny, but community consensus + multiple FAQs say
--     locked. Double-check Rayquaza if you want maximal certainty.)
--     Source: https://www.gameslearningsociety.org/are-all-legendaries-in-oras-shiny-locked/
DELETE FROM method_availability
WHERE game_id = 10 AND method_id = 178 AND pokemon_id IN (382, 383, 384);
-- Expect: 3 rows deleted.

COMMIT;

-- ============================================================================
-- SECTION 2 — shiny_locks TABLE FIXES
-- ============================================================================

BEGIN;

-- 2A. REMOVE false-positive locks — these Pokémon are NOT shiny-locked.
--     BDSP (game 15): Dialga(483)/Palkia(484) are SR-able at Spear Pillar; Giratina(487)
--     is SR-able at Turnback Cave (and already has a correct Soft Reset row — the lock
--     directly contradicts it).
--     Source: https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon#Brilliant_Diamond_and_Shining_Pearl
DELETE FROM shiny_locks WHERE game_id = 15 AND pokemon_id IN (483, 484, 487);
-- Expect: 3 rows deleted.

--     Scarlet/Violet (game 17): Archaludon(1018) and Hydrapple(1019) are evolutions of
--     wild-obtainable Pokémon and are NOT shiny-locked (you evolve a shiny base).
--     (Gouging Fire (1020) is left in shiny_locks for now — its lock status is uncertain;
--      see Section 3 NEEDS REVIEW. Not deleted here.)
--     Source: https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
DELETE FROM shiny_locks WHERE game_id = 17 AND pokemon_id IN (1018, 1019);
-- Expect: 2 rows deleted.

-- 2B. ADD missing locks — genuinely shiny-locked Pokémon absent from shiny_locks.

--     ORAS (game 10): table had ZERO entries. The 4 ORAS locks:
--     Kyogre(382), Groudon(383), Rayquaza(384), Deoxys(386).
--     Source: https://www.gameslearningsociety.org/are-all-legendaries-in-oras-shiny-locked/
INSERT INTO shiny_locks (pokemon_id, game_id)
SELECT v.pid, 10 FROM (VALUES (382),(383),(384),(386)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 4 rows inserted.

--     Let's Go P/E (game 13): Articuno(144), Zapdos(145), Moltres(146), Mewtwo(150) are
--     shiny-locked in LGPE.
--     Source: https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon#Generation_VII
INSERT INTO shiny_locks (pokemon_id, game_id)
SELECT v.pid, 13 FROM (VALUES (144),(145),(146),(150)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 4 rows inserted.

--     Legends: Arceus (game 16): ALL legendaries/mythicals are shiny-locked. Table had only
--     Dialga/Palkia/Arceus/Enamorus; adding the rest. None have method rows (data-hygiene).
--     Source: https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon#Legends:_Arceus
INSERT INTO shiny_locks (pokemon_id, game_id)
SELECT v.pid, 16 FROM (VALUES (480),(481),(482),(485),(486),(487),(488),(490),(491),(492)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 10 rows inserted. (Uxie, Mesprit, Azelf, Heatran, Regigigas,
--          Giratina-altered, Cresselia, Manaphy, Darkrai, Shaymin-land)

--     Scarlet/Violet (game 17): DLC locks missing from table. Loyal Three + Terapagos.
--     None have method rows (no huntable conflict), but UI lock-checks need them.
--     Source: https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon
INSERT INTO shiny_locks (pokemon_id, game_id)
SELECT v.pid, 17 FROM (VALUES (1014),(1015),(1016),(1024)) AS v(pid)
ON CONFLICT DO NOTHING;
-- Expect: up to 4 rows inserted. (Okidogi, Munkidori, Fezandipiti, Terapagos)

COMMIT;

-- ============================================================================
-- SECTION 3 — NEEDS REVIEW (intentionally NOT executed)
-- ============================================================================
--
-- 3A. XY gift starters Bulbasaur(1)/Charmander(4)/Squirtle(7) + Kalos starters + gift Lapras(131):
--     The Gen 6 audit flagged these as shiny-locked. RE-VERIFIED AS NOT LOCKED — do NOT add to
--     shiny_locks. (Their incorrectly-assigned Friend Safari method rows are a separate
--     over-assignment problem; handle in the Gen 6 seed-pipeline work, not here.)
--
-- 3B. XY roaming legendary bird (144/145/146): only one appears (player-dependent) and IS
--     shiny-locked, but the schema can't disambiguate which form on one pokemon_id. Confirm
--     which applies before locking.
--
-- 3C. ORAS Latias(380)/Latios(381): the story Soul-Dew gift is shiny-locked, but the Eon-Ticket
--     roaming encounter is SR-able — same pokemon_id. Don't lock blindly; decide per encounter.
--
-- 3D. SV Gouging Fire(1020): left in shiny_locks. Lock status uncertain (Indigo Disk Paradox
--     legendary); verify whether it is huntable-shiny before removing its lock.
--
-- 3E. XY Zygarde(718): one Bulbapedia table marked it unobtainable-shiny; not surfaced by the
--     Gen 6 audit. Verify before adding a lock.
--
-- 3F. ORAS Cosplay Pikachu: shiny-locked but shares pokemon_id 25 with normally-huntable
--     Pikachu — cannot be represented in shiny_locks without blocking all Pikachu hunts. Skip.
-- ============================================================================
