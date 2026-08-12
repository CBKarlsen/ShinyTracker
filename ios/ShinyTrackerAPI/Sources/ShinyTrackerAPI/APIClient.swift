import Foundation
import ShinyTrackerAuth

// MARK: - Configuration

/// The Go API's base URL, read from the app bundle — never compiled in.
///
/// Same route as ``AuthConfig``: `Info.plist` gets `API_BASE_URL` from build settings, which
/// come from `ios/App/Config/Secrets.xcconfig` (gitignored; copy `Secrets.example.xcconfig`).
public struct APIConfig: Sendable {
    /// e.g. `https://api.example.com` — no trailing `/api`, the client appends paths.
    public let baseURL: URL

    public init(baseURL: URL) { self.baseURL = baseURL }

    public static func fromBundle(_ bundle: Bundle = .main) -> APIConfig {
        guard
            let raw = bundle.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
            let url = URL(string: raw), url.scheme != nil, url.host != nil
        else {
            // ponytail: fail loudly at launch, exactly like AuthConfig.fromBundle() — a missing
            // base URL is a build-configuration mistake, not a runtime condition to recover from.
            fatalError(
                """
                API_BASE_URL missing or malformed in Info.plist.
                Copy ios/App/Config/Secrets.example.xcconfig to Secrets.xcconfig, set a full \
                https:// URL, and re-run `xcodegen generate` in ios/.
                """
            )
        }
        return APIConfig(baseURL: url)
    }
}

// MARK: - Transport

/// The one seam ``APIClient`` needs for testing: swap `URLSession` for a stub.
///
/// It hands back the status code rather than the `HTTPURLResponse` because nothing here reads
/// a response header, and an `Int` crosses actor boundaries without any Sendable argument.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http.statusCode)
    }
}

// MARK: - Auth

/// How ``APIClient`` gets a bearer token and reports an unrecoverable 401.
///
/// Two closures rather than a protocol so tests need no `AuthSession` (which reads Supabase
/// config from the bundle and is `@MainActor`). Build the real one with ``session(_:)``.
public struct AuthProvider: Sendable {
    /// `forceRefresh` is true only on the single post-401 retry, where the cached token is the
    /// one the server just rejected.
    public var accessToken: @Sendable (_ forceRefresh: Bool) async throws -> String
    /// Called when a request 401s *again* after a refresh — the web client's `onSessionExpired`.
    public var markExpired: @Sendable () async -> Void

    public init(
        accessToken: @escaping @Sendable (_ forceRefresh: Bool) async throws -> String,
        markExpired: @escaping @Sendable () async -> Void
    ) {
        self.accessToken = accessToken
        self.markExpired = markExpired
    }

    public static func session(_ session: AuthSession) -> AuthProvider {
        AuthProvider(
            accessToken: { forceRefresh in
                forceRefresh
                    ? try await session.refreshAccessToken()
                    : try await session.currentAccessToken()
            },
            markExpired: { await session.markSessionExpired() }
        )
    }
}

// MARK: - Errors

/// Failures the API itself produces. Transport failures are **not** in here: `URLError` and
/// friends propagate unchanged so a flaky network is never mistaken for an expired session.
/// An unrecoverable 401 throws `ShinyTrackerAuth.SessionExpiredError`, the same type the auth
/// layer throws, so callers have one thing to catch.
public enum APIError: Error, CustomStringConvertible {
    /// Any non-2xx that is not a recoverable 401. `body` is the server's message, truncated.
    case http(status: Int, path: String, body: String)
    /// The response did not match the model. Carries the endpoint, because a bare
    /// `DecodingError` says which *field* disagreed but never which *request* produced it.
    case decoding(path: String, underlying: any Error)

    public var description: String {
        switch self {
        case .http(let status, let path, let body):
            "HTTP \(status) from \(path): \(body)"
        case .decoding(let path, let underlying):
            "Failed to decode the response of \(path): \(underlying)"
        }
    }
}

// MARK: - Client

