/// Shiny-odds engine — the third implementation of the formulas that already live in
/// `backend/internal/calc/methods.go` (Go) and `frontend/src/utils/odds.ts` (TS).
///
/// The source of truth is `shared/odds_anchors.json`, NOT the other two engines: an
/// identical bug has previously lived in both copies and read as consensus. If this file
/// disagrees with an anchor, this file is wrong.
///
/// Pure and dependency-free (Foundation is only needed for JSON in the tests, not here) so
/// it can compute on-device mid-chain while offline.

/// A `hunt_parameters` value. JSON numbers and booleans are the only shapes the stored
/// params ever use.
public enum ParamValue: Equatable, Sendable, Codable {
    case number(Double)
    case bool(Bool)

    public var intValue: Int? {
        if case .number(let d) = self { return Int(d) } // truncates toward zero, as Go's paramInt does
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else {
            self = .number(try c.decode(Double.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        }
    }
}

/// Per-method odds configuration, mirroring `calc.OddsConfig`'s odds-relevant fields.
public struct OddsConfig: Equatable, Sendable {
    public var baseOdds: Int
    public var baseRolls: Int
    public var charmRolls: Int

    public init(baseOdds: Int, baseRolls: Int = 1, charmRolls: Int = 0) {
        self.baseOdds = baseOdds
        self.baseRolls = baseRolls
        self.charmRolls = charmRolls
    }
}

public enum ShinyOdds {

    /// Returns the integer `1 / N` denominator for a method.
    ///
    /// - Parameters:
    ///   - formulaType: `hunt_methods.formula_type`. `nil`, empty, and unknown values all
    ///     behave as `static`.
    ///   - params: stored `hunt_parameters`.
    ///   - base: the method's base odds / rolls / charm rolls.
    ///   - hasCharm: whether the player owns the Shiny Charm. Deliberately inert in
    ///     `radar_chain_gen4` (no charm in Gen IV) and `radar_chain_bdsp` (BDSP's charm is
    ///     breeding-only), and in `radar_chain_xy` it moves only the ordinary-roll term.
    ///   - encounters: the live encounter counter, used as the LAST fallback for
    ///     chain/combo/defeat counts on legacy hunts stored without params.
    ///     Precedence is always `chain_length` > `count` > `encounters`.
    public static func effectiveOdds(
        formulaType: String?,
        params: [String: ParamValue] = [:],
        base: OddsConfig,
        hasCharm: Bool,
        encounters: Int = 0
    ) -> Int {
        let charmRolls = hasCharm ? base.charmRolls : 0

        func floorDiv(_ rolls: Int) -> Int {
            base.baseOdds / max(rolls, 1)
        }

        switch formulaType ?? "static" {

        case "radar_chain_gen4":
            // DPPt ONLY. Bulbapedia: numerator = ceil(65535 / (8200 - 200*chain)); rate =
            // numerator / 65536. chain 0 -> 1/8192, chain 40 (cap) -> 1/200. base_odds is
            // intentionally NOT read (the curve already encodes 1/8192 at chain 0) and the
            // Shiny Charm is intentionally IGNORED — it does not exist in Gen IV.
            let chain = clamp(params.int("chain_length", or: encounters), 0, 40)
            return roundDiv(65536, ceilDiv(65535, 8200 - 200 * chain))

        case "radar_chain_xy":
            // X/Y ONLY. A chain-dependent "sparkle" check is rolled independently of, and in
            // addition to, the ordinary roll-count check. The Shiny Charm affects ONLY the
            // ordinary-roll side, never the sparkle denominator.
            let chain = clamp(params.int("chain_length", or: encounters), 0, 40)
            let pSparkle = 1.0 / Double(8100 - 200 * chain)
            let pNormal = Double(base.baseRolls + charmRolls) / Double(base.baseOdds)
            let pTotal = pSparkle + (1 - pSparkle) * pNormal
            return pTotal > 0 ? Int((1 / pTotal).rounded()) : base.baseOdds

        case "radar_chain_bdsp":
            // BDSP ONLY. Literal numerator/65536 table with real discontinuities at chain 30
            // and chain 36 — not a closed form. numerator[0] = 16 already IS 1/4096, so
            // base_odds is not read; the Shiny Charm is IGNORED (datamined: BDSP's charm
            // affects breeding only).
            let chain = clamp(params.int("chain_length", or: encounters), 0, 40)
            return roundDiv(65536, bdspRadarNumerators[chain])

        case "catch_combo_lgpe":
            // The combo arrives under two historical key names: `chain_length` (live per-hunt
            // state written by the frontend) and `count` (Go route ranking / DefaultParams).
            // Precedence chain_length > count > live counter. Reversing it is silent and ~2x.
            let combo = max(0, params.int("chain_length", "count", or: encounters))
            let extra = tier(combo, [(31, 11), (21, 7), (11, 3)])
            // An active Lure adds exactly one roll: combo 31+ (12) + charm (2) + lure (1) = 15 -> 1/273.
            return floorDiv(base.baseRolls + extra + charmRolls + (params.bool("lure_active") ? 1 : 0))

        case "brilliant_swsh":
            // SwSh Brilliant (sparkle-aura) Pokemon. Rolls scale with how many of that
            // species the player has battled; charm is additive on top.
            // https://bulbapedia.bulbagarden.net/wiki/Brilliant_Pok%C3%A9mon
            // number_battled is NOT a chain -- it never resets, so it defaults to 0
            // rather than falling back to the live encounter counter.
            let battled = max(0, params.int("number_battled", or: 0))
            let extra = tier(battled, [(500, 6), (300, 5), (200, 4), (100, 3), (50, 2), (1, 1)])
            return floorDiv(base.baseRolls + extra + charmRolls)

        case "outbreak_defeats_sv":
            let defeats = max(0, params.int("defeated_count", or: encounters))
            let extra = tier(defeats, [(60, 2), (30, 1)]) + sparklingRolls(params.int("sparkling_power", or: 0))
            return floorDiv(base.baseRolls + extra + charmRolls)

        case "sos_chain_gen7":
            let chain = max(0, params.int("chain_length", or: encounters)) % 255
            return floorDiv(base.baseRolls + tier(chain, [(31, 12), (21, 8), (11, 4)]) + charmRolls)

        case "dexnav_gen6":
            let searchLevel = max(0, params.int("search_level", or: 0))
            let chain = max(0, params.int("chain_length", or: encounters))
            // Piecewise search-level -> points: 6/level to 100, 2/level for 101-200, 1/level beyond.
            var points = 0.0
            if searchLevel > 0 { points += Double(min(searchLevel, 100)) * 6 }
            if searchLevel > 100 { points += Double(min(searchLevel - 100, 100)) * 2 }
            if searchLevel > 200 { points += Double(searchLevel - 200) }
            // dexnav_level = points / 100; per-check forced-shiny probability = dexnav_level / 10000.
            let probDexNav = searchLevel > 0 ? points / 100 / 10000 : 0
            let extra = chain > 0 && chain % 100 == 0 ? 10 : (chain > 0 && chain % 50 == 0 ? 5 : 0)
            let probStandard = Double(base.baseRolls + extra + charmRolls) / Double(base.baseOdds)
            let total = probDexNav + (1 - probDexNav) * probStandard
            return total > 0 ? Int((1 / total).rounded()) : base.baseOdds

        case "sandwich_power_sv":
            return floorDiv(base.baseRolls + sparklingRolls(params.int("sparkling_power", or: 0)) + charmRolls)

        case "dynamax_adventures_gen8":
            return hasCharm ? 100 : 300

        case "chain_fishing_gen6":
            // Same two-key split as catch_combo_lgpe: TS writes `chain_length`, Go's route
            // ranking supplies `count`. Accept both, same precedence.
            let chain = clamp(params.int("chain_length", "count", or: encounters), 0, 20)
            return floorDiv(base.baseRolls + chain * 2 + charmRolls)

        case "pla_research", "pla_mass_outbreak", "pla_massive_outbreak":
            // Legends: Arceus additive rolls. Research Lv10 (+1) and Perfect (+2) STACK. The
            // outbreak bonus comes from the formula_type (where you hunt), not a param.
            // MMO is worse per-encounter than MO by design — its advantage is spawn volume.
            var extra = 0
            if params.int("research_level", or: 0) >= 10 { extra += 1 }
            if params.bool("dex_perfect") { extra += 2 }
            if formulaType == "pla_mass_outbreak" { extra += 25 }
            if formulaType == "pla_massive_outbreak" { extra += 12 }
            return floorDiv(base.baseRolls + extra + charmRolls)

        case "ultra_wormhole":
            // USUM Ultra Warp Ride (non-legendary). Shiny percent scales with distance
            // (capped at 5000 ly, k <= 9) and ring rarity; the Shiny Charm has NO effect.
            let k = clamp(params.int("wormhole_distance_ly", or: 0) / 500 - 1, 0, 9)
            let percent: Int
            switch params.int("wormhole_ring_type", or: 4) {
            case 2: percent = min(10, 1 + k)
            case 3: percent = min(19, 1 + 2 * k)
            case 4: percent = min(36, 1 + 4 * k)
            default: percent = 1 // ring 1 or unknown: flat 1%
            }
            return Int((100.0 / Double(max(percent, 1))).rounded())

        default: // "static" and any unknown formula
            return floorDiv(base.baseRolls + charmRolls)
        }
    }
}

// MARK: - Integer helpers

// ceilDiv/roundDiv are integer-only equivalents of ceil/round for positive-int division.
// They exist because Go's math.Round is half-away-from-zero and JS's Math.round is half-up:
// the integer forms are bit-identical across all three engines. Do NOT replace these with
// Double division and `.rounded()`.
private func ceilDiv(_ a: Int, _ b: Int) -> Int { (a + b - 1) / b }
private func roundDiv(_ a: Int, _ b: Int) -> Int { (2 * a + b) / (2 * b) }

private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(v, hi)) }

