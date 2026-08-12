import Foundation
import ShinyTrackerKit
import Testing

@testable import ShinyTrackerAPI

/// Decoding tests run against fixtures written from the Go handlers' response shapes
/// (`backend/internal/api/*.go` + `backend/internal/models/models.go`). No server is involved
/// and none can be — the API is not deployed yet (scope doc, P1).

// MARK: - Hunts

/// `GET /api/hunts` — `[]models.UserHuntDetail`. Two rows on purpose: a curated hunt with a
/// game, a method and populated `hunt_parameters`, and a custom-method hunt where `game_id`,
/// `hunt_method_id` and every left-joined column are null.
private let huntListJSON = """
[
  {
    "id": "8f14e45f-ceea-467a-9e7f-3d1e33f34d43",
    "user_id": "0b3c9a7e-1d2f-4a5b-8c6d-7e8f9a0b1c2d",
    "pokemon_id": 25,
    "game_id": 34,
    "hunt_method_id": 7,
    "encounter_count": 1234,
    "phase_count": 1,
    "status": "active",
    "acquisition_type": "HUNTED",
    "hunt_parameters": {
      "chain_length": 31,
      "lure_active": true,
      "shiny_charm": null,
      "note": "left over from an old client"
    },
    "created_at": "2026-08-11T12:00:00.482913Z",
    "updated_at": "2026-08-11T12:34:56Z",
    "pokemon_name": "pikachu",
    "method_name": "Masuda Method",
    "custom_method_name": null,
    "game_title": "Sword",
    "total_time_seconds": 4200,
    "base_rolls": 1,
    "charm_rolls": 3,
    "avg_time_seconds": 30,
    "base_odds": 4096,
    "has_shiny_charm": true,
    "formula_type": "masuda",
    "sprite_url": "https://img.example/25.png",
    "nickname": "Sparky",
    "phases": [
      {
        "id": "1c9f0b2a-3d4e-4f50-a617-283940516273",
        "hunt_id": "8f14e45f-ceea-467a-9e7f-3d1e33f34d43",
        "pokemon_id": 129,
        "pokemon_name": "magikarp",
        "sprite_url": "https://example.invalid/129.png",
        "encounter_count_at_phase": 812,
        "created_at": "2026-08-10T22:15:01.5Z"
      }
    ]
  },
  {
    "id": "a2d5f8c1-4b6e-4a90-91f2-0c5d7e8a9b01",
    "user_id": "0b3c9a7e-1d2f-4a5b-8c6d-7e8f9a0b1c2d",
    "pokemon_id": 133,
    "game_id": null,
    "hunt_method_id": null,
    "encounter_count": 0,
    "phase_count": 0,
    "status": "active",
    "acquisition_type": "HUNTED",
    "hunt_parameters": {},
    "created_at": "2026-08-11T14:03:20+02:00",
    "updated_at": "2026-08-11T14:03:20+02:00",
    "pokemon_name": "eevee",
    "method_name": null,
    "custom_method_name": "Outbreak sniping",
    "game_title": null,
    "total_time_seconds": 0,
    "base_rolls": null,
    "charm_rolls": null,
    "avg_time_seconds": null,
    "base_odds": null,
    "has_shiny_charm": null,
    "formula_type": "static",
    "phases": []
  }
]
"""

/// `sprite_url` and `nickname` are newer than the shipped app, so the second hunt in the
/// fixture omits both — a server that predates them must still decode, not blow up the list.
@Test func huntSpriteAndNicknameTolerateAnOlderServer() throws {
    let hunts = try apiDecoder().decode([HuntDetail].self, from: Data(huntListJSON.utf8))

    #expect(hunts[0].spriteURL == "https://img.example/25.png")
    #expect(hunts[0].nickname == "Sparky")

    #expect(hunts[1].spriteURL == nil)
    #expect(hunts[1].nickname == nil)
}

