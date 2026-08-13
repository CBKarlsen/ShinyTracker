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
            (isLive ? Palette.surfaceLive : Palette.surface).color,
            in: .rect(cornerRadius: Radii.card)
        )
        // `box-shadow: h.live ? '0 0 0 2px accent88, 0 0 38px -12px accent'
        //                     : 'inset 0 0 0 1px #1a1a22'`
        .overlay(
            RoundedRectangle(cornerRadius: Radii.card)
                .strokeBorder(
                    isLive ? Palette.hunt.alpha(0x88) : Palette.hairline.color,
                    lineWidth: isLive ? 2 : 1
                )
        )
        .shadow(color: isLive ? Palette.hunt.alpha(0x66) : .clear, radius: 19, y: 4)
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
                    .foregroundStyle(Palette.textPrimary.color)
                if !row.meta.isEmpty {
                    Text(row.meta)
                        .font(Typography.meta)
                        .foregroundStyle(Palette.textSecondary.color)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 0) {
                Text(row.count.formatted(.number))
                    .font(Typography.count)
                    .tracking(Typography.countTracking)
                    .foregroundStyle(Palette.textPrimary.color)
                Text("ENCOUNTERS")
                    .font(Typography.overline)
                    .tracking(Typography.overlineTracking)
                    .foregroundStyle(Palette.textMuted.color)
                    .padding(.top, 6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(row.name), \(row.count) encounters")
        }
    }

    // MARK: Timer

    /// The badge is read-only. Elapsed time is `total_time_seconds` from the API; the client-owned
    /// timer that would make this tappable is DECISIONS.md D1 and is not implemented, so the card
    /// does not offer a control that would not do anything.
    private var timerRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                // `border-radius:4px;background:currentColor` — the paused glyph is the filled dot.
                Circle()
                    .fill(Palette.textMuted.color)
                    .frame(width: 8, height: 8)
                Text(formatElapsed(row.detail.totalTimeSeconds))
                    .font(Typography.badge)
                    .foregroundStyle(Palette.textMuted.color)
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Palette.surfaceRaised.color, in: .rect(cornerRadius: Radii.badge))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.badge)
                    .strokeBorder(Palette.border.color, lineWidth: 1)
            )

            Text("paused")
                .font(Typography.hint)
                .foregroundStyle(Palette.textMuted.color)

            if model.hasPendingWrites(row.id) {
                queuedBadge
            }
        }
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Hunted for \(formatElapsed(row.detail.totalTimeSeconds)), paused"
                + (model.hasPendingWrites(row.id)
                    ? (model.isWaitingToRetry ? ", counts waiting to retry" : ", counts queued to sync")
                    : "")
        )
    }

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
        .foregroundStyle(Palette.textMuted.color)
        .padding(.horizontal, 11)
        .frame(height: 30)
        .background(Palette.surfaceRaised.color, in: .rect(cornerRadius: Radii.badge))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.badge)
                .strokeBorder(Palette.border.color, lineWidth: 1)
        )
    }

    // MARK: Progress

    /// `height:6px;border-radius:3px;background:#1a1a22` with a gold fill.
    @ViewBuilder
    private var progressBar: some View {
        if row.denominator != nil {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.hairline.color)
                    Capsule()
                        .fill(Palette.hunt.color)
                        .frame(width: geometry.size.width * row.progressRatio)
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
                .foregroundStyle(Palette.textMuted.color)
            Spacer(minLength: 8)
            if let denominator = row.denominator {
                if row.count > denominator {
                    Text("past odds — keep going")
                        .font(Typography.statStrong)
                        .foregroundStyle(Palette.hunt.color)
                } else if let probability = row.cumulativeProbability {
                    Text("\(probability * 100, specifier: "%.1f")% chance by now")
                        .font(Typography.stat)
                        .foregroundStyle(Palette.textMuted.color)
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
            // `−` always corrects by exactly 1, and greys out at 0.
            controlButton(label: "Remove one encounter from \(row.name)") {
                model.bump(row.id, by: -1)
            } content: {
                Image(systemName: "minus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(
                        (row.count > 0 ? Palette.textSecondary : Palette.textDisabled).color
                    )
            }
            .frame(width: Metrics.controlNarrow)
            .disabled(row.count == 0)

            // The primary tap target. IOS_HANDOVER.md: this one control carries the feature.
            Button {
                model.bump(row.id, by: step)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                    Text("+\(step) encounter\(step > 1 ? "s" : "")")
                        .font(Typography.primaryButton)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.controlHeight)
                .foregroundStyle((isLive ? Palette.onAccent : Palette.textSecondary).color)
                .background(
                    (isLive ? Palette.hunt : Palette.surfaceRaised).color,
                    in: .rect(cornerRadius: Radii.control)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.control)
                        .strokeBorder(isLive ? .clear : Palette.border.color, lineWidth: 1)
                )
                .contentShape(.rect)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Add \(step) encounter\(step > 1 ? "s" : "") to \(row.name)")

            // ×N cycles 1 · 2 · 3 · 5 · 10 and goes gold once it is above 1.
            controlButton(
                label: "Encounters per tap, currently \(step). Tap to change."
            ) {
                model.cycleStep(row.id)
            } content: {
                Text("×\(step)")
                    .font(Typography.chip)
                    .foregroundStyle((step > 1 ? Palette.hunt : Palette.textPrimary).color)
            }
            .frame(width: Metrics.controlNarrow)
            .overlay(
                RoundedRectangle(cornerRadius: Radii.control)
                    .strokeBorder(
                        step > 1 ? Palette.hunt.alpha(0x55) : Palette.borderChip.color,
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
                    .foregroundStyle(Palette.hunt.color)
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
                .background(Palette.surfaceRaised.color, in: .rect(cornerRadius: Radii.control))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.control)
                        .strokeBorder(Palette.border.color, lineWidth: 1)
                )
                .contentShape(.rect)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }
}

/// `style-active="transform:scale(.97)"` on the increment button.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
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
        .background {
            RadialGradient(
                colors: [Palette.spriteTileInner.color, Palette.spriteTileOuter.color],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 0,
                endRadius: size * 0.72
            )
        }
        .clipShape(.rect(cornerRadius: Radii.sprite(size)))
        .accessibilityHidden(true)
    }
}
