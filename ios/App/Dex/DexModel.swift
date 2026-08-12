import Foundation
import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// One generation's worth of tiles. Built once per load — the species list never changes while
/// the screen is open, so the grid's structure is not recomputed on every tick.
struct DexSection: Identifiable {
    let generation: Int
    /// `Gen 4 · Sinnoh`
    let label: String
    let species: [Pokemon]

    var id: Int { generation }
}

/// Everything a tile needs to draw itself, resolved from the current view and the registration
/// sets. Kept as one value so the tile reads the model once instead of six times.
struct DexTileState: Equatable {
    /// Ticked in the current view.
    var registered = false
    /// The gold dot: a shiny you own, which the living dex counts for you.
    var goldDot = false
    /// Ticked and not un-tickable — a shiny finished in Hunt, or (in Living) one covered by a
    /// shiny you own. Tapping does nothing on purpose.
    var locked = false
    /// Outside the counted set: not in any game you own, or shiny locked everywhere.
    var unavailable = false
    /// The line under the name.
    var sub = ""
    var subColour: Color = Palette.textMuted.color
}

/// The Dex mode: one grid of every species, three ways of reading it.
///
/// Registration is split in two on purpose, because the API stores exactly one of the two:
/// - **Shiny** ticks are `user_hunts` rows. A hunt finished in Hunt (`HUNTED` / `PHASE`) is
///   already there and cannot be removed from here — `DELETE /api/hunts/manual/{id}` only
///   deletes `MANUAL_OVERRIDE` rows, and this model refuses to send the request at all.
/// - **Living** ticks for a species you own but have *not* got shiny have nowhere to go: there
///   is no living-dex table and no endpoint for one. They are kept on the device.
@MainActor
@Observable
final class DexModel {
    enum DexView: String, CaseIterable, Identifiable {
        case browse = "Browse", living = "Living", shiny = "Shiny"
        var id: Self { self }
    }

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: LoadState = .loading
    private(set) var sections: [DexSection] = []
    private(set) var games: [Game] = []

    /// nil = "All your games" — the only scope `/api/dex/status` can actually answer for.
    var selectedGameID: Int?
    var view: DexView = .browse

    /// Shinies finished in Hunt. Read-only here, by design.
    private(set) var huntShinyIDs: Set<Int> = []
    /// Shinies registered by hand (`MANUAL_OVERRIDE`). Tickable both ways.
    private(set) var manualShinyIDs: Set<Int> = []
    /// Species owned in a non-shiny form. Device-local; see the type's note.
    private(set) var livingOnlyIDs: Set<Int> = []
    /// Encounter count per hunt-derived shiny, for the tile's "2,847 enc" line.
    private(set) var huntEncounters: [Int: Int] = [:]

    private(set) var notInYourGames: Set<Int> = []
    private(set) var lockedEverywhere: Set<Int> = []

    /// A failed write, surfaced above the grid after the tile has been put back.
    private(set) var syncError: String?
    /// Why the tap you just made did nothing.
    private(set) var refusal: String?

    /// Not private: the species sheet fetches its own detail through the same client rather
    /// than routing every field through this model.
    let client: APIClient
    private let store: LivingDexStore

    init(client: APIClient, store: LivingDexStore) {
        self.client = client
        self.store = store
        livingOnlyIDs = store.load()
    }

    var selectedGame: Game? {
        games.first { $0.id == selectedGameID }
    }

    // MARK: Loading

    func load() async {
        state = .loading
        syncError = nil
        do {
            // Three independent GETs; the species list is the big one (1,025 rows) and there is
            // no reason for the other two to wait behind it.
            async let speciesTask = client.pokemon(all: true)
            async let gamesTask = client.games()
            async let huntsTask = client.hunts()
            async let statusTask = client.dexStatus()

            let species = try await speciesTask
            let games = try await gamesTask
            let hunts = try await huntsTask
            // `/api/dex/status` is the only blocked-state source; if it fails the grid is still
            // usable, so it degrades to "nothing is known to be blocked" instead of failing
            // the whole screen.
            let status = try? await statusTask

            sections = Self.group(species)
            self.games = games
            apply(hunts: hunts)
            notInYourGames = Set(status?.notInYourGames ?? [])
            lockedEverywhere = Set(status?.lockedEverywhere ?? [])
            state = .ready
        } catch {
            state = .failed(userFacingMessage(for: error))
        }
    }

