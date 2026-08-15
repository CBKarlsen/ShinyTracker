import SwiftUI

/// Design tokens transcribed from `docs/design/hunt-prototype.dc.html` — the owner's own
/// mobile-native design, which is the spec.
///
/// Nearly every value here is a literal that appears in that file's inline styles. Nothing is
/// derived from `frontend/src/index.css`: the native design is not the web design.
///
/// The exceptions are marked at their declaration and are all accessibility corrections the
/// prototype could not have caught, because a design file is looked at on a bright monitor at
/// arm's length rather than on a phone in a car: ``Palette/textFaint``, ``Palette/textDisabled``
/// (contrast) and ``Metrics/controlNarrow`` (tap target). When re-transcribing from the
/// prototype, do not "fix" these back.

// MARK: - Colour

extension Color {
    /// `0xRRGGBB`, exactly as written in the design file.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// The prototype tints by appending two hex digits to the accent — `${accent}55`,
    /// `${accent}88`. Same thing, spelled as an alpha fraction.
    public func alpha(_ byte: UInt8) -> Color { opacity(Double(byte) / 255) }
}

public enum Palette {
    // --- ground ---
    /// The device body behind everything: `background:#060608`.
    public static let screen = Color(hex: 0x060608)
    /// Ink on a gold/accent fill: `color:#060608`.
    public static let onAccent = Color(hex: 0x060608)

    // --- surfaces ---
    /// Cards, header buttons, history rows: `background:#111118`.
    public static let surface = Color(hex: 0x111118)
    /// Controls sitting on a card — −, ×N, ✦, timer badge: `background:#181822`.
    public static let surfaceRaised = Color(hex: 0x181822)
    /// The empty-state panel, darker than a card: `background:#0b0b10`.
    public static let surfaceSunken = Color(hex: 0x0B0B10)
    /// The emphasised (live) hunt card: `background:#17151b`.
    public static let surfaceLive = Color(hex: 0x17151B)
    /// A block inside the species sheet — stats, weaknesses, locations: `background:#0f0f15`.
    public static let surfaceBlock = Color(hex: 0x0F0F15)
    /// The bottom sheet itself: `background:#141419`.
    public static let sheet = Color(hex: 0x141419)

    // --- lines ---
    /// The 1px card outline and the progress track: `#1a1a22`.
    public static let hairline = Color(hex: 0x1A1A22)
    /// Control outlines: `inset 0 0 0 1px #25252f`.
    public static let border = Color(hex: 0x25252F)
    /// The ×N chip at step 1: `inset 0 0 0 1px #33333f`.
    public static let borderChip = Color(hex: 0x33333F)

    // --- text ---
    /// Titles, species names, the count: `#f4f2ec`.
    public static let textPrimary = Color(hex: 0xF4F2EC)
    /// The card meta line and inactive tab-bar glyphs: `#b6b5c0`.
    public static let textSecondary = Color(hex: 0xB6B5C0)
    /// Labels, hints, odds, the segmented control's off state: `#8a8896`.
    public static let textMuted = Color(hex: 0x8A8896)
    /// The quietest tier — history timestamps, the Dex scope note, Nuzlocke chapter summaries.
    ///
    /// **Deliberately not the prototype's `#44444e`.** That value is 1.83:1 against ``surface``,
    /// under half of WCAG's 4.5:1 and below even the 3:1 floor for large text — and this tier is
    /// not decoration: a timestamp saying when a hunt ended is content. Lightened to the darkest
    /// grey that still clears 3:1, which keeps it visibly the quietest tier without making it
    /// unreadable in daylight or to anyone over about forty.
    public static let textFaint = Color(hex: 0x6E6E7A)
    /// − at count 0. Also lightened from the prototype's `#3a3a44` (1.57:1 on ``surfaceRaised``,
    /// the ground it actually sits on), for the same reason: a disabled control still has to be
    /// *findable*, or the user cannot tell a greyed-out button from empty card background and
    /// reads the row as missing rather than as merely unavailable.
    ///
    /// WCAG exempts inactive components from the contrast minimum, so this one is a judgement
    /// call rather than a rule; it is held to the same 3:1 anyway. That squeezes the gap to
    /// ``textFaint`` (3.5:1) — the two tiers are close now, which is fine because nothing renders
    /// them side by side: this token has exactly one use site. It stays far below the *enabled*
    /// − (``textSecondary``, ~8:1), which is the distinction that has to survive.
    public static let textDisabled = Color(hex: 0x646470)

