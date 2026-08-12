-- 016_add_shiny_sprite_url.sql
--
-- Clients hardcode a GitHub sprite host for the shiny variant because
-- pokemon only ever stored front_default. PokeAPI's same sprites object also
-- carries front_shiny, so SyncPokemonData now writes it too
-- (internal/services/pokeapi.go) -- this migration adds the column it lands in
-- and fills it for the rows that already exist.
--
-- Nullable, same as sprite_url, and every read path COALESCEs it to '' so a
-- row this backfill misses returns a blank rather than failing a request.
--
-- Purely additive, safe to re-run.
ALTER TABLE pokemon ADD COLUMN IF NOT EXISTS shiny_sprite_url TEXT;

-- Backfill without a re-seed. PokeAPI's front_shiny is its front_default with
-- one extra path segment, so the shiny URL is derivable from the sprite_url
-- already stored -- no network, and it follows the host in the data rather
-- than hardcoding one here, so a mirrored sprite_url yields a mirrored shiny.
--
-- This exists because the alternative is worse: SyncPokemonData is the only
-- code that writes this column, it lives in cmd/sync, and it opens with
-- TRUNCATE TABLE hunt_methods CASCADE. TRUNCATE CASCADE truncates *referencing*
-- tables outright -- it does not honour ON DELETE SET NULL -- and user_hunts
-- references hunt_methods, so running cmd/sync to populate a sprite column
-- risks real user hunts. Populate here; leave cmd/sync for a deliberate,
-- backed-up full catalog refresh.
--
-- Idempotent: only touches rows that have no shiny URL yet.
UPDATE pokemon
   SET shiny_sprite_url = replace(sprite_url, '/pokemon/', '/pokemon/shiny/')
 WHERE shiny_sprite_url IS NULL
   AND sprite_url LIKE '%/pokemon/%';