    private func apply(hunts: [HuntDetail]) {
        let completed = hunts.filter { $0.status == "completed" }
        // `MANUAL_OVERRIDE` is the "I already own this shiny" row the Dex writes; everything
        // else completed — `HUNTED`, `PHASE` — was earned in Hunt and is not ours to remove.
        huntShinyIDs = Set(
            completed.filter { $0.acquisitionType != "MANUAL_OVERRIDE" }.map(\.pokemonID))
        manualShinyIDs = Set(
            completed.filter { $0.acquisitionType == "MANUAL_OVERRIDE" }.map(\.pokemonID))
        huntEncounters = completed.reduce(into: [:]) { counts, hunt in
            guard hunt.acquisitionType != "MANUAL_OVERRIDE" else { return }
            counts[hunt.pokemonID] = max(counts[hunt.pokemonID] ?? 0, hunt.encounterCount)
        }
    }

    /// `genOf` + `REGION` from the prototype.
    static func group(_ species: [Pokemon]) -> [DexSection] {
        let regions = [
            1: "Kanto", 2: "Johto", 3: "Hoenn", 4: "Sinnoh", 5: "Unova",
            6: "Kalos", 7: "Alola", 8: "Galar", 9: "Paldea",
        ]
        return Dictionary(grouping: species.sorted { $0.id < $1.id }, by: { generation(of: $0.id) })
            .sorted { $0.key < $1.key }
            .map { generation, species in
                DexSection(
                    generation: generation,
                    label: "Gen \(generation) · \(regions[generation] ?? "—")",
                    species: species
                )
            }
    }

    static func generation(of id: Int) -> Int {
        switch id {
        case ...151: 1
        case ...251: 2
        case ...386: 3
        case ...493: 4
        case ...649: 5
        case ...721: 6
        case ...809: 7
        case ...905: 8
        default: 9
        }
    }

    // MARK: Registration sets

    /// Every shiny the user owns, however it got there.
    var shinyIDs: Set<Int> { huntShinyIDs.union(manualShinyIDs) }

    /// "A shiny counts for the living dex too" — so the living set is the union, never a
    /// separate tick the user has to make twice.
    var livingIDs: Set<Int> { livingOnlyIDs.union(shinyIDs) }

    // MARK: Obtainability
    //
    // ponytail: the qualifier the design puts on the bar — "counts only what is obtainable in
    // the selected game" — needs a per-game availability set, and the API has no endpoint that
    // returns one. `/api/dex/status` answers a *library-wide* question ("in none of the games
    // you own"), `/api/pokemon/{id}` answers a per-species one, and `/api/admin/availability`
    // is admin-only and also per-species. So the counted set here is "obtainable in your
    // library", and ``scopeNote`` says so on screen rather than letting the bar imply more
    // than it knows. One bulk endpoint — `GET /api/games/{id}/pokemon` returning
    // `pokemon_availability.pokemon_id` for a game — makes this exact.

    /// Not in any game the user owns.
    func isOutOfLibrary(_ id: Int) -> Bool { notInYourGames.contains(id) }

    /// Shiny locked in every game it appears in — it can never be caught shiny, so it is not
    /// part of the Shiny Dex's denominator.
    func isShinyLocked(_ id: Int) -> Bool { lockedEverywhere.contains(id) }

    /// Counted for the current view.
    func isCounted(_ id: Int) -> Bool {
        if isOutOfLibrary(id) { return false }
        return view == .shiny ? !isShinyLocked(id) : true
    }

