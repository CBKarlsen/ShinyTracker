import Foundation
import ShinyTrackerAPI
import ShinyTrackerKit
import ShinyTrackerUI
import SwiftUI

/// The new-hunt flow: "search a species, pick a game, pick a method, start. The sheet grows step
/// by step and the chips at its top jump back."
@MainActor
@Observable
final class NewHuntModel {
    /// The prototype's `s.step` 1…4, with its sheet height and copy attached.
    enum Step: Int, CaseIterable {
        case species = 1, game, method, ready

        /// `stepMeta[n].t`
        var title: String {
            switch self {
            case .species: "Which Pokémon?"
            case .game: "Which game?"
            case .method: "Which method?"
            case .ready: "Ready"
            }
        }

        /// `stepMeta[n].h`
        var hint: String {
            switch self {
            case .species: "Search by name. You can change the game and method next."
            case .game: "Base odds and Shiny Charm support come from the game."
            case .method: "Rate and pace, side by side. Pick the one you actually want to play."
            case .ready: ""
            }
        }

        /// `stepMeta[n].h2` — the sheet's height as a fraction of the screen.
        var height: CGFloat {
            switch self {
            case .species: 0.76
            case .game: 0.66
            case .method: 0.80
            // The prototype's 56%. Raised because the same content — 76pt sprite, four rows,
            // a 52pt button — does not fit 56% of a real iPhone at system type sizes.
            case .ready: 0.70
            }
        }
    }

    private(set) var step: Step = .species

    // --- step 1 ---
    var query = ""
    private(set) var results: [Pokemon] = []
    private(set) var searching = false

    // --- the picks ---
    private(set) var species: Pokemon?
    private(set) var gameID: Int?
    private(set) var method: HuntMethodDetail?

    /// Every method that can catch ``species`` in a game the owner has. One fetch feeds both the
    /// game step (its distinct games) and the method step — `GET /api/hunt-methods` already joins
    /// `user_games`, so there is nothing to filter client-side.
    private(set) var methods: [HuntMethodDetail] = []
    private(set) var loadingMethods = false

    /// Optional name for the catch, sent with `POST /api/hunts`.
    ///
    /// Capped as it is typed: the server rejects anything over 100 characters with a 400, and
    /// finding that out after tapping Start would lose the whole sheet's worth of picks. Counted
    /// in Characters, matching the runes the Go side counts, so an emoji costs one either way.
    var nickname = "" {
        didSet {
            if nickname.count > Self.nicknameLimit {
                nickname = String(nickname.prefix(Self.nicknameLimit))
            }
        }
    }
    static let nicknameLimit = 100

    private(set) var starting = false
    private(set) var error: String?

    let library: GameLibraryModel
    private let client: APIClient
    private var searchTask: Task<Void, Never>?

    init(client: APIClient, library: GameLibraryModel) {
        self.client = client
        self.library = library
    }

    // MARK: Navigation

    /// Reopening starts clean — `openSheet` resets `query` and all three picks.
    func open() {
        step = .species
        query = ""
        nickname = ""
        species = nil
        gameID = nil
        method = nil
        methods = []
        error = nil
        Task { await search() }
    }

    func jump(to step: Step) { self.step = step }

    func pick(species: Pokemon) {
        self.species = species
        gameID = nil
        method = nil
        step = .game
        Task { await loadMethods(species.id) }
    }

    func pick(gameID: Int) {
        self.gameID = gameID
        method = nil
        step = .method
    }

    func pick(method: HuntMethodDetail) {
        self.method = method
        step = .ready
    }

    // MARK: Step 1 — species

