import SwiftUI
import Testing

@testable import ShinyTrackerUI

/// The palette is transcribed from `docs/design/hunt-prototype.dc.html`, and two of its greys are
/// deliberately *not* what the prototype says — see the notes on ``Palette/textFaint`` and
/// ``Palette/textDisabled``. A future re-transcription would silently put the unreadable values
/// back, and nothing else in the build would notice: the app still compiles, still renders, and
/// the text is still there, just invisible on a phone in daylight.
///
/// This is the check that fails instead. It is arithmetic, not taste — the WCAG relative-luminance
/// formula, against the actual backgrounds these greys are drawn on.
struct ContrastTests {

    /// WCAG 2.1 relative luminance.
    ///
    /// `Color.resolve(in:)` hands back `linearRed`/`linearGreen`/`linearBlue` — already
    /// gamma-decoded, which is exactly the half of the WCAG formula that is easy to get wrong.
    /// It is also the reason this test compiles on macOS, where `swift test` actually runs:
    /// `UIColor` does not exist there.
    private static func luminance(_ color: Color) -> Double {
        let c = color.resolve(in: EnvironmentValues())
        return 0.2126 * Double(c.linearRed)
            + 0.7152 * Double(c.linearGreen)
            + 0.0722 * Double(c.linearBlue)
    }

    private static func ratio(_ a: Color, on b: Color) -> Double {
        let (l1, l2) = (luminance(a), luminance(b))
        let (hi, lo) = (max(l1, l2), min(l1, l2))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Every ground a body-text token can land on. `surfaceRaised` is the darkest-contrast case
    /// and the one that actually binds.
    private static let grounds: [(String, Color)] = [
        ("screen", Palette.screen),
        ("surface", Palette.surface),
        ("surfaceRaised", Palette.surfaceRaised),
        ("surfaceLive", Palette.surfaceLive),
        ("sheet", Palette.sheet),
    ]

    /// The formula itself, against a pair with a known answer: white on black is exactly 21:1.
    @Test("The contrast formula agrees with the known 21:1 extreme")
    func formulaIsCorrect() {
        #expect(abs(Self.ratio(.white, on: .black) - 21) < 0.01)
    }

    /// `textFaint` carries real content — History timestamps, the Dex scope note, Nuzlocke
    /// chapter summaries. The prototype's `#44444e` was 1.83:1 here.
    @Test("textFaint clears 3:1 on every surface it is drawn on")
    func textFaintIsLegible() {
        for (name, ground) in Self.grounds {
            let r = Self.ratio(Palette.textFaint, on: ground)
            #expect(r >= 3.0, "textFaint on \(name) is \(r), under 3:1")
        }
    }

    /// A disabled control is WCAG-exempt, but an invisible one still reads as a missing one.
    /// The prototype's `#3a3a44` was 1.57:1.
    @Test("textDisabled clears 3:1 on every surface it is drawn on")
    func textDisabledIsFindable() {
        for (name, ground) in Self.grounds {
            let r = Self.ratio(Palette.textDisabled, on: ground)
            #expect(r >= 3.0, "textDisabled on \(name) is \(r), under 3:1")
        }
    }

    /// The tiers have to stay ordered, or "quietest" stops meaning anything. Faint is quieter than
    /// muted; disabled is quieter than faint; and the disabled − must stay clearly distinct from
    /// the enabled one (``textSecondary``), which is the difference the user actually reads.
    @Test("The quiet tiers stay in order, and disabled stays distinct from enabled")
    func tiersRemainOrdered() {
        let ground = Palette.surfaceRaised
        let muted = Self.ratio(Palette.textMuted, on: ground)
        let faint = Self.ratio(Palette.textFaint, on: ground)
        let disabled = Self.ratio(Palette.textDisabled, on: ground)
        let enabled = Self.ratio(Palette.textSecondary, on: ground)

        #expect(disabled <= faint, "disabled (\(disabled)) must not be louder than faint (\(faint))")
        #expect(faint < muted, "faint (\(faint)) must be quieter than muted (\(muted))")
        // The enabled − versus the disabled −: the one comparison a user makes directly.
        #expect(enabled > disabled * 2, "enabled (\(enabled)) is too close to disabled (\(disabled))")
    }
}
