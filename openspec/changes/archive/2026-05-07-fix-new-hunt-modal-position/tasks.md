## 1. Replace Modal with Dialog

- [x] 1.1 In `NewHuntModal.tsx`, update the MUI import: replace `Modal` with `Dialog` and `DialogContent`
- [x] 1.2 Delete the `const style = { ... }` object (lines 18–30)
- [x] 1.3 Replace `<Modal open={open} onClose={onClose}>` and its inner `<Box sx={style}>` wrapper with `<Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth scroll="paper">`
- [x] 1.4 Add `PaperProps={{ sx: { borderRadius: 4, p: 2, mt: '6vh' } }}` to `<Dialog>` to preserve border-radius and shift content slightly above center
- [x] 1.5 Wrap the modal body content in `<DialogContent>` (replacing the now-removed `<Box sx={style}>`)
- [x] 1.6 Close `</Dialog>` at the bottom (replacing `</Box></Modal>`)

## 2. Verify Scroll Behaviour

- [x] 2.1 Start the Vite dev server (`npm run dev` in `/frontend`) and open the New Hunt modal
- [ ] 2.2 Confirm the modal is centered (slightly above midpoint) on a standard 1280×800 viewport
- [ ] 2.3 Resize the browser to a short viewport (≈ 600 px tall) and confirm the modal body scrolls internally without the dialog overflowing the screen
- [ ] 2.4 Confirm the modal width is ≤ 600 px on a wide viewport
