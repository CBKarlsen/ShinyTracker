import Foundation
import ShinyTrackerKit

/// Response and request shapes for the v1 endpoints, derived from the Go handlers in
/// `backend/internal/api/` and the DDL in `backend/schema.sql`.
///
/// Every type spells its `CodingKeys` out rather than using
/// `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase`. That strategy also rewrites
/// **dictionary** keys, so `hunt_parameters: {"chain_length": 30}` would decode as
/// `chainLength` and every `params.int("chain_length", …)` lookup in `ShinyTrackerKit` would
/// silently fall back to its default — wrong odds, no error. Explicit keys, no strategy.

// MARK: - Reference data

/// `GET /api/me` — `MeHandler` returns exactly these three fields (it upserts the profile row).
public struct Profile: Decodable, Sendable, Equatable {
    public let id: UUID
    public let username: String
    public let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case id, username
        case isAdmin = "is_admin"
    }
}

/// `GET /api/games` — `models.Game`.
public struct Game: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let generation: Int
    public let baseOdds: Int

    enum CodingKeys: String, CodingKey {
        case id, title, generation
        case baseOdds = "base_odds"
    }
}

/// `GET /api/pokemon` — `models.Pokemon`.
public struct Pokemon: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let spriteURL: String
    /// `pokemon.types` is a nullable `jsonb` holding a string array (`services/pokeapi.go`
    /// marshals `[]string`), and a nil slice marshals to `null` — hence optional.
    public let types: [String]?
    public let isLegendary: Bool
    public let isMythical: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, types
        case spriteURL = "sprite_url"
        case isLegendary = "is_legendary"
        case isMythical = "is_mythical"
    }
}

/// One node of an evolution line — `calc.EvolveFrom`.
public struct EvolutionLink: Decodable, Sendable, Equatable {
    public let pokemonID: Int
    public let name: String

    enum CodingKeys: String, CodingKey {
        case name
        case pokemonID = "pokemon_id"
    }
}

/// One `pokemon_locations` row — `api.PokemonLocationDetail`. The numeric columns and
/// `conditions` are `COALESCE`d in the query, so none of them arrive as null.
public struct PokemonLocation: Decodable, Sendable, Equatable {
    public let gameID: Int
    public let area: String
    public let version: String
    public let terrain: String
    public let minLevel: Int
    public let maxLevel: Int
    public let chance: Int
    public let conditions: [String]

    enum CodingKeys: String, CodingKey {
        case area, version, terrain, chance, conditions
        case gameID = "game_id"
        case minLevel = "min_level"
        case maxLevel = "max_level"
    }
}

/// `GET /api/pokemon/{id}` — `api.PokemonDetail`. The three list fields are explicitly
/// nil-guarded to `[]` by the handler before encoding, so they are never null.
public struct PokemonDetail: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let spriteURL: String
    public let types: [String]?
    public let canBreed: Bool
    public let isLegendary: Bool
    public let isMythical: Bool
    public let evolvesFromID: Int?
    /// Pre-evolution line, nearest first.
    public let evolvesFrom: [EvolutionLink]
    /// Direct evolutions.
    public let evolvesTo: [EvolutionLink]
    public let locations: [PokemonLocation]

    enum CodingKeys: String, CodingKey {
        case id, name, types, locations
        case spriteURL = "sprite_url"
        case canBreed = "can_breed"
        case isLegendary = "is_legendary"
        case isMythical = "is_mythical"
        case evolvesFromID = "evolves_from_id"
        case evolvesFrom = "evolves_from"
        case evolvesTo = "evolves_to"
    }
}

/// `GET /api/methods` — `api.MethodDetail`. One row per (game, method name).
public struct MethodDetail: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let gameID: Int
    public let gameTitle: String
    public let methodName: String
    public let baseRolls: Int
    public let charmRolls: Int
    public let avgTimeSeconds: Int
    public let formulaType: String

    enum CodingKeys: String, CodingKey {
        case id
        case gameID = "game_id"
        case gameTitle = "game_title"
        case methodName = "method_name"
        case baseRolls = "base_rolls"
        case charmRolls = "charm_rolls"
        case avgTimeSeconds = "avg_time_seconds"
        case formulaType = "formula_type"
    }
}

