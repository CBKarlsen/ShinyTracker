## MODIFIED Requirements

### Requirement: Odds API endpoint
The system SHALL expose `GET /api/odds?encounter_id=<id>&shiny_charm=<bool>` returning computed shiny odds for a given encounter method. It MAY accept an optional `hunt_parameters` JSON string parameter to compute odds dynamically for parameterized methods (like SOS Chaining or DexNav).

#### Scenario: Valid encounter with charm
- **WHEN** a request is made with a valid `encounter_id` and `shiny_charm=true`
- **THEN** the response includes `fraction` (e.g. "1/1365"), `percentage` (e.g. "0.073%"), `expected_encounters` (integer), and `eta_hours` (float, one decimal)

#### Scenario: Valid encounter without charm
- **WHEN** a request is made with a valid `encounter_id` and `shiny_charm=false`
- **THEN** the response includes correct odds computed using `base_rolls` only

#### Scenario: Valid encounter with hunt parameters
- **WHEN** a request is made with a valid `encounter_id` and `hunt_parameters` (e.g. `{"chain_length": 31}`)
- **THEN** the response reflects the correct odds factoring in the provided parameters

#### Scenario: Unknown encounter ID
- **WHEN** a request is made with an `encounter_id` that does not exist in the database
- **THEN** the response is `404 Not Found`

#### Scenario: Missing encounter_id parameter
- **WHEN** `encounter_id` is omitted from the request
- **THEN** the response is `400 Bad Request`
