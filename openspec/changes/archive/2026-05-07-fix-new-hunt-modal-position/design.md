## Context

`NewHuntModal` renders an MUI `Modal` with a hand-rolled `style` object that positions the box with `position: absolute`, `top: 50%`, `left: 50%`, and `transform: translate(-50%, -50%)`. This geometric-center approach works on large viewports but:
- Clips content at the bottom on short viewports (the `maxHeight: 85vh` guard is present but overflow behaviour is tied to the outer box, not a scrollable inner body).
- Feels visually low on tall screens where the eye naturally rests slightly above center.
- Is not idiomatic MUI — the `Dialog` component handles all of this natively.

## Goals / Non-Goals

**Goals:**
- Modal feels naturally centered and visually balanced on all common viewport sizes.
- Content scrolls inside the modal body (action buttons stay visible) on short viewports.
- Change is isolated to `NewHuntModal.tsx` — no other component is touched.

**Non-Goals:**
- Responsive breakpoint overhaul or mobile layout redesign.
- Animations / transition changes.
- Any backend or data-model work.

## Decisions

### Decision: Switch from `Modal` to `Dialog`

MUI `Dialog` is built on top of `Modal` and manages centering, scroll containment, and focus trap automatically. Replacing the bare `Modal` + custom style object with `Dialog` eliminates the positioning hack and gives us `scroll="paper"` for free.

**Alternative considered:** Keep `Modal`, fix `sx` with a flex layout (`display: flex; align-items: center; justify-content: center`). This works but requires re-implementing what `Dialog` already provides and is harder to maintain.

**Chosen:** Use `Dialog` with `maxWidth="sm"` (≈600 px) and `fullWidth`, which matches the current 500 px feel while being responsive.

### Decision: Shift content 4% above geometric center

MUI `Dialog` by default centers vertically. Adding `sx={{ '& .MuiDialog-container': { alignItems: 'flex-start', paddingTop: '8vh' } }}` (or `PaperProps` top margin) nudges the dialog slightly above the mathematical midpoint, which is the standard optical correction used in most design systems.

**Alternative:** Leave at geometric center. Fine for most viewports but feels slightly low on landscape laptop screens.

**Chosen:** Small upward shift via `PaperProps={{ sx: { mt: '6vh' } }}`.

## Risks / Trade-offs

- [Visual regression in existing screenshots/tests] → No automated visual tests exist; manually verify at 1280×800, 1920×1080, and mobile (375×812).
- [Dialog vs Modal API mismatch] → `Dialog` accepts `open`/`onClose` just like `Modal`; props are compatible. Internal content (Box, Typography, etc.) is unchanged.

## Migration Plan

1. Replace `import { ..., Modal, ... }` with `import { ..., Dialog, DialogContent, ... }` in `NewHuntModal.tsx`.
2. Delete the `const style = { ... }` object.
3. Wrap content with `<Dialog>` / `<DialogContent>` instead of `<Modal><Box sx={style}>`.
4. Add `PaperProps={{ sx: { borderRadius: 4, p: 2, mt: '6vh' } }}` to preserve the current look.
5. Smoke-test the modal at multiple viewport sizes.