    /// Debounced so a fast typist sends one request, not one per keystroke.
    func queryChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.search()
        }
    }

    private func search() async {
        searching = true
        error = nil
        do {
            // An empty query is not an error: the server answers the first 50 species, which is
            // a better opening screen than a blank one.
            results = try await client.pokemon(search: query.trimmingCharacters(in: .whitespaces))
        } catch {
            results = []
            self.error = userFacingMessage(for: error)
        }
        searching = false
    }

    // MARK: Step 2 — games

    private func loadMethods(_ pokemonID: Int) async {
        loadingMethods = true
        error = nil
        do {
            methods = try await client.huntMethods(pokemonID: pokemonID)
        } catch {
            methods = []
            self.error = userFacingMessage(for: error)
        }
        loadingMethods = false
    }

    /// The games this species can be hunted in, in the order the API returned them (generation
    /// ascending), each with how many methods it offers.
    var gameOptions: [(game: Game, methodCount: Int)] {
        var order: [Int] = []
        var counts: [Int: Int] = [:]
        for method in methods {
            if counts[method.gameID] == nil { order.append(method.gameID) }
            counts[method.gameID, default: 0] += 1
        }
        // A game present in method_availability but missing from GET /api/games cannot be
        // priced — no base_odds, no honest odds — so it is dropped rather than guessed at.
        return order.compactMap { id in
            library.game(id).map { ($0, counts[id] ?? 0) }
        }
    }

    // MARK: Step 3 — methods

    var methodOptions: [HuntMethodDetail] {
        guard let gameID else { return [] }
        return methods.filter { $0.gameID == gameID }
    }

    /// `1 / N` for a method at its BEST realistic case, computed on device by ``ShinyOdds``.
    ///
    /// Best case, not first-encounter, because this is a picker. With empty params a chain
    /// method sits at chain zero, where Poké Radar reads 1/8192 — the same as full odds —
    /// so the list would tell you nothing and make every chain method look pointless. The
    /// design quotes the radar at its cap for exactly this reason. ``bestCaseNote(for:)``
    /// supplies the qualifier shown beside the number, so the best case can never be
    /// mistaken for the hunt's current odds.
    func odds(for method: HuntMethodDetail, hasCharm: Bool? = nil) -> Int? {
        guard let game = library.game(method.gameID), game.baseOdds > 0 else { return nil }
        return ShinyOdds.effectiveOdds(
            formulaType: method.formulaType,
            params: ShinyOdds.defaultParams(for: method.formulaType),
            base: OddsConfig(
                baseOdds: game.baseOdds,
                baseRolls: method.baseRolls,
                charmRolls: method.charmRolls
            ),
            hasCharm: hasCharm ?? library.charmOn(method.gameID)
        )
    }

    /// The qualifier for ``odds(for:hasCharm:)`` — "at chain 40" and friends.
    func oddsNote(for method: HuntMethodDetail) -> String? {
        ShinyOdds.bestCaseNote(for: method.formulaType)
    }

    // MARK: Step 4 — start

    /// `POST /api/hunts`. Returns true when the hunt exists, so the caller can close and refresh.
    func start() async -> Bool {
        guard let species, let gameID, let method, !starting else { return false }
        starting = true
        error = nil
        defer { starting = false }
        do {
            let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try await client.createHunt(
                CreateHuntRequest(
                    pokemonID: species.id,
                    gameID: gameID,
                    huntMethodID: method.id,
                    // Absent, not "": the column holds a real name or NULL, and the update path
                    // reads an empty string as "clear this".
                    nickname: trimmed.isEmpty ? nil : trimmed
                )
            )
            Haptics.notify(.success)
            return true
        } catch {
            if let message = userFacingMessage(for: error) {
                self.error = "Couldn't start that hunt. \(message)"
            }
            return false
        }
    }
}

// MARK: - View

