import Foundation
import Testing

@testable import ShinyTrackerKit

private let huntA = UUID()
private let huntB = UUID()

/// Five hundred taps must become one request, not five hundred.
@Test func consecutiveCountsForOneHuntMerge() {
    var queue = WriteQueue()
    for _ in 0..<500 { queue.enqueue(.count(delta: 1), for: huntA) }
    #expect(queue.entries.count == 1)
    #expect(queue.entries[0].kind == .count(delta: 500))
}

@Test func upsAndDownsMergeToTheirNet() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 5), for: huntA)
    queue.enqueue(.count(delta: -2), for: huntA)
    #expect(queue.entries[0].kind == .count(delta: 3))
}

/// A net-zero delta is not a write. Sending it would burn an idempotency key to do nothing.
@Test func aNetZeroDeltaDisappears() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 3), for: huntA)
    queue.enqueue(.count(delta: -3), for: huntA)
    #expect(queue.entries.isEmpty)
}

/// THE subtle rule. An attempted entry may already be applied server-side with its response lost,
/// so merging into it would have the dedupe table swallow the new work.
@Test func anAttemptedEntryIsFrozenAndNeverMergedInto() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 10), for: huntA)
    let first = try! #require(queue.next)
    queue.markAttempted(first.id)

    queue.enqueue(.count(delta: 5), for: huntA)
    #expect(queue.entries.count == 2)
    #expect(queue.entries[0].kind == .count(delta: 10))
    #expect(queue.entries[1].kind == .count(delta: 5))
    #expect(queue.entries[1].id != first.id)
}

/// Same rule from the other direction: an attempted entry must not be collapsed away either.
@Test func anAttemptedEntryIsNotRemovedByANetZero() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 3), for: huntA)
    let first = try! #require(queue.next)
    queue.markAttempted(first.id)
    queue.enqueue(.count(delta: -3), for: huntA)
    #expect(queue.entries.count == 2)
}

/// A completion is a barrier: the hunt would otherwise complete at the wrong number.
@Test func aFoundBlocksMergingAcrossIt() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 4), for: huntA)
    queue.enqueue(.found, for: huntA)
    queue.enqueue(.count(delta: 2), for: huntA)
    #expect(queue.entries.count == 3)
    #expect(queue.entries[0].kind == .count(delta: 4))
    #expect(queue.entries[1].kind == .found)
    #expect(queue.entries[2].kind == .count(delta: 2))
}

/// Counts enqueued before a completion must go out before it.
@Test func countsBeforeAFoundDrainFirst() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 4), for: huntA)
    queue.enqueue(.found, for: huntA)
    #expect(queue.next?.kind == .count(delta: 4))
}

/// Two hunts counted alternately must not merge into each other, and each must keep its own order.
@Test func interleavedHuntsKeepPerHuntOrder() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 1), for: huntA)
    queue.enqueue(.count(delta: 1), for: huntB)
    queue.enqueue(.count(delta: 1), for: huntA)
    #expect(queue.entries.count == 3)
    #expect(queue.entries.map(\.huntID) == [huntA, huntB, huntA])
}

/// Draining removes the front, so the next drain sees the next entry.
@Test func removingTheFrontAdvancesTheQueue() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 1), for: huntA)
    queue.enqueue(.found, for: huntA)
    let first = try! #require(queue.next)
    queue.remove(first.id)
    #expect(queue.next?.kind == .found)
}

/// Failures accumulate so a write that can never succeed stops being retried forever.
@Test func failuresAccumulatePerEntry() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 1), for: huntA)
    let first = try! #require(queue.next)
    queue.markFailed(first.id)
    queue.markFailed(first.id)
    #expect(queue.entries[0].failures == 2)
}

/// The queue is persisted between launches, so it has to survive a round trip intact — including
/// the attempted flag, or a resumed launch would merge into an already-sent entry.
@Test func theQueueRoundTripsThroughCodable() throws {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 7), for: huntA)
    let first = try #require(queue.next)
    queue.markAttempted(first.id)
    queue.enqueue(.found, for: huntB)
    let replayed = try JSONDecoder().decode(WriteQueue.self, from: JSONEncoder().encode(queue))
    #expect(replayed == queue)
    #expect(replayed.entries[0].attempted)
}

// MARK: - Regression guards added in review round 1

/// The id is the server's idempotency key, so a merge must keep it. Minting a fresh one would
/// have the server treat the merged write as new and apply the delta a second time.
@Test func mergingKeepsTheEntrysIdentity() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 1), for: huntA)
    let original = queue.entries[0].id
    queue.enqueue(.count(delta: 1), for: huntA)
    #expect(queue.entries[0].id == original)
    #expect(queue.entries[0].kind == .count(delta: 2))
}

/// A failed send is still an attempted one — the request may have reached the server even though
/// the response didn't come back. `markFailed` must not reopen the entry to merging.
@Test func markFailedDoesNotUnfreezeAnAttemptedEntry() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 1), for: huntA)
    let first = try! #require(queue.next)
    queue.markAttempted(first.id)
    queue.markFailed(first.id)
    queue.enqueue(.count(delta: 1), for: huntA)
    #expect(queue.entries.count == 2)
}

/// A drain can race a removal (e.g. a retry timer firing after the entry was already cleared).
/// All three id-addressed mutators must no-op rather than trap or touch the wrong entry.
@Test func mutatorsNoOpOnAnUnknownID() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 1), for: huntA)
    let untouched = queue

    let unknown = UUID()
    queue.markAttempted(unknown)
    queue.markFailed(unknown)
    queue.remove(unknown)
    #expect(queue == untouched)
}

@Test func nextIsNilOnAnEmptyQueue() {
    let queue = WriteQueue()
    #expect(queue.next == nil)
}

/// The barrier cuts both ways: a `.found` must survive sitting behind a count that nets to zero,
/// not just block merging across itself.
@Test func aFoundIsNotRemovedByAFollowingNetZero() {
    var queue = WriteQueue()
    queue.enqueue(.found, for: huntA)
    queue.enqueue(.count(delta: 3), for: huntA)
    queue.enqueue(.count(delta: -3), for: huntA)
    #expect(queue.entries.count == 1)
    #expect(queue.entries[0].kind == .found)
}

/// Restoring from disk races a tap made during the file read. Neither side may be dropped, the
/// disk side is older and so drains first, and the seam must not merge: the disk entry may already
/// have been attempted in the launch that wrote it, in which case merging this launch's count into
/// it would have the server's dedupe swallow those encounters.
@Test func prependKeepsBothSidesInOrderAndDoesNotMergeAcrossTheSeam() {
    var fromDisk = WriteQueue()
    fromDisk.enqueue(.count(delta: 7), for: huntA)
    let older = try! #require(fromDisk.next)
    fromDisk.markAttempted(older.id)

    var live = WriteQueue()
    live.enqueue(.count(delta: 2), for: huntA)

    live.prepend(fromDisk)
    #expect(live.entries.count == 2)
    #expect(live.entries[0].id == older.id)
    #expect(live.entries[0].kind == .count(delta: 7))
    #expect(live.entries[0].attempted)
    #expect(live.entries[1].kind == .count(delta: 2))
}

/// The ordinary case: nothing was tapped during the read, so the queue is simply what was on disk.
@Test func prependOntoAnEmptyQueueIsTheDiskQueue() {
    var fromDisk = WriteQueue()
    fromDisk.enqueue(.count(delta: 4), for: huntA)
    fromDisk.enqueue(.found, for: huntB)

    var live = WriteQueue()
    live.prepend(fromDisk)
    #expect(live == fromDisk)
}
