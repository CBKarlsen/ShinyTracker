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

/// One built Pokémon.
public struct PokemonSet: Codable, Equatable, Sendable {
    public var speciesID: Int
    public var speciesName: String
    public var nickname: String?
    public var nature: Nature
    public var abilitySlug: String
    public var itemSlug: String?
    public var teraType: String?
    public var level: Int
    public var evs: StatSpread
    public var ivs: StatSpread
    public var moves: [String]

    public init(
        speciesID: Int, speciesName: String, nickname: String? = nil,
        nature: Nature = .hardy, abilitySlug: String, itemSlug: String? = nil,
        teraType: String? = nil, level: Int = 50,
        evs: StatSpread = .zero, ivs: StatSpread = .maxIVs, moves: [String] = []
    ) {
        self.speciesID = speciesID; self.speciesName = speciesName
        self.nickname = nickname; self.nature = nature
        self.abilitySlug = abilitySlug; self.itemSlug = itemSlug
        self.teraType = teraType; self.level = level
        self.evs = evs; self.ivs = ivs; self.moves = moves
    }

    public enum SetError: Error, Equatable {
        case evTotalTooHigh(Int)
        case evStatTooHigh(Stat, Int)
        case ivOutOfRange(Stat, Int)
        case tooManyMoves(Int)
        case levelOutOfRange(Int)
    }

    /// The game's own caps. Validated here as well as in the handler and the UI because a
    /// set that breaks them exports to a paste Showdown rejects — a silent corruption of
    /// the one output that has to interoperate.
    public func validate() throws {
        if evs.total > 508 { throw SetError.evTotalTooHigh(evs.total) }
        for stat in Stat.allCases {
            if evs[stat] > 252 { throw SetError.evStatTooHigh(stat, evs[stat]) }
            if ivs[stat] < 0 || ivs[stat] > 31 { throw SetError.ivOutOfRange(stat, ivs[stat]) }
        }
        if moves.count > 4 { throw SetError.tooManyMoves(moves.count) }
        if level < 1 || level > 100 { throw SetError.levelOutOfRange(level) }
    }
}
