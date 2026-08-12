import Foundation
import Testing

@testable import ShinyTrackerKit

private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

@Test func theFirstEncounterContributesNoTime() {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    #expect(clock.totalSeconds == 0)
    #expect(clock.lastEncounterAt == t0)
}

@Test func aGapUnderTheThresholdAccumulates() {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(7), idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(14), idleThreshold: 600)
    #expect(clock.totalSeconds == 14)
}

/// The whole point of the threshold: a phone put down mid-hunt must not bank the hours it spent
/// in a pocket.
@Test func aGapOverTheThresholdContributesNothingButRestartsTheClock() {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(4000), idleThreshold: 600)
    #expect(clock.totalSeconds == 0)
    clock.record(at: t0.addingTimeInterval(4010), idleThreshold: 600)
    #expect(clock.totalSeconds == 10)
}

/// Clock changes and a stale timestamp must not bank negative time.
@Test func aBackwardsClockContributesNothing() {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(-50), idleThreshold: 600)
    #expect(clock.totalSeconds == 0)
}

/// Per-method rather than fixed: a soft-reset hunt's normal cadence is minutes and a wild
/// encounter's is seconds, so one constant cannot serve both.
@Test func theIdleThresholdScalesWithTheMethodAndClampsAtBothEnds() {
    #expect(HuntClock.idleThreshold(avgTimeSeconds: 30) == 600)      // 30 x 20
    #expect(HuntClock.idleThreshold(avgTimeSeconds: 3) == 120)       // 60 clamped up to 2 min
    #expect(HuntClock.idleThreshold(avgTimeSeconds: 300) == 900)     // 6000 clamped to 15 min
}

/// A custom-method hunt has no method row and therefore no avg_time_seconds.
@Test func theIdleThresholdFallsBackWithoutAMethod() {
    #expect(HuntClock.idleThreshold(avgTimeSeconds: nil) == 600)
    #expect(HuntClock.idleThreshold(avgTimeSeconds: 0) == 600)
}

/// The clock is persisted between launches, so it has to survive a round trip intact.
@Test func theClockRoundTripsThroughCodable() throws {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(9), idleThreshold: 600)
    let replayed = try JSONDecoder().decode(
        HuntClock.self, from: JSONEncoder().encode(clock))
    #expect(replayed == clock)
}
