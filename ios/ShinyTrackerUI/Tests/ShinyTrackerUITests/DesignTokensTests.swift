import Testing
@testable import ShinyTrackerUI

/// Pins the palette to `docs/design/hunt-prototype.dc.html`.
///
/// The point is drift: a `Color` is opaque once built, so nothing else in the app can tell you
/// that a token stopped matching the design. Every literal below was copied out of an inline
/// `style` attribute in that file — if one of these fails, either the design changed and the
/// token should follow, or someone nudged a colour by hand and should not have.
struct DesignTokensTests {

    @Test("Mode accents match the prototype")
    func modeAccents() {
        // `accent` prop default + the three literals passed to pill() in renderVals().
        #expect(Palette.hunt.hex == 0xF5C661)
        #expect(Palette.nuzlocke.hex == 0x7B9BFF)
        #expect(Palette.team.hex == 0x6EE7A2)
        // Dex's colour IS primary text — pill(mode === 'dex', '#f4f2ec').
        #expect(Palette.dex.hex == 0xF4F2EC)
        #expect(Palette.dex.hex == Palette.textPrimary.hex)
    }

    @Test("Surfaces and text tiers match the prototype")
    func surfacesAndText() {
        #expect(Palette.screen.hex == 0x060608)
        #expect(Palette.surface.hex == 0x111118)
        #expect(Palette.surfaceRaised.hex == 0x181822)
        #expect(Palette.surfaceSunken.hex == 0x0B0B10)
        #expect(Palette.surfaceLive.hex == 0x17151B)
        #expect(Palette.hairline.hex == 0x1A1A22)
        #expect(Palette.border.hex == 0x25252F)

        #expect(Palette.textPrimary.hex == 0xF4F2EC)
        #expect(Palette.textSecondary.hex == 0xB6B5C0)
        #expect(Palette.textMuted.hex == 0x8A8896)
        #expect(Palette.textFaint.hex == 0x44444E)
    }

    @Test("Swatch decomposes hex into the right channels")
    func channels() {
        // 0xF5C661 -> 245, 198, 97. Guards the shift/mask, which a test pinning only `hex`
        // would never exercise — a swapped red/blue would otherwise pass everything above.
        let (r, g, b) = Palette.hunt.components
        #expect(r == 245.0 / 255)
        #expect(g == 198.0 / 255)
        #expect(b == 97.0 / 255)

        // The prototype tints by appending hex digits: `${accent}55`, `${accent}88`.
        #expect(Palette.hunt.alpha(0x55) == Palette.hunt.color.opacity(85.0 / 255))
    }

    @Test("Sheet surfaces match the prototype")
    func sheetSurfaces() {
        // Every `sc-if`-gated sheet in the prototype opens with these literals.
        #expect(Palette.sheet.hex == 0x141419)
        #expect(Palette.field.hex == 0x0D0D12)
        #expect(Palette.detailPanel.hex == 0x0F0F15)
        #expect(Palette.confirmCard.hex == 0x15131A)
        // `abandonStyle` — the only red in the file, and only once armed.
        #expect(Palette.danger.hex == 0xFF7373)
    }

    @Test("Card radii match the prototype")
    func radii() {
        #expect(Radii.card == 20)
        #expect(Radii.control == 15)
        #expect(Radii.segmentItem == 9)
        #expect(Radii.pill == 19)
        // sprite() mirrors `Math.round(size / 4)` — 62 -> 16 (15.5 rounds up), 44 -> 11.
        #expect(Radii.sprite(62) == 16)
        #expect(Radii.sprite(44) == 11)

        // `border-radius:26px 26px 0 0` on the sheet, 16 on the cards it holds, 15 on rows.
        #expect(Radii.sheet == 26)
        #expect(Radii.listCard == 16)
        #expect(Radii.row == 15)
        #expect(Radii.tag == 8)
    }
}
