## Context

Hunt cards currently display encounter count and a progress bar hardcoded to 4096. The backend has all odds data (`base_rolls`, `charm_rolls`, `base_odds`, `avg_time_seconds`) but never returns it from the hunts endpoint. There is no mechanism to track how long a user has actually spent hunting.

The PATCH endpoint already updates `updated_at` on every encounter increment. This timestamp is the natural anchor for time accumulation.

## Goals / Non-Goals

**Goals:**
- Persist cumulative active hunting time per hunt in the database
- Expose odds data through the existing GET /api/hunts endpoint
- Display hunted time and expected time on each hunt card
- Snap hunt cards into a visually distinct over-odds state at the expected-encounters threshold

**Non-Goals:**
- Per-session breakdowns (only total cumulative time)
- Live ticking clock during a session (time is committed on PATCH)
- Encounter rate or encounters-per-hour analytics
- Notification or push alerts when over odds is reached

## Decisions

### D1: Time accumulation on PATCH, not a separate endpoint

**Decision**: Accumulate `total_time_seconds` as a side-effect of the existing PATCH handler, using `now - updated_at` as the delta when the gap is under 600 seconds.

**Alternatives considered**:
- Dedicated session start/stop endpoints — more precise but adds significant complexity (session state, abandoned sessions, concurrent tabs)
- Client-sent elapsed time — simpler but trivially spoofable and requires client-side clock management

**Rationale**: `updated_at` is already maintained by the PATCH handler's `CURRENT_TIMESTAMP`. No new endpoints, no client-side timekeeping. The 10-minute threshold handles the common case (putting the Switch down, checking phone) without counting genuine breaks between sessions.

### D2: No migration framework — raw SQL migration file

**Decision**: Add `total_time_seconds` via a SQL file in `backend/migrations/` run with `go run ./cmd/migrate_recommended/main.go` (the existing migration runner pattern).

**Rationale**: The project has no ORM or migration framework; `schema.sql` is the DDL reference and changes are applied manually. Consistent with the existing `migrate_recommended` pattern.

### D3: Odds data joined in GetHuntsHandler, not a separate endpoint

**Decision**: Extend the existing SELECT to join `e.base_rolls`, `e.charm_rolls`, `e.avg_time_seconds`, `g.base_odds`, and `ug.has_shiny_charm`.

**Rationale**: All required fields are already reachable via the existing JOINs or a single new LEFT JOIN on `user_games`. Keeping it in one query avoids a second round-trip.

### D4: Over-odds computed on the frontend

**Decision**: Frontend computes `expectedEncounters = base_odds / (base_rolls + (hasShinyCharm ? charm_rolls : 0))` and compares to `encounter_count`.

**Rationale**: Pure arithmetic with no side effects. No reason to push this to the backend; keeping it frontend-only avoids a new API field and lets the UI react instantly to optimistic count updates.

### D5: No gradual visual transition — single snap at 100% odds

**Decision**: Card switches state once, when `encounter_count > expectedEncounters`. No gradient or multi-stage escalation.

**Rationale**: The user explicitly requested a "clear moment" rather than gradual transition. A single threshold is simpler to implement and more impactful as a UI event.

## Risks / Trade-offs

- **Clock skew on rapid PATCH bursts**: The debounce fires after 1.5s, so consecutive PATCHes are at minimum ~1.5s apart. `now - updated_at` will be small (~1.5s) and accumulated faithfully. No risk of double-counting.
- **First PATCH on a hunt**: `updated_at` equals `created_at` at hunt creation. The first PATCH delta could be hours if the user creates a hunt but doesn't start clicking immediately. The 600s threshold mitigates this — gaps > 10 min are ignored, so only the first 10 minutes could incorrectly be counted at most.
- **Hunts with no encounter_id**: Manual/MANUAL_OVERRIDE acquisitions have null encounter data. Frontend must null-guard before rendering odds-dependent UI elements.
- **`user_games` LEFT JOIN**: If a user never registered a game in `user_games`, `has_shiny_charm` will be null. Treat null as false.

## Migration Plan

1. Add migration SQL file: `ALTER TABLE user_hunts ADD COLUMN IF NOT EXISTS total_time_seconds INT NOT NULL DEFAULT 0;`
2. Run via existing migration runner
3. Deploy backend (new fields are additive — old frontend continues to work)
4. Deploy frontend
5. Rollback: column is additive, old code ignores it; frontend rollback simply stops reading the field
