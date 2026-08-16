import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// One team: a name and six slots. Tapping a slot opens ``MemberSheet``.
///
/// **There is no export.** A Showdown paste encodes EVs, IVs and a Tera type, and Champions has
/// none of the three — writing one out would advertise a spread this team does not have. Import
/// stays: that direction has a defined conversion (``ShowdownBridge/member(from:slot:detail:items:)``).
///
/// The species list and the item list are fetched once, here, and handed down to every member
/// sheet this screen opens — the search in that sheet is then a local filter rather than a
/// debounced request per keystroke, and the slot rows can name the species a `TeamMember` only
/// carries the id of.
struct TeamEditorScreen: View {
    let model: TeamsModel
    let client: APIClient
    /// nil for a team that does not exist yet.
    let team: Team?

    @State private var name: String
    /// Six entries, index 0 = slot 1. A fixed six is what makes "at most six members" and the
    /// one-member-per-slot rule unrepresentable-if-broken rather than validated after the fact.
    @State private var slots: [TeamMember?]
    @State private var species: [Pokemon] = []
    @State private var items: [Item] = []
    @State private var editingSlot: SlotEdit?
    @State private var saving = false
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    /// `Int` is not `Identifiable`, and conforming it globally to satisfy one `.sheet(item:)`
    /// would be a change to every Int in the app.
    struct SlotEdit: Identifiable {
        let id: Int
    }

    init(model: TeamsModel, client: APIClient, team: Team?) {
        self.model = model
        self.client = client
        self.team = team
        _name = State(initialValue: team?.name ?? "")
        var slots = [TeamMember?](repeating: nil, count: 6)
        for member in team?.members ?? [] where (1...6).contains(member.slot) {
            slots[member.slot - 1] = member
        }
        _slots = State(initialValue: slots)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.cardGap) {
                nameField

                TeamBlock("Roster") {
                    VStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { index in
                            slotRow(index)
                        }
                    }
                }

                if let syncError = model.syncError {
                    Text(syncError)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let ruleBreach {
                    Text(ruleBreach)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await save() }
                } label: {
                    Text(team == nil ? "Create team" : "Save team")
                }
                .buttonStyle(GreenButtonStyle())
                .disabled(saving || trimmedName.isEmpty || ruleBreach != nil)
                .padding(.top, 4)