/// An omitted nickname must not reach the wire as `"nickname": null` — the update handler
/// treats a nil pointer as "leave it alone", so a stray null would be indistinguishable from
/// a deliberate one.
@Test func createHuntBodyOmitsAnAbsentNickname() throws {
    let encoder = JSONEncoder()
    let without = try encoder.encode(CreateHuntRequest(pokemonID: 25, customMethodName: "Radar"))
    #expect(!String(decoding: without, as: UTF8.self).contains("nickname"))

    let with = try encoder.encode(
        CreateHuntRequest(pokemonID: 25, customMethodName: "Radar", nickname: "Sparky"))
    #expect(String(decoding: with, as: UTF8.self).contains("\"nickname\":\"Sparky\""))
}

/// The killer case: a custom-method hunt has no game and no method row. If `gameID` or
/// `huntMethodID` were non-optional, every such hunt would fail to decode.
@Test func decodesHuntWithNullGameAndMethod() throws {
    let hunts = try apiDecoder().decode([HuntDetail].self, from: Data(huntListJSON.utf8))
    #expect(hunts.count == 2)

    let custom = hunts[1]
    #expect(custom.gameID == nil)
    #expect(custom.huntMethodID == nil)
    #expect(custom.methodName == nil)
    #expect(custom.gameTitle == nil)
    #expect(custom.hasShinyCharm == nil)
    #expect(custom.customMethodName == "Outbreak sniping")
    #expect(custom.phases.isEmpty)
    #expect(custom.huntParameters == [:])
}

@Test func decodesCuratedHuntAndItsPhases() throws {
    let hunt = try apiDecoder().decode([HuntDetail].self, from: Data(huntListJSON.utf8))[0]
    #expect(hunt.gameID == 34)
    #expect(hunt.huntMethodID == 7)
    #expect(hunt.encounterCount == 1234)
    #expect(hunt.totalTimeSeconds == 4200)
    #expect(hunt.pokemonName == "pikachu")
    #expect(hunt.phases.count == 1)
    #expect(hunt.phases[0].pokemonName == "magikarp")
    #expect(hunt.phases[0].encounterCountAtPhase == 812)
}

/// `hunt_parameters` keys must survive **verbatim** — `ShinyTrackerKit` looks them up as
/// `chain_length`, not `chainLength`. This is what a `convertFromSnakeCase` key strategy
/// would have broken silently, since the strategy rewrites dictionary keys too.
@Test func huntParameterKeysSurviveVerbatimAndTolerateJunk() throws {
    let hunt = try apiDecoder().decode([HuntDetail].self, from: Data(huntListJSON.utf8))[0]
    let params = try #require(hunt.huntParameters)

    #expect(params["chain_length"]?.intValue == 31)
    #expect(params["lure_active"]?.boolValue == true)
    #expect(params["chainLength"] == nil)
    // A null and a string must degrade to .unrecognized per key, not fail the whole object.
    #expect(params["shiny_charm"] == ParamValue.unrecognized)
    #expect(params["note"] == ParamValue.unrecognized)
}

/// Go trims trailing zeros off the fractional second, and the columns are
/// `TIMESTAMP WITH TIME ZONE`, so all three of these shapes are real.
@Test func decodesGoTimestampsWithAndWithoutFractionAndWithOffset() throws {
    let hunts = try apiDecoder().decode([HuntDetail].self, from: Data(huntListJSON.utf8))

    // Epochs computed independently of Foundation (Python datetime.fromisoformat).
    #expect(abs(hunts[0].createdAt.timeIntervalSince1970 - 1_786_449_600.482913) < 0.001)
    #expect(hunts[0].updatedAt.timeIntervalSince1970 == 1_786_451_696)  // no fractional part
    #expect(hunts[0].phases[0].createdAt.timeIntervalSince1970 == 1_786_400_101.5)
    // 14:03:20+02:00 is 12:03:20Z — a non-UTC offset must not be read as wall-clock UTC.
    #expect(hunts[1].createdAt.timeIntervalSince1970 == 1_786_449_800)
}

