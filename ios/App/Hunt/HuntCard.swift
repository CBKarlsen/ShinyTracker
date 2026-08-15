import ShinyTrackerUI
import SwiftUI

/// One hunt card — the heart of the screen.
///
/// Transcribed from the `hunts` block of `docs/design/hunt-prototype.dc.html`: sprite + name +
/// meta, the count with its ENCOUNTERS overline, the timer badge, the progress bar with odds and
/// cumulative probability, then the − / +N / ×N / ✦ control row.
struct HuntCard: View {
    let row: HuntRow
    let model: HuntListModel
    /// The prototype's `h.live` — the card you are actually counting on.
    let isLive: Bool
    /// Opens the confirm sheet. The card does not complete the hunt itself.
    let onFound: () -> Void

    private var step: Int { model.step(for: row.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityRow
            timerRow
            progressBar
            statsRow
            controlRow
        }
        .padding(Metrics.cardPadding)
        .background(
            isLive ? Palette.surfaceLive : Palette.surface,
            in: .rect(cornerRadius: Radii.card)
        )
        // `box-shadow: h.live ? '0 0 0 2px accent88, 0 0 38px -12px accent'
        //                     : 'inset 0 0 0 1px #1a1a22'`
        //
        // Only the 2px ring survives. The second shadow's `-12px` spread makes it a tight rim in
        // CSS; SwiftUI's `.shadow` has no spread, so the transcription bloomed a wide gold haze
        // across the whole card and the background behind it. The ring plus ``surfaceLive`` already
        // says which card is live — the haze only said "generated".
        .overlay(
            RoundedRectangle(cornerRadius: Radii.card)
                .strokeBorder(
                    isLive ? Palette.hunt.alpha(0x88) : Palette.hairline,
                    lineWidth: isLive ? 2 : 1
                )
        )
    }

    // MARK: Identity

