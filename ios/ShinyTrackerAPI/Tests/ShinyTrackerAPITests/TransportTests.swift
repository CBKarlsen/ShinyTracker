import Foundation
import ShinyTrackerAuth
import Testing

@testable import ShinyTrackerAPI

/// The 401 refresh-and-retry path, exercised against a stubbed transport. It is the branchiest
/// code in the package and the only place a silent bug could hide, since nothing here has ever
/// spoken to a real server.

// MARK: - Doubles

private enum Stub: Sendable {
    case response(status: Int, body: String)
    case failure(any Error)
}

private actor StubTransport: HTTPTransport {
    private var queue: [Stub]
    private(set) var requests: [URLRequest] = []

    init(_ queue: [Stub]) { self.queue = queue }

    var bearerTokens: [String?] {
        requests.map { $0.value(forHTTPHeaderField: "Authorization") }
    }

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        requests.append(request)
        guard !queue.isEmpty else {
            Issue.record("The client sent more requests than the test stubbed")
            throw URLError(.unknown)
        }
        switch queue.removeFirst() {
        case .response(let status, let body): return (Data(body.utf8), status)
        case .failure(let error): throw error
        }
    }
}

/// Stands in for `AuthSession`: counts refreshes and expiry notifications.
private actor AuthSpy {
    private(set) var tokenRequests: [Bool] = []  // the forceRefresh flag of each call
    private(set) var expiredCount = 0
    private var tokenError: (any Error)?

    init(tokenError: (any Error)? = nil) { self.tokenError = tokenError }

    var refreshCount: Int { tokenRequests.filter { $0 }.count }

    func token(forceRefresh: Bool) throws -> String {
        tokenRequests.append(forceRefresh)
        if let tokenError { throw tokenError }
        return forceRefresh ? "refreshed-token" : "cached-token"
    }

    func markExpired() { expiredCount += 1 }

    var provider: AuthProvider {
        AuthProvider(
            accessToken: { [self] force in try await token(forceRefresh: force) },
            markExpired: { [self] in await markExpired() }
        )
    }
}

private func makeClient(_ transport: StubTransport, _ auth: AuthSpy) async -> APIClient {
    await APIClient(
        config: APIConfig(baseURL: URL(string: "https://api.test.invalid")!),
        auth: auth.provider,
        transport: transport
    )
}

private let profileJSON = """
    {"id":"0b3c9a7e-1d2f-4a5b-8c6d-7e8f9a0b1c2d","username":"casper","is_admin":false}
    """

// MARK: - Happy path

@Test func injectsTheBearerTokenAndHitsTheRightURL() async throws {
    let transport = StubTransport([.response(status: 200, body: profileJSON)])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)

    let me = try await client.me()

    #expect(me.username == "casper")
    #expect(await transport.bearerTokens == ["Bearer cached-token"])
    #expect(await transport.requests[0].url?.absoluteString == "https://api.test.invalid/api/me")
    #expect(await auth.refreshCount == 0)
    #expect(await auth.expiredCount == 0)
}

@Test func sendsQueryItemsAndLowercasesPathUUIDs() async throws {
    let transport = StubTransport([
        .response(status: 200, body: #"{"message":"success"}"#),
        .response(status: 200, body: "[]"),
        .response(status: 200, body: "[]"),
    ])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)
    // Uppercase on purpose: UUID.uuidString is uppercase, and the lowercase form is what the
    // rest of the app logs, caches and keys the write queue by — an id that changes case
    // between requests is one that cannot be matched by eye.
    let huntID = UUID(uuidString: "0B3C9A7E-1D2F-4A5B-8C6D-7E8F9A0B1C2D")!

    try await client.deleteHunt(huntID: huntID)
    _ = try await client.huntMethods(pokemonID: 25)
    _ = try await client.pokemon(search: "eevee", all: true)

    let urls = await transport.requests.compactMap { $0.url?.absoluteString }
    #expect(
        urls == [
            "https://api.test.invalid/api/hunts/0b3c9a7e-1d2f-4a5b-8c6d-7e8f9a0b1c2d",
            "https://api.test.invalid/api/hunt-methods?pokemon_id=25",
            "https://api.test.invalid/api/pokemon?q=eevee&limit=all",
        ])
}

/// Handlers that build their slice with `var xs []T` send literal `null` when empty, because a
/// nil Go slice marshals to null. An empty list must not be a decode failure.
@Test func decodesAnEmptyListSentAsJSONNull() async throws {
    let transport = StubTransport([
        .response(status: 200, body: "null"), .response(status: 200, body: "null"),
    ])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)

    #expect(try await client.games().isEmpty)
    #expect(try await client.hunts().isEmpty)
}

// MARK: - 401 handling

