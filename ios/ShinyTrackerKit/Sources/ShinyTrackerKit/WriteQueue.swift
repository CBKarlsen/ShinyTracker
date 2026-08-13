import Foundation

/// One write the client owes the server: a delta to a hunt's encounter count, or a completion.
///
/// `id` is the idempotency key sent with the request. It is minted once, at `enqueue`, and never
/// regenerated — including when a later count merges into this entry — because the server's dedupe
/// table is keyed on it.
public struct PendingWrite: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let huntID: UUID
    public var kind: Kind
    /// Set once this entry has been sent. See `WriteQueue` for why that freezes it.
    public var attempted: Bool
    /// How many times a send has come back as a failure, so a write that can never succeed can
    /// eventually be given up on instead of retried forever.
    public var failures: Int

    public enum Kind: Codable, Equatable, Sendable {
        case count(delta: Int)
        case found
    }
}

/// A durable, ordered queue of writes owed to the server, coalesced so that a burst of taps costs
/// one request instead of one per tap.
///
/// `attempted` is the reason this can't just be "merge whatever's mergeable": a send can succeed on
/// the server and still look like a failure locally (timeout, dropped response, app killed
/// mid-flight). Once an id has gone out, the server may already hold it — merging a later `+5` into
/// that entry and resending it would have the server's dedupe swallow the five silently, because as
/// far as the dedupe table is concerned that id was already applied. So an attempted entry is
/// frozen: nothing merges into it, and nothing coalesces it away. New work after an attempt starts a
/// fresh entry with a fresh id.
public struct WriteQueue: Codable, Equatable, Sendable {
    public private(set) var entries: [PendingWrite]

    public init() {
        entries = []
    }

    /// The entry a drain should send next.
    public var next: PendingWrite? { entries.first }

    /// Adds one write, coalescing it into the queue's tail when that's safe.
    ///
    /// Only a `.count` merges, and only into the *last* entry, and only when that entry is for the
    /// same hunt, is itself a `.count`, and is not `attempted`. `.found` never merges — it isn't a
    /// `.count`, so the same-kind check above already excludes it in both directions, as both the
    /// thing being merged and the thing merged into. That is deliberate: a completion needs no
    /// separate barrier case, because appending after a `.found` fails the "last entry is a .count"
    /// check just as merging *through* one would.
    public mutating func enqueue(_ kind: PendingWrite.Kind, for huntID: UUID) {
        if case .count(let delta) = kind,
            let last = entries.last,
            last.huntID == huntID,
            case .count(let existingDelta) = last.kind,
            !last.attempted
        {
            let merged = existingDelta + delta
            if merged == 0 {
                entries.removeLast()
            } else {
                entries[entries.count - 1].kind = .count(delta: merged)
            }
            return
        }

        entries.append(
            PendingWrite(id: UUID(), huntID: huntID, kind: kind, attempted: false, failures: 0))
    }

    /// How far ahead of the server this hunt's screen count is: the sum of every queued delta for
    /// it.
    ///
    /// The server's stored count only ever reflects the writes it has actually seen, so it is the
    /// right number for a row only once this is added back. Both places that need it are places
    /// where a count is taken from the server or from a snapshot — a drain's response, which is
    /// blind to everything queued behind the entry that produced it, and a cached restore, whose
    /// snapshot predates every queued tap by construction.
    ///
    /// A `.found` contributes nothing: a completion carries no encounters of its own.
    public func pendingDelta(for huntID: UUID) -> Int {
        entries.reduce(0) { total, entry in
            guard entry.huntID == huntID, case .count(let delta) = entry.kind else { return total }
            return total + delta
        }
    }

    /// Puts an older queue in front of this one.
    ///
    /// Restoring from disk races a tap that lands during the file read: the read is an `await`, and
    /// the queue can be enqueued into while it is in flight. Choosing a side loses data either way
    /// — discarding the file throws away a whole previous session, discarding the tap throws away
    /// the tap — so both are kept, and the disk entries go first because they were enqueued in an
    /// earlier launch and the queue's whole guarantee is that it drains in order.
    ///
    /// Nothing merges across the seam, deliberately: an entry restored from disk may already have
    /// been attempted in the launch that wrote it, and merging this launch's work into it would
    /// have the server's dedupe swallow that work. Same rule as `enqueue`, same reason.
    public mutating func prepend(_ older: WriteQueue) {
        entries.insert(contentsOf: older.entries, at: 0)
    }

    /// Marks an entry as (maybe) sent, freezing it against future merges and coalescing. Call this
    /// *before* the request goes out, not after it returns: `attempted` means "may have reached the
    /// server", not "was sent". A drain that waits until after a successful response to mark this
    /// leaves the entry mergeable for the whole flight, so a delta tapped mid-request merges into
    /// the id already in transit — the server's dedupe then swallows it. Marking early can waste at
    /// most one queue entry (on a request that turns out to have failed outright); marking late can
    /// lose real counts. Addressed by `id`, not index — the request is awaited after this call, and
    /// the queue can change underneath it during that await.
    public mutating func markAttempted(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].attempted = true
    }

    /// Records a failed send. Addressed by `id` for the same reason as `markAttempted`.
    public mutating func markFailed(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].failures += 1
    }

    /// Drops an entry once its write is confirmed durable server-side. Addressed by `id` for the
    /// same reason as `markAttempted`.
    public mutating func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
    }
}
