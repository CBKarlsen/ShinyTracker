import Testing
@testable import ShinyTrackerKit

/// Values cross-checked against the published Gen 3+ formula. These are the numbers
/// a competitive player will recognise on sight — a wrong one is visible immediately
/// to a user and invisible to a reviewer.
@Test func garchompMaxSpeedJolly() {
    // Garchomp base Spe 102, 31 IV, 252 EV, Jolly (+Spe), level 50.
    let value = StatCalculator.value(
        base: 102, iv: 31, ev: 252, level: 50, nature: .jolly, stat: .spe)
    #expect(value == 169)
}

@Test func garchompHPAtLevelFifty() {
    // Base HP 108. HP ignores nature entirely.
    let value = StatCalculator.value(
        base: 108, iv: 31, ev: 0, level: 50, nature: .jolly, stat: .hp)
    #expect(value == 183)
}

@Test func aLoweringNatureRoundsDown() {
    // Garchomp base SpA 80, Jolly lowers it. Core is 100, x0.9 = 90 exactly.
    let value = StatCalculator.value(
        base: 80, iv: 31, ev: 0, level: 50, nature: .jolly, stat: .spa)
    #expect(value == 90)
}

/// Truncation, not rounding. Base 95 Def at L50 gives a core of 115; x0.9 is 103.5,
/// and the game floors it. Rounding here would inflate one stat on most bulky spreads.
@Test func aLoweringNatureTruncatesRatherThanRounds() {
    let value = StatCalculator.value(
        base: 95, iv: 31, ev: 0, level: 50, nature: .lonely, stat: .def)
    #expect(value == 103)
}

@Test func levelOneHundredDoublesRoughly() {
    let value = StatCalculator.value(
        base: 102, iv: 31, ev: 252, level: 100, nature: .jolly, stat: .spe)
    #expect(value == 333)
}

/// Shedinja is the only species whose HP ignores the formula. It is exactly the kind
/// of special case a fixture catches and a reviewer does not.
@Test func shedinjaAlwaysHasOneHP() {
    let value = StatCalculator.value(
        base: 1, iv: 31, ev: 252, level: 50, nature: .hardy, stat: .hp, speciesID: 292)
    #expect(value == 1)
}

@Test func aLegalSpreadValidates() throws {
    let set = PokemonSet(
        speciesID: 445, speciesName: "garchomp", abilitySlug: "rough-skin",
        evs: StatSpread(atk: 252, spd: 4, spe: 252))
    try set.validate()          // must not throw
    #expect(set.evs.total == 508)
}

@Test func anOverCapSpreadIsRejected() {
    let set = PokemonSet(
        speciesID: 445, speciesName: "garchomp", abilitySlug: "rough-skin",
        evs: StatSpread(hp: 252, atk: 252, def: 252))
    #expect(throws: PokemonSet.SetError.evTotalTooHigh(756)) { try set.validate() }
}

@Test func moreThan252InOneStatIsRejected() {
    let set = PokemonSet(
        speciesID: 445, speciesName: "garchomp", abilitySlug: "rough-skin",
        evs: StatSpread(atk: 300))
    #expect(throws: PokemonSet.SetError.evStatTooHigh(.atk, 300)) { try set.validate() }
}

@Test func ivsDefaultToThirtyOneNotZero() {
    let set = PokemonSet(speciesID: 445, speciesName: "garchomp", abilitySlug: "rough-skin")
    for stat in Stat.allCases { #expect(set.ivs[stat] == 31) }
}
