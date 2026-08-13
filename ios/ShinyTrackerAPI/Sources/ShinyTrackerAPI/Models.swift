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
///
/// The response types are `Codable` rather than `Decodable` because ``SnapshotStore`` writes them
/// back out to disk. The encoding is never sent to the server — it re-reads its own files — so the
/// synthesised `encode` only has to round-trip against the synthesised `init(from:)`, which the
/// shared `CodingKeys` guarantee.

// MARK: - Reference data

/// `GET /api/me` — `MeHandler` returns exactly these three fields (it upserts the profile row).
public struct Profile: Codable, Sendable, Equatable {
    public let id: UUID
    public let username: String
    public let isAdmin: Bool

    enum CodingKeys: String, CodingKey {
        case id, username
        case isAdmin = "is_admin"
    }
}

/// `GET /api/games` — `models.Game`.
public struct Game: Codable, Sendable, Equatable, Identifiable {
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
public struct Pokemon: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let spriteURL: String
    /// The shiny variant from `pokemon.shiny_sprite_url`. Optional and possibly `""`: the
    /// column is newer than the shipped app, and older rows stay blank until migration 016's
    /// backfill runs. Callers fall back rather than showing a hole — see `SpriteSource`.
    public let shinySpriteURL: String?
    /// `pokemon.types` is a nullable `jsonb` holding a string array (`services/pokeapi.go`
    /// marshals `[]string`), and a nil slice marshals to `null` — hence optional.
    public let types: [String]?
    public let isLegendary: Bool
    public let isMythical: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, types
        case spriteURL = "sprite_url"
        case shinySpriteURL = "shiny_sprite_url"
        case isLegendary = "is_legendary"
        case isMythical = "is_mythical"
    }
}

/// One node of an evolution line — `calc.EvolveFrom`.
public struct EvolutionLink: Codable, Sendable, Equatable {
    public let pokemonID: Int
    public let name: String

    enum CodingKeys: String, CodingKey {
        case name
        case pokemonID = "pokemon_id"
    }
}

/// One `pokemon_locations` row — `api.PokemonLocationDetail`. The numeric columns and
/// `conditions` are `COALESCE`d in the query, so none of them arrive as null.
public struct PokemonLocation: Codable, Sendable, Equatable {
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

/// Six base stats — `api.PokemonStats`. Absent (not zero) for a species `cmd/seed_moves` has
/// not been through, which is why the handler declares it `omitempty`.
public struct PokemonStats: Codable, Sendable, Equatable {
    public let hp: Int
    public let attack: Int
    public let defense: Int
    public let specialAttack: Int
    public let specialDefense: Int
    public let speed: Int

    public var total: Int { hp + attack + defense + specialAttack + specialDefense + speed }

    /// In the order every stat block in the game prints them.
    public var ordered: [(label: String, value: Int)] {
        [
            ("HP", hp), ("Atk", attack), ("Def", defense),
            ("SpA", specialAttack), ("SpD", specialDefense), ("Spe", speed),
        ]
    }

    enum CodingKeys: String, CodingKey {
        case hp, attack, defense, speed
        case specialAttack = "special_attack"
        case specialDefense = "special_defense"
    }
}

/// One ability slot — `api.PokemonAbilityDetail`.
public struct PokemonAbility: Codable, Sendable, Equatable, Identifiable {
    public let slug: String
    public let name: String
    public let effect: String
    public let slot: Int
    public let isHidden: Bool

    public var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, effect, slot
        case isHidden = "is_hidden"
    }
}

/// One moveset entry for one game — `api.PokemonMoveDetail`.
///
/// `power` and `accuracy` are genuinely null for status and always-hit moves, and `level` is
/// non-null only for `method == "level-up"`; none of the three may be flattened to 0, which
/// would read as "0 power" rather than "not applicable".
public struct PokemonMove: Codable, Sendable, Equatable, Identifiable {
    public let slug: String
    public let name: String
    /// A PokeAPI type slug — `"ground"`. `PokemonType(slug:)` in `ShinyTrackerUI` parses it.
    public let type: String
    public let damageClass: String
    public let power: Int?
    public let accuracy: Int?
    public let pp: Int
    public let effect: String
    /// `level-up` | `tm` | `egg` | `tutor`.
    public let method: String
    public let level: Int?

    /// The same move can arrive twice for one game — learned by level-up *and* on a TM — so the
    /// slug alone is not unique and would collapse the two rows in a `ForEach`.
    public var id: String { "\(method)-\(slug)" }

