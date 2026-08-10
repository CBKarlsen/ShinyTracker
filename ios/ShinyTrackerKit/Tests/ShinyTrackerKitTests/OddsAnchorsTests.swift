import Foundation
import Testing
@testable import ShinyTrackerKit

/// One entry of `shared/odds_anchors.json` — the language-neutral fixture also consumed by
/// `backend/internal/calc/anchors_test.go`. The fixture is the source of truth: if this
/// engine disagrees with it, fix the engine, never the anchor.
struct OddsAnchor: Decodable, CustomStringConvertible {
    let name: String
    let formula: String
    let params: [String: ParamValue]
    let baseOdds: Int
    let baseRolls: Int
    let charmRolls: Int
    let hasCharm: Bool
    let expected: Int
    let tolerance: Int

    enum CodingKeys: String, CodingKey {
        case name, formula, params, expected, tolerance
        case baseOdds = "base_odds"
        case baseRolls = "base_rolls"
        case charmRolls = "charm_rolls"
        case hasCharm = "has_charm"
    }

    var description: String { name }
}

private struct AnchorFile: Decodable {
    let anchors: [OddsAnchor]
}

enum Anchors {
    /// Walk up from this source file to the repo root; the fixture is shared with the Go and
    /// TS engines and deliberately lives outside the package, so it is not an SPM resource.
    static func url() -> URL? {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            let candidate = dir.appendingPathComponent("shared/odds_anchors.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    static let all: [OddsAnchor] = {
        guard let url = url(), let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode(AnchorFile.self, from: data))?.anchors ?? []
    }()
}

/// Guards against a vacuous suite: if the fixture cannot be found or parsed, the
/// parameterised test below silently runs zero cases, which is worse than no test at all.
@Test func anchorFixtureLoads() {
    #expect(Anchors.url() != nil, "shared/odds_anchors.json not found by walking up from #filePath")
    #expect(Anchors.all.count >= 30, "loaded only \(Anchors.all.count) anchors")
}

@Test(arguments: Anchors.all)
func matchesAnchor(_ a: OddsAnchor) {
    let got = ShinyOdds.effectiveOdds(
        formulaType: a.formula,
        params: a.params,
        base: OddsConfig(baseOdds: a.baseOdds, baseRolls: a.baseRolls, charmRolls: a.charmRolls),
        hasCharm: a.hasCharm
    )
    #expect(abs(got - a.expected) <= a.tolerance,
            "\(a.name): got 1/\(got), want 1/\(a.expected) (+/- \(a.tolerance))")
}

/// The third precedence level the anchors cannot express: with neither param key present the
/// combo comes from the live encounter counter, and it must never outrank an explicit key.
@Test func encounterCounterIsLastResort() {
    let base = OddsConfig(baseOdds: 4096, baseRolls: 1, charmRolls: 2)
    func odds(_ params: [String: ParamValue]) -> Int {
        ShinyOdds.effectiveOdds(formulaType: "catch_combo_lgpe", params: params,
                                base: base, hasCharm: true, encounters: 31)
    }
    #expect(odds([:]) == 292)                              // counter used
    #expect(odds(["count": .number(5)]) == 1365)           // count outranks counter
    #expect(odds(["chain_length": .number(5)]) == 1365)    // chain_length outranks counter
}