    var countedTotal: Int {
        sections.reduce(0) { total, section in
            total + section.species.filter { isCounted($0.id) }.count
        }
    }

    var registeredCount: Int {
        let registered = view == .shiny ? shinyIDs : livingIDs
        return sections.reduce(0) { total, section in
            total + section.species.filter { registered.contains($0.id) && isCounted($0.id) }.count
        }
    }

    var progress: Double {
        countedTotal > 0 ? Double(registeredCount) / Double(countedTotal) : 0
    }

    /// `318 / 1025` / `1025 species`.
    var progressLabel: String {
        view == .browse
            ? "\(countedTotal) obtainable · \(sections.reduce(0) { $0 + $1.species.count }) total"
            : "\(registeredCount) of \(countedTotal)"
    }

    /// What the bar just counted, said plainly.
    var scopeNote: String? {
        guard view != .browse else { return nil }
        if countedTotal == 0 {
            return "No games in your library, so nothing counts yet — add the games you own, "
                + "and the bar starts counting what they can catch."
        }
        if let game = selectedGame {
            return "Counted across every game in your library. \(game.title) scopes the "
                + "locations and moveset on a species, but per-game availability is not in the "
                + "API yet, so it does not change this count."
        }
        return "Counted across every game in your library."
    }

    // MARK: Tiles

    func tileState(for species: Pokemon) -> DexTileState {
        var tile = DexTileState()
        let id = species.id
        tile.unavailable = !isCounted(id)

        switch view {
        case .browse:
            tile.sub = tile.unavailable
                ? (isShinyLocked(id) ? "shiny locked" : "not in your games")
                : "#" + String(format: "%03d", id)
            tile.subColour = tile.unavailable
                ? Palette.textMuted.color : Palette.textFaint.color

        case .living:
            tile.registered = livingIDs.contains(id)
            tile.goldDot = shinyIDs.contains(id) && !tile.unavailable
            tile.locked = shinyIDs.contains(id)
            if tile.unavailable {
                tile.sub = "not in your games"
            } else if tile.locked && !livingOnlyIDs.contains(id) {
                tile.sub = "Shiny — counts"
                tile.subColour = Palette.hunt.color
            } else {
                tile.sub = tile.registered ? "Registered" : "Missing"
                tile.subColour = tile.registered
                    ? Palette.textSecondary.color : Palette.textMuted.color
            }

        case .shiny:
            tile.registered = shinyIDs.contains(id)
            tile.locked = huntShinyIDs.contains(id)
            if tile.unavailable {
                tile.sub = isShinyLocked(id) ? "shiny locked" : "not in your games"
            } else if let encounters = huntEncounters[id], tile.locked {
                tile.sub = "\(encounters.formatted(.number)) enc"
                tile.subColour = Palette.hunt.color
            } else {
                tile.sub = tile.registered ? "Registered" : "Missing"
                tile.subColour = tile.registered
                    ? Palette.hunt.color : Palette.textMuted.color
            }
        }
        return tile
    }

    /// The line under the segmented control — the prototype's `dexViewHint`, verbatim.
    var viewHint: String {
        switch view {
        case .browse:
            "Tap a species for stats, locations, evolutions and moves."
        case .living:
            "Tap to register a species you own in any form. Gold-dot tiles are already covered "
                + "by a shiny you own, so they register themselves and stay ticked here."
        case .shiny:
            "Tap to register a shiny you own. Anything you finish in Hunt lands here on its own "
                + "and cannot be un-registered by hand."
        }
    }

    // MARK: Ticking

