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
/// **Import only.** The Showdown paste format encodes EVs, IVs and Tera types; Champions has
/// none of the three — it has one Stat Point pool, no IVs at all, and no Terastallization. A
/// paste can be read into that shape with a well-defined conversion (see ``member(from:slot:detail:items:)``),
/// but a Champions team cannot be honestly written back out as one: the result would advertise
/// an EV spread and IVs the team does not have. So there is no `paste(...)` here, and there
/// should not be one added back — restoring it re-introduces the lie.
public enum ShowdownBridge {
    /// Showdown's own normalisation: lowercase, and drop everything that is not a letter or a
    /// digit. `"Urshifu-Rapid-Strike"`, `"urshifu-rapid-strike"` and `"Urshifu Rapid Strike"`
    /// are one key, which is why a paste written by hand still resolves.
    public static func key(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    // MARK: Import

    /// One parsed set as a member of `slot`, with every value the server would otherwise 400 on
    /// already clamped: stat points to 32 per stat and 66 in total, level to 1–100, moves to
    /// four, nature to its lowercase `rawValue`. The paste's IV line and Tera type are discarded
    /// outright — Champions has neither.
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

        // Champions has no EVs and no IVs. A pasted mainline spread converts at Pokemon HOME's
        // own rate; the paste's IV line is discarded entirely, because every Champions Pokemon
        // calculates as though it had 31.
        let points = StatPoints.fromEVs(set.evs)

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
            level: min(100, max(1, set.level)),
            statPoints: dictionary(cappedTotal(points)),
            moves: set.moves.prefix(4).map { moveSlugs[key($0)] ?? slugify($0) }
        )
    }

    /// `Swords Dance` → `swords-dance`, the shape every real slug already has.
    ///
    /// Truncated to 50 unicode scalars, because that is the cap `validateMembers` in
    /// `backend/internal/api/teams.go` applies to `ability_slug`, `item_slug` and every move
    /// slug, and this is the one value on the import path that comes from the paste as free
    /// text. Real slugs run well under it; junk in an `Ability:` line does not, and an
    /// unbounded one would 400 the whole save — the failure every other clamp here exists to
    /// prevent. An item the catalogue does not hold still gets a manufactured slug, which the
    /// server stores as free text: `item_slug` has had no foreign key since migration 024.
    private static func slugify(_ name: String) -> String {
        let cleaned = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let slug = String(cleaned).split(separator: "-").joined(separator: "-")
        // Trimmed after truncating, so a cut landing on a separator does not leave a trailing
        // hyphen that no real slug has.
        return String(String.UnicodeScalarView(slug.unicodeScalars.prefix(50)))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// `fromEVs` clamps each stat to 32 but not the total. A paste is untrusted input —
    /// `ShowdownPaste.parse` does not validate it — so an over-cap spread can still exceed 66 in
    /// aggregate; spent in `Stat.allCases` order, the same order the old EV clamp used, so the
    /// result is deterministic.
    private static func cappedTotal(_ points: StatPoints) -> StatPoints {
        var capped = StatPoints.zero
        var remaining = StatPoints.maxTotal
        for stat in Stat.allCases {
            let value = max(0, min(points[stat], remaining))
            capped[stat] = value
            remaining -= value
        }
        return capped
    }

    // MARK: Wire conversion

    /// `hp/atk/def/spa/spd/spe` — `Stat.rawValue` is already the JSONB key the column holds.
    private static func dictionary(_ points: StatPoints) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: Stat.allCases.map { ($0.rawValue, points[$0]) })
    }
}
