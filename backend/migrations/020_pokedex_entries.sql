-- 020_pokedex_entries.sql
--
-- Per-game regional Pokedex numbering. Until now pokemon_availability only
-- carried national ids, with no way to show a game's own dex order/number.
-- Seeded from PokeAPI /api/v2/pokedex/{slug} by cmd/seed_pokedex (idempotent).
--
-- A game can have multiple dexes (e.g. X/Y has Central/Coastal/Mountain
-- Kalos), so the key includes dex_slug, not just game_id + pokemon_id.
--
-- Purely additive: no existing column or row changes.

CREATE TABLE IF NOT EXISTS pokedex_entries (
  game_id      INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  dex_slug     TEXT NOT NULL,          -- PokeAPI pokedex slug, e.g. 'kalos-central'
  dex_name     TEXT NOT NULL,          -- display name, e.g. 'Central Kalos'
  dex_order    INTEGER NOT NULL,       -- ordering of dexes within a game (0-based)
  pokemon_id   INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
  entry_number INTEGER NOT NULL,       -- regional dex number within that dex
  PRIMARY KEY (game_id, dex_slug, pokemon_id)
);

CREATE INDEX IF NOT EXISTS idx_pokedex_entries_order
  ON pokedex_entries (game_id, dex_order, entry_number);

ALTER TABLE pokedex_entries ENABLE ROW LEVEL SECURITY;