    /// `display:flex;gap:13px;align-items:flex-start`
    private var identityRow: some View {
        HStack(alignment: .top, spacing: 13) {
            SpriteTile(
                pokemonID: row.detail.pokemonID,
                size: Metrics.cardSprite,
                served: row.detail.shinySpriteURL
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(row.name)
                    .font(Typography.cardTitle)
                    .tracking(Typography.cardTitleTracking)
                    .foregroundStyle(Palette.textPrimary)
                if !row.meta.isEmpty {
                    Text(row.meta)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                Text(row.count.formatted(.number))
                    .font(Typography.count)
                    .tracking(Typography.countTracking)
                    .foregroundStyle(Palette.textPrimary)
                    // The one thing the tap is *for*. Without this the number swaps in place and
                    // a tap that worked is indistinguishable from one that didn't register.
                    .contentTransition(.numericText(value: Double(row.count)))
                    .animation(.snappy(duration: 0.22), value: row.count)
                Text("ENCOUNTERS")
                    .font(Typography.overline)
                    .tracking(Typography.overlineTracking)
                    .foregroundStyle(Palette.textMuted)
                    .padding(.top, 6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.name), \(row.count) encounters")
        }
    }

    // MARK: Timer

    /// The badge is read-only, and reads the client's clock (DECISIONS.md D1), not the server's
    /// total. `HuntClock` banks the gap between encounters on every `bump`, so this is the number
    /// that is actually true — the API's `total_time_seconds` is only the floor, and a hunt counted
    /// entirely offline has none of this session in it at all.
    private var timerRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                // `border-radius:4px;background:currentColor` — the paused glyph is the filled dot.
                Circle()
                    .fill(counting ? Palette.hunt : Palette.textMuted)
                    .frame(width: 8, height: 8)
                Text(formatElapsed(model.elapsed(for: row)))
                    .font(Typography.badge)
                    .foregroundStyle(Palette.textMuted)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Palette.surfaceRaised, in: .rect(cornerRadius: Radii.badge))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.badge)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )

            Text(counting ? "counting" : "paused")
                .font(Typography.hint)
                .foregroundStyle(Palette.textMuted)

            if model.hasPendingWrites(row.id) {
                queuedBadge
            }
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Hunted for \(formatElapsed(model.elapsed(for: row))), "
                + (counting ? "counting" : "paused")
                + (model.hasPendingWrites(row.id)
                    ? (model.isWaitingToRetry ? ", counts waiting to retry" : ", counts queued to sync")
                    : "")
        )
    }

    /// Whether the next tap still lands in this session — see ``HuntListModel/isCounting(_:)``.
    private var counting: Bool { model.isCounting(row) }

    /// An acknowledgement, not a warning: queued work is the normal state of counting offline, so
    /// this borrows the timer badge's own pill — same size, same muted colour — rather than an
    /// alert colour or a spinner that would suggest something is stuck or wrong.
    private var queuedBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: model.isWaitingToRetry
                    ? "arrow.clockwise.icloud" : "icloud.and.arrow.up")
                .font(.system(size: 11, weight: .semibold))
            // "waiting" only while the drain is cooling off after the server answered and failed.
            // Otherwise the badge would be indistinguishable from ordinary offline counting, and a
            // pull-to-refresh that deliberately does nothing would read as the app being broken.
            Text(model.isWaitingToRetry ? "waiting" : "queued")
                .font(Typography.badge)
        }
        .foregroundStyle(Palette.textMuted)
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Palette.surfaceRaised, in: .rect(cornerRadius: Radii.badge))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.badge)
                .strokeBorder(Palette.border, lineWidth: 1)
        )
    }

    // MARK: Progress

    /// `height:6px;border-radius:3px;background:#1a1a22` with a gold fill.
    @ViewBuilder
    private var progressBar: some View {
        if row.denominator != nil {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.hairline)
                    Capsule()
                        .fill(Palette.hunt)
                        .frame(width: geometry.size.width * row.progressRatio)
                        // Grows with the count instead of jumping — same spring as the number, so
                        // the two halves of one tap move together.
                        .animation(.snappy(duration: 0.22), value: row.progressRatio)
                }
            }
            .frame(height: Metrics.barHeight)
            .padding(.top, 13)
        }
    }

    /// Left: the odds. Right: `${(cumulative * 100).toFixed(1)}% chance by now`, or the
    /// past-odds line once the count has overtaken the denominator.
    private var statsRow: some View {
        HStack {
            Text(oddsLabel)
                .font(Typography.stat)
                .foregroundStyle(Palette.textMuted)
            Spacer(minLength: 8)
            if let denominator = row.denominator {
                if row.count > denominator {
                    Text("past odds — keep going")
                        .font(Typography.statStrong)
                        .foregroundStyle(Palette.hunt)
                } else if let probability = row.cumulativeProbability {
                    Text("\(probability * 100, specifier: "%.1f")% chance by now")
                        .font(Typography.stat)
                        .foregroundStyle(Palette.textMuted)
                }
            }
        }
        .padding(.top, 9)
    }

    /// "1 / 8,192". A hunt with no game has no base odds, so there is nothing honest to print —
    /// the bar and the probability disappear with it rather than showing an invented number.
    private var oddsLabel: String {
        guard let denominator = row.denominator else { return "Odds unknown" }
        return "1 / \(denominator.formatted(.number))"
    }

    // MARK: Controls

    /// `display:flex;gap:8px;margin-top:14px` — −, the wide +N, ×N, ✦.
    private var controlRow: some View {
        HStack(spacing: 8) {
            // `−` always corrects by exactly 1, and greys out at 0. It holds for the same reason
            // `+` does, and it is what makes holding `+` safe: an overshoot is undone the same way
            // it was made. The repeat stops on its own at 0, where the button disables.
            controlButton(label: "Remove one encounter from \(row.name)") {
                model.bump(row.id, by: -1)
            } content: {
                Image(systemName: "minus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(row.count > 0 ? Palette.textSecondary : Palette.textDisabled)
            }
            .frame(width: Metrics.controlNarrow)
            .disabled(row.count == 0)
            .buttonRepeatBehavior(.enabled)
            .accessibilityHint("Hold to keep removing.")

            // The primary tap target. IOS_HANDOVER.md: this one control carries the feature.
            Button {
                model.bump(row.id, by: step)
            } label: {
                HStack(spacing: 7) {
                    // The glyph kicks upward each time the count actually moves — keyed to
                    // `row.count`, not to `isPressed`, so a press that changed nothing (− at 0,
                    // a bump the clamp swallowed) stays still and the button never lies about
                    // having counted. Sped up so one bounce finishes inside a hold's repeat
                    // interval instead of being cut off by the next; drop the option to slow it.
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .symbolEffect(.bounce.up, options: .speed(1.6), value: row.count)
                    // No "+" in the string: the glyph beside it is the plus, and carrying it in
                    // both rendered as "+ +1 encounter" on device.
                    Text("\(step) encounter\(step > 1 ? "s" : "")")
                        .font(Typography.primaryButton)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.controlHeight)
                .foregroundStyle(isLive ? Palette.onAccent : Palette.textSecondary)
                .background(
                    isLive ? Palette.hunt : Palette.surfaceRaised,
                    in: .rect(cornerRadius: Radii.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.control)
                        .strokeBorder(isLive ? .clear : Palette.border, lineWidth: 1)
                )
                .contentShape(.rect)
            }
            .buttonStyle(PressScaleStyle())
            // The discharge, separate from the press above. Keyed to `row.count`, so it fires when
            // an encounter actually lands rather than when a finger touches down — a press the
            // clamp swallowed leaves the button still. The `trigger:` overload runs the phases
            // once and settles back on the first, which is the one-shot the plain overload isn't.
            //
            // Deliberately small: at ×10 with a finger held down this repeats several times a
            // second, and anything bigger stops reading as feedback and starts reading as lag.
            // 1.03 / 0.10 are the knobs.
            .phaseAnimator([false, true], trigger: row.count) { button, firing in
                button
                    .scaleEffect(firing ? 1.03 : 1)
                    .brightness(firing ? 0.10 : 0)
            } animation: { firing in
                firing ? .easeOut(duration: 0.07) : .snappy(duration: 0.2, extraBounce: 0.35)
            }
            // Catching up is the case this is for: a hunter who counted a stretch in their head,
            // or forgot to log one, is not going to tap forty times. Repeat is an environment
            // value, so it reaches the Button through `PressScaleStyle` untouched — and it is set
            // per button rather than on the row, because ×N would cycle wildly and ✦ would
            // re-present the found sheet. Each repeat is an ordinary `bump`: clamped at 0,
            // coalesced by `WriteQueue`, one haptic per step so a hold ratchets audibly.
            .buttonRepeatBehavior(.enabled)
            .accessibilityLabel("Add \(step) encounter\(step > 1 ? "s" : "") to \(row.name)")
            .accessibilityHint("Hold to keep counting.")

            // ×N cycles 1 · 2 · 3 · 5 · 10 and goes gold once it is above 1.
            controlButton(
                label: "Encounters per tap, currently \(step). Tap to change."
            ) {
                model.cycleStep(row.id)
            } content: {
                Text("×\(step)")
                    .font(Typography.chip)
                    .foregroundStyle(step > 1 ? Palette.hunt : Palette.textPrimary)
            }
            .frame(width: Metrics.controlNarrow)
            .overlay(
                RoundedRectangle(cornerRadius: Radii.control)
                    .strokeBorder(
                        step > 1 ? Palette.hunt.alpha(0x55) : Palette.borderChip,
                        lineWidth: 1
                    )
            )

            // ✦ found — opens the confirm sheet, which is also where the hunt can be abandoned.
            controlButton(label: "Mark \(row.name) as found") {
                Haptics.impact(.light)
                onFound()
            } content: {
                Image(systemName: "sparkles")
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.hunt)
            }
            .frame(width: Metrics.controlNarrow)
            .overlay(
                RoundedRectangle(cornerRadius: Radii.control)
                    .strokeBorder(Palette.hunt.alpha(0x55), lineWidth: 1)
            )
        }
        .padding(.top, 14)
    }

    /// The shared shell of the three narrow controls: 42×54, `#181822`, `border-radius:15px`.
    private func controlButton(
        label: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.controlHeight)
                .background(Palette.surfaceRaised, in: .rect(cornerRadius: Radii.control))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.control)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
                .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

