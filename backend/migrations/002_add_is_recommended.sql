-- Add is_recommended column to hunt_methods table.
-- The seed_fulldex Go script is responsible for populating this flag
-- based on the human-curated FullDexMethods.csv.
ALTER TABLE hunt_methods ADD COLUMN IF NOT EXISTS is_recommended BOOLEAN NOT NULL DEFAULT FALSE;
