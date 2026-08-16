-- Widen pokemon_moves.method to include 'train'.
--
-- Champions is battle-only: no overworld, no levelling, no TMs. Every move a
-- Champions Pokemon has is acquired by training rather than by level-up,
-- machine, egg, or tutor -- verified against PokeAPI for multiple species,
-- 100% of their champions-version-group moves report learn method "train".
-- The four-value vocabulary this CHECK enforced was a fact about the
-- mainline games (Platinum, Scarlet/Violet), not a fact about Pokemon in
-- general, and Champions is the first game we seed that doesn't fit it.
--
-- Do NOT apply this migration yet -- coordinator holds that step.
ALTER TABLE pokemon_moves DROP CONSTRAINT IF EXISTS pokemon_moves_method_check;
ALTER TABLE pokemon_moves ADD CONSTRAINT pokemon_moves_method_check
    CHECK (method IN ('level-up', 'tm', 'egg', 'tutor', 'train'));
