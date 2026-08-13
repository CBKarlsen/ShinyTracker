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
