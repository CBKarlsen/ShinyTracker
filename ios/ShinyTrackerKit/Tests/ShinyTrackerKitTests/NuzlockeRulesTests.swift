import Testing

@testable import ShinyTrackerKit

/// The real seeded head of Platinum's checkpoint list, `backend/seeds/nuzlocke_platinum.json`
/// in `sort_order`. The three descents in here are the whole reason ``NuzlockeRules/levelCap``
/// exists, so the fixture is the actual data rather than an invented sequence.
private let platinum: [NuzlockeRules.Checkpoint] = [
    .init(slug: "rival1", levelCap: 5),
    .init(slug: "rival2", levelCap: 9),
    .init(slug: "gym1", levelCap: 14),
    .init(slug: "galactic-windworks", levelCap: 17),
    .init(slug: "gym2", levelCap: 22),
    .init(slug: "galactic-eterna", levelCap: 23),
    .init(slug: "gym3", levelCap: 26),
    .init(slug: "rival3", levelCap: 27),
    .init(slug: "gym4", levelCap: 32),
    .init(slug: "rival4", levelCap: 36),
    .init(slug: "gym5", levelCap: 37),
    .init(slug: "cyrus1", levelCap: 36),   // <- descends
    .init(slug: "rival5", levelCap: 38),
    .init(slug: "gym6", levelCap: 41),
    .init(slug: "galactic-valor", levelCap: 40),   // <- descends
]

/// Beats every checkpoint up to and including `slug`.
private func beaten(through slug: String) -> Set<String> {
    guard let end = platinum.firstIndex(where: { $0.slug == slug }) else { return [] }
    return Set(platinum[...end].map(\.slug))
}

// MARK: - The bug this exists to prevent

/// Gym 5 caps at 37, and the next checkpoint — Cyrus at Celestic — caps at 36. Reading the next
/// checkpoint's cap directly told the player to go *down* a level after beating a gym.
@Test func beatingAGymNeverLowersTheCap() {
    let cap = NuzlockeRules.levelCap(checkpoints: platinum, beaten: beaten(through: "gym5"))
    #expect(cap == 37)
}

/// The same descent again after Byron (41 -> Saturn at Valor Cavern, 40), to prove the first case
/// is the rule and not a one-off.
@Test func theRatchetHoldsAcrossEveryDescent() {
    let cap = NuzlockeRules.levelCap(checkpoints: platinum, beaten: beaten(through: "gym6"))
    #expect(cap == 41)
}

// MARK: - Ordinary progress

@Test func aFreshRunCapsAtTheFirstCheckpoint() {
    #expect(NuzlockeRules.levelCap(checkpoints: platinum, beaten: []) == 5)
}

/// While the caps are still ascending the ratchet must be invisible — it is the next
/// checkpoint's cap, exactly as before.
@Test func anAscendingRunReadsAsTheNextCheckpoint() {
    #expect(NuzlockeRules.levelCap(checkpoints: platinum, beaten: beaten(through: "gym1")) == 17)
    #expect(NuzlockeRules.levelCap(checkpoints: platinum, beaten: beaten(through: "gym3")) == 27)
}

/// Checkpoints are beaten out of order — the API sends a set, not a sequence, and nothing stops a
/// player ticking a later boss first. The cap still comes from the first *unbeaten* one.
@Test func anOutOfOrderTickDoesNotSkipTheRatchet() {
    let cap = NuzlockeRules.levelCap(checkpoints: platinum, beaten: ["gym4"])
    #expect(cap == 5)
}

// MARK: - Edges

@Test func everyCheckpointBeatenHasNoCap() {
    let all = Set(platinum.map(\.slug))
    #expect(NuzlockeRules.levelCap(checkpoints: platinum, beaten: all) == nil)
}

@Test func anEmptyTimelineHasNoCap() {
    #expect(NuzlockeRules.levelCap(checkpoints: [], beaten: []) == nil)
}

/// `level_cap` is nullable, so a run whose early bosses carry no cap must not report 0 — it has
/// no cap to report until one appears.
@Test func missingCapsAreAbsentNotZero() {
    let sparse: [NuzlockeRules.Checkpoint] = [
        .init(slug: "a", levelCap: nil),
        .init(slug: "b", levelCap: nil),
        .init(slug: "c", levelCap: 20),
    ]
    #expect(NuzlockeRules.levelCap(checkpoints: sparse, beaten: []) == nil)
    #expect(NuzlockeRules.levelCap(checkpoints: sparse, beaten: ["a", "b"]) == 20)
}

/// A nil cap after a real one must not erase it: the ratchet is over everything seen so far.
@Test func aNilCapDoesNotClearTheRatchet() {
    let sparse: [NuzlockeRules.Checkpoint] = [
        .init(slug: "a", levelCap: 30),
        .init(slug: "b", levelCap: nil),
    ]
    #expect(NuzlockeRules.levelCap(checkpoints: sparse, beaten: ["a"]) == 30)
}
