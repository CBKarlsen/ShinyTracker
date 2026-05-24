## Context

`CollectionManager.tsx` renders a flat MUI `<List>` of all Pokemon games (~20+ entries) with `<Switch>` controls for "Owned" and "Shiny Charm". The component already fetches the correct data from two endpoints and handles optimistic state updates. The redesign is purely a frontend UI change — no API work needed.

## Goals / Non-Goals

**Goals:**
- Replace switch-list with a scannable card grid grouped by generation
- Make owned vs. unowned status visually obvious at a glance
- Keep click-to-own as the primary interaction; charm toggle secondary
- Retain all existing API calls and state logic

**Non-Goals:**
- Searching or filtering games by name
- Adding game box art or cover images
- Any backend or API changes

## Decisions

**Card grid over list rows**
Each game becomes an MUI `<Card>` in a `<Grid>` layout. Cards make better use of horizontal space and allow visual differentiation (opacity, border color) without extra text labels.

**Generation grouping via labeled sections**
Games are grouped under a `Typography` header per generation (e.g., "Generation I"). Groups are sorted numerically. This breaks the list into ~9 manageable chunks instead of one wall of rows.

**Click-card = toggle ownership**
Removes the dedicated "Owned" switch. The whole card is clickable. Owned cards get a colored border (primary color) and full opacity; unowned cards are dimmed (`opacity: 0.45`). This mirrors the Collection tab's click-to-toggle pattern.

**Shiny Charm as an icon button on the card**
A small star/sparkle `IconButton` sits in the card's action area. It is disabled when the game is unowned and visually active (gold color) when the charm is obtained. Keeps charm management accessible without a separate switch label.

**No breaking changes to state logic**
`handleToggle` already handles both owned-toggle and charm-toggle cases via the POST endpoint. The refactor only changes the JSX rendering layer.

## Risks / Trade-offs

- [Risk] Many games per generation (Gen 3 especially) → cards may wrap awkwardly on small screens → Mitigation: use `xs={6} sm={4} md={3}` grid breakpoints so cards stay compact
- [Risk] "Unowning" a game (removing it) — the current code has a bug where the Owned switch can only toggle on, not off → this redesign will fix that by implementing a proper delete call to the API or toggling the owned state correctly

## Open Questions

- Should unowned games be hidden behind a "Show all games" toggle to reduce clutter further? (Not in scope for this change — can be a follow-up.)