/// The stepped sheet behind the header's gold +.
///
/// Presented with SwiftUI's own `.sheet`, so the grabber, the dimmed backdrop, the slide-up and
/// the drag-to-dismiss are the platform's — the prototype hand-builds all four in CSS because
/// the web has none of them. `presentationDetents` carries the step-by-step growth.
struct NewHuntSheet: View {
    @Bindable var model: NewHuntModel
    /// Called once the hunt exists.
    let onStarted: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.fraction(model.step.height)])
        .presentationCornerRadius(Radii.sheet)
        .presentationBackground(Palette.sheet)
        .presentationDragIndicator(.visible)
    }

    // MARK: Header

    /// `padding:16px 18px 0` — title, close, hint, then the crumbs that jump back.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.step.title)
                    .font(Typography.cardTitle)
                    .tracking(Typography.cardTitleTracking)
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 8)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Palette.surfaceRaised, in: .rect(cornerRadius: Radii.badge))
                        .contentShape(.rect)
                }
                .accessibilityLabel("Close")
            }

            if !model.step.hint.isEmpty {
                Text(model.step.hint)
                    .font(Typography.meta)
                    .foregroundStyle(Palette.textMuted)
                    .padding(.top, 8)
            }

            if !crumbs.isEmpty {
                HStack(spacing: 7) {
                    ForEach(crumbs, id: \.label) { crumb in
                        Button { model.jump(to: crumb.step) } label: {
                            Text(crumb.label)
                                .font(Typography.summary)
                                .foregroundStyle(Palette.textSecondary)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                // `border-radius:9px;background:#181822` — used only here.
                                .background(Palette.surfaceRaised, in: .rect(cornerRadius: 9))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .strokeBorder(Palette.border, lineWidth: 1)
                                )
                        }
                        .accessibilityLabel("Change \(crumb.label)")
                    }
                }
                .padding(.top, 13)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private var crumbs: [(label: String, step: NewHuntModel.Step)] {
        var crumbs: [(String, NewHuntModel.Step)] = []
        if let species = model.species { crumbs.append((species.name.capitalized, .species)) }
        if let gameID = model.gameID, let game = model.library.game(gameID) {
            crumbs.append((game.title, .game))
        }
        return crumbs
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .species: speciesStep
        case .game: gameStep
        case .method: methodStep
        case .ready: readyStep
        }
    }

    /// `height:46px;border-radius:14px;background:#0d0d12;border:1px solid #25252f` plus the list.
    private var speciesStep: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(Palette.textMuted)
                TextField("Search Pokémon", text: $model.query)
                    .font(.system(size: 17))
                    .foregroundStyle(Palette.textPrimary)
                    .tint(Palette.hunt)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Palette.field, in: .rect(cornerRadius: Radii.headerButton))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.headerButton)
                    .strokeBorder(Palette.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
            .padding(.top, 14)

            stepList {
                ForEach(model.results) { pokemon in
                    Button { model.pick(species: pokemon) } label: {
                        listRow(
                            title: pokemon.name.capitalized,
                            subtitle: (pokemon.types ?? []).map(\.capitalized).joined(separator: " · "),
                            pokemonID: pokemon.id
                        )
                    }
                    .accessibilityLabel("Hunt \(pokemon.name.capitalized)")
                }

                if model.results.isEmpty, !model.searching {
                    Text(
                        model.error
                            ?? "Nothing matches \"\(model.query)\". Try a different spelling."
                    )
                    .font(Typography.emptyBody)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                }
            }
        }
        .onChange(of: model.query) { model.queryChanged() }
    }

    private var gameStep: some View {
        stepList {
            if model.loadingMethods {
                ProgressView().tint(Palette.textMuted).frame(maxWidth: .infinity).padding(.top, 26)
            } else if model.gameOptions.isEmpty {
                // The dead end that actually happens: `GET /api/hunt-methods` joins `user_games`,
                // so an empty library answers nothing for every species. Name the fix.
                emptyStep(
                    model.error
                        ?? """
                        No method reaches \(model.species?.name.capitalized ?? "this species") \
                        in the games in your library. Add the games you own in the Games tab.
                        """
                )
            } else {
                ForEach(model.gameOptions, id: \.game.id) { option in
                    Button { model.pick(gameID: option.game.id) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(option.game.title)
                                    .font(Typography.listTitle)
                                    .foregroundStyle(Palette.textPrimary)
                                Text(gameMeta(option))
                                    .font(Typography.stat)
                                    .foregroundStyle(Palette.textMuted)
                            }
                            // A Button label centres wrapped text by default, which reads as a
                            // stray indent on every two-line game title.
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            CharmTag(
                                hasCharm: shinyCharmAvailable(option.game.id),
                                charmOn: model.library.charmOn(option.game.id)
                            )
                        }
                        .padding(.vertical, 13)
                        .padding(.horizontal, 15)
                        .background(Palette.surface, in: .rect(cornerRadius: Radii.listCard))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radii.listCard)
                                .strokeBorder(Palette.hairline, lineWidth: 1)
                        )
                        .contentShape(.rect)
                    }
                }
            }
        }
    }

    /// `${g.gen} · base 1/${fmtNum(g.base)} · ${g.methods.length} methods`
    private func gameMeta(_ option: (game: Game, methodCount: Int)) -> String {
        let methods = option.methodCount == 1 ? "1 method" : "\(option.methodCount) methods"
        return """
            \(generationLabel(option.game.generation)) · \
            base 1/\(option.game.baseOdds.formatted(.number)) · \(methods)
            """
    }

    private var methodStep: some View {
        stepList {
            ForEach(model.methodOptions) { method in
                Button { model.pick(method: method) } label: {
                    methodCard(method)
                }
                .accessibilityLabel(methodAccessibility(method))
            }

            // The prototype's own disclaimer, and the reason there is no "recommended" badge.
            Text("Odds only — nothing here is recommended over anything else.")
                .font(Typography.stat)
                .lineSpacing(4)
                .foregroundStyle(Palette.textFaint)
                .padding(.horizontal, 2)
                .padding(.top, 4)
        }
    }

    /// `padding:13px 15px;border-radius:16px` — name, odds, and the odds note.
    ///
    /// No pace and no time-to-expected. `avg_time_seconds` is one constant on the method row
    /// shared by every game that method appears in — the same 30 s stands for a GBA soft reset and
    /// a Switch one — so multiplying it by the odds denominator produced a confident total that
    /// was routinely off by a factor of two. A number that wrong is worse than no number.
    private func methodCard(_ method: HuntMethodDetail) -> some View {
        let denominator = model.odds(for: method)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(method.methodName)
                    .font(Typography.listTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                // The qualifier is not decoration: without it "1 / 200" reads as this
                // method's odds right now, when it is the value at the chain cap.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(denominator.map { "1 / \($0.formatted(.number))" } ?? "Odds unknown")
                        .font(Typography.oddsValue)
                        .foregroundStyle(Palette.hunt)
                        .lineLimit(1)
                    if let note = model.oddsNote(for: method) {
                        Text(note)
                            .font(Typography.stat)
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(1)
                    }
                }
            }

        }
        .padding(.vertical, 13)
        .padding(.horizontal, 15)
        .background(Palette.surface, in: .rect(cornerRadius: Radii.listCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.listCard)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .contentShape(.rect)
    }

    private func methodAccessibility(_ method: HuntMethodDetail) -> String {
        guard let denominator = model.odds(for: method) else {
            return "\(method.methodName), odds unknown"
        }
        return "\(method.methodName), 1 in \(denominator.formatted(.number))"
    }

    /// The Ready step: the gold-glow card, the four facts, and the one button.
    @ViewBuilder
    private var readyStep: some View {
        if let species = model.species, let method = model.method,
            let game = model.library.game(method.gameID)
        {
            ScrollView {
              VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    SpriteTile(pokemonID: species.id, size: 76)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(species.name.capitalized)
                            .font(Typography.sheetHeadline)
                            .tracking(Typography.sheetHeadlineTracking)
                            .foregroundStyle(Palette.textPrimary)
                        Text("\(game.title) · \(method.methodName)")
                            .font(Typography.meta)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.confirmCard, in: .rect(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Palette.hunt.alpha(0x55), lineWidth: 1)
                )
                .shadow(color: Palette.hunt.alpha(0x55), radius: 15, y: 2)

                DetailPanel(rows: readyRows(game: game, method: method))

                nicknameField(for: species)

                if let error = model.error {
                    Text(error)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.danger)
                }

                Spacer(minLength: 0)

                Button {
                    Task { if await model.start() { onStarted() } }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 16))
                        Text("Start hunting")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(WideGoldButtonStyle())
                .disabled(model.starting)
              }
              .padding(.horizontal, 18)
              .padding(.top, 16)
              .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// Optional, and says so — a hunt with no nickname is the normal case, so the field must not
    /// read as one more thing to fill in before the gold button will work.
    private func nicknameField(for species: Pokemon) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("NICKNAME · OPTIONAL")
                .font(Typography.overline)
                .tracking(Typography.overlineTracking)
                .foregroundStyle(Palette.textMuted)

            TextField("Name your \(species.name.capitalized)", text: $model.nickname)
                .font(.system(size: 17))
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.hunt)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Palette.field, in: .rect(cornerRadius: Radii.headerButton))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.headerButton)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
                .accessibilityLabel("Nickname, optional")
        }
    }

    /// `confirmRows` — odds and charm. Pace and expected time are deliberately absent; see
    /// ``methodCard`` for why a projection off `avg_time_seconds` is not worth showing.
    private func readyRows(game: Game, method: HuntMethodDetail) -> [DetailRow] {
        let denominator = model.odds(for: method)
        return [
            DetailRow(
                "Odds per encounter",
                denominator.map { "1 / \($0.formatted(.number))" } ?? "Unknown",
                accent: true
            ),
            DetailRow("Shiny Charm", charmSummary(game: game, method: method)),
        ]
    }

    /// The prototype prints `Applied (+${game.charmRolls} rolls)` whenever the charm is on, which
    /// would be a lie here for the three formulas that ignore `hasCharm` outright
    /// (`radar_chain_gen4`, `radar_chain_bdsp`, `ultra_wormhole`). Asking the engine both ways is
    /// the only answer that cannot drift from what the odds above actually did.
    private func charmSummary(game: Game, method: HuntMethodDetail) -> String {
        guard shinyCharmAvailable(game.id) else { return "Not in this game" }
        guard model.library.charmOn(game.id) else { return "Off in library" }
        let with = model.odds(for: method, hasCharm: true)
        let without = model.odds(for: method, hasCharm: false)
        guard with != without else { return "No effect on this method" }
        return "Applied (+\(method.charmRolls) rolls)"
    }

    // MARK: Shared shell

    /// `flex:1;min-height:0;overflow-y:auto;padding:14px 18px 22px;gap:8px`
    private func stepList(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 22)
        }
        .scrollIndicators(.hidden)
    }

    private func emptyStep(_ message: String) -> some View {
        Text(message)
            .font(Typography.emptyBody)
            .lineSpacing(4)
            .foregroundStyle(Palette.textMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
    }

    /// `padding:10px 13px;border-radius:15px` — sprite, name, subtitle, chevron.
    private func listRow(title: String, subtitle: String, pokemonID: Int) -> some View {
        HStack(spacing: 13) {
            SpriteTile(pokemonID: pokemonID, size: 44)
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(Typography.listTitle)
                    .foregroundStyle(Palette.textPrimary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Typography.stat)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundStyle(Palette.textFaint)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 13)
        .background(Palette.surface, in: .rect(cornerRadius: Radii.row))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.row)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .contentShape(.rect)
    }
}

