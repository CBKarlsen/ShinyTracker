import Foundation

/// Pokemon Champions' unified stat allocation, replacing both EVs and IVs.
///
/// 66 points across six stats, at most 32 in any one. IVs do not exist in
/// Champions at all — every Pokemon calculates as though it had 31 in every
/// stat — so there is no second spread to model.
public struct StatPoints: Codable, Equatable, Sendable {
    public var hp: Int
    public var atk: Int
    public var def: Int
    public var spa: Int
    public var spd: Int
    public var spe: Int

    public init(hp: Int = 0, atk: Int = 0, def: Int = 0, spa: Int = 0, spd: Int = 0, spe: Int = 0) {
        self.hp = hp; self.atk = atk; self.def = def
        self.spa = spa; self.spd = spd; self.spe = spe
    }

    public static let maxTotal = 66
    public static let maxPerStat = 32
    public static let zero = StatPoints()

    public subscript(stat: Stat) -> Int {
        get {
            switch stat {
            case .hp: hp
            case .atk: atk
            case .def: def
            case .spa: spa
            case .spd: spd
            case .spe: spe
            }
        }
        set {
            switch stat {
            case .hp: hp = newValue
            case .atk: atk = newValue
            case .def: def = newValue
            case .spa: spa = newValue
            case .spd: spd = newValue
            case .spe: spe = newValue
            }
        }
    }

    public var total: Int { Stat.allCases.reduce(0) { $0 + self[$1] } }

    /// The largest legal value for `stat`, given what the other five already
    /// spend. Clamping here rather than validating afterwards is what makes an
    /// illegal spread unreachable from the UI.
    public func capped(_ value: Int, for stat: Stat) -> Int {
        let spentElsewhere = total - self[stat]
        return max(0, min(value, Self.maxPerStat, Self.maxTotal - spentElsewhere))
    }

    /// Converts a mainline EV spread, as Pokemon HOME does on transfer: 4 EVs
    /// buy the first point in a stat, 8 buy each additional one.
    ///
    /// Used for importing an existing Scarlet/Violet team. The rate is not a
    /// guess — 252 EVs (the mainline per-stat cap) lands exactly on 32
    /// (Champions' per-stat cap), and a 252/252/4 spread lands exactly on the
    /// 65 points a fully-trained transfer is documented to arrive with.
    public static func fromEVs(_ evs: StatSpread) -> StatPoints {
        var points = StatPoints.zero
        for stat in Stat.allCases {
            let ev = evs[stat]
            guard ev >= 4 else { continue }
            points[stat] = min(Self.maxPerStat, 1 + (ev - 4) / 8)
        }
        return points
    }
}
