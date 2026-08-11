#if DEBUG
import Foundation
import ShinyTrackerAPI

/// Renders the Hunt screen against canned responses, with no session and no server.
///
/// This exists because the screen is otherwise unverifiable: signing in needs a real Supabase
/// session, so a simulator run shows the login screen and nothing about the design gets checked.
/// It rides the `HTTPTransport` seam ``APIClient`` already has for its own tests — no production
/// code changes shape to accommodate it, and the whole file is out of release builds.
///
/// Launch with `-huntPreview empty | hunts | error` (Xcode scheme argument, `simctl launch`, or
/// a `#Preview`).
enum HuntPreview {
    enum Fixture: String {
        case empty, hunts, error
        /// Only the null-game / null-method hunt, so that path is checkable on its own.
        case custom
    }

    static var requested: Fixture? {
        guard
            let index = ProcessInfo.processInfo.arguments.firstIndex(of: "-huntPreview"),
            let raw = ProcessInfo.processInfo.arguments[safe: index + 1]
        else { return nil }
        return Fixture(rawValue: raw)
    }

    static func client(_ fixture: Fixture) -> APIClient {
        APIClient(
            config: APIConfig(baseURL: URL(string: "https://preview.invalid")!),
            auth: AuthProvider(accessToken: { _ in "preview" }, markExpired: {}),
            transport: StubTransport(fixture: fixture)
        )
    }
}

private struct StubTransport: HTTPTransport {
    let fixture: HuntPreview.Fixture

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        // A beat of latency so the loading state is real rather than skipped.
        try? await Task.sleep(for: .milliseconds(250))

        if request.httpMethod == "PATCH" {
            // UpdateHuntHandler returns a UserHunt; nothing on this screen reads it.
            return (Data(patchResponse.utf8), 200)
        }
        switch fixture {
        case .empty: return (Data("[]".utf8), 200)
        case .hunts: return (Data(huntList.utf8), 200)
        case .custom: return (Data("[\(customHunt)]".utf8), 200)
        case .error: return (Data("hunts: connection refused".utf8), 503)
        }
    }
}

/// Three hunts: the two from the prototype's seeded state, plus one with a null game and null
/// method — the case the odds engine cannot answer, which has to render without inventing a
/// denominator.
private let huntList = """
[
  {
    "id": "11111111-1111-1111-1111-111111111111",
    "user_id": "00000000-0000-0000-0000-0000000000aa",
    "pokemon_id": 443, "game_id": 4, "hunt_method_id": 1,
    "encounter_count": 2847, "phase_count": 0,
    "status": "active", "acquisition_type": "HUNTED",
    "hunt_parameters": null,
    "created_at": "2026-08-01T09:00:00Z", "updated_at": "2026-08-11T18:12:00Z",
    "pokemon_name": "gible", "method_name": "Full odds — wild",
    "custom_method_name": null, "game_title": "Platinum",
    "total_time_seconds": 22320,
    "base_rolls": 1, "charm_rolls": 0, "avg_time_seconds": 7,
    "base_odds": 8192, "has_shiny_charm": false, "formula_type": "static",
    "phases": []
  },
  {
    "id": "22222222-2222-2222-2222-222222222222",
    "user_id": "00000000-0000-0000-0000-0000000000aa",
    "pokemon_id": 447, "game_id": 15, "hunt_method_id": 2,
    "encounter_count": 218, "phase_count": 0,
    "status": "active", "acquisition_type": "HUNTED",
    "hunt_parameters": null,
    "created_at": "2026-07-20T09:00:00Z", "updated_at": "2026-08-10T18:12:00Z",
    "pokemon_name": "riolu", "method_name": "Masuda breeding",
    "custom_method_name": null, "game_title": "BDSP",
    "total_time_seconds": 2460,
    "base_rolls": 6, "charm_rolls": 3, "avg_time_seconds": 26,
    "base_odds": 4096, "has_shiny_charm": false, "formula_type": "static",
    "phases": []
  },
  \(customHunt)
]
"""

/// A hunt with no game and no curated method: `base_odds` is null, so there is no denominator,
/// no progress bar and no cumulative probability to show.
private let customHunt = """
{
    "id": "33333333-3333-3333-3333-333333333333",
    "user_id": "00000000-0000-0000-0000-0000000000aa",
    "pokemon_id": 133, "game_id": null, "hunt_method_id": null,
    "encounter_count": 42, "phase_count": 0,
    "status": "active", "acquisition_type": "HUNTED",
    "hunt_parameters": null,
    "created_at": "2026-07-01T09:00:00Z", "updated_at": "2026-08-09T18:12:00Z",
    "pokemon_name": "eevee", "method_name": null,
    "custom_method_name": "Soft resets on the 3DS", "game_title": null,
    "total_time_seconds": 40,
    "base_rolls": null, "charm_rolls": null, "avg_time_seconds": null,
    "base_odds": null, "has_shiny_charm": null, "formula_type": null,
    "phases": []
}
"""

private let patchResponse = """
{
  "id": "11111111-1111-1111-1111-111111111111",
  "user_id": "00000000-0000-0000-0000-0000000000aa",
  "pokemon_id": 443, "game_id": null, "hunt_method_id": 1,
  "encounter_count": 2847, "phase_count": 0,
  "status": "active", "acquisition_type": "HUNTED", "hunt_parameters": null,
  "created_at": "2026-08-01T09:00:00Z", "updated_at": "2026-08-11T18:12:00Z"
}
"""

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