/// First `(threshold, bonus)` whose threshold `value` reaches, else 0. Tiers must be descending.
private func tier(_ value: Int, _ tiers: [(Int, Int)]) -> Int {
    tiers.first { value >= $0.0 }?.1 ?? 0
}

private func sparklingRolls(_ power: Int) -> Int { (1...3).contains(power) ? power : 0 }

/// BDSP Poké Radar chain -> numerator/65536 (rate = numerator / 65536).
/// Bulbapedia: https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9_Radar
/// 41 entries, index = clamp(chain, 0, 40). Copied verbatim, discontinuities included.
private let bdspRadarNumerators: [Int] = [
    16, 17, 18, 19, 20, 21, 22, 23, 24, 25, // chain  0- 9
    26, 27, 28, 29, 30, 31, 32, 33, 34, 35, // chain 10-19
    36, 37, 38, 39, 40, 41, 42, 43, 44, 45, // chain 20-29
    50, 51, 52, 53, 54, 55,                 // chain 30-35  (discontinuity at 30)
    66, 82, 164, 328, 662,                  // chain 36-40  (discontinuity at 36)
]

// MARK: - Param access

extension Dictionary where Key == String, Value == ParamValue {
    /// First present-and-numeric key wins; key order IS the precedence order.
    func int(_ keys: String..., or fallback: Int) -> Int {
        for key in keys {
            if let v = self[key]?.intValue { return v }
        }
        return fallback
    }

    func bool(_ key: String) -> Bool { self[key]?.boolValue ?? false }
}
