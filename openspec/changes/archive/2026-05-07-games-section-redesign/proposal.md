## Why

The Games Owned section presents all Pokemon games as a flat switch-list, which is overwhelming (20+ rows) and relies on toggle switches that feel more like a settings form than a collection screen. Users want to quickly see which games they own and manage their Shiny Charm status without wading through every game ever released.

## What Changes

- Replace the `<List>` + `<Switch>` layout in `CollectionManager.tsx` with a card grid grouped by generation
- Owned games are visually prominent; unowned games are dimmed/muted
- Clicking a card toggles ownership (no separate "Owned" switch)
- A Shiny Charm badge/button on owned cards toggles charm status
- Games grouped under collapsible or labeled generation headers so the list feels manageable

## Capabilities

### New Capabilities
- `games-collection-grid`: Card-grid view for browsing and managing owned games, grouped by generation with click-to-own interaction and per-card Shiny Charm toggle

### Modified Capabilities

## Impact

- `frontend/src/components/CollectionManager.tsx` — full component rewrite
- No backend or API changes needed; existing endpoints (`/api/games`, `/api/user/:id/games`, `/api/user/:id/games/:gameId`) remain unchanged
- MUI components used will shift from `List/ListItem/Switch` to `Card/Grid`/`Chip`
