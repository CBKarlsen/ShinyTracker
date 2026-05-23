## Why

The "New Hunt" modal uses an `position: absolute` / `top: 50%` / `transform: translate(-50%, -50%)` pattern inside a MUI `Modal`, which hard-codes geometric center but ignores safe-area insets, clips content on short viewports, and can feel visually low on taller screens. A flex-based centering approach with a small upward bias and proper overflow handling will feel more natural.

## What Changes

- Replace the inline `style` object in `NewHuntModal.tsx` with MUI `Dialog` (or update the `Modal` `sx` to use flex layout), so the modal is centered via the component's built-in positioning system.
- Remove the absolute-positioning hack (`position: absolute`, `top: 50%`, `transform`) and rely on MUI's default centering.
- Add `scroll="paper"` (or equivalent `overflowY` guard) so the modal body scrolls internally on short viewports rather than clipping.
- Constrain max-height relative to viewport (`90vh`) and ensure padding is preserved at the bottom so action buttons are always visible.

## Capabilities

### New Capabilities

- `new-hunt-modal-layout`: Correct modal positioning and scroll behaviour for the New Hunt flow.

### Modified Capabilities

<!-- None — no existing spec-level requirements are changing. -->

## Impact

- `frontend/src/components/NewHuntModal.tsx` — only file changed.
- No API, backend, or schema changes.
- Visual regression possible; should be spot-checked at common viewport sizes (mobile, laptop, wide monitor).
