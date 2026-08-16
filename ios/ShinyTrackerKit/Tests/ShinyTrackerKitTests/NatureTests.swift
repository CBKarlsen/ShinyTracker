import Testing
@testable import ShinyTrackerKit

@Test func thereAreExactlyTwentyFiveNatures() {
    #expect(Nature.allCases.count == 25)
}

@Test func aNeutralNatureModifiesNothing() {
    // Five natures raise and lower the same stat, so they are neutral.
    #expect(Nature.hardy.raised == nil)
    #expect(Nature.hardy.lowered == nil)
    for stat in Stat.allCases {
        #expect(Nature.hardy.modifier(for: stat) == 1.0)
    }
}

@Test func adamantRaisesAttackAndLowersSpecialAttack() {
    #expect(Nature.adamant.raised == .atk)
    #expect(Nature.adamant.lowered == .spa)
    #expect(Nature.adamant.modifier(for: .atk) == 1.1)
    #expect(Nature.adamant.modifier(for: .spa) == 0.9)
    #expect(Nature.adamant.modifier(for: .spe) == 1.0)
}

/// HP is never affected by nature. A table that raised it would silently
/// inflate every bulky set.
@Test func noNatureEverModifiesHP() {
    for nature in Nature.allCases {
        #expect(nature.modifier(for: .hp) == 1.0)
        #expect(nature.raised != .hp)
        #expect(nature.lowered != .hp)
    }
}

/// Exactly 20 natures modify stats; the other 5 are neutral.
@Test func exactlyTwentyNaturesAreNonNeutral() {
    let nonNeutral = Nature.allCases.filter { $0.raised != nil }
    #expect(nonNeutral.count == 20)
}