    // --- mode accents: "Each mode owns a colour, so you always know where you are." ---
    /// Hunt. The default of the prototype's `accent` prop.
    public static let hunt = Color(hex: 0xF5C661)
    /// Nuzlocke.
    public static let nuzlocke = Color(hex: 0x7B9BFF)
    /// Team.
    public static let team = Color(hex: 0x6EE7A2)
    /// Dex — the same bone white as primary text.
    public static let dex = Color(hex: 0xF4F2EC)

    // --- base-stat bars: `v >= 90 ? '#6ee7a2' : v >= 60 ? '#f5c661' : '#ff7373'` ---
    /// A weak base stat. The only red in the palette; the other two tiers are ``team``/``hunt``.
    public static let statLow = Color(hex: 0xFF7373)

    /// The bar colour for a stat value, per the prototype's ternary above.
    public static func statBar(_ value: Int) -> Color {
        value >= 90 ? team : value >= 60 ? hunt : statLow
    }

    // --- sheets --- (the sheet background itself is ``sheet``, above)
    /// The search field inside a sheet: `background:#0d0d12`.
    public static let field = Color(hex: 0x0D0D12)
    /// The key/value panel on the Ready and confirm sheets: `background:#0f0f15`.
    public static let detailPanel = Color(hex: 0x0F0F15)
    /// The gold-glowing summary card on the Ready step: `background:#15131a`.
    public static let confirmCard = Color(hex: 0x15131A)
    /// The armed "this deletes the hunt" state: `color:#ff7373`.
    public static let danger = Color(hex: 0xFF7373)

    // --- sprite tile ---
    /// The plate behind every sprite, so a row never renders as an empty hole while the image
    /// loads or 404s.
    ///
    /// The prototype fills it with `radial-gradient(circle at 50% 42%,#23232f 0%,#14141c 72%)`.
    /// Flat here, at the gradient's *centre* value rather than its average: the plate has to stay
    /// legible on ``surfaceLive`` (#17151B) as well as on ``surface``, and the average (~#1B1B25)
    /// disappears against the live card — the one card you look at most.
    public static let spriteTile = Color(hex: 0x23232F)

}

// MARK: - Radius

public enum Radii {
    /// Hunt card: `border-radius:20px`.
    public static let card: CGFloat = 20
    /// The −, +1, ×N and ✦ row: `border-radius:15px`.
    public static let control: CGFloat = 15
    /// Header search / + buttons: `border-radius:14px`.
    public static let headerButton: CGFloat = 14
    /// Empty-state panel: `border-radius:14px`.
    public static let panel: CGFloat = 14
    /// Empty-state icon tile: `border-radius:16px`.
    public static let iconTile: CGFloat = 16
    /// Segmented control shell: `border-radius:12px`.
    public static let segment: CGFloat = 12
    /// Selected segment: `border-radius:9px`.
    public static let segmentItem: CGFloat = 9
    /// Timer badge, and a sheet's close button: `border-radius:11px`.
    public static let badge: CGFloat = 11
    /// Bottom sheet: `border-radius:26px 26px 0 0`.
    public static let sheet: CGFloat = 26
    /// Game / method cards and the key-value panel inside a sheet: `border-radius:16px`.
    public static let listCard: CGFloat = 16
    /// Search results, history rows, secondary sheet buttons: `border-radius:15px`.
    public static let row: CGFloat = 15
    /// The Shiny Charm tag on a game row: `border-radius:8px`.
    public static let tag: CGFloat = 8
    // No `bar` radius token: the progress bar is drawn with `Capsule()`, which
    // self-rounds. The prototype's `border-radius:3px` on a 6px-tall bar is the
    // same shape, so a token would only be a second way to say it.
    /// Dex grid tile: `border-radius:14px`. Same number as ``panel``, kept separate because a
    /// 1,025-tile grid and a 52px-padded empty state have no reason to move together.
    public static let tile: CGFloat = 14
    /// A block inside the species sheet: `border-radius:16px`.
    public static let block: CGFloat = 16
    /// A type chip: `border-radius:7px`.
    public static let typeChip: CGFloat = 7
    /// Tab-bar pill: `border-radius:19px`.
    public static let pill: CGFloat = 19
    /// Sprite tile — the prototype computes `Math.round(size / 4)`.
    public static func sprite(_ size: CGFloat) -> CGFloat { (size / 4).rounded() }
}

