import Foundation

/// Pokémon Showdown's team paste format — the interop layer of competitive Pokémon.
///
/// The format is human-authored and loosely specified. It is worth parsing carefully
/// because a team that round-trips works with Showdown, every damage calculator, and
/// every forum post; a team that round-trips *lossily* is worse than no export at all,
/// because the loss is silent.
///
/// Behaviour is pinned by `shared/showdown_pastes.json`, the same way `odds_anchors.json`
/// pins the odds engine.
public enum ShowdownPaste {
    /// The default IV spread for a paste. **Omitted IVs are 31, not 0** — getting this
    /// backwards is the most common way a Showdown parser silently corrupts a set. This
    /// is a fact about the paste format, not about Champions (which has no IVs at all —
    /// see `StatPoints`), so it lives here rather than on `StatSpread`.
    public static let defaultPasteIVs = StatSpread(hp: 31, atk: 31, def: 31, spa: 31, spd: 31, spe: 31)

    /// One set as it appears in a paste: names, not ids. Resolving "Iron Valiant" to a
    /// species id and "Swords Dance" to a move slug needs the database, which this package
    /// deliberately cannot reach.
    public struct ParsedSet: Equatable, Sendable {
        public var species: String
        public var nickname: String?
        public var gender: String?
        public var item: String?
        public var ability: String?
        public var level: Int
        public var teraType: String?
        public var nature: Nature
        public var evs: StatSpread
        public var ivs: StatSpread
        public var moves: [String]

        /// Spelled out because the synthesised memberwise initialiser is internal, and the
        /// side that resolves names to ids — `ShowdownBridge` in `ShinyTrackerAPI` — builds
        /// sets to export from another module.
        public init(
            species: String, nickname: String? = nil, gender: String? = nil, item: String? = nil,
            ability: String? = nil, level: Int = 100, teraType: String? = nil,
            nature: Nature = .hardy, evs: StatSpread = .zero, ivs: StatSpread = ShowdownPaste.defaultPasteIVs,
            moves: [String] = []
        ) {
            self.species = species
            self.nickname = nickname
            self.gender = gender
            self.item = item
            self.ability = ability
            self.level = level
            self.teraType = teraType
            self.nature = nature
            self.evs = evs
            self.ivs = ivs
            self.moves = moves
        }
    }

    public enum ParseError: Error, Equatable {
        case empty
        case unknownNature(String)
        case unknownStat(String)
        case malformedSpreadLine(String)
    }

    public static func parse(_ text: String) throws -> [ParsedSet] {
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalised
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !blocks.isEmpty else { throw ParseError.empty }
        return try blocks.map(parseBlock)
    }

