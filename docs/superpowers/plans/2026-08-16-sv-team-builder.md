# Scarlet/Violet Team Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, save, and import/export six-Pokémon Scarlet/Violet competitive teams in Showdown paste format.

**Architecture:** Pure logic (natures, stat maths, EV validation, the Showdown parser) lives in `ShinyTrackerKit`, which has a test target. Persistence is Postgres tables behind `/api/me/teams`, cached for offline *reads* via `SnapshotStore`. The iOS UI is a new `ios/App/Teams/` following the shape of `Hunt/`, `Dex/` and `Nuzlocke/`.

**Tech Stack:** Go 1.26 + chi + pgx (no ORM, `$1` placeholders) · Swift 6 / SwiftUI, iOS 26 · Swift Testing (`@Test`/`#expect`) · Postgres on Supabase.

## Global Constraints

Copied from `docs/superpowers/specs/2026-08-16-sv-team-builder-design.md`. Every task's requirements implicitly include these.

- **Scarlet/Violet only.** `game_id` is always `17`. No other game has moveset data.
- **EV caps:** 508 total, 252 per stat. **IV cap:** 31 per stat. Enforced in handler, Swift model, and UI.
- **Every handler scopes by `user_id` from the token**, never from a path or body parameter. RLS is enabled but bypassed by the backend's `postgres` role, so these `WHERE` clauses are the only isolation between users.
- **No damage calculation, no tiers, no usage data, no shiny filter.** Later sub-projects.
- **Items carry no effect data.** Effects belong to the damage calculator.
- **Go:** raw SQL, `$1/$2` placeholders, `gofmt` clean, `go vet` clean.
- **Swift:** pure logic goes in `ShinyTrackerKit` (has tests), never in a view model (no test target).
- **New API routes use `/api/me/*`**, matching the convention established when `/api/user/{id}/games` was collapsed.

## Prerequisite

**PR #61 (`chore/production-hardening`) must be merged before starting.** This plan depends on three things it introduces:

- `writeJSON(w, v)` in `backend/internal/api/handlers.go`
- the `/api/me/*` route convention
- `PreviewHarness` in `ios/App/PreviewHarness.swift`

## Decision: teams do NOT use `WriteQueue` in this slice

The spec left this open. Reading the code closes it: **teams are online-write only, snapshot-cached for reads.**

`PendingWrite` is hunt-scoped by construction — every entry carries `huntID: UUID`. Worse, `SnapshotStore` documents `.pendingWrites` as *"the one key here that is records, not cache… the only copy of encounters the server has never seen"* and requires that any change to `PendingWrite`'s shape be **migrated, never dropped**.

So offline team editing means migrating the app's most safety-critical persisted file, to serve a feature with zero users. That is a bad trade. Offline team writes get their own task after this slice ships, when the shape is known.

Reads are still offline: `SnapshotStore` caching is cheap and carries no such hazard.

## File Structure

**Create — `ShinyTrackerKit` (pure, tested):**
- `Sources/ShinyTrackerKit/Nature.swift` — the 25 natures and their stat modifiers
- `Sources/ShinyTrackerKit/StatCalculator.swift` — Gen 3+ stat formula
- `Sources/ShinyTrackerKit/PokemonSet.swift` — one built Pokémon; EV/IV validation
- `Sources/ShinyTrackerKit/ShowdownPaste.swift` — parser and exporter
- `Tests/ShinyTrackerKitTests/NatureTests.swift`
- `Tests/ShinyTrackerKitTests/StatCalculatorTests.swift`
- `Tests/ShinyTrackerKitTests/ShowdownPasteTests.swift`

**Create — shared fixture:**
- `shared/showdown_pastes.json`

**Create — backend:**
- `backend/migrations/023_teams.sql`
- `backend/cmd/seed_items/main.go`
- `backend/internal/api/teams.go`

**Create — iOS app:**
- `ios/App/Teams/TeamsModel.swift`
- `ios/App/Teams/TeamsScreen.swift`
- `ios/App/Teams/TeamEditorScreen.swift`
- `ios/App/Teams/MemberSheet.swift`
- `ios/App/Teams/TeamsPreviewHarness.swift`

**Modify:**
- `backend/internal/api/router.go` — six new routes
- `backend/internal/models/models.go` — `Team`, `TeamMember`, `Item`
- `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/Models.swift` — response types
- `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/APIClient.swift` — team methods
- `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/SnapshotStore.swift` — `.teams` key
- `ios/App/ShinyTrackerApp.swift` — Teams tab

---

### Task 1: Natures, stat maths, and EV validation

Pure value types with no dependencies. Everything else builds on these.

**Files:**
- Create: `ios/ShinyTrackerKit/Sources/ShinyTrackerKit/Nature.swift`
- Create: `ios/ShinyTrackerKit/Sources/ShinyTrackerKit/StatCalculator.swift`
- Create: `ios/ShinyTrackerKit/Sources/ShinyTrackerKit/PokemonSet.swift`
- Test: `ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/NatureTests.swift`
- Test: `ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/StatCalculatorTests.swift`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `enum Stat: String, CaseIterable, Sendable { case hp, atk, def, spa, spd, spe }`
  - `enum Nature: String, CaseIterable, Sendable` with `var raised: Stat?`, `var lowered: Stat?`, `func modifier(for: Stat) -> Double`
  - `struct StatSpread: Codable, Equatable, Sendable` with `subscript(Stat) -> Int`, `init(hp:atk:def:spa:spd:spe:)`, `static let zero`, `static let maxIVs`, `var total: Int`
  - `enum StatCalculator { static func value(base:iv:ev:level:nature:stat:) -> Int }`
  - `struct PokemonSet: Codable, Equatable, Sendable` with `func validate() throws`, `enum SetError: Error, Equatable`

- [ ] **Step 1: Write the failing nature test**

`ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/NatureTests.swift`:

```swift
import Testing
@testable import ShinyTrackerKit

@Test func thereAreExactlyTwentyFiveNatures() {
    #expect(Nature.allCases.count == 25)
}

@Test func aNeutralNatureModifiesNothing() {
    // Five natures raise and lower the same stat, so they are neutral.
    #expect(Nature.hardy.raised == nil)
    #expect(Nature.hardy.lowered == nil)
    for stat in Stat.allCases {
        #expect(Nature.hardy.modifier(for: stat) == 1.0)
    }
}

@Test func adamantRaisesAttackAndLowersSpecialAttack() {
    #expect(Nature.adamant.raised == .atk)
    #expect(Nature.adamant.lowered == .spa)
    #expect(Nature.adamant.modifier(for: .atk) == 1.1)
    #expect(Nature.adamant.modifier(for: .spa) == 0.9)
    #expect(Nature.adamant.modifier(for: .spe) == 1.0)
}

/// HP is never affected by nature. A table that raised it would silently
/// inflate every bulky set.
@Test func noNatureEverModifiesHP() {
    for nature in Nature.allCases {
        #expect(nature.modifier(for: .hp) == 1.0)
        #expect(nature.raised != .hp)
        #expect(nature.lowered != .hp)
    }
}

/// Exactly 20 natures modify stats; the other 5 are neutral.
@Test func exactlyTwentyNaturesAreNonNeutral() {
    let nonNeutral = Nature.allCases.filter { $0.raised != nil }
    #expect(nonNeutral.count == 20)
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `cd ios/ShinyTrackerKit && swift test --filter NatureTests`
Expected: FAIL — `cannot find 'Nature' in scope`

- [ ] **Step 3: Implement `Nature.swift`**

```swift
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
```

- [ ] **Step 4: Run the nature tests**

Run: `cd ios/ShinyTrackerKit && swift test --filter NatureTests`
Expected: PASS, 5 tests

- [ ] **Step 5: Write the failing stat test**

`ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/StatCalculatorTests.swift`:

```swift
import Testing
@testable import ShinyTrackerKit