    enum CodingKeys: String, CodingKey {
        case slug, name, type, power, accuracy, pp, effect, method, level
        case damageClass = "damage_class"
    }
}

/// `GET /api/pokemon/{id}` — `api.PokemonDetail`. `evolves_from`, `evolves_to` and `locations`
/// are explicitly nil-guarded to `[]` by the handler before encoding, so they are never null.
///
/// ``stats``, ``abilities`` and ``moves`` were added for the Dex species sheet and are all
/// optional *for compatibility, not only for nullability*: a client built against the older
/// handler must keep decoding a response that has none of the three keys, and Swift's
/// synthesised decoder treats a missing key as nil only for `Optional` properties.
/// - ``stats`` is absent for a species without seeded base stats.
/// - ``abilities`` is always present from the current handler (`[]` at worst).
/// - ``moves`` is `null` when the request carried no `game_id`, and `[]` when it did but that
///   game has no seeded moveset — the handler keeps those two cases distinct on purpose.
public struct PokemonDetail: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let spriteURL: String
    /// The shiny variant from `pokemon.shiny_sprite_url`. Optional and possibly `""`: the
    /// column is newer than the shipped app, and older rows stay blank until migration 016's
    /// backfill runs. Callers fall back rather than showing a hole — see `SpriteSource`.
    public let shinySpriteURL: String?
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
    public let stats: PokemonStats?
    public let abilities: [PokemonAbility]?
    public let moves: [PokemonMove]?

    enum CodingKeys: String, CodingKey {
        case id, name, types, locations, stats, abilities, moves
        case spriteURL = "sprite_url"
        case shinySpriteURL = "shiny_sprite_url"
        case canBreed = "can_breed"
        case isLegendary = "is_legendary"
        case isMythical = "is_mythical"
        case evolvesFromID = "evolves_from_id"
        case evolvesFrom = "evolves_from"
        case evolvesTo = "evolves_to"
    }
}

/// `GET /api/dex/status` — `api.DexStatusResponse`.
///
/// Note what this does and does not say. `notInYourGames` is "available somewhere, but in none
/// of the games *you own*" — it is not per-game, and there is no endpoint that is.
/// `lockedEverywhere` is shiny-locked in every game it appears in, i.e. it can never be caught
/// shiny by anyone. Both lists are nil-guarded to `[]` by the handler.
public struct DexStatus: Codable, Sendable, Equatable {
    public let notInYourGames: [Int]
    public let lockedEverywhere: [Int]

    enum CodingKeys: String, CodingKey {
        case notInYourGames = "not_in_your_games"
        case lockedEverywhere = "locked_everywhere"
    }
}

/// `GET /api/methods` — `api.MethodDetail`. One row per (game, method name).
public struct MethodDetail: Codable, Sendable, Equatable, Identifiable {
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
public struct HuntMethodDetail: Codable, Sendable, Equatable, Identifiable {
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
public struct UserGame: Codable, Sendable, Equatable {
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
public struct Hunt: Codable, Sendable, Equatable, Identifiable {
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
public struct HuntPhase: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let huntID: UUID
    public let pokemonID: Int
    public let pokemonName: String
    public let spriteURL: String
    /// The shiny variant from `pokemon.shiny_sprite_url`. Optional and possibly `""`: the
    /// column is newer than the shipped app, and older rows stay blank until migration 016's
    /// backfill runs. Callers fall back rather than showing a hole — see `SpriteSource`.
    public let shinySpriteURL: String?
    public let encounterCountAtPhase: Int
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case huntID = "hunt_id"
        case pokemonID = "pokemon_id"
        case pokemonName = "pokemon_name"
        case spriteURL = "sprite_url"
        case shinySpriteURL = "shiny_sprite_url"
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
public struct HuntDetail: Codable, Sendable, Equatable, Identifiable {
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
    /// `pokemon.sprite_url` — the **non-shiny** sprite, `""` when the species has none. There is
    /// no shiny sprite in the database, so a shiny hunt's own sprite still has to be derived
    /// client-side; see ``SpriteTile``.
    ///
    /// Optional where ``Pokemon/spriteURL`` is not, on purpose: this field is newer than the
    /// shipped app, and the app updates on its own schedule. Requiring it would turn an older
    /// server into a hunts list that fails to decode at all rather than one without sprites.
    public let spriteURL: String?
    /// The shiny variant from `pokemon.shiny_sprite_url`. Optional and possibly `""`: the
    /// column is newer than the shipped app, and older rows stay blank until migration 016's
    /// backfill runs. Callers fall back rather than showing a hole — see `SpriteSource`.
    public let shinySpriteURL: String?
    /// Optional name the user gave this catch. Absent stays absent — the server never coerces
    /// it to `""`, and omitting it from a PATCH leaves the stored value untouched.
    public let nickname: String?
    public let phases: [HuntPhase]

