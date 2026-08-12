import Foundation

/// The 18 types, their prototype colours, and the gen-6+ damage chart.
///
/// This is static data — it does not change per game, per user or per release — so it lives on
/// the client and is never fetched. `docs/design/hunt-prototype.dc.html` holds the same chart in
/// its `CHART` constant and computes weaknesses with `defenseMults`; this is that, in Swift.
///
/// Raw values are PokeAPI type slugs, which is exactly what `pokemon.types` holds
/// (`services/pokeapi.go` marshals `t.Type.Name`) and what a move's `type` column holds.

public enum PokemonType: String, CaseIterable, Sendable {
    // Declaration order is the chart's row order — the order weaknesses are listed in.
    case normal, fire, water, electric, grass, ice, fighting, poison, ground
    case flying, psychic, bug, rock, ghost, dragon, dark, steel, fairy

    /// Tolerates the odd capitalisation/whitespace rather than dropping the type silently: a
    /// species whose type failed to parse would render as having no weaknesses at all, which
    /// reads as a fact rather than as a parse failure.
    public init?(slug: String) {
        self.init(rawValue: slug.trimmingCharacters(in: .whitespaces).lowercased())
    }

    public var displayName: String { rawValue.capitalized }

    /// `TYPE_COLORS` from the prototype, verbatim.
    public var swatch: Swatch {
        switch self {
        case .normal: Swatch(0x9A9A7C)
        case .fire: Swatch(0xE08A4C)
        case .water: Swatch(0x6D94D6)
        case .grass: Swatch(0x7DBA6A)
        case .electric: Swatch(0xD9C24F)
        case .rock: Swatch(0xB1A04E)
        case .ground: Swatch(0xD4B56A)
        case .flying: Swatch(0x9D8FD8)
        case .poison: Swatch(0xA973C9)
        case .psychic: Swatch(0xE07A9A)
        case .dark: Swatch(0x8A7A6A)
        case .ghost: Swatch(0x8571B5)
        case .bug: Swatch(0xA8B545)
        case .ice: Swatch(0x8FD0D0)
        case .fighting: Swatch(0xC45F4C)
        case .steel: Swatch(0xA8A8C0)
        case .dragon: Swatch(0x7A6ADB)
        case .fairy: Swatch(0xDD99C6)
        }
    }
}

/// One attacking type and what it does to a defender — `×4`, `×½`, `×0`.
public struct TypeMatchup: Equatable, Sendable {
    public let type: PokemonType
    public let multiplier: Double

    /// `×4 · ×2 · ×½ · ×¼ · ×0` — the prototype's `multChip` labels.
    public var label: String {
        switch multiplier {
        case 0: "×0"
        case 0.25: "×¼"
        case 0.5: "×½"
        case 4: "×4"
        case 8: "×8"                       // only reachable if a third type is ever passed
        default: "×\(Int(multiplier))"
        }
    }
}

public enum TypeChart {
    /// Attacking type → the defending types it does *not* hit neutrally. Gen 6+ (Fairy, and
    /// Steel no longer resisting Ghost/Dark). Anything absent is ×1.
    static let chart: [PokemonType: [PokemonType: Double]] = [
        .normal: [.rock: 0.5, .ghost: 0, .steel: 0.5],
        .fire: [.fire: 0.5, .water: 0.5, .grass: 2, .ice: 2, .bug: 2, .rock: 0.5, .dragon: 0.5, .steel: 2],
        .water: [.fire: 2, .water: 0.5, .grass: 0.5, .ground: 2, .rock: 2, .dragon: 0.5],
        .electric: [.water: 2, .electric: 0.5, .grass: 0.5, .ground: 0, .flying: 2, .dragon: 0.5],
        .grass: [.fire: 0.5, .water: 2, .grass: 0.5, .poison: 0.5, .ground: 2, .flying: 0.5, .bug: 0.5, .rock: 2, .dragon: 0.5, .steel: 0.5],
        .ice: [.fire: 0.5, .water: 0.5, .grass: 2, .ice: 0.5, .ground: 2, .flying: 2, .dragon: 2, .steel: 0.5],
        .fighting: [.normal: 2, .ice: 2, .poison: 0.5, .flying: 0.5, .psychic: 0.5, .bug: 0.5, .rock: 2, .ghost: 0, .dark: 2, .steel: 2, .fairy: 0.5],
        .poison: [.grass: 2, .poison: 0.5, .ground: 0.5, .rock: 0.5, .ghost: 0.5, .steel: 0, .fairy: 2],
        .ground: [.fire: 2, .electric: 2, .grass: 0.5, .poison: 2, .flying: 0, .bug: 0.5, .rock: 2, .steel: 2],
        .flying: [.electric: 0.5, .grass: 2, .fighting: 2, .bug: 2, .rock: 0.5, .steel: 0.5],
        .psychic: [.fighting: 2, .poison: 2, .psychic: 0.5, .dark: 0, .steel: 0.5],
        .bug: [.fire: 0.5, .grass: 2, .fighting: 0.5, .poison: 0.5, .flying: 0.5, .psychic: 2, .ghost: 0.5, .dark: 2, .steel: 0.5, .fairy: 0.5],
        .rock: [.fire: 2, .ice: 2, .fighting: 0.5, .ground: 0.5, .flying: 2, .bug: 2, .steel: 0.5],
        .ghost: [.normal: 0, .psychic: 2, .ghost: 2, .dark: 0.5],
        .dragon: [.dragon: 2, .steel: 0.5, .fairy: 0],
        .dark: [.fighting: 0.5, .psychic: 2, .ghost: 2, .dark: 0.5, .fairy: 0.5],
        .steel: [.fire: 0.5, .water: 0.5, .electric: 0.5, .ice: 2, .rock: 2, .steel: 0.5, .fairy: 2],
        .fairy: [.fire: 0.5, .fighting: 2, .poison: 0.5, .dragon: 2, .dark: 2, .steel: 0.5],
    ]

    /// Every attacking type that is *not* neutral against this defender, multipliers multiplied
    /// across the defender's types — so Dragon/Ground takes Ice ×4 and Electric ×0, and Grass
    /// (×2 into Ground, ×½ into Dragon) cancels out and is omitted.
    ///
    /// Attack-type order, i.e. ``PokemonType.allCases``, so the list is stable rather than
    /// dictionary-random.
    public static func defense(against types: [PokemonType]) -> [TypeMatchup] {
        guard !types.isEmpty else { return [] }
        return PokemonType.allCases.compactMap { attack in
            let multiplier = types.reduce(1.0) { $0 * (chart[attack]?[$1] ?? 1) }
            return multiplier == 1 ? nil : TypeMatchup(type: attack, multiplier: multiplier)
        }
    }

    /// Takes more than neutral damage — the detail sheet's "Weak to".
    public static func weaknesses(_ types: [PokemonType]) -> [TypeMatchup] {
        defense(against: types).filter { $0.multiplier > 1 }
    }

    /// Takes less — resistances and immunities together, exactly as the prototype's "Resists"
    /// block does (a ×0 is the strongest resistance there is, not a separate section).
    public static func resistances(_ types: [PokemonType]) -> [TypeMatchup] {
        defense(against: types).filter { $0.multiplier < 1 }
    }
}
