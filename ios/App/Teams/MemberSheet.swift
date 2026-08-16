import ShinyTrackerAPI
import ShinyTrackerKit
import ShinyTrackerUI
import SwiftUI

/// One slot of a team: pick the species, then build it.
///
/// Every value this sheet can produce is one the server accepts. That is deliberate at three
/// specific points, because each has already been a real bug:
/// - **Nature** goes over the wire as `Nature.rawValue` — lowercase. `displayName` is for reading.
/// - **Level** is not editable. Champions auto-levels every Pokémon to 50 in battle, so a stepper
///   would edit a number the game overrides; the row states it and `save()` sends 50.
/// - **Stat points** cannot be pushed past 32 in one stat or 66 in total — the slider is bound
///   through ``StatPoints/capped(_:for:)``. There are exactly three guards on that rule and they
///   all agree on 32/66: `statPointsValid` in `backend/internal/api/teams.go`,
///   `ShowdownBridge.cappedTotal` on the paste-import path, and this one. This is the only one
///   that acts before the user commits, so it exists so the user is never allowed to build a set
///   the handler would reject.
struct MemberSheet: View {
    let client: APIClient
    /// The whole species list, fetched once by the editor — the search below is a local filter.
    let species: [Pokemon]
    let items: [Item]
    let slot: Int
    let existing: TeamMember?
    let onSave: (TeamMember) -> Void
    let onRemove: () -> Void

    /// The id, not the `Pokemon`: `TeamMember` carries only an id, and this sheet must open
    /// correctly even if the editor's species fetch has not landed yet.
    @State private var pokemonID: Int?
    /// What ``pokemonID`` was before "Change" emptied it. See ``choose(_:)``.
    @State private var previousID: Int?
    @State private var query = ""
    @State private var detail: PokemonDetail?
    @State private var failure: String?

    @State private var nature: Nature
    @State private var ability: String
    /// Also where a Mega Stone is chosen — in Champions the gimmick is a held item, so there is
    /// no separate control for it.
    @State private var itemSlug: String?
    @State private var statPoints: StatPoints
    /// Exactly four, so "at most four moves" cannot be violated in the first place.
    @State private var moveSlots: [String?]

    @State private var picking: PickerTarget?
    @Environment(\.dismiss) private var dismiss

    enum PickerTarget: Hashable, Identifiable {
        case item
        case move(Int)

        var id: Self { self }
    }

    init(
        client: APIClient,
        species: [Pokemon],
        items: [Item],
        slot: Int,
        existing: TeamMember?,
        onSave: @escaping (TeamMember) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.client = client
        self.species = species
        self.items = items
        self.slot = slot
        self.existing = existing
        self.onSave = onSave
        self.onRemove = onRemove

        _pokemonID = State(initialValue: existing?.pokemonID)
        _nature = State(initialValue: existing.flatMap { Nature(rawValue: $0.nature) } ?? .hardy)
        _ability = State(initialValue: existing?.abilitySlug ?? "")
        _itemSlug = State(initialValue: existing?.itemSlug)
        _statPoints = State(initialValue: Self.points(existing?.statPoints))
        let known = existing?.moves ?? []
        _moveSlots = State(initialValue: (0..<4).map { $0 < known.count ? known[$0] : nil })
    }

