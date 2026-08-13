-- 019_add_hunt_writes.sql
--
-- Idempotency keys for relative encounter-count writes.
--
-- A delta is the only write model in which two offline sessions on one hunt
-- both survive (D1 names phone + Apple Watch as planned), but it is not
-- naturally idempotent: an offline queue retries by definition, and a "+500"
-- that lands twice invents 500 encounters. The client generates a UUID per
-- write and the server records the ones it has applied.
--
-- Written in the SAME transaction as the count update. Two transactions leave
-- a window where a crash between them either double-applies the delta or
-- loses it.
--
-- Purely additive: no existing column or row changes, and the absolute-count
-- path is untouched.

CREATE TABLE IF NOT EXISTS hunt_writes (
    write_id   UUID PRIMARY KEY,
    user_id    UUID NOT NULL,
    -- CASCADE, unlike the reference-data tables: these rows are meaningless
    -- once the hunt is gone, and a replayed write for a deleted hunt should
    -- fail on the hunt's own absence rather than dedupe against a ghost.
    hunt_id    UUID NOT NULL REFERENCES user_hunts(id) ON DELETE CASCADE,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hunt_writes_hunt ON hunt_writes (hunt_id);

ALTER TABLE hunt_writes ENABLE ROW LEVEL SECURITY;
