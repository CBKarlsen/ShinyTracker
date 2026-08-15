import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// The Dex mode. Structure, spacing and colour come from the `isDex` screen of
/// `docs/design/hunt-prototype.dc.html`.
///
/// One grid of every species, grouped by generation in national-dex order, read three ways:
/// **Browse** opens a species; **Living** and **Shiny** turn the same tiles into a checklist.
struct DexScreen: View {
    @State var model: DexModel
    @State private var openSpecies: Pokemon?
    @State private var pickingGame = false

    /// `grid-template-columns:repeat(3,1fr);gap:8px`
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    /// The title, the game picker and the search button are the navigation bar's job now, which
    /// buys the large-title-collapses-on-scroll behaviour for free — the five stacked rows this
    /// screen used to pin above the grid cost ~150pt that the 1,025 tiles wanted.
    ///
    /// Only the Browse/Living/Shiny control stays pinned, via `safeAreaInset`: it filters what you
    /// are looking at, so it has to stay reachable while you scroll. The progress bar and the hint
    /// moved *into* the scroll view — they describe the current view rather than controlling it.
    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle("Dex")
                // Where the header's count went. Empty until the dex loads, so the bar does not
                // advertise "0 of 0" during the fetch.
                .navigationSubtitle(model.state == .ready ? model.progressLabel : "")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { gameToolbarButton }
                    ToolbarItem(placement: .topBarTrailing) { searchToolbarButton }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    segmentedControl
                        .padding(.horizontal, Metrics.screenPadding)
                        .padding(.bottom, 8)
                        // Hides the tiles passing under it, for the same reason the grid's pinned
                        // section headers do — the margin around the control is transparent without
                        // a background. A material rather than the flat fill it used to be, so the
                        // collapsing large title dissolves under this strip instead of being clipped
                        // by it. See the longer note on `HuntScreen`'s.
                        .background(.bar)
                }
        }
        .task {
            await model.appear()
            #if DEBUG
            // ponytail: `simctl` cannot tap, so the preview harness names the species whose
            // sheet to open. Debug-only, and inert unless -dexSpecies is passed.
            if let id = DexPreview.openSpeciesID {
                openSpecies = model.sections.flatMap(\.species).first { $0.id == id }
            }
            #endif
        }
        .sheet(item: $openSpecies) { species in
            SpeciesSheet(
                species: species,
                gameID: model.selectedGameID,
                gameTitle: model.selectedGame?.title,
                shiny: model.view == .shiny,
                client: model.client
            )
        }
        .sheet(isPresented: $pickingGame) {
            GamePickerSheet(games: model.games, selected: $model.selectedGameID)
        }
    }

    // MARK: Toolbar

    /// The game picker, compacted from the full-width row it used to be. The bar gives it a
    /// tappable background, so the hand-drawn surface + hairline the row carried is redundant.
    private var gameToolbarButton: some View {
        Button { pickingGame = true } label: {
            HStack(spacing: 4) {
                Text(model.selectedGame?.title ?? "All games")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .accessibilityLabel("Game: \(model.selectedGame?.title ?? "all your games")")
    }

    /// Still inert — the Reference sheet the prototype promised "from every header" is not built.
    /// It keeps its place in the bar so the affordance does not move when it is.
    private var searchToolbarButton: some View {
        Button {} label: {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("Search the reference")
    }

    // MARK: Segmented control

    /// Same shell as Hunt's. The selected pill takes the colour of what it counts: bone white
    /// for Browse and Living, gold for Shiny — `pill(on, accent)` in the prototype.
    private var segmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(DexModel.DexView.allCases) { candidate in
                let on = candidate == model.view
                Button {
                    model.view = candidate
                    model.clearMessages()
                } label: {
                    Text(candidate.rawValue)
                        .font(on ? Typography.segmentOn : Typography.segmentOff)
                        .foregroundStyle((on ? Palette.onAccent : Palette.textMuted).color)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            on ? accent(for: candidate) : .clear,
                            in: .rect(cornerRadius: Radii.segmentItem)
                        )
                        .contentShape(.rect)
                }
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Palette.surface.color, in: .rect(cornerRadius: Radii.segment))
        .overlay(
            RoundedRectangle(cornerRadius: Radii.segment)
                .strokeBorder(Palette.hairline.color, lineWidth: 1)
        )
    }

    private func accent(for view: DexModel.DexView) -> Color {
        (view == .shiny ? Palette.hunt : Palette.dex).color
    }

    // MARK: Progress

    /// `height:6px` track with the percentage beside it, tabular so it does not jitter.
    private var progressRow: some View {
        HStack(spacing: 12) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.hairline.color)
                    Capsule()
                        .fill(accent(for: model.view))
                        .frame(width: geometry.size.width * model.progress)
                }
            }
            .frame(height: Metrics.barHeight)

            Text(model.progress.formatted(.percent.precision(.fractionLength(0))))
                .font(Typography.statStrong)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.registeredCount) of \(model.countedTotal) registered")
    }

    private var hint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.viewHint)
                .font(Typography.meta)
                .foregroundStyle(Palette.textMuted.color)
            if let note = model.scopeNote {
                Text(note)
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textFaint.color)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Grid

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .tint(Palette.textMuted.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let reason):
            VStack(spacing: 12) {
                Text("Couldn't load the dex")
                    .font(Typography.emptyTitle)
                    .foregroundStyle(Palette.textPrimary.color)
                Text(reason)
                    .font(Typography.emptyBody)
                    .foregroundStyle(Palette.textMuted.color)
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await model.load() } }
                    .buttonStyle(GoldButtonStyle())
                    .padding(.top, 10)
            }
            // The root is a NavigationStack now, so it carries no horizontal inset of its own.
            .padding(.horizontal, Metrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready:
            grid
        }
    }

    /// 1,025 tiles.
    ///
    /// `LazyVStack` + one `LazyVGrid` per generation: SwiftUI builds a section's rows only as
    /// they approach the viewport, so ~30 tiles exist at a time rather than 1,025. Each tile's
    /// ``DexSprite`` fetches in its own `.task`, so nothing is fetched or decoded until its row is
    /// built, and ``SpriteCache`` hands back the already-decoded image on the way back up.
    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Inside the scroll view, not pinned above it: these describe the current view
                // rather than controlling it, so they are worth screen space only until you
                // start scrolling.
                if model.view != .browse {
                    progressRow.padding(.bottom, Metrics.screenGap)
                }
                hint.padding(.bottom, Metrics.screenGap)

                if let message = model.syncError ?? model.refusal {
                    Text(message)
                        .font(Typography.hint)
                        // Same reason as HuntScreen's: a Dex screen must not print in Nuzlocke's
                        // blue. The two tiers survive the change though — a `refusal` explains
                        // something ("shiny locked in every game") and belongs with the hint it
                        // sits beside, while a `syncError` is a failure and has to outrank it.
                        .foregroundStyle(
                            model.syncError == nil
                                ? Palette.textMuted.color : Palette.textSecondary.color
                        )
                        .padding(.vertical, 6)
                        .padding(.horizontal, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(model.sections) { section in
                    Section {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(section.species) { species in
                                tile(species)
                            }
                        }
                        .padding(.bottom, 10)
                    } header: {
                        Text(section.label)
                            .font(Typography.blockLabel)
                            .tracking(Typography.blockLabelTracking)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.textMuted.color)
                            .padding(.top, 6)
                            .padding(.bottom, 9)
                            .padding(.horizontal, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Palette.screen.color)
                    }
                }
            }
            // Horizontal padding lives here rather than on the screen's root: the root is a
            // NavigationStack now, and insetting that would inset the navigation bar too.
            .padding(.horizontal, Metrics.screenPadding)
            // No bottom padding for the tab bar: `TabView` insets its own content, and adding
            // the prototype's `padding-bottom:104px` on top of that leaves a dead gap under
            // the last row. The accessory, when a hunt is live, is inset by the same mechanism.
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
    }

    private func tile(_ species: Pokemon) -> some View {
        let state = model.tileState(for: species)
        return Button {
            if model.view == .browse {
                guard !state.unavailable else {
                    model.tap(species)                 // says why, opens nothing
                    return
                }
                openSpecies = species
            } else {
                model.tap(species)
            }
        } label: {
            VStack(spacing: 6) {
                DexSprite(
                    pokemonID: species.id,
                    shiny: model.view == .shiny,
                    size: 52,
                    // `filter:grayscale(1) brightness(.6)` on anything unavailable, and on
                    // anything not yet ticked while a checklist is up.
                    dimmed: state.unavailable || (model.view != .browse && !state.registered),
                    served: model.view == .shiny
                        ? species.shinySpriteURL : species.spriteURL
                )
                Text(species.name.capitalized)
                    .font(Typography.tileName)
                    .foregroundStyle(Palette.textPrimary.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(state.sub)
                    .font(Typography.tileSub)
                    .foregroundStyle(state.subColour)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 14)
            .padding(.bottom, 12)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .background(Palette.surface.color, in: .rect(cornerRadius: Radii.tile))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.tile)
                    .strokeBorder(ring(state), lineWidth: state.registered && !state.unavailable && model.view != .browse ? 2 : 1)
            )
            // The gold dot: "a shiny counts for the living dex too, marked with a gold dot".
            .overlay(alignment: .topTrailing) {
                if state.goldDot {
                    Circle()
                        .fill(Palette.hunt.color)
                        .frame(width: 7, height: 7)
                        .padding(8)
                }
            }
            .opacity(state.unavailable ? 0.45 : 1)
            .contentShape(.rect)
        }
        .accessibilityLabel(accessibilityLabel(species, state))
        .accessibilityAddTraits(state.registered ? [.isSelected] : [])
    }

    /// `ring = un ? '#1a1a22' : on ? (shiny ? accent66 : '#f4f2ec33') : '#1a1a22'`
    private func ring(_ state: DexTileState) -> Color {
        guard state.registered, !state.unavailable, model.view != .browse else {
            return Palette.hairline.color
        }
        return model.view == .shiny ? Palette.hunt.alpha(0x66) : Palette.dex.alpha(0x33)
    }

    private func accessibilityLabel(_ species: Pokemon, _ state: DexTileState) -> String {
        var parts = [species.name.capitalized, state.sub]
        if state.goldDot { parts.append("owned shiny") }
        if state.locked && !state.unavailable { parts.append("registered automatically") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Sprite

/// A dex sprite: the radial-gradient plate with the sprite on top, fetched through
/// ``SpriteCache``. Still separate from Hunt's ``SpriteTile``, which is shiny-only and still on
/// `AsyncImage` — the two have converged on the same plate and want merging, but that is a
/// follow-up, not something this type's existence justifies any more.
///
/// Both variants now come from the API when it has them — `sprite_url` and `shiny_sprite_url`
/// are separate columns — and ``SpriteSource`` falls back to the id-derived URL for a server
/// that has not run migration 016's backfill.
struct DexSprite: View {
    let pokemonID: Int
    var shiny = false
    var size: CGFloat = 52
    var dimmed = false
    /// The matching URL from the API, when the caller has the species loaded.
    var served: String?

    private var url: URL? {
        SpriteSource.url(id: pokemonID, shiny: shiny, served: served)
    }

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            // The sprite plate, always. `Color.clear` left a hole while loading, which is what
            // makes a list look like it is still working after the text has arrived.
            RoundedRectangle(cornerRadius: Radii.sprite(size))
                .fill(Palette.spriteTile.color)
            if let image {
                Image(uiImage: image)
                    .resizable().interpolation(.none).scaledToFit()   // image-rendering:pixelated
            }
        }
        .frame(width: size, height: size)
        .grayscale(dimmed ? 1 : 0)
        .opacity(dimmed ? 0.6 : 1)
        .task(id: url) {
            // `@State` survives a url change on the same view identity (the Shiny segment keeps
            // every tile's identity), so without this the tile shows its *old* sprite until the
            // new one lands — a non-shiny under a shiny checklist. The plate is the honest
            // placeholder. No-op on first appearance and on scroll-back: already nil.
            image = nil
            guard let url else { return }
            let fetched = await SpriteCache.shared.image(for: url)
            // SpriteCache's fetch is an unstructured Task of its own, so cancelling this
            // .task(id:) doesn't stop it — a cell recycled onto a new url (same View identity,
            // e.g. a Browse/Shiny toggle) must not have its now-current image overwritten by a
            // late-arriving fetch for the url it used to show.
            guard !Task.isCancelled else { return }
            image = fetched
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Game picker

/// "Dex for which game?" — the sheet behind the selector.
struct GamePickerSheet: View {
    let games: [Game]
    @Binding var selected: Int?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Dex for which game?")
                    .font(Typography.sheetTitle)
                    .tracking(Typography.sheetTitleTracking)
                    .foregroundStyle(Palette.textPrimary.color)
                    .padding(.bottom, 4)

                row(
                    title: "All your games",
                    meta: "Locations and movesets from every game",
                    isOn: selected == nil
                ) { selected = nil }

                ForEach(games) { game in
                    row(title: game.title, meta: "Gen \(game.generation)", isOn: selected == game.id) {
                        selected = game.id
                    }
                }
            }
            .padding(18)
        }
        .background(Palette.sheet.color)
        .presentationDetents([.medium, .large])
        .presentationBackground(Palette.sheet.color)
    }

    /// `background:#111118;border-radius:16px;padding:13px 15px` with a "Selected" tag.
    private func row(
        title: String, meta: String, isOn: Bool, pick: @escaping () -> Void
    ) -> some View {
        Button {
            pick()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(Typography.segmentOn)
                        .foregroundStyle(Palette.textPrimary.color)
                    Text(meta)
                        .font(Typography.tileSub)
                        .foregroundStyle(Palette.textMuted.color)
                }
                Spacer(minLength: 0)
                if isOn {
                    Text("Selected")
                        .font(Typography.statStrong)
                        .foregroundStyle(Palette.textPrimary.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Palette.dex.alpha(0x33), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Palette.surface.color, in: .rect(cornerRadius: Radii.block))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.block)
                    .strokeBorder(
                        isOn ? Palette.dex.alpha(0x33) : Palette.hairline.color,
                        lineWidth: isOn ? 2 : 1
                    )
            )
            .contentShape(.rect)
        }
    }
}
