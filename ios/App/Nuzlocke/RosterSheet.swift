import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// Everything the run has caught, in three sections: party, box, graveyard.
///
/// The run screen shows the party as a strip of tiles and the other two as bare counts — "3 in
/// graveyard" with nothing behind it. That is the gap this fills. It matters more than it looks:
/// a Nuzlocke's dead are the record of the run, and until now the only place a fainted Pokémon
/// appeared at all was a `Dead` tag on one timeline row.
///
/// Every row names the route its Pokémon came from, which is the lookup the party strip cannot
/// answer — "what did I get on 205?" previously meant scrolling 62 timeline rows hunting a sprite.
/// ``NuzlockeModel/locationName(for:)`` had been written for exactly this and never called.
struct RosterSheet: View {
    @State var model: NuzlockeModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                section("Party", model.party, tint: Palette.nuzlocke)
                section("Box", model.boxed, tint: Palette.textMuted)
                section("Graveyard", model.graveyard, tint: Palette.danger)

                if model.party.isEmpty, model.boxed.isEmpty, model.graveyard.isEmpty {
                    Text("Nothing caught yet.")
                        .font(Typography.hint)
                        .foregroundStyle(Palette.textFaint.color)
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .navigationTitle("Roster")
            .navigationSubtitle(summary)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// "4 alive · 2 boxed · 3 lost" — the shape of the run in one line. Omits what is empty
    /// rather than printing "0 lost", which reads as a boast on a run that has not started.
    private var summary: String {
        var parts: [String] = []
        if !model.party.isEmpty { parts.append("\(model.party.count) alive") }
        if !model.boxed.isEmpty { parts.append("\(model.boxed.count) boxed") }
        if !model.graveyard.isEmpty { parts.append("\(model.graveyard.count) lost") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func section(
        _ title: String, _ members: [NuzlockeEncounterLog], tint: Swatch
    ) -> some View {
        if !members.isEmpty {
            Section {
                ForEach(members) { member in
                    row(member)
                }
            } header: {
                Text("\(title) · \(members.count)")
                    .foregroundStyle(tint.color)
            }
        }
    }

    private func row(_ member: NuzlockeEncounterLog) -> some View {
        HStack(spacing: 12) {
            DexSprite(
                pokemonID: member.pokemonID ?? 0,
                size: 40,
                served: model.option(for: member)?.spriteURL
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(member.nickname ?? model.speciesName(for: member))
                    .font(Typography.summary)
                    .foregroundStyle(Palette.textPrimary.color)
                    .lineLimit(1)

                // Species as well as nickname: six runs in, "Gerald" alone does not tell you
                // whether you are looking at the Staraptor.
                Text(subtitle(for: member))
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textMuted.color)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing) {
            // Only the moves that mean something from where this Pokémon is. A fainted Nuzlocke
            // Pokémon is terminal by the rules, but the tick is a human action and humans mistap,
            // so revival stays available — as an explicit choice, not a default.
            if member.status == "caught", !member.isBoxed {
                Button("Box") { Task { await model.move(member, to: .boxed) } }
                Button("Fainted", role: .destructive) {
                    Task { await model.move(member, to: .fainted) }
                }
            } else if member.status == "caught", member.isBoxed {
                Button("To party") { Task { await model.move(member, to: .alive) } }
                Button("Fainted", role: .destructive) {
                    Task { await model.move(member, to: .fainted) }
                }
            } else if member.status == "fainted" {
                Button("Revive") { Task { await model.move(member, to: .alive) } }
            }
        }
    }

    /// "Staraptor · Route 205". The route is where it was **caught** — the schema records no
    /// death location, so a graveyard row must not imply one.
    private func subtitle(for member: NuzlockeEncounterLog) -> String {
        let route = model.locationName(for: member)
        // The row's title is the nickname when there is one. Without a nickname it is already
        // the species, so naming the species again here would print the same word twice.
        guard member.nickname != nil else { return route }
        return "\(model.speciesName(for: member)) · \(route)"
    }
}