/// Values cross-checked against the published Gen 3+ formula. These are the numbers
/// a competitive player will recognise on sight — a wrong one is visible immediately
/// to a user and invisible to a reviewer.
@Test func garchompMaxSpeedJolly() {
    // Garchomp base Spe 102, 31 IV, 252 EV, Jolly (+Spe), level 50.
    let value = StatCalculator.value(
        base: 102, iv: 31, ev: 252, level: 50, nature: .jolly, stat: .spe)
    #expect(value == 169)
}

@Test func garchompHPAtLevelFifty() {
    // Base HP 108. HP ignores nature entirely.
    let value = StatCalculator.value(
        base: 108, iv: 31, ev: 0, level: 50, nature: .jolly, stat: .hp)
    #expect(value == 183)
}

@Test func aLoweringNatureRoundsDown() {
    // Garchomp base SpA 80, Jolly lowers it. Core is 100, x0.9 = 90 exactly.
    let value = StatCalculator.value(
        base: 80, iv: 31, ev: 0, level: 50, nature: .jolly, stat: .spa)
    #expect(value == 90)
}

/// Truncation, not rounding. Base 95 Def at L50 gives a core of 115; x0.9 is 103.5,
/// and the game floors it. Rounding here would inflate one stat on most bulky spreads.
@Test func aLoweringNatureTruncatesRatherThanRounds() {
    let value = StatCalculator.value(
        base: 95, iv: 31, ev: 0, level: 50, nature: .lonely, stat: .def)
    #expect(value == 103)
}

@Test func levelOneHundredDoublesRoughly() {
    let value = StatCalculator.value(
        base: 102, iv: 31, ev: 252, level: 100, nature: .jolly, stat: .spe)
    #expect(value == 333)
}

/// Shedinja is the only species whose HP ignores the formula. It is exactly the kind
/// of special case a fixture catches and a reviewer does not.
@Test func shedinjaAlwaysHasOneHP() {
    let value = StatCalculator.value(
        base: 1, iv: 31, ev: 252, level: 50, nature: .hardy, stat: .hp, speciesID: 292)
    #expect(value == 1)
}
```

- [ ] **Step 6: Run it to make sure it fails**

Run: `cd ios/ShinyTrackerKit && swift test --filter StatCalculatorTests`
Expected: FAIL — `cannot find 'StatCalculator' in scope`

- [ ] **Step 7: Implement `StatCalculator.swift`**

```swift
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
```

- [ ] **Step 8: Run the stat tests**

Run: `cd ios/ShinyTrackerKit && swift test --filter StatCalculatorTests`
Expected: PASS, 6 tests

- [ ] **Step 9: Implement `PokemonSet.swift` with validation**

```swift
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
```

- [ ] **Step 10: Add validation tests to `StatCalculatorTests.swift`**

```swift
@Test func aLegalSpreadValidates() throws {
    let set = PokemonSet(
        speciesID: 445, speciesName: "garchomp", abilitySlug: "rough-skin",
        evs: StatSpread(atk: 252, spd: 4, spe: 252))
    try set.validate()          // must not throw
    #expect(set.evs.total == 508)
}

@Test func anOverCapSpreadIsRejected() {
    let set = PokemonSet(
        speciesID: 445, speciesName: "garchomp", abilitySlug: "rough-skin",
        evs: StatSpread(hp: 252, atk: 252, def: 252))
    #expect(throws: PokemonSet.SetError.evTotalTooHigh(756)) { try set.validate() }
}

@Test func moreThan252InOneStatIsRejected() {
    let set = PokemonSet(
        speciesID: 445, speciesName: "garchomp", abilitySlug: "rough-skin",
        evs: StatSpread(atk: 300))
    #expect(throws: PokemonSet.SetError.evStatTooHigh(.atk, 300)) { try set.validate() }
}

