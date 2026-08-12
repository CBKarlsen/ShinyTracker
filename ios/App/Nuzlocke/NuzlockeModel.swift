import Foundation
import ShinyTrackerAPI
import ShinyTrackerUI
import SwiftUI

/// Loads the caller's runs and owns the one that is open.
///
/// The server's `GET /api/runs/{id}` hands back an immutable ``NuzlockeRunDetail``. Rather than
/// rebuild that whole struct after every write, the parts a write touches — the logged
/// encounters and the beaten set — are unpacked into mutable state here, and the timeline (pure
/// reference data, never written) is kept beside them. A write applies the row the server
/// returned; nothing re-fetches the run.
@MainActor
@Observable
final class NuzlockeModel {
    private(set) var state: LoadState = .loading
    /// Every run, newest first — `GET /api/runs` orders by `created_at DESC` and does not filter
    /// by status, so ended runs are in here too.
    private(set) var runs: [NuzlockeRun] = []

    /// The open run. Nil when the user has none, or while the list is still loading.
    private(set) var run: NuzlockeRun?
    /// Seeded reference data for ``run``'s game, in `sort_order`.
    private(set) var timeline: [NuzlockeTimelineEntry] = []
    private(set) var encounters: [NuzlockeEncounterLog] = []
    /// Boss slugs marked beaten. A set, not the `[NuzlockeBossProgress]` the API sends: every
    /// read is a membership test and every write flips one slug.
    private(set) var beaten: Set<String> = []

    /// A failed write, surfaced after the optimistic change has been rolled back.
    private(set) var syncError: String?
    /// True while the open run is being swapped for another one.
    private(set) var loadingRun = false

    let client: APIClient

    init(client: APIClient) { self.client = client }

    // MARK: Loading

    func load() async {
        state = .loading
        await reload(quiet: false)
    }

    /// After starting a run, where blanking the screen behind the closing sheet reads as a bug.
    func refresh() async { await reload(quiet: true) }

    private func reload(quiet: Bool) async {
        syncError = nil
        do {
            runs = try await client.runs()
            // Prefer the run the user is actually playing. `runs` is newest-first, so this picks
            // the most recently started active run and only falls back to an archived one when
            // every run has been ended.
            let wanted = run.flatMap { current in runs.first { $0.id == current.id } }
                ?? runs.first { $0.isActive }
                ?? runs.first
            if let wanted {
                try await open(wanted)
            } else {
                clearOpenRun()
            }
            state = .ready
        } catch {
            if quiet {
                syncError = "Couldn't refresh your runs. \(userFacingMessage(for: error))"
            } else {
                state = .failed(userFacingMessage(for: error))
            }
        }
    }

    /// Switches the open run. Errors surface as ``syncError`` rather than blanking the screen —
    /// the run that is already open is still perfectly readable.
    func select(_ candidate: NuzlockeRun) async {
        guard candidate.id != run?.id else { return }
        loadingRun = true
        defer { loadingRun = false }
        do {
            try await open(candidate)
            syncError = nil
        } catch {
            syncError = "Couldn't open that run. \(userFacingMessage(for: error))"
        }
    }

    private func open(_ candidate: NuzlockeRun) async throws {
        let detail = try await client.run(id: candidate.id)
        run = candidate
        timeline = detail.timeline.sorted { $0.sortOrder < $1.sortOrder }
        encounters = detail.encounters
        beaten = Set(detail.bossProgress.filter(\.beaten).map(\.bossSlug))
    }

    private func clearOpenRun() {
        run = nil
        timeline = []
        encounters = []
        beaten = []
    }

    // MARK: Reading the timeline

    func log(at locationSlug: String) -> NuzlockeEncounterLog? {
        encounters.first { $0.locationSlug == locationSlug }
    }

    func isBeaten(_ bossSlug: String) -> Bool { beaten.contains(bossSlug) }

    /// The next boss you have not beaten — the run's current checkpoint, and the source of the
    /// level cap. Nil once every seeded boss is down.
    var nextCheckpoint: NuzlockeTimelineEntry? {
        timeline.first { $0.isBoss && !isBeaten($0.slug) }
    }

