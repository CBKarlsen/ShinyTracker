import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// Logging the one encounter a route gives you — the single act a Nuzlocke run is made of.
///
/// The species list is the location's seeded pool and nothing else: `PutRunEncounterHandler`
/// validates `pokemon_id` against exactly that pool and 400s on anything else, so offering a
/// free search here would only produce refusals.
struct EncounterSheet: View {
    @State var model: NuzlockeModel
    let location: NuzlockeTimelineEntry

    @Environment(\.dismiss) private var dismiss
    @State private var pokemonID: Int?
    @State private var status: EncounterStatus = .caught
    @State private var nickname = ""
    @State private var saving = false
    @State private var failure: String?

    private var pool: [NuzlockeEncounterOption] { location.encounters ?? [] }

    /// Nickname is required when the run says so and the outcome carries a Pokémon — the same
    /// rule `needsNickname` applies server-side, checked here so the sheet does not have to be
    /// re-opened to learn it.
    private var needsNickname: Bool {
        (model.run?.nicknamesRequired ?? false) && status.carriesPokemon
    }

    private var canSave: Bool {
        guard !saving else { return false }
        if status.carriesPokemon && pokemonID == nil { return false }
        if needsNickname && nickname.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                outcomePicker

                if status.carriesPokemon {
                    speciesPicker
                    if needsNickname { nicknameField }
                }

                if let failure {
                    Text(failure)
                        .font(Typography.hint)
                        .foregroundStyle(Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button(saving ? "Saving…" : "Log it") { save() }
                    .buttonStyle(BlueButtonStyle())
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.5)
            }
            .padding(18)
        }
        .background(Palette.sheet)
        .presentationDetents([.large])
        .presentationBackground(Palette.sheet)
        .onAppear(perform: preload)
    }

    /// Re-opening a logged route edits it rather than starting over, so the sheet opens on what
    /// is already recorded.
    private func preload() {
        guard let existing = model.log(at: location.slug) else { return }
        pokemonID = existing.pokemonID
        status = EncounterStatus(rawValue: existing.status) ?? .caught
        nickname = existing.nickname ?? ""
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(location.name)
                .font(Typography.sheetTitle)
                .tracking(Typography.sheetTitleTracking)
                .foregroundStyle(Palette.textPrimary)
            Text(
                model.run?.dupesClause == true
                    ? "One encounter · dupes clause on" : "One encounter"
            )
            .font(Typography.meta)
            .foregroundStyle(Palette.textMuted)
        }
    }

    /// Caught / Fainted / Missed / Ran. All four burn the route; only the first two carry a
    /// Pokémon forward.
    private var outcomePicker: some View {
        HStack(spacing: 2) {
            ForEach(EncounterStatus.allCases, id: \.self) { candidate in
                let on = candidate == status
                Button {
                    status = candidate
                    failure = nil
                } label: {
                    Text(candidate.rawValue.capitalized)
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
    }

    private var speciesPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What did you meet?")
                .font(Typography.blockLabel)
                .tracking(Typography.blockLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textMuted)

            if pool.isEmpty {
                Text("This route has no seeded encounter pool.")
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textFaint)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8
            ) {
                ForEach(pool) { option in
                    speciesTile(option)
                }
            }
        }
    }

    /// A dupe is shown, not hidden: the clause re-rolls the encounter, and you can only decide
    /// that if you can see what you ran into. The server flags it either way.
    private func speciesTile(_ option: NuzlockeEncounterOption) -> some View {
        let dupe = model.run?.dupesClause == true
            && model.caughtSpeciesIDs.contains(option.pokemonID)
            && model.log(at: location.slug)?.pokemonID != option.pokemonID
        let on = pokemonID == option.pokemonID
        return Button {
            pokemonID = option.pokemonID
            failure = nil
        } label: {
            VStack(spacing: 5) {
                DexSprite(pokemonID: option.pokemonID, size: 50, served: option.spriteURL)
                Text(option.pokemonName.capitalized)
                    .font(Typography.tileName)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if dupe {
                    Text("dupe")
                        .font(Typography.tileSub)
                        .foregroundStyle(Palette.textFaint)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
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
        .accessibilityLabel(option.pokemonName.capitalized + (dupe ? ", already caught" : ""))
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    private var nicknameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nickname")
                .font(Typography.blockLabel)
                .tracking(Typography.blockLabelTracking)
                .textCase(.uppercase)
                .foregroundStyle(Palette.textMuted)
            TextField("", text: $nickname, prompt: Text("Required by this run's rules"))
                .font(Typography.segmentOn)
                .foregroundStyle(Palette.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Palette.field, in: .rect(cornerRadius: Radii.headerButton))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.headerButton)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
        }
    }

    private func save() {
        saving = true
        failure = nil
        let trimmed = nickname.trimmingCharacters(in: .whitespaces)
        let carries = status.carriesPokemon
        // ponytail: `nature` is accepted by the API and not collected here — a free-text field
        // invites typos and a 25-value picker earns its place only once natures affect something
        // the app computes.
        //
        // `isBoxed` is carried over from the existing row rather than left nil. This endpoint is
        // an upsert, not a patch: `PutRunEncounterHandler` reads an absent `is_boxed` as **false**
        // and writes it unconditionally, so omitting it here would pull a boxed Pokémon back into
        // the party every time the row is re-saved — fixing a nickname typo would silently
        // un-box it.
        //
        // `nickname` is gated on the outcome for the same reason `pokemonID` is: the field is
        // hidden, not cleared, when the status stops carrying a Pokémon, and the server stores
        // whatever it is sent. Switching a catch to "missed" would otherwise leave a nickname on
        // a slot with nothing in it.
        let body = LogEncounterRequest(
            status: status,
            pokemonID: carries ? pokemonID : nil,
            nickname: carries && !trimmed.isEmpty ? trimmed : nil,
            isBoxed: carries ? model.log(at: location.slug)?.isBoxed : nil
        )
        Task {
            failure = await model.logEncounter(at: location.slug, body)
            saving = false
            if failure == nil { dismiss() }
        }
    }
}
