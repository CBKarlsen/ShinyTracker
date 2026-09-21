import Foundation
import Testing

@testable import ShinyTrackerAPI
import ShinyTrackerKit

/// A throwaway directory per test, so nothing touches the real Application Support.
private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct Fixture: Codable, Equatable {
    let name: String
    let count: Int
    let when: Date
}

private let sample = Fixture(name: "gible", count: 2847, when: Date(timeIntervalSince1970: 1_760_000_000))

@Test func savesAndLoadsARoundTrip() async {
    let user = UUID()
    let store = SnapshotStore(userID: user, containerDirectory: tempDirectory())
    await store.save(sample, as: .hunts)
    #expect(await store.load(Fixture.self, as: .hunts) == sample)
}

@Test func aMissingSnapshotIsNilRatherThanAnError() async {
    let store = SnapshotStore(userID: UUID(), containerDirectory: tempDirectory())
    #expect(await store.load(Fixture.self, as: .games) == nil)
}

/// Corruption must degrade to a cache miss. The worst thing persistence is allowed to cause is
/// the spinner the user would have seen anyway.
@Test func aCorruptFileIsAMissNotACrash() async {
    let dir = tempDirectory()
    let user = UUID()
    let store = SnapshotStore(userID: user, containerDirectory: dir)
    await store.save(sample, as: .hunts)
    let file = dir.appendingPathComponent(user.uuidString.lowercased()).appendingPathComponent("hunts.json")
    try? Data("{ this is not json".utf8).write(to: file)
    #expect(await store.load(Fixture.self, as: .hunts) == nil)
}

@Test func aPayloadOfTheWrongShapeIsAMiss() async {
    let store = SnapshotStore(userID: UUID(), containerDirectory: tempDirectory())
    await store.save(["a", "b"], as: .species)
    #expect(await store.load(Fixture.self, as: .species) == nil)
}

/// The reason snapshots are keyed by user id at all: DexModel's UserDefaults store already
/// documents that an unscoped key shows one account another's data after a sign-out/sign-in.
@Test func twoUsersDoNotSeeEachOthersSnapshots() async {
    let dir = tempDirectory()
    let alice = SnapshotStore(userID: UUID(), containerDirectory: dir)
    let bob = SnapshotStore(userID: UUID(), containerDirectory: dir)
    await alice.save(sample, as: .hunts)
    #expect(await bob.load(Fixture.self, as: .hunts) == nil)
    #expect(await alice.load(Fixture.self, as: .hunts) == sample)
}

@Test func clearRemovesOnlyItsOwnUsersSnapshots() async {
    let dir = tempDirectory()
    let alice = SnapshotStore(userID: UUID(), containerDirectory: dir)
    let bob = SnapshotStore(userID: UUID(), containerDirectory: dir)
    await alice.save(sample, as: .hunts)
    await bob.save(sample, as: .hunts)
    await alice.clear()
    #expect(await alice.load(Fixture.self, as: .hunts) == nil)
    #expect(await bob.load(Fixture.self, as: .hunts) == sample)
}

/// One file per run: a single `run` key would be rewritten every time the user switched runs.
@Test func runKeysAreDistinctPerRun() async {
    let store = SnapshotStore(userID: UUID(), containerDirectory: tempDirectory())
    let first = UUID(), second = UUID()
    await store.save(sample, as: .run(first))
    #expect(await store.load(Fixture.self, as: .run(second)) == nil)
    #expect(await store.load(Fixture.self, as: .run(first)) == sample)
}

/// A store with no user id (the DEBUG preview harnesses) must never write into a real user's
/// directory, or a screenshot run would poison a real account's cache.
@Test func anAnonymousStoreIsIsolatedFromEveryUser() async {
    let dir = tempDirectory()
    let user = UUID()
    let real = SnapshotStore(userID: user, containerDirectory: dir)
    let anonymous = SnapshotStore(userID: nil, containerDirectory: dir)
    await anonymous.save(sample, as: .hunts)
    #expect(await real.load(Fixture.self, as: .hunts) == nil)
}

/// The clocks snapshot is `[UUID: HuntClock]`, and `JSONEncoder` writes a dictionary with
/// non-`String` keys as a flat array of alternating keys and values rather than an object. That is
/// fine — but only because it round-trips, which is what this pins. Accumulated time is the one
/// thing in the store the server cannot rebuild.
@Test func clocksRoundTripDespiteUUIDKeys() async {
    let store = SnapshotStore(userID: UUID(), containerDirectory: tempDirectory())
    var clock = HuntClock(totalSeconds: 900, lastEncounterAt: Date(timeIntervalSince1970: 1_760_000_000))
    // A fractional gap, so the sub-second `carry` is non-zero and has to survive the file too:
    // a carry silently reset to 0 on every relaunch is the rounding drift it exists to prevent.
    clock.record(at: Date(timeIntervalSince1970: 1_760_000_006.6), idleThreshold: 140)
    let clocks = [UUID(): clock, UUID(): HuntClock()]
    await store.save(clocks, as: .clocks)
    #expect(await store.load([UUID: HuntClock].self, as: .clocks) == clocks)
}

/// `mutate` must not lose a write when two callers arrive at once — the durable Lock Screen path
/// appends one encounter per press, each from its own `Task`, and a lost append is an encounter
/// the server never hears about.
///
/// This fails if `mutate` is ever split back into `load` then `save`: those are two awaits on a
/// reentrant actor, so the presses interleave, each appends to the same loaded queue and the last
/// save wins. Measured at 200 presses that loses well over half of them — it is not a rare race.
@Test func concurrentMutatesDoNotLoseAWrite() async {
    let store = SnapshotStore(userID: UUID(), containerDirectory: tempDirectory())
    let hunt = UUID()
    let presses = 200

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<presses {
            group.addTask {
                await store.mutate(WriteQueue.self, as: .pendingWrites, default: WriteQueue()) {
                    $0.enqueue(.count(delta: 1), for: hunt)
                }
            }
        }
    }

    let queue = await store.load(WriteQueue.self, as: .pendingWrites) ?? WriteQueue()
    #expect(queue.projectedCount(from: 0, for: hunt) == presses)
}

/// The control for the test above, and the reason it is written that way: the same 200 presses
/// done as load-then-save from outside the actor lose writes. Kept as a test rather than a comment
/// because a claim about a race that nothing runs is a claim that quietly stops being true.
@Test func loadThenSaveFromOutsideTheActorLosesWrites() async {
    let store = SnapshotStore(userID: UUID(), containerDirectory: tempDirectory())
    let hunt = UUID()
    let presses = 200

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<presses {
            group.addTask {
                var queue = await store.load(WriteQueue.self, as: .pendingWrites) ?? WriteQueue()
                queue.enqueue(.count(delta: 1), for: hunt)
                await store.save(queue, as: .pendingWrites)
            }
        }
    }

    let queue = await store.load(WriteQueue.self, as: .pendingWrites) ?? WriteQueue()
    #expect(queue.projectedCount(from: 0, for: hunt) < presses)
}
