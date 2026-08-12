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

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.screenGap) {
            header
            gameSelector
            segmentedControl
            if model.view != .browse { progressRow }
            hint
            content
        }
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task {
            await model.load()
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

    // MARK: Header

    /// The mode glyph, the title, the count, and the (inert) Reference search — "reachable from
    /// every header", but the Reference sheet is not built.
    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "square.split.1x2")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.dex.color)
                Text("Dex")
                    .font(Typography.screenTitle)
                    .tracking(Typography.screenTitleTracking)
                    .foregroundStyle(Palette.textPrimary.color)
            }

            Spacer(minLength: 0)

            if model.state == .ready {
                Text(model.progressLabel)
                    .font(Typography.summary)
                    .foregroundStyle(Palette.textMuted.color)
            }

            Button {} label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .frame(width: Metrics.headerButton, height: Metrics.headerButton)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Search the reference")
            .foregroundStyle(Palette.textSecondary.color)
            .background(Palette.surface.color, in: .rect(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(Palette.hairline.color, lineWidth: 1)
            )
        }
    }

    // MARK: Game selector

    /// `height:46px;background:#111118;border:1px solid #1a1a22;border-radius:14px;padding:0 14px`
    private var gameSelector: some View {
        Button { pickingGame = true } label: {
            HStack(spacing: 10) {
                Text("Game")
                    .font(Typography.emptyBody)
                    .foregroundStyle(Palette.textMuted.color)
                Spacer(minLength: 0)
                Text(model.selectedGame?.title ?? "All your games")
                    .font(Typography.segmentOn)
                    .foregroundStyle(Palette.textPrimary.color)
                Text("›")
                    .font(Typography.segmentOn)
                    .foregroundStyle(Palette.textFaint.color)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(Palette.surface.color, in: .rect(cornerRadius: Radii.headerButton))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.headerButton)
                    .strokeBorder(Palette.hairline.color, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .accessibilityLabel("Game: \(model.selectedGame?.title ?? "all your games")")
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready:
            grid
        }
    }

    /// 1,025 tiles.
    ///
    /// `LazyVStack` + one `LazyVGrid` per generation: SwiftUI builds a section's rows only as
    /// they approach the viewport, so ~30 tiles exist at a time rather than 1,025. Sprites are
    /// `AsyncImage`s inside those tiles, so nothing is fetched or decoded until its row is
    /// built, and `URLSession`'s cache serves it on the way back up.
    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                if let message = model.syncError ?? model.refusal {
                    Text(message)
                        .font(Typography.hint)
                        .foregroundStyle(
                            model.syncError == nil
                                ? Palette.textSecondary.color : Palette.nuzlocke.color
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
            // No bottom padding for the tab bar: `AppShell` insets this scroll view by the
            // bar's measured height with `safeAreaInset`, and adding the prototype's
            // `padding-bottom:104px` on top of that leaves a dead gap under the last row.
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.load() }
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
                    dimmed: state.unavailable || (model.view != .browse && !state.registered)
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

/// A dex sprite. Separate from Hunt's ``SpriteTile`` because that one is shiny-only and has the
/// card's radial-gradient plate behind it; a dex tile draws the sprite bare on the card.
///
/// ponytail: same `SPRITE_BASE` the prototype and ``SpriteTile`` use. `Pokemon.sprite_url` from
/// the API is the normal sprite only — there is no shiny column — so both variants are built
/// from the id rather than mixing two sources.
struct DexSprite: View {
    let pokemonID: Int
    var shiny = false
    var size: CGFloat = 52
    var dimmed = false

    private var url: URL? {
        URL(
            string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/"
                + (shiny ? "shiny/" : "") + "\(pokemonID).png")
    }

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().interpolation(.none).scaledToFit()   // image-rendering:pixelated
        } placeholder: {
            Color.clear
        }
        .frame(width: size, height: size)
        .grayscale(dimmed ? 1 : 0)
        .opacity(dimmed ? 0.6 : 1)
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