    enum CodingKeys: String, CodingKey {
        case id, status, phases, nickname
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
        case spriteURL = "sprite_url"
        case shinySpriteURL = "shiny_sprite_url"
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
    /// Optional name for the catch. The server rejects anything over 100 characters with a 400,
    /// so a field bound to this wants the same cap on its input.
    public let nickname: String?

    public init(
        pokemonID: Int,
        gameID: Int? = nil,
        huntMethodID: Int? = nil,
        customMethodName: String? = nil,
        huntParameters: [String: ParamValue]? = nil,
        nickname: String? = nil
    ) {
        self.pokemonID = pokemonID
        self.gameID = gameID
        self.huntMethodID = huntMethodID
        self.customMethodName = customMethodName
        self.huntParameters = huntParameters
        self.nickname = nickname
    }

    enum CodingKeys: String, CodingKey {
        case pokemonID = "pokemon_id"
        case gameID = "game_id"
        case huntMethodID = "hunt_method_id"
        case customMethodName = "custom_method_name"
        case huntParameters = "hunt_parameters"
        case nickname
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
    public let encounterCount: Int?
    public let encounterDelta: Int?
    /// The server's idempotency key for the delta path: a retried queued write that already
    /// landed must not apply twice. Required whenever `encounterDelta` is present (and rejected
    /// as a 400 otherwise).
    public let writeID: UUID?
    /// Optional so the delta initialiser can omit it: a count-only queued write has no status to
    /// send, and the server's `COALESCE($2, status)` leaves the row alone rather than the client
    /// inventing `.active` and reopening a hunt completed on another device.
    public let status: HuntStatus?
    public let huntParameters: [String: ParamValue]?
    public let totalTimeSeconds: Int?
    /// The absolute path: the count is stored as submitted. No iOS caller counts through this —
    /// counting goes through the delta initialiser below — so it is reachable only from a caller
    /// that knows the true count outright.
    public init(
        encounterCount: Int,
        status: HuntStatus,
        huntParameters: [String: ParamValue]? = nil,
        totalTimeSeconds: Int? = nil
    ) {
        self.encounterCount = encounterCount
        self.encounterDelta = nil
        self.writeID = nil
        self.status = status
        self.huntParameters = huntParameters
        self.totalTimeSeconds = totalTimeSeconds
    }

    /// The relative path, for queued writes. `writeID` is the idempotency key: a retried delta
    /// that already landed must not apply twice. Two initialisers rather than one with everything
    /// optional, so a caller cannot express "both an absolute count and a delta" or "neither" —
    /// states the server would otherwise have to reject at runtime.
    public init(
        status: HuntStatus? = nil,
        encounterDelta: Int,
        writeID: UUID,
        huntParameters: [String: ParamValue]? = nil,
        totalTimeSeconds: Int? = nil
    ) {
        self.encounterCount = nil
        self.encounterDelta = encounterDelta
        self.writeID = writeID
        self.status = status
        self.huntParameters = huntParameters
        self.totalTimeSeconds = totalTimeSeconds
    }

    enum CodingKeys: String, CodingKey {
        case status
        case encounterCount = "encounter_count"
        case encounterDelta = "encounter_delta"
        case writeID = "write_id"
        case huntParameters = "hunt_parameters"
        case totalTimeSeconds = "total_time_seconds"
    }
}

/// `POST /api/hunts/manual` — registers a shiny you already own as a completed hunt with
/// `acquisition_type = 'MANUAL_OVERRIDE'`. That type is exactly what
/// `DELETE /api/hunts/manual/{pokemonId}` filters on, so a hunt you actually finished in Hunt
/// (`HUNTED` / `PHASE`) cannot be deleted through this pair at all.
public struct ManualCatchRequest: Codable, Sendable, Equatable {
    public let pokemonID: Int

    public init(pokemonID: Int) { self.pokemonID = pokemonID }

