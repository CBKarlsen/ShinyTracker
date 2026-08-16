import Foundation

/// The Gen 3+ stat formula, unchanged since Ruby/Sapphire.
///
///     HP    = floor((2·Base + IV + floor(EV/4)) · Level / 100) + Level + 10
///     Other = floor((floor((2·Base + IV + floor(EV/4)) · Level / 100) + 5) · NatureMod)
///
/// Integer division at every step is load-bearing: computing in Double and rounding at
/// the end produces off-by-one values on roughly a third of spreads, and those are the
/// values a competitive player checks first.
public enum StatCalculator {
    /// Shedinja's National Dex number. Its HP is always 1, whatever the formula says.
    static let shedinjaID = 292

    public static func value(
        base: Int,
        iv: Int,
        ev: Int,
        level: Int,
        nature: Nature,
        stat: Stat,
        speciesID: Int? = nil
    ) -> Int {
        if stat == .hp {
            if speciesID == shedinjaID { return 1 }
            return (2 * base + iv + ev / 4) * level / 100 + level + 10
        }
        let core = (2 * base + iv + ev / 4) * level / 100 + 5
        return Int(Double(core) * nature.modifier(for: stat))
    }
}
