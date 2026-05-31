# ⌘K Pokémon Command Search — Design

**Date:** 2026-05-31
**Branch:** `shiny-charm-icon-and-pro-removal`
**Status:** Approved (design), pending implementation plan

## Problem

The topbar search box is decorative. It is a `readOnly` `<input>` with a `⌘K`
hint and no `value`/`onChange`/handler, so typing does nothing and the keyboard
hint is a lie. The app already has a working Pokémon search endpoint
(`GET /api/pokemon?q=…`, used by the New Hunt flow and the Phase modal), so the
backend need is already met — only the frontend was never built.

## Goal

Turn the topbar search into a real, keyboard-first **command-palette overlay**
that searches any Pokémon and lets the user act on a result. Confirmed scope
decisions (from brainstorming):

- **Searches:** Pokémon only (by name and dex number). Not hunts, not navigation.
- **Surface:** a centered ⌘K command-palette overlay, not an inline dropdown.
- **Primary action (Enter):** start a hunt for the highlighted Pokémon.
- **Secondary action:** view that Pokémon in the Living Dex.

### Non-goals (YAGNI)

- Searching active/historic hunts.
- Navigation/action commands in the palette ("go to Stats", etc.).
- Recent-search history or fuzzy ranking beyond what the API returns.

## Architecture

### New units

1. **`usePokemonSearch(query: string)` hook**
   `frontend/src/hooks/usePokemonSearch.ts` (or `features/search/`).
   - Input: a query string.
   - Output: `{ results: Pokemon[]; loading: boolean }`.
   - Debounces (~200ms), calls `GET ${API_BASE}/api/pokemon?q=<encoded>` with the
     auth header, ignores stale responses (request-sequence guard), returns `[]`
     for empty/whitespace query.
   - Purpose: remove the third copy of this fetch. `PhaseModal` and the New Hunt
     search step already duplicate it; this hook is the shared implementation.
     Targeted dedup — refactoring those two call sites onto the hook is optional
     and can be a follow-up, not required for this feature.

2. **`CommandSearch` component**
   `frontend/src/components/search/CommandSearch.tsx`.
   - Props: `{ open: boolean; onClose: () => void; onStartHunt: (p: Pokemon) => void; onViewInDex: (p: Pokemon) => void }`.
   - Renders nothing when `open` is false.
   - When open: a scrim (reuse `.scrim`) + a centered panel with a search input
     (autofocused), a results list, and footer hint row (`↑↓ move · ↵ start hunt
     · esc`). Uses `usePokemonSearch` for data.
   - Owns: query string state, highlighted-index state, keyboard handling.
   - Reuses existing `.poke-search-results` row styling where it fits; adds a
     small amount of palette-specific CSS in `index.css`.

### Changed units

3. **`App.tsx`** — owns the overlay's open/close state and global shortcut.
   - New `searchOpen` state.
   - Global `keydown` listener (mounted in an effect): `⌘K` / `Ctrl+K` toggles
     `searchOpen` and `preventDefault()`s the browser default. Ignore the
     shortcut when focus is in an input/textarea other than the palette itself.
   - Renders `<CommandSearch open={searchOpen} … />`.
   - `onStartHunt(p)`: set `huntPrefill` to a Pokémon-only prefill, open the New
     Hunt modal, close the palette.
   - `onViewInDex(p)`: `setRoute("dex")`, set a new `focusPokemonId` passed to
     `Collection`, close the palette.

4. **`Topbar.tsx`** — the search box becomes a trigger.
   - New prop `onOpenSearch: () => void`.
   - Replace the `readOnly` `<input>` with a `<button className="searchbox" …>`
     showing the placeholder text and the real `⌘K` kbd. Clicking opens the
     overlay. Keep the same visual styling (it already looks like a search box).
   - Works on mobile: tapping it opens the full-width overlay. (The topbar search
     is already fluid on mobile from the responsive pass.)