                if team != nil {
                    Button("Delete team", role: .destructive) { confirmingDelete = true }
                        .font(Typography.summary)
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, minHeight: Metrics.controlNarrow)
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(team == nil ? "New team" : "Edit team")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Both lists are static reference data. `all: true` because the picker searches
            // locally: without every species the search would silently stop at the server's 50.
            async let allSpecies = try? client.pokemon(all: true)
            async let allItems = try? client.items()
            species = await allSpecies ?? []
            items = await allItems ?? []
        }
        .sheet(item: $editingSlot) { edit in
            MemberSheet(
                client: client,
                species: species,
                items: items,
                slot: edit.id,
                existing: slots[edit.id - 1],
                onSave: { slots[edit.id - 1] = $0 },
                onRemove: { slots[edit.id - 1] = nil }
            )
        }
        .confirmationDialog(
            "Delete \(team?.name ?? "this team")?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete team", role: .destructive) {
                guard let id = team?.id else { return }
                Task {
                    await model.delete(id)
                    if model.syncError == nil { dismiss() }
                }
            }
        } message: {
            Text("The six slots go with it. This cannot be undone.")
        }
    }

    // MARK: Name

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Capped as it is typed, like ``NewHuntModel/nickname``: the server rejects anything over 100
    /// characters with a 400, and finding that out on Save would lose the edit.
    ///
    /// Counted in **unicode scalars**, because that is what the Go side counts (`utf8.RuneCount`).
    /// Swift's `Character` is a grapheme cluster and is not the same unit: 🇳🇴 is one Character and
    /// two runes, 👨‍👩‍👧‍👦 is one and seven — so a name capped at 100 Characters can still 400. Trimmed a
    /// whole Character at a time so the cap never severs a cluster into a dangling joiner.
    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TEAM NAME")
                .font(Typography.overline)
                .tracking(Typography.overlineTracking)
                .foregroundStyle(Palette.textMuted)

            TextField("Name this team", text: $name)
                .font(Typography.listTitle)
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.team)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .frame(minHeight: Metrics.controlNarrow)
                .background(Palette.field, in: .rect(cornerRadius: Radii.headerButton))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.headerButton)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
                .accessibilityLabel("Team name")
                .onChange(of: name) {
                    while name.unicodeScalars.count > Self.nameLimit { name.removeLast() }
                }
        }
    }

    static let nameLimit = 100

    // MARK: Slots

    private func slotRow(_ index: Int) -> some View {
        let member = slots[index]
        let breach = breach(member)
        return Button { editingSlot = SlotEdit(id: index + 1) } label: {
            HStack(spacing: 13) {
                if let member {
                    SpriteTile(pokemonID: member.pokemonID, size: 44, shiny: false)
                } else {
                    EmptySlotPlate(size: 44)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(member.map { speciesName($0.pokemonID) } ?? "Empty slot \(index + 1)")
                        .font(Typography.listTitle)
                        .foregroundStyle(member == nil ? Palette.textMuted : Palette.textPrimary)
                    if let member {
                        Text(summary(member))
                            .font(Typography.stat)
                            .foregroundStyle(Palette.textMuted)
                            .lineLimit(2)
                    }
                    if let breach {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                            Text(breach)
                        }
                        .font(Typography.hint)
                        .foregroundStyle(Palette.danger)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(breach)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: member == nil ? "plus" : "chevron.right")
                    .font(Typography.tileSub)
                    .foregroundStyle(Palette.textFaint)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 13)
            .frame(minHeight: Metrics.controlNarrow)
            .background(Palette.surface, in: .rect(cornerRadius: Radii.row))
            .overlay(
                RoundedRectangle(cornerRadius: Radii.row)
                    .strokeBorder(breach == nil ? Palette.hairline : Palette.danger, lineWidth: 1)
            )
            .contentShape(.rect)
        }
        .accessibilityLabel(
            member.map {
                "Slot \(index + 1), \(speciesName($0.pokemonID)), \(summary($0))"
                    + (breach.map { ". \($0)." } ?? "")
            } ?? "Slot \(index + 1), empty. Add a Pokémon."
        )
    }

    /// A `TeamMember` carries only `pokemon_id`, so the name comes from the species list. Before
    /// that lands — or for an id the list somehow lacks — the dex number is still a true answer.
    private func speciesName(_ pokemonID: Int) -> String {
        species.first { $0.id == pokemonID }?.name.capitalized ?? "#\(pokemonID)"
    }

    private func summary(_ member: TeamMember) -> String {
        var parts = ["Lv \(member.level)", member.nature.capitalized]
        if let item = member.itemSlug, !item.isEmpty {
            parts.append(items.first { $0.slug == item }?.name ?? prettifySlug(item))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: The two roster rules

    /// Champions rejects a team holding the same species twice, or the same item twice — a 400
    /// from `UpdateTeamHandler` either way. Both are computed here so the editor can say it before
    /// Save rather than after, the way the stat-point cap is unreachable rather than validated.
    ///
    /// An empty `item_slug` is "no item", which any number of slots may share.
    private var duplicateSpecies: Set<Int> { repeated(members.map(\.pokemonID)) }

    private var duplicateItems: Set<String> {
        repeated(members.compactMap(\.itemSlug).filter { !$0.isEmpty })
    }

    private func repeated<T: Hashable>(_ values: [T]) -> Set<T> {
        var seen: Set<T> = []
        var twice: Set<T> = []
        for value in values where !seen.insert(value).inserted { twice.insert(value) }
        return twice
    }

    /// The message under the roster, naming the rule that is broken. `nil` means Save is allowed.
    private var ruleBreach: String? {
        switch (duplicateSpecies.isEmpty, duplicateItems.isEmpty) {
        case (true, true): nil
        case (false, true): "A team can't carry the same Pokémon twice."
        case (true, false): "A team can't carry the same held item twice."
        case (false, false): "A team can't carry the same Pokémon twice, or the same held item twice."
        }
    }

    /// What this slot is guilty of, spelled out — the marker is a word as well as a colour, since
    /// a red hairline alone says nothing to anyone who cannot see it.
    private func breach(_ member: TeamMember?) -> String? {
        guard let member else { return nil }
        var reasons: [String] = []
        if duplicateSpecies.contains(member.pokemonID) { reasons.append("Duplicate Pokémon") }
        if let item = member.itemSlug, duplicateItems.contains(item) { reasons.append("Duplicate item") }
        return reasons.isEmpty ? nil : reasons.joined(separator: " · ")
    }

    // MARK: Save

    private var members: [TeamMember] { slots.compactMap { $0 } }

    /// **The rename rule.** `members: nil` omits the key, which `UpdateTeamHandler` reads as "leave
    /// the roster alone"; an array replaces it wholesale. So a save that changed only the name
    /// sends `nil` — sending the six slots back would be a needless rewrite, and sending `[]` (or a
    /// partial list) would delete the team's Pokémon. A team being created has nothing to preserve,
    /// so it always sends its array.
    private func save() async {
        saving = true
        await model.save(
            id: team?.id,
            name: trimmedName,
            members: team == nil || members != (team?.members ?? []) ? members : nil
        )
        saving = false
        if model.syncError == nil { dismiss() }
    }
}

/// `leftovers` → `Leftovers`. ``SpeciesSheet`` has the same two lines as a private method; this is
/// the Teams copy rather than a shared helper, because the two would want different things the
/// moment either grows an exception.
func prettifySlug(_ slug: String) -> String {
    slug.replacingOccurrences(of: "-", with: " ").capitalized
}
