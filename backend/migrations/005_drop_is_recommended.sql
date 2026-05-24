-- Remove the method-global is_recommended flag from hunt_methods.
-- A single boolean on the method row cannot express a per-Pokemon
-- recommendation (e.g. Poké Radar is invalid for water-only Pokemon),
-- so the feature is removed entirely.
ALTER TABLE hunt_methods DROP COLUMN IF EXISTS is_recommended;
