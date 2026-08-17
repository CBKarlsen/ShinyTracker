-- Champions is battle-only: no overworld, no wild encounters, no shiny hunting.
-- Its games row and its 208 pokemon_availability rows exist so the team builder
-- can scope a roster and a learnset, NOT so it can be hunted. Every hunt-facing
-- query reads this flag rather than hardcoding an id, so the next battle-only
-- title is one INSERT rather than a grep.
ALTER TABLE games ADD COLUMN IF NOT EXISTS supports_hunting BOOLEAN NOT NULL DEFAULT TRUE;
UPDATE games SET supports_hunting = FALSE WHERE title = 'Pokemon Champions';
