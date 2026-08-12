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

/// The backward glitch must not move the anchor either — otherwise the next legitimate
/// encounter measures against a too-early timestamp and banks the difference as phantom time.
@Test func aBackwardGlitchDoesNotPoisonTheAnchorForTheNextRecord() {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(-590), idleThreshold: 600)
    #expect(clock.totalSeconds == 0)
    clock.record(at: t0.addingTimeInterval(1), idleThreshold: 600)
    #expect(clock.totalSeconds == 1)
}

/// The `<=` at the threshold boundary is deliberate — pin it so a future swap to `<` fails loudly.
@Test func aGapExactlyAtTheThresholdCounts() {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(600), idleThreshold: 600)
    #expect(clock.totalSeconds == 600)
}

@Test func twoRecordsAtTheSameInstantBankNothing() {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0, idleThreshold: 600)
    #expect(clock.totalSeconds == 0)
}

/// Regression guard for per-call rounding drift: rounding each gap independently used to
/// compound into invented time — at this cadence, an hour of it over 10,000 encounters.
@Test func fractionalGapsAccumulateWithoutDrift() {
    var clock = HuntClock()
    var t = t0
    clock.record(at: t, idleThreshold: 600)
    for _ in 0..<1000 {
        t = t.addingTimeInterval(6.6)
        clock.record(at: t, idleThreshold: 600)
    }
    #expect(abs(clock.totalSeconds - 6600) <= 2)
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

/// Behind the server, the client's sends are swallowed by `DecideTotalTime`'s max() until it
/// catches up, so it adopts the server total and counts on from there — but never rewinds to a
/// lower one, which would throw away time this client banked offline.
@Test func raisingAdoptsAHigherServerTotalAndIgnoresALowerOne() {
    var clock = HuntClock(totalSeconds: 100)
    clock.raise(to: 5000)
    #expect(clock.totalSeconds == 5000)
    clock.raise(to: 4000)
    #expect(clock.totalSeconds == 5000)
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(7), idleThreshold: 600)
    #expect(clock.totalSeconds == 5007)
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
