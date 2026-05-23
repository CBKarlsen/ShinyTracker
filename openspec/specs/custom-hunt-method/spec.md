### Requirement: User can start a hunt with a custom method name
The system SHALL allow a user to create a hunt by providing a free-text `custom_method_name` instead of a `hunt_method_id`. A hunt with a custom method SHALL have no odds or ETA data.

#### Scenario: Hunt created with custom method
- **WHEN** the user submits a new hunt with `custom_method_name` set and `hunt_method_id` absent
- **THEN** a `user_hunts` row is inserted with `hunt_method_id = NULL` and `custom_method_name` set to the provided value

#### Scenario: Hunt created with curated method (unchanged)
- **WHEN** the user submits a new hunt with a valid `hunt_method_id`
- **THEN** a `user_hunts` row is inserted with `hunt_method_id` set and `custom_method_name = NULL`

#### Scenario: Hunt created with both fields rejected
- **WHEN** the user submits a new hunt with both `hunt_method_id` and `custom_method_name` present
- **THEN** the response SHALL be `400 Bad Request`

#### Scenario: Hunt created with neither field rejected
- **WHEN** the user submits a new hunt with neither `hunt_method_id` nor `custom_method_name`
- **THEN** the response SHALL be `400 Bad Request`

### Requirement: Dashboard displays custom method name
The system SHALL display `custom_method_name` on the active hunt card when no curated method is linked, with a visual indicator that odds data is unavailable.

#### Scenario: Custom hunt card shows method name
- **WHEN** an active hunt has `custom_method_name` set and `hunt_method_id` is null
- **THEN** the dashboard card SHALL display the custom method name as the method label

#### Scenario: Custom hunt card shows no odds
- **WHEN** an active hunt has `custom_method_name` set
- **THEN** the dashboard card SHALL display "Custom method — no odds data" in place of the odds/ETA row

### Requirement: NewHuntModal offers custom method fallback
The New Hunt modal SHALL present a "Use custom method" option at the bottom of the method list. When selected, a text input SHALL appear for the user to type their method name.

#### Scenario: Custom method option is always visible
- **WHEN** the user has selected a Pokémon and a game in the New Hunt modal
- **THEN** a "Use custom method" option SHALL appear below all curated methods

#### Scenario: Custom method requires non-empty name
- **WHEN** the user selects "Use custom method" and leaves the name input blank
- **THEN** the confirm button SHALL be disabled

#### Scenario: Hunt starts with custom method name
- **WHEN** the user selects "Use custom method", types a method name, and confirms
- **THEN** the hunt is created with `custom_method_name` equal to the typed value
