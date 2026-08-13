import Foundation
import ShinyTrackerAPI
import ShinyTrackerAuth
import ShinyTrackerKit
import SwiftUI

/// One row of the Active list.
///
/// Holds the whole ``HuntDetail`` rather than flattened strings because the odds denominator is
/// **not** a constant: `radar_chain_*`, `sos_chain_gen7` and friends read the live encounter
/// count, so the denominator has to be recomputed every time ``count`` changes. Flattening it
/// once at load would freeze a chain hunt's odds at whatever they were when the list loaded.
struct HuntRow: Identifiable, Equatable {
    let detail: HuntDetail
    /// The optimistic count. Diverges from `detail.encounterCount` between a tap and its PATCH.
    var count: Int

    var id: UUID { detail.id }

    /// The API stores species names lowercase (`pokemon.name` comes straight from PokeAPI).
    var name: String { detail.pokemonName.capitalized }

    /// "Platinum · Full odds — wild". Both halves are `LEFT JOIN`ed and genuinely nullable — a
    /// custom-method hunt has no game row and no method row — so this drops what is missing
    /// instead of printing "nil" or an empty separator.
    var meta: String {
        [detail.gameTitle, detail.customMethodName ?? detail.methodName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The `1 / N` denominator, or nil when it cannot be computed.
    ///
    /// `baseOdds` comes from the joined game row, so a hunt with no game has no base odds and
    /// therefore no honest denominator. Guessing 8192 would be worse than showing nothing: the
    /// whole progress bar and the cumulative-probability label are derived from this.
    var denominator: Int? {
        guard let baseOdds = detail.baseOdds, baseOdds > 0 else { return nil }
        return ShinyOdds.effectiveOdds(
            formulaType: detail.formulaType,
            params: detail.huntParameters ?? [:],
            base: OddsConfig(
                baseOdds: baseOdds,
                baseRolls: detail.baseRolls ?? 1,
                charmRolls: detail.charmRolls ?? 0
            ),
            hasCharm: detail.hasShinyCharm ?? false,
            encounters: count
        )
    }

    /// `1 - (1 - 1/denominator)^encounters` — the chance of having seen a shiny by now.
    var cumulativeProbability: Double? {
        guard let denominator, denominator > 0, count > 0 else { return nil }
        return 1 - pow(1 - 1 / Double(denominator), Double(count))
    }

    /// Fill fraction of the progress bar: `Math.min(h.count / h.denom, 1)`.
    var progressRatio: Double {
        guard let denominator, denominator > 0 else { return 0 }
        return min(Double(count) / Double(denominator), 1)
    }
}

/// Loading / loaded / failed. Top-level because the Hunt list and the game library are two
/// screens with the same three states and no reason to spell them twice.
enum LoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

/// Loads the Active list and owns the optimistic counter.
@MainActor
@Observable
final class HuntListModel {
    /// `STEPS = [1, 2, 3, 5, 10]` — the ×N cycler.
    static let steps = [1, 2, 3, 5, 10]

    private(set) var state: LoadState = .loading
    private(set) var rows: [HuntRow] = []
    /// The History tab: `status == "completed"`, newest first (`GET /api/hunts` orders by
    /// `created_at DESC`).
    private(set) var history: [HuntRow] = []

    /// The emphasised card. The server has no such flag; the prototype sets `live` on whichever
    /// hunt you last counted (see its `bump()`), so this does the same and seeds it with the
    /// most recent hunt — `GET /api/hunts` orders by `created_at DESC`.
    private(set) var liveHuntID: UUID?

    /// A failed PATCH, surfaced above the list after the count has been rolled back.
    private(set) var syncError: String?

    /// Per-hunt ×N step. Lives here, not in ``HuntRow``, so it survives a reload of the list.
    private var stepByHunt: [UUID: Int] = [:]

    private let client: APIClient
    private let store: SnapshotStore
    /// Debounced writers, one per hunt. See ``scheduleSync(_:)``.
    private var pendingWrites: [UUID: Task<Void, Never>] = [:]
    /// The count each hunt had before its current burst of taps — the rollback target.
    private var preBurstCount: [UUID: Int] = [:]
    /// The clock each hunt had before that same burst. Time and count have to move together: the
    /// clock banks a gap on every tap and reaches disk before the PATCH, so rolling back only the
    /// count would credit a failed offline session its hours and one encounter, and every derived
    /// rate (the web app divides straight by `total_time_seconds`) is then nonsense.
    private var preBurstClock: [UUID: HuntClock] = [:]
    /// Client-owned elapsed time per hunt (D1). Restored from the store once per launch, then
    /// written back on every flush — a burst of taps is already coalesced there, so this does not
    /// touch the disk once per tap.
    private var clocks: [UUID: HuntClock] = [:]
    private var clocksRestored = false
    /// Hunts whose count the user lowered with "−" and whose PATCH has not landed yet. Cleared the
    /// moment the write resolves, either way, so a later sync cannot inherit the permission.
    private var loweredByUser: Set<UUID> = []
    /// Hunts whose count on screen is a number the server has confirmed this launch.
    ///
    /// The snapshot is stale by every tap of the previous session by construction — `.hunts` is
    /// written only by `load`, never by `flush` — so a restored 2,500 can sit in front of a server
    /// total of 2,847 indefinitely when the refresh behind it fails. `allow_decrease` on an
    /// absolute count from that state does not remove one encounter, it removes 348.
    ///
    /// Per row, not one flag for the session, because provenance genuinely is per row: `load`'s
    /// carve-out keeps the local count for any hunt with an unflushed burst, so a refresh can make
    /// every other row server-backed while that one still holds the snapshot's number. Membership
    /// is only ever added within a launch (and dropped with the hunt), so the press-time and
    /// send-time checks cannot disagree in the direction that loses data.
    private var serverBacked: Set<UUID> = []

    init(client: APIClient, store: SnapshotStore) {
        self.client = client
        self.store = store
    }

    func step(for id: UUID) -> Int { stepByHunt[id] ?? 1 }

    func cycleStep(_ id: UUID) {
        let steps = Self.steps
        let next = (steps.firstIndex(of: step(for: id)).map { $0 + 1 } ?? 1) % steps.count
        stepByHunt[id] = steps[next]
    }

    func load() async { await load(quiet: false) }

    /// `quiet` skips the loading state, for the reloads that follow a write the user just made:
    /// they already saw the sheet close, and blanking the list behind it reads as a bug.
    func refresh() async { await load(quiet: true) }

    /// What a screen's `.task` calls. Reloading from scratch every time a tab is shown throws
    /// away a screen that is already correct: `AppShell` holds these models as `@State`, so the
    /// data survives the switch even though the view does not. Only a cold model shows a spinner.
    func appear() async {
        state == .ready ? await refresh() : await load()
    }

    private func load(quiet: Bool) async {
        syncError = nil
        // Once per launch, not once per refresh: after the first read the in-memory dictionary is
        // newer than the file, and re-reading would throw away time counted since.
        if !clocksRestored {
            clocksRestored = true
            clocks = await store.load([UUID: HuntClock].self, as: .clocks) ?? [:]
        }
        // Draw last-known data immediately rather than a spinner. The refresh below always runs,
        // so this is never shown without being corrected in the same breath — the trade is that a
        // cold launch briefly shows stale data, which is what "opens instantly" costs.
        if !quiet, state != .ready, let cached: [HuntDetail] = await store.load([HuntDetail].self, as: .hunts) {
            rows = cached.filter { $0.status == "active" }.map { HuntRow(detail: $0, count: $0.encounterCount) }
            history = cached.filter { $0.status == "completed" }.map { HuntRow(detail: $0, count: $0.encounterCount) }
            // Same seeding rule as the loaded path, so a cold offline launch highlights a card
            // instead of waiting for the first tap to pick one.
            if liveHuntID == nil { liveHuntID = rows.first?.id }
            state = .ready
        }
        // Only reached still `.loading` (or `.failed`, retried) when the restore above did not
        // run or found nothing on disk — so this guard is the one actually gating whether the
        // spinner replaces a screen that already has something to show.
        if !quiet, state != .ready { state = .loading }
        do {
            // `status` is a free-form String on purpose (Models.swift), so both tabs are filled
            // by filtering one response rather than trusting the server to send one kind.
            let all = try await client.hunts()
            // The server's total is authoritative when it is ahead of this device: `DecideTotalTime`
            // keeps the max, so a clock left behind would have every send swallowed until it caught
            // up on its own. Only existing clocks are raised — `bump` seeds new ones from the same
            // field. Not persisted here: the value came from the server, which still has it.
            for detail in all where clocks[detail.id] != nil {
                clocks[detail.id]?.raise(to: detail.totalTimeSeconds)
            }
            // A burst of taps that has not been flushed yet is newer than anything this response
            // can contain, so it survives the reload. Without this, pull-to-refresh — or the
            // refresh that follows starting or completing another hunt — silently rolls those
            // taps back. `preBurstCount` is the unflushed set: `flush` clears it either way.
            //
            // ponytail: local wins while unflushed, which is wrong only in the multi-device case
            // (a second device's higher count would lose). Real reconciliation is the offline
            // sync layer's job — see DECISIONS.md D1 on the monotonic counter.
            // Which count each row shows, and whether it counts as confirmed, are one decision —
            // `HuntCountPolicy.rebuild`, in ShinyTrackerKit, where it is tested. They were two
            // expressions reading the same state, and a review found the pairing they can produce
            // (a count this client never confirmed, marked confirmed) is exactly what arms a
            // destructive "−". Returning both together makes them impossible to disagree.
            let unflushed = preBurstCount
            let current = rows
            var backed = serverBacked
            rows = all.filter { $0.status == "active" }.map { detail in
                let decision = HuntCountPolicy.rebuild(
                    response: detail.encounterCount,
                    onScreen: current.first(where: { $0.id == detail.id })?.count,
                    hasUnflushedBurst: unflushed[detail.id] != nil,
                    isServerBacked: backed.contains(detail.id)
                )
                if decision.isServerBacked { backed.insert(detail.id) }
                return HuntRow(detail: detail, count: decision.count)
            }
            serverBacked = backed
            history = all.filter { $0.status == "completed" }
                .map { HuntRow(detail: $0, count: $0.encounterCount) }
            if liveHuntID == nil || !rows.contains(where: { $0.id == liveHuntID }) {
                liveHuntID = rows.first?.id
            }
            state = .ready
            // The raw response, not `rows`/`history`: those are derived on the way back in, and a
            // second saved copy of the same thing is a second thing to keep in sync.
            await store.save(all, as: .hunts)
        } catch {
            if quiet || state == .ready {
                // A snapshot is on screen. Cached hunts plus a quiet warning beat an error page.
                syncError = "Couldn't refresh your hunts. \(message(for: error))"
            } else {
                state = .failed(message(for: error))
            }
        }
    }

    // MARK: Counting

    func bump(_ id: UUID, by delta: Int) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let before = rows[index].count
        let after = max(0, before + delta)          // the prototype clamps at 0 the same way
        guard after != before else { return }

        rows[index].count = after
        liveHuntID = id
        syncError = nil
        // D1: the client owns elapsed time. The threshold comes from the method's own cadence —
        // avg_time_seconds is already on HuntDetail, so this needs no request. Seeding from the
        // server's total means a hunt that was being timed server-side does not restart at zero
        // when this client takes over.
        let threshold = HuntClock.idleThreshold(avgTimeSeconds: rows[index].detail.avgTimeSeconds)
        let clockBefore = clocks[id] ?? HuntClock(totalSeconds: rows[index].detail.totalTimeSeconds)
        var clock = clockBefore
        clock.record(at: Date(), idleThreshold: threshold)
        clocks[id] = clock
        // Only "−" can get here with a negative delta (HuntCard), and this is the sole source of
        // allow_decrease. The provenance gate is at press time, not send time: what the permission
        // has to be true of is the number the user was looking at when they pressed. A refresh
        // landing inside the 400ms debounce backs every *other* row without correcting this one —
        // `load` deliberately keeps the local count for anything in `preBurstCount` — so a
        // send-time-only gate would hand this row's stale count the permission the first press was
        // denied, on nothing more exotic than a second tap of "−".
        if HuntCountPolicy.armsDecreasePermission(delta: delta, isServerBacked: serverBacked.contains(id)) {
            loweredByUser.insert(id)
        }
        Haptics.impact(delta > 0 ? .light : .rigid)
        scheduleSync(id, rollbackTo: before, clockRollbackTo: clockBefore)
    }

    /// Coalesces a burst of taps into one PATCH.
    ///
    /// Counting is a rapid-fire interaction — a hunter taps hundreds of times — and firing one
    /// request per tap both floods the API and races: two in-flight PATCHes can land out of
    /// order and write a stale count. Debouncing removes the race entirely instead of managing
    /// it, and the value sent is always the current one.
    private func scheduleSync(_ id: UUID, rollbackTo: Int, clockRollbackTo: HuntClock) {
        if preBurstCount[id] == nil {
            preBurstCount[id] = rollbackTo
            preBurstClock[id] = clockRollbackTo
        }
        pendingWrites[id]?.cancel()
        pendingWrites[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.flush(id)
        }
    }

    private func flush(_ id: UUID) async {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        let rollback = preBurstCount[id]
        // Captured before the await for the same reason `rollback` is: `markFound` and `abandon`
        // clear this state, so a Found pressed while this request is in flight would otherwise
        // leave the catch below rolling the count back with no clock to roll back with it.
        let rollbackClock = preBurstClock[id]
        // Before the request, not after: a clock that only reaches disk on a successful PATCH
        // loses the whole session if the app is killed offline, which is the case D1 exists for.
        await store.save(clocks, as: .clocks)
        do {
            // Supplying total_time_seconds latches this hunt client-authoritative for good
            // (calc.DecideTotalTime). That is correct now that HuntClock actually tracks it: the
            // server cannot see an offline session, and deriving from PATCH gaps would credit it
            // zero.
            let saved = try await client.updateHunt(
                huntID: id,
                UpdateHuntRequest(
                    encounterCount: row.count,
                    status: .active,
                    totalTimeSeconds: clocks[id]?.totalSeconds,
                    allowDecrease: allowDecrease(for: id)
                )
            )
            // The response carries what the server actually stored, so a value that lost
            // `DecideEncounterCount`'s comparison learns the truth here instead of diverging
            // silently — this is what heals a screen still showing a stale snapshot count.
            // `max` because taps made while the request was in flight are newer than both.
            if let index = rows.firstIndex(where: { $0.id == id }) {
                rows[index].count = HuntCountPolicy.reconciled(
                    local: rows[index].count, stored: saved.encounterCount)
            }
            // This row now rests on a number the server accepted, so it is server-backed even if
            // the list has never loaded. That is what turns a clamped "−" into a working one after
            // a single successful write, rather than only after a successful refresh.
            serverBacked.insert(id)
            forgetPendingBurst(id)
        } catch {
            // The row still being here gates both halves. A mark-found or abandon that landed
            // while this request was in flight has already dropped the hunt, and restoring its
            // clock then would write the entry back to disk to be restored on every launch for the
            // rest of the account's life — the dead weight `drop` deletes it to avoid. Count and
            // clock move together or not at all, which is I2's whole point.
            if let rollback, let index = rows.firstIndex(where: { $0.id == id }) {
                rows[index].count = rollback
                // The clock goes back with it, and back to disk: it was persisted above, before
                // the request, so leaving it advanced would keep time the taps never earned.
                if let rollbackClock {
                    clocks[id] = rollbackClock
                    await store.save(clocks, as: .clocks)
                }
            }
            // The count went back up with the rollback, so the permission to lower it no longer
            // describes anything the user asked for.
            forgetPendingBurst(id)
            syncError = "Couldn't save that count. \(message(for: error))"
        }
    }

    /// The only grant of `allow_decrease`: the user pressed "−" **and** the count it is relative to
    /// is one the server has confirmed. The flag makes the server take the number sent verbatim, so
    /// pairing it with a count restored from the snapshot would not subtract one encounter, it
    /// would overwrite the real total with a stale one.
    ///
    /// Belt and braces — `bump` already refuses to arm `loweredByUser` for an unbacked row, and
    /// `serverBacked` only grows within a launch, so this can only ever agree with that decision.
    private func allowDecrease(for id: UUID) -> Bool? {
        HuntCountPolicy.sendsDecreasePermission(
            userLowered: loweredByUser.contains(id), isServerBacked: serverBacked.contains(id)
        ) ? true : nil
    }

    // MARK: Found and abandoned

    /// Completes the hunt: it leaves the Active list and appears in History.
    ///
    /// Returns false and leaves the hunt alone if the write failed, so the confirm sheet can stay
    /// open rather than pretending a shiny was registered.
    @discardableResult
    func markFound(_ id: UUID) async -> Bool {
        guard let row = rows.first(where: { $0.id == id }) else { return false }
        // Land any pending count first, otherwise the completing PATCH races the debounced one.
        pendingWrites[id]?.cancel()
        do {
            // Sends the clock for the same reason `flush` does, so a completed hunt records the
            // time it actually took.
            //
            // It carries `allowDecrease` for the same reason too: the cancel above means this
            // PATCH inherits whatever the debounced one was going to send, including a "−"
            // pressed inside the 400ms window. Without the permission the monotonic guard
            // (`calc.DecideEncounterCount`) clamps that decrement away silently.
            //
            // The flag is dropped on **both** exits — `drop` on the way out, the catch below on
            // failure. Nothing here scopes it to mark-found, so keeping it after a failure would
            // arm the next ordinary `+` flush to write an absolute count with permission to lower
            // it, with no "−" pressed. The cost of dropping it is that the "−" inside that 400ms
            // window is silently clamped on a retry: a no-op instead of lost encounters.
            // The response is not reconciled into `rows` the way `flush` does it: this row leaves
            // the list two lines below, and the `refresh` after that re-reads the completed hunt
            // — with the stored count — straight from the server.
            _ = try await client.updateHunt(
                huntID: id,
                UpdateHuntRequest(
                    encounterCount: row.count,
                    status: .completed,
                    totalTimeSeconds: clocks[id]?.totalSeconds,
                    allowDecrease: allowDecrease(for: id)
                )
            )
            await drop(id)
            Haptics.notify(.success)
            // The completed hunt's final elapsed time is derived server-side from this very
            // PATCH, and the response is a `Hunt` (no `total_time_seconds`), so History can only
            // show the right number after a re-read.
            await refresh()
            return true
        } catch {
            forgetPendingBurst(id)
            syncError = "Couldn't mark that hunt found. \(message(for: error))"
            return false
        }
    }

    /// Deletes the hunt outright — no History row, nothing registered. There is no undo: the
    /// server has no soft delete, so the sheet arms this behind a second tap.
    @discardableResult
    func abandon(_ id: UUID) async -> Bool {
        pendingWrites[id]?.cancel()
        do {
            try await client.deleteHunt(huntID: id)
            await drop(id)
            Haptics.notify(.warning)
            return true
        } catch {
            forgetPendingBurst(id)
            syncError = "Couldn't abandon that hunt. \(message(for: error))"
            return false
        }
    }

    /// Forgets a burst that will now never be flushed: `markFound` and `abandon` both cancel the
    /// debounced write, so on their failure paths nothing else is left to clear this state. Leaving
    /// it arms two separate mistakes on a hunt that is still on screen — `loweredByUser` would hand
    /// the decrease permission to the next ordinary `+`, and `preBurstCount` would keep `load`'s
    /// carve-out treating the row as locally authoritative for the rest of the launch, which is
    /// exactly the stale-count-meets-fresh-permission pairing the gate in `bump` exists to stop.
    private func forgetPendingBurst(_ id: UUID) {
        loweredByUser.remove(id)
        preBurstCount[id] = nil
        preBurstClock[id] = nil
    }

    private func drop(_ id: UUID) async {
        rows.removeAll { $0.id == id }
        if liveHuntID == id { liveHuntID = rows.first?.id }
        // The hunt is finished or gone, so its clock is dead weight that would otherwise be
        // restored on every launch for the rest of the account's life.
        clocks[id] = nil
        // The only removal from `serverBacked`: the hunt itself is gone, so nothing can be pressed
        // against a stale copy of it. Anything less than that and the set could shrink under a row
        // still on screen, which is how the press-time and send-time gates would come to disagree.
        serverBacked.remove(id)
        forgetPendingBurst(id)
        await store.save(clocks, as: .clocks)
    }

    private func message(for error: any Error) -> String { userFacingMessage(for: error) }
}

/// Turns any error this app throws into something worth showing a user.
///
/// Shared by the hunt list and the login screen, which previously disagreed: login
/// used `localizedDescription` unconditionally. That matters because `APIError` and
/// `SessionExpiredError` conform to `CustomStringConvertible`, NOT `LocalizedError` —
/// so `localizedDescription` on them does not reach `description`. It bridges through
/// NSError and yields "The operation couldn't be completed…", silently discarding the
/// endpoint and server message those types exist to carry.
///
/// `URLError` is the opposite case: no useful `description`, but a good localized one.
func userFacingMessage(for error: any Error) -> String {
    if let api = error as? APIError { return api.description }
    if let expired = error as? SessionExpiredError { return expired.description }
    return error.localizedDescription
}

// MARK: - Formatting

/// `fmtTime` from the prototype: `1h 05m`, `41m`, `3d`. Anything under a minute renders as "—"
/// at the call site, exactly as `elapsed` does there.
func formatElapsed(_ seconds: Int) -> String {
    guard seconds >= 60 else { return "—" }
    let hours = seconds / 3600
    let minutes = Int((Double(seconds % 3600) / 60).rounded())
    if hours >= 24 { return "\(Int((Double(hours) / 24).rounded()))d" }
    if hours >= 1 { return String(format: "%dh %02dm", hours, minutes) }
    return "\(max(1, minutes))m"
}

// MARK: - Haptics

/// IOS_HANDOVER.md: "Large primary tap target with haptics — the baseline, and it carries the
/// whole feature." Generators are prepared on first use so the first tap is not the slow one.
@MainActor
enum Haptics {
    #if canImport(UIKit)
    private static let impactLight = UIImpactFeedbackGenerator(style: .light)
    private static let impactRigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notifier = UINotificationFeedbackGenerator()
    #endif

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let generator = style == .light ? impactLight : impactRigid
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        #if canImport(UIKit)
        notifier.prepare()
        notifier.notificationOccurred(type)
        #endif
    }
}