@Test func rejectsAnUnparseableTimestamp() {
    let json = huntListJSON.replacingOccurrences(
        of: "\"2026-08-11T12:34:56Z\"", with: "\"11 Aug 2026\"")
    #expect(throws: DecodingError.self) {
        try apiDecoder().decode([HuntDetail].self, from: Data(json.utf8))
    }
}

/// `POST /api/hunts` and `PATCH /api/hunts/{id}` answer with the bare `models.UserHunt`.
/// The PATCH `RETURNING` clause omits `game_id`, so it always encodes as null.
@Test func decodesBareHuntFromCreateAndPatch() throws {
    let json = """
        {
          "id": "8f14e45f-ceea-467a-9e7f-3d1e33f34d43",
          "user_id": "0b3c9a7e-1d2f-4a5b-8c6d-7e8f9a0b1c2d",
          "pokemon_id": 25,
          "game_id": null,
          "hunt_method_id": 7,
          "encounter_count": 5,
          "phase_count": 0,
          "status": "completed",
          "acquisition_type": "HUNTED",
          "hunt_parameters": {"chain_length": 4},
          "created_at": "2026-08-11T12:00:00Z",
          "updated_at": "2026-08-11T12:00:09Z"
        }
        """
    let hunt = try apiDecoder().decode(Hunt.self, from: Data(json.utf8))
    #expect(hunt.gameID == nil)
    #expect(hunt.huntMethodID == 7)
    #expect(hunt.status == "completed")
    #expect(hunt.huntParameters?["chain_length"]?.intValue == 4)
}

// MARK: - Reference data

