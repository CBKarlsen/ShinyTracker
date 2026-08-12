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

    // MARK: Derived row state
    //
    // Built once per data change by `rebuild()` rather than computed per access. These were
    // computed properties, and `NuzlockeScreen` read `currentLocationSlug` inside the row builder
    // — so every redraw scanned the whole timeline, and for each entry scanned the encounters,
    // once for each of 62 rows. That was invisible at the 13 stops the prototype seeded and
    // became the dominant cost the day the timeline reached 62.

    private(set) var logsBySlug: [String: NuzlockeEncounterLog] = [:]
    /// `location slug -> pokemon id -> pool entry`, for the sprite and name of a logged catch.
    private(set) var optionsBySlug: [String: [Int: NuzlockeEncounterOption]] = [:]
    /// "you're here" — the first location with nothing logged against it.
    private(set) var currentSlug: String?
    private(set) var coverage: [CoverageGap] = []

    /// A failed write, surfaced after the optimistic change has been rolled back.
    private(set) var syncError: String?
    /// True while the open run is being swapped for another one.
    private(set) var loadingRun = false

    /// `pokemon_id -> types`, for the coverage matchup. A logged encounter carries no types and
    /// neither does the encounter pool, so the species table is the only source.
    private(set) var speciesTypes: [Int: [PokemonType]] = [:]
    private var loadedSpeciesTypes = false

    let client: APIClient
    private let store: SnapshotStore

    init(client: APIClient, store: SnapshotStore) {
        self.client = client
        self.store = store
    }

    // MARK: Loading

    func load() async {
        state = .loading
        await restoreSnapshot()
        await reload(quiet: false, reopen: true)
    }

    /// Draws the last-known run immediately rather than a spinner. The reload that follows always
    /// runs, so this is never shown without being corrected in the same breath — the trade is that
    /// a cold launch briefly shows stale data, which is what "opens instantly" costs.
    ///
    /// Only on the cold path, and only when both halves are on disk: a runs list with no open run
    /// renders the "start a run" empty state, which is a worse lie than a spinner.
    private func restoreSnapshot() async {
        guard let cached = await store.load([NuzlockeRun].self, as: .runs) else { return }
        // Same choice `reload` makes, and for the same reason: `runs` is newest-first, so this is
        // the most recently started active run, falling back to an archived one only if all ended.
        guard let wanted = cached.first(where: \.isActive) ?? cached.first,
            let detail = await store.load(NuzlockeRunDetail.self, as: .run(wanted.id))
        else { return }
        runs = cached
        apply(detail, for: wanted)
        state = .ready
    }

    /// Pull-to-refresh: the user asked for the server's version of everything, detail included.
    func refresh() async { await reload(quiet: true, reopen: true) }

    /// What a screen's `.task` calls. Reloading from scratch every time a tab is shown throws
    /// away a screen that is already correct: `AppShell` holds these models as `@State`, so the
    /// data survives the switch even though the view does not. Only a cold model shows a spinner.
    func appear() async {
        state == .ready ? await reload(quiet: true, reopen: false) : await load()
    }

    /// - Parameter reopen: whether to re-fetch the open run's detail. See the call site below for
    ///   why a warm appear says no.
    private func reload(quiet: Bool, reopen: Bool) async {
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
                // A quiet reload leaves the screen interactive, so anything the user does while
                // it is in flight races the detail GET: `open` assigns `beaten` and `encounters`
                // wholesale from a response that was assembled *before* the tap, silently undoing
                // a tick or a just-logged catch, and no later write re-syncs it. Skipped on a warm
                // appear because it buys nothing — every write already applies the row the server
                // returned, so the open run is current, and there is no second device to sync
                // from. Pull-to-refresh still re-opens: that one the user asked for.
                if reopen || wanted.id != run?.id {
                    try await open(wanted)
                } else {
                    run = wanted                    // list metadata only — never the detail
                }
            } else {
                clearOpenRun()
            }
            state = .ready
            await store.save(runs, as: .runs)
        } catch {
            if quiet || state == .ready {
                // A snapshot is on screen — warn inline rather than replacing it with an error.
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
        apply(detail, for: candidate)
        await store.save(detail, as: .run(candidate.id))
    }

    /// Unpacks a run detail into the mutable state this model keeps, derived rows included.
    ///
    /// Split out of ``open(_:)`` so the snapshot restore goes through the same path: the screen
    /// renders from `logsBySlug`/`currentSlug`/`coverage`, so assigning the three stores without
    /// the trailing `rebuild()` draws a run with an empty timeline and no coverage warning.
    private func apply(_ detail: NuzlockeRunDetail, for candidate: NuzlockeRun) {
        run = candidate
        timeline = detail.timeline.sorted { $0.sortOrder < $1.sortOrder }
        encounters = detail.encounters
        beaten = Set(detail.bossProgress.filter(\.beaten).map(\.bossSlug))
        rebuild()
    }

    private func clearOpenRun() {
        run = nil
        timeline = []
        encounters = []
        beaten = []
        rebuild()
    }

    /// Loads the species table once, for the coverage matchup only.
    ///
    /// One `GET /api/pokemon?limit=all` rather than a `pokemonDetail` per party member: a party
    /// turns over constantly, so per-member fetches would run on every catch and every death,
    /// and each one carries locations, stats, abilities and movesets this screen never reads.
    /// Failure is silent by design — a coverage warning that cannot be computed is simply not
    /// shown, and it is not worth an error banner over a run you can still play.
    func loadSpeciesTypes() async {
        guard !loadedSpeciesTypes else { return }
        do {
            let all = try await client.pokemon(all: true)
            // Not `uniqueKeysWithValues`: that traps on a duplicate id. Same reasoning as
            // `GameLibraryModel.load` — a crash is the wrong way to find out the table has one.
            speciesTypes = Dictionary(
                all.map { ($0.id, ($0.types ?? []).compactMap(PokemonType.init(slug:))) },
                uniquingKeysWith: { _, second in second }
            )
            loadedSpeciesTypes = true
            rebuild()
        } catch {
            // Deliberately swallowed — see above.
        }
    }

    // MARK: Reading the timeline

    /// Recomputes every derived value. Called from each of the four seams that can change what it
    /// depends on — see the call sites. Cheap enough to run whole: the timeline is ~62 entries.
    private func rebuild() {
        // Not `uniqueKeysWithValues`: it traps on a duplicate key, and the server's one-row-per-
        // (run, location) guarantee is not worth a crash to re-verify.
        logsBySlug = Dictionary(
            encounters.map { ($0.locationSlug, $0) }, uniquingKeysWith: { _, second in second })
        optionsBySlug = Dictionary(
            timeline.map { entry in
                (entry.slug,
                 Dictionary((entry.encounters ?? []).map { ($0.pokemonID, $0) },
                            uniquingKeysWith: { _, second in second }))
            },
            uniquingKeysWith: { _, second in second })
        currentSlug = timeline.first { !$0.isBoss && logsBySlug[$0.slug] == nil }?.slug
        coverage = computeCoverage()
    }

    func log(at locationSlug: String) -> NuzlockeEncounterLog? { logsBySlug[locationSlug] }

    func isBeaten(_ bossSlug: String) -> Bool { beaten.contains(bossSlug) }

    /// The next boss you have not beaten — the run's current checkpoint, and the source of the
    /// level cap. Nil once every seeded boss is down.
    var nextCheckpoint: NuzlockeTimelineEntry? {
        timeline.first { $0.isBoss && !isBeaten($0.slug) }
    }

    /// "CAP 33" — the next checkpoint's cap. Every seeded boss has one, but the column is
    /// nullable, so this can be nil even mid-run.
    var levelCap: Int? { nextCheckpoint?.levelCap }

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
        return optionsBySlug[log.locationSlug]?[pokemonID]
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

    // MARK: Coverage

    /// A damage type the next checkpoint deals that nothing alive in your party resists.
    struct CoverageGap: Identifiable {
        let type: PokemonType
        /// Boxed Pokémon that *do* resist it — "Gastly (box) and Staravia both do."
        let benchResisters: [NuzlockeEncounterLog]

        var id: String { type.rawValue }
    }

    /// "Nothing in your party resists Fighting."
    ///
    /// The threat is read off the boss's **moves**, not its species types, for two reasons: the
    /// API sends the squad's movesets and not their types, and what actually hurts you is the
    /// damage you will be hit with. Status moves are excluded — a Growl threatens nothing.
    ///
    /// The test is ``NuzlockeBossMove/isDamaging`` (damage class), **not** `power > 0`. Power is
    /// 0 for every variable-power move, and fifteen of Platinum's seeded boss moves are in that
    /// state — including all three of Gardenia's Grass Knots, which would otherwise make the
    /// Grass gym look like it threatened nothing at all.
    ///
    /// Returns empty rather than guessing whenever the answer would be unsound: no checkpoint, an
    /// empty party, or any living member whose types have not loaded. That last guard matters —
    /// an unknown member resists nothing as far as ``resists(_:_:)`` can tell, so without it a
    /// half-loaded species table would invent warnings about a party that covers itself fine.
    private func computeCoverage() -> [CoverageGap] {
        guard let boss = nextCheckpoint, let squad = boss.squad else { return [] }
        let alive = party
        guard !alive.isEmpty else { return [] }
        guard alive.allSatisfy({ log in log.pokemonID.map { speciesTypes[$0] != nil } ?? false })
        else { return [] }

        let threats = Set(
            squad.flatMap { $0.moves ?? [] }
                .filter(\.isDamaging)
                .compactMap { PokemonType(slug: $0.type) }
        )

        return threats
            .filter { threat in !alive.contains { resists($0, threat) } }
            .map { threat in
                CoverageGap(
                    type: threat,
                    benchResisters: boxed.filter { resists($0, threat) }
                )
            }
            // Stable order: a set iterates arbitrarily, and a warning card that reshuffles
            // itself between redraws reads as a glitch.
            .sorted { $0.type.rawValue < $1.type.rawValue }
    }

    /// Whether one logged Pokémon takes less than neutral damage from an attacking type.
    /// ``TypeChart/resistances(_:)`` folds immunities in, which is right here: a ×0 is the
    /// strongest resistance there is.
    private func resists(_ log: NuzlockeEncounterLog, _ threat: PokemonType) -> Bool {
        guard let id = log.pokemonID, let types = speciesTypes[id], !types.isEmpty else {
            return false
        }
        return TypeChart.resistances(types).contains { $0.type == threat }
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
        rebuild()
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
            rebuild()
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
        rebuild()
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
