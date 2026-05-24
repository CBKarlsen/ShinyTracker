## 1. Refactor State and Toggle Logic

- [x] 1.1 Fix the owned-toggle bug: implement a DELETE or toggle-off call so clicking an owned card removes it from the collection
- [x] 1.2 Update `handleToggle` (or add a separate `handleOwnershipToggle`) to handle both adding and removing owned games
- [x] 1.3 Ensure removing ownership also clears the Shiny Charm state locally and via API

## 2. Build Card Grid Layout

- [x] 2.1 Replace `<List>` / `<ListItem>` JSX with a `<Grid container>` wrapper in `CollectionManager.tsx`
- [x] 2.2 Create a `GameCard` sub-component (or inline) that accepts `game`, `isOwned`, `hasCharm`, and callbacks
- [x] 2.3 Add responsive grid breakpoints: `xs={6} sm={4} md={3}` per card
- [x] 2.4 Apply owned vs. unowned visual styles: full opacity + colored border when owned, `opacity: 0.45` when unowned

## 3. Generation Grouping

- [x] 3.1 Group the `games` array by `generation` before rendering
- [x] 3.2 Sort groups in ascending generation order
- [x] 3.3 Render a `Typography` section header ("Generation I", "Generation II", etc.) above each group

## 4. Shiny Charm Icon Button

- [x] 4.1 Add a Shiny Charm `IconButton` (star/sparkle icon) to each card
- [x] 4.2 Style the button: gold/active color when charm is obtained, muted when not
- [x] 4.3 Disable the button when the game is not owned
- [x] 4.4 Wire click handler to call `handleToggle` for charm state change

## 5. Visual Polish

- [x] 5.1 Ensure card click target covers the whole card (not just the icon button)
- [x] 5.2 Add `cursor: pointer` on cards and a subtle hover effect
- [x] 5.3 Verify the layout on narrow viewports (mobile 2-per-row)