/// `style-active="transform:scale(.97)"` on the increment button.
///
/// The travel is the prototype's, the curve is not: an 80ms ease-out is a CSS transition, and on a
/// button pressed hundreds of times per hunt it reads as lag because there is no release. A spring
/// overshoots back past 1 and lands, which is what "responsive" actually feels like on iOS.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            // The whole face darkens under the finger, not just the glyph on it — a button this
            // size needs the press to be visible somewhere other than its edges.
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.snappy(duration: 0.18, extraBounce: 0.3), value: configuration.isPressed)
    }
}

/// A sprite on the design's radial-gradient tile.
///
/// The tile is a fallback layer in the prototype for exactly the reason it is one here: it shows
/// through while the image loads and stays put if it 404s, so a card never renders as a hole.
struct SpriteTile: View {
    let pokemonID: Int
    let size: CGFloat
    /// `shiny_sprite_url` off the hunt row, when the caller has one.
    var served: String?

    var body: some View {
        AsyncImage(url: SpriteSource.url(id: pokemonID, shiny: true, served: served)) { image in
            image.resizable().interpolation(.none).scaledToFit()   // image-rendering:pixelated
        } placeholder: {
            Color.clear
        }
        .frame(width: size, height: size)
        .background(Palette.spriteTile)
        .clipShape(.rect(cornerRadius: Radii.sprite(size)))
        .accessibilityHidden(true)
    }
}
