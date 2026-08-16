import ShinyTrackerAPI
import ShinyTrackerKit
import ShinyTrackerUI
import SwiftUI
import UIKit

/// Paste a Showdown team in, get a saved team out.
///
/// **Import always creates a new team.** It never writes into one that already exists — a paste
/// is unvalidated text from somewhere else, and a bad one must not be able to destroy six slots
/// of work. The cost of that rule is a duplicate team when someone meant to replace one, which
/// they can delete; the cost of breaking it is unrecoverable.
///
/// A species that cannot be matched is **named** in the result rather than dropped in silence.
/// Losing a Pokémon without saying so is the failure this screen exists to avoid.
struct ImportPasteSheet: View {
    let model: TeamsModel
    let client: APIClient
    /// The outcome to surface on the list behind this sheet: nil when everything resolved,
    /// otherwise what was skipped. Only called after the team is actually saved.
    let onImported: (String?) -> Void

    @State private var name = ""
    @State private var text = ""
    @State private var species: [Pokemon] = []
    @State private var items: [Item] = []
    @State private var importing = false
    @State private var failure: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.cardGap) {
                    nameField
                    pasteField

                    if let failure {
                        Text(failure)
                            .font(Typography.hint)
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(
                        "Six sets at most. Anything the Scarlet/Violet dex doesn't have is named back to you rather than dropped quietly."
                    )
                    .font(Typography.hint)
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .background(Palette.sheet)
            .navigationTitle("Import a paste")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { Task { await runImport() } }
                        .fontWeight(.semibold)
                        .disabled(importing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(Palette.team)
        .presentationDetents([.large])
        .presentationBackground(Palette.sheet)
        .task {
            // The same two static lists the editor loads, for the same reason: resolving
            // "Rocky Helmet" to `rocky-helmet` is a local lookup, not a request per set.
            async let allSpecies = try? client.pokemon(all: true)
            async let allItems = try? client.items()
            species = await allSpecies ?? []
            items = await allItems ?? []
        }
    }

    // MARK: Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("TEAM NAME")
                .font(Typography.overline)
                .tracking(Typography.overlineTracking)
                .foregroundStyle(Palette.textMuted)

            TextField("Imported team", text: $name)
                .font(Typography.listTitle)
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.team)
                .autocorrectionDisabled()
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
                    while name.unicodeScalars.count > TeamEditorScreen.nameLimit { name.removeLast() }
                }
        }
    }

    private var pasteField: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("SHOWDOWN PASTE")
                    .font(Typography.overline)
                    .tracking(Typography.overlineTracking)
                    .foregroundStyle(Palette.textMuted)
                Spacer(minLength: 10)
                // Nobody types a six-set paste on a phone; it arrives on the clipboard.
                Button("Paste") { text = UIPasteboard.general.string ?? text }
                    .font(Typography.summary)
                    .foregroundStyle(Palette.team)
                    .frame(minHeight: Metrics.controlNarrow)
                    .accessibilityLabel("Paste from the clipboard")
            }

            TextEditor(text: $text)
                .font(Typography.stat)
                .foregroundStyle(Palette.textPrimary)
                .tint(Palette.team)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 240)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Palette.field, in: .rect(cornerRadius: Radii.row))
                .overlay(
                    RoundedRectangle(cornerRadius: Radii.row)
                        .strokeBorder(Palette.border, lineWidth: 1)
                )
                .accessibilityLabel("Showdown paste")
        }
    }

    // MARK: Import

    private func runImport() async {
        importing = true
        failure = nil
        defer { importing = false }

        guard !species.isEmpty else {
            failure = "Couldn't load the species list, so nothing can be matched yet. Try again in a moment."
            return
        }

        let sets: [ShowdownPaste.ParsedSet]
        do {
            sets = try ShowdownPaste.parse(text)
        } catch let error as ShowdownPaste.ParseError {
            failure = message(for: error)
            return
        } catch {
            failure = "That doesn't read as a Showdown paste."
            return
        }

        var warnings: [String] = []
        // A paste is allowed to be a whole box. Six is what a team holds, so the rest are left
        // behind — said out loud, because a silent truncation is the same failure as a silent
        // drop.
        var kept = sets
        if kept.count > 6 {
            warnings.append(
                "That paste had \(kept.count) sets. Only the first six were imported — a team holds six.")
            kept = Array(kept.prefix(6))
        }

        var members: [TeamMember] = []
        var unresolved: [String] = []
        for set in kept {
            guard let match = species.first(where: {
                ShowdownBridge.key($0.name) == ShowdownBridge.key(set.species)
            }) else {
                unresolved.append(set.species)
                continue
            }
            do {
                // The Scarlet/Violet learnset and this species' abilities — what turns
                // "Swords Dance" into `swords-dance`.
                let detail = try await client.pokemonDetail(id: match.id, gameID: scarletVioletGameID)
                members.append(
                    ShowdownBridge.member(
                        from: set, slot: members.count + 1, detail: detail, items: items))
            } catch {
                // A network failure mid-resolve aborts before anything is created, rather than
                // saving a team that is quietly missing the sets the request did not reach.
                failure = userFacingMessage(for: error) ?? "Couldn't load \(set.species)."
                return
            }
        }

        if !unresolved.isEmpty {
            warnings.append(
                "No match for \(unresolved.joined(separator: ", ")) — check the spelling, or the form name.")
        }
        guard !members.isEmpty else {
            failure = (warnings + ["Nothing in that paste could be matched to a Pokémon."])
                .joined(separator: " ")
            return
        }

        await model.save(
            id: nil,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Imported team" : name.trimmingCharacters(in: .whitespacesAndNewlines),
            members: members)

        guard model.syncError == nil else {
            failure = model.syncError
            return
        }
        onImported(warnings.isEmpty ? nil : warnings.joined(separator: " "))
        dismiss()
    }

    /// The typed parse error, naming what it choked on — `ParseError` carries the offending
    /// token in every case, which is the part a user can act on.
    private func message(for error: ShowdownPaste.ParseError) -> String {
        switch error {
        case .empty:
            "There is nothing to import yet."
        case .unknownNature(let name):
            "\"\(name)\" is not a nature."
        case .unknownStat(let label):
            "\"\(label)\" is not a stat. EV and IV lines use HP, Atk, Def, SpA, SpD and Spe."
        case .malformedSpreadLine(let part):
            "Couldn't read \"\(part.trimmingCharacters(in: .whitespaces))\" — an EV or IV line reads like \"252 Atk / 4 SpD / 252 Spe\"."
        }
    }
}
