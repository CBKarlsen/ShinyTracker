import Foundation

/// A spread of six values — EVs, IVs, or computed stats.
public struct StatSpread: Codable, Equatable, Sendable {
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

    public static let zero = StatSpread()

    /// The default IV spread. **Omitted IVs are 31, not 0** — getting this backwards is
    /// the most common way a Showdown parser silently corrupts a set.
    public static let maxIVs = StatSpread(hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31)

    public var total: Int { Stat.allCases.reduce(0) { $0 + self[$1] } }
}
