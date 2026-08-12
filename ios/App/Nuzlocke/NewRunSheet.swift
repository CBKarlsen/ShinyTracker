import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// "Set your rules" — screen `1g` of `docs/design/mobile-app.dc.html`.
///
/// Only three of the prototype's clauses are real: the API stores `dupes_clause`,
/// `battle_style` and `nicknames_required` and nothing else. The shiny clause and custom rules
/// are honour-system rules with nowhere to live, and a switch that saves nothing is worse than
/// no switch — so they are absent rather than decorative.
struct NewRunSheet: View {
    @State var model: NuzlockeModel
    @Environment(\.dismiss) private var dismiss

    @State private var games: [Game] = []
    @State private var gameID: Int?
    /// How many timeline stops the picked game has seeded — nil while unknown.
    @State private var seededStops: Int?
    @State private var checking = false
    @State private var dupesClause = true
    @State private var battleStyle: BattleStyle = .set
    @State private var nicknamesRequired = true
    @State private var starting = false
    @State private var failure: String?

    private var canStart: Bool {
        gameID != nil && !starting && !checking && (seededStops ?? 0) > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Set your rules")
                    .font(Typography.sheetTitle)
                    .tracking(Typography.sheetTitleTracking)
                    .foregroundStyle(Palette.textPrimary.color)

                gamePicker
                presets
                clauses

                if let failure {
                    Text(failure)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.danger.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(starting ? "Starting…" : "Start the run") { start() }
                    .buttonStyle(BlueButtonStyle())
                    .disabled(!canStart)
                    .opacity(canStart ? 1 : 0.5)
            }
            .padding(18)
        }
        .background(Palette.sheet.color)
        .presentationDetents([.large])
        .presentationBackground(Palette.sheet.color)
        .task { await loadGames() }
    }

    // MARK: Game

    private var gamePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Game")
                .font(Typography.blockLabel)
                .tracking(Typography.blockLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textMuted.color)

            Menu {
                ForEach(games) { game in
                    Button(game.title) { pick(game.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(games.first { $0.id == gameID }?.title ?? "Pick a game")
                        .font(Typography.segmentOn)
                        .foregroundStyle(
                            (gameID == nil ? Palette.textMuted : Palette.textPrimary).color)
                    Spacer(minLength: 0)
                    if checking {
                        ProgressView().tint(Palette.textMuted.color)
                    } else {
                        Text("›")
                            .font(Typography.segmentOn)
                            .foregroundStyle(Palette.textFaint.color)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .frame(maxWidth: .infinity)
                .background(Palette.surface.color, in: .rect(cornerRadius: Radii.headerButton))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.headerButton)
                        .strokeBorder(Palette.hairline.color, lineWidth: 1)
                )
            }

            // Routes are seeded per game (`backend/seeds/nuzlocke_*.json`) and today only
            // Platinum has any. `CreateRunHandler` rejects a game with no timeline, so the pick
            // is checked here instead of letting the user fill the form and then be refused.
            if let stops = seededStops, gameID != nil {
                Text(
                    stops > 0
                        ? "\(stops) stops seeded — routes and checkpoints in order"
                        : "No Nuzlocke route is seeded for this game yet."
                )
                .font(Typography.hint)
                .foregroundStyle((stops > 0 ? Palette.textMuted : Palette.danger).color)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pick(_ id: Int) {
        gameID = id
        seededStops = nil
        failure = nil
        checking = true
        Task {
            do {
                seededStops = try await model.client.nuzlockeTimeline(gameID: id).count
            } catch {
                failure = userFacingMessage(for: error)
            }
            checking = false
        }
    }

    private func loadGames() async {
        do {
            games = try await model.client.games()
                .sorted { ($0.generation, $0.id) < ($1.generation, $1.id) }
        } catch {
            failure = userFacingMessage(for: error)
        }
    }

    // MARK: Rules

    /// The prototype's two presets, reduced to the switches that actually persist.
    private var presets: some View {
        HStack(spacing: 8) {
            preset("Classic", detail: "Faint = death, one per route") {
                dupesClause = true
                battleStyle = .shift
                nicknamesRequired = false
            }
            preset("Hardcore", detail: "Set mode, nickname everything") {
                dupesClause = true
                battleStyle = .set
                nicknamesRequired = true
            }
        }
    }

    private func preset(
        _ title: String, detail: String, apply: @escaping () -> Void
    ) -> some View {
        Button(action: apply) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Typography.segmentOn)
                    .foregroundStyle(Palette.textPrimary.color)
                Text(detail)
                    .font(Typography.tileSub)
                    .foregroundStyle(Palette.textMuted.color)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(Palette.surface.color, in: .rect(cornerRadius: Radii.block))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.block)
                    .strokeBorder(Palette.hairline.color, lineWidth: 1)
            )
            .contentShape(.rect)
        }
    }

    private var clauses: some View {
        VStack(spacing: 0) {
            toggle(
                "Dupes clause", detail: "Re-roll species you already own",
                isOn: $dupesClause)
            divider
            toggle(
                "Set battle mode", detail: "No free switch on KO",
                isOn: Binding(
                    get: { battleStyle == .set },
                    set: { battleStyle = $0 ? .set : .shift }
                ))
            divider
            toggle(
                "Nickname everything", detail: "Every catch needs a name",
                isOn: $nicknamesRequired)
        }
        .padding(.horizontal, 15)
        .background(Palette.surface.color, in: .rect(cornerRadius: Radii.block))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.block)
                .strokeBorder(Palette.hairline.color, lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline.color).frame(height: 1)
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.segmentOn)
                    .foregroundStyle(Palette.textPrimary.color)
                Text(detail)
                    .font(Typography.tileSub)
                    .foregroundStyle(Palette.textMuted.color)
            }
        }
        .tint(Palette.nuzlocke.color)
        .padding(.vertical, 13)
    }

    private func start() {
        guard let gameID else { return }
        starting = true
        failure = nil
        Task {
            failure = await model.startRun(
                CreateRunRequest(
                    gameID: gameID,
                    dupesClause: dupesClause,
                    battleStyle: battleStyle,
                    nicknamesRequired: nicknamesRequired
                ))
            starting = false
            if failure == nil { dismiss() }
        }
    }
}
