import Foundation
import ShinyTrackerKit
import Testing

@testable import ShinyTrackerAPI

/// `ShowdownBridge` is import-only: a Showdown paste resolves to a Champions `TeamMember`, with
/// its EVs converted to Stat Points and its IVs and Tera type discarded. There is no export
/// path to pin a round trip against — see the "Import only" note on `ShowdownBridge` itself for
/// why not.

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

private func reimport(_ text: String, slot: Int = 1) throws -> TeamMember {
    let sets = try ShowdownPaste.parse(text)
    return ShowdownBridge.member(from: sets[0], slot: slot, detail: garchomp, items: items)
}

/// A pasted Scarlet/Violet set converts to a Champions member: EVs become stat points at the
/// HOME rate, IVs are discarded because Champions has none, and the Tera type is dropped
/// because Champions has no Terastallization.
@Test func aPastedSVSetConvertsToChampionsShape() throws {
    let member = try reimport("""
        Garchomp @ Rocky Helmet
        Ability: Rough Skin
        Tera Type: Steel
        EVs: 252 Atk / 4 SpD / 252 Spe
        Jolly Nature
        IVs: 0 SpA
        - Earthquake
        """)

    #expect(member.statPoints["atk"] == 32)
    #expect(member.statPoints["spe"] == 32)
    #expect(member.statPoints["spd"] == 1)
    #expect(member.statPoints.values.reduce(0, +) == 65)
    #expect(member.nature == "jolly")
    #expect(member.itemSlug == "rocky-helmet")
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
    // Lowercase on the wire. The paste's `Tera Type:` line is read but never carried into the
    // member — Champions has no Terastallization.
    #expect(imported.nature == "adamant")
}

/// Every value the server would answer with a 400 is clamped before it can be sent — including
/// a stat point total over 66, which `StatPoints.fromEVs` does not clamp on its own.
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
    // hp and atk are spent first (`Stat.allCases` order), so they keep their full 32; def gets
    // only what is left of the 66 budget, and spa is left with nothing.
    #expect(imported.statPoints["hp"] == 32)
    #expect(imported.statPoints["atk"] == 32)
    #expect(imported.statPoints["def"] == 2)
    #expect(imported.statPoints["spa"] == 0)
    #expect(imported.statPoints.values.reduce(0, +) == 66)
    #expect(imported.statPoints.values.allSatisfy { $0 <= 32 })
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
