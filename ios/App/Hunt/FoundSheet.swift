import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// The ✦ confirm: "The ✦ button marks it found — behind a confirm, which is also where you can
/// abandon a hunt."
///
/// Two irreversible things live on one sheet on purpose, because that is where the design put
/// them, and they are told apart by weight: found is the gold full-width button, abandon is a
/// bare row of text that has to be tapped twice.
///
/// Phases live here too, and reached from ✦ rather than from a fifth control on the card: a phase
/// starts the same way a find does — a shiny appeared — and only turns into a different action once
/// you see it is the wrong species. The control row is also already full, and the answer to "where
/// does the fifth button go" is usually that it doesn't.
struct FoundSheet: View {
    /// A snapshot taken when the sheet opened. The card behind it is covered, so the count
    /// cannot move underneath.
    let row: HuntRow
    let model: HuntListModel
    let onClose: () -> Void

    /// `s.abandonArm`. Sheet-local: dismissing disarms it, which is the behaviour you want.
    @State private var abandonArmed = false
    @State private var busy = false
    /// Swaps this sheet to the species picker rather than stacking a second sheet on top of it.
    @State private var phasing = false

    var body: some View {
        if phasing {
            PhasePicker(row: row, model: model, onCancel: { phasing = false }, onClose: onClose)
        } else {
            confirmBody
        }
    }

    private var confirmBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    SpriteTile(pokemonID: row.detail.pokemonID, size: 72)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Found \(row.name)?")
                            .font(Typography.sheetHeadline)
                            .tracking(Typography.sheetHeadlineTracking)
                            .foregroundStyle(Palette.textPrimary)
                        if !row.meta.isEmpty {
                            Text(row.meta)
                                .font(Typography.meta)
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                }

                summary

                // The prototype also promises "and registers it in your Shiny Dex". Dex mode is
                // not built in this app yet, so the copy claims only what this sheet does.
                Text("This closes the hunt and moves it to History.")
                    .font(Typography.stat)
                    .lineSpacing(4)
                    .foregroundStyle(Palette.textMuted)

                if let syncError = model.syncError {
                    Text(syncError)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.danger)
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

                // The other thing a shiny can be. Phrased as the species rather than as the
                // jargon — "phase" is the record it writes, not the thing that just happened.
                Button("A different shiny showed up") { phasing = true }
                    .buttonStyle(SecondaryButtonStyle())

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
        .presentationBackground(Palette.sheet)
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
        .background(Palette.detailPanel, in: .rect(cornerRadius: Radii.listCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.listCard)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    private func stat(
        _ label: String, _ value: String, color: Color, alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 9) {
            Text(label)
                .font(Typography.stat)
                .foregroundStyle(Palette.textMuted)
            // `font:600 22px/1;font-variant-numeric:tabular-nums` — this pairing appears only here.
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
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
            .foregroundStyle(abandonArmed ? Palette.danger : Palette.textMuted)
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

// MARK: - Phase

/// Names the shiny that interrupted the hunt, then banks the phase.
///
/// A search rather than a picked-from-the-route list: the interrupter can be anything the encounter
/// table can produce, and the hunter is looking straight at it.
struct PhasePicker: View {
    let row: HuntRow
    let model: HuntListModel
    let onCancel: () -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var results: [Pokemon] = []
    @State private var searching = false
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What showed up?")
                        .font(Typography.sheetHeadline)
                        .tracking(Typography.sheetHeadlineTracking)
                        .foregroundStyle(Palette.textPrimary)
                    // Says the number out loud before it is spent. A phase is not undoable from
                    // here, and the count is the thing it consumes.
                    Text(
                        """
                        \(row.name) is at \(row.count.formatted(.number)) encounters. Logging a \
                        phase banks that count against the shiny you pick and starts this hunt \
                        again from zero.
                        """
                    )
                    .font(Typography.stat)
                    .lineSpacing(4)
                    .foregroundStyle(Palette.textMuted)
                }

                TextField("Search species", text: $query)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(Typography.primaryButton)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(Palette.field, in: .rect(cornerRadius: Radii.row))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radii.row)
                            .strokeBorder(Palette.border, lineWidth: 1)
                    )

                if !results.isEmpty { resultList }
                emptyHint

                Button("Back") { onCancel() }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .disabled(busy)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large])
        .presentationCornerRadius(Radii.sheet)
        .presentationBackground(Palette.sheet)
        .presentationDragIndicator(.visible)
        // `.task(id:)` cancels the previous run on every keystroke, so the sleep below *is* the
        // debounce — no timer, no cancellation bookkeeping of our own.
        .task(id: query) { await search() }
    }

    private var resultList: some View {
        VStack(spacing: 8) {
            ForEach(results) { pokemon in
                Button {
                    busy = true
                    Task {
                        if await model.logPhase(row.id, pokemonID: pokemon.id) { onClose() }
                        busy = false
                    }
                } label: {
                    HStack(spacing: 13) {
                        SpriteTile(pokemonID: pokemon.id, size: 40, served: pokemon.shinySpriteURL)
                        Text(pokemon.name.capitalized)
                            .font(Typography.listTitle)
                            .foregroundStyle(Palette.textPrimary)
                        Spacer(minLength: 8)
                        Text((pokemon.types ?? []).map(\.capitalized).joined(separator: " · "))
                            .font(Typography.stat)
                            .foregroundStyle(Palette.textMuted)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(Palette.surface, in: .rect(cornerRadius: Radii.row))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radii.row)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Log \(pokemon.name.capitalized) as a phase")
            }
        }
    }

    @ViewBuilder
    private var emptyHint: some View {
        if results.isEmpty, !searching, query.trimmingCharacters(in: .whitespaces).count >= 2 {
            Text("Nothing matches \"\(query)\". Try a different spelling.")
                .font(Typography.hint)
                .foregroundStyle(Palette.textMuted)
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        searching = true
        results = await model.searchPokemon(trimmed)
        searching = false
    }
}

/// `height:46px;border-radius:15px;background:#181822;font:600 17px/1` — "Keep hunting".
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(Palette.surfaceRaised, in: .rect(cornerRadius: Radii.row))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.row)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
