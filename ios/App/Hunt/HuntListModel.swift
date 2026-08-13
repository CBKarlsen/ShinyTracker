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
    /// The optimistic count. Diverges from `detail.encounterCount` from the tap until the queued
    /// write behind it is accepted — offline, that can be days.
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

    /// How many *answered* failures a queued write gets before it is given up on. A write the
    /// server keeps refusing for a reason this client cannot classify would otherwise block every
    /// entry behind it forever, and the queue is ordered precisely so nothing overtakes.
    ///
    /// Only a failure the server itself produced spends one of these. A transport failure or an
    /// expired session must never count: being offline is the state this queue exists for, and a
    /// drain fires after every pause in tapping, so counting those would delete an offline
    /// session's encounters within seconds of starting it.
    static let failureLimit = 5

    /// How long after an answered failure the next drain waits. The limit above is meant to be
    /// spent by a server that *keeps* refusing a write, over time — but the drain fires 400 ms
    /// after every pause in tapping, so without this a hunter tapping through one bad minute (a
    /// deploy blip, an exhausted pool, a migration not yet live) spends all five lives in about
    /// three seconds and the session is deleted. This also stops the app hammering a server that
    /// is already failing.
    static let drainCooldown: TimeInterval = 30

    private(set) var state: LoadState = .loading
    private(set) var rows: [HuntRow] = []
    /// The History tab: `status == "completed"`, newest first (`GET /api/hunts` orders by
    /// `created_at DESC`).
    private(set) var history: [HuntRow] = []

    /// The emphasised card. The server has no such flag; the prototype sets `live` on whichever
    /// hunt you last counted (see its `bump()`), so this does the same and seeds it with the
    /// most recent hunt — `GET /api/hunts` orders by `created_at DESC`.
    private(set) var liveHuntID: UUID?

    /// A failure worth telling the user about, surfaced above the list.
    ///
    /// Not set for a write that merely could not be sent yet: that is what the queue is for, and
    /// saying so on every foreground of an offline hunt would be noise. Only a refresh that failed
    /// with nothing cached gets here now — a queued write given up on has its own channel below,
    /// because it does not share this one's lifecycle: `bump` clears `syncError` on every tap
    /// (right, for "couldn't refresh" — the next tap is the retry), which would erase a permanent
    /// failure before the user had a chance to read it.
    private(set) var syncError: String?

    /// One sentence per write the server will never accept, naming the hunt. Deliberately not
    /// folded into `syncError`: that string is for something transient ("couldn't refresh", "try
    /// again") that the UI clears on the next tap or reload, and a permanent failure needs the
    /// opposite — it says so in the danger colour and stays said until the user dismisses it,
    /// because the encounters really are gone and no retry is coming.
    private(set) var failedWrites: [String] = []

    /// Per-hunt ×N step. Lives here, not in ``HuntRow``, so it survives a reload of the list.
    private var stepByHunt: [UUID: Int] = [:]

    private let client: APIClient
    private let store: SnapshotStore
    /// Everything this client owes the server. Counting no longer needs a connection: a tap lands
    /// here and on disk, and ``drain()`` sends it whenever there is a network. All the rules about
    /// what may merge into what live in ``WriteQueue``, where they are tested — nothing in this
    /// file may re-decide them.
    private var queue = WriteQueue()
    private var queueRestored = false
    /// Debounces the drain. Not for coalescing — ``WriteQueue/enqueue(_:for:)`` already does that
    /// — only so a burst of taps does not launch a burst of requests.
    private var drainTask: Task<Void, Never>?
    /// Reentrancy guard for ``drain()``. Two drains over one ordered queue would send the same
    /// entry twice and, worse, let the second overtake the first.
    private var draining = false
    /// When the next drain may run. Set only by an answered failure — see ``drainCooldown``.
    /// Memory-only on purpose: a relaunch is not the tap-burst this protects against, and at worst
    /// costs the entry one life.
    private var nextDrainNotBefore: Date?
    /// Client-owned elapsed time per hunt (D1). Restored from the store once per launch, then
    /// written back beside the queue on every tap: the two are halves of one action, and a clock
    /// that reached disk later than the count it belongs to would survive a kill without it.
    private var clocks: [UUID: HuntClock] = [:]
    private var clocksRestored = false
    /// Hunts whose count on screen is a number the server has confirmed this launch.
    ///
    /// The snapshot is stale by every tap of the previous session by construction — `.hunts` is
    /// written only by `load`, never by a drain — so a restored 2,500 can sit in front of a server
    /// total of 2,847 indefinitely when the refresh behind it fails. `allow_decrease` on an
    /// absolute count from that state does not remove one encounter, it removes 348.
    ///
    /// Per row, not one flag for the session, because provenance genuinely is per row: `load`'s
    /// carve-out keeps the local count for any hunt with a queued write, so a refresh can make
    /// every other row server-backed while that one still holds the snapshot's number. Membership
    /// is only ever added within a launch (and dropped with the hunt), so the press-time and
    /// send-time checks cannot disagree in the direction that loses data.
    private var serverBacked: Set<UUID> = []

    init(client: APIClient, store: SnapshotStore) {
        self.client = client
        self.store = store
    }

    func step(for id: UUID) -> Int { stepByHunt[id] ?? 1 }

    /// Whether this hunt has a write sitting in the queue. The UI's cue that counting happened —
    /// not that anything is wrong: the count and the buttons already read correctly regardless,
    /// so this exists only to acknowledge the queue, not to gate on it.
    func hasPendingWrites(_ id: UUID) -> Bool { huntsOwedWrites.contains(id) }

    /// Clears the permanent-failure banner. Nothing to undo server-side — those writes are already
    /// gone from the queue — this only stops telling the user about it.
    func dismissFailedWrites() { failedWrites = [] }

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
            // Merged, not assigned, for exactly the reason `restoreQueue` merges: the flag is set
            // before the read, so a tap landing during it writes a clock this line would otherwise
            // overwrite with the file. Where both sides have one the in-memory clock wins — it
            // banked a gap this launch, so it is the newer of the two.
            let restored = await store.load([UUID: HuntClock].self, as: .clocks) ?? [:]
            clocks = restored.merging(clocks) { _, live in live }
        }
        await restoreQueue()
        // Draw last-known data immediately rather than a spinner. The refresh below always runs,
        // so this is never shown without being corrected in the same breath — the trade is that a
        // cold launch briefly shows stale data, which is what "opens instantly" costs.
        if !quiet, state != .ready, let cached: [HuntDetail] = await store.load([HuntDetail].self, as: .hunts) {
            // A hunt whose completion is still queued is finished as far as this device is
            // concerned, snapshot or not — it was marked found offline and the snapshot predates
            // that. Showing it back in Active would read as the completion having been undone.
            let completing = huntsCompleting
            // Snapshot count **plus what is still queued**. `.hunts` is written only by a
            // successful `load`, so by construction it predates every queued tap: shown raw, the
            // cold launch after an offline session displays the count from *before* the session —
            // on the one path this whole feature exists for, and offline it never corrects. A
            // hunt found offline would sit in History showing 12 for a shiny caught at 3,412.
            rows = cached.filter { $0.status == "active" && !completing.contains($0.id) }
                .map { HuntRow(detail: $0, count: restoredCount(for: $0)) }
            history = cached.filter { $0.status == "completed" || completing.contains($0.id) }
                .map { HuntRow(detail: $0, count: restoredCount(for: $0)) }
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
            // A burst of taps the server has not accepted yet is newer than anything this response
            // can contain, so it survives the reload. Without this, pull-to-refresh — or the
            // refresh that follows starting or completing another hunt — silently rolls those
            // taps back. The queue is the unsent set: an entry exists exactly while the server is
            // behind this screen, and is removed the moment the write is confirmed.
            //
            // ponytail: local wins while unflushed, which is wrong only in the multi-device case
            // (a second device's higher count would lose). Real reconciliation is the offline
            // sync layer's job — see DECISIONS.md D1 on the monotonic counter.
            // Which count each row shows, and whether it counts as confirmed, are one decision —
            // `HuntCountPolicy.rebuild`, in ShinyTrackerKit, where it is tested. They were two
            // expressions reading the same state, and a review found the pairing they can produce
            // (a count this client never confirmed, marked confirmed) is exactly what arms a
            // destructive "−". Returning both together makes them impossible to disagree.
            let unsent = huntsOwedWrites
            let completing = huntsCompleting
            let current = rows + history
            var backed = serverBacked
            rows = all.filter { $0.status == "active" && !completing.contains($0.id) }.map { detail in
                let decision = HuntCountPolicy.rebuild(
                    response: detail.encounterCount,
                    onScreen: current.first(where: { $0.id == detail.id })?.count,
                    hasUnflushedBurst: unsent.contains(detail.id),
                    isServerBacked: backed.contains(detail.id)
                )
                if decision.isServerBacked { backed.insert(detail.id) }
                return HuntRow(detail: detail, count: decision.count)
            }
            serverBacked = backed
            // A hunt completed on this device but not yet on the server comes back from `GET
            // /api/hunts` as active. It belongs in History until the queued completion lands, or
            // every refresh in between would resurrect a hunt the user has already finished — and
            // with the on-screen count, which is ahead of the response by whatever is still queued.
            history = all.filter { $0.status == "completed" || completing.contains($0.id) }
                .map { detail in
                    // Only the hunts completing offline get the local count. A hunt the server
                    // already calls completed takes the response verbatim: reconciling it too
                    // would hold a number this client never confirmed above one the server did —
                    // `LogPhaseHandler` resets counts, and another device can lower one — which is
                    // exactly the pairing `rebuild`'s `isServerBacked` gate exists to prevent, and
                    // here there would be no gate at all.
                    guard completing.contains(detail.id) else {
                        return HuntRow(detail: detail, count: detail.encounterCount)
                    }
                    return HuntRow(
                        detail: detail,
                        count: HuntCountPolicy.reconciled(
                            local: current.first(where: { $0.id == detail.id })?.count ?? 0,
                            stored: detail.encounterCount))
                }
            if liveHuntID == nil || !rows.contains(where: { $0.id == liveHuntID }) {
                liveHuntID = rows.first?.id
            }
            state = .ready
            // The raw response, not `rows`/`history`: those are derived on the way back in, and a
            // second saved copy of the same thing is a second thing to keep in sync.
            await store.save(all, as: .hunts)
            // The network just answered, which is the only evidence this app collects that a drain
            // is worth attempting. Cheap when the queue is empty, and it means the writes of an
            // offline session go out on the same pull-to-refresh that reveals it is over.
            await drain()
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
        // `after - before`, not `delta`: the clamp at 0 above can shrink it, and the server has to
        // move by what the screen moved by. Coalescing a burst into one request is the queue's
        // decision, not this one's.
        queue.enqueue(.count(delta: after - before), for: id)
        Haptics.impact(delta > 0 ? .light : .rigid)
        // On disk before anything else can happen to it. A tap that only exists in memory is a tap
        // the next crash eats, and this is the app's one job.
        Task { await persist() }
        scheduleDrain()
    }

    /// Sends the queue shortly after the taps stop.
    ///
    /// Counting is rapid-fire — a hunter taps hundreds of times — and a request per tap would both
    /// flood the API and race. The queue already merges those taps into one entry, so this timer
    /// exists only to pick a moment to send, and losing it to a cancel costs nothing: the entry
    /// stays queued and the next tap, foreground or refresh sends it.
    private func scheduleDrain() {
        drainTask?.cancel()
        drainTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.drain()
        }
    }

    /// Sends queued writes in order, stopping at the first that cannot be sent — order matters
    /// (a completion must follow the counts it completes), so a failure must not let later
    /// entries overtake it.
    func drain() async {
        // `load` calls this, and a completion landing here calls `refresh`. The guard is what makes
        // that safe, and it is also what stops a foreground drain racing the debounced one.
        guard !draining else { return }
        // Backing off after an answered failure. Without it the 400 ms debounce turns one bad
        // minute into five failed drains in about three seconds, and the fifth deletes the entry.
        if let notBefore = nextDrainNotBefore, Date() < notBefore { return }
        draining = true
        defer { draining = false }
        await restoreQueue()

        var completedAny = false
        // Held until the end rather than appended to `failedWrites` as it happens: the whole drain
        // finishes in one pass, so there is no reason for the banner to trickle in one hunt at a
        // time when it can just gain the whole batch at once.
        var dropped: [String] = []
        while let entry = queue.next {
            if entry.failures >= Self.failureLimit {
                // Never silently: the user counted these encounters and is entitled to know they
                // did not reach the server, even though nothing can be done about it now.
                dropped.append(await dropPermanently(entry))
                continue
            }
            // Marked and persisted BEFORE the request goes out. `attempted` means "may have reached
            // the server", not "was sent": a request can apply server-side with its response lost,
            // and an entry that survives a crash still looking unsent would be merged into by the
            // next tap — the server's dedupe would then swallow that tap's encounters, because as
            // far as it is concerned this id already landed. Over-marking wastes one queue entry;
            // under-marking loses counts.
            queue.markAttempted(entry.id)
            await persist()
            do {
                let saved = try await client.updateHunt(huntID: entry.huntID, request(for: entry))
                queue.remove(entry.id)
                await persist()
                if case .found = entry.kind {
                    completedAny = true
                    await retireClock(entry.huntID)
                } else if let index = rows.firstIndex(where: { $0.id == entry.huntID }) {
                    // `saved.encounterCount` is the server's total after **this entry only**;
                    // everything still queued behind it is work the server has not been told
                    // about, so the number the screen should agree with is that total plus the
                    // remainder. Reconciling against the response alone makes `max` pick the wrong
                    // side whenever the remainder is negative — a "+5" landing while a "−3" is
                    // still queued would push the screen 3 *up*, and `serverBacked` would then
                    // defend that lie for the rest of the launch. Read after `remove`, so this
                    // entry's own delta is no longer in it.
                    rows[index].count = HuntCountPolicy.reconciled(
                        local: rows[index].count,
                        stored: saved.encounterCount + queue.pendingDelta(for: entry.huntID))
                    // The server has now confirmed a number for this row, so a later response that
                    // is lower than what is on screen can be recognised as stale.
                    serverBacked.insert(entry.huntID)
                }
            } catch {
                guard isRetryable(error) else {
                    // Retrying this forever would wedge every entry behind it, and the queue is
                    // ordered so that nothing overtakes.
                    dropped.append(await dropPermanently(entry))
                    continue
                }
                // A life is spent only on a failure the server answered. `APIError` is exactly
                // that set — a 5xx, a 429, or a response that would not decode. A `URLError` or an
                // expired session never counts: a drain fires after every pause in tapping, so
                // counting those would burn all five lives within seconds of a plane taking off
                // and delete the very encounters this queue exists to keep.
                if error is APIError {
                    queue.markFailed(entry.id)
                    // …and the next drain waits, so a burst of taps cannot spend the rest of the
                    // lives in the seconds it takes to make them.
                    nextDrainNotBefore = Date().addingTimeInterval(Self.drainCooldown)
                }
                await persist()
                // Deliberately silent. Being offline is the normal state this whole queue exists
                // for, and the counts are safe on disk — there is nothing for the user to do and
                // nothing worth interrupting a hunt to say.
                break
            }
        }
        // The completed hunt's final elapsed time is derived server-side from that very PATCH, and
        // the response is a `Hunt` (no `total_time_seconds`), so History can only show the right
        // number after a re-read.
        if completedAny { await refresh() }
        // Appended, not assigned: a hunt given up on in an earlier drain this session must not be
        // forgotten because a later, unrelated drain also had a drop.
        failedWrites += dropped
    }

    /// Gives up on an entry, takes its effect back off the screen, and says what was lost.
    ///
    /// Removing it from the queue is not enough on its own. Its delta is already on the row, and
    /// nothing else ever subtracts it — so the screen would keep encounters the server will never
    /// have, and `serverBacked` would refuse to correct them for the rest of the launch.
    ///
    /// The sentence is chosen on the kind, because a dropped completion did not fail to save a
    /// *count*: the hunt is about to come back out of History and into Active on the next refresh
    /// (`huntsCompleting` no longer holds it), and being told its count went missing would not
    /// explain that at all.
    private func dropPermanently(_ entry: PendingWrite) async -> String {
        queue.remove(entry.id)
        await persist()
        let name = name(of: entry.huntID)
        guard case .count(let delta) = entry.kind else {
            return "\(name) couldn't be marked found. It's still an active hunt."
        }
        if let index = rows.firstIndex(where: { $0.id == entry.huntID }) {
            rows[index].count = max(0, rows[index].count - delta)
        } else if let index = history.firstIndex(where: { $0.id == entry.huntID }) {
            // A count for a hunt already completed on this device: its row lives in History until
            // the completion behind it lands.
            history[index].count = max(0, history[index].count - delta)
        }
        return "\(name)'s count couldn't be saved and will not be retried."
    }

    /// One entry as a request. Count writes carry no `status`: the server's `COALESCE` then leaves
    /// the lifecycle column alone, so a count queued before another device completed the hunt
    /// cannot reopen it.
    private func request(for entry: PendingWrite) -> UpdateHuntRequest {
        // The clock rides along with every write for the same reason the old absolute PATCH sent
        // it: the server cannot see an offline session, and `calc.DecideTotalTime` keeps the max,
        // so sending it repeatedly is idempotent.
        let seconds = clocks[entry.huntID]?.totalSeconds
        switch entry.kind {
        case .count(let delta):
            return UpdateHuntRequest(
                encounterDelta: delta, writeID: entry.id, totalTimeSeconds: seconds)
        case .found:
            // Delta 0: a completion carries no encounters of its own — the counts it completes are
            // their own entries, ahead of it in the queue. It still needs the delta path, because
            // that is where `write_id` lives, and the dedupe is what makes a retried completion
            // safe when the first response was lost.
            return UpdateHuntRequest(
                status: .completed, encounterDelta: 0, writeID: entry.id, totalTimeSeconds: seconds)
        }
    }

    /// Whether a failed send is worth queueing again.
    ///
    /// The default is yes, and deliberately so: transport failures and an expired session both land
    /// here, and both are conditions that pass. Only a server verdict this client cannot change is
    /// treated as final — retrying that forever would be a queue that never empties.
    private func isRetryable(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return true }
        switch api {
        case .http(let status, _, _):
            return status >= 500 || status == 408 || status == 429
        case .decoding:
            // The write very likely landed; only the response failed to parse. The write id makes
            // a retry a no-op server-side, so retrying is the safe side of that uncertainty.
            return true
        }
    }

    /// Reads the queue back, once per launch.
    ///
    /// Nothing should be able to enqueue before this: `bump` and `markFound` both need a row, rows
    /// only exist after `load`, and `load` restores here before it publishes any. So this never
    /// has to merge disk into memory — which is as well, since merging two queues is exactly the
    /// kind of decision that does not belong in this file.
    ///
    /// The `prepend` is not that argument repeated, it is the cost of being wrong about it. The
    /// flag is set before the read so two callers cannot both restore, which leaves a window where
    /// a tap can enqueue while the file is being read — `load` has no reentrancy guard, so a second
    /// load can publish rows from the cache and take a tap while the first is still in that await.
    /// Merging keeps both, oldest first; choosing a side would throw away either the tap or the
    /// whole previous session's queue. See `WriteQueue.prepend`.
    private func restoreQueue() async {
        guard !queueRestored else { return }
        queueRestored = true
        queue.prepend(await store.load(WriteQueue.self, as: .pendingWrites) ?? WriteQueue())
    }

    /// Queue and clocks together. They are two halves of one tap — encounters and the time they
    /// took — and a kill between the two writes would leave a hunt crediting one without the other.
    private func persist() async {
        await store.save(queue, as: .pendingWrites)
        await store.save(clocks, as: .clocks)
    }

    /// Names a hunt in a failure message. Falls back because a completion's row has already left
    /// the Active list by the time its write can be given up on.
    private func name(of huntID: UUID) -> String {
        (rows + history).first { $0.id == huntID }?.name ?? "that hunt"
    }

    // MARK: Found and abandoned

    /// Completes the hunt: it leaves the Active list and appears in History.
    ///
    /// Returns true without waiting for a server. A hunter watching a shiny appear must not be told
    /// to wait for a round trip, and there is nothing left to wait for: the completion is durable
    /// the moment it is queued, and the drain sends it after — never before — the counts it
    /// completes, because the queue is ordered.
    @discardableResult
    func markFound(_ id: UUID) async -> Bool {
        guard let row = rows.first(where: { $0.id == id }) else { return false }
        queue.enqueue(.found, for: id)
        // Straight into History rather than nowhere. `load` keeps it there for as long as the
        // completion is queued, so a refresh in between cannot resurrect a finished hunt.
        history.insert(row, at: 0)
        drop(id)
        // The clock is deliberately not retired here: the queued completion still has to report
        // how long the hunt took. `drain` retires it once the server has that number.
        await persist()
        Haptics.notify(.success)
        scheduleDrain()
        return true
    }

    /// Deletes the hunt outright — no History row, nothing registered. There is no undo: the
    /// server has no soft delete, so the sheet arms this behind a second tap.
    ///
    /// Still online-only, unlike counting. A delete is not a count: there is nothing to lose by
    /// refusing it offline, and everything to explain if a hunt vanished locally and came back.
    @discardableResult
    func abandon(_ id: UUID) async -> Bool {
        do {
            try await client.deleteHunt(huntID: id)
            // Whatever this hunt still owes has nowhere to land now — the row is gone server-side,
            // so every one of those writes would 404 and be reported as a failure the user did not
            // cause and cannot act on.
            for entry in queue.entries where entry.huntID == id { queue.remove(entry.id) }
            drop(id)
            await retireClock(id)
            Haptics.notify(.warning)
            return true
        } catch {
            syncError = "Couldn't abandon that hunt. \(message(for: error))"
            return false
        }
    }

    /// Takes the hunt off the Active list. The clock stays: a completion can still be queued behind
    /// this, and it has to report how long the hunt took. ``retireClock(_:)`` is where it dies.
    private func drop(_ id: UUID) {
        rows.removeAll { $0.id == id }
        if liveHuntID == id { liveHuntID = rows.first?.id }
        // The only removal from `serverBacked`: the hunt itself is gone, so nothing can be pressed
        // against a stale copy of it. Anything less than that and the set could shrink under a row
        // still on screen, which is how the press-time and send-time gates would come to disagree.
        serverBacked.remove(id)
    }

    /// The hunt is finished or gone and the server knows it, so its clock is dead weight that would
    /// otherwise be restored on every launch for the rest of the account's life.
    private func retireClock(_ id: UUID) async {
        clocks[id] = nil
        await persist()
    }

    /// A cached hunt's count as it should appear now: the snapshot, plus every queued delta the
    /// server has not been told about. The sum lives in ``WriteQueue/pendingDelta(for:)``, where
    /// it is tested.
    private func restoredCount(for detail: HuntDetail) -> Int {
        max(0, detail.encounterCount + queue.pendingDelta(for: detail.id))
    }

    /// Hunts the queue still owes a write for. Their on-screen count is newer than any response
    /// can be, by construction: the server has not been told about those taps yet.
    private var huntsOwedWrites: Set<UUID> { Set(queue.entries.map(\.huntID)) }

    /// Hunts completed on this device but not yet on the server. They read as active in every
    /// response until the queued completion lands.
    private var huntsCompleting: Set<UUID> {
        Set(queue.entries.filter { $0.kind == .found }.map(\.huntID))
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
