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
    /// Versions of the picked game that have a seeded timeline — nil while unknown, empty when
    /// the game cannot be Nuzlocked at all. One `games` row can cover three versions whose
    /// routes and trainers differ, so this is a real choice, not a formality.
    @State private var versions: [NuzlockeVersionInfo]?
    @State private var version: NuzlockeVersionInfo?
    /// The player's own starter. Rival rosters depend on it — Barry takes the one that beats
    /// yours — so without it two players in three would be shown a team they never fight.
    @State private var starter: String?
    @State private var checking = false
    @State private var dupesClause = true
    @State private var battleStyle: BattleStyle = .set
    @State private var nicknamesRequired = true
    @State private var starting = false
    @State private var failure: String?

    private var canStart: Bool {
        guard gameID != nil, let version, !starting, !checking else { return false }
        return version.starters.isEmpty || starter != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Set your rules")
                    .font(Typography.sheetTitle)
                    .tracking(Typography.sheetTitleTracking)
                    .foregroundStyle(Palette.textPrimary)

                gamePicker
                versionPicker
                starterPicker
                presets
                clauses

                if let failure {
                    Text(failure)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(starting ? "Starting…" : "Start the run") { start() }
                    .buttonStyle(BlueButtonStyle())
                    .disabled(!canStart)
                    .opacity(canStart ? 1 : 0.5)
            }
            .padding(18)
        }
        .background(Palette.sheet)
        .presentationDetents([.large])
        .presentationBackground(Palette.sheet)
        .task { await loadGames() }
    }

    // MARK: Game

    private var gamePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Game")
                .font(Typography.blockLabel)
                .tracking(Typography.blockLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textMuted)

            Menu {
                ForEach(games) { game in
                    Button(game.title) { pick(game.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(games.first { $0.id == gameID }?.title ?? "Pick a game")
                        .font(Typography.segmentOn)
                        .foregroundStyle(gameID == nil ? Palette.textMuted : Palette.textPrimary)
                    Spacer(minLength: 0)
                    if checking {
                        ProgressView().tint(Palette.textMuted)
                    } else {
                        Text("›")
                            .font(Typography.segmentOn)
                            .foregroundStyle(Palette.textFaint)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .frame(maxWidth: .infinity)
                .background(Palette.surface, in: .rect(cornerRadius: Radii.headerButton))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.headerButton)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
            }

            // Routes are seeded per game AND version (`backend/seeds/nuzlocke_*.json`).
            // `CreateRunHandler` rejects an unseeded pair, so it is checked here rather than
            // letting the user fill the whole form and then be refused.
            if let versions, versions.isEmpty, gameID != nil {
                Text("No Nuzlocke route is seeded for this game yet.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Only shown when there is a choice to make. A single seeded version is picked silently —
    /// asking "which version?" of a one-option list is a question with no information in it.
    @ViewBuilder
    private var versionPicker: some View {
        if let versions, versions.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Version")
                    .font(Typography.blockLabel)
                    .tracking(Typography.blockLabelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textMuted)
                HStack(spacing: 2) {
                    ForEach(versions) { candidate in
                        let on = candidate == version
                        Button {
                            version = candidate
                            starter = nil
                        } label: {
                            Text(candidate.version.capitalized)
                                .font(on ? Typography.segmentOn : Typography.segmentOff)
                                .foregroundStyle(on ? Palette.onAccent : Palette.textMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    on ? Palette.nuzlocke : .clear,
                                    in: .rect(cornerRadius: Radii.segmentItem)
                                )
                                .contentShape(.rect)
                        }
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                }
                .padding(3)
                .background(Palette.surface, in: .rect(cornerRadius: Radii.segment))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.segment)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                )
                Text("Routes and trainers differ between versions.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textFaint)
            }
        }
    }

    /// Only shown when this timeline's rosters actually depend on the choice — the server
    /// derives that list from the data and rejects a starter it has no use for, so a game whose
    /// rivals never vary is never asked.
    @ViewBuilder
    private var starterPicker: some View {
        if let version, !version.starters.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your starter")
                    .font(Typography.blockLabel)
                    .tracking(Typography.blockLabelTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textMuted)
                HStack(spacing: 8) {
                    ForEach(version.starters, id: \.self) { candidate in
                        let on = candidate == starter
                        Button { starter = candidate } label: {
                            // ponytail: the name, not a sprite — the API sends starter *names*
                            // and a sprite needs a dex id this screen has no reason to fetch.
                            Text(candidate.capitalized)
                                .font(Typography.segmentOff)
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Palette.surface, in: .rect(cornerRadius: Radii.tile))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radii.tile)
                                    .strokeBorder(
                                        on ? Palette.nuzlocke.alpha(0x99) : Palette.hairline,
                                        lineWidth: on ? 2 : 1
                                    )
                            )
                            .contentShape(.rect)
                        }
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                    }
                }
                Text("Your rival takes the starter that beats yours, and the rest of his team "
                     + "changes with it.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func pick(_ id: Int) {
        gameID = id
        versions = nil
        version = nil
        failure = nil
        checking = true
        Task {
            do {
                let found = try await model.client.nuzlockeVersions(gameID: id)
                versions = found
                version = found.first          // silently correct when there is only one
                starter = nil
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
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.tileSub)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(13)
            .background(Palette.surface, in: .rect(cornerRadius: Radii.block))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.block)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
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
        .background(Palette.surface, in: .rect(cornerRadius: Radii.block))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.block)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Typography.segmentOn)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(Typography.tileSub)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .tint(Palette.nuzlocke)
        .padding(.vertical, 13)
    }

    private func start() {
        guard let gameID, let version else { return }
        starting = true
        failure = nil
        Task {
            failure = await model.startRun(
                CreateRunRequest(
                    gameID: gameID,
                    version: version.version,
                    starter: starter,
                    dupesClause: dupesClause,
                    battleStyle: battleStyle,
                    nicknamesRequired: nicknamesRequired
                ))
            starting = false
            if failure == nil { dismiss() }
        }
    }
}
