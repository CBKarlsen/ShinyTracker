## MODIFIED Requirements

### Requirement: Encounters admin page
The admin encounters page SHALL allow the admin to search for a Pokémon by name, view its current encounter rows in a table, and add, edit, or delete rows inline. The page SHALL also include a CSV import section (see `admin-csv-import`) that operates independently of the per-Pokémon search flow.

#### Scenario: Search and load
- **WHEN** the admin types a Pokémon name and selects from results
- **THEN** the encounter table populates with that Pokémon's current rows

#### Scenario: Add new encounter
- **WHEN** the admin fills in the add-row form and submits
- **THEN** the new encounter appears in the table without a page reload

#### Scenario: Edit existing encounter
- **WHEN** the admin clicks edit on a row, modifies a field, and saves
- **THEN** the row updates in place

#### Scenario: Delete encounter
- **WHEN** the admin clicks delete on a row and confirms
- **THEN** the row is removed from the table

#### Scenario: CSV import section is visible without selecting a Pokémon
- **WHEN** the admin visits the encounters page
- **THEN** the CSV import section SHALL be visible and usable regardless of whether a Pokémon has been searched
