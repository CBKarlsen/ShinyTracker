import Foundation
import ShinyTrackerKit

/// The translation between what a Showdown paste says and what this API stores.
///
/// `ShowdownPaste.ParsedSet` speaks **display names** — `"Urshifu-Rapid-Strike"`, `"Swords
/// Dance"`, `"Rough Skin"`, `"Rocky Helmet"` — because `ShinyTrackerKit` deliberately cannot
/// reach the database. `TeamMember` speaks **ids and slugs** — `892`, `"swords-dance"`,
/// `"rough-skin"`, `"rocky-helmet"`. Neither side can resolve the other alone, so the
/// resolution lives here, next to the types it produces, where it is testable without a
/// screen: the reference data is passed in, nothing is fetched.
///
/// Both directions go through ``key(_:)``, which is what makes a round trip hold. Export
/// emits `"Swords Dance"` when it knows the name and `"swords-dance"` when it does not, and
/// import resolves both to the same slug.
public enum ShowdownBridge {
    /// Showdown's own normalisation: lowercase, and drop everything that is not a letter or a
    /// digit. `"Urshifu-Rapid-Strike"`, `"urshifu-rapid-strike"` and `"Urshifu Rapid Strike"`
    /// are one key, which is why a paste written by hand still resolves.
    public static func key(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The 19 legal Tera types, Title-case — the casing `validTeraTypes` in
    /// `backend/internal/api/teams.go` accepts. 18 elemental plus Stellar; a value outside this
    /// set is a 400, so an unrecognised `Tera Type:` line becomes no Tera type rather than a
    /// rejected import.
    public static let teraTypes: Set<String> = [
        "Normal", "Fire", "Water", "Electric", "Grass", "Ice", "Fighting", "Poison", "Ground",
        "Flying", "Psychic", "Bug", "Rock", "Ghost", "Dragon", "Dark", "Steel", "Fairy",
        "Stellar",
    ]

    // MARK: Export

    /// Renders saved members as paste text.
    ///
    /// Every name that cannot be resolved falls back to its slug. That is deliberate: a paste
    /// carrying `- swords-dance` is still usable by a human and still re-imports, whereas a
    /// blank move line is neither.
    public static func paste(
        _ members: [TeamMember],
        species: [Pokemon],
        items: [Item],
        details: [Int: PokemonDetail]
    ) -> String {
        let speciesNames = Dictionary(species.map { ($0.id, displayName($0.name)) }) { first, _ in first }
        let itemNames = Dictionary(items.map { ($0.slug, $0.name) }) { first, _ in first }

        return ShowdownPaste.export(
            members.sorted { $0.slot < $1.slot }.map { member in
                let detail = details[member.pokemonID]
                let moveNames = Dictionary(
                    (detail?.moves ?? []).map { ($0.slug, $0.name) }) { first, _ in first }
                let abilityNames = Dictionary(
                    (detail?.abilities ?? []).map { ($0.slug, $0.name) }) { first, _ in first }

                return ShowdownPaste.ParsedSet(
                    species: speciesNames[member.pokemonID]
                        ?? detail.map { displayName($0.name) }
                        ?? "#\(member.pokemonID)",
                    nickname: exportableNickname(member.nickname),
                    // Not modelled by `TeamMember`, so never emitted. See the round-trip note.
                    gender: nil,
                    item: member.itemSlug.flatMap { $0.isEmpty ? nil : (itemNames[$0] ?? $0) },
                    ability: member.abilitySlug.isEmpty
                        ? nil : (abilityNames[member.abilitySlug] ?? member.abilitySlug),
                    level: member.level,
                    teraType: member.teraType.flatMap { $0.isEmpty ? nil : $0 },
                    nature: Nature(rawValue: member.nature) ?? .hardy,
                    evs: spread(member.evs, fallback: 0),
                    ivs: spread(member.ivs, fallback: 31),
                    moves: member.moves.map { moveNames[$0] ?? $0 }
                )
            })
    }

    /// `great-tusk` → `Great-Tusk`. Hyphens are kept because they are what separates a form
    /// (`Urshifu-Rapid-Strike`); ``key(_:)`` and Showdown's own importer both ignore them
    /// either way, so the difference is cosmetic.
    private static func displayName(_ slug: String) -> String {
        slug.split(separator: "-").map(\.capitalized).joined(separator: "-")
    }

    /// A nickname is free text and the header line is positional: `Chomp (Garchomp) @ Item`.
    /// A nickname carrying `(`, `)` or `@` would re-parse as a different species or a held
    /// item, so it is dropped rather than allowed to corrupt the set it labels.
    private static func exportableNickname(_ nickname: String?) -> String? {
        guard let nickname, !nickname.isEmpty else { return nil }
        return nickname.contains(where: { "()@".contains($0) }) ? nil : nickname
    }

    // MARK: Import

    /// One parsed set as a member of `slot`, with every value the server would otherwise 400 on
    /// already clamped: EVs to 252 per stat and 508 in total, IVs to 0–31, level to 1–100, moves
    /// to four, Tera type to the legal 19, nature to its lowercase `rawValue`.
    ///
    /// `detail` is the species this set resolved to — its Scarlet/Violet learnset and its
    /// abilities are what turn `"Swords Dance"` into `"swords-dance"`. A move or ability the
    /// learnset does not have is slugified rather than dropped: it is information the paste
    /// carried, the column is free text, and the editor renders an unknown slug readably.
    public static func member(
        from set: ShowdownPaste.ParsedSet,
        slot: Int,
        detail: PokemonDetail,
        items: [Item]
    ) -> TeamMember {
        let moveSlugs = Dictionary((detail.moves ?? []).map { (key($0.name), $0.slug) }) { first, _ in first }
        let abilitySlugs = Dictionary((detail.abilities ?? []).map { (key($0.name), $0.slug) }) { first, _ in first }
        let itemSlugs = Dictionary(items.map { (key($0.name), $0.slug) }) { first, _ in first }

        return TeamMember(
            slot: slot,
            pokemonID: detail.id,
            // Same 100-rune cap the server applies, counted in unicode scalars for the same
            // reason `TeamEditorScreen` does: Go counts runes, Swift's Character is a cluster.
            nickname: set.nickname.map { String($0.unicodeScalars.prefix(100).map(Character.init)) },
            // Lowercase. `displayName` here would be a 400.
            nature: set.nature.rawValue,
            abilitySlug: set.ability.map { abilitySlugs[key($0)] ?? slugify($0) }
                ?? detail.abilities?.first?.slug ?? "",
            itemSlug: set.item.map { itemSlugs[key($0)] ?? slugify($0) },
            teraType: set.teraType.flatMap { tera in
                teraTypes.first { key($0) == key(tera) }
            },
            level: min(100, max(1, set.level)),
            evs: dictionary(cappedEVs(set.evs)),
            ivs: dictionary(clamped(set.ivs, to: 0...31)),
            moves: set.moves.prefix(4).map { moveSlugs[key($0)] ?? slugify($0) }
        )
    }

    /// `Swords Dance` → `swords-dance`, the shape every real slug already has.
    ///
    /// Truncated to 50 unicode scalars, because that is the cap `validateMembers` in
    /// `backend/internal/api/teams.go` applies to `ability_slug` and to every move slug, and
    /// this is the one value on the import path that comes from the paste as free text. Real
    /// slugs run well under it; junk in an `Ability:` line does not, and an unbounded one would
    /// 400 the whole save — the failure every other clamp here exists to prevent. `item_slug`
    /// has no server-side length check, so it is left alone.
    private static func slugify(_ name: String) -> String {
        let cleaned = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let slug = String(cleaned).split(separator: "-").joined(separator: "-")
        // Trimmed after truncating, so a cut landing on a separator does not leave a trailing
        // hyphen that no real slug has.
        return String(String.UnicodeScalarView(slug.unicodeScalars.prefix(50)))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// 252 per stat, 508 in total — spent in `Stat.allCases` order, so an over-budget paste
    /// keeps its HP and Attack investment and loses the tail rather than being rejected whole.
    private static func cappedEVs(_ spread: StatSpread) -> StatSpread {
        var capped = StatSpread.zero
        var remaining = 508
        for stat in Stat.allCases {
            let value = max(0, min(spread[stat], 252, remaining))
            capped[stat] = value
            remaining -= value
        }
        return capped
    }

    private static func clamped(_ spread: StatSpread, to range: ClosedRange<Int>) -> StatSpread {
        var result = spread
        for stat in Stat.allCases {
            result[stat] = min(range.upperBound, max(range.lowerBound, spread[stat]))
        }
        return result
    }

    // MARK: Spread conversion

    /// `hp/atk/def/spa/spd/spe` — `Stat.rawValue` is already the JSONB key the column holds.
    private static func dictionary(_ spread: StatSpread) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: Stat.allCases.map { ($0.rawValue, spread[$0]) })
    }

    /// **Omitted IVs are 31, not 0.** A member row written before a column existed can be
    /// missing a key, and defaulting it to zero would silently gut the set.
    private static func spread(_ values: [String: Int], fallback: Int) -> StatSpread {
        var spread = StatSpread()
        for stat in Stat.allCases { spread[stat] = values[stat.rawValue] ?? fallback }
        return spread
    }
}