// MARK: - Type

/// The prototype's font stack is `-apple-system, 'SF Pro Text', 'SF Pro Display', …` — i.e.
/// the system face, so every token below is `Font.system`.
///
/// **Text styles, not point sizes.** These were `Font.system(size:)` literals transcribed from the
/// prototype's CSS px, and a `Font` built from a raw size does not participate in Dynamic Type:
/// the whole app rendered at one fixed size no matter what the user had chosen in Settings, which
/// is an accessibility failure and, at the large accessibility sizes, an unusable app.
///
/// SwiftUI's only *relative* font constructor is `Font.custom(_:size:relativeTo:)`, which needs a
/// real font file name — there is no `Font.system(size:relativeTo:)`, so a system font at an
/// arbitrary point size cannot scale. The fix is therefore to say which text style each token *is*
/// and let SwiftUI supply the size. This costs nothing in fidelity, because at the default
/// (Large) content size the standard styles already are the prototype's numbers: `.title2` is 22,
/// `.headline` 17, `.subheadline` 15, `.footnote` 13, `.caption` 12, `.caption2` 11. Twenty-one of
/// these twenty-six tokens are pixel-identical to what shipped before.
///
/// The five that are not are noted individually below: `screenTitle` 30→28, `count` 26→28,
/// `sheetTitle` and `sheetHeadline` 24→22, `primaryButton` 18→17. None of them sit in a layout
/// where the 1–2pt shift is visible.
///
/// `.tracking` is separate from `.font` in SwiftUI, so the em-based letter-spacings the prototype
/// uses come back as the point values they resolve to at the *design* size. They stay fixed —
/// tracking is a typographic nicety, and scaling it buys nothing legible.
public enum Typography {
    /// `font:700 30px/1;letter-spacing:-.035em` — the "Hunt" screen title.
    /// `.title` is 28, not 30: the nearest style below `.largeTitle`'s 34.
    public static let screenTitle = Font.system(.title, weight: .bold)
    public static let screenTitleTracking: CGFloat = -0.035 * 30

    /// `font:700 22px/1;letter-spacing:-.02em` — species name on a hunt card.
    public static let cardTitle = Font.system(.title2, weight: .bold)
    public static let cardTitleTracking: CGFloat = -0.02 * 22

    /// `font:600 26px/1;letter-spacing:-.03em;font-variant-numeric:tabular-nums` — the count.
    /// `.title` is 28, not 26.
    public static let count = Font.system(.title, weight: .semibold).monospacedDigit()
    public static let countTracking: CGFloat = -0.03 * 26

    /// `font:500 12px/1;letter-spacing:.12em;text-transform:uppercase` — "ENCOUNTERS".
    public static let overline = Font.system(.caption, weight: .medium)
    public static let overlineTracking: CGFloat = 0.12 * 12

    /// `font:600 22px/1.2;letter-spacing:-.02em` — "No active hunts".
    public static let emptyTitle = Font.system(.title2, weight: .semibold)
    /// `font:400 15px/1.5` — the empty-state paragraph.
    public static let emptyBody = Font.system(.subheadline, weight: .regular)

