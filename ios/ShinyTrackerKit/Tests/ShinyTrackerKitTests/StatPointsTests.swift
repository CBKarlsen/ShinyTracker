import Testing
@testable import ShinyTrackerKit

@Test func theCapsAreSixtySixAndThirtyTwo() {
    #expect(StatPoints.maxTotal == 66)
    #expect(StatPoints.maxPerStat == 32)
}

/// The documented HOME conversion: 4 EVs buy the first point in a stat, 8 buy
/// each additional one.
@Test func evsConvertAtFourThenEight() {
    #expect(StatPoints.fromEVs(StatSpread(hp: 0))[.hp] == 0)
    #expect(StatPoints.fromEVs(StatSpread(hp: 3))[.hp] == 0)
    #expect(StatPoints.fromEVs(StatSpread(hp: 4))[.hp] == 1)
    #expect(StatPoints.fromEVs(StatSpread(hp: 11))[.hp] == 1)
    #expect(StatPoints.fromEVs(StatSpread(hp: 12))[.hp] == 2)
}

/// This is the check that confirms the conversion rather than assuming it.
/// 252 EVs is the per-stat maximum in the mainline games and it lands exactly
/// on 32, the per-stat maximum in Champions. If the rate were wrong these two
/// independently-documented numbers would not meet.
@Test func maxEVsInOneStatLandsExactlyOnTheStatCap() {
    #expect(StatPoints.fromEVs(StatSpread(atk: 252))[.atk] == 32)
}

/// And a fully-trained 252/252/4 spread lands on exactly 65 — the figure
/// Bulbapedia states a transferred, fully-EV-trained Pokemon arrives with.
@Test func aFullyTrainedSpreadLandsOnSixtyFive() {
    let sp = StatPoints.fromEVs(StatSpread(atk: 252, spd: 4, spe: 252))
    #expect(sp.total == 65)
}

@Test func cappedClampsPerStatAndAgainstTheRemainingPool() {
    var sp = StatPoints.zero
    sp[.atk] = 32
    sp[.spe] = 32
    // 64 spent, 2 left in the pool — asking for 30 in HP yields 2.
    #expect(sp.capped(30, for: .hp) == 2)
    // And a single stat can never exceed 32 even with the whole pool free.
    #expect(StatPoints.zero.capped(50, for: .hp) == 32)
    #expect(StatPoints.zero.capped(-5, for: .hp) == 0)
}
