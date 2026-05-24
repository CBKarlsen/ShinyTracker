# new-hunt-modal-layout Specification

## Purpose
Defines the layout behavior of the New Hunt modal: native centering, internal scrolling on short viewports, and width matching the existing design.

## Requirements

### Requirement: Modal is centered using the framework's native centering mechanism
The New Hunt modal SHALL use MUI `Dialog` for positioning instead of a manually calculated `position: absolute` / `transform` style, so that centering is handled by the component system and remains correct across viewport sizes.

#### Scenario: Modal opens at center of viewport
- **WHEN** the user clicks the button to open a new hunt
- **THEN** the modal SHALL appear centered horizontally on the screen

#### Scenario: Modal is shifted slightly above geometric center
- **WHEN** the modal is open on a tall viewport (height > 700 px)
- **THEN** the modal SHALL appear slightly above the mathematical midpoint of the screen to match standard optical alignment

### Requirement: Modal content scrolls internally on short viewports
The New Hunt modal SHALL keep its header and action buttons visible at all times; only the middle content area SHALL scroll when the viewport height is insufficient to display all content.

#### Scenario: Content fits without scrolling on a standard laptop viewport
- **WHEN** the modal is open on a 1280×800 viewport
- **THEN** no scroll bar SHALL appear and all modal content SHALL be visible without scrolling

#### Scenario: Content scrolls inside the modal on a short viewport
- **WHEN** the modal is open on a viewport with height ≤ 600 px
- **THEN** the modal body SHALL scroll internally and the modal container SHALL NOT extend outside the visible screen area

### Requirement: Modal width matches existing design
The New Hunt modal SHALL remain approximately 500–600 px wide (MUI `sm` breakpoint) on desktop viewports so the visual design is unchanged.

#### Scenario: Modal width on desktop
- **WHEN** the modal is open on a viewport wider than 600 px
- **THEN** the modal SHALL be constrained to ≤ 600 px wide and centered horizontally
