#if DEBUG
import Foundation
import ShinyTrackerAPI

/// Renders the Hunt screen against canned responses — see ``PreviewHarness`` for why and how.
///
/// Launch with `-huntPreview empty | hunts | error | custom`.
enum HuntPreview {
    enum Fixture: String {
        case empty, hunts, error
        /// Only the null-game / null-method hunt, so that path is checkable on its own.
        case custom
    }

    /// Where to send the screen once it has loaded, so the tabs and sheets can be screenshotted
    /// without a human tapping through to them. `-huntPreviewOpen games`, etc.
    enum Route: String {
        case history, games
        /// The four steps of the new-hunt sheet.
        case species, game, method, ready
        /// The ✦ confirm on the first hunt.
        case found
    }

    static var requested: Fixture? { PreviewHarness.argument("-huntPreview").flatMap(Fixture.init) }

    static var route: Route? { PreviewHarness.argument("-huntPreviewOpen").flatMap(Route.init) }

    /// Routes by path, not by fixture: only `GET /api/hunts` differs between the fixtures, and
    /// the new-hunt sheet needs the reference endpoints to answer in every one of them.
    static func client(_ fixture: Fixture) -> APIClient {
        PreviewHarness.client(latency: .milliseconds(250)) { method, path, _ in
            // Writes: every one of them answers success, so the optimistic paths are exercised
            // without a rollback. Point the app at a real API to see the failure states.
            if method == "PATCH" { return (Data(patchResponse.utf8), 200) }
            if method == "POST", path.hasSuffix("/api/hunts") {
                return (Data(patchResponse.utf8), 200)
            }
            if method == "POST" || method == "DELETE" {
                return (Data(#"{"message":"success"}"#.utf8), 200)
            }

            if path == "/api/me/games" { return (Data(userGames.utf8), 200) }
            if path == "/api/me" { return (Data(profile.utf8), 200) }
            if path == "/api/games" { return (Data(games.utf8), 200) }
            if path == "/api/pokemon" { return (Data(species.utf8), 200) }
            // The same five methods for whichever species was asked about — enough to drive the
            // game and method steps, and not a claim about what can be caught where.
            if path == "/api/hunt-methods" { return (Data(huntMethods.utf8), 200) }

            switch fixture {
            case .empty: return (Data("[]".utf8), 200)
            case .hunts: return (Data(huntList.utf8), 200)
            case .custom: return (Data("[\(customHunt)]".utf8), 200)
            case .error: return (Data("hunts: connection refused".utf8), 503)
            }
        }
    }
}

/// Three active hunts: the two from the prototype's seeded state, plus one with a null game and
/// null method — the case the odds engine cannot answer, which has to render without inventing a
/// denominator. Then one completed hunt, which is the whole History tab.
private let huntList = """
[
  {
    "id": "11111111-1111-1111-1111-111111111111",
    "user_id": "00000000-0000-0000-0000-0000000000aa",
    "pokemon_id": 443, "game_id": 5, "hunt_method_id": 1,
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
    "base_odds": 4096, "has_shiny_charm": true, "formula_type": "static",
    "phases": []
  },
  \(customHunt),
  \(completedHunt)
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

private let completedHunt = """
{
    "id": "44444444-4444-4444-4444-444444444444",
    "user_id": "00000000-0000-0000-0000-0000000000aa",
    "pokemon_id": 129, "game_id": 17, "hunt_method_id": 5,
    "encounter_count": 1204, "phase_count": 0,
    "status": "completed", "acquisition_type": "HUNTED",
    "hunt_parameters": null,
    "created_at": "2026-06-02T09:00:00Z", "updated_at": "2026-08-06T11:30:00Z",
    "pokemon_name": "magikarp", "method_name": "Outbreak — mass defeat",
    "custom_method_name": null, "game_title": "Scarlet / Violet",
    "total_time_seconds": 9180,
    "base_rolls": 1, "charm_rolls": 2, "avg_time_seconds": 5,
    "base_odds": 4096, "has_shiny_charm": false, "formula_type": "outbreak_defeats_sv",
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

private let profile = """
{"id": "00000000-0000-0000-0000-0000000000aa", "username": "preview", "is_admin": false}
"""

/// Game ids and base odds follow `backend/internal/calc/charm.go` — ids 8 and up have the charm.
private let games = """
[
  {"id": 1, "title": "Red / Blue / Yellow", "generation": 1, "base_odds": 8192},
  {"id": 5, "title": "Diamond / Pearl / Platinum", "generation": 4, "base_odds": 8192},
  {"id": 8, "title": "Black 2 / White 2", "generation": 5, "base_odds": 8192},
  {"id": 14, "title": "Sword / Shield", "generation": 8, "base_odds": 4096},
  {"id": 15, "title": "Brilliant Diamond / Shining Pearl", "generation": 8, "base_odds": 4096},
  {"id": 17, "title": "Scarlet / Violet", "generation": 9, "base_odds": 4096}
]
"""

/// Owned: Platinum (no charm exists), BDSP (charm on), Scarlet/Violet (charm off). The other
/// three games are absent, which is what an un-owned row looks like on the Games tab.
private let userGames = """
[
  {"user_id": "00000000-0000-0000-0000-0000000000aa", "game_id": 5, "has_shiny_charm": false},
  {"user_id": "00000000-0000-0000-0000-0000000000aa", "game_id": 15, "has_shiny_charm": true},
  {"user_id": "00000000-0000-0000-0000-0000000000aa", "game_id": 17, "has_shiny_charm": false}
]
"""

private let species = """
[
  {"id": 443, "name": "gible", "sprite_url": "", "types": ["dragon", "ground"],
   "is_legendary": false, "is_mythical": false},
  {"id": 447, "name": "riolu", "sprite_url": "", "types": ["fighting"],
   "is_legendary": false, "is_mythical": false},
  {"id": 133, "name": "eevee", "sprite_url": "", "types": ["normal"],
   "is_legendary": false, "is_mythical": false},
  {"id": 129, "name": "magikarp", "sprite_url": "", "types": ["water"],
   "is_legendary": false, "is_mythical": false},
  {"id": 349, "name": "feebas", "sprite_url": "", "types": ["water"],
   "is_legendary": false, "is_mythical": false}
]
"""

/// Chosen to exercise all three Shiny Charm outcomes on the Ready step: Platinum has no charm at
/// all, BDSP's Masuda applies it, and BDSP's Poké Radar is one of the formulas that ignores it.
private let huntMethods = """
[
  {"id": 1, "pokemon_id": 443, "game_id": 5, "game_title": "Diamond / Pearl / Platinum",
   "method_name": "Full odds — wild", "avg_time_seconds": 7,
   "base_rolls": 1, "charm_rolls": 0, "formula_type": "static"},
  {"id": 3, "pokemon_id": 443, "game_id": 5, "game_title": "Diamond / Pearl / Platinum",
   "method_name": "Poké Radar chain", "avg_time_seconds": 12,
   "base_rolls": 1, "charm_rolls": 0, "formula_type": "radar_chain_gen4"},
  {"id": 2, "pokemon_id": 443, "game_id": 15, "game_title": "Brilliant Diamond / Shining Pearl",
   "method_name": "Masuda breeding", "avg_time_seconds": 26,
   "base_rolls": 6, "charm_rolls": 3, "formula_type": "static"},
  {"id": 4, "pokemon_id": 443, "game_id": 15, "game_title": "Brilliant Diamond / Shining Pearl",
   "method_name": "Poké Radar chain", "avg_time_seconds": 12,
   "base_rolls": 1, "charm_rolls": 3, "formula_type": "radar_chain_bdsp"},
  {"id": 5, "pokemon_id": 443, "game_id": 17, "game_title": "Scarlet / Violet",
   "method_name": "Outbreak — mass defeat", "avg_time_seconds": 5,
   "base_rolls": 1, "charm_rolls": 2, "formula_type": "outbreak_defeats_sv"}
]
"""
#endif