    /// `font:400 13px/1.4` — the card meta line.
    public static let meta = Font.system(.footnote, weight: .regular)
    /// `font:400 13px/1` — odds and the cumulative-probability label.
    public static let stat = Font.system(.footnote, weight: .regular)
    /// `font:600 13px/1` — the same label once the count is past the odds.
    public static let statStrong = Font.system(.footnote, weight: .semibold)
    /// `font:500 13px/1` — the header's "2 hunts".
    public static let summary = Font.system(.footnote, weight: .medium)
    /// `font:400 12px/1.3` — the hint line under the segmented control.
    public static let hint = Font.system(.caption, weight: .regular)
    /// `font:600 13px/1;font-variant-numeric:tabular-nums` — the timer badge.
    public static let badge = Font.system(.footnote, weight: .semibold).monospacedDigit()
    /// `font:600 15px/1` (selected) / `font:500 15px/1` — segmented control and pill labels.
    public static let segmentOn = Font.system(.subheadline, weight: .semibold)
    public static let segmentOff = Font.system(.subheadline, weight: .medium)
    /// `font:700 24px/1;letter-spacing:-.03em` — the species sheet's name.
    /// `.title2` is 22, not 24 — `.title`'s 28 overshoots by more than this undershoots.
    public static let sheetTitle = Font.system(.title2, weight: .bold)
    public static let sheetTitleTracking: CGFloat = -0.03 * 24

    /// `font:500 11px/1;letter-spacing:.14em;text-transform:uppercase` — "BASE STATS", and the
    /// Dex grid's per-generation section headers.
    public static let blockLabel = Font.system(.caption2, weight: .medium)
    public static let blockLabelTracking: CGFloat = 0.14 * 11

    /// `font:600 13px/1` — the species name on a Dex tile.
    public static let tileName = Font.system(.footnote, weight: .semibold)
    /// `font:400 11px/1` — the line under it ("Registered", "#443", "2,847 enc").
    public static let tileSub = Font.system(.caption2, weight: .regular)

    /// `font:600 18px/1` — the wide gold "+1 encounter" button.
    /// `.headline` is 17, not 18, and is already semibold at that size.
    public static let primaryButton = Font.system(.headline, weight: .semibold)
    /// `font:600 15px/1` — the ×N chip.
    public static let chip = Font.system(.subheadline, weight: .semibold)

    /// `font:700 24px/1;letter-spacing:-.03em` — the species on the Ready card, and "Found X?"
    /// on the confirm sheet. The two are the same type at the same size in the prototype.
    /// Same 22-for-24 substitution as ``sheetTitle``.
    public static let sheetHeadline = Font.system(.title2, weight: .bold)
    public static let sheetHeadlineTracking: CGFloat = -0.03 * 24

    /// `font:600 17px/1` — a row's headline inside a sheet or the History list: species,
    /// game title, method name.
    public static let listTitle = Font.system(.headline, weight: .semibold)
    /// `font:600 17px/1;font-variant-numeric:tabular-nums` — the gold odds on a method card.
    public static let oddsValue = Font.system(.headline, weight: .semibold).monospacedDigit()
    /// `font:400 15px/1` — the left-hand label of a key/value row.
    public static let rowLabel = Font.system(.subheadline, weight: .regular)
    /// `font:600 15px/1;font-variant-numeric:tabular-nums` — its right-hand value.
    public static let rowValue = Font.system(.subheadline, weight: .semibold).monospacedDigit()
    /// `font:600 13px/1` — the Shiny Charm tag on a game row.
    public static let tag = Font.system(.footnote, weight: .semibold)
}

// MARK: - Metrics

/// The handful of sizes the Hunt screen repeats. Anything used once stays inline at its
/// use site rather than becoming a token nobody can place.
public enum Metrics {
    /// `padding:8px 18px 0` on the screen column.
    public static let screenPadding: CGFloat = 18
    /// `gap:13px` between the header, segmented control and list.
    public static let screenGap: CGFloat = 13
    /// `gap:10px` between hunt cards.
    public static let cardGap: CGFloat = 10
    /// `padding:16px` inside a hunt card.
    public static let cardPadding: CGFloat = 16
    /// `width:44px;height:44px` — header buttons. Also the iOS minimum tap target.
    public static let headerButton: CGFloat = 44
    /// `height:54px` — the increment row.
    public static let controlHeight: CGFloat = 54
    /// The −, ×N and ✦ buttons. The prototype says `width:42px`; 44 here, because 44×44 is
    /// Apple's minimum tap target and these three are hit repeatedly, one-handed, by someone
    /// looking at a game and not at the phone. ``headerButton`` was already 44 for the same reason.
    public static let controlNarrow: CGFloat = 44
    /// `width:62px;height:62px` — the hunt-card sprite.
    public static let cardSprite: CGFloat = 62
    /// `height:6px` — the progress bar.
    public static let barHeight: CGFloat = 6
}
