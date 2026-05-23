-- Rename encounters table to hunt_methods and update the FK column in user_hunts.
-- Run this once in Supabase SQL Editor.

ALTER TABLE encounters RENAME TO hunt_methods;
ALTER TABLE user_hunts RENAME COLUMN encounter_id TO hunt_method_id;
