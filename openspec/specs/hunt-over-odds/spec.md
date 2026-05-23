## Requirements

### Requirement: Hunt card detects over-odds state
The hunt card SHALL compute whether the hunt has exceeded expected encounters. A hunt is over-odds when `encounter_count > expected_encounters`. This computation SHALL use the optimistic local count so the state snaps immediately on increment.

#### Scenario: Hunt reaches over-odds threshold
- **WHEN** the displayed encounter count exceeds the computed expected encounters
- **THEN** the card enters over-odds state immediately

#### Scenario: Hunt has no odds data
- **WHEN** odds data is null (manual acquisition)
- **THEN** over-odds state is never applied

### Requirement: Over-odds card has a distinct visual state
When a hunt is over-odds, the card SHALL display: an orange border, a "🔥 OVER ODDS" badge in the card header area, and a shifted background color distinct from the normal card background. The transition SHALL be instantaneous (no animation or fade).

#### Scenario: Normal hunt card
- **WHEN** `encounter_count` is at or below expected encounters
- **THEN** card uses the standard border (`colors.border`) and background (`colors.bgPaper`)

#### Scenario: Over-odds hunt card
- **WHEN** `encounter_count` exceeds expected encounters
- **THEN** card border is orange (`rgba(251, 146, 60, 0.6)`), background shifts to a warm dark tone, and "🔥 OVER ODDS" badge is visible near the Pokemon name

#### Scenario: Over-odds badge content
- **WHEN** a hunt is over-odds
- **THEN** the badge shows "🔥 OVER ODDS" as text (no additional counter or percentage)
