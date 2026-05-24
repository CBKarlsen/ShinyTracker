## 1. Database Migration

- [x] 1.1 Create migration SQL file `backend/migrations/add_total_time_seconds.sql` with `ALTER TABLE user_hunts ADD COLUMN IF NOT EXISTS total_time_seconds INT NOT NULL DEFAULT 0;`
- [x] 1.2 Run the migration against the database

## 2. Backend: Update Models

- [x] 2.1 Add `TotalTimeSeconds int` field to `UserHuntDetail` struct in `internal/models/models.go`
- [x] 2.2 Add `BaseRolls`, `CharmRolls`, `AvgTimeSeconds`, `BaseOdds`, `HasShinyCharm` nullable fields to `UserHuntDetail`

## 3. Backend: Update GET /api/hunts

- [x] 3.1 Extend the SELECT in `GetHuntsHandler` to include `e.base_rolls, e.charm_rolls, e.avg_time_seconds, g.base_odds, h.total_time_seconds`
- [x] 3.2 Add `LEFT JOIN user_games ug ON ug.game_id = g.id AND ug.user_id = h.user_id` and include `ug.has_shiny_charm` in SELECT
- [x] 3.3 Update `rows.Scan(...)` call to scan all new fields into the `UserHuntDetail` struct

## 4. Backend: Update PATCH /api/hunts/:id

- [x] 4.1 In `PatchHuntHandler`, fetch `updated_at` from the existing hunt row before running the UPDATE
- [x] 4.2 Compute `delta = now - updated_at`; if `delta < 600s`, add delta to `total_time_seconds`
- [x] 4.3 Include `total_time_seconds = total_time_seconds + $N` in the UPDATE statement (conditionally, based on delta check)

## 5. Frontend: Update Hunt Interface and API Data

- [x] 5.1 Update the `Hunt` interface in `Dashboard.tsx` to add `total_time_seconds`, `base_rolls`, `charm_rolls`, `avg_time_seconds`, `base_odds`, `has_shiny_charm` (all nullable except `total_time_seconds`)

## 6. Frontend: Replace Progress Bar with Stats Display

- [x] 6.1 Remove the `LinearProgress` and percentage text from hunt cards
- [x] 6.2 Add a helper function `formatHuntedTime(seconds: number): string` that returns "X h Y m" or "Y m"
- [x] 6.3 Add a helper function `computeExpectedEncounters(hunt: Hunt): number | null` that returns null when odds data is missing
- [x] 6.4 Render "Hunted: X h Y m" row using `total_time_seconds`
- [x] 6.5 Render "Expected: ~Y h" row using `avg_time_seconds × expected_encounters / 3600`, null-guarded

## 7. Frontend: Over-Odds Visual State

- [x] 7.1 Add `isOverOdds` computed boolean per card: `displayCount > expectedEncounters` (null-safe)
- [x] 7.2 Apply conditional card styling when `isOverOdds`: orange border `rgba(251, 146, 60, 0.6)`, warm shifted background
- [x] 7.3 Render "🔥 OVER ODDS" badge in the card header area when `isOverOdds` is true