    var body: some View {
        NavigationStack {
            Group {
                if pokemonID == nil {
                    speciesStep
                } else {
                    form
                }
            }
            .background(Palette.sheet)
            .navigationTitle(pokemonID == nil ? "Slot \(slot)" : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .disabled(pokemonID == nil)
                }
            }
            .navigationDestination(item: $picking) { target in
                picker(for: target)
            }
        }
        .tint(Palette.team)
        .presentationDetents([.large])
        .presentationBackground(Palette.sheet)
        .task(id: pokemonID) { await loadDetail() }
    }

    // MARK: Species

    private var name: String {
        (detail?.name ?? species.first { $0.id == pokemonID }?.name)?.capitalized
            ?? pokemonID.map { "#\($0)" } ?? "Slot \(slot)"
    }

    private var types: [PokemonType] {
        (detail?.types ?? species.first { $0.id == pokemonID }?.types ?? [])
            .compactMap(PokemonType.init(slug:))
    }

    private var results: [Pokemon] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matches = needle.isEmpty ? species : species.filter { $0.name.contains(needle) }
        return Array(matches.prefix(60))
    }

    private var speciesStep: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if species.isEmpty {
                    Text("Couldn't load the species list. Close this and try again.")
                        .font(Typography.emptyBody)
                        .foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                }
                ForEach(results) { candidate in
                    Button { choose(candidate.id) } label: {
                        HStack(spacing: 13) {
                            SpriteTile(pokemonID: candidate.id, size: 44, shiny: false)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(candidate.name.capitalized)
                                    .font(Typography.listTitle)
                                    .foregroundStyle(Palette.textPrimary)
                                Text((candidate.types ?? []).map(\.capitalized).joined(separator: " · "))
                                    .font(Typography.stat)
                                    .foregroundStyle(Palette.textMuted)
                            }
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 13)
                        .frame(minHeight: Metrics.controlNarrow)
                        .background(Palette.surface, in: .rect(cornerRadius: Radii.row))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radii.row)
                                .strokeBorder(Palette.hairline, lineWidth: 1)
                        )
                        .contentShape(.rect)
                    }
                    .accessibilityLabel("Put \(candidate.name.capitalized) in slot \(slot)")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .searchable(text: $query, prompt: "Search Pokémon")
    }

    /// A different species has a different learnset and different abilities, so both are dropped
    /// rather than carried over into a set they may not be legal in.
    ///
    /// "the same species" is compared against ``previousID`` as well, because "Change" clears
    /// `pokemonID` to get back to the search — without it, tapping Change, changing your mind and
    /// tapping the same Pokémon would wipe the ability and all four moves.
    private func choose(_ id: Int) {
        let before = pokemonID ?? previousID
        previousID = nil
        pokemonID = id
        guard id != before else { return }
        ability = ""
        moveSlots = [nil, nil, nil, nil]
        detail = nil
    }

    private func loadDetail() async {
        // Already loaded — the nil-and-back-again of a cancelled "Change" must not refetch.
        guard let pokemonID, detail?.id != pokemonID else { return }
        failure = nil
        do {
            // `game_id` is what makes `moves` the Scarlet/Violet learnset rather than null.
            let loaded = try await client.pokemonDetail(id: pokemonID, gameID: scarletVioletGameID)
            detail = loaded
            if ability.isEmpty { ability = loaded.abilities?.first?.slug ?? "" }
        } catch {
            failure = userFacingMessage(for: error)
        }
    }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.cardGap) {
                header
                if let failure {
                    Text(failure)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                build
                moves
                statPointBlock

                if existing != nil {
                    Button("Clear this slot", role: .destructive) {
                        onRemove()
                        dismiss()
                    }
                    .font(Typography.summary)
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, minHeight: Metrics.controlNarrow)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(spacing: 13) {
            SpriteTile(pokemonID: pokemonID ?? 0, size: Metrics.cardSprite, shiny: false)
            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(Typography.sheetHeadline)
                    .tracking(Typography.sheetHeadlineTracking)
                    .foregroundStyle(Palette.textPrimary)
                HStack(spacing: 5) {
                    ForEach(types, id: \.self) { type in
                        typeChip(type.displayName, type.color)
                    }
                }
            }
            Spacer(minLength: 0)
            Button("Change") {
                previousID = pokemonID
                pokemonID = nil
            }
                .font(Typography.summary)
                .foregroundStyle(Palette.team)
                .frame(minHeight: Metrics.controlNarrow)
        }
    }

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

    /// Nature, ability, item and level. Each `Menu` wraps a `Picker`, which is what puts the
    /// checkmark beside the current choice — selection is never signalled by colour alone.
    private var build: some View {
        TeamBlock("Build") {
            VStack(spacing: 0) {
                Menu {
                    Picker("Nature", selection: $nature) {
                        ForEach(Nature.allCases, id: \.self) { candidate in
                            Text(natureLabel(candidate)).tag(candidate)
                        }
                    }
                } label: {
                    fieldRow("Nature", natureLabel(nature))
                }
                .accessibilityLabel("Nature, \(nature.displayName)")

                separator

                Menu {
                    Picker("Ability", selection: $ability) {
                        ForEach(detail?.abilities ?? []) { option in
                            Text(option.isHidden ? "\(option.name) (hidden)" : option.name)
                                .tag(option.slug)
                        }
                    }
                } label: {
                    fieldRow("Ability", abilityLabel)
                }
                .disabled((detail?.abilities ?? []).isEmpty)
                .accessibilityLabel("Ability, \(abilityLabel)")

                separator

                // Mega Stones live here too — Mega Evolution is Champions' gimmick and the stone
                // is an ordinary held item, so this picker is the whole of it.
                Button { picking = .item } label: {
                    fieldRow("Held item", itemLabel, chevron: "chevron.right")
                }
                .accessibilityLabel("Held item, \(itemLabel)")

                separator

                // Stated, not editable: Champions auto-levels to 50 in battle, so a stepper here
                // would let the user set a number the game immediately overrides.
                HStack(spacing: 10) {
                    Text("Level")
                        .font(Typography.rowLabel)
                        .foregroundStyle(Palette.textMuted)
                    Spacer(minLength: 10)
                    Text("50 · set by the game")
                        .font(Typography.rowValue)
                        .foregroundStyle(Palette.textPrimary)
                }
                .frame(minHeight: Metrics.controlNarrow)
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// "Jolly · +Spe −SpA" — the two stats are the whole reason to pick one, and a bare list of 25
    /// adjectives makes the user look them up somewhere else.
    private func natureLabel(_ nature: Nature) -> String {
        guard let raised = nature.raised, let lowered = nature.lowered else {
            return "\(nature.displayName) · neutral"
        }
        return "\(nature.displayName) · +\(raised.showdownLabel) −\(lowered.showdownLabel)"
    }

    private var abilityLabel: String {
        (detail?.abilities ?? []).first { $0.slug == ability }?.name
            ?? (ability.isEmpty ? "—" : prettifySlug(ability))
    }

    private var itemLabel: String {
        guard let itemSlug, !itemSlug.isEmpty else { return "None" }
        return items.first { $0.slug == itemSlug }?.name ?? prettifySlug(itemSlug)
    }

    // MARK: Moves

    private var moves: some View {
        TeamBlock("Moves · Scarlet/Violet learnset") {
            VStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { index in
                    if index > 0 { separator }
                    Button { picking = .move(index) } label: {
                        fieldRow(
                            "Move \(index + 1)",
                            moveSlots[index].map(moveName) ?? "Empty",
                            chevron: "chevron.right"
                        )
                    }
                    .accessibilityLabel(
                        "Move \(index + 1), \(moveSlots[index].map(moveName) ?? "empty")")
                }
            }
        }
    }

    private func moveName(_ slug: String) -> String {
        learnset.first { $0.slug == slug }?.name ?? prettifySlug(slug)
    }

    /// The species' real moveset for this game. The same move arrives once per learn method, so it
    /// is deduplicated by slug — a picker does not care whether it came off a TM or a level-up.
    private var learnset: [PokemonMove] {
        var seen = Set<String>()
        return (detail?.moves ?? [])
            .filter { seen.insert($0.slug).inserted }
            .sorted { $0.name < $1.name }
    }

    // MARK: Stat points

    /// The remaining budget is the headline, because "how many do I have left" is the only
    /// question anyone asks while spending the pool.
    private var statPointBlock: some View {
        // `max(0, …)` because a row written before the server validated spreads can still load at
        // over 66, and "−4 of 66 left" reads as a bug rather than as an over-budget set.
        TeamBlock("Stat points · \(max(0, StatPoints.maxTotal - statPoints.total)) of \(StatPoints.maxTotal) left") {
            VStack(spacing: 10) {
                ForEach(Stat.allCases, id: \.self) { stat in
                    HStack(spacing: 10) {
                        Text(stat.showdownLabel)
                            .font(Typography.overline)
                            .foregroundStyle(Palette.textMuted)
                            .frame(width: 34, alignment: .leading)
                        // The label and the value both go on the `Slider`, and the row is
                        // deliberately *not* `.accessibilityElement(children: .combine)`:
                        // combining flattens the row into one static element and takes the
                        // slider's adjustable action with it, which would leave stat points
                        // unsettable under VoiceOver on the one screen whose whole point is
                        // setting them.
                        //
                        // The explicit value is not redundant either. Left to itself a `Slider`
                        // announces its position as a percentage of its range — "78%" — and the
                        // number of points in a stat is the only figure anyone spending 66 of
                        // them can use.
                        //
                        // `step: 1`, not the 4 the EV slider used: one stat point is the
                        // meaningful unit in Champions, and 66 of them do not divide into steps.
                        Slider(value: pointBinding(stat), in: 0...Double(StatPoints.maxPerStat), step: 1) {
                            Text("\(stat.showdownLabel) stat points")
                        }
                        .tint(Palette.team)
                        .accessibilityValue("\(statPoints[stat])")
                        Text("\(statPoints[stat])")
                            .font(Typography.statStrong)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                            .frame(width: 34, alignment: .trailing)
                            // Already spoken as the slider's value.
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    /// The UI half of the 32/66 rule. The slider is bound through ``StatPoints/capped(_:for:)``,
    /// so dragging past either cap simply stops — there is no state in which the user has built
    /// something the handler will answer with a 400.
    private func pointBinding(_ stat: Stat) -> Binding<Double> {
        Binding(
            get: { Double(statPoints[stat]) },
            set: { statPoints[stat] = statPoints.capped(Int($0.rounded()), for: stat) }
        )
    }

    // MARK: Pushed pickers

    @ViewBuilder
    private func picker(for target: PickerTarget) -> some View {
        switch target {
        case .item:
            SlugPicker(
                title: "Held item",
                rows: items.map { SlugRow(id: $0.slug, title: $0.name, subtitle: $0.description) },
                selected: itemSlug.map { [$0] } ?? [],
                noneLabel: "No item"
            ) { slug in
                itemSlug = slug
            }

        case .move(let index):
            SlugPicker(
                title: "Move \(index + 1)",
                rows: learnset.map {
                    SlugRow(
                        id: $0.slug,
                        title: $0.name,
                        subtitle: moveMeta($0),
                        tint: PokemonType(slug: $0.type)?.color
                    )
                },
                // Every move already on this set, so the picker can say which are taken —
                // including the one this slot holds.
                selected: Set(moveSlots.compactMap { $0 }),
                noneLabel: "No move"
            ) { slug in
                moveSlots[index] = slug
            }
        }
    }

    private func moveMeta(_ move: PokemonMove) -> String {
        var parts = [move.type.capitalized, move.damageClass.capitalized]
        parts.append(move.power.map { "\($0) BP" } ?? "—")
        parts.append("\(move.pp) PP")
        return parts.joined(separator: " · ")
    }

    // MARK: Save

    private func save() {
        guard let pokemonID else { return }
        onSave(
            TeamMember(
                slot: slot,
                pokemonID: pokemonID,
                nickname: existing?.nickname,
                // Lowercase — `displayName` would be a 400.
                nature: nature.rawValue,
                abilitySlug: ability,
                itemSlug: itemSlug,
                // Champions auto-levels to 50; there is nothing else this could legally be.
                level: 50,
                statPoints: dictionary(statPoints),
                moves: moveSlots.compactMap { $0 }
            )
        )
        dismiss()
    }

    /// `hp/atk/def/spa/spd/spe` — `Stat.rawValue` is already the JSONB key the column holds.
    private func dictionary(_ points: StatPoints) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: Stat.allCases.map { ($0.rawValue, points[$0]) })
    }

    /// Missing stats are 0 — an unspent pool, which is the only reading a Champions set has.
    private static func points(_ values: [String: Int]?) -> StatPoints {
        guard let values else { return .zero }
        var points = StatPoints.zero
        for stat in Stat.allCases { points[stat] = values[stat.rawValue] ?? 0 }
        return points
    }

    // MARK: Row shell

    private func fieldRow(_ label: String, _ value: String, chevron: String = "chevron.up.chevron.down")
        -> some View
    {
        HStack(spacing: 10) {
            Text(label)
                .font(Typography.rowLabel)
                .foregroundStyle(Palette.textMuted)
            Spacer(minLength: 10)
            Text(value)
                .font(Typography.rowValue)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
            Image(systemName: chevron)
                .font(Typography.tileSub)
                .foregroundStyle(Palette.textFaint)
        }
        .frame(minHeight: Metrics.controlNarrow)
        .contentShape(.rect)
    }

    private var separator: some View {
        Rectangle().fill(Palette.hairline).frame(height: 1)
    }
}

// MARK: - Slug picker

struct SlugRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    /// A type colour, for moves. Items have none.
    var tint: Color?
}

/// A searchable list of slugs — held items and moves are the same screen twice, so it is written
/// once. `.searchable` rather than a hand-built field: this one is pushed onto a navigation stack,
/// which is exactly the case the system control is for.
struct SlugPicker: View {
    let title: String
    let rows: [SlugRow]
    /// Everything already chosen, so a taken move can say so.
    let selected: Set<String>
    /// The "clear this" row at the top, when clearing is allowed.
    let noneLabel: String?
    let choose: (String?) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [SlugRow] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return rows }
        return rows.filter { $0.title.lowercased().contains(needle) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if let noneLabel, query.isEmpty {
                    row(SlugRow(id: "", title: noneLabel, subtitle: ""), slug: nil)
                }
                ForEach(filtered) { entry in
                    row(entry, slug: entry.id)
                }
                if filtered.isEmpty {
                    Text("Nothing matches \"\(query)\".")
                        .font(Typography.emptyBody)
                        .foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 26)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Palette.sheet)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search")
    }

    private func row(_ entry: SlugRow, slug: String?) -> some View {
        // The "None" row (`slug == nil`) is the selected one when nothing is chosen — otherwise
        // "No item" sits unticked while it is exactly what is in force, which is the same
        // colour-alone failure the tick exists to avoid.
        let isSelected = slug.map(selected.contains) ?? selected.isEmpty
        return Button {
            choose(slug)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title)
                        .font(Typography.listTitle)
                        .foregroundStyle(entry.tint ?? Palette.textPrimary)
                    if !entry.subtitle.isEmpty {
                        Text(entry.subtitle)
                            .font(Typography.stat)
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(2)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                // A tick, not just a tinted border: colour alone is not a state anyone can rely on.
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(Typography.statStrong)
                        .foregroundStyle(Palette.team)
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .frame(minHeight: Metrics.controlNarrow)
            .background(Palette.surface, in: .rect(cornerRadius: Radii.row))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.row)
                    .strokeBorder(isSelected ? Palette.team.alpha(0x55) : Palette.hairline, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
