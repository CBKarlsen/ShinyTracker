import ShinyTrackerUI
import SwiftUI

/// The live hunt, docked above the tab bar on every screen — so a hunt can be counted while
/// browsing the Dex or a Nuzlocke run, without switching tabs.
///
/// `+` calls the same ``HuntListModel/bump(_:by:)`` the hunt card calls, which is the whole point:
/// the tap lands in the offline write queue, is coalesced with its neighbours, and carries an
/// idempotency key. Counting from here is offline-safe for free rather than by re-implementation.
///
/// Renders nothing when no hunt is live, so the chrome disappears rather than showing an empty
/// frame or nagging the user to start a hunt.
struct LiveHuntAccessory: View {
    let model: HuntListModel
    /// Switches the shell to the Hunt tab.
    let onOpen: () -> Void

    var body: some View {
        if let row = model.liveRow {
            HStack(spacing: 10) {
                Button(action: onOpen) {
                    HStack(spacing: 10) {
                        SpriteTile(
                            pokemonID: row.detail.pokemonID,
                            size: 28,
                            served: row.detail.shinySpriteURL
                        )
                        Text(row.name)
                            .font(Typography.summary)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(row.count.formatted())
                            .font(Typography.badge)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.name), \(row.count) encounters. Open Hunt.")

                Button {
                    model.bump(row.id, by: 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolEffect(.bounce.up, options: .speed(1.6), value: row.count)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.hunt)
                // Holds like the card's `+`, so counting from another tab is not the worse one.
                // Unlike the card there is no `−` beside it, so an overshoot here is corrected on
                // the Hunt tab rather than in place — tapping the row above opens it.
                .buttonRepeatBehavior(.enabled)
                .accessibilityLabel("Add one encounter to \(row.name)")
                .accessibilityHint("Hold to keep counting.")
            }
            .padding(.horizontal, 14)
        }
    }
}