@Test func decodesReferenceDataPayloads() throws {
    let decoder = apiDecoder()

    let me = try decoder.decode(
        Profile.self,
        from: Data(
            """
            {"id":"0b3c9a7e-1d2f-4a5b-8c6d-7e8f9a0b1c2d","username":"casper","is_admin":false}
            """.utf8))
    #expect(me.username == "casper")
    #expect(me.isAdmin == false)

    let games = try decoder.decode(
        [Game].self,
        from: Data(#"[{"id":34,"title":"Sword","generation":8,"base_odds":4096}]"#.utf8))
    #expect(games[0].baseOdds == 4096)

    let pokemon = try decoder.decode(
        [Pokemon].self,
        from: Data(
            """
            [{"id":25,"name":"pikachu","sprite_url":"https://example.invalid/25.png",
              "types":["electric"],"is_legendary":false,"is_mythical":false},
             {"id":9999,"name":"missingno","sprite_url":"","types":null,
              "is_legendary":false,"is_mythical":false}]
            """.utf8))
    #expect(pokemon[0].types == ["electric"])
    #expect(pokemon[1].types == nil)  // types is a nullable jsonb column

    let methods = try decoder.decode(
        [MethodDetail].self,
        from: Data(
            """
            [{"id":7,"game_id":34,"game_title":"Sword","method_name":"Masuda Method",
              "base_rolls":1,"charm_rolls":3,"avg_time_seconds":30,"formula_type":"masuda"}]
            """.utf8))
    #expect(methods[0].formulaType == "masuda")

    let huntMethods = try decoder.decode(
        [HuntMethodDetail].self,
        from: Data(
            """
            [{"id":7,"pokemon_id":25,"game_id":34,"game_title":"Sword",
              "method_name":"Masuda Method","avg_time_seconds":30,"base_rolls":1,
              "charm_rolls":3,"formula_type":"masuda"}]
            """.utf8))
    #expect(huntMethods[0].pokemonID == 25)

    let userGames = try decoder.decode(
        [UserGame].self,
        from: Data(
            """
            [{"user_id":"0b3c9a7e-1d2f-4a5b-8c6d-7e8f9a0b1c2d","game_id":34,
              "has_shiny_charm":true}]
            """.utf8))
    #expect(userGames[0].hasShinyCharm)
}

@Test func decodesPokemonDetail() throws {
    let json = """
        {
          "id": 134, "name": "vaporeon", "sprite_url": "https://example.invalid/134.png",
          "types": ["water"], "can_breed": true, "is_legendary": false, "is_mythical": false,
          "evolves_from_id": 133,
          "evolves_from": [{"pokemon_id": 133, "name": "eevee"}],
          "evolves_to": [],
          "locations": [
            {"game_id": 4, "area": "route-1", "version": "red", "terrain": "walk",
             "min_level": 2, "max_level": 5, "chance": 20, "conditions": ["time-day"]}
          ]
        }
        """
    let detail = try apiDecoder().decode(PokemonDetail.self, from: Data(json.utf8))
    #expect(detail.evolvesFromID == 133)
    #expect(detail.evolvesFrom == [EvolutionLink(pokemonID: 133, name: "eevee")])
    #expect(detail.evolvesTo.isEmpty)
    #expect(detail.locations[0].conditions == ["time-day"])
    #expect(detail.locations[0].maxLevel == 5)
}

/// The compatibility guarantee, stated as a test: the fixture above is a response from the
/// handler *before* stats, abilities and moves existed, and it must keep decoding into the
/// widened model. `decodesPokemonDetail` above already exercises that payload; this pins the
/// three new fields to nil so a later "tidy-up" that makes any of them non-optional — which
/// would throw `keyNotFound` on every pre-existing response — fails here instead of in the app.
@Test func pokemonDetailStaysBackwardCompatible() throws {
    let legacy = """
        {
          "id": 134, "name": "vaporeon", "sprite_url": "https://example.invalid/134.png",
          "types": ["water"], "can_breed": true, "is_legendary": false, "is_mythical": false,
          "evolves_from_id": 133, "evolves_from": [], "evolves_to": [], "locations": []
        }
        """
    let detail = try apiDecoder().decode(PokemonDetail.self, from: Data(legacy.utf8))
    #expect(detail.stats == nil)
    #expect(detail.abilities == nil)
    #expect(detail.moves == nil)
    #expect(detail.name == "vaporeon")
}

/// The current handler, with `?game_id=`: stats present, abilities populated, moves scoped to
/// that game. Null `power`/`accuracy`/`level` are the normal case for status and TM moves.
@Test func decodesPokemonDetailWithStatsAbilitiesAndMoves() throws {
    let json = """
        {
          "id": 443, "name": "gible", "sprite_url": "https://example.invalid/443.png",
          "types": ["dragon", "ground"], "can_breed": true,
          "is_legendary": false, "is_mythical": false,
          "evolves_from_id": null, "evolves_from": [],
          "evolves_to": [{"pokemon_id": 444, "name": "gabite"}],
          "locations": [
            {"game_id": 4, "area": "wayward-cave", "version": "platinum", "terrain": "cave",
             "min_level": 15, "max_level": 18, "chance": 4, "conditions": []}
          ],
          "stats": {"hp": 58, "attack": 70, "defense": 45,
                    "special_attack": 40, "special_defense": 45, "speed": 42},
          "abilities": [
            {"slug": "sand-veil", "name": "Sand Veil", "effect": "Evasion up in a sandstorm.",
             "slot": 1, "is_hidden": false},
            {"slug": "rough-skin", "name": "Rough Skin", "effect": "", "slot": 3,
             "is_hidden": true}
          ],
          "moves": [
            {"slug": "tackle", "name": "Tackle", "type": "normal", "damage_class": "physical",
             "power": 40, "accuracy": 100, "pp": 35, "effect": "", "method": "level-up",
             "level": 1},
            {"slug": "sandstorm", "name": "Sandstorm", "type": "rock", "damage_class": "status",
             "power": null, "accuracy": null, "pp": 10, "effect": "", "method": "tm",
             "level": null}
          ]
        }
        """
    let detail = try apiDecoder().decode(PokemonDetail.self, from: Data(json.utf8))

    let stats = try #require(detail.stats)
    #expect(stats.specialAttack == 40)
    #expect(stats.total == 300)                       // the prototype's "Base stats · 300 total"
    #expect(stats.ordered.map(\.label) == ["HP", "Atk", "Def", "SpA", "SpD", "Spe"])

    #expect(detail.abilities?.last?.isHidden == true)

    let moves = try #require(detail.moves)
    #expect(moves[0].level == 1)
    #expect(moves[1].power == nil)                    // a status move, not a 0-power one
    #expect(moves[1].accuracy == nil)
    #expect(moves[1].level == nil)
    // Same species, same game, same slug on two methods must stay two rows.
    #expect(moves[0].id != moves[1].id)
}

/// `moves: null` (no `game_id` asked) and `moves: []` (asked, nothing seeded) mean different
/// things to the sheet — "pick a game" vs "this game has no moveset seeded".
@Test func movesDistinguishesNullFromEmpty() throws {
    let base = """
        "id": 1, "name": "bulbasaur", "sprite_url": "", "types": [], "can_breed": true,
        "is_legendary": false, "is_mythical": false, "evolves_from_id": null,
        "evolves_from": [], "evolves_to": [], "locations": [], "abilities": []
        """
    let notAsked = try apiDecoder().decode(
        PokemonDetail.self, from: Data("{\(base), \"moves\": null}".utf8))
    let askedButEmpty = try apiDecoder().decode(
        PokemonDetail.self, from: Data("{\(base), \"moves\": []}".utf8))

    #expect(notAsked.moves == nil)
    #expect(askedButEmpty.moves == [])
}

@Test func decodesDexStatus() throws {
    let status = try apiDecoder().decode(
        DexStatus.self,
        from: Data("""
            {"not_in_your_games": [151, 251], "locked_everywhere": [385]}
            """.utf8))
    #expect(status.notInYourGames == [151, 251])
    #expect(status.lockedEverywhere == [385])
}

// MARK: - Request encoding

/// D1: sending `total_time_seconds` latches `client_owns_time`, so it must be *absent*, not
/// null, when the client is not claiming authority — `UpdateHuntHandler` decodes it into a
/// `*int` and only distinguishes absent from present.
@Test func patchBodyOmitsOptionalsRatherThanEncodingNull() throws {
    let bare = UpdateHuntRequest(encounterCount: 12, status: .active)
    let json = try #require(String(data: JSONEncoder().encode(bare), encoding: .utf8))

    #expect(!json.contains("total_time_seconds"))
    #expect(!json.contains("hunt_parameters"))
    #expect(!json.contains("null"))
    #expect(json.contains("\"encounter_count\":12"))
    #expect(json.contains("\"status\":\"active\""))

    let timed = UpdateHuntRequest(
        encounterCount: 12,
        status: .completed,
        huntParameters: ["chain_length": .number(4)],
        totalTimeSeconds: 900
    )
    let timedJSON = try #require(String(data: JSONEncoder().encode(timed), encoding: .utf8))
    #expect(timedJSON.contains("\"total_time_seconds\":900"))
    #expect(timedJSON.contains("\"chain_length\":4"))
}

@Test func createHuntBodyOmitsTheBranchItIsNotUsing() throws {
    let custom = CreateHuntRequest(pokemonID: 133, customMethodName: "Outbreak sniping")
    let json = try #require(String(data: JSONEncoder().encode(custom), encoding: .utf8))
    #expect(json.contains("\"custom_method_name\":\"Outbreak sniping\""))
    #expect(!json.contains("hunt_method_id"))
    #expect(!json.contains("game_id"))
}

/// Requests are plain `Codable` values so an offline queue can persist and replay them later.
@Test func requestBodiesRoundTrip() throws {
    let original = UpdateHuntRequest(
        encounterCount: 7, status: .active, huntParameters: ["lure_active": .bool(true)],
        totalTimeSeconds: 60)
    let replayed = try JSONDecoder().decode(
        UpdateHuntRequest.self, from: JSONEncoder().encode(original))
    #expect(replayed == original)
}

// MARK: - Helper

/// The same decoder configuration ``APIClient`` builds.
private func apiDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom(decodeGoTimestamp)
    return decoder
}

// MARK: - Nuzlocke

/// `GET /api/runs/{id}` — `models.NuzlockeRunDetail`. The timeline carries one entry of each
/// kind, because they are two shapes in one type: the location has `encounters` and no
/// `boss_title`/`level_cap`/`squad`, the boss has all of those and no `encounters`. Go's
/// `omitempty` means the other kind's keys are *absent*, not null or empty.
private let runDetailJSON = """
{
  "id": "5c1f0f7e-2b3a-4c5d-8e9f-0a1b2c3d4e5f",
  "user_id": "0b3c9a7e-1d2f-4a5b-8c6d-7e8f9a0b1c2d",
  "game_id": 12,
  "game_title": "Platinum",
  "dupes_clause": true,
  "battle_style": "set",
  "nicknames_required": true,
  "status": "active",
  "started_at": "2026-08-01T09:00:00Z",
  "ended_at": null,
  "created_at": "2026-08-01T09:00:00.482913Z",
  "updated_at": "2026-08-06T18:20:00Z",
  "timeline": [
    {
      "id": 41,
      "slug": "r201",
      "kind": "location",
      "name": "Route 201",
      "sort_order": 2,
      "encounters": [
        {"pokemon_id": 396, "pokemon_name": "starly", "sprite_url": "https://img.example/396.png"},
        {"pokemon_id": 399, "pokemon_name": "bidoof", "sprite_url": ""}
      ]
    },
    {
      "id": 48,
      "slug": "gym1",
      "kind": "boss",
      "name": "Roark",
      "sort_order": 9,
      "place": "Oreburgh City",
      "boss_title": "Gym Leader",
      "level_cap": 14,
      "squad": [
        {
          "pokemon_id": 95,
          "pokemon_name": "onix",
          "sprite_url": "https://img.example/95.png",
          "level": 12,
          "ability": "Rock Head",
          "moves": [{"name": "Stealth Rock", "type": "rock", "power": 0}]
        },
        {
          "pokemon_id": 408,
          "pokemon_name": "cranidos",
          "sprite_url": "",
          "level": 14,
          "ability": "Mold Breaker",
          "moves": null
        }
      ]
    }
  ],
  "encounters": [
    {
      "id": "9a8b7c6d-5e4f-4a3b-9c8d-7e6f5a4b3c2d",
      "run_id": "5c1f0f7e-2b3a-4c5d-8e9f-0a1b2c3d4e5f",
      "location_slug": "r201",
      "pokemon_id": 399,
      "pokemon_name": "bidoof",
      "nickname": "Chomper",
      "status": "fainted",
      "nature": null,
      "is_boxed": false,
      "is_dupe": false,
      "created_at": "2026-08-01T09:14:00Z",
      "updated_at": "2026-08-03T11:02:00Z"
    }
  ],
  "boss_progress": [
    {"boss_slug": "gym1", "beaten": true}
  ]
}
"""

@Test func decodesRunDetailWithBothTimelineKinds() throws {
    let detail = try apiDecoder().decode(NuzlockeRunDetail.self, from: Data(runDetailJSON.utf8))

    #expect(detail.gameTitle == "Platinum")
    #expect(detail.isActive)
    #expect(detail.endedAt == nil)
    #expect(detail.dupesClause && detail.nicknamesRequired)

    let location = try #require(detail.timeline.first { !$0.isBoss })
    #expect(location.encounters?.map(\.pokemonID) == [396, 399])
    // The absent-vs-empty distinction: a location has no boss keys at all.
    #expect(location.levelCap == nil)
    #expect(location.squad == nil)

    let boss = try #require(detail.timeline.first { $0.isBoss })
    #expect(boss.bossTitle == "Gym Leader")
    #expect(boss.levelCap == 14)
    #expect(boss.encounters == nil)
    #expect(boss.squad?.count == 2)
    // `Moves` has no `omitempty`, so a squad member with no seeded moves sends `"moves":null` —
    // nil, not []. The fixture spells the null out because that is what the server really writes.
    #expect(boss.squad?.last?.moves == nil)
    #expect(boss.squad?.first?.moves?.first?.power == 0)

    let logged = try #require(detail.encounters.first)
    #expect(logged.locationSlug == "r201")
    #expect(logged.nickname == "Chomper")
    #expect(logged.status == "fainted")
    #expect(!logged.isDupe)

    #expect(detail.bossProgress == [NuzlockeBossProgress(bossSlug: "gym1", beaten: true)])
}

/// `PUT /api/runs/{id}/encounters/{slug}` answers from a `RETURNING` clause with no join, so
/// `pokemon_name` is absent and `location_slug` is filled in by the handler, not the query.
@Test func decodesEncounterLogFromAWriteResponse() throws {
    let json = """
    {
      "id": "9a8b7c6d-5e4f-4a3b-9c8d-7e6f5a4b3c2d",
      "run_id": "5c1f0f7e-2b3a-4c5d-8e9f-0a1b2c3d4e5f",
      "location_slug": "r202",
      "pokemon_id": 403,
      "nickname": "Sparks",
      "status": "caught",
      "nature": "Adamant",
      "is_boxed": false,
      "is_dupe": true,
      "created_at": "2026-08-04T10:00:00Z",
      "updated_at": "2026-08-04T10:00:00Z"
    }
    """
    let log = try apiDecoder().decode(NuzlockeEncounterLog.self, from: Data(json.utf8))
    #expect(log.pokemonName == nil)
    #expect(log.isDupe)
    #expect(log.pokemonID == 403)
}

/// A miss carries no Pokemon, so the body must omit `pokemon_id` rather than send null — and
/// `is_boxed` must stay out of a request that is not setting it.
@Test func logEncounterBodyOmitsWhatItIsNotSetting() throws {
    let missed = LogEncounterRequest(status: .missed)
    let json = try #require(String(data: JSONEncoder().encode(missed), encoding: .utf8))
    #expect(json.contains("\"status\":\"missed\""))
    #expect(!json.contains("pokemon_id"))
    #expect(!json.contains("nickname"))
    #expect(!json.contains("is_boxed"))
    #expect(EncounterStatus.missed.carriesPokemon == false)
    #expect(EncounterStatus.fainted.carriesPokemon)
}

/// `PUT .../encounters/{slug}` is an **upsert, not a patch**: `PutRunEncounterHandler` reads an
/// absent `is_boxed` as `false` and writes it unconditionally. So omitting the field is not
/// "leave it alone", it is "un-box this Pokémon" — a caller re-saving an existing row has to send
/// the value it wants kept. This pins that `false` and absent are distinguishable on the wire,
/// which is the whole reason `isBoxed` is an `Optional<Bool>` rather than a `Bool`.
@Test func logEncounterBodyDistinguishesUnboxedFromUnspecified() throws {
    let encoder = JSONEncoder()
    let boxed = LogEncounterRequest(status: .caught, pokemonID: 74, isBoxed: true)
    let unboxed = LogEncounterRequest(status: .caught, pokemonID: 74, isBoxed: false)
    let unspecified = LogEncounterRequest(status: .caught, pokemonID: 74)

    #expect(try #require(String(data: encoder.encode(boxed), encoding: .utf8))
        .contains("\"is_boxed\":true"))
    #expect(try #require(String(data: encoder.encode(unboxed), encoding: .utf8))
        .contains("\"is_boxed\":false"))
    #expect(!(try #require(String(data: encoder.encode(unspecified), encoding: .utf8))
        .contains("is_boxed")))
}

/// The clauses are sent explicitly on every create: the server defaults them to *true*, so an
/// omitted `false` would silently turn a clause the user switched off back on.
@Test func createRunBodySendsEveryClause() throws {
    let body = CreateRunRequest(
        gameID: 12, dupesClause: false, battleStyle: .shift, nicknamesRequired: false)
    let json = try #require(String(data: JSONEncoder().encode(body), encoding: .utf8))
    #expect(json.contains("\"dupes_clause\":false"))
    #expect(json.contains("\"nicknames_required\":false"))
    #expect(json.contains("\"battle_style\":\"shift\""))
    #expect(json.contains("\"game_id\":12"))
}
