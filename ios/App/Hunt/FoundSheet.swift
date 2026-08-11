import ShinyTrackerUI
import SwiftUI

/// The ✦ confirm: "The ✦ button marks it found — behind a confirm, which is also where you can
/// abandon a hunt."
///
/// Two irreversible things live on one sheet on purpose, because that is where the design put
/// them, and they are told apart by weight: found is the gold full-width button, abandon is a
/// bare row of text that has to be tapped twice.
struct FoundSheet: View {
    /// A snapshot taken when the sheet opened. The card behind it is covered, so the count
    /// cannot move underneath.
    let row: HuntRow
    let model: HuntListModel
    let onClose: () -> Void

    /// `s.abandonArm`. Sheet-local: dismissing disarms it, which is the behaviour you want.
    @State private var abandonArmed = false
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    SpriteTile(pokemonID: row.detail.pokemonID, size: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Found \(row.name)?")
                            .font(Typography.sheetHeadline)
                            .tracking(Typography.sheetHeadlineTracking)
                            .foregroundStyle(Palette.textPrimary.color)
                        if !row.meta.isEmpty {
                            Text(row.meta)
                                .font(Typography.meta)
                                .foregroundStyle(Palette.textMuted.color)
                        }
                    }
                }

                summary

                // The prototype also promises "and registers it in your Shiny Dex". Dex mode is
                // not built in this app yet, so the copy claims only what this sheet does.
                Text("This closes the hunt and moves it to History.")
                    .font(Typography.stat)
                    .lineSpacing(4)
                    .foregroundStyle(Palette.textMuted.color)

                if let syncError = model.syncError {
                    Text(syncError)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.danger.color)
                }

                Button {
                    act { await model.markFound(row.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 16))
                        Text("Yes, found it")
                    }
                }
                .buttonStyle(WideGoldButtonStyle())

                Button("Keep hunting") { onClose() }
                    .buttonStyle(SecondaryButtonStyle())

                abandonButton
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .disabled(busy)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.fraction(0.62)])
        .presentationCornerRadius(Radii.sheet)
        .presentationBackground(Palette.sheet.color)
        .presentationDragIndicator(.visible)
    }

    /// `Final count` and `Against odds`, side by side in the sunken panel.
    private var summary: some View {
        HStack(alignment: .top) {
            stat("Final count", "\(row.count.formatted(.number)) enc", color: Palette.hunt)
            Spacer(minLength: 10)
            stat(
                "Against odds",
                row.denominator.map { "1 / \($0.formatted(.number))" } ?? "Odds unknown",
                color: Palette.textPrimary,
                alignment: .trailing
            )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Palette.detailPanel.color, in: .rect(cornerRadius: Radii.listCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.listCard)
                .strokeBorder(Palette.hairline.color, lineWidth: 1)
        )
    }

    private func stat(
        _ label: String, _ value: String, color: Swatch, alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 9) {
            Text(label)
                .font(Typography.stat)
                .foregroundStyle(Palette.textMuted.color)
            // `font:600 22px/1;font-variant-numeric:tabular-nums` — this pairing appears only here.
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(color.color)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Abandon hunt — delete without registering", then "Tap again — this deletes the hunt".
    private var abandonButton: some View {
        Button {
            guard abandonArmed else {
                abandonArmed = true
                Haptics.impact(.rigid)
                return
            }
            act { await model.abandon(row.id) }
        } label: {
            Text(
                abandonArmed
                    ? "Tap again — this deletes the hunt"
                    : "Abandon hunt — delete without registering"
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle((abandonArmed ? Palette.danger : Palette.textMuted).color)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(
                        abandonArmed ? Palette.danger.alpha(0x55) : .clear, lineWidth: 1
                    )
            )
            .contentShape(.rect)
        }
    }

    /// Closes only when the write landed — a failed one leaves the sheet up with the error on it.
    private func act(_ operation: @escaping () async -> Bool) {
        busy = true
        Task {
            if await operation() { onClose() }
            busy = false
        }
    }
}

/// `height:46px;border-radius:15px;background:#181822;font:600 17px/1` — "Keep hunting".
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Palette.textSecondary.color)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Palette.surfaceRaised.color, in: .rect(cornerRadius: Radii.row))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.row)
                    .strokeBorder(Palette.border.color, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