    enum CodingKeys: String, CodingKey {
        case pokemonID = "pokemon_id"
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

// MARK: - Nuzlocke

/// One species in a location's seeded wild encounter pool — `models.NuzlockeEncounterOption`.
///
/// `PutRunEncounterHandler` validates the logged `pokemon_id` against exactly this pool, so a
/// picker must offer these and nothing else: anything off-pool is a 400.
public struct NuzlockeEncounterOption: Codable, Sendable, Equatable, Identifiable {
    public let pokemonID: Int
    public let pokemonName: String
    public let spriteURL: String

    public var id: Int { pokemonID }

    enum CodingKeys: String, CodingKey {
        case pokemonID = "pokemon_id"
        case pokemonName = "pokemon_name"
        case spriteURL = "sprite_url"
    }
}

/// One move on a boss squad member — `models.NuzlockeBossMove`.
public struct NuzlockeBossMove: Codable, Sendable, Equatable {
    public let name: String
    public let type: String
    /// Base power, or **0 for a variable-power move** — Grass Knot, Metal Burst, Gyro Ball,
    /// Endeavor, Night Shade. Zero here does not mean harmless; use ``isDamaging``.
    public let power: Int
    /// `physical` | `special` | `status`. The honest test for "will this hurt me", because
    /// `moves.power` is NULL for every variable-power damaging move and seeds as 0 (migration
    /// 017). Fifteen of Platinum's seeded boss moves are in exactly that state.
    public let damageClass: String

    /// Whether this move deals damage at all.
    public var isDamaging: Bool { damageClass != "status" }

    enum CodingKeys: String, CodingKey {
        case name, type, power
        case damageClass = "damage_class"
    }
}

/// One member of a boss's squad — `models.NuzlockeBossMon`.
public struct NuzlockeBossMon: Codable, Sendable, Equatable, Identifiable {
    public let pokemonID: Int
    public let pokemonName: String
    public let spriteURL: String
    public let level: Int
    public let ability: String
    /// Optional because it arrives as literal `null`, not because the key is missing: unlike the
    /// timeline entry's `encounters`/`squad`, `models.NuzlockeBossMon.Moves` carries **no**
    /// `omitempty`, and a nil Go slice marshals to `null`. A squad member with no seeded moves
    /// therefore sends `"moves":null`.
    public let moves: [NuzlockeBossMove]?

    public var id: Int { pokemonID }

    enum CodingKeys: String, CodingKey {
        case level, ability, moves
        case pokemonID = "pokemon_id"
        case pokemonName = "pokemon_name"
        case spriteURL = "sprite_url"
    }
}

/// One point on the seeded route timeline — `models.NuzlockeTimelineEntry`.
///
/// Two shapes in one type, discriminated by ``kind``: a `location` carries ``encounters``, a
/// `boss` carries ``bossTitle``/``place``/``levelCap``/``squad``. Every one of those is
/// `omitempty` in Go, so the other kind's fields are simply absent — optional, not empty.
public struct NuzlockeTimelineEntry: Codable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let slug: String
    /// `"location"` or `"boss"` — a `CHECK` constraint, but kept a `String` for the same reason
    /// hunt status is: an added kind must not fail the decode of the whole timeline.
    public let kind: String
    public let name: String
    public let sortOrder: Int
    public let place: String?
    public let bossTitle: String?
    public let levelCap: Int?
    public let encounters: [NuzlockeEncounterOption]?
    public let squad: [NuzlockeBossMon]?

    public var isBoss: Bool { kind == "boss" }

    enum CodingKeys: String, CodingKey {
        case id, slug, kind, name, place, squad, encounters
        case sortOrder = "sort_order"
        case bossTitle = "boss_title"
        case levelCap = "level_cap"
    }
}

/// One seeded version of a game, plus the starter choices its rosters depend on —
/// `models.NuzlockeVersionInfo`. Empty ``starters`` means the rosters are identical whatever
/// you picked, so the run need not record one and the UI must not ask.
public struct NuzlockeVersionInfo: Codable, Sendable, Equatable, Identifiable {
    public let version: String
    public let starters: [String]