    func tap(_ species: Pokemon) {
        let id = species.id
        refusal = nil
        syncError = nil

        guard isCounted(id) else {
            refusal = view == .shiny && isShinyLocked(id)
                ? "\(species.name.capitalized) is shiny locked in every game it appears in."
                : "\(species.name.capitalized) is not in any game in your library."
            Haptics.notify(.warning)
            return
        }

        switch view {
        case .browse:
            break                                       // the screen opens the sheet instead

        case .living:
            // A shiny already covers the living dex. Un-ticking it here would claim you no
            // longer own a Pokemon you demonstrably caught.
            guard !shinyIDs.contains(id) else {
                refusal = "You own \(species.name.capitalized) shiny, so the living dex counts "
                    + "it already. Un-register it in Shiny if that is wrong."
                Haptics.notify(.warning)
                return
            }
            if livingOnlyIDs.contains(id) {
                livingOnlyIDs.remove(id)
            } else {
                livingOnlyIDs.insert(id)
            }
            store.save(livingOnlyIDs)
            Haptics.impact(.light)

        case .shiny:
            // The rule from the design: shinies you finish in Hunt register themselves and
            // can't be unticked by hand. The server enforces it too (the delete filters on
            // MANUAL_OVERRIDE); refusing here means no pointless request and a real message.
            guard !huntShinyIDs.contains(id) else {
                refusal = "\(species.name.capitalized) was finished in Hunt, so it registers "
                    + "itself. Delete the hunt if it should not be here."
                Haptics.notify(.warning)
                return
            }
            Task { await toggleManualShiny(id) }
        }
    }

    private func toggleManualShiny(_ id: Int) async {
        let wasRegistered = manualShinyIDs.contains(id)
        // Optimistic, like the hunt counter: the tile flips now and goes back if the write
        // fails, so a tap never waits on a round trip.
        if wasRegistered { manualShinyIDs.remove(id) } else { manualShinyIDs.insert(id) }
        Haptics.impact(.light)

        do {
            if wasRegistered {
                try await client.removeManualCatch(pokemonID: id)
            } else {
                _ = try await client.markManualCatch(pokemonID: id)
            }
        } catch {
            if wasRegistered { manualShinyIDs.insert(id) } else { manualShinyIDs.remove(id) }
            syncError = "Couldn't save that. \(userFacingMessage(for: error))"
        }
    }

    func clearMessages() {
        refusal = nil
        syncError = nil
    }
}

/// Where the living-dex-only ticks live.
///
/// ponytail: `UserDefaults`, because the server has nowhere to put them — `user_hunts` is the
/// only ownership table and every row in it means "shiny". A species you own in a normal form
/// is not representable in the API today, so this is per-device and does not sync — and the key
/// is not scoped by user, so two accounts on one device would share these ticks. Both problems
/// go away with a server table; swap the two closures for a real endpoint when one exists and
/// nothing else has to change.
@MainActor
struct LivingDexStore {
    var load: () -> Set<Int>
    var save: (Set<Int>) -> Void

    /// Scoped to a user id, so two accounts on one device do not inherit each other's
    /// ticks. Still per-device and still unsynced — that needs a server table — but a
    /// signed-out/signed-in pair no longer silently shows one person another's dex.
    static func userDefaults(userID: UUID?) -> LivingDexStore {
        let key = key(for: userID)
        return LivingDexStore(
            load: { Set(UserDefaults.standard.array(forKey: key) as? [Int] ?? []) },
            save: { UserDefaults.standard.set(Array($0).sorted(), forKey: key) }
        )
    }

    /// In memory only — the preview harness, which must not write to the simulator's defaults.
    static func ephemeral(_ initial: Set<Int> = []) -> LivingDexStore {
        let box = Box(initial)
        return LivingDexStore(load: { box.value }, save: { box.value = $0 })
    }

    /// A signed-out device gets its own bucket rather than colliding with the last
    /// user's, which is the case that would otherwise leak one dex into another.
    private static func key(for userID: UUID?) -> String {
        "dex.livingOnly." + (userID?.uuidString.lowercased() ?? "anonymous")
    }

    private final class Box {
        var value: Set<Int>
        init(_ value: Set<Int>) { self.value = value }
    }
}
