## Why

Shiny hunting is measured in time as much as encounters — users want to know how many hours they've actually invested in a hunt, not just a raw click count. The current hunt card also has no sense of probability context: users have no way to know when they've crossed the "expected" odds threshold, which is one of the most emotionally significant moments in the hobby.

## What Changes

- Add `total_time_seconds` column to `user_hunts`; PATCH endpoint accumulates active hunting time using a 10-minute inactivity threshold
- GET `/api/hunts` returns encounter odds data (`base_rolls`, `charm_rolls`, `avg_time_seconds`, `base_odds`) and `has_shiny_charm` so the frontend can compute expected encounters and estimated time
- Hunt cards drop the progress bar and display "Hunted: X h Y m" and "Expected: ~Y h" instead
- When `encounter_count` crosses the expected-encounters threshold, the card snaps into a distinct over-odds visual state (orange border, 🔥 OVER ODDS badge, shifted background)
- Hunts with no `encounter_id` (manual acquisitions) skip odds-dependent displays

## Capabilities

### New Capabilities

- `hunt-active-timer`: Tracks cumulative active hunting time per hunt, persisted to the database and displayed on hunt cards
- `hunt-odds-display`: Computes and surfaces expected encounters and expected time on each hunt card, using encounter odds data from the backend
- `hunt-over-odds`: Detects when a hunt has crossed expected odds and applies a distinct visual state to the card

### Modified Capabilities

<!-- none -->

## Impact

- **Database**: `user_hunts` table gains `total_time_seconds INT NOT NULL DEFAULT 0`
- **Backend**: `GetHuntsHandler` query extended; `PatchHuntHandler` gains time-accumulation logic
- **Frontend**: `Dashboard.tsx` — `Hunt` interface updated, progress bar removed, new stat rows and over-odds styling added
- **No breaking API changes**: new fields added to existing response shape