    public var id: String { version }
}

/// One playthrough — `models.NuzlockeRun`, from `GET/POST /api/runs` and `PATCH /api/runs/{id}`.
///
/// `gameID`/`gameTitle` are both nullable: the FK is `ON DELETE SET NULL`, so a run outlives the
/// game row it was started against. A run in that state can no longer log anything — every write
/// handler 400s with "This run has no game set".
public struct NuzlockeRun: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let userID: UUID
    public let gameID: Int?
    /// Which version's timeline this run follows — `platinum`, `diamond`, … Fixed at creation:
    /// one `games` row covers all three Sinnoh versions and they disagree about both routes and
    /// trainers (Fantina is gym 3 in Platinum, gym 5 in D/P).
    public let version: String
    /// The starter this player picked, or `""` when the timeline's rosters don't depend on one.
    /// Rival squads arrive already filtered by it, so what you receive is the team you will
    /// actually fight.
    public let starter: String
    public let gameTitle: String?
    public let dupesClause: Bool
    /// `"set"` or `"shift"`. ``BattleStyle`` types the write side.
    public let battleStyle: String
    public let nicknamesRequired: Bool
    /// `"active"` or `"ended"`. ``RunStatus`` types the write side.
    public let status: String
    public let startedAt: Date
    public let endedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public var isActive: Bool { status == "active" }

    enum CodingKeys: String, CodingKey {
        case id, status, version, starter
        case userID = "user_id"
        case gameID = "game_id"
        case gameTitle = "game_title"
        case dupesClause = "dupes_clause"
        case battleStyle = "battle_style"
        case nicknamesRequired = "nicknames_required"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// The encounter logged at one location of one run — `models.NuzlockeEncounterLog`.
///
/// `pokemonName` is joined in by `GetRunHandler` **only**. The `PUT` and `PATCH` responses come
/// from a `RETURNING` clause with no join, so they carry `pokemon_id` and no name — a caller
/// that renders one of those directly must supply the name from the pool it picked out of.
///
/// `locationSlug` is likewise empty on nothing: `PutRunEncounterHandler` sets it from the path
/// and the `PATCH` re-selects it, so it is always populated in practice.
public struct NuzlockeEncounterLog: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let runID: UUID
    public let locationSlug: String
    public let pokemonID: Int?
    public let pokemonName: String?
    public let nickname: String?
    /// `"caught"`, `"missed"`, `"fainted"` or `"ran"` — see ``EncounterStatus``.
    public let status: String
    public let nature: String?
    public let isBoxed: Bool
    /// Server-computed, never sent: `PutRunEncounterHandler` sets it when the run's dupes clause
    /// is on and that species is already caught at another location.
    public let isDupe: Bool
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, nickname, status, nature
        case runID = "run_id"
        case locationSlug = "location_slug"
        case pokemonID = "pokemon_id"
        case pokemonName = "pokemon_name"
        case isBoxed = "is_boxed"
        case isDupe = "is_dupe"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// The beaten flag for one boss of one run — `models.NuzlockeBossProgress`.
public struct NuzlockeBossProgress: Codable, Sendable, Equatable, Identifiable {
    public let bossSlug: String
    public let beaten: Bool

    public var id: String { bossSlug }

    enum CodingKeys: String, CodingKey {
        case beaten
        case bossSlug = "boss_slug"
    }
}

/// `GET /api/runs/{id}` — `models.NuzlockeRunDetail`.
///
/// Go embeds `NuzlockeRun`, which flattens into the same JSON object, so this is a flat struct
/// for the same reason ``HuntDetail`` is. The three list fields are always present (the handler
/// initialises them to empty slices), unlike most list responses in this API.
public struct NuzlockeRunDetail: Codable, Sendable, Equatable, Identifiable {
    // --- embedded NuzlockeRun ---
    public let id: UUID
    public let userID: UUID
    public let gameID: Int?
    public let version: String
    public let starter: String
    public let gameTitle: String?
    public let dupesClause: Bool
    public let battleStyle: String
    public let nicknamesRequired: Bool
    public let status: String
    public let startedAt: Date
    public let endedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    // --- everything logged against it ---
    public let timeline: [NuzlockeTimelineEntry]
    public let encounters: [NuzlockeEncounterLog]
    public let bossProgress: [NuzlockeBossProgress]

    public var isActive: Bool { status == "active" }

