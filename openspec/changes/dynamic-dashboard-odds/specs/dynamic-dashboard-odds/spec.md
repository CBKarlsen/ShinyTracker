## ADDED Requirements

### Requirement: Dashboard Live Odds Calculation
The system SHALL display dynamically calculated live odds on the active hunt dashboard cards, matching the specific hunt method's formula scaling rather than falling back to static math.

#### Scenario: Displaying SV Outbreak Odds
- **WHEN** the user is viewing an active hunt using the `outbreak_defeats_sv` formula type on the dashboard
- **THEN** the live odds displayed MUST factor in the current encounter count according to the SV Outbreak scaling rules

#### Scenario: Displaying PokeRadar Odds
- **WHEN** the user is viewing an active hunt using the `radar_chain_gen4` formula type on the dashboard
- **THEN** the live odds displayed MUST factor in the current encounter count according to the Gen 4 PokéRadar chaining rules

### Requirement: Odds Curve Rendering
The system SHALL render the progression curve of the hunt (OddsCurve component) by cumulatively mapping the dynamic odds across encounter milestones, rather than assuming a fixed roll chance.

#### Scenario: Charting dynamic scaling
- **WHEN** the SVG path for the odds curve is generated
- **THEN** the system MUST use the `calculateOdds` utility at incremental encounter counts to plot the expected probability curve accurately
