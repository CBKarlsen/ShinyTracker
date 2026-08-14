-- pokedex_availability_gap_corrections.sql
-- Fix list for the "in a game's own regional Pokedex but missing
-- pokemon_availability" audit run against pokedex_entries (added 2026-08-14,
-- backend/cmd/seed_pokedex). NOT applied to the live DB — proposal only.
--
-- Scope: of 384 dex/availability mismatches across 9 games, 314 are Pokemon
-- that only exist as evolved/trade forms of an already-available pre-evolution
-- (by design: pokemon_availability intentionally omits evolved-only forms —
-- see the comment on deriveEggEncounters in cmd/seed/main.go — the frontend's
-- /api/pokemon/{id}/route handler walks evolves_from_id to build a "hunt the
-- pre-evo, then evolve" route instead). 15 more are real-world/cross-title
-- distribution Pokemon (Mew, Celebi's GS Ball, Zarude, Pecharunt, PLA's
-- Darkrai/Shaymin/Manaphy Mystery Gift items, PLA's Treasures-of-Ruin-style
-- Forces of Nature which require linking a completed SV DLC save) that no
-- amount of seeding can turn into a normal encounter route — left alone.
--
-- The remaining 55 candidate rows were run through a Bulbapedia verification
-- pass: only 10 hold up (kept below, Sections B and E). 11 were factually
-- wrong and 34 are shiny-locked or method-less and deliver nothing for a
-- shiny tracker — see the REMOVED note at the bottom for what was cut and why.
--
-- Keying and safety conventions match docs/audit/legendary_gap_corrections.sql:
-- ON CONFLICT DO NOTHING / NOT EXISTS guards throughout, method_id resolved
-- by requires_kind (never hardcoded), shiny_locks guard on every
-- method_availability insert.

BEGIN;

-- ============================================================================
-- B  Gold/Silver/Crystal + HeartGold/SoulSilver — National Park Bug-Catching
--    Contest (123 Scyther, 127 Pinsir). 5% encounter rate at Lv13-14, present
--    in all versions of both bundles (not version-exclusive). Contest-only,
--    so no wild row was ever sourced from PokeAPI — a genuine gap. Modeled as
--    'wild' (a contest catch is a real wild-encounter table roll, not a
--    guaranteed individual), so existing wild-based hunt methods pick it up
--    via the normal computeAvailability join — no method_availability insert
--    needed here.
--    Durable fix (already wired): seeds/overworld_species.json now carries
--    these two ids under "Gold/Silver/Crystal" / "HeartGold/SoulSilver", so a
--    normal `go run ./cmd/seed` reseed no longer drops them — this section is
--    left in place only as an immediate direct-DB patch if applying ahead of
--    a full reseed.
--    Source: https://bulbapedia.bulbagarden.net/wiki/Bug-Catching_Contest
-- ============================================================================

INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
SELECT v.pid, g.id, 'wild', 'none'
FROM (VALUES (123),(127)) AS v(pid)
CROSS JOIN games g
WHERE g.title IN ('Gold/Silver/Crystal', 'HeartGold/SoulSilver')
ON CONFLICT DO NOTHING;

INSERT INTO pokemon_availability (pokemon_id, game_id)
SELECT v.pid, g.id
FROM (VALUES (123),(127)) AS v(pid)
CROSS JOIN games g
WHERE g.title IN ('Gold/Silver/Crystal', 'HeartGold/SoulSilver')
ON CONFLICT DO NOTHING;
-- Expect: up to 4 rows per INSERT.

-- ============================================================================
-- E  HeartGold/SoulSilver — incense-free baby Pokemon obtainable only by
--    breeding their already-available evolved parent (172 Pichu <- Pikachu,
--    173 Cleffa <- Clefairy, 174 Igglybuff <- Jigglypuff, 238 Smoochum <-
--    Jynx, 239 Elekid <- Electabuzz, 240 Magby <- Magmar). No incense item
--    needed for any of these six — still normal play.
--    reconcileAvailability can never backfill them: they have no wild/static/
--    raid encounter of their own, and the old deriveEggEncounters couldn't
--    bootstrap an egg row without a pre-existing availability row for the
--    baby itself (the baby has evolves_from_id IS NULL like its parent, but
--    unlike the parent it is itself can_breed = false — only the evolved
--    form can be paired at the Day Care).
--    Durable fix (already wired): deriveEggEncounters in cmd/seed/main.go now
--    walks the evolution family via a recursive CTE instead of fanning out
--    from pokemon_availability directly, so a normal reseed picks these six
--    up on its own — this section is left in place only as an immediate
--    direct-DB patch if applying ahead of a full reseed.
--    Source: https://bulbapedia.bulbagarden.net/wiki/Egg_Group (Baby Pokemon)
-- ============================================================================

INSERT INTO pokemon_availability (pokemon_id, game_id)
SELECT v.pid, g.id
FROM (VALUES (172),(173),(174),(238),(239),(240)) AS v(pid)
CROSS JOIN games g
WHERE g.title = 'HeartGold/SoulSilver'
ON CONFLICT DO NOTHING;

-- Egg encounter rows, mirroring deriveEggEncounters' own INSERT shape.
INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind)
SELECT v.pid, g.id, 'egg'
FROM (VALUES (172),(173),(174),(238),(239),(240)) AS v(pid)
CROSS JOIN games g
WHERE g.title = 'HeartGold/SoulSilver'
ON CONFLICT DO NOTHING;

INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT v.pid, hm.id, g.id
FROM (VALUES (172),(173),(174),(238),(239),(240)) AS v(pid)
CROSS JOIN hunt_methods hm
CROSS JOIN games g
WHERE hm.requires_kind = 'egg'
  AND g.title = 'HeartGold/SoulSilver'
  AND EXISTS (SELECT 1 FROM method_games mg WHERE mg.method_id = hm.id AND mg.game_id = g.id)
  AND NOT EXISTS (SELECT 1 FROM method_availability ma
      WHERE ma.pokemon_id = v.pid AND ma.method_id = hm.id AND ma.game_id = g.id)
  AND NOT EXISTS (SELECT 1 FROM shiny_locks sl
      WHERE sl.pokemon_id = v.pid AND sl.game_id = g.id);
-- Expect: up to 6 rows per INSERT.

-- ============================================================================
-- REMOVED — a Bulbapedia verification pass found these do not hold up.
-- Nothing below this line was ever applied to any database.
--
--   Section A (144/145/146/150 Kanto birds + Mewtwo in Gold/Silver/Crystal)
--     — all four are "Time Capsule, Event" only in Gen 2; Cerulean Cave
--     collapsed after Red/Blue/Yellow and does not exist in GSC's map data.
--
--   Section C (138/140 Omanyte/Kabuto in Gold/Silver/Crystal) — the Gen 1
--     fossils were removed from GSC's data entirely; Pewter Museum fossil
--     revival is an HGSS-only feature, not present in GSC.
--
--   Section D (1/4/7 Kanto starters in Gold/Silver/Crystal) — Oak's
--     Kanto-starter gift is HGSS-only, given after defeating Red on Mt.
--     Silver; it does not exist in GSC.
--
--   Section E's Ruby/Sapphire/Emerald half (172 Pichu, 174 Igglybuff, 298
--     Azurill) — the breeding claim itself is correct, but no
--     requires_kind='egg' hunt method exists for Gen 3 in hunt_methods.json,
--     so inserting it would create an "available, no method" entry instead
--     of a usable route. The new deriveEggEncounters rule reproduces this
--     same shape for RSE on a full reseed (see its code comment) — left
--     un-gated deliberately rather than silently filtered.
--
--   Section F (83 Farfetch'd, 108 Lickitung in FireRed/LeafGreen) —
--     obtainable via in-game trade (Farfetch'd for a Spearow in Vermilion
--     City; Lickitung for a Golduck on Route 18), but Gen 3 in-game trades
--     always hand over a fixed, non-shiny individual — cannot be shiny.
--     Both are now in seeds/shiny_locks.json instead of being granted
--     availability.
--
--   Sections G (Sword/Shield), H (Scarlet/Violet), I (Legends: Arceus) —
--     every row in all three is shiny-locked, so their method_availability
--     inserts would self-neutralise against the shiny_locks guard in
--     computeAvailability; an availability-only row (no hunt route) delivers
--     nothing to a shiny tracker. Two factual errors worth recording from
--     Section G/H's comments while removing them: Glastrier/Spectrier are a
--     player CHOICE available in BOTH Sword and Shield (not version
--     exclusives — shiny_locks.json already has this right, one row per
--     Pokemon listing "Sword/Shield"), and the "Loyal Three" (1014 Okidogi,
--     1015 Munkidori, 1016 Fezandipiti) are a Teal Mask DLC encounter, not
--     Indigo Disk. One more addition wired separately: 772 Type: Null
--     (Sword/Shield) was verified genuinely shiny-locked and missing from
--     shiny_locks.json — added there directly rather than through this file.
--
--   H's 1009 Walking Wake / 1010 Iron Leaves specifically — these are timed
--     7-star Tera raid event distributions, not a standing Area Zero
--     encounter, so even as an availability-only row they'd be wrong.
-- ============================================================================

COMMIT;