    enum CodingKeys: String, CodingKey {
        case id, status, timeline, encounters, version, starter
        case userID = "user_id"
        case gameID = "game_id"
        case gameTitle = "game_title"
        case dupesClause = "dupes_clause"
        case battleStyle = "battle_style"
        case nicknamesRequired = "nicknames_required"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case bossProgress = "boss_progress"
    }
}

// MARK: - Nuzlocke request bodies

/// The two values `CreateRunHandler` accepts; anything else is a 400.
public enum BattleStyle: String, Codable, Sendable, CaseIterable {
    case set, shift
}

/// The two values `UpdateRunHandler` accepts. A run is never deleted — ending it stamps
/// `ended_at` and archives it.
public enum RunStatus: String, Codable, Sendable {
    case active, ended
}

/// What happened at a location. `caught` and `fainted` are the two that carry a Pokemon, and
/// therefore the two that need a `pokemon_id` — and, on a run with nicknames required, a
/// nickname. `missed`/`ran` take neither.
public enum EncounterStatus: String, Codable, Sendable, CaseIterable {
    case caught, missed, fainted, ran

    /// Whether `PutRunEncounterHandler` requires `pokemon_id` for this status.
    public var carriesPokemon: Bool { self == .caught || self == .fainted }
}

/// Where a caught Pokemon sits now — `PatchPartyMemberHandler`'s vocabulary, which is *not* the
/// encounter-status vocabulary: `alive`/`boxed` both store `status = "caught"` and differ only in
/// `is_boxed`, and `fainted` leaves `is_boxed` untouched.
public enum PartyStatus: String, Codable, Sendable {
    case alive, boxed, fainted
}

/// `POST /api/runs`. Omitting a clause is not the same as sending `false`: the server defaults
/// `dupes_clause` and `nicknames_required` to **true** and `battle_style` to `"set"`, so these
/// are non-optional here and always sent explicitly.
public struct CreateRunRequest: Codable, Sendable, Equatable {
    public let gameID: Int
    /// Required by the server: it validates the timeline per (game, version), so Platinum being
    /// seeded says nothing about whether Diamond is.
    public let version: String
    /// Required when — and only when — ``NuzlockeVersionInfo/starters`` is non-empty for this
    /// version. The server rejects a missing one there, and ignores it everywhere else.
    public let starter: String?
    public let dupesClause: Bool
    public let battleStyle: BattleStyle
    public let nicknamesRequired: Bool

    public init(
        gameID: Int,
        version: String,
        starter: String? = nil,
        dupesClause: Bool = true,
        battleStyle: BattleStyle = .set,
        nicknamesRequired: Bool = true
    ) {
        self.gameID = gameID
        self.version = version
        self.starter = starter
        self.dupesClause = dupesClause
        self.battleStyle = battleStyle
        self.nicknamesRequired = nicknamesRequired
    }

    enum CodingKeys: String, CodingKey {
        case version, starter
        case gameID = "game_id"
        case dupesClause = "dupes_clause"
        case battleStyle = "battle_style"
        case nicknamesRequired = "nicknames_required"
    }
}

/// `PATCH /api/runs/{id}` — the only field the handler reads.
public struct UpdateRunRequest: Codable, Sendable, Equatable {
    public let status: RunStatus

    public init(status: RunStatus) { self.status = status }
}

/// `PUT /api/runs/{id}/encounters/{locationSlug}` — upserts the encounter at one location.
///
/// `pokemonID` must name a species in that location's seeded pool. The optionals are omitted
/// rather than sent as `null` when nil, which the handler treats identically.
public struct LogEncounterRequest: Codable, Sendable, Equatable {
    public let pokemonID: Int?
    public let status: EncounterStatus
    public let nickname: String?
    public let nature: String?
    public let isBoxed: Bool?

    public init(
        status: EncounterStatus,
        pokemonID: Int? = nil,
        nickname: String? = nil,
        nature: String? = nil,
        isBoxed: Bool? = nil
    ) {
        self.status = status
        self.pokemonID = pokemonID
        self.nickname = nickname
        self.nature = nature
        self.isBoxed = isBoxed
    }

    enum CodingKeys: String, CodingKey {
        case status, nickname, nature
        case pokemonID = "pokemon_id"
        case isBoxed = "is_boxed"
    }
}

/// `PATCH /api/runs/{id}/party/{memberId}` — moves one catch between alive, boxed and fainted.
public struct PartyStatusRequest: Codable, Sendable, Equatable {
    public let status: PartyStatus

    public init(status: PartyStatus) { self.status = status }
}

/// `PUT /api/runs/{id}/bosses/{bossSlug}`.
public struct BossProgressRequest: Codable, Sendable, Equatable {
    public let beaten: Bool

    public init(beaten: Bool) { self.beaten = beaten }
}
