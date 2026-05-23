## Why

Users currently have no way to calculate shiny odds or browse encounter methods without starting an actual hunt. Adding a dedicated Odds Calculator and Method Library to the left sidebar gives users a quick-reference tool for planning hunts and comparing methods at a glance.

## What Changes

- Add two new collapsible sections to the left sidebar, below the existing Stats panel:
  - **Odds Calculator**: Input fields for game, method, and optional Shiny Charm toggle — displays live calculated odds and expected encounter count.
  - **Method Library**: Browseable list of all encounter methods grouped by game, showing each method's base rolls, charm rolls, and average time.
- No existing features are removed or broken.

## Capabilities

### New Capabilities

- `odds-calculator`: Standalone calculator widget in the sidebar; user picks a game and method, toggles Shiny Charm, and sees computed odds (fraction + percentage) and ETA estimate.
- `method-library`: Browseable, filterable reference list of all encounter methods across games; shows base rolls, charm rolls, avg time per encounter, and whether the method is recommended.

### Modified Capabilities

- `hunt-odds-display`: The underlying odds/calc logic (`internal/calc/odds.go`) will be reused by the new Odds Calculator endpoint — no behavioral change to the hunt display itself, but the API surface expands.

## Impact

- **Frontend**: New `OddsCalculator.tsx` and `MethodLibrary.tsx` components added to `src/components/`; `Sidebar.tsx` updated to render them below `Stats`.
- **Backend**: New `GET /api/methods` endpoint returning all encounter methods (optionally filtered by `?game_id=`); new `GET /api/odds` endpoint accepting `encounter_id` + `shiny_charm` and returning computed odds.
- **No schema changes**: All data is already in the `encounters` table.
- **No breaking changes**.
