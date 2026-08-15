import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// One species, opened from the grid — the prototype's `dexOpen` sheet.
///
/// Everything except the type maths comes from `GET /api/pokemon/{id}?game_id=`: stats,
/// abilities, the evolution line, that game's locations and that game's moveset. Weaknesses and
/// resists are computed here from ``TypeChart``, which is static 18×18 data on the client — no
/// request, no table.
struct SpeciesSheet: View {
    let species: Pokemon
    let gameID: Int?
    let gameTitle: String?
    /// Which sprite to show — the sheet opened from the Shiny checklist shows the shiny.
    var shiny = false
    let client: APIClient

    /// The evolution row can walk the line without closing the sheet.
    @State private var currentID: Int?
    @State private var detail: PokemonDetail?
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    private var id: Int { currentID ?? species.id }

    private var types: [PokemonType] {
        (detail?.types ?? species.types ?? []).compactMap(PokemonType.init(slug:))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let failure {
                        block("Couldn't load this species") {
                            Text(failure)
                                .font(Typography.emptyBody)
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                    // Order from `mobile-app.dc.html` 1e — stats and the matchup read first,
                    // because that is what you open a species for; the prototype's drawer
                    // leads with flavour text this app has no field for.
                    stats
                    matchups(
                        "Takes damage from", TypeChart.weaknesses(types),
                        empty: "Nothing hits it for extra damage.")
                    matchups(
                        "Resists", TypeChart.resistances(types),
                        empty: "It resists nothing.")
                    abilities
                    evolution
                    locations
                    moves
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 22)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.sheet)
        .presentationBackground(Palette.sheet)
        .presentationDetents([.large])
        .task(id: id) { await load() }
    }

    private func load() async {
        failure = nil
        do {
            detail = try await client.pokemonDetail(id: id, gameID: gameID)
        } catch {
            detail = nil
            failure = userFacingMessage(for: error)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 13) {
            DexSprite(
                pokemonID: id, shiny: shiny, size: 64,
                // The evolution cards below deliberately pass nothing: they are other species,
                // whose detail this sheet has not loaded, so they fall back on the id.
                served: shiny ? detail?.shinySpriteURL : detail?.spriteURL
            )

            VStack(alignment: .leading, spacing: 0) {
                Text("#" + String(format: "%03d", id))
                    .font(Typography.overline)
                    .foregroundStyle(Palette.textMuted)
                Text((detail?.name ?? species.name).capitalized)
                    .font(Typography.sheetTitle)
                    .tracking(Typography.sheetTitleTracking)
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.top, 6)
                HStack(spacing: 5) {
                    ForEach(types, id: \.self) { type in
                        typeChip(type.displayName, type.color)
                    }
                }
                .padding(.top, 9)
            }

            Spacer(minLength: 0)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Palette.surfaceRaised, in: .rect(cornerRadius: 11))
                    .contentShape(.rect)
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    /// `padding:5px 9px;border-radius:7px;…;box-shadow:inset 0 0 0 1px ${color}55`
    private func typeChip(_ label: String, _ tint: Color) -> some View {
        Text(label)
            .font(Typography.blockLabel)
            .tracking(0.06 * 11)
            .textCase(.uppercase)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .overlay(
                RoundedRectangle(cornerRadius: Radii.typeChip)
                    .strokeBorder(tint.alpha(0x55), lineWidth: 1)
            )
    }

    // MARK: Blocks

