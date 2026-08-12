import SwiftUI

/// Design tokens transcribed from `docs/design/hunt-prototype.dc.html` — the owner's own
/// mobile-native design, which is the spec.
///
/// Every value here is a literal that appears in that file's inline styles. Nothing is
/// derived from `frontend/src/index.css`: the native design is not the web design.
///
/// Colours keep their raw hex rather than becoming opaque `Color`s, because a `Color` cannot
/// be compared back to the value it was built from — `DesignTokensTests` pins the hex so the
/// palette cannot drift away from the prototype unnoticed.

// MARK: - Colour

/// One palette entry: the literal hex from the prototype, plus the `Color` built from it.
public struct Swatch: Equatable, Sendable {
    /// `0xRRGGBB`, exactly as written in the design file.
    public let hex: UInt32

    public init(_ hex: UInt32) { self.hex = hex }

    /// Split out from ``color`` so the shift/mask is assertable — a built `Color` is opaque.
    public var components: (red: Double, green: Double, blue: Double) {
        (
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }

    public var color: Color {
        let (r, g, b) = components
        return Color(red: r, green: g, blue: b)
    }

    /// The prototype tints by appending two hex digits to the accent — `${accent}55`,
    /// `${accent}88`. Same thing, spelled as an alpha fraction.
    public func alpha(_ byte: UInt8) -> Color { color.opacity(Double(byte) / 255) }
}

public enum Palette {
    // --- ground ---
    /// The device body behind everything: `background:#060608`.
    public static let screen = Swatch(0x060608)
    /// Ink on a gold/accent fill: `color:#060608`.
    public static let onAccent = Swatch(0x060608)
    /// Warm bloom in the top-right: `radial-gradient(420px 260px at 78% -6%,#1d1a12 0%,…)`.
    public static let glow = Swatch(0x1D1A12)

    // --- surfaces ---
    /// Cards, header buttons, history rows: `background:#111118`.
    public static let surface = Swatch(0x111118)
    /// Controls sitting on a card — −, ×N, ✦, timer badge: `background:#181822`.
    public static let surfaceRaised = Swatch(0x181822)
    /// The empty-state panel, darker than a card: `background:#0b0b10`.
    public static let surfaceSunken = Swatch(0x0B0B10)
    /// The emphasised (live) hunt card: `background:#17151b`.
    public static let surfaceLive = Swatch(0x17151B)
    /// A block inside the species sheet — stats, weaknesses, locations: `background:#0f0f15`.
    public static let surfaceBlock = Swatch(0x0F0F15)
    /// The bottom sheet itself: `background:#141419`.
    public static let sheet = Swatch(0x141419)

    // --- lines ---
    /// The 1px card outline and the progress track: `#1a1a22`.
    public static let hairline = Swatch(0x1A1A22)
    /// Control outlines: `inset 0 0 0 1px #25252f`.
    public static let border = Swatch(0x25252F)
    /// The ×N chip at step 1: `inset 0 0 0 1px #33333f`.
    public static let borderChip = Swatch(0x33333F)

    // --- text ---
    /// Titles, species names, the count: `#f4f2ec`.
    public static let textPrimary = Swatch(0xF4F2EC)
    /// The card meta line and inactive tab-bar glyphs: `#b6b5c0`.
    public static let textSecondary = Swatch(0xB6B5C0)
    /// Labels, hints, odds, the segmented control's off state: `#8a8896`.
    public static let textMuted = Swatch(0x8A8896)
    /// The quietest tier — history timestamps, disclaimers: `#44444e`.
    public static let textFaint = Swatch(0x44444E)
    /// − at count 0: `color:#3a3a44`.
    public static let textDisabled = Swatch(0x3A3A44)

    // --- mode accents: "Each mode owns a colour, so you always know where you are." ---
    /// Hunt. The default of the prototype's `accent` prop.
    public static let hunt = Swatch(0xF5C661)
    /// Nuzlocke.
    public static let nuzlocke = Swatch(0x7B9BFF)
    /// Team.
    public static let team = Swatch(0x6EE7A2)
    /// Dex — the same bone white as primary text.
    public static let dex = Swatch(0xF4F2EC)

    // --- base-stat bars: `v >= 90 ? '#6ee7a2' : v >= 60 ? '#f5c661' : '#ff7373'` ---
    /// A weak base stat. The only red in the palette; the other two tiers are ``team``/``hunt``.
    public static let statLow = Swatch(0xFF7373)

    /// The bar colour for a stat value, per the prototype's ternary above.
    public static func statBar(_ value: Int) -> Swatch {
        value >= 90 ? team : value >= 60 ? hunt : statLow
    }

    // --- sheets --- (the sheet background itself is ``sheet``, above)
    /// The search field inside a sheet: `background:#0d0d12`.
    public static let field = Swatch(0x0D0D12)
    /// The key/value panel on the Ready and confirm sheets: `background:#0f0f15`.
    public static let detailPanel = Swatch(0x0F0F15)
    /// The gold-glowing summary card on the Ready step: `background:#15131a`.
    public static let confirmCard = Swatch(0x15131A)
    /// The armed "this deletes the hunt" state: `color:#ff7373`.
    public static let danger = Swatch(0xFF7373)

    // --- sprite tile ---
    // `radial-gradient(circle at 50% 42%,#23232f 0%,#14141c 72%)` — the layer behind every
    // sprite, so a row never renders as an empty hole while the image loads or 404s.
    public static let spriteTileInner = Swatch(0x23232F)
    public static let spriteTileOuter = Swatch(0x14141C)