    /// "CAP 33" — the next checkpoint's cap. Every seeded boss has one, but the column is
    /// nullable, so this can be nil even mid-run.
    var levelCap: Int? { nextCheckpoint?.levelCap }

    /// "you're here": the first location with nothing logged against it. Locations are logged in
    /// route order in practice, but this deliberately finds the first *gap* rather than the
    /// furthest point, so skipping one and coming back still points at the one you owe.
    var currentLocationSlug: String? {
        timeline.first { !$0.isBoss && log(at: $0.slug) == nil }?.slug
    }

    /// Alive and in the party: caught, not boxed. The API imposes no party size — six is a game
    /// rule the server does not model — so this is however many you have.
    var party: [NuzlockeEncounterLog] { encounters.filter { $0.status == "caught" && !$0.isBoxed } }

    var boxed: [NuzlockeEncounterLog] { encounters.filter { $0.status == "caught" && $0.isBoxed } }

    /// The graveyard. `fainted` is terminal for a Nuzlocke — the run's whole point.
    var graveyard: [NuzlockeEncounterLog] { encounters.filter { $0.status == "fainted" } }

    /// "11 encounters" — every location you have resolved, however it went. A missed or fled
    /// encounter still burns the route.
    var encounterCount: Int { encounters.count }

    /// "Hardcore · 11 encounters". The prototype's "day 6" is deliberately absent: nothing stores
    /// in-game days, and counting real days since `started_at` would be a different number
    /// wearing the same label.
    var runSummary: String {
        guard let run else { return "" }
        var parts: [String] = []
        parts.append(run.dupesClause ? "Dupes clause" : "No dupes clause")
        if run.battleStyle == "set" { parts.append("set mode") }
        parts.append("\(encounterCount) encounter\(encounterCount == 1 ? "" : "s")")
        if !run.isActive { parts.append("ended") }
        return parts.joined(separator: " · ")
    }

    /// The pool entry a logged encounter came from, which is where its sprite and species name
    /// live — a ``NuzlockeEncounterLog`` carries neither reliably (`pokemon_name` is joined in by
    /// `GET /api/runs/{id}` alone, and absent from every write response).
    func option(for log: NuzlockeEncounterLog) -> NuzlockeEncounterOption? {
        guard let pokemonID = log.pokemonID else { return nil }
        return timeline
            .first { $0.slug == log.locationSlug }?
            .encounters?
            .first { $0.pokemonID == pokemonID }
    }

    /// Display name for a logged catch, from whichever source has it.
    func speciesName(for log: NuzlockeEncounterLog) -> String {
        let name = log.pokemonName ?? option(for: log)?.pokemonName
        return name?.capitalized ?? "Pokémon"
    }

    /// "Route 206" — the timeline entry a catch came from.
    func locationName(for log: NuzlockeEncounterLog) -> String {
        timeline.first { $0.slug == log.locationSlug }?.name ?? log.locationSlug
    }

    func entry(at slug: String) -> NuzlockeTimelineEntry? {
        timeline.first { $0.slug == slug }
    }

    /// Species already caught elsewhere in this run — what the dupes clause bars. Computed here
    /// so the encounter picker can grey them out *before* the server refuses, rather than after.
    /// The server is still the authority: it re-derives this on every write.
    var caughtSpeciesIDs: Set<Int> {
        Set(encounters.filter { $0.status == "caught" }.compactMap(\.pokemonID))
    }

    // MARK: Writing

    /// Starts a run and opens it. Returns the server's message on failure — a game with no
    /// seeded route is a 400, and that is the common case, not an exceptional one.
    func startRun(_ body: CreateRunRequest) async -> String? {
        do {
            let created = try await client.createRun(body)
            runs.insert(created, at: 0)
            try await open(created)
            state = .ready
            Haptics.notify(.success)
            return nil
        } catch {
            return userFacingMessage(for: error)
        }
    }

