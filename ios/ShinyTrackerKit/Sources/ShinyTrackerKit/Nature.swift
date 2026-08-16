import Foundation

/// The six battle stats, in the order every stat block in the game prints them.
public enum Stat: String, CaseIterable, Codable, Sendable {
    case hp, atk, def, spa, spd, spe

    /// The label Showdown uses in an `EVs:` / `IVs:` line.
    public var showdownLabel: String {
        switch self {
        case .hp: "HP"
        case .atk: "Atk"
        case .def: "Def"
        case .spa: "SpA"
        case .spd: "SpD"
        case .spe: "Spe"
        }
    }
}

/// The 25 natures. Each raises one stat by 10% and lowers another by 10%; the five
/// where those would be the same stat are neutral instead.
///
/// Hardcoded rather than seeded, deliberately. This set has not changed since
/// Generation 3 and cannot change without a new game — a table would be a migration,
/// a seeder and a network round trip in exchange for nothing. Same reasoning as
/// `calc.ShinyCharmAvailable`'s allow-list on the Go side.
public enum Nature: String, CaseIterable, Codable, Sendable {
    case hardy, lonely, brave, adamant, naughty
    case bold, docile, relaxed, impish, lax
    case timid, hasty, serious, jolly, naive
    case modest, mild, quiet, bashful, rash
    case calm, gentle, sassy, careful, quirky

    /// The stat this nature raises by 10%, or nil when neutral.
    public var raised: Stat? {
        switch self {
        case .lonely, .brave, .adamant, .naughty: .atk
        case .bold, .relaxed, .impish, .lax: .def
        case .timid, .hasty, .jolly, .naive: .spe
        case .modest, .mild, .quiet, .rash: .spa
        case .calm, .gentle, .sassy, .careful: .spd
        case .hardy, .docile, .serious, .bashful, .quirky: nil
        }
    }

    /// The stat this nature lowers by 10%, or nil when neutral.
    public var lowered: Stat? {
        switch self {
        case .bold, .timid, .modest, .calm: .atk
        case .lonely, .hasty, .mild, .gentle: .def
        case .brave, .relaxed, .quiet, .sassy: .spe
        case .adamant, .impish, .jolly, .careful: .spa
        case .naughty, .lax, .naive, .rash: .spd
        case .hardy, .docile, .serious, .bashful, .quirky: nil
        }
    }

    public func modifier(for stat: Stat) -> Double {
        if stat == raised { return 1.1 }
        if stat == lowered { return 0.9 }
        return 1.0
    }

    /// Title-case, as Showdown writes it: `Jolly Nature`.
    public var displayName: String { rawValue.capitalized }
}