@Test func refreshesOnceAndRetriesOnceAfterA401() async throws {
    let transport = StubTransport([
        .response(status: 401, body: "Invalid or expired token"),
        .response(status: 200, body: profileJSON),
    ])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)

    let me = try await client.me()

    #expect(me.username == "casper")
    #expect(await transport.requests.count == 2)
    // The retry must carry a *newly refreshed* token; replaying the rejected one is a
    // guaranteed second 401.
    #expect(await transport.bearerTokens == ["Bearer cached-token", "Bearer refreshed-token"])
    #expect(await auth.tokenRequests == [false, true])
    #expect(await auth.expiredCount == 0)
}

@Test func expiresTheSessionWhenTheRetryAlso401s() async throws {
    let transport = StubTransport([
        .response(status: 401, body: "Invalid or expired token"),
        .response(status: 401, body: "Invalid or expired token"),
    ])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)

    await #expect(throws: SessionExpiredError.self) { try await client.me() }

    // Exactly twice — no retry loop against a session that is definitively gone.
    #expect(await transport.requests.count == 2)
    #expect(await auth.refreshCount == 1)
    #expect(await auth.expiredCount == 1)
}

@Test func doesNotRetryNon401Failures() async throws {
    let transport = StubTransport([.response(status: 500, body: "Failed to fetch hunts")])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)

    let error = await #expect(throws: APIError.self) { try await client.hunts() }
    guard case .http(let status, let path, let body) = error else {
        Issue.record("expected APIError.http, got \(String(describing: error))")
        return
    }
    #expect(status == 500)
    #expect(path == "api/hunts")
    #expect(body == "Failed to fetch hunts")

    #expect(await transport.requests.count == 1)
    #expect(await auth.refreshCount == 0)
    #expect(await auth.expiredCount == 0)
}

@Test func doesNotRetryA403() async throws {
    let transport = StubTransport([.response(status: 403, body: "Unauthorized access")])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)

    await #expect(throws: APIError.self) {
        try await client.userGames()
    }
    #expect(await transport.requests.count == 1)
    #expect(await auth.expiredCount == 0)
}

/// A dropped connection is not an expired session. `URLError` must reach the caller unchanged
/// and must never sign the user out — the same distinction `AuthSession` already draws.
@Test func transportFailuresPropagateAndNeverExpireTheSession() async throws {
    let transport = StubTransport([.failure(URLError(.notConnectedToInternet))])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)

    await #expect(throws: URLError(.notConnectedToInternet)) { try await client.me() }
    #expect(await transport.requests.count == 1)
    #expect(await auth.refreshCount == 0)
    #expect(await auth.expiredCount == 0)
}

/// If the network dies *during* the retry, that is still a transport failure, not expiry.
@Test func transportFailureDuringTheRetryDoesNotExpireTheSession() async throws {
    let transport = StubTransport([
        .response(status: 401, body: "Invalid or expired token"),
        .failure(URLError(.timedOut)),
    ])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)

    await #expect(throws: URLError(.timedOut)) { try await client.me() }
    #expect(await auth.expiredCount == 0)
}

/// When the refresh itself fails, `AuthSession` has already marked the session expired and
/// thrown; the client must surface that rather than send a third request.
@Test func aFailedRefreshSurfacesTheAuthErrorWithoutRetrying() async throws {
    let transport = StubTransport([.response(status: 401, body: "Invalid or expired token")])
    let auth = AuthSpy(tokenError: SessionExpiredError())
    let client = await makeClient(transport, auth)

    await #expect(throws: SessionExpiredError.self) { try await client.me() }
    #expect(await transport.requests.isEmpty)  // the very first token fetch already threw
}

// MARK: - Decode errors

/// A bare `DecodingError` does not say which request produced it, which makes a field mismatch
/// miserable to chase. ``APIError/decoding(path:underlying:)`` carries the endpoint.
@Test func decodeFailuresNameTheEndpoint() async throws {
    let transport = StubTransport([.response(status: 200, body: #"{"id":"not-a-uuid"}"#)])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)

    let error = await #expect(throws: APIError.self) { try await client.me() }
    guard case .decoding(let path, let underlying) = error else {
        Issue.record("expected APIError.decoding, got \(String(describing: error))")
        return
    }
    #expect(path == "api/me")
    #expect(underlying is DecodingError)
    #expect("\(error)".contains("api/me"))
}

// MARK: - Bodies

@Test func encodesTheRequestBodyAndSetsContentType() async throws {
    let transport = StubTransport([.response(status: 200, body: #"{"message":"success"}"#)])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)

    try await client.setUserGame(gameID: 34, SetUserGameRequest(hasShinyCharm: true))

    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let body = try #require(request.httpBody.map { String(decoding: $0, as: UTF8.self) })
    #expect(body == #"{"has_shiny_charm":true}"#)
}

@Test func bodylessVerbsSendNoBody() async throws {
    let transport = StubTransport([.response(status: 200, body: #"{"message":"deleted"}"#)])
    let auth = AuthSpy()
    let client = await makeClient(transport, auth)

    try await client.deleteHunt(huntID: UUID())

    let request = try #require(await transport.requests.first)
    #expect(request.httpMethod == "DELETE")
    #expect(request.httpBody == nil)
    #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
}
