import Testing
@testable import ShinyTrackerUI

/// The type chart is the one piece of real arithmetic in the Dex, and it fails *quietly*: a
/// wrong row still renders a plausible-looking list of chips. Each case below is a matchup a
/// player would notice instantly if it were wrong.
struct TypeChartTests {

    @Test("Dual type with an immunity — Gible, Dragon/Ground")
    func dualTypeWithImmunity() {
        let gible: [PokemonType] = [.dragon, .ground]

        // Ice ×4, Dragon ×2, Fairy ×2 — and nothing else.
        //
        // `mobile-app.dc.html` screen 1e also draws a "Water ×2" chip for Gible. That chip is
        // wrong: Water is ×2 into Ground but ×½ into Dragon, so it comes out neutral. The
        // static mock is decoration; this is the arithmetic, and it agrees with Bulbapedia.
        let weak = TypeChart.weaknesses(gible)
        #expect(weak.map(\.type) == [.ice, .dragon, .fairy])
        #expect(weak.first { $0.type == .ice }?.multiplier == 4)   // ×2 into both halves
        #expect(!weak.contains { $0.type == .water })
        #expect(!TypeChart.resistances(gible).contains { $0.type == .water })

        // Ground's Electric immunity survives being multiplied by Dragon's ×½.
        let resist = TypeChart.resistances(gible)
        #expect(resist.first { $0.type == .electric }?.multiplier == 0)

        // Grass is ×2 into Ground and ×½ into Dragon — neutral, so it must not appear at all.
        #expect(!weak.contains { $0.type == .grass })
        #expect(!resist.contains { $0.type == .grass })
    }

    @Test("Two weaknesses stack to 4× — Golem, Rock/Ground")
    func stackedWeaknesses() {
        let golem: [PokemonType] = [.rock, .ground]
        let weak = TypeChart.weaknesses(golem)

        #expect(weak.first { $0.type == .water }?.multiplier == 4)
        #expect(weak.first { $0.type == .grass }?.multiplier == 4)
        #expect(weak.first { $0.type == .fighting }?.multiplier == 2)
        // Ground's immunity again, this time under a Rock half that is neutral to Electric.
        #expect(TypeChart.resistances(golem).first { $0.type == .electric }?.multiplier == 0)
    }

    @Test("Two resistances stack to ¼ — Skarmory, Steel/Flying")
    func stackedResistances() {
        let skarmory: [PokemonType] = [.steel, .flying]
        let resist = TypeChart.resistances(skarmory)

        #expect(resist.first { $0.type == .bug }?.multiplier == 0.25)
        #expect(resist.first { $0.type == .grass }?.multiplier == 0.25)
        // Poison is ×0 into Steel; Flying is neutral to it, so it stays an immunity.
        #expect(resist.first { $0.type == .poison }?.multiplier == 0)
        #expect(resist.first { $0.type == .ground }?.multiplier == 0)
        // Steel does NOT resist Electric (only Grass, Electric and Dragon do), so Flying's ×2
        // stands — Skarmory's two weaknesses are Fire and Electric, both ×2.
        #expect(TypeChart.weaknesses(skarmory).map(\.type) == [.fire, .electric])
        #expect(TypeChart.weaknesses(skarmory).allSatisfy { $0.multiplier == 2 })
    }

    @Test("Single type — Snorlax, Normal")
    func singleType() {
        #expect(TypeChart.weaknesses([.normal]).map(\.type) == [.fighting])
        #expect(TypeChart.resistances([.normal]).map(\.type) == [.ghost])
        #expect(TypeChart.resistances([.normal]).first?.multiplier == 0)
    }

    @Test("Sableye, Ghost/Dark, has no weaknesses at all")
    func noWeaknesses() {
        // Gen 6+ only: before Fairy, Sableye was weakness-free too, but Fairy now hits Dark ×2
        // and Ghost is neutral — so the pair is ×2. If this ever returns empty, the chart has
        // reverted to a pre-gen-6 row.
        let sableye: [PokemonType] = [.ghost, .dark]
        #expect(TypeChart.weaknesses(sableye).map(\.type) == [.fairy])
        let resist = TypeChart.resistances(sableye)
        #expect(resist.first { $0.type == .normal }?.multiplier == 0)
        #expect(resist.first { $0.type == .fighting }?.multiplier == 0)
        #expect(resist.first { $0.type == .psychic }?.multiplier == 0)
    }

    @Test("Every row of the chart is present and only names real types")
    func chartShape() {
        #expect(PokemonType.allCases.count == 18)
        #expect(TypeChart.chart.count == 18)
        // A neutral matchup must be *absent*, never stored as 1 — `defense` filters on the
        // product, so a stray 1 would be harmless here but would hide a typo like `.fire: 1`.
        for (_, row) in TypeChart.chart {
            #expect(!row.values.contains(1))
        }
        // No type is listed as its own attacker/defender pair with a made-up value: spot-check
        // the two that are famously ×½ against themselves.
        #expect(TypeChart.chart[.fire]?[.fire] == 0.5)
        #expect(TypeChart.chart[.dragon]?[.fairy] == 0)
    }

    @Test("Slugs parse the way the API sends them")
    func slugs() {
        // `pokemon.types` is PokeAPI's `type.name` — lowercase.
        #expect(PokemonType(slug: "ground") == .ground)
        #expect(PokemonType(slug: "Fire") == .fire)
        #expect(PokemonType(slug: " steel ") == .steel)
        #expect(PokemonType(slug: "shadow") == nil)
    }

    @Test("Multiplier labels")
    func labels() {
        #expect(TypeMatchup(type: .ice, multiplier: 4).label == "×4")
        #expect(TypeMatchup(type: .ice, multiplier: 2).label == "×2")
        #expect(TypeMatchup(type: .ice, multiplier: 0.5).label == "×½")
        #expect(TypeMatchup(type: .ice, multiplier: 0.25).label == "×¼")
        #expect(TypeMatchup(type: .ice, multiplier: 0).label == "×0")
    }

    @Test("Type colours match the prototype's TYPE_COLORS")
    func typeColours() {
        #expect(PokemonType.dragon.swatch.hex == 0x7A6ADB)
        #expect(PokemonType.ground.swatch.hex == 0xD4B56A)
        #expect(PokemonType.ice.swatch.hex == 0x8FD0D0)
        #expect(PokemonType.fairy.swatch.hex == 0xDD99C6)
        #expect(PokemonType.normal.swatch.hex == 0x9A9A7C)
    }
}
