import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// Champions is the game a team is built for, and the backend says so too — `championsGameID` in
/// `backend/internal/api/teams.go`, and the `games` row inserted by migration 025. It is the
/// `game_id` the member sheet asks `GET /api/pokemon/{id}` for, which is what makes the move
/// picker that game's real moveset rather than every move the species has ever learned.
///
/// 18, not 17: 17 is Scarlet/Violet, and the Champions movesets are seeded under 18. Getting this
/// wrong does not fail loudly — the picker fills with a plausible *Scarlet/Violet* learnset for a
/// team that cannot use it.
let championsGameID = 18

/// The Teams mode: every saved team, six sprites wide.
///
/// Same shape as ``DexScreen`` — loading spinner, ``StateBlock`` on failure with a retry, a
/// ``StateBlock`` invitation when the list is empty, rows when it is not. Green throughout:
/// "each mode owns a colour, so you always know where you are".
struct TeamsScreen: View {
    @State var model: TeamsModel
    let client: APIClient

    @State private var editing: EditorTarget?
    /// The banner is dismissible, but ``TeamsModel/syncError`` is `private(set)` and clears itself
    /// on the next call — so "dismissed" is remembered here, by message. A *new* failure carries a
    /// different string and shows again, which is the behaviour you want: dismissing one stale
    /// warning must not silence the next real one.
    @State private var dismissedError: String?
    @State private var importing = false
    /// What the last import skipped, if anything — shown in the same banner as a sync failure,
    /// because "your team is here, minus two Pokémon" is exactly as important to see.
    @State private var importNote: String?

    /// `Team` cannot be the navigation value: `navigationDestination(item:)` needs `Hashable` and
    /// `Team` holds `[TeamMember]`, which holds two dictionaries. The id is all the editor needs.
    enum EditorTarget: Hashable, Identifiable {
        case new
        case existing(UUID)

        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                syncBanner
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Teams")
            .navigationSubtitle(model.state == .ready ? subtitle : "")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("Import a Showdown paste")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = .new } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New team")
                }
            }
            .navigationDestination(item: $editing) { target in
                TeamEditorScreen(model: model, client: client, team: team(for: target))
            }
            .sheet(isPresented: $importing) {
                ImportPasteSheet(model: model, client: client) { note in
                    importNote = note
                }
            }
        }
        .task {
            // The note belongs to the screen it was raised on and no longer than that. Left
            // standing it would outrank — and so hide — every sync failure that followed it,
            // which is the same "one stale warning silences the next real one" failure
            // `dismissedError` is keyed by message to avoid.
            importNote = nil
            await model.appear()
        }
    }

    private var subtitle: String {
        model.teams.count == 1 ? "1 team" : "\(model.teams.count) teams"
    }

    private func team(for target: EditorTarget) -> Team? {
        guard case .existing(let id) = target else { return nil }
        return model.teams.first { $0.id == id }
    }

    // MARK: Sync banner

    /// Above the content, never instead of it: a refresh that failed still leaves the cached teams
    /// on screen, and replacing them with an error would throw away work the user can still edit.
    /// An import outcome outranks a sync warning: it is the thing that just happened, and it is
    /// the only place the skipped Pokémon are ever named.
    private var bannerMessage: String? {
        if let importNote { return importNote }
        guard let message = model.syncError, message != dismissedError else { return nil }
        return message
    }

    @ViewBuilder
    private var syncBanner: some View {
        if let message = bannerMessage {
            HStack(alignment: .top, spacing: 8) {
                Text(message)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    if importNote != nil { importNote = nil } else { dismissedError = message }
                } label: {
                    Image(systemName: "xmark")
                        .font(Typography.statStrong)
                        .foregroundStyle(Palette.textMuted)
                        .frame(width: Metrics.controlNarrow)
                        .frame(minHeight: Metrics.controlNarrow)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(.leading, 14)
            .padding(.trailing, 2)
            .padding(.vertical, 4)
            .background(Palette.surface, in: .rect(cornerRadius: Radii.row))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.row)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, 8)
        }
    }

    // MARK: States

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .tint(Palette.textMuted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let reason):
            StateBlock(
                symbol: "exclamationmark.triangle",
                title: "Couldn't load your teams",
                body: reason,
                tint: Palette.team
            ) {
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(GreenButtonStyle())
                    .padding(.top, 22)
            }
            .padding(.horizontal, Metrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

        case .ready:
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.cardGap) {
                if model.teams.isEmpty {
                    StateBlock(
                        symbol: "square.grid.3x2",
                        title: "No teams yet",
                        body: "Six slots, natures, stat points and moves — built against the Champions learnsets.",
                        tint: Palette.team
                    ) {
                        Button("Build a team") { editing = .new }
                            .buttonStyle(GreenButtonStyle())
                            .padding(.top, 22)
                    }
                    .padding(.top, 6)
                } else {
                    ForEach(model.teams) { team in
                        row(team)
                    }
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
        }
        .scrollIndicators(.hidden)
        // Same reason as the `.task` above: a refresh is the next event, and whatever it has to
        // say outranks what the last import had to say.
        .refreshable {
            importNote = nil
            await model.refresh()
        }
    }

    private func row(_ team: Team) -> some View {
        Button { editing = .existing(team.id) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text(team.name)
                        .font(Typography.listTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(filledLabel(team))
                        .font(Typography.tileSub)
                        .foregroundStyle(Palette.textMuted)
                    Image(systemName: "chevron.right")
                        .font(Typography.tileSub)
                        .foregroundStyle(Palette.textFaint)
                }

                HStack(spacing: 6) {
                    ForEach(1...6, id: \.self) { slot in
                        if let member = team.members.first(where: { $0.slot == slot }) {
                            SpriteTile(pokemonID: member.pokemonID, size: 44, shiny: false)
                        } else {
                            EmptySlotPlate(size: 44)
                        }
                    }
                }
            }
            .padding(Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: .rect(cornerRadius: Radii.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.card)
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .accessibilityLabel("\(team.name), \(filledLabel(team))")
    }

    private func filledLabel(_ team: Team) -> String {
        "\(team.members.count) of 6"
    }
}

// MARK: - Shared pieces

/// The hole a sprite would fill. Same plate as ``SpriteTile``'s background, one tier quieter, so a
/// half-built team reads as six slots rather than as three sprites and some missing images.
struct EmptySlotPlate: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: Radii.sprite(size))
            .fill(Palette.surfaceRaised)
            .frame(width: size, height: size)
            .overlay(
                RoundedRectangle(cornerRadius: Radii.sprite(size))
                    .strokeBorder(Palette.hairline, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// ``SpeciesSheet``'s labelled block, lifted out so the editor and the member sheet share it.
struct TeamBlock<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title)
                .font(Typography.blockLabel)
                .tracking(Typography.blockLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textMuted)
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceBlock, in: .rect(cornerRadius: Radii.block))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.block)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}

/// Hunt's ``GoldButtonStyle`` in Teams green, exactly as ``BlueButtonStyle`` is for a run.
/// `minHeight`, not `height`: at the accessibility text sizes a fixed 54 clips the label.
struct GreenButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.primaryButton)
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Metrics.controlHeight)
            .background(Palette.team, in: .rect(cornerRadius: Radii.control))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}