    private static func parseBlock(_ block: String) throws -> ParsedSet {
        let lines = block.split(separator: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        guard let header = lines.first else { throw ParseError.empty }

        var set = try parseHeader(header)

        for line in lines.dropFirst() {
            if line.hasPrefix("- ") {
                set.moves.append(String(line.dropFirst(2)))
            } else if let value = strip(line, prefix: "Ability: ") {
                set.ability = value
            } else if let value = strip(line, prefix: "Level: ") {
                set.level = Int(value) ?? 100
            } else if let value = strip(line, prefix: "Tera Type: ") {
                set.teraType = value
            } else if let value = strip(line, prefix: "EVs: ") {
                set.evs = try parseSpread(value, into: .zero)
            } else if let value = strip(line, prefix: "IVs: ") {
                // Base is defaultPasteIVs: a paste lists only the stats it changes, and
                // every stat it omits is 31.
                set.ivs = try parseSpread(value, into: defaultPasteIVs)
            } else if line.hasSuffix(" Nature") {
                let name = String(line.dropLast(" Nature".count))
                guard let nature = Nature(rawValue: name.lowercased()) else {
                    throw ParseError.unknownNature(name)
                }
                set.nature = nature
            }
            // Unrecognised lines (Shiny: Yes, Happiness, Gigantamax) are skipped rather
            // than rejected: the format grows, and refusing a whole team over one
            // unknown line is worse than dropping the line.
        }

        return set
    }

    /// `Chomp (Garchomp) (M) @ Life Orb` — nickname, species, gender and item are all
    /// optional, and the species may itself contain hyphens (`Urshifu-Rapid-Strike`).
    private static func parseHeader(_ header: String) throws -> ParsedSet {
        var rest = header
        var item: String?

        if let atRange = rest.range(of: " @ ") {
            item = String(rest[atRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            rest = String(rest[..<atRange.lowerBound])
        }

        var gender: String?
        for candidate in ["(M)", "(F)"] where rest.hasSuffix(candidate) {
            gender = String(candidate.dropFirst().dropLast())
            rest = String(rest.dropLast(candidate.count)).trimmingCharacters(in: .whitespaces)
        }

        var nickname: String?
        var species = rest.trimmingCharacters(in: .whitespaces)

        // A trailing parenthesised group is the SPECIES and what precedes it is the
        // nickname — the reverse of how it reads. `Chomp (Garchomp)` is a Garchomp
        // nicknamed Chomp.
        if species.hasSuffix(")"), let open = species.lastIndex(of: "(") {
            let inner = species[species.index(after: open)..<species.index(before: species.endIndex)]
            nickname = String(species[..<open]).trimmingCharacters(in: .whitespaces)
            species = String(inner).trimmingCharacters(in: .whitespaces)
        }

        return ParsedSet(
            species: species, nickname: nickname, gender: gender, item: item,
            ability: nil, level: 100, teraType: nil, nature: .hardy,
            evs: .zero, ivs: defaultPasteIVs, moves: [])
    }

    /// `252 Atk / 4 SpD / 252 Spe`
    private static func parseSpread(_ value: String, into base: StatSpread) throws -> StatSpread {
        var spread = base
        for part in value.split(separator: "/") {
            let tokens = part.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard tokens.count == 2, let amount = Int(tokens[0]) else {
                throw ParseError.malformedSpreadLine(String(part))
            }
            let label = String(tokens[1])
            guard let stat = Stat.allCases.first(where: { $0.showdownLabel == label }) else {
                throw ParseError.unknownStat(label)
            }
            spread[stat] = amount
        }
        return spread
    }

    private static func strip(_ line: String, prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    /// Renders sets back to paste text. Every default is omitted, because a paste
    /// bloated with zero lines is one no human will read and one that diffs badly
    /// against the source it came from.
    public static func export(_ sets: [ParsedSet]) -> String {
        sets.map(exportOne).joined(separator: "\n\n")
    }

    private static func exportOne(_ set: ParsedSet) -> String {
        var lines: [String] = []

        var header = set.nickname.map { "\($0) (\(set.species))" } ?? set.species
        if let gender = set.gender { header += " (\(gender))" }
        if let item = set.item { header += " @ \(item)" }
        lines.append(header)

        if let ability = set.ability { lines.append("Ability: \(ability)") }
        if set.level != 100 { lines.append("Level: \(set.level)") }
        if let tera = set.teraType { lines.append("Tera Type: \(tera)") }

        if let evs = spreadLine(set.evs, omitting: 0) { lines.append("EVs: \(evs)") }
        if set.nature != .hardy { lines.append("\(set.nature.displayName) Nature") }
        if let ivs = spreadLine(set.ivs, omitting: 31) { lines.append("IVs: \(ivs)") }

        lines.append(contentsOf: set.moves.map { "- \($0)" })
        return lines.joined(separator: "\n")
    }

    /// `252 Atk / 4 SpD / 252 Spe`, in `Stat.allCases` order so the same spread always
    /// renders the same way. Returns nil when every value is the default.
    private static func spreadLine(_ spread: StatSpread, omitting defaultValue: Int) -> String? {
        let parts = Stat.allCases
            .filter { spread[$0] != defaultValue }
            .map { "\(spread[$0]) \($0.showdownLabel)" }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }
}