    // --- tab bar ---
    /// `background:rgba(18,18,26,.82)` under a `blur(24px)`.
    public static let tabBar = Swatch(0x12121A)
    public static let tabBarOpacity = 0.82
    /// `border:1px solid #2a2a36`.
    public static let tabBarBorder = Swatch(0x2A2A36)
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
    /// Tab-bar shell: `border-radius:24px`.
    public static let tabBar: CGFloat = 24
    /// Sprite tile — the prototype computes `Math.round(size / 4)`.
    public static func sprite(_ size: CGFloat) -> CGFloat { (size / 4).rounded() }
}

// MARK: - Type

/// The prototype's font stack is `-apple-system, 'SF Pro Text', 'SF Pro Display', …` — i.e.
/// the system face, so every token below is `Font.system`. Sizes are CSS px, which map 1:1 to
/// points at the design's 390pt frame width.
///
/// `.tracking` is separate from `.font` in SwiftUI, so the em-based letter-spacings the
/// prototype uses come back as the point values they resolve to at that size.
public enum Typography {
    /// `font:700 30px/1;letter-spacing:-.035em` — the "Hunt" screen title.
    public static let screenTitle = Font.system(size: 30, weight: .bold)
    public static let screenTitleTracking: CGFloat = -0.035 * 30

    /// `font:700 22px/1;letter-spacing:-.02em` — species name on a hunt card.
    public static let cardTitle = Font.system(size: 22, weight: .bold)
    public static let cardTitleTracking: CGFloat = -0.02 * 22

    /// `font:600 26px/1;letter-spacing:-.03em;font-variant-numeric:tabular-nums` — the count.
    public static let count = Font.system(size: 26, weight: .semibold).monospacedDigit()
    public static let countTracking: CGFloat = -0.03 * 26

    /// `font:500 12px/1;letter-spacing:.12em;text-transform:uppercase` — "ENCOUNTERS".
    public static let overline = Font.system(size: 12, weight: .medium)
    public static let overlineTracking: CGFloat = 0.12 * 12

    /// `font:600 22px/1.2;letter-spacing:-.02em` — "No active hunts".
    public static let emptyTitle = Font.system(size: 22, weight: .semibold)
    /// `font:400 15px/1.5` — the empty-state paragraph.
    public static let emptyBody = Font.system(size: 15, weight: .regular)

    /// `font:400 13px/1.4` — the card meta line.
    public static let meta = Font.system(size: 13, weight: .regular)
    /// `font:400 13px/1` — odds and the cumulative-probability label.
    public static let stat = Font.system(size: 13, weight: .regular)
    /// `font:600 13px/1` — the same label once the count is past the odds.
    public static let statStrong = Font.system(size: 13, weight: .semibold)
    /// `font:500 13px/1` — the header's "2 hunts".
    public static let summary = Font.system(size: 13, weight: .medium)
    /// `font:400 12px/1.3` — the hint line under the segmented control.
    public static let hint = Font.system(size: 12, weight: .regular)
    /// `font:600 13px/1;font-variant-numeric:tabular-nums` — the timer badge.
    public static let badge = Font.system(size: 13, weight: .semibold).monospacedDigit()
    /// `font:600 15px/1` (selected) / `font:500 15px/1` — segmented control and pill labels.
    public static let segmentOn = Font.system(size: 15, weight: .semibold)
    public static let segmentOff = Font.system(size: 15, weight: .medium)
    /// `font:700 24px/1;letter-spacing:-.03em` — the species sheet's name.
    public static let sheetTitle = Font.system(size: 24, weight: .bold)
    public static let sheetTitleTracking: CGFloat = -0.03 * 24

    /// `font:500 11px/1;letter-spacing:.14em;text-transform:uppercase` — "BASE STATS", and the
    /// Dex grid's per-generation section headers.
    public static let blockLabel = Font.system(size: 11, weight: .medium)
    public static let blockLabelTracking: CGFloat = 0.14 * 11

    /// `font:600 13px/1` — the species name on a Dex tile.
    public static let tileName = Font.system(size: 13, weight: .semibold)
    /// `font:400 11px/1` — the line under it ("Registered", "#443", "2,847 enc").
    public static let tileSub = Font.system(size: 11, weight: .regular)

    /// `font:600 18px/1` — the wide gold "+1 encounter" button.
    public static let primaryButton = Font.system(size: 18, weight: .semibold)
    /// `font:600 15px/1` — the ×N chip.
    public static let chip = Font.system(size: 15, weight: .semibold)

    /// `font:700 24px/1;letter-spacing:-.03em` — the species on the Ready card, and "Found X?"
    /// on the confirm sheet. The two are the same type at the same size in the prototype.
    public static let sheetHeadline = Font.system(size: 24, weight: .bold)
    public static let sheetHeadlineTracking: CGFloat = -0.03 * 24

    /// `font:600 17px/1` — a row's headline inside a sheet or the History list: species,
    /// game title, method name.
    public static let listTitle = Font.system(size: 17, weight: .semibold)
    /// `font:600 17px/1;font-variant-numeric:tabular-nums` — the gold odds on a method card.
    public static let oddsValue = Font.system(size: 17, weight: .semibold).monospacedDigit()
    /// `font:400 15px/1` — the left-hand label of a key/value row.
    public static let rowLabel = Font.system(size: 15, weight: .regular)
    /// `font:600 15px/1;font-variant-numeric:tabular-nums` — its right-hand value.
    public static let rowValue = Font.system(size: 15, weight: .semibold).monospacedDigit()
    /// `font:600 13px/1` — the Shiny Charm tag on a game row.
    public static let tag = Font.system(size: 13, weight: .semibold)
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
    /// `width:42px` — the −, ×N and ✦ buttons.
    public static let controlNarrow: CGFloat = 42
    /// `width:62px;height:62px` — the hunt-card sprite.
    public static let cardSprite: CGFloat = 62
    /// `height:6px` — the progress bar.
    public static let barHeight: CGFloat = 6
}
