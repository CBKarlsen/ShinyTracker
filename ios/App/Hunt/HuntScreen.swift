import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// The Hunt mode. Layout, spacing and colour come from `docs/design/hunt-prototype.dc.html`.
///
/// All three segments are built. The header's search button is still inert: Reference "is the
/// search button in every header, not a tab", and that pillar is out of scope.
struct HuntScreen: View {
    @State var model: HuntListModel
    let library: GameLibraryModel
    @State var newHunt: NewHuntModel

    @State private var segment: Segment = .active
    @State private var newHuntOpen = false
    /// A snapshot of the hunt whose ✦ was tapped; non-nil presents the confirm sheet.
    @State private var founding: HuntRow?

    /// `tabs: [{label:'Active'}, {label:'History'}, {label:'Games'}]`.
    enum Segment: String, CaseIterable, Identifiable {
        case active = "Active", history = "History", games = "Games"
        var id: Self { self }
    }

    var body: some View {
        // `gap:13px;padding:8px 18px 0`
        VStack(alignment: .leading, spacing: Metrics.screenGap) {
            header
            // Above the segmented control, not inside the Active list: a failed completion's hunt
            // has already left Active for History by the time it can fail, so a banner scoped to
            // one tab could name a hunt the user is not looking at.
            if !model.failedWrites.isEmpty {
                failedWritesBanner
            }
            segmentedControl
            content
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await model.appear() }
        // The library is what makes the + button work at all (no owned games, no methods), and
        // the Games tab reads the same model, so it loads with the screen rather than on demand.
        .task { await library.appear() }
        .sheet(isPresented: $newHuntOpen) {
            NewHuntSheet(model: newHunt) {
                newHuntOpen = false
                segment = .active
                Task { await model.refresh() }
            }
        }
        .sheet(item: $founding) { row in
            FoundSheet(row: row, model: model) { founding = nil }
        }
        #if DEBUG
        .task { await openPreviewRoute() }
        #endif
    }

