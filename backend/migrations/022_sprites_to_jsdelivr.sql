-- Move served sprite URLs off raw.githubusercontent.com onto jsDelivr.
--
-- Why: raw.githubusercontent.com is a source-code endpoint, not a CDN. GitHub's
-- ToS disallows using it as asset hosting, it rate-limits under load, it has no
-- SLA, and it can start failing without notice — which for this app means every
-- sprite in the Dex grid turning into a blank plate. jsDelivr exists to serve
-- GitHub content, returns byte-identical files (verified by SHA-1), sets a
-- week-long cache, and has an Oslo edge node.
--
-- This changes only WHERE the artwork is fetched from. It does NOT change the
-- copyright position: the sprites are Nintendo/Game Freak's either way. That is
-- a separate, unresolved question — see README "Known gaps". Bundling them into
-- the app would make it worse, not better, because it turns referencing into
-- redistributing.
--
-- Safe to re-run: replace() on an already-converted URL is a no-op.
-- To roll back, swap the two arguments to replace() and run again.

UPDATE pokemon
   SET sprite_url = replace(
           sprite_url,
           'https://raw.githubusercontent.com/PokeAPI/sprites/master/',
           'https://cdn.jsdelivr.net/gh/PokeAPI/sprites@master/')
 WHERE sprite_url LIKE 'https://raw.githubusercontent.com/PokeAPI/sprites/master/%';

UPDATE pokemon
   SET shiny_sprite_url = replace(
           shiny_sprite_url,
           'https://raw.githubusercontent.com/PokeAPI/sprites/master/',
           'https://cdn.jsdelivr.net/gh/PokeAPI/sprites@master/')
 WHERE shiny_sprite_url LIKE 'https://raw.githubusercontent.com/PokeAPI/sprites/master/%';

-- Verify (expect 0 rows on both):
--   SELECT count(*) FROM pokemon WHERE sprite_url LIKE '%raw.githubusercontent%';
--   SELECT count(*) FROM pokemon WHERE shiny_sprite_url LIKE '%raw.githubusercontent%';
--
-- NOTE: cmd/seed and cmd/sync repopulate these columns from PokeAPI's own
-- response, which returns raw.githubusercontent URLs — so a re-seed UNDOES this.
-- internal/services/pokeapi.go rewrites the host on write for that reason; if
-- that rewrite is ever removed, this migration has to be re-run after seeding.