    /// Logs — or overwrites — the encounter at one location.
    ///
    /// No optimistic write: `is_dupe` is decided by the server (it re-derives the clause against
    /// every other catch in the run), so guessing the row here would show the wrong dupe flag
    /// about as often as the clause matters.
    @discardableResult
    func logEncounter(at locationSlug: String, _ body: LogEncounterRequest) async -> String? {
        guard let run else { return "No run is open." }
        do {
            let saved = try await client.logEncounter(
                runID: run.id, locationSlug: locationSlug, body)
            apply(saved)
            Haptics.notify(body.status == .caught ? .success : .warning)
            return nil
        } catch {
            return userFacingMessage(for: error)
        }
    }

    /// Moves a catch between alive, boxed and fainted.
    func move(_ log: NuzlockeEncounterLog, to status: PartyStatus) async {
        guard let run else { return }
        syncError = nil
        do {
            let saved = try await client.setPartyStatus(
                runID: run.id, memberID: log.id, PartyStatusRequest(status: status))
            apply(saved)
            Haptics.impact(status == .fainted ? .rigid : .light)
        } catch {
            syncError = "Couldn't move that Pokémon. \(userFacingMessage(for: error))"
        }
    }

    /// Ticks a checkpoint. Optimistic, because it is one boolean behind a checkbox and a
    /// round-trip of lag on a tick reads as a dropped tap.
    func setBoss(_ bossSlug: String, beaten isBeaten: Bool) async {
        guard let run else { return }
        if isBeaten { beaten.insert(bossSlug) } else { beaten.remove(bossSlug) }
        syncError = nil
        Haptics.impact(.light)
        do {
            try await client.setBossBeaten(
                runID: run.id, bossSlug: bossSlug, BossProgressRequest(beaten: isBeaten))
        } catch {
            // Undo this slug and nothing else. Restoring a snapshot of the whole set taken
            // before the request would erase any *other* checkpoint toggled while this one was
            // in flight — including one the server has already accepted. Same rule the hunt
            // counter and the game library follow: a rollback touches only the row that failed.
            if isBeaten { beaten.remove(bossSlug) } else { beaten.insert(bossSlug) }
            syncError = "Couldn't save that checkpoint. \(userFacingMessage(for: error))"
        }
    }

    /// Ends the run — archived, never deleted, and reopenable.
    func setRunStatus(_ status: RunStatus) async {
        guard let run else { return }
        syncError = nil
        do {
            let updated = try await client.updateRun(
                id: run.id, UpdateRunRequest(status: status))
            self.run = updated
            if let index = runs.firstIndex(where: { $0.id == updated.id }) {
                runs[index] = updated
            }
            Haptics.notify(.success)
        } catch {
            syncError = "Couldn't update the run. \(userFacingMessage(for: error))"
        }
    }

    /// Upserts a row the server returned, keyed the way the server keys it: one row per
    /// (run, location).
    private func apply(_ saved: NuzlockeEncounterLog) {
        if let index = encounters.firstIndex(where: { $0.id == saved.id })
            ?? encounters.firstIndex(where: { $0.locationSlug == saved.locationSlug })
        {
            encounters[index] = saved
        } else {
            encounters.append(saved)
        }
    }
}

// MARK: - Status vocabulary

/// How a logged encounter reads on screen. Encounter status and party status are two different
/// vocabularies server-side (`caught` + `is_boxed` is what "boxed" actually is), so this is the
/// one place they are collapsed into the four states a row can show.
enum EncounterOutcome {
    case party, boxed, dead, gone

    init(_ log: NuzlockeEncounterLog) {
        switch log.status {
        case "caught": self = log.isBoxed ? .boxed : .party
        case "fainted": self = .dead
        default: self = .gone                     // "missed" and "ran" both mean route burned
        }
    }

    var label: String {
        switch self {
        case .party: "Party"
        case .boxed: "Box"
        case .dead: "Dead"
        case .gone: "Gone"
        }
    }

    var tint: Swatch {
        switch self {
        case .party: Palette.nuzlocke
        case .boxed: Palette.textMuted
        case .dead: Palette.danger
        case .gone: Palette.textFaint
        }
    }
}
