## Requirements

### Requirement: Active hunting time is persisted per hunt
The system SHALL maintain a `total_time_seconds` integer on each hunt record, representing cumulative seconds the user has spent actively encountering Pokemon on that hunt. Only time between encounter increments that are separated by less than 600 seconds SHALL be counted.

#### Scenario: Time accumulated within a session
- **WHEN** a PATCH request updates `encounter_count` and the elapsed time since `updated_at` is less than 600 seconds
- **THEN** `total_time_seconds` is incremented by that elapsed duration

#### Scenario: Gap longer than inactivity threshold is ignored
- **WHEN** a PATCH request updates `encounter_count` and the elapsed time since `updated_at` is 600 seconds or more
- **THEN** `total_time_seconds` is NOT incremented (the break is not counted)

#### Scenario: First encounter on a new hunt
- **WHEN** a PATCH request is the first encounter increment after hunt creation and `created_at` equals `updated_at`
- **THEN** the time delta is evaluated against the 600-second threshold; if the hunt was just created it likely counts, if it was created much earlier the gap is ignored

### Requirement: Hunted time is returned by the hunts API
The GET `/api/hunts` response SHALL include `total_time_seconds` for each hunt.

#### Scenario: Hunt with accumulated time
- **WHEN** a user fetches their hunts
- **THEN** each hunt in the response includes a `total_time_seconds` field reflecting the persisted value

### Requirement: Hunt card displays hunted time
The hunt card SHALL display the accumulated hunting time in a human-readable format ("X h Y m" or "Y m" if under one hour). The card SHALL also display the current phase number (e.g. "Phase 2") when `phase_count` is greater than 0, and a collapsible or inline list of past phases showing the phase Pokémon sprite and the encounter count at which the phase occurred.

#### Scenario: Hunt with over an hour logged
- **WHEN** `total_time_seconds` is 8100
- **THEN** the card shows "Hunted: 2 h 15 m"

#### Scenario: Hunt with under an hour logged
- **WHEN** `total_time_seconds` is 1800
- **THEN** the card shows "Hunted: 30 m"

#### Scenario: Hunt with no time yet
- **WHEN** `total_time_seconds` is 0
- **THEN** the card shows "Hunted: 0 m" or omits the field

#### Scenario: Hunt with phases
- **WHEN** a hunt has `phase_count: 2` and two entries in `phases`
- **THEN** the card shows "Phase 3" (current phase = phase_count + 1) and lists the two prior phases with their Pokémon sprite and encounter count

#### Scenario: Hunt on first phase (no prior phases)
- **WHEN** a hunt has `phase_count: 0`
- **THEN** no phase indicator is shown on the card
