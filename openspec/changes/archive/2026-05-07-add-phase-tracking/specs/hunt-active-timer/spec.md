## MODIFIED Requirements

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
