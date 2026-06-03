-- Add PHASE to the acquisition_type CHECK constraint on user_hunts.
-- ORDERING GATE: apply this migration BEFORE deploying the LogPhaseHandler
-- change that writes 'PHASE' rows, or the INSERT will fail the constraint.
ALTER TABLE user_hunts DROP CONSTRAINT IF EXISTS user_hunts_acquisition_type_check;
ALTER TABLE user_hunts ADD CONSTRAINT user_hunts_acquisition_type_check
  CHECK (acquisition_type IN ('HUNTED', 'EVOLVED', 'MANUAL_OVERRIDE', 'TRADED', 'PHASE'));