5. **`NewHuntModal.tsx`** — accept a Pokémon-only prefill.
   - Change `prefill` type to `{ pokemon: Pokemon; route?: PokemonRoute } | null`.
   - The existing effect that jumps to step 2 on prefill keeps working with just
     a Pokémon. When `route` is absent, the existing default-route-selection
     effect must run so a sensible route is preselected once routes load. (Today
     that effect is gated on `!prefill`; adjust it to run when there is a prefill
     without a route, i.e. gate on "no route chosen yet" rather than "no
     prefill".)
   - No change to the start-hunt POST logic.

6. **`App.tsx` `huntPrefill` type** — widen to allow a route-less prefill
   (`{ pokemon: Pokemon; route?: PokemonRoute }`). Existing Collection→start-hunt
   path keeps passing a full `{pokemon, route}`.

7. **`Collection.tsx`** — open a specific Pokémon's drawer from outside.
   - New optional prop `focusPokemonId?: number | null`.
   - An effect: when `focusPokemonId` changes to a non-null id, set the internal
     `drawerId` to it (opening that Pokémon's drawer). App is responsible for
     clearing `focusPokemonId` after handling so re-selecting the same Pokémon
     works (e.g. clear on drawer close or reset to null after a tick).

8. **`index.css`** — palette panel styling (centered modal, input row, results,
   highlighted row, footer hint), reusing tokens and `.scrim`. Respect design
   bans (no side-stripe, no gradient text, no `transition: all`, ease-out only).

## Data flow

```
user presses ⌘K  ──▶ App.searchOpen = true ──▶ <CommandSearch open>
user types       ──▶ usePokemonSearch(query) ──▶ GET /api/pokemon?q= ──▶ results[]
↑/↓              ──▶ move highlightedIndex
Enter            ──▶ onStartHunt(results[i]) ──▶ App sets huntPrefill + opens NewHuntModal + closes palette
View in Dex      ──▶ onViewInDex(results[i]) ──▶ App setRoute("dex") + focusPokemonId + closes palette
Esc / click-away ──▶ onClose()
```

## Interaction details

- **Open triggers:** ⌘K / Ctrl+K from anywhere; clicking the topbar search box.
- **Keyboard inside palette:** `↑/↓` move highlight (wrap at ends), `Enter` =
  start hunt for highlighted result, `Esc` = close. Secondary "View in Dex" is a
  visible button on the highlighted row; optionally also `⌘↵`.
- **Focus management:** autofocus the input on open; on close, return focus to the
  trigger (the topbar search button). Lock body scroll while open (match the
  existing modal/sheet approach).
- **States:** empty query (show a hint / nothing), loading ("Searching…"),
  no results ("No Pokémon found"), populated list (sprite + capitalized name +
  `#0000` dex number, mirroring `.poke-search-results .row`).
- **Mobile:** overlay panel is full-width (with margins) and usable with the
  on-screen keyboard; same component, responsive panel width.

## Error handling

- Fetch failures in `usePokemonSearch` resolve to an empty result set and clear
  `loading` (no crash, no error banner — search is low-stakes). Stale responses
  are discarded via a sequence/abort guard so fast typing can't show old results.

## Testing / verification

No test framework is configured in the project. Verification is manual:
- `npm run build` and `npm run lint` clean.
- Manual smoke (ideally at desktop + a 390px viewport): ⌘K opens, typing
  "gible" lists Gible/Gabite/Garchomp, ↑/↓ + Enter opens New Hunt prefilled,
  "View in Dex" opens the Dex drawer for that Pokémon, Esc closes and focus
  returns to the trigger.

## Risks / notes

- The default-route-selection change in `NewHuntModal` is the most behaviorally
  sensitive edit; the existing Collection→start-hunt path (which passes a full
  route) must remain unchanged. Implementation must verify both paths.
- `focusPokemonId` lifecycle must avoid a stuck-open drawer; App clears it after
  the drawer opens.
