#if DEBUG
import Foundation
import ShinyTrackerAPI

/// The shared half of the three preview harnesses (``HuntPreview``, ``DexPreview``,
/// ``NuzlockePreview``).
///
/// They exist because the screens are otherwise unverifiable: signing in needs a real Supabase
/// session, so a plain simulator run shows the login screen and nothing about the design gets
/// checked. Each rides the `HTTPTransport` seam ``APIClient`` already has for its own tests — no
/// production code changes shape to accommodate them, and all of it is out of release builds.
///
/// What differs between the three is only the routing table, so that is all each one still
/// writes. The launch-argument reader, the sessionless client and the stub transport were three
/// copies of the same twenty lines.
enum PreviewHarness {
    /// The value after `-flag` in the launch arguments (Xcode scheme argument, `simctl launch`,
    /// or a `#Preview`). Nil when the flag is absent or is the last argument.
    static func argument(_ flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    /// A client with no session and no server, answering every request from `route`.
    ///
    /// - Parameter latency: a beat before each response, so the loading state is real rather
    ///   than skipped between two frames.
    static func client(
        latency: Duration = .milliseconds(200),
        route: @escaping @Sendable (_ method: String, _ path: String, _ request: URLRequest) -> (
            Data, Int
        )
    ) -> APIClient {
        APIClient(
            config: APIConfig(baseURL: URL(string: "https://preview.invalid")!),
            auth: AuthProvider(accessToken: { _ in "preview" }, markExpired: {}),
            transport: StubTransport(latency: latency, route: route)
        )
    }
}

private struct StubTransport: HTTPTransport {
    let latency: Duration
    let route: @Sendable (String, String, URLRequest) -> (Data, Int)

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        try? await Task.sleep(for: latency)
        return route(request.httpMethod ?? "GET", request.url?.path ?? "", request)
    }
}
#endif