/// `GET /api/hunt-methods?pokemon_id=` — `api.HuntMethodDetail`. Same columns as
/// ``MethodDetail`` plus the Pokemon it was resolved for. Only covers games the user owns.
public struct HuntMethodDetail: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let pokemonID: Int
    public let gameID: Int
    public let gameTitle: String
    public let methodName: String
    public let avgTimeSeconds: Int
    public let baseRolls: Int
    public let charmRolls: Int
    public let formulaType: String

    enum CodingKeys: String, CodingKey {
        case id
        case pokemonID = "pokemon_id"
        case gameID = "game_id"
        case gameTitle = "game_title"
        case methodName = "method_name"
        case avgTimeSeconds = "avg_time_seconds"
        case baseRolls = "base_rolls"
        case charmRolls = "charm_rolls"
        case formulaType = "formula_type"
    }
}

/// `GET /api/user/{id}/games` — `models.UserGame`.
public struct UserGame: Decodable, Sendable, Equatable {
    public let userID: UUID
    public let gameID: Int
    public let hasShinyCharm: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case gameID = "game_id"
        case hasShinyCharm = "has_shiny_charm"
    }
}

// MARK: - Hunts

/// `models.UserHunt` — what `POST /api/hunts` and `PATCH /api/hunts/{id}` return.
///
/// `gameID` and `huntMethodID` are genuinely nullable: a custom-method hunt is inserted with
/// both NULL (`CreateHuntHandler`), and `PHASE` / `MANUAL_OVERRIDE` rows carry a NULL
/// `hunt_method_id`. Do not "simplify" them to non-optionals — every custom-method hunt would
/// stop decoding.
///
/// `gameID` is additionally always null on the `PATCH` response: `UpdateHuntHandler`'s
/// `RETURNING` clause omits `game_id`, so Go encodes the zero value of the pointer. Read the
/// game from the hunt list, not from a patch result.
public struct Hunt: Decodable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userID: UUID
    public let pokemonID: Int
    public let gameID: Int?
    public let huntMethodID: Int?
    public let encounterCount: Int
    public let phaseCount: Int
    /// `"active"` or `"completed"`. Kept as a `String` rather than an enum so an added status
    /// can never fail the decode of a whole hunt list; ``HuntStatus`` types the write side.
    public let status: String
    /// `HUNTED`, `PHASE`, or `MANUAL_OVERRIDE`.
    public let acquisitionType: String
    /// Open JSONB. `ParamValue` comes from `ShinyTrackerKit` — the same decoder the odds
    /// engine consumes, which tolerates nulls/strings/out-of-range numbers per key. The
    /// column is nullable, so the dictionary itself is optional.
    public let huntParameters: [String: ParamValue]?
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status
        case userID = "user_id"
        case pokemonID = "pokemon_id"
        case gameID = "game_id"
        case huntMethodID = "hunt_method_id"
        case encounterCount = "encounter_count"
        case phaseCount = "phase_count"
        case acquisitionType = "acquisition_type"
        case huntParameters = "hunt_parameters"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// One `hunt_phases` row, joined with its Pokemon — `models.HuntPhase`.
public struct HuntPhase: Decodable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let huntID: UUID
    public let pokemonID: Int
    public let pokemonName: String
    public let spriteURL: String
    public let encounterCountAtPhase: Int
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case huntID = "hunt_id"
        case pokemonID = "pokemon_id"
        case pokemonName = "pokemon_name"
        case spriteURL = "sprite_url"
        case encounterCountAtPhase = "encounter_count_at_phase"
        case createdAt = "created_at"
    }
}

/// `models.UserHuntDetail` — `GET /api/hunts` and `POST /api/hunts/{id}/phases`.
///
/// Go embeds `UserHunt`, which flattens into the same JSON object, so this is a flat struct
/// too. Everything from the `LEFT JOIN`s is optional: a custom-method hunt has no method row,
/// no game row and therefore no charm flag. `formulaType` is `COALESCE`d to `'static'` in SQL
/// but stays optional because the column is left-joined.
public struct HuntDetail: Decodable, Sendable, Equatable, Identifiable {
    // --- embedded UserHunt ---
    public let id: UUID
    public let userID: UUID
    public let pokemonID: Int
    public let gameID: Int?
    public let huntMethodID: Int?
    public let encounterCount: Int
    public let phaseCount: Int
    public let status: String
    public let acquisitionType: String
    public let huntParameters: [String: ParamValue]?
    public let createdAt: Date
    public let updatedAt: Date

    // --- join detail ---
    public let pokemonName: String
    public let methodName: String?
    public let customMethodName: String?
    public let gameTitle: String?
    public let totalTimeSeconds: Int
    public let baseRolls: Int?
    public let charmRolls: Int?
    public let avgTimeSeconds: Int?
    public let baseOdds: Int?
    public let hasShinyCharm: Bool?
    public let formulaType: String?
    public let phases: [HuntPhase]

