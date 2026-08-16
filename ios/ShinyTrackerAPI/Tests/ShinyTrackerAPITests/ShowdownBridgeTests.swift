import Foundation
import ShinyTrackerKit
import Testing

@testable import ShinyTrackerAPI

/// The property that matters is the round trip: a saved member exported to a paste, parsed back
/// and resolved again must be the same member. `ShowdownPasteTests` pins the text format; this
/// pins the name/slug translation sitting on top of it.

private let garchomp = PokemonDetail(
    id: 445, name: "garchomp", spriteURL: "", shinySpriteURL: nil, types: ["dragon", "ground"],
    canBreed: true, isLegendary: false, isMythical: false, evolvesFromID: 444,
    evolvesFrom: [], evolvesTo: [], locations: [],
    stats: nil,
    abilities: [
        PokemonAbility(slug: "rough-skin", name: "Rough Skin", effect: "", slot: 1, isHidden: false),
        PokemonAbility(slug: "sand-veil", name: "Sand Veil", effect: "", slot: 3, isHidden: true),
    ],
    moves: [
        ("earthquake", "Earthquake"), ("dragon-claw", "Dragon Claw"),
        ("stealth-rock", "Stealth Rock"), ("swords-dance", "Swords Dance"), ("u-turn", "U-turn"),
    ].map {
        PokemonMove(
            slug: $0.0, name: $0.1, type: "ground", damageClass: "physical", power: 100,
            accuracy: 100, pp: 10, effect: "", method: "level-up", level: 1)
    })

private let items = [
    Item(slug: "rocky-helmet", name: "Rocky Helmet", spriteURL: "", description: ""),
    Item(slug: "life-orb", name: "Life Orb", spriteURL: "", description: ""),
]

private let member = TeamMember(
    slot: 1, pokemonID: 445, nickname: "Chomp", nature: "jolly", abilitySlug: "rough-skin",
    itemSlug: "rocky-helmet", teraType: "Steel", level: 50,
    evs: ["hp": 0, "atk": 252, "def": 0, "spa": 0, "spd": 4, "spe": 252],
    ivs: ["hp": 31, "atk": 31, "def": 31, "spa": 0, "spd": 31, "spe": 31],
    moves: ["earthquake", "dragon-claw", "stealth-rock", "swords-dance"])

private func reimport(_ text: String, slot: Int = 1) throws -> TeamMember {
    let sets = try ShowdownPaste.parse(text)
    return ShowdownBridge.member(from: sets[0], slot: slot, detail: garchomp, items: items)
}

@Test func exportedMemberRoundTrips() throws {
    let text = ShowdownBridge.paste(
        [member], species: [], items: items, details: [445: garchomp])

    #expect(text.hasPrefix("Chomp (Garchomp) @ Rocky Helmet\nAbility: Rough Skin\nLevel: 50"))
    #expect(text.contains("Tera Type: Steel"))
    #expect(text.contains("- Swords Dance"))
    #expect(try reimport(text) == member)
}

/// The fallback path: with no species list and no detail, every name is emitted as its slug —
/// and the slug still resolves back, because both sides normalise the same way.
@Test func slugFallbackStillRoundTrips() throws {
    let text = ShowdownBridge.paste([member], species: [], items: [], details: [:])

    #expect(text.contains("- swords-dance"))
    #expect(try reimport(text) == member)
}

/// A hand-written paste — display names throughout, no ids anywhere.
@Test func handWrittenPasteResolvesToSlugs() throws {
    let imported = try reimport(
        """
        Garchomp @ Life Orb
        Ability: Sand Veil
        Level: 50
        Tera Type: steel
        EVs: 252 Atk / 252 Spe
        Adamant Nature
        - U-turn
        """)

    #expect(imported.pokemonID == 445)
    #expect(imported.itemSlug == "life-orb")
    #expect(imported.abilitySlug == "sand-veil")
    #expect(imported.moves == ["u-turn"])
    // Lowercase on the wire, and the Tera type is normalised back to the legal Title-case.
    #expect(imported.nature == "adamant")
    #expect(imported.teraType == "Steel")
}

/// Every value the server would answer with a 400 is clamped before it can be sent.
@Test func illegalValuesAreClamped() throws {
    let imported = try reimport(
        """
        Garchomp
        Level: 250
        Tera Type: Cardboard
        EVs: 300 HP / 252 Atk / 252 Def / 252 SpA
        IVs: 99 Atk
        - Earthquake
        - Dragon Claw
        - Stealth Rock
        - Swords Dance
        - U-turn
        """)

    #expect(imported.level == 100)
    #expect(imported.teraType == nil)
    #expect(imported.evs["hp"] == 252)
    #expect(imported.evs.values.reduce(0, +) <= 508)
    #expect(imported.evs.values.allSatisfy { $0 <= 252 })
    #expect(imported.ivs["atk"] == 31)
    #expect(imported.moves.count == 4)
    // No `Ability:` line, so the species' first ability stands in rather than an empty slug.
    #expect(imported.abilitySlug == "rough-skin")
}

/// `ability_slug` and every move slug are capped at 50 runes by `validateMembers`, and both are
/// free text straight off the paste when the learnset does not recognise them. Unbounded, they
/// are the one untrusted value left that would 400 the save.
@Test func junkAbilityAndMoveSlugsAreCappedAtFifty() throws {
    let junk = String(repeating: "wobbuffet ", count: 12)
    let imported = try reimport(
        """
        Garchomp
        Ability: \(junk)
        - \(junk)
        """)

    #expect(imported.abilitySlug.unicodeScalars.count <= 50)
    #expect(imported.moves[0].unicodeScalars.count <= 50)
    // Truncation never leaves the trailing separator no real slug has.
    #expect(!imported.abilitySlug.hasSuffix("-"))
}

/// A nickname that would re-parse as a species or a held item is dropped, not exported.
@Test func hostileNicknameIsNotExported() throws {
    let hostile = TeamMember(
        slot: 1, pokemonID: 445, nickname: "Chomp (Ditto) @ Leftovers", nature: "hardy",
        abilitySlug: "rough-skin", level: 50, evs: [:], ivs: [:], moves: [])
    let text = ShowdownBridge.paste([hostile], species: [], items: [], details: [445: garchomp])

    #expect(text.hasPrefix("Garchomp\nAbility: Rough Skin"))
    #expect(try reimport(text).pokemonID == 445)
}