    #if DEBUG
    /// Walks the screen to wherever `-huntPreviewOpen` points, so every tab and every step of the
    /// sheet can be screenshotted from `simctl` alone. Debug-only, and inert without the argument.
    private func openPreviewRoute() async {
        guard let route = HuntPreview.route else { return }

        /// The stub transport answers after a beat; poll rather than guess a sleep.
        func settle(until ready: @escaping () -> Bool) async {
            for _ in 0..<40 where !ready() {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }

        switch route {
        case .history:
            segment = .history
        case .games:
            segment = .games
        case .found:
            await settle { !model.rows.isEmpty }
            founding = model.rows.first
        case .species, .game, .method, .ready:
            newHunt.open()
            newHuntOpen = true
            guard route != .species else { return }

            await settle { !newHunt.results.isEmpty }
            guard let species = newHunt.results.first else { return }
            newHunt.pick(species: species)
            guard route != .game else { return }

            await settle { !newHunt.gameOptions.isEmpty }
            guard let game = newHunt.gameOptions.first?.game else { return }
            newHunt.pick(gameID: game.id)
            guard route != .method else { return }

            guard let method = newHunt.methodOptions.first else { return }
            newHunt.pick(method: method)
        }
    }
    #endif

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            // `gap:9px` — mode glyph then title. The prototype's glyph is a shiny-charm PNG we
            // do not have as an asset; `sparkles` is the nearest system symbol and is used for
            // the ✦ found button too, keeping one glyph for "shiny" throughout.
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.hunt.color)
                Text("Hunt")
                    .font(Typography.screenTitle)
                    .tracking(Typography.screenTitleTracking)
                    .foregroundStyle(Palette.textPrimary.color)
            }

            Spacer(minLength: 0)

            Text(huntSummary)
                .font(Typography.summary)
                .foregroundStyle(Palette.textMuted.color)

            // Reference search. Present per the design ("reachable from every header"), inert:
            // the Reference sheet is out of scope.
            headerButton(symbol: "magnifyingglass", label: "Search the reference") {}
                .foregroundStyle(Palette.textSecondary.color)
                .background(Palette.surface.color, in: .rect(cornerRadius: Radii.headerButton))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.headerButton)
                        .strokeBorder(Palette.hairline.color, lineWidth: 1)
                )

            // The gold +.
            headerButton(symbol: "plus", label: "Start a new hunt") {
                newHunt.open()
                newHuntOpen = true
            }
            .fontWeight(.bold)
            .foregroundStyle(Palette.onAccent.color)
            .background(Palette.hunt.color, in: .rect(cornerRadius: Radii.headerButton))
        }
    }

    /// `${n} ${n === 1 ? 'hunt' : 'hunts'}`.
    private var huntSummary: String {
        let count = model.rows.count
        return "\(count) \(count == 1 ? "hunt" : "hunts")"
    }

    private func headerButton(
        symbol: String, label: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .frame(width: Metrics.headerButton, height: Metrics.headerButton)
                .contentShape(.rect)
        }
        .accessibilityLabel(label)
    }

    // MARK: Segmented control

    /// `display:flex;gap:2px;background:#111118;border:1px solid #1a1a22;border-radius:12px;padding:3px`
    private var segmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(Segment.allCases) { tab in
                let on = tab == segment
                Button { segment = tab } label: {
                    Text(tab.rawValue)
                        .font(on ? Typography.segmentOn : Typography.segmentOff)
                        .foregroundStyle((on ? Palette.onAccent : Palette.textMuted).color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            on ? Palette.textPrimary.color : .clear,
                            in: .rect(cornerRadius: Radii.segmentItem)
                        )
                        .contentShape(.rect)
                }
            }
        }
        .padding(3)
        .background(Palette.surface.color, in: .rect(cornerRadius: Radii.segment))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.segment)
                .strokeBorder(Palette.hairline.color, lineWidth: 1)
        )
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch segment {
        case .active: activeList
        case .history: historyList
        case .games: GamesTab(library: library)
        }
    }

    @ViewBuilder
    private var activeList: some View {
        switch model.state {
        case .loading:
            centered {
                ProgressView().tint(Palette.textMuted.color)
            }

        case .failed(let reason):
            centered {
                StateBlock(
                    symbol: "exclamationmark.triangle",
                    title: "Couldn't load your hunts",
                    body: reason
                ) {
                    Button("Try again") { Task { await model.load() } }
                        .buttonStyle(GoldButtonStyle())
                        .padding(.top, 22)
                }
            }

        case .ready:
            // `overflow-y:auto;gap:10px;padding-bottom:104px`
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.cardGap) {
                    if let syncError = model.syncError {
                        Text(syncError)
                            .font(Typography.hint)
                            .foregroundStyle(Palette.nuzlocke.color)
                            .padding(.horizontal, 2)
                    }

                    if model.rows.isEmpty {
                        emptyState
                    } else {
                        // `countHint` — the prototype promises Space/volume-up counting, ⌘Z undo
                        // and a wake lock. None of those exist here (volume counting is ruled
                        // out by DECISIONS.md D3), so the line says only what is true.
                        Text("Tap +1 to count. ×N changes how many each tap adds.")
                            .font(Typography.hint)
                            .foregroundStyle(Palette.textMuted.color)
                            .padding(.horizontal, 2)
                            .padding(.top, 2)

                        ForEach(model.rows) { row in
                            HuntCard(row: row, model: model, isLive: row.id == model.liveHuntID) {
                                founding = row
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.refresh() }
        }
    }

    /// Completed hunts. Same fetch as the Active list, filtered the other way.
    @ViewBuilder
    private var historyList: some View {
        switch model.state {
        case .loading:
            centered { ProgressView().tint(Palette.textMuted.color) }

        case .failed(let reason):
            centered {
                StateBlock(
                    symbol: "exclamationmark.triangle",
                    title: "Couldn't load your hunts",
                    body: reason
                )
            }

        case .ready:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.history.isEmpty {
                        StateBlock(
                            symbol: "sparkles",
                            title: "No shinies yet",
                            body: "Hunts you mark found land here, with the count they took."
                        )
                        .padding(.top, 6)
                    } else {
                        ForEach(model.history) { row in
                            HistoryRow(row: row)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await model.refresh() }
        }
    }

    /// Writes that will never land, named one per line. Unlike `syncError` above it, this is not
    /// noise a retry will clear on its own — the encounters are really gone — so it says so in
    /// the danger colour and waits for the user to dismiss it rather than fading on its own.
    private var failedWritesBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.failedWrites, id: \.self) { message in
                Text(message)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.danger.color)
            }
            Button("Dismiss") { model.dismissFailedWrites() }
                .font(Typography.hint)
                .foregroundStyle(Palette.textMuted.color)
        }
        .padding(.horizontal, 2)
    }

    /// The owner has zero hunts, so this is the first thing they will see.
    private var emptyState: some View {
        StateBlock(
            symbol: "sparkles",
            title: "No active hunts",
            body: "Every shiny you've caught is in History. Start the next one whenever you're ready."
        )
        .padding(.top, 6)
    }

    private func centered(@ViewBuilder content: () -> some View) -> some View {
        ScrollView {
            content().padding(.top, 6)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - History

/// `padding:11px 14px;border-radius:15px` — sprite, name, meta, then the final count over the
/// time it took.
struct HistoryRow: View {
    let row: HuntRow

    var body: some View {
        HStack(spacing: 13) {
            SpriteTile(pokemonID: row.detail.pokemonID, size: 44)

            VStack(alignment: .leading, spacing: 7) {
                Text(row.name)
                    .font(Typography.listTitle)
                    .foregroundStyle(Palette.textPrimary.color)
                Text(meta)
                    .font(Typography.stat)
                    .foregroundStyle(Palette.textMuted.color)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 6) {
                Text(row.count.formatted(.number))
                    .font(Typography.rowValue)
                    .foregroundStyle(Palette.hunt.color)
                // `font:400 12px/1` — the quietest line on the row.
                Text(formatElapsed(row.detail.totalTimeSeconds))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textFaint.color)
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(Palette.surface.color, in: .rect(cornerRadius: Radii.row))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.row)
                .strokeBorder(Palette.hairline.color, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            """
            \(row.name), \(meta), \(row.count.formatted(.number)) encounters over \
            \(formatElapsed(row.detail.totalTimeSeconds))
            """
        )
    }

    /// `${r.nick} · ${r.game} · ${r.method} · found ${r.date}`, the nickname first as the
    /// prototype has it. Most hunts have none — it is optional at every layer — so it is dropped
    /// from the line rather than leaving a stray separator.
    private var meta: String {
        let found = row.detail.updatedAt.formatted(
            .relative(presentation: .named, unitsStyle: .wide))
        let nickname = row.detail.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([nickname?.isEmpty == false ? nickname : nil,
                 row.detail.gameTitle,
                 row.detail.customMethodName ?? row.detail.methodName]
            .compactMap { $0 } + ["found \(found)"]).joined(separator: " · ")
    }
}

// MARK: - Shared blocks

/// `padding:52px 24px` panel with a 64pt icon tile — the prototype's empty state, reused for the
/// error and empty states of all three tabs because it is the same shape in each.
struct StateBlock<Accessory: View>: View {
    let symbol: String
    let title: String
    /// Not named `body`: that is the `View` requirement, and a stored property would shadow it.
    let message: String
    /// The icon's tint. Defaults to Hunt's gold, because every caller but Nuzlocke is a Hunt
    /// screen — and a run screen must never show gold ("each mode owns a colour").
    let tint: Swatch
    @ViewBuilder var accessory: () -> Accessory

    init(
        symbol: String,
        title: String,
        body: String,
        tint: Swatch = Palette.hunt,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.symbol = symbol
        self.title = title
        self.message = body
        self.tint = tint
        self.accessory = accessory
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(tint.color.opacity(0.55))
                .frame(width: 64, height: 64)
                .background(Palette.surface.color, in: .rect(cornerRadius: Radii.iconTile))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.iconTile)
                        .strokeBorder(Palette.hairline.color, lineWidth: 1)
                )
                .padding(.bottom, 20)

            Text(title)
                .font(Typography.emptyTitle)
                .tracking(Typography.cardTitleTracking)
                .foregroundStyle(Palette.textPrimary.color)
                .padding(.bottom, 10)

            Text(message)
                .font(Typography.emptyBody)
                .lineSpacing(4)
                .foregroundStyle(Palette.textMuted.color)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)

            accessory()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 52)
        .padding(.horizontal, 24)
        .background(Palette.surfaceSunken.color, in: .rect(cornerRadius: Radii.panel))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.panel)
                .strokeBorder(Palette.hairline.color, lineWidth: 1)
        )
    }
}

/// `height:52px;border-radius:16px;background:#f5c661;color:#060608;font:600 18px/1`
struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.primaryButton)
            .foregroundStyle(Palette.onAccent.color)
            .padding(.horizontal, 22)
            .frame(height: 46)
            .background(Palette.hunt.color, in: .rect(cornerRadius: Radii.headerButton))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