/// Talks to the ShinyTracker Go API. One actor, `URLSession`, no networking dependency.
///
/// Scope is the v1 endpoint set in `docs/handoff/IOS_API_CLIENT_SCOPE.md`, plus `/dex/status`
/// and the manual-catch pair, which the Dex mode needs. `/dex/suggestions`, `/stats`,
/// `/export`, `/odds` and `/admin/*` are deliberately absent — odds are computed on device by
/// `ShinyTrackerKit`, which offline display needs anyway.
public actor APIClient {
    private let baseURL: URL
    private let auth: AuthProvider
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let encoder = JSONEncoder()

    public init(
        config: APIConfig = .fromBundle(),
        auth: AuthProvider,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.baseURL = config.baseURL
        self.auth = auth
        self.transport = transport
        decoder = JSONDecoder()
        // No keyDecodingStrategy on purpose — see the note at the top of Models.swift.
        decoder.dateDecodingStrategy = .custom(decodeGoTimestamp)
    }

    // MARK: Reference data

    public func me() async throws -> Profile {
        try await get("api/me")
    }

    public func games() async throws -> [Game] {
        try await getList("api/games")
    }

    /// `search` filters by `name ILIKE %q%`. The server caps results at 50 unless `all` is set.
    public func pokemon(search: String? = nil, all: Bool = false) async throws -> [Pokemon] {
        var query: [URLQueryItem] = []
        if let search, !search.isEmpty { query.append(URLQueryItem(name: "q", value: search)) }
        if all { query.append(URLQueryItem(name: "limit", value: "all")) }
        return try await getList("api/pokemon", query: query)
    }

    public func pokemonDetail(id: Int, gameID: Int? = nil) async throws -> PokemonDetail {
        try await get("api/pokemon/\(id)", query: intQuery("game_id", gameID))
    }

    /// Every species obtainable in one game — `pokemon_availability.pokemon_id`, and the Dex's
    /// per-game denominator. A game with no availability rows returns empty rather than 404.
    public func gamePokemon(gameID: Int) async throws -> [Int] {
        try await getList("api/games/\(gameID)/pokemon")
    }

    /// Every curated method, optionally narrowed to one game.
    public func methods(gameID: Int? = nil) async throws -> [MethodDetail] {
        try await getList("api/methods", query: intQuery("game_id", gameID))
    }

    /// The methods that can actually catch this Pokemon, in the games the user owns.
    public func huntMethods(pokemonID: Int) async throws -> [HuntMethodDetail] {
        try await getList("api/hunt-methods", query: intQuery("pokemon_id", pokemonID))
    }

    // MARK: Owned games

    /// The server 403s unless `userID` is the caller's own id (`AuthSession.userID`).
    public func userGames(userID: UUID) async throws -> [UserGame] {
        try await getList("api/user/\(id(userID))/games")
    }

    public func setUserGame(userID: UUID, gameID: Int, _ body: SetUserGameRequest) async throws {
        try await sendDiscardingBody("POST", "api/user/\(id(userID))/games/\(gameID)", body: body)
    }

    public func removeUserGame(userID: UUID, gameID: Int) async throws {
        try await sendDiscardingBody(
            "DELETE", "api/user/\(id(userID))/games/\(gameID)", body: noBody)
    }

    // MARK: Hunts

    public func hunts() async throws -> [HuntDetail] {
        try await getList("api/hunts")
    }

    public func createHunt(_ body: CreateHuntRequest) async throws -> Hunt {
        try await send("POST", "api/hunts", body: body)
    }

    public func updateHunt(huntID: UUID, _ body: UpdateHuntRequest) async throws -> Hunt {
        try await send("PATCH", "api/hunts/\(id(huntID))", body: body)
    }

    public func deleteHunt(huntID: UUID) async throws {
        try await sendDiscardingBody("DELETE", "api/hunts/\(id(huntID))", body: noBody)
    }

    /// Logs a phase: archives the interrupting Pokemon, resets the encounter count and returns
    /// the refreshed hunt.
    public func logPhase(huntID: UUID, _ body: LogPhaseRequest) async throws -> HuntDetail {
        try await send("POST", "api/hunts/\(id(huntID))/phases", body: body)
    }

    // MARK: Dex

    /// What the Dex may not tick: species outside your library, and species that are shiny
    /// locked in every game they appear in.
    public func dexStatus() async throws -> DexStatus {
        try await get("api/dex/status")
    }

    /// Registers a shiny the user already owns — a completed `MANUAL_OVERRIDE` hunt.
    public func markManualCatch(pokemonID: Int) async throws -> Hunt {
        try await send("POST", "api/hunts/manual", body: ManualCatchRequest(pokemonID: pokemonID))
    }

    /// Un-registers one. The handler deletes only `acquisition_type = 'MANUAL_OVERRIDE'` rows,
    /// so calling this for a shiny finished in Hunt is a no-op server-side — the Dex enforces
    /// the same rule up front rather than firing a request it knows will do nothing.
    public func removeManualCatch(pokemonID: Int) async throws {
        try await sendDiscardingBody("DELETE", "api/hunts/manual/\(pokemonID)", body: noBody)
    }

    // MARK: Nuzlocke

    /// The seeded route timeline for one game — pure reference data, not scoped to a user, and
    /// empty for a game with no seeded route (which is all of them but Platinum today). That
    /// emptiness is the only way to tell in advance what ``createRun(_:)`` would reject.
    public func nuzlockeTimeline(gameID: Int) async throws -> [NuzlockeTimelineEntry] {
        try await getList("api/nuzlocke/timeline", query: intQuery("game_id", gameID))
    }

    /// Every run the caller owns, newest first, active and ended together — the handler orders by
    /// `created_at DESC` and does not filter by status.
    public func runs() async throws -> [NuzlockeRun] {
        try await getList("api/runs")
    }

    /// Starts a run. 400s for a game with no seeded Nuzlocke timeline, which is most of them —
    /// only `seeds/nuzlocke_platinum.json` ships one — so the error is a normal outcome here,
    /// not an exceptional one, and belongs in front of the user verbatim.
    public func createRun(_ body: CreateRunRequest) async throws -> NuzlockeRun {
        try await send("POST", "api/runs", body: body)
    }

    /// One run with its timeline, logged encounters and boss progress. 404s for another user's
    /// run rather than 403, so existence is never leaked.
    public func run(id runID: UUID) async throws -> NuzlockeRunDetail {
        try await get("api/runs/\(id(runID))")
    }

    /// Ends a run (or reopens it). Runs are archived, never deleted.
    public func updateRun(id runID: UUID, _ body: UpdateRunRequest) async throws -> NuzlockeRun {
        try await send("PATCH", "api/runs/\(id(runID))", body: body)
    }

    /// Logs — or overwrites — the encounter at one location. The response has no `pokemon_name`
    /// (see ``NuzlockeEncounterLog``), so callers rendering it directly carry the name over from
    /// the pool entry they picked.
    public func logEncounter(
        runID: UUID, locationSlug: String, _ body: LogEncounterRequest
    ) async throws -> NuzlockeEncounterLog {
        try await send(
            "PUT", "api/runs/\(id(runID))/encounters/\(locationSlug)", body: body)
    }

    /// Moves one catch between alive, boxed and fainted. `memberID` is the *logged encounter's*
    /// id — a party member is a specific catch, not a location.
    public func setPartyStatus(
        runID: UUID, memberID: UUID, _ body: PartyStatusRequest
    ) async throws -> NuzlockeEncounterLog {
        try await send("PATCH", "api/runs/\(id(runID))/party/\(id(memberID))", body: body)
    }

    @discardableResult
    public func setBossBeaten(
        runID: UUID, bossSlug: String, _ body: BossProgressRequest
    ) async throws -> NuzlockeBossProgress {
        try await send("PUT", "api/runs/\(id(runID))/bosses/\(bossSlug)", body: body)
    }

    // MARK: - Plumbing

    private func get<Response: Decodable>(
        _ path: String, query: [URLQueryItem] = []
    ) async throws -> Response {
        try await send("GET", path, query: query, body: noBody)
    }

    /// Several handlers build their slice with `var xs []T`, and a nil slice marshals to
    /// `null`, not `[]` — so an empty games/pokemon/user-games/hunt-methods list arrives as
    /// literal `null`. Decode through an optional and flatten.
    private func getList<Element: Decodable>(
        _ path: String, query: [URLQueryItem] = []
    ) async throws -> [Element] {
        let list: [Element]? = try await send("GET", path, query: query, body: noBody)
        return list ?? []
    }

    private func send<Response: Decodable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: (some Encodable)?
    ) async throws -> Response {
        let data = try await perform(method, path, query: query, body: body)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(path: path, underlying: error)
        }
    }

    /// For the endpoints that answer `{"message": "..."}` — nothing to model.
    private func sendDiscardingBody(
        _ method: String, _ path: String, body: (some Encodable)?
    ) async throws {
        _ = try await perform(method, path, query: [], body: body)
    }

    /// Bearer-injects, sends, and applies the single refresh-and-retry on 401.
    ///
    /// Mirrors `frontend/src/utils/authedFetch.ts`: a 401 means the session, not the request,
    /// is the problem. Unlike the web client — which has no refresh step and expires
    /// immediately — this retries once first, because the SDK can hold a token the server has
    /// already rotated past. Exactly once: retrying an expired session in a loop is how you
    /// rate-limit yourself out of the API.
    private func perform(
        _ method: String, _ path: String, query: [URLQueryItem], body: (some Encodable)?
    ) async throws -> Data {
        var request = URLRequest(url: url(path, query))
        request.httpMethod = method
        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // A transport failure here throws URLError and leaves the session alone.
        var (data, status) = try await authorizedSend(request, forceRefresh: false)

        if status == 401 {
            (data, status) = try await authorizedSend(request, forceRefresh: true)
            if status == 401 {
                await auth.markExpired()
                throw SessionExpiredError()
            }
        }

        guard (200..<300).contains(status) else {
            throw APIError.http(status: status, path: path, body: errorBody(data))
        }
        return data
    }

    private func authorizedSend(
        _ request: URLRequest, forceRefresh: Bool
    ) async throws -> (data: Data, status: Int) {
        var request = request
        // Throws SessionExpiredError itself if the session is already unrecoverable.
        let token = try await auth.accessToken(forceRefresh)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await transport.send(request)
    }

    /// Force-unwrapped: `APIConfig` already rejected a URL without a scheme and host, and the
    /// path components are built here, not by callers.
    private func url(_ path: String, _ query: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func intQuery(_ name: String, _ value: Int?) -> [URLQueryItem] {
        value.map { [URLQueryItem(name: name, value: String($0))] } ?? []
    }

    /// `UUID.uuidString` is UPPERCASE. `GetUserGamesHandler` string-compares the `{id}` path
    /// param against `X-User-ID`, which is the JWT `sub` claim verbatim — lowercase from
    /// Supabase — so an uppercase id 403s on every owned-games call. Lowercase everywhere.
    private func id(_ value: UUID) -> String { value.uuidString.lowercased() }

    /// The Go handlers answer errors with `http.Error`, i.e. a plain-text line.
    private func errorBody(_ data: Data) -> String {
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 500 ? String(text.prefix(500)) + "…" : text
    }
}

/// Sentinel for the request-less verbs. `send`/`perform` take `(some Encodable)?`, so the
/// bodyless calls still need a concrete type to bind it to.
private let noBody: String? = nil

// MARK: - Timestamps

// Go's encoding/json writes time.Time as RFC 3339 and *trims trailing zeros* from the
// fractional part, so the same column yields "…T12:00:00Z" and "…T12:00:00.482913Z". The
// columns are `TIMESTAMP WITH TIME ZONE`, so a non-UTC offset is possible too. One fixed
// formatter would reject half of that; try fractional first, then plain.
private let rfc3339 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
private let rfc3339NoFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

/// Internal rather than private so the decoding tests can build the same decoder the client does.
@Sendable
func decodeGoTimestamp(_ decoder: any Decoder) throws -> Date {
    let text = try decoder.singleValueContainer().decode(String.self)
    if let date = try? rfc3339.parse(text) { return date }
    if let date = try? rfc3339NoFraction.parse(text) { return date }
    throw DecodingError.dataCorrupted(
        .init(codingPath: decoder.codingPath, debugDescription: "Not an RFC 3339 date: \(text)")
    )
}
