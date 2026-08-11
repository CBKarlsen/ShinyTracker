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
    /// Debounced writers, one per hunt. See ``scheduleSync(_:)``.
    private var pendingWrites: [UUID: Task<Void, Never>] = [:]
    /// The count each hunt had before its current burst of taps — the rollback target.
    private var preBurstCount: [UUID: Int] = [:]

    init(client: APIClient) { self.client = client }

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

    private func load(quiet: Bool) async {
        if !quiet { state = .loading }
        syncError = nil
        do {
            // `status` is a free-form String on purpose (Models.swift), so both tabs are filled
            // by filtering one response rather than trusting the server to send one kind.
            let all = try await client.hunts()
            // A burst of taps that has not been flushed yet is newer than anything this response
            // can contain, so it survives the reload. Without this, pull-to-refresh — or the
            // refresh that follows starting or completing another hunt — silently rolls those
            // taps back. `preBurstCount` is the unflushed set: `flush` clears it either way.
            //
            // ponytail: local wins while unflushed, which is wrong only in the multi-device case
            // (a second device's higher count would lose). Real reconciliation is the offline
            // sync layer's job — see DECISIONS.md D1 on the monotonic counter.
            let unflushed = preBurstCount
            let current = rows
            rows = all.filter { $0.status == "active" }.map { detail in
                let local = unflushed[detail.id] != nil
                    ? current.first(where: { $0.id == detail.id })?.count : nil
                return HuntRow(detail: detail, count: local ?? detail.encounterCount)
            }
            history = all.filter { $0.status == "completed" }
                .map { HuntRow(detail: $0, count: $0.encounterCount) }
            if liveHuntID == nil || !rows.contains(where: { $0.id == liveHuntID }) {
                liveHuntID = rows.first?.id
            }
            state = .ready
        } catch {
            if quiet {
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
        Haptics.impact(delta > 0 ? .light : .rigid)
        scheduleSync(id, rollbackTo: before)
    }

    /// Coalesces a burst of taps into one PATCH.
    ///
    /// Counting is a rapid-fire interaction — a hunter taps hundreds of times — and firing one
    /// request per tap both floods the API and races: two in-flight PATCHes can land out of
    /// order and write a stale count. Debouncing removes the race entirely instead of managing
    /// it, and the value sent is always the current one.
    private func scheduleSync(_ id: UUID, rollbackTo: Int) {
        if preBurstCount[id] == nil { preBurstCount[id] = rollbackTo }
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
        do {
            // `totalTimeSeconds` is deliberately omitted: supplying it latches the hunt to
            // client-owned time (DECISIONS.md D1) and there is no client timer yet, so this
            // screen must not claim authority over it.
            _ = try await client.updateHunt(
                huntID: id,
                UpdateHuntRequest(encounterCount: row.count, status: .active)
            )
            preBurstCount[id] = nil
        } catch {
            if let rollback, let index = rows.firstIndex(where: { $0.id == id }) {
                rows[index].count = rollback
            }
            preBurstCount[id] = nil
            syncError = "Couldn't save that count. \(message(for: error))"
        }
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
            // `totalTimeSeconds` stays omitted here for the same reason as in `flush` — see D1.
            _ = try await client.updateHunt(
                huntID: id,
                UpdateHuntRequest(encounterCount: row.count, status: .completed)
            )
            drop(id)
            Haptics.notify(.success)
            // The completed hunt's final elapsed time is derived server-side from this very
            // PATCH, and the response is a `Hunt` (no `total_time_seconds`), so History can only
            // show the right number after a re-read.
            await refresh()
            return true
        } catch {
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
            drop(id)
            Haptics.notify(.warning)
            return true
        } catch {
            syncError = "Couldn't abandon that hunt. \(message(for: error))"
            return false
        }
    }

    private func drop(_ id: UUID) {
        rows.removeAll { $0.id == id }
        if liveHuntID == id { liveHuntID = rows.first?.id }
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
