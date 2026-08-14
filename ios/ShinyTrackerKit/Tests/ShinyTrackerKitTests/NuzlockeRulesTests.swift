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

// MARK: - Chapters

/// A miniature of Platinum's real shape: routes, a rival and a Galactic fight between gyms, and
/// the League as a run of bosses with no routes among them.
private let shape: [NuzlockeRules.Row] = [
    .init(slug: "r201", isBoss: false, isGym: false, place: nil),
    .init(slug: "rival1", isBoss: true, isGym: false, place: "Route 201"),
    .init(slug: "r203", isBoss: false, isGym: false, place: nil),
    .init(slug: "mine", isBoss: false, isGym: false, place: nil),
    .init(slug: "gym1", isBoss: true, isGym: true, place: "Oreburgh Gym"),
    .init(slug: "r205", isBoss: false, isGym: false, place: nil),
    .init(slug: "wind", isBoss: false, isGym: false, place: nil),
    .init(slug: "galactic-windworks", isBoss: true, isGym: false, place: "Valley Windworks"),
    .init(slug: "gym2", isBoss: true, isGym: true, place: "Eterna Gym"),
    .init(slug: "e4-aaron", isBoss: true, isGym: false, place: "Pokémon League"),
    .init(slug: "champion", isBoss: true, isGym: false, place: "Pokémon League"),
]

@Test func chaptersBreakAfterGymsNotAfterEveryBoss() {
    let chapters = NuzlockeRules.chapters(shape)
    #expect(chapters.map(\.id) == ["gym1", "gym2", "champion"])
    // The rival and the Galactic fight are rows inside a chapter, not chapters of their own.
    #expect(chapters[0].rows.map(\.slug) == ["r201", "rival1", "r203", "mine", "gym1"])
    #expect(chapters[1].rows.map(\.slug) == ["r205", "wind", "galactic-windworks", "gym2"])
}

/// The Elite Four and the Champion are one chapter. Five separate ones would misrepresent the
/// only stretch of a run you cannot leave partway through.
@Test func theLeagueIsOneChapter() {
    let chapters = NuzlockeRules.chapters(shape)
    #expect(chapters.last?.rows.map(\.slug) == ["e4-aaron", "champion"])
    #expect(chapters.last?.title == "Pokémon League")
}

@Test func gymChaptersAreNamedForTheirTownNotTheirGym() {
    #expect(NuzlockeRules.chapters(shape).map(\.title) == ["Oreburgh", "Eterna", "Pokémon League"])
}

@Test func anEmptyTimelineHasNoChapters() {
    #expect(NuzlockeRules.chapters([]).isEmpty)
}

// MARK: - Which chapter is open

@Test func theOpenChapterHoldsTheFirstUnbeatenBoss() {
    let chapters = NuzlockeRules.chapters(shape)
    #expect(NuzlockeRules.openChapterID(chapters, beaten: []) == "gym1")
    #expect(NuzlockeRules.openChapterID(chapters, beaten: ["rival1", "gym1"]) == "gym2")
}

/// The reason the open chapter is derived from bosses and not from the first unlogged route:
/// Valley Windworks needs a Friday *and* a beaten Mars, so a player routinely walks past it. If
/// an unlogged route drove this, the run would stay pinned to chapter 2 forever.
@Test func aSkippedRouteDoesNotPinTheOpenChapter() {
    let chapters = NuzlockeRules.chapters(shape)
    let beaten: Set<String> = ["rival1", "gym1", "galactic-windworks", "gym2"]
    // "wind" is deliberately never logged.
    #expect(NuzlockeRules.openChapterID(chapters, beaten: beaten) == "champion")
}

@Test func aFinishedRunHasNoOpenChapter() {
    let chapters = NuzlockeRules.chapters(shape)
    let all = Set(shape.filter(\.isBoss).map(\.slug))
    #expect(NuzlockeRules.openChapterID(chapters, beaten: all) == nil)
}

// MARK: - Resolution, the collapse trigger

@Test func aChapterWithEveryBossBeatenAndEveryRouteLoggedIsResolved() {
    let first = NuzlockeRules.chapters(shape)[0]
    #expect(
        NuzlockeRules.isResolved(
            first, beaten: ["rival1", "gym1"], logged: ["r201", "r203", "mine"]))
}

/// The case that rules out collapsing on "gym beaten": the gym is down, but a route in the
/// chapter is still owed, and one encounter per route means it stays owed.
@Test func aBeatenGymWithAnUnloggedRouteIsNotResolved() {
    let first = NuzlockeRules.chapters(shape)[0]
    #expect(
        !NuzlockeRules.isResolved(first, beaten: ["rival1", "gym1"], logged: ["r201", "r203"]))
    #expect(NuzlockeRules.openRouteCount(first, logged: ["r201", "r203"]) == 1)
}

/// And the mirror: every route logged but a boss still standing.
@Test func everyRouteLoggedWithABossStandingIsNotResolved() {
    let first = NuzlockeRules.chapters(shape)[0]
    #expect(
        !NuzlockeRules.isResolved(first, beaten: ["rival1"], logged: ["r201", "r203", "mine"]))
}

/// A League chapter has no routes, so it resolves on its bosses alone — `allSatisfy` over an
/// empty set of locations must not make it un-resolvable.
@Test func aChapterWithNoRoutesResolvesOnItsBosses() {
    let league = NuzlockeRules.chapters(shape)[2]
    #expect(NuzlockeRules.openRouteCount(league, logged: []) == 0)
    #expect(NuzlockeRules.isResolved(league, beaten: ["e4-aaron", "champion"], logged: []))
}