    /// `background:#0f0f15;border:1px solid #1a1a22;border-radius:16px;padding:14px 16px`
    private func block(
        _ title: String, @ViewBuilder content: () -> some View
    ) -> some View {
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

    @ViewBuilder
    private var abilities: some View {
        if let abilities = detail?.abilities, !abilities.isEmpty {
            block("Abilities") {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(abilities) { ability in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(ability.name)
                                .font(Typography.statStrong)
                                .foregroundStyle(Palette.textPrimary)
                            if ability.isHidden {
                                Text("hidden")
                                    .font(Typography.tileSub)
                                    .foregroundStyle(Palette.textFaint)
                            }
                        }
                    }
                }
            }
        }
    }

    /// `Where to catch — Platinum`. The handler scopes these rows to `?game_id=` when one was
    /// picked; with "All your games" they span every game, so the game is named on each row.
    @ViewBuilder
    private var locations: some View {
        if let detail {
            block(gameTitle.map { "Where to catch — \($0)" } ?? "Where to catch") {
                if detail.locations.isEmpty {
                    Text(
                        gameTitle.map { "No seeded encounters in \($0)." }
                            ?? "No seeded encounters. Evolve or trade for it."
                    )
                    .font(Typography.emptyBody)
                    .foregroundStyle(Palette.textMuted)
                } else {
                    let shown = Array(detail.locations.prefix(12))
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, location in
                            HStack(alignment: .top, spacing: 9) {
                                Circle()
                                    .fill(Palette.hunt)
                                    .frame(width: 5, height: 5)
                                    .padding(.top, 6)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(prettify(location.area))
                                        .font(Typography.emptyBody)
                                        .foregroundStyle(Palette.textPrimary)
                                    Text(meta(for: location))
                                        .font(Typography.tileSub)
                                        .foregroundStyle(Palette.textMuted)
                                }
                            }
                        }
                        if detail.locations.count > shown.count {
                            Text("+\(detail.locations.count - shown.count) more")
                                .font(Typography.tileSub)
                                .foregroundStyle(Palette.textFaint)
                        }
                    }
                }
            }
        }
    }

    private func meta(for location: PokemonLocation) -> String {
        var parts = [location.version, location.terrain].filter { !$0.isEmpty }.map(prettify)
        if location.maxLevel > 0 {
            parts.append(
                location.minLevel == location.maxLevel
                    ? "Lv \(location.maxLevel)"
                    : "Lv \(location.minLevel)–\(location.maxLevel)")
        }
        if location.chance > 0 { parts.append("\(location.chance)%") }
        parts.append(contentsOf: location.conditions.map(prettify))
        return parts.joined(separator: " · ")
    }

    private func prettify(_ slug: String) -> String {
        slug.replacingOccurrences(of: "-", with: " ").capitalized
    }

    /// Pre-evolutions, this species, then its evolutions. Tapping one walks the line in place.
    @ViewBuilder
    private var evolution: some View {
        if let detail, !(detail.evolvesFrom.isEmpty && detail.evolvesTo.isEmpty) {
            block("Evolution") {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(detail.evolvesFrom.reversed(), id: \.pokemonID) { link in
                        evolutionCard(id: link.pokemonID, name: link.name, isCurrent: false)
                    }
                    evolutionCard(id: id, name: detail.name, isCurrent: true)
                    ForEach(detail.evolvesTo, id: \.pokemonID) { link in
                        evolutionCard(id: link.pokemonID, name: link.name, isCurrent: false)
                    }
                }
            }
        }
    }

    private func evolutionCard(id: Int, name: String, isCurrent: Bool) -> some View {
        Button {
            guard !isCurrent else { return }
            currentID = id
        } label: {
            VStack(spacing: 5) {
                DexSprite(pokemonID: id, shiny: shiny, size: 44)
                Text(name.capitalized)
                    .font(Typography.tileSub)
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 8)
            .padding(.top, 10)
            .padding(.bottom, 9)
            .frame(maxWidth: .infinity)
            .background(
                isCurrent ? Palette.surfaceLive : Palette.surface,
                in: .rect(cornerRadius: 13)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(
                        isCurrent ? Palette.dex.alpha(0x33) : Palette.hairline,
                        lineWidth: isCurrent ? 2 : 1
                    )
            )
            .contentShape(.rect)
        }
        .disabled(isCurrent)
    }

    /// The level-up learnset for the selected game. TMs, tutors and egg moves are in the same
    /// payload; the sheet lists the one a player reads down a route.
    @ViewBuilder
    private var moves: some View {
        if let detail {
            block(gameTitle.map { "Level-up moves — \($0)" } ?? "Level-up moves") {
                if gameID == nil {
                    Text("Pick a game above to see its moveset.")
                        .font(Typography.emptyBody)
                        .foregroundStyle(Palette.textMuted)
                } else {
                    let levelUp = (detail.moves ?? [])
                        .filter { $0.method == "level-up" }
                        .sorted { ($0.level ?? 0, $0.name) < ($1.level ?? 0, $1.name) }
                    if levelUp.isEmpty {
                        Text("No moveset seeded for this game yet.")
                            .font(Typography.emptyBody)
                            .foregroundStyle(Palette.textMuted)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(levelUp.enumerated()), id: \.element.id) { index, move in
                                moveRow(move)
                                    .padding(.vertical, 11)
                                    .overlay(alignment: .top) {
                                        if index > 0 {
                                            Rectangle()
                                                .fill(Palette.hairline)
                                                .frame(height: 1)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
        }
    }

    private func moveRow(_ move: PokemonMove) -> some View {
        HStack(spacing: 10) {
            Text(move.level.map { "Lv \($0)" } ?? "—")
                .font(Typography.tileName)
                .monospacedDigit()
                .foregroundStyle(Palette.textMuted)
                .frame(width: 42, alignment: .leading)
            Text(move.name)
                .font(Typography.emptyBody)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
            if let type = PokemonType(slug: move.type) {
                typeChip(type.displayName, type.color)
            }
            Text(move.power.map(String.init) ?? "—")
                .font(Typography.statStrong)
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
                .frame(minWidth: 26, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var stats: some View {
        if let stats = detail?.stats {
            block("Base stats · \(stats.total) total") {
                VStack(spacing: 9) {
                    ForEach(stats.ordered, id: \.label) { stat in
                        HStack(spacing: 10) {
                            Text(stat.label)
                                .font(Typography.overline)
                                .foregroundStyle(Palette.textMuted)
                                .frame(width: 30, alignment: .leading)
                            Text("\(stat.value)")
                                .font(Typography.statStrong)
                                .monospacedDigit()
                                .foregroundStyle(Palette.textPrimary)
                                .frame(width: 30, alignment: .trailing)
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.hairline)
                                    Capsule()
                                        .fill(Palette.statBar(stat.value))
                                        // `Math.min(v, 160) / 1.6` percent — 160 is a full bar.
                                        .frame(
                                            width: geometry.size.width
                                                * min(Double(stat.value), 160) / 160)
                                }
                            }
                            .frame(height: Metrics.barHeight)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(stat.label) \(stat.value)")
                    }
                }
            }
        }
    }

    private func matchups(
        _ title: String, _ matchups: [TypeMatchup], empty: String
    ) -> some View {
        block(title) {
            if types.isEmpty {
                Text("No types on this species, so there is nothing to compute.")
                    .font(Typography.emptyBody)
                    .foregroundStyle(Palette.textMuted)
            } else if matchups.isEmpty {
                Text(empty)
                    .font(Typography.emptyBody)
                    .foregroundStyle(Palette.textMuted)
            } else {
                // `flex-wrap:wrap;gap:6px`
                FlowRow(spacing: 6) {
                    ForEach(matchups, id: \.type) { matchup in
                        typeChip(
                            "\(matchup.type.displayName) \(matchup.label)", matchup.type.color)
                    }
                }
            }
        }
    }
}

/// A wrapping row of chips. `Layout` rather than a `LazyVGrid` because the chips are all
/// different widths and a grid would column-align them into ragged gaps.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
