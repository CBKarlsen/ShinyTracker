import ActivityKit
import AppIntents
import ShinyTrackerUI
import SwiftUI
import WidgetKit

@main
struct ShinyTrackerWidgets: WidgetBundle {
    var body: some Widget {
        HuntLiveActivity()
    }
}

/// The hunt on the Lock Screen, and in the Dynamic Island.
///
/// The point of this is the `+`: your hands are on a console, not on the phone, so the count has to
/// be reachable without unlocking. Everything else here exists to make that button safe to press —
/// the species and the count, so you can see at a glance that you are adding to the right hunt.
///
/// No sprite. A widget's network loads are unreliable and there is no shared image cache with the
/// app, so a species that failed to load would leave a hole on the Lock Screen; the name carries
/// the identity instead.
struct HuntLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HuntActivity.self) { context in
            lockScreen(context)
                // Widgets render in the system's colour scheme, and this app is dark-only —
                // without this the Lock Screen card would come up in light mode's colours while
                // the app it belongs to is black.
                .environment(\.colorScheme, .dark)
                .activityBackgroundTint(Palette.screen)
                .activitySystemActionForegroundColor(Palette.hunt)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.speciesName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    count(context.state.count)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        oddsLine(context.state)
                        Spacer(minLength: 8)
                        countButton(context)
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles").foregroundStyle(Palette.hunt)
            } compactTrailing: {
                Text(context.state.count.formatted(.number))
                    .foregroundStyle(Palette.hunt)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "sparkles").foregroundStyle(Palette.hunt)
            }
        }
    }

    // MARK: Lock Screen

    private func lockScreen(_ context: ActivityViewContext<HuntActivity>) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    // Same cue as the card's timer badge: gold while the clock is still banking
                    // time, muted once the gap since the last encounter says the hunt has paused.
                    Circle()
                        .fill(context.state.counting ? Palette.hunt : Palette.textMuted)
                        .frame(width: 7, height: 7)
                    Text(context.attributes.speciesName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                }
                Text(context.attributes.meta)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
                oddsLine(context.state)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 8) {
                count(context.state.count)
                countButton(context)
            }
        }
        .padding(16)
    }

    private func count(_ value: Int) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value.formatted(.number))
                .font(.system(size: 26, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
                .foregroundStyle(Palette.textPrimary)
            Text("ENCOUNTERS")
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Palette.textMuted)
        }
    }

    /// The odds and how far through them this hunt is — the same two facts the card's stats row
    /// carries, on one line because a Lock Screen card has no room for two.
    @ViewBuilder
    private func oddsLine(_ state: HuntActivity.ContentState) -> some View {
        if let denominator = state.denominator {
            Text(
                "1 / \(denominator.formatted(.number))"
                    + (state.cumulativeProbability.map {
                        " · \(($0 * 100).formatted(.number.precision(.fractionLength(1))))%"
                    } ?? "")
                    + " · \(formatElapsed(state.elapsedSeconds))"
            )
            .font(.system(size: 12))
            .foregroundStyle(Palette.textMuted)
        } else {
            Text(formatElapsed(state.elapsedSeconds))
                .font(.system(size: 12))
                .foregroundStyle(Palette.textMuted)
        }
    }

    /// The whole reason this exists. `LiveHuntCountIntent` is a `LiveActivityIntent`, so pressing
    /// this runs it in the *app's* process — where the write queue lives — rather than in this
    /// extension, where it does not.
    private func countButton(_ context: ActivityViewContext<HuntActivity>) -> some View {
        Button(
            intent: LiveHuntCountIntent(
                huntID: context.attributes.huntID, step: context.state.step)
        ) {
            Text("+\(context.state.step)")
                .font(.system(size: 15, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Palette.onAccent)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(Palette.hunt, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "Add \(context.state.step) encounter\(context.state.step > 1 ? "s" : "") to "
                + context.attributes.speciesName)
    }
}
