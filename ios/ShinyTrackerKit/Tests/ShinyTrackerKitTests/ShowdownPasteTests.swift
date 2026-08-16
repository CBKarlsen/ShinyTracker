import Foundation
import Testing
@testable import ShinyTrackerKit

/// One entry of `shared/showdown_pastes.json`. The fixture is the source of truth: the
/// format is defined by someone else's software, so when this parser disagrees with the
/// fixture, fix the parser.
private struct PasteCase: Decodable {
    let name: String
    let paste: String
    let expected: [ExpectedSet]
}

private struct ExpectedSet: Decodable {
    let species: String
    let nickname: String?
    let gender: String?
    let item: String?
    let ability: String?
    let level: Int
    let teraType: String?
    let nature: String
    let evs: [String: Int]
    let ivs: [String: Int]
    let moves: [String]
}

private struct PasteFile: Decodable { let cases: [PasteCase] }

/// Same walk-up-to-repo-root trick as `Anchors.url()` in OddsAnchorsTests: the fixture is
/// deliberately outside the package so other languages can consume it later.
private func fixtureURL() -> URL? {
    var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<12 {
        let candidate = dir.appendingPathComponent("shared/showdown_pastes.json")
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        dir.deleteLastPathComponent()
    }
    return nil
}

private func loadCases() throws -> [PasteCase] {
    let url = try #require(fixtureURL(), "shared/showdown_pastes.json not found")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(PasteFile.self, from: data).cases
}

private func spread(_ dict: [String: Int]) -> StatSpread {
    var s = StatSpread.zero
    for stat in Stat.allCases { s[stat] = dict[stat.rawValue] ?? 0 }
    return s
}

@Test func everyFixtureCaseParses() throws {
    for testCase in try loadCases() {
        let parsed = try ShowdownPaste.parse(testCase.paste)
        #expect(parsed.count == testCase.expected.count, "\(testCase.name): set count")

        for (got, want) in zip(parsed, testCase.expected) {
            #expect(got.species == want.species, "\(testCase.name): species")
            #expect(got.nickname == want.nickname, "\(testCase.name): nickname")
            #expect(got.gender == want.gender, "\(testCase.name): gender")
            #expect(got.item == want.item, "\(testCase.name): item")
            #expect(got.ability == want.ability, "\(testCase.name): ability")
            #expect(got.level == want.level, "\(testCase.name): level")
            #expect(got.teraType == want.teraType, "\(testCase.name): tera")
            #expect(got.nature.rawValue == want.nature, "\(testCase.name): nature")
            #expect(got.evs == spread(want.evs), "\(testCase.name): EVs")
            #expect(got.ivs == spread(want.ivs), "\(testCase.name): IVs")
            #expect(got.moves == want.moves, "\(testCase.name): moves")
        }
    }
}

/// The single most common way a naive parser corrupts a set.
@Test func omittedIVsAreThirtyOneNotZero() throws {
    let parsed = try ShowdownPaste.parse("Garchomp\nIVs: 0 Atk")
    #expect(parsed[0].ivs.atk == 0)
    #expect(parsed[0].ivs.spe == 31)
    #expect(parsed[0].ivs.hp == 31)
}

@Test func anEmptyPasteIsAnError() {
    #expect(throws: ShowdownPaste.ParseError.empty) {
        try ShowdownPaste.parse("   \n\n  ")
    }
}

@Test func anUnknownNatureNamesTheLine() {
    #expect(throws: ShowdownPaste.ParseError.unknownNature("Sparkly")) {
        try ShowdownPaste.parse("Garchomp\nSparkly Nature")
    }
}

/// The property that actually matters. Parse-only tests pass happily while export
/// silently drops the Tera type.
@Test func everyFixtureCaseRoundTrips() throws {
    for testCase in try loadCases() {
        let parsed = try ShowdownPaste.parse(testCase.paste)
        let exported = ShowdownPaste.export(parsed)
        let reparsed = try ShowdownPaste.parse(exported)
        #expect(reparsed == parsed, "\(testCase.name) did not round-trip:\n\(exported)")
    }
}

@Test func exportOmitsEverythingThatIsDefault() throws {
    let parsed = try ShowdownPaste.parse("Gholdengo")
    // No item, no ability, no EV line, no nature line, no moves — a bare species
    // must not export six lines of zeroes.
    #expect(ShowdownPaste.export(parsed) == "Gholdengo")
}

@Test func exportWritesTheSpreadInStatOrder() throws {
    let parsed = try ShowdownPaste.parse(
        "Garchomp\nEVs: 252 Spe / 252 Atk\nJolly Nature")
    #expect(ShowdownPaste.export(parsed).contains("EVs: 252 Atk / 252 Spe"))
}