@Test func ivsDefaultToThirtyOneNotZero() {
    let set = PokemonSet(speciesID: 445, speciesName: "garchomp", abilitySlug: "rough-skin")
    for stat in Stat.allCases { #expect(set.ivs[stat] == 31) }
}
```

- [ ] **Step 11: Run the whole Kit suite**

Run: `cd ios/ShinyTrackerKit && swift test`
Expected: PASS — 75 existing + 14 new

- [ ] **Step 12: Commit**

```bash
git add ios/ShinyTrackerKit/Sources/ShinyTrackerKit/Nature.swift \
        ios/ShinyTrackerKit/Sources/ShinyTrackerKit/StatCalculator.swift \
        ios/ShinyTrackerKit/Sources/ShinyTrackerKit/PokemonSet.swift \
        ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/NatureTests.swift \
        ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/StatCalculatorTests.swift
git commit -m "feat(kit): natures, Gen 3+ stat formula, and EV/IV validation"
```

---

### Task 2: Showdown paste parser

The riskiest piece in the slice. Fixture-driven, mirroring `shared/odds_anchors.json`.

**Files:**
- Create: `shared/showdown_pastes.json`
- Create: `ios/ShinyTrackerKit/Sources/ShinyTrackerKit/ShowdownPaste.swift`
- Create: `ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/ShowdownPasteTests.swift`

**Interfaces:**
- Consumes: `PokemonSet`, `StatSpread`, `Stat`, `Nature` from Task 1
- Produces: `enum ShowdownPaste { static func parse(_ text: String) throws -> [ParsedSet]; static func export(_ sets: [ParsedSet]) -> String }`, `struct ParsedSet: Equatable, Sendable`, `enum ParseError: Error, Equatable`

**Why `ParsedSet` and not `PokemonSet`:** a paste names its species and moves as *display strings* ("Iron Valiant", "Swords Dance"). Resolving those to ids and slugs needs the database, which `ShinyTrackerKit` has no access to. The parser produces names; a later task resolves them.

- [ ] **Step 1: Write the fixture**

`shared/showdown_pastes.json`:

```json
{
  "cases": [
    {
      "name": "full set with every optional element",
      "paste": "Garchomp (M) @ Rocky Helmet\nAbility: Rough Skin\nLevel: 50\nTera Type: Steel\nEVs: 252 Atk / 4 SpD / 252 Spe\nJolly Nature\nIVs: 0 SpA\n- Earthquake\n- Dragon Claw\n- Stealth Rock\n- Swords Dance",
      "expected": [
        {
          "species": "Garchomp", "nickname": null, "gender": "M",
          "item": "Rocky Helmet", "ability": "Rough Skin",
          "level": 50, "teraType": "Steel", "nature": "jolly",
          "evs": {"hp": 0, "atk": 252, "def": 0, "spa": 0, "spd": 4, "spe": 252},
          "ivs": {"hp": 31, "atk": 31, "def": 31, "spa": 0, "spd": 31, "spe": 31},
          "moves": ["Earthquake", "Dragon Claw", "Stealth Rock", "Swords Dance"]
        }
      ]
    },
    {
      "name": "bare minimum — species only",
      "paste": "Gholdengo",
      "expected": [
        {
          "species": "Gholdengo", "nickname": null, "gender": null,
          "item": null, "ability": null, "level": 100, "teraType": null,
          "nature": "hardy",
          "evs": {"hp": 0, "atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0},
          "ivs": {"hp": 31, "atk": 31, "def": 31, "spa": 31, "spd": 31, "spe": 31},
          "moves": []
        }
      ]
    },
    {
      "name": "nickname with the species in parentheses",
      "paste": "Chomp (Garchomp) (M) @ Life Orb\nAbility: Rough Skin\n- Earthquake",
      "expected": [
        {
          "species": "Garchomp", "nickname": "Chomp", "gender": "M",
          "item": "Life Orb", "ability": "Rough Skin", "level": 100,
          "teraType": null, "nature": "hardy",
          "evs": {"hp": 0, "atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0},
          "ivs": {"hp": 31, "atk": 31, "def": 31, "spa": 31, "spd": 31, "spe": 31},
          "moves": ["Earthquake"]
        }
      ]
    },
    {
      "name": "hyphenated form name is not mistaken for a nickname",
      "paste": "Urshifu-Rapid-Strike @ Choice Scarf\nAbility: Unseen Fist\n- Surging Strikes\n- Close Combat\n- U-turn\n- Aqua Jet",
      "expected": [
        {
          "species": "Urshifu-Rapid-Strike", "nickname": null, "gender": null,
          "item": "Choice Scarf", "ability": "Unseen Fist", "level": 100,
          "teraType": null, "nature": "hardy",
          "evs": {"hp": 0, "atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0},
          "ivs": {"hp": 31, "atk": 31, "def": 31, "spa": 31, "spd": 31, "spe": 31},
          "moves": ["Surging Strikes", "Close Combat", "U-turn", "Aqua Jet"]
        }
      ]
    },
    {
      "name": "two sets separated by a blank line, CRLF endings",
      "paste": "Amoonguss @ Sitrus Berry\r\nAbility: Regenerator\r\n- Spore\r\n\r\nRillaboom @ Assault Vest\r\nAbility: Grassy Surge\r\n- Grassy Glide",
      "expected": [
        {
          "species": "Amoonguss", "nickname": null, "gender": null,
          "item": "Sitrus Berry", "ability": "Regenerator", "level": 100,
          "teraType": null, "nature": "hardy",
          "evs": {"hp": 0, "atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0},
          "ivs": {"hp": 31, "atk": 31, "def": 31, "spa": 31, "spd": 31, "spe": 31},
          "moves": ["Spore"]
        },
        {
          "species": "Rillaboom", "nickname": null, "gender": null,
          "item": "Assault Vest", "ability": "Grassy Surge", "level": 100,
          "teraType": null, "nature": "hardy",
          "evs": {"hp": 0, "atk": 0, "def": 0, "spa": 0, "spd": 0, "spe": 0},
          "ivs": {"hp": 31, "atk": 31, "def": 31, "spa": 31, "spd": 31, "spe": 31},
          "moves": ["Grassy Glide"]
        }
      ]
    }
  ]
}
```

- [ ] **Step 2: Write the failing parser test**

`ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/ShowdownPasteTests.swift`:

```swift
import Foundation
import Testing
@testable import ShinyTrackerKit

/// One entry of `shared/showdown_pastes.json`. The fixture is the source of truth: the
/// format is defined by someone else's software, so when this parser disagrees with the
/// fixture, fix the parser.
private struct PasteCase: Decodable {
    let name: String
    let paste: String
    let expected: [ExpectedSet]
}

private struct ExpectedSet: Decodable {
    let species: String
    let nickname: String?
    let gender: String?
    let item: String?
    let ability: String?
    let level: Int
    let teraType: String?
    let nature: String
    let evs: [String: Int]
    let ivs: [String: Int]
    let moves: [String]
}

private struct PasteFile: Decodable { let cases: [PasteCase] }

/// Same walk-up-to-repo-root trick as `Anchors.url()` in OddsAnchorsTests: the fixture is
/// deliberately outside the package so other languages can consume it later.
private func fixtureURL() -> URL? {
    var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    for _ in 0..<12 {
        let candidate = dir.appendingPathComponent("shared/showdown_pastes.json")
        if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        dir.deleteLastPathComponent()
    }
    return nil
}

private func loadCases() throws -> [PasteCase] {
    let url = try #require(fixtureURL(), "shared/showdown_pastes.json not found")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(PasteFile.self, from: data).cases
}

private func spread(_ dict: [String: Int]) -> StatSpread {
    var s = StatSpread.zero
    for stat in Stat.allCases { s[stat] = dict[stat.rawValue] ?? 0 }
    return s
}

@Test func everyFixtureCaseParses() throws {
    for testCase in try loadCases() {
        let parsed = try ShowdownPaste.parse(testCase.paste)
        #expect(parsed.count == testCase.expected.count, "\(testCase.name): set count")

        for (got, want) in zip(parsed, testCase.expected) {
            #expect(got.species == want.species, "\(testCase.name): species")
            #expect(got.nickname == want.nickname, "\(testCase.name): nickname")
            #expect(got.gender == want.gender, "\(testCase.name): gender")
            #expect(got.item == want.item, "\(testCase.name): item")
            #expect(got.ability == want.ability, "\(testCase.name): ability")
            #expect(got.level == want.level, "\(testCase.name): level")
            #expect(got.teraType == want.teraType, "\(testCase.name): tera")
            #expect(got.nature.rawValue == want.nature, "\(testCase.name): nature")
            #expect(got.evs == spread(want.evs), "\(testCase.name): EVs")
            #expect(got.ivs == spread(want.ivs), "\(testCase.name): IVs")
            #expect(got.moves == want.moves, "\(testCase.name): moves")
        }
    }
}

/// The single most common way a naive parser corrupts a set.
@Test func omittedIVsAreThirtyOneNotZero() throws {
    let parsed = try ShowdownPaste.parse("Garchomp\nIVs: 0 Atk")
    #expect(parsed[0].ivs.atk == 0)
    #expect(parsed[0].ivs.spe == 31)
    #expect(parsed[0].ivs.hp == 31)
}

@Test func anEmptyPasteIsAnError() {
    #expect(throws: ShowdownPaste.ParseError.empty) {
        try ShowdownPaste.parse("   \n\n  ")
    }
}

@Test func anUnknownNatureNamesTheLine() {
    #expect(throws: ShowdownPaste.ParseError.unknownNature("Sparkly")) {
        try ShowdownPaste.parse("Garchomp\nSparkly Nature")
    }
}
```

- [ ] **Step 3: Run it to make sure it fails**

Run: `cd ios/ShinyTrackerKit && swift test --filter ShowdownPasteTests`
Expected: FAIL — `cannot find 'ShowdownPaste' in scope`

- [ ] **Step 4: Implement the parser**

`ios/ShinyTrackerKit/Sources/ShinyTrackerKit/ShowdownPaste.swift`:

```swift
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
                // Base is maxIVs: a paste lists only the stats it changes, and every
                // stat it omits is 31.
                set.ivs = try parseSpread(value, into: .maxIVs)
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
            evs: .zero, ivs: .maxIVs, moves: [])
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
}
```

- [ ] **Step 5: Run the parser tests**

Run: `cd ios/ShinyTrackerKit && swift test --filter ShowdownPasteTests`
Expected: PASS, 4 tests

- [ ] **Step 6: Commit**

```bash
git add shared/showdown_pastes.json \
        ios/ShinyTrackerKit/Sources/ShinyTrackerKit/ShowdownPaste.swift \
        ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/ShowdownPasteTests.swift
git commit -m "feat(kit): Showdown paste parser, fixture-pinned"
```

---

### Task 3: Showdown paste exporter and round-trip

**Files:**
- Modify: `ios/ShinyTrackerKit/Sources/ShinyTrackerKit/ShowdownPaste.swift`
- Modify: `ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/ShowdownPasteTests.swift`

**Interfaces:**
- Consumes: `ShowdownPaste.ParsedSet` from Task 2
- Produces: `ShowdownPaste.export(_ sets: [ParsedSet]) -> String`

- [ ] **Step 1: Write the failing round-trip test**

Append to `ShowdownPasteTests.swift`:

```swift
/// The property that actually matters. Parse-only tests pass happily while export
/// silently drops the Tera type.
@Test func everyFixtureCaseRoundTrips() throws {
    for testCase in try loadCases() {
        let parsed = try ShowdownPaste.parse(testCase.paste)
        let exported = ShowdownPaste.export(parsed)
        let reparsed = try ShowdownPaste.parse(exported)
        #expect(reparsed == parsed, "\(testCase.name) did not round-trip:\n\(exported)")
    }
}

@Test func exportOmitsEverythingThatIsDefault() throws {
    let parsed = try ShowdownPaste.parse("Gholdengo")
    // No item, no ability, no EV line, no nature line, no moves — a bare species
    // must not export six lines of zeroes.
    #expect(ShowdownPaste.export(parsed) == "Gholdengo")
}

@Test func exportWritesTheSpreadInStatOrder() throws {
    let parsed = try ShowdownPaste.parse(
        "Garchomp\nEVs: 252 Spe / 252 Atk\nJolly Nature")
    #expect(ShowdownPaste.export(parsed).contains("EVs: 252 Atk / 252 Spe"))
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `cd ios/ShinyTrackerKit && swift test --filter ShowdownPasteTests`
Expected: FAIL — `type 'ShowdownPaste' has no member 'export'`

- [ ] **Step 3: Implement `export`**

Add to `ShowdownPaste`:

```swift
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
```

- [ ] **Step 4: Run the tests**

Run: `cd ios/ShinyTrackerKit && swift test --filter ShowdownPasteTests`
Expected: PASS, 7 tests

- [ ] **Step 5: Run the whole Kit suite**

Run: `cd ios/ShinyTrackerKit && swift test`
Expected: PASS — no regressions in the 75 existing tests

- [ ] **Step 6: Commit**

```bash
git add ios/ShinyTrackerKit/Sources/ShinyTrackerKit/ShowdownPaste.swift \
        ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/ShowdownPasteTests.swift
git commit -m "feat(kit): Showdown paste export with round-trip tests"
```

---

### Task 4: Database schema

**Files:**
- Create: `backend/migrations/023_teams.sql`
- Modify: `backend/schema.sql` — append the same DDL

**Interfaces:**
- Produces: tables `items`, `teams`, `team_members`

- [ ] **Step 1: Write the migration**

`backend/migrations/023_teams.sql`:

```sql
-- Competitive team builder, sub-project 1. Scarlet/Violet only.
-- See docs/superpowers/specs/2026-08-16-sv-team-builder-design.md

-- Held items. Seeded from PokeAPI by cmd/seed_items.
-- No effect data on purpose: Choice Band's x1.5 belongs to the damage calculator,
-- where it can be tested against a reference. An unused column now is a guess the
-- calculator would have to unpick.
CREATE TABLE IF NOT EXISTS items (
    slug        TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    sprite_url  TEXT,
    description TEXT
);

CREATE TABLE IF NOT EXISTS teams (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    -- Always 17 (Scarlet/Violet) today. Stored anyway: adding it later means a
    -- migration over live rows with no correct default.
    game_id    INTEGER NOT NULL REFERENCES games(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_teams_user ON teams (user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS team_members (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id      UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    slot         SMALLINT NOT NULL CHECK (slot BETWEEN 1 AND 6),
    pokemon_id   INTEGER NOT NULL REFERENCES pokemon(id),
    nickname     TEXT,
    nature       TEXT NOT NULL,
    ability_slug TEXT NOT NULL,
    item_slug    TEXT REFERENCES items(slug),
    tera_type    TEXT,
    level        SMALLINT NOT NULL DEFAULT 50 CHECK (level BETWEEN 1 AND 100),
    -- Read and written as a whole spread, never queried per stat — same reasoning
    -- that put hunt_parameters in JSONB. The 508 total cannot be expressed as a
    -- cheap CHECK over JSONB, so it is enforced in the handler and the client.
    evs          JSONB NOT NULL DEFAULT '{}'::jsonb,
    ivs          JSONB NOT NULL DEFAULT '{}'::jsonb,
    moves        TEXT[] NOT NULL DEFAULT '{}',
    UNIQUE (team_id, slot)
);

CREATE INDEX IF NOT EXISTS idx_team_members_team ON team_members (team_id, slot);

ALTER TABLE items        ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams        ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_members ENABLE ROW LEVEL SECURITY;
```

- [ ] **Step 2: Append the same DDL to `backend/schema.sql`**

Copy the entire contents of `023_teams.sql` (minus the leading comment block) to the end of `backend/schema.sql`. `schema.sql` is the full-DDL source of truth; a migration that is not reflected there means a fresh database is missing the table.

- [ ] **Step 3: Verify it applies to a scratch database**

Run: `psql "$DATABASE_URL_SCRATCH" -f backend/migrations/023_teams.sql`
Expected: `CREATE TABLE` ×3, `CREATE INDEX` ×2, `ALTER TABLE` ×3, no errors.

**Do not apply this to production yet.** It is applied in Task 6, once a seeder exists to fill `items`.

- [ ] **Step 4: Commit**

```bash
git add backend/migrations/023_teams.sql backend/schema.sql
git commit -m "feat(db): teams, team_members and items tables"
```

---

### Task 5: Item seeder

**Files:**
- Create: `backend/cmd/seed_items/main.go`
- Modify: `backend/CLAUDE.md` — add to the seed command list

**Interfaces:**
- Consumes: `items` table from Task 4
- Produces: populated `items` table

- [ ] **Step 1: Write the seeder**

`backend/cmd/seed_items/main.go`:

```go
// cmd/seed_items seeds held items from PokeAPI.
//
// RUNBOOK: run after migrations/023_teams.sql. Safe to re-run — every write is an
// upsert on the slug, which is PokeAPI's own stable identifier.
//
// Only the competitively relevant categories are fetched. PokeAPI carries ~2000 items
// including every berry, TM and key item; a team builder needs the ~100 a set can hold.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"time"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

// PokeAPI item categories a held item can come from.
var heldItemCategories = []string{
	"held-items", "choice", "type-enhancement", "bad-held-items",
	"training", "species-specific", "type-protection", "picky-healing",
}

var httpClient = &http.Client{Timeout: 30 * time.Second}

type categoryResponse struct {
	Items []struct {
		Name string `json:"name"`
		URL  string `json:"url"`
	} `json:"items"`
}

type itemResponse struct {
	Name    string `json:"name"`
	Sprites struct {
		Default string `json:"default"`
	} `json:"sprites"`
	Names []struct {
		Name     string `json:"name"`
		Language struct {
			Name string `json:"name"`
		} `json:"language"`
	} `json:"names"`
	EffectEntries []struct {
		ShortEffect string `json:"short_effect"`
		Language    struct {
			Name string `json:"name"`
		} `json:"language"`
	} `json:"effect_entries"`
}

func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal(err)
	}
	defer database.CloseDB()

	seen := map[string]bool{}
	total := 0

	for _, category := range heldItemCategories {
		url := fmt.Sprintf("https://pokeapi.co/api/v2/item-category/%s", category)
		var cat categoryResponse
		if err := getJSON(url, &cat); err != nil {
			log.Printf("category %s: %v", category, err)
			continue
		}

		for _, ref := range cat.Items {
			if seen[ref.Name] {
				continue
			}
			seen[ref.Name] = true

			var item itemResponse
			if err := getJSON(ref.URL, &item); err != nil {
				log.Printf("item %s: %v", ref.Name, err)
				continue
			}

			if err := upsert(item); err != nil {
				log.Printf("upsert %s: %v", ref.Name, err)
				continue
			}
			total++
			time.Sleep(100 * time.Millisecond) // same courtesy delay as cmd/seed
		}
	}

	log.Printf("seeded %d items", total)
}

func getJSON(url string, into any) error {
	resp, err := httpClient.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("status %d", resp.StatusCode)
	}
	return json.NewDecoder(resp.Body).Decode(into)
}

func upsert(item itemResponse) error {
	displayName := item.Name
	for _, n := range item.Names {
		if n.Language.Name == "en" {
			displayName = n.Name
			break
		}
	}

	description := ""
	for _, e := range item.EffectEntries {
		if e.Language.Name == "en" {
			description = e.ShortEffect
			break
		}
	}

	_, err := database.DB.Exec(context.Background(),
		`INSERT INTO items (slug, name, sprite_url, description)
		 VALUES ($1, $2, $3, $4)
		 ON CONFLICT (slug) DO UPDATE SET
		   name = EXCLUDED.name,
		   sprite_url = EXCLUDED.sprite_url,
		   description = EXCLUDED.description`,
		item.Name, displayName, item.Sprites.Default, description)
	return err
}
```

- [ ] **Step 2: Build and vet**

Run: `cd backend && gofmt -w ./cmd/seed_items && go build ./... && go vet ./...`
Expected: no output

- [ ] **Step 3: Document it**

Add to the seed command list in `backend/CLAUDE.md`:

```bash
go run ./cmd/seed_items/main.go       # Seed held items from PokeAPI (after migration 023)
```

- [ ] **Step 4: Commit**

```bash
git add backend/cmd/seed_items/main.go backend/CLAUDE.md
git commit -m "feat(backend): held item seeder"
```

---

### Task 6: Apply the migration and seed items to production

The first task that touches live data. Separated from Task 4 and 5 so a reviewer can reject the schema without rejecting a production write.

- [ ] **Step 1: Apply the migration**

Run migration `023_teams.sql` against production. Prefer Supabase's `apply_migration` so the ledger records it — the recorded migration list is already far behind the 22 files in `backend/migrations/`, and every one applied ad hoc widens that gap.

- [ ] **Step 2: Verify the tables exist and are empty**

```sql
SELECT
  (SELECT count(*) FROM items)        AS items,
  (SELECT count(*) FROM teams)        AS teams,
  (SELECT count(*) FROM team_members) AS members;
```

Expected: `0, 0, 0`

- [ ] **Step 3: Seed items**

Run: `cd backend && go run ./cmd/seed_items/main.go`
Expected: log line `seeded N items`, N between 80 and 200.

- [ ] **Step 4: Spot-check the data**

```sql
SELECT slug, name FROM items
WHERE slug IN ('choice-band','life-orb','leftovers','rocky-helmet','focus-sash')
ORDER BY slug;
```

Expected: five rows with human-readable names (`Choice Band`, not `choice-band`).

- [ ] **Step 5: No commit** — this task changes no files.

---

### Task 7: Teams API

**Files:**
- Create: `backend/internal/api/teams.go`
- Modify: `backend/internal/api/router.go`
- Test: `backend/internal/api/teams_test.go`

**Interfaces:**
- Consumes: tables from Task 4; `writeJSON` from PR #61
- Produces: `GET/POST /api/me/teams`, `GET/PATCH/DELETE /api/me/teams/{id}`, `GET /api/items`

- [ ] **Step 1: Write the failing validation test**

`backend/internal/api/teams_test.go`:

```go
package api

import "testing"

func TestEVSpreadValid(t *testing.T) {
	cases := []struct {
		name string
		evs  map[string]int
		want bool
	}{
		{"empty is fine", map[string]int{}, true},
		{"exactly 508 total", map[string]int{"atk": 252, "spe": 252, "spd": 4}, true},
		{"509 is over the cap", map[string]int{"atk": 252, "spe": 252, "spd": 5}, false},
		{"253 in one stat", map[string]int{"atk": 253}, false},
		{"negative", map[string]int{"atk": -4}, false},
		{"unknown stat key", map[string]int{"luck": 4}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := evSpreadValid(tc.evs); got != tc.want {
				t.Errorf("evSpreadValid(%v) = %v, want %v", tc.evs, got, tc.want)
			}
		})
	}
}

func TestIVSpreadValid(t *testing.T) {
	cases := []struct {
		name string
		ivs  map[string]int
		want bool
	}{
		{"empty is fine", map[string]int{}, true},
		{"all 31", map[string]int{"hp": 31, "atk": 31, "spe": 31}, true},
		{"zero is legal", map[string]int{"atk": 0}, true},
		{"32 is not", map[string]int{"atk": 32}, false},
		{"negative", map[string]int{"atk": -1}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := ivSpreadValid(tc.ivs); got != tc.want {
				t.Errorf("ivSpreadValid(%v) = %v, want %v", tc.ivs, got, tc.want)
			}
		})
	}
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `cd backend && go test ./internal/api/ -run 'TestEVSpreadValid|TestIVSpreadValid'`
Expected: FAIL — `undefined: evSpreadValid`

- [ ] **Step 3: Implement `teams.go`**

```go
package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"

	"github.com/casper/shinytracker/internal/database"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

// scarletVioletGameID is the only game this slice supports. Scarlet/Violet is the
// only Switch title with moveset data seeded, and it is where current VGC is played.
const scarletVioletGameID = 17

// validStats is the closed set of EV/IV keys, matching Stat.rawValue in ShinyTrackerKit.
var validStats = map[string]bool{
	"hp": true, "atk": true, "def": true, "spa": true, "spd": true, "spe": true,
}

// evSpreadValid enforces the game's own caps: 508 total, 252 per stat.
//
// Also enforced in the Swift model and the UI. Triplication is deliberate: the
// database cannot express "sum of JSONB values <= 508" cheaply, and a set that breaks
// the cap exports to a paste Showdown rejects — a silent corruption of the one output
// that has to interoperate.
func evSpreadValid(evs map[string]int) bool {
	total := 0
	for stat, value := range evs {
		if !validStats[stat] || value < 0 || value > 252 {
			return false
		}
		total += value
	}
	return total <= 508
}

func ivSpreadValid(ivs map[string]int) bool {
	for stat, value := range ivs {
		if !validStats[stat] || value < 0 || value > 31 {
			return false
		}
	}
	return true
}

type TeamMemberPayload struct {
	Slot        int            `json:"slot"`
	PokemonID   int            `json:"pokemon_id"`
	Nickname    *string        `json:"nickname"`
	Nature      string         `json:"nature"`
	AbilitySlug string         `json:"ability_slug"`
	ItemSlug    *string        `json:"item_slug"`
	TeraType    *string        `json:"tera_type"`
	Level       int            `json:"level"`
	EVs         map[string]int `json:"evs"`
	IVs         map[string]int `json:"ivs"`
	Moves       []string       `json:"moves"`
}

type TeamPayload struct {
	ID      string              `json:"id"`
	Name    string              `json:"name"`
	GameID  int                 `json:"game_id"`
	Members []TeamMemberPayload `json:"members"`
}

const maxTeamNameLength = 100

// validateMembers checks everything the database cannot. Returns a user-facing message
// on failure, empty on success.
func validateMembers(members []TeamMemberPayload) string {
	if len(members) > 6 {
		return "a team holds at most six Pokemon"
	}
	slots := map[int]bool{}
	for _, m := range members {
		if m.Slot < 1 || m.Slot > 6 {
			return "slot must be between 1 and 6"
		}
		if slots[m.Slot] {
			return "two members share a slot"
		}
		slots[m.Slot] = true
		if m.PokemonID <= 0 {
			return "pokemon_id is required"
		}
		if len(m.Moves) > 4 {
			return "a Pokemon knows at most four moves"
		}
		if m.Level < 1 || m.Level > 100 {
			return "level must be between 1 and 100"
		}
		if !evSpreadValid(m.EVs) {
			return "EVs exceed the 508 total or 252 per-stat cap"
		}
		if !ivSpreadValid(m.IVs) {
			return "IVs must be between 0 and 31"
		}
	}
	return ""
}

func GetTeamsHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	teams, err := loadTeams(context.Background(), userID, "")
	if err != nil {
		http.Error(w, "Failed to load teams", http.StatusInternalServerError)
		return
	}
	writeJSON(w, teams)
}

func GetTeamHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	teams, err := loadTeams(context.Background(), userID, chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, "Failed to load team", http.StatusInternalServerError)
		return
	}
	if len(teams) == 0 {
		http.Error(w, "Team not found", http.StatusNotFound)
		return
	}
	writeJSON(w, teams[0])
}