// MARK: - Key/value panel

/// One line of the `#0f0f15` panel the Ready and found-confirm sheets both use.
struct DetailRow: Identifiable {
    let key: String
    let value: String
    /// Gold rather than bone — the prototype accents exactly the odds row.
    let accent: Bool

    var id: String { key }

    init(_ key: String, _ value: String, accent: Bool = false) {
        self.key = key
        self.value = value
        self.accent = accent
    }
}

/// `background:#0f0f15;border:1px solid #1a1a22;border-radius:16px` with hairline-separated rows.
struct DetailPanel: View {
    let rows: [DetailRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack {
                    Text(row.key)
                        .font(Typography.rowLabel)
                        .foregroundStyle(Palette.textMuted)
                    Spacer(minLength: 10)
                    Text(row.value)
                        .font(Typography.rowValue)
                        .foregroundStyle(row.accent ? Palette.hunt : Palette.textPrimary)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .accessibilityElement(children: .combine)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 1)
                }
            }
        }
        .background(Palette.detailPanel, in: .rect(cornerRadius: Radii.listCard))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.listCard)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
    }
}

/// `height:52px;border-radius:16px` — the full-width gold action at the bottom of a sheet.
/// ``GoldButtonStyle`` is the same fill at the inline size the empty state uses.
struct WideGoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.primaryButton)
            .foregroundStyle(Palette.onAccent)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Palette.hunt, in: .rect(cornerRadius: Radii.listCard))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
