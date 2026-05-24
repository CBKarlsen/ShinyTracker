# edit-hunt-parameters Specification

## Purpose
Defines editing the parameters of an active hunt and the backend API that accepts those updates.

## Requirements

### Requirement: Active hunts can update their parameters
The system SHALL allow users to modify the dynamic `hunt_parameters` of an active hunt and persist these changes via the `PATCH /api/hunts/:id` endpoint.

#### Scenario: User updates an outbreak count
- **WHEN** a user modifies the method parameters on an active hunt (e.g. changing Outbreak Defeats from 30 to 60)
- **THEN** a PATCH request is sent updating the `hunt_parameters` field
- **THEN** the UI reflects the updated configuration immediately

### Requirement: Backend API accepts parameters update
The `PATCH /api/hunts/:id` endpoint SHALL accept an optional `hunt_parameters` JSON field and update the database accordingly.

#### Scenario: Valid parameters provided
- **WHEN** the PATCH payload contains `hunt_parameters: {"defeats": 60}`
- **THEN** the `user_hunts` table is updated with the new JSON payload
- **THEN** the updated hunt object is returned