// loadTeams returns the caller's teams with members attached. A blank teamID means all.
// Scoped by user_id in the WHERE clause, never by a path parameter.
func loadTeams(ctx context.Context, userID, teamID string) ([]TeamPayload, error) {
	query := `SELECT id, name, game_id FROM teams WHERE user_id = $1`
	args := []any{userID}
	if teamID != "" {
		query += ` AND id = $2`
		args = append(args, teamID)
	}
	query += ` ORDER BY updated_at DESC`

	rows, err := database.DB.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	teams := []TeamPayload{}
	ids := []string{}
	for rows.Next() {
		var t TeamPayload
		if err := rows.Scan(&t.ID, &t.Name, &t.GameID); err != nil {
			return nil, err
		}
		t.Members = []TeamMemberPayload{}
		teams = append(teams, t)
		ids = append(ids, t.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(teams) == 0 {
		return teams, nil
	}

	memberRows, err := database.DB.Query(ctx,
		`SELECT team_id, slot, pokemon_id, nickname, nature, ability_slug, item_slug,
		        tera_type, level, evs, ivs, moves
		   FROM team_members WHERE team_id = ANY($1::uuid[]) ORDER BY team_id, slot`, ids)
	if err != nil {
		return nil, err
	}
	defer memberRows.Close()

	byTeam := map[string][]TeamMemberPayload{}
	for memberRows.Next() {
		var teamID string
		var m TeamMemberPayload
		if err := memberRows.Scan(&teamID, &m.Slot, &m.PokemonID, &m.Nickname, &m.Nature,
			&m.AbilitySlug, &m.ItemSlug, &m.TeraType, &m.Level, &m.EVs, &m.IVs, &m.Moves); err != nil {
			return nil, err
		}
		byTeam[teamID] = append(byTeam[teamID], m)
	}
	if err := memberRows.Err(); err != nil {
		return nil, err
	}
	for i := range teams {
		if members, ok := byTeam[teams[i].ID]; ok {
			teams[i].Members = members
		}
	}
	return teams, nil
}

func CreateTeamHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	var req TeamPayload
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.Name == "" || len([]rune(req.Name)) > maxTeamNameLength {
		http.Error(w, "name is required and must be 100 characters or fewer", http.StatusBadRequest)
		return
	}
	if msg := validateMembers(req.Members); msg != "" {
		http.Error(w, msg, http.StatusBadRequest)
		return
	}

	tx, err := database.DB.Begin(context.Background())
	if err != nil {
		http.Error(w, "Failed to start transaction", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(context.Background())

	var teamID string
	if err := tx.QueryRow(context.Background(),
		`INSERT INTO teams (user_id, name, game_id) VALUES ($1, $2, $3) RETURNING id`,
		userID, req.Name, scarletVioletGameID).Scan(&teamID); err != nil {
		http.Error(w, "Failed to create team", http.StatusInternalServerError)
		return
	}
	if err := insertMembers(context.Background(), tx, teamID, req.Members); err != nil {
		http.Error(w, "Failed to save team members", http.StatusInternalServerError)
		return
	}
	if err := tx.Commit(context.Background()); err != nil {
		http.Error(w, "Failed to commit transaction", http.StatusInternalServerError)
		return
	}

	teams, err := loadTeams(context.Background(), userID, teamID)
	if err != nil || len(teams) == 0 {
		http.Error(w, "Failed to reload team", http.StatusInternalServerError)
		return
	}
	writeJSON(w, teams[0])
}

func UpdateTeamHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	teamID := chi.URLParam(r, "id")

	var req struct {
		Name    *string             `json:"name"`
		Members []TeamMemberPayload `json:"members"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.Name != nil && (*req.Name == "" || len([]rune(*req.Name)) > maxTeamNameLength) {
		http.Error(w, "name must be 1 to 100 characters", http.StatusBadRequest)
		return
	}
	if msg := validateMembers(req.Members); msg != "" {
		http.Error(w, msg, http.StatusBadRequest)
		return
	}

	tx, err := database.DB.Begin(context.Background())
	if err != nil {
		http.Error(w, "Failed to start transaction", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(context.Background())

	// Ownership and existence in one statement, scoped by user_id.
	var found string
	err = tx.QueryRow(context.Background(),
		`UPDATE teams SET name = COALESCE($1, name), updated_at = now()
		  WHERE id = $2 AND user_id = $3 RETURNING id`,
		req.Name, teamID, userID).Scan(&found)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Team not found", http.StatusNotFound)
			return
		}
		http.Error(w, "Failed to update team", http.StatusInternalServerError)
		return
	}

	// Members are replaced wholesale. A team is edited as a unit, six slots are small,
	// and per-slot patching invents the merge problem the encounter-delta work already
	// showed is expensive to get right.
	if _, err := tx.Exec(context.Background(),
		`DELETE FROM team_members WHERE team_id = $1`, teamID); err != nil {
		http.Error(w, "Failed to replace members", http.StatusInternalServerError)
		return
	}
	if err := insertMembers(context.Background(), tx, teamID, req.Members); err != nil {
		http.Error(w, "Failed to save team members", http.StatusInternalServerError)
		return
	}
	if err := tx.Commit(context.Background()); err != nil {
		http.Error(w, "Failed to commit transaction", http.StatusInternalServerError)
		return
	}

	teams, err := loadTeams(context.Background(), userID, teamID)
	if err != nil || len(teams) == 0 {
		http.Error(w, "Failed to reload team", http.StatusInternalServerError)
		return
	}
	writeJSON(w, teams[0])
}

func insertMembers(ctx context.Context, tx pgx.Tx, teamID string, members []TeamMemberPayload) error {
	for _, m := range members {
		evs := m.EVs
		if evs == nil {
			evs = map[string]int{}
		}
		ivs := m.IVs
		if ivs == nil {
			ivs = map[string]int{}
		}
		moves := m.Moves
		if moves == nil {
			moves = []string{}
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO team_members
			   (team_id, slot, pokemon_id, nickname, nature, ability_slug, item_slug,
			    tera_type, level, evs, ivs, moves)
			 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
			teamID, m.Slot, m.PokemonID, m.Nickname, m.Nature, m.AbilitySlug,
			m.ItemSlug, m.TeraType, m.Level, evs, ivs, moves); err != nil {
			return err
		}
	}
	return nil
}

func DeleteTeamHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	tag, err := database.DB.Exec(context.Background(),
		`DELETE FROM teams WHERE id = $1 AND user_id = $2`, chi.URLParam(r, "id"), userID)
	if err != nil {
		http.Error(w, "Failed to delete team", http.StatusInternalServerError)
		return
	}
	if tag.RowsAffected() == 0 {
		http.Error(w, "Team not found", http.StatusNotFound)
		return
	}
	writeJSON(w, map[string]string{"message": "Team deleted successfully"})
}

// GetItemsHandler serves the static held-item list. Public and unauthenticated, like
// /api/games and /api/methods.
func GetItemsHandler(w http.ResponseWriter, r *http.Request) {
	rows, err := database.DB.Query(context.Background(),
		`SELECT slug, name, COALESCE(sprite_url,''), COALESCE(description,'')
		   FROM items ORDER BY name`)
	if err != nil {
		http.Error(w, "Failed to load items", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type item struct {
		Slug        string `json:"slug"`
		Name        string `json:"name"`
		SpriteURL   string `json:"sprite_url"`
		Description string `json:"description"`
	}
	items := []item{}
	for rows.Next() {
		var i item
		if err := rows.Scan(&i.Slug, &i.Name, &i.SpriteURL, &i.Description); err != nil {
			continue
		}
		items = append(items, i)
	}
	writeJSON(w, items)
}
```

- [ ] **Step 4: Run the validation tests**

Run: `cd backend && go test ./internal/api/ -run 'TestEVSpreadValid|TestIVSpreadValid' -v`
Expected: PASS, 11 subtests

- [ ] **Step 5: Wire the routes**

In `backend/internal/api/router.go`, add to the public group (beside `r.Get("/methods", ...)`):

```go
		r.Get("/items", GetItemsHandler)
```

And inside the authenticated group (beside the `/me/games` routes):

```go
			r.Get("/me/teams", GetTeamsHandler)
			r.Post("/me/teams", CreateTeamHandler)
			r.Get("/me/teams/{id}", GetTeamHandler)
			r.Patch("/me/teams/{id}", UpdateTeamHandler)
			r.Delete("/me/teams/{id}", DeleteTeamHandler)
```

- [ ] **Step 6: Build, vet, test**

Run: `cd backend && gofmt -l ./internal ./cmd && go build ./... && go vet ./... && go test ./...`
Expected: gofmt silent, all tests pass

- [ ] **Step 7: Commit**

```bash
git add backend/internal/api/teams.go backend/internal/api/teams_test.go backend/internal/api/router.go
git commit -m "feat(api): teams CRUD and held item list"
```

---

### Task 8: Swift API client

**Files:**
- Modify: `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/Models.swift`
- Modify: `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/APIClient.swift`
- Modify: `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/SnapshotStore.swift`
- Test: `ios/ShinyTrackerAPI/Tests/ShinyTrackerAPITests/DecodingTests.swift`

**Interfaces:**
- Consumes: routes from Task 7
- Produces: `Team`, `TeamMember`, `Item`, `CreateTeamRequest`, `UpdateTeamRequest`; `APIClient.teams()`, `.createTeam(_:)`, `.updateTeam(id:_:)`, `.deleteTeam(id:)`, `.items()`; `SnapshotKey.teams`

- [ ] **Step 1: Write the failing decode test**

Append to `ios/ShinyTrackerAPI/Tests/ShinyTrackerAPITests/DecodingTests.swift`:

```swift
@Test func decodesATeamWithMembers() throws {
    let json = """
        {"id":"aaaaaaaa-0000-4000-8000-00000000aaaa","name":"Reg H core","game_id":17,
         "members":[
           {"slot":1,"pokemon_id":445,"nickname":null,"nature":"jolly",
            "ability_slug":"rough-skin","item_slug":"rocky-helmet","tera_type":"Steel",
            "level":50,"evs":{"atk":252,"spe":252,"spd":4},
            "ivs":{"spa":0},"moves":["earthquake","dragon-claw"]}]}
        """
    let team = try JSONDecoder().decode(Team.self, from: Data(json.utf8))
    #expect(team.name == "Reg H core")
    #expect(team.gameID == 17)
    #expect(team.members.count == 1)
    #expect(team.members[0].pokemonID == 445)
    #expect(team.members[0].evs["atk"] == 252)
    #expect(team.members[0].ivs["spa"] == 0)
    #expect(team.members[0].moves == ["earthquake", "dragon-claw"])
}

/// A team with no members must decode as an empty array, not fail. Go sends `[]` here
/// because the handler initialises the slice, but a null must not be fatal either.
@Test func decodesATeamWithNoMembers() throws {
    let json = """
        {"id":"aaaaaaaa-0000-4000-8000-00000000aaaa","name":"Empty","game_id":17,"members":[]}
        """
    let team = try JSONDecoder().decode(Team.self, from: Data(json.utf8))
    #expect(team.members.isEmpty)
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `cd ios/ShinyTrackerAPI && swift test --filter decodesATeam`
Expected: FAIL — `cannot find 'Team' in scope`

- [ ] **Step 3: Add the models**

Append to `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/Models.swift`:

```swift
// MARK: - Teams

/// `GET /api/me/teams` — `api.TeamPayload`.
public struct Team: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    /// Always 17 (Scarlet/Violet) in this slice. Carried so a later game does not need
    /// a migration over live rows.
    public let gameID: Int
    public let members: [TeamMember]

    enum CodingKeys: String, CodingKey {
        case id, name, members
        case gameID = "game_id"
    }
}

/// One slot of a team — `api.TeamMemberPayload`.
///
/// `evs` and `ivs` are `[String: Int]` rather than a typed spread because they cross the
/// wire as JSONB and the keys are the closed set `hp/atk/def/spa/spd/spe`. Callers convert
/// to `ShinyTrackerKit.StatSpread` at the edge.
public struct TeamMember: Codable, Sendable, Equatable, Identifiable {
    public let slot: Int
    public let pokemonID: Int
    public let nickname: String?
    public let nature: String
    public let abilitySlug: String
    public let itemSlug: String?
    public let teraType: String?
    public let level: Int
    public let evs: [String: Int]
    public let ivs: [String: Int]
    public let moves: [String]

    public var id: Int { slot }

    enum CodingKeys: String, CodingKey {
        case slot, nickname, nature, level, evs, ivs, moves
        case pokemonID = "pokemon_id"
        case abilitySlug = "ability_slug"
        case itemSlug = "item_slug"
        case teraType = "tera_type"
    }
}

/// `GET /api/items` — public reference data.
public struct Item: Codable, Sendable, Equatable, Identifiable {
    public let slug: String
    public let name: String
    public let spriteURL: String
    public let description: String

    public var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, description
        case spriteURL = "sprite_url"
    }
}

/// `POST /api/me/teams`.
public struct CreateTeamRequest: Codable, Sendable, Equatable {
    public let name: String
    public let members: [TeamMember]

    public init(name: String, members: [TeamMember]) {
        self.name = name
        self.members = members
    }
}

/// `PATCH /api/me/teams/{id}`. Members are replaced wholesale — an absent `members`
/// leaves them untouched, an empty array clears them.
public struct UpdateTeamRequest: Codable, Sendable, Equatable {
    public let name: String?
    public let members: [TeamMember]

    public init(name: String? = nil, members: [TeamMember]) {
        self.name = name
        self.members = members
    }
}
```

- [ ] **Step 4: Add the client methods**

In `APIClient.swift`, after the owned-games section:

```swift
    // MARK: Teams

    public func teams() async throws -> [Team] {
        try await getList("api/me/teams")
    }

    public func createTeam(_ body: CreateTeamRequest) async throws -> Team {
        try await send("POST", "api/me/teams", body: body)
    }

    public func updateTeam(id teamID: UUID, _ body: UpdateTeamRequest) async throws -> Team {
        try await send("PATCH", "api/me/teams/\(id(teamID))", body: body)
    }

    public func deleteTeam(id teamID: UUID) async throws {
        try await sendDiscardingBody("DELETE", "api/me/teams/\(id(teamID))", body: noBody)
    }

    /// Public reference data, like `games()` and `methods()`.
    public func items() async throws -> [Item] {
        try await getList("api/items")
    }
```

- [ ] **Step 5: Add the snapshot key**

In `SnapshotStore.swift`, beside the other keys:

```swift
    /// Saved teams. Cache only — the server is the source of truth, and unlike
    /// `.pendingWrites` nothing here is the only copy of anything.
    public static let teams = SnapshotKey("teams")
```

- [ ] **Step 6: Run the tests**

Run: `cd ios/ShinyTrackerAPI && swift test`
Expected: PASS — 48 existing + 2 new

- [ ] **Step 7: Commit**

```bash
git add ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/Models.swift \
        ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/APIClient.swift \
        ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/SnapshotStore.swift \
        ios/ShinyTrackerAPI/Tests/ShinyTrackerAPITests/DecodingTests.swift
git commit -m "feat(api-client): team and item models and endpoints"
```

---

### Task 9: TeamsModel

**Files:**
- Create: `ios/App/Teams/TeamsModel.swift`

**Interfaces:**
- Consumes: `APIClient.teams()`, `SnapshotKey.teams` from Task 8
- Produces: `@MainActor @Observable final class TeamsModel` with `state`, `teams`, `syncError`, `load()`, `refresh()`, `appear()`, `save(name:members:)`, `delete(_:)`

- [ ] **Step 1: Implement the model**

Follow `GameLibraryModel` in `ios/App/Hunt/GamesTab.swift` exactly — same load/refresh/appear lifecycle, same cache-then-network ordering, same inline-warning-over-cached-content rule.

```swift
import Foundation
import ShinyTrackerAPI
import SwiftUI

/// Saved Scarlet/Violet teams.
///
/// Reads are cached through `SnapshotStore` so a cold launch draws something before the
/// network answers, matching `HuntListModel` and `DexModel`. Writes are online-only in
/// this slice — see the plan's "teams do NOT use WriteQueue" note. A team that cannot be
/// edited without signal is a smaller failure than a hunt that cannot be counted, and
/// extending `PendingWrite` means migrating the one file that holds unsent encounters.
@MainActor
@Observable
final class TeamsModel {
    private(set) var state: LoadState = .loading
    private(set) var teams: [Team] = []
    private(set) var syncError: String?

    private let client: APIClient
    private let store: SnapshotStore

    init(client: APIClient, store: SnapshotStore) {
        self.client = client
        self.store = store
    }

    func load() async { await load(quiet: false) }
    func refresh() async { await load(quiet: true) }

    /// See `HuntListModel.appear()`.
    func appear() async {
        state == .ready ? await refresh() : await load()
    }

    private func load(quiet: Bool) async {
        syncError = nil
        if !quiet, state != .ready, let cached = await store.load([Team].self, as: .teams) {
            teams = cached
            state = .ready
        }
        if !quiet, state != .ready { state = .loading }
        do {
            let fresh = try await client.teams()
            teams = fresh
            state = .ready
            await store.save(fresh, as: .teams)
        } catch {
            if let message = userFacingMessage(for: error) {
                if quiet || state == .ready {
                    syncError = "Couldn't refresh your teams. \(message)"
                } else {
                    state = .failed(message)
                }
            }
        }
    }

    /// Creates a new team, or replaces an existing one's members wholesale.
    func save(id: UUID?, name: String, members: [TeamMember]) async {
        syncError = nil
        do {
            let saved: Team
            if let id {
                saved = try await client.updateTeam(id: id, UpdateTeamRequest(name: name, members: members))
                if let index = teams.firstIndex(where: { $0.id == id }) {
                    teams[index] = saved
                } else {
                    teams.insert(saved, at: 0)
                }
            } else {
                saved = try await client.createTeam(CreateTeamRequest(name: name, members: members))
                teams.insert(saved, at: 0)
            }
            await store.save(teams, as: .teams)
        } catch {
            if let message = userFacingMessage(for: error) {
                syncError = "Couldn't save the team. \(message)"
            }
        }
    }

    func delete(_ id: UUID) async {
        let before = teams
        teams.removeAll { $0.id == id }
        syncError = nil
        do {
            try await client.deleteTeam(id: id)
            await store.save(teams, as: .teams)
        } catch {
            teams = before
            if let message = userFacingMessage(for: error) {
                syncError = "Couldn't delete the team. \(message)"
            }
        }
    }
}
```

- [ ] **Step 2: Build the app target**

Run:
```bash
cd ios && xcodegen generate && xcodebuild -project ShinyTracker.xcodeproj \
  -scheme ShinyTracker -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add ios/App/Teams/TeamsModel.swift
git commit -m "feat(ios): TeamsModel with snapshot-cached reads"
```

---

### Task 10: Teams UI

**Files:**
- Create: `ios/App/Teams/TeamsScreen.swift`
- Create: `ios/App/Teams/TeamEditorScreen.swift`
- Create: `ios/App/Teams/MemberSheet.swift`
- Modify: `ios/App/ShinyTrackerApp.swift`

**Interfaces:**
- Consumes: `TeamsModel` from Task 9; `Palette`, `Radii`, `Typography` from `ShinyTrackerUI`
- Produces: a `Teams` tab

- [ ] **Step 1: Build the three screens**

Follow the existing screens for structure and styling — `DexScreen.swift` for the list-with-states shape and `NewHuntSheet.swift` for a multi-step sheet.

Requirements, all of which have precedent in the codebase:

- `TeamsScreen`: `.loading` → `ProgressView().tint(Palette.textMuted)`; `.failed(reason)` → `StateBlock` with a retry button; `.ready` and empty → `StateBlock` inviting a first team; `.ready` with teams → rows showing name and six sprite tiles via `SpriteTile`.
- `syncError` renders as a dismissible banner above the content, never replacing it.
- `TeamEditorScreen`: six slots; tapping one opens `MemberSheet`; a name field capped at 100 characters; Save calls `TeamsModel.save`.
- `MemberSheet`: species search, then nature / ability / item pickers and a move picker restricted to that species' SV learnset (`APIClient.pokemonDetail` already returns `moves` when `game_id` is supplied), then the EV/IV editor.
- The EV editor shows remaining points out of 508 and refuses input that would exceed 508 total or 252 in one stat — the third enforcement point named in the Global Constraints.
- Every icon-only button gets an `accessibilityLabel`, matching the standard the rest of the app already meets.
- Use `Typography` tokens, never `Font.system(size:)` — the tokens carry Dynamic Type.

- [ ] **Step 2: Add the tab**

In `ios/App/ShinyTrackerApp.swift`, add a Teams tab beside Hunt, Dex and Nuzlocke, using `Palette.team` (`#6EE7A2`) as its accent — the palette already reserves that colour for exactly this, under the comment "Each mode owns a colour, so you always know where you are."

- [ ] **Step 3: Build**

Run:
```bash
cd ios && xcodegen generate && xcodebuild -project ShinyTracker.xcodeproj \
  -scheme ShinyTracker -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ios/App/Teams/ ios/App/ShinyTrackerApp.swift
git commit -m "feat(ios): teams list, editor and member sheet"
```

---

### Task 11: Preview harness and paste import/export UI

**Files:**
- Create: `ios/App/Teams/TeamsPreviewHarness.swift`
- Modify: `ios/App/Teams/TeamsScreen.swift`
- Modify: `ios/App/Teams/TeamEditorScreen.swift`

**Interfaces:**
- Consumes: `PreviewHarness` from PR #61; `ShowdownPaste` from Tasks 2–3

- [ ] **Step 1: Write the harness**

Mirror `ios/App/Nuzlocke/NuzlockePreviewHarness.swift` exactly: `#if DEBUG`, an enum with a `Fixture` raw-value enum, `requested` reading `PreviewHarness.argument("-teamsPreview")`, and `client(_:)` returning `PreviewHarness.client { method, path, _ in ... }` with a routing table covering `/api/me/teams`, `/api/items`, `/api/pokemon` and `/api/pokemon/{id}`.

Fixtures: `seeded` (one full six-slot team), `empty`, `error`.

- [ ] **Step 2: Add import and export**

- Export: a button on `TeamEditorScreen` that maps the team's members to `ShowdownPaste.ParsedSet` and puts `ShowdownPaste.export(...)` on `UIPasteboard.general.string`.
- Import: a paste-text sheet that calls `ShowdownPaste.parse`, resolves species names and move names to ids and slugs via `APIClient.pokemon(search:)`, and creates a **new** team. Import is additive and never overwrites in place, so a bad paste cannot destroy a saved team.
- A parse failure shows the typed error and names the offending line. A species that cannot be resolved is reported by name rather than silently dropped.

- [ ] **Step 3: Verify the previews render**

Run:
```bash
cd ios && xcodegen generate && xcodebuild -project ShinyTracker.xcodeproj \
  -scheme ShinyTracker -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build
xcrun simctl launch booted com.casperkarlsen.shinytracker -teamsPreview seeded
```
Expected: the Teams tab shows the seeded team without a session or a server.

- [ ] **Step 4: Full verification**

Run:
```bash
cd backend && gofmt -l ./internal ./cmd && go build ./... && go vet ./... && go test ./...
cd ../ios/ShinyTrackerKit && swift test
cd ../ShinyTrackerAPI && swift test
cd ../ && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add ios/App/Teams/
git commit -m "feat(ios): teams preview harness and Showdown paste import/export"
```

---

## Self-Review

**Spec coverage.** Every spec section maps to a task: six slots and all set fields (7, 10) · EV/IV caps enforced in three places (1, 7, 10) · computed stats at 50 and 100 (1) · named teams persisted and cached (7, 8, 9) · Showdown import and export round-tripping (2, 3, 11) · natures hardcoded (1) · items seeded without effect data (5) · `teams`/`team_members` DDL (4) · five routes plus `/api/items` (7) · `ios/App/Teams/` following existing shapes (9, 10, 11) · error handling conventions (9, 11) · Shedinja (1) · every named parser edge case (2).

**One deliberate deviation from the spec.** The spec left `WriteQueue` extension as the default with online-only as a fallback. This plan inverts that, for the reason given in the "Decision" section above — `PendingWrite` is hunt-scoped and its persisted shape is the only copy of unsent encounters. Reads remain offline-capable.

**Placeholders:** none. Every code step carries the code.

**Type consistency:** `Stat.rawValue` (`hp/atk/def/spa/spd/spe`) is the single key vocabulary across the Swift enum (Task 1), the JSON fixture (Task 2), Go's `validStats` (Task 7), and the JSONB columns (Task 4). `StatSpread.maxIVs` is the IV default in Task 1, Task 2's parser, and Task 3's exporter. `ParsedSet` is produced in Task 2 and consumed unchanged in Tasks 3 and 11.
