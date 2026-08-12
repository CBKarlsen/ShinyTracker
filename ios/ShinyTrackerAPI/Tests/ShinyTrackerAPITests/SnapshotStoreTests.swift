import Foundation
import Testing

@testable import ShinyTrackerAPI

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