    enum CodingKeys: String, CodingKey {
        case id, status, phases
        case userID = "user_id"
        case pokemonID = "pokemon_id"
        case gameID = "game_id"
        case huntMethodID = "hunt_method_id"
        case encounterCount = "encounter_count"
        case phaseCount = "phase_count"
        case acquisitionType = "acquisition_type"
        case huntParameters = "hunt_parameters"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case pokemonName = "pokemon_name"
        case methodName = "method_name"
        case customMethodName = "custom_method_name"
        case gameTitle = "game_title"
        case totalTimeSeconds = "total_time_seconds"
        case baseRolls = "base_rolls"
        case charmRolls = "charm_rolls"
        case avgTimeSeconds = "avg_time_seconds"
        case baseOdds = "base_odds"
        case hasShinyCharm = "has_shiny_charm"
        case formulaType = "formula_type"
    }
}

// MARK: - Request bodies

/// The only two values `UpdateHuntHandler` accepts; anything else is a 400.
public enum HuntStatus: String, Codable, Sendable {
    case active, completed
}

/// `POST /api/hunts`. Supply *either* `huntMethodID` + `gameID` (curated) *or*
/// `customMethodName` (the handler rejects both together, and rejects negative method ids).
public struct CreateHuntRequest: Codable, Sendable, Equatable {
    public let pokemonID: Int
    public let gameID: Int?
    public let huntMethodID: Int?
    public let customMethodName: String?
    public let huntParameters: [String: ParamValue]?

    public init(
        pokemonID: Int,
        gameID: Int? = nil,
        huntMethodID: Int? = nil,
        customMethodName: String? = nil,
        huntParameters: [String: ParamValue]? = nil
    ) {
        self.pokemonID = pokemonID
        self.gameID = gameID
        self.huntMethodID = huntMethodID
        self.customMethodName = customMethodName
        self.huntParameters = huntParameters
    }

    enum CodingKeys: String, CodingKey {
        case pokemonID = "pokemon_id"
        case gameID = "game_id"
        case huntMethodID = "hunt_method_id"
        case customMethodName = "custom_method_name"
        case huntParameters = "hunt_parameters"
    }
}

/// `PATCH /api/hunts/{id}`.
///
/// `totalTimeSeconds` is optional and, being an `Optional` property, is **omitted** by the
/// synthesised encoder when nil rather than written as `null` — which is what the server
/// needs: `UpdateHuntHandler` decodes it into a `*int` and treats absent as "keep deriving
/// time server-side". Supplying a value latches `client_owns_time` on, making the hunt
/// client-time-authoritative from then on (decision D1, `docs/handoff/DECISIONS.md`, see
/// `calc.DecideTotalTime`). Omitting `huntParameters` likewise leaves the stored JSONB alone.
public struct UpdateHuntRequest: Codable, Sendable, Equatable {
    public let encounterCount: Int
    public let status: HuntStatus
    public let huntParameters: [String: ParamValue]?
    public let totalTimeSeconds: Int?

    public init(
        encounterCount: Int,
        status: HuntStatus,
        huntParameters: [String: ParamValue]? = nil,
        totalTimeSeconds: Int? = nil
    ) {
        self.encounterCount = encounterCount
        self.status = status
        self.huntParameters = huntParameters
        self.totalTimeSeconds = totalTimeSeconds
    }

    enum CodingKeys: String, CodingKey {
        case status
        case encounterCount = "encounter_count"
        case huntParameters = "hunt_parameters"
        case totalTimeSeconds = "total_time_seconds"
    }
}

/// `POST /api/hunts/{id}/phases` — the Pokemon that interrupted the hunt.
public struct LogPhaseRequest: Codable, Sendable, Equatable {
    public let pokemonID: Int

    public init(pokemonID: Int) { self.pokemonID = pokemonID }

    enum CodingKeys: String, CodingKey {
        case pokemonID = "pokemon_id"
    }
}

/// `POST /api/user/{id}/games/{gameId}` — upserts ownership and the charm flag.
public struct SetUserGameRequest: Codable, Sendable, Equatable {
    public let hasShinyCharm: Bool

    public init(hasShinyCharm: Bool) { self.hasShinyCharm = hasShinyCharm }

    enum CodingKeys: String, CodingKey {
        case hasShinyCharm = "has_shiny_charm"
    }
}
