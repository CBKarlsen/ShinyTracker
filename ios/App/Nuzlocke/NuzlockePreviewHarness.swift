#if DEBUG
import Foundation
import ShinyTrackerAPI

/// Renders the Nuzlocke mode against canned responses, with no session and no server — the same
/// trick as ``HuntPreview`` and ``DexPreview``, riding ``APIClient``'s `HTTPTransport` seam.
///
/// Launch with `-nuzlockePreview seeded | empty | error`:
/// - `seeded` — a Platinum run six routes in: one in the party, one boxed, one dead, one route
///   missed, Barry beaten and Roark next. The fixture the screenshots come from.
/// - `empty` — no runs at all, i.e. the "Start a run" state.
/// - `error` — the load failure path.
///
/// The timeline is the first stretch of `backend/seeds/nuzlocke_platinum.json`, not invented
/// data, so the screen is judged against the shape it will really receive.
enum NuzlockePreview {
    enum Fixture: String {
        case seeded, empty, error
    }

    static var requested: Fixture? {
        argument(after: "-nuzlockePreview").flatMap(Fixture.init(rawValue:))
    }

    private static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }

    static func client(_ fixture: Fixture) -> APIClient {
        APIClient(
            config: APIConfig(baseURL: URL(string: "https://preview.invalid")!),
            auth: AuthProvider(accessToken: { _ in "preview" }, markExpired: {}),
            transport: NuzlockeStubTransport(fixture: fixture)
        )
    }
}

private struct NuzlockeStubTransport: HTTPTransport {
    let fixture: NuzlockePreview.Fixture

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        try? await Task.sleep(for: .milliseconds(200))

        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        if fixture == .error, method == "GET" {
            return (Data("runs: connection refused".utf8), 503)
        }

        switch (method, path) {
        case (_, "/api/games"):
            return (Data(games.utf8), 200)
        case (_, "/api/pokemon"):
            return (Data(species.utf8), 200)
        case (_, "/api/nuzlocke/timeline"):
            return (Data("[\(timelineEntries)]".utf8), 200)
        case ("GET", "/api/runs"):
            return (Data((fixture == .empty ? "[]" : "[\(run)]").utf8), 200)
        case ("POST", "/api/runs"):
            return (Data(run.utf8), 200)
        case ("GET", let runPath) where runPath.hasPrefix("/api/runs/"):
            return (Data(runDetail.utf8), 200)
        default:
            // Every write answers with the row it wrote; the encounter shape is the only one the
            // screen re-reads, and PUT/PATCH both return it.
            return (Data(writtenEncounter.utf8), 200)
        }
    }
}

private let games = """
[
  {"id":4,"title":"Platinum","generation":4,"base_odds":8192},
  {"id":31,"title":"Scarlet","generation":9,"base_odds":4096}
]
"""

/// Real types for every species this fixture logs — what the coverage matchup reads.
///
/// The real endpoint answers with all 1,025; the coverage warning only ever looks up the ids it
/// has logged, so a fixture that carries those is a faithful stand-in and a 1,025-row blob is
/// not worth committing.
private let species = """
[
  {"id":74,"name":"geodude","sprite_url":"","types":["rock","ground"],
   "is_legendary":false,"is_mythical":false},
  {"id":393,"name":"piplup","sprite_url":"","types":["water"],
   "is_legendary":false,"is_mythical":false},
  {"id":396,"name":"starly","sprite_url":"","types":["normal","flying"],
   "is_legendary":false,"is_mythical":false},
  {"id":399,"name":"bidoof","sprite_url":"","types":["normal"],
   "is_legendary":false,"is_mythical":false}
]
"""

/// The first eight stops of the seeded Platinum route, verbatim in shape.
private let timelineEntries = """
{"id":1,"slug":"starter","kind":"location","name":"Lake Verity","sort_order":1,
 "encounters":[{"pokemon_id":387,"pokemon_name":"turtwig","sprite_url":""},
               {"pokemon_id":390,"pokemon_name":"chimchar","sprite_url":""},
               {"pokemon_id":393,"pokemon_name":"piplup","sprite_url":""}]},
{"id":2,"slug":"r201","kind":"location","name":"Route 201","sort_order":2,
 "encounters":[{"pokemon_id":396,"pokemon_name":"starly","sprite_url":""},
               {"pokemon_id":399,"pokemon_name":"bidoof","sprite_url":""}]},
{"id":3,"slug":"r202","kind":"location","name":"Route 202","sort_order":3,
 "encounters":[{"pokemon_id":403,"pokemon_name":"shinx","sprite_url":""},
               {"pokemon_id":396,"pokemon_name":"starly","sprite_url":""},
               {"pokemon_id":399,"pokemon_name":"bidoof","sprite_url":""},
               {"pokemon_id":401,"pokemon_name":"kricketot","sprite_url":""}]},
{"id":4,"slug":"rival1","kind":"boss","name":"Barry","sort_order":4,
 "boss_title":"Rival","place":"Route 203","level_cap":9,
 "squad":[{"pokemon_id":396,"pokemon_name":"starly","sprite_url":"","level":7,
           "ability":"Keen Eye",
           "moves":[{"name":"Quick Attack","type":"Normal","power":40},
                    {"name":"Growl","type":"Normal","power":0},
                    {"name":"Wing Attack","type":"Flying","power":60}]},
          {"pokemon_id":390,"pokemon_name":"chimchar","sprite_url":"","level":9,
           "ability":"Blaze",
           "moves":[{"name":"Scratch","type":"Normal","power":40},
                    {"name":"Ember","type":"Fire","power":40}]}]},
{"id":5,"slug":"r203","kind":"location","name":"Route 203","sort_order":5,
 "encounters":[{"pokemon_id":396,"pokemon_name":"starly","sprite_url":""},
               {"pokemon_id":403,"pokemon_name":"shinx","sprite_url":""},
               {"pokemon_id":399,"pokemon_name":"bidoof","sprite_url":""},
               {"pokemon_id":401,"pokemon_name":"kricketot","sprite_url":""},
               {"pokemon_id":63,"pokemon_name":"abra","sprite_url":""}]},
{"id":6,"slug":"gate","kind":"location","name":"Oreburgh Gate","sort_order":6,
 "encounters":[{"pokemon_id":41,"pokemon_name":"zubat","sprite_url":""},
               {"pokemon_id":74,"pokemon_name":"geodude","sprite_url":""},
               {"pokemon_id":95,"pokemon_name":"onix","sprite_url":""}]},
{"id":7,"slug":"mine","kind":"location","name":"Oreburgh Mine","sort_order":7,
 "encounters":[{"pokemon_id":74,"pokemon_name":"geodude","sprite_url":""},
               {"pokemon_id":95,"pokemon_name":"onix","sprite_url":""},
               {"pokemon_id":41,"pokemon_name":"zubat","sprite_url":""}]},
{"id":8,"slug":"gym1","kind":"boss","name":"Roark","sort_order":8,
 "boss_title":"Gym Leader · Rock","place":"Oreburgh Gym","level_cap":14,
 "squad":[{"pokemon_id":74,"pokemon_name":"geodude","sprite_url":"","level":12,
           "ability":"Sturdy",
           "moves":[{"name":"Stealth Rock","type":"Rock","power":0},
                    {"name":"Rock Throw","type":"Rock","power":50}]},
          {"pokemon_id":95,"pokemon_name":"onix","sprite_url":"","level":12,
           "ability":"Rock Head",
           "moves":[{"name":"Rock Throw","type":"Rock","power":50},
                    {"name":"Screech","type":"Normal","power":0}]},
          {"pokemon_id":408,"pokemon_name":"cranidos","sprite_url":"","level":14,
           "ability":"Mold Breaker",
           "moves":[{"name":"Headbutt","type":"Normal","power":70},
                    {"name":"Leer","type":"Normal","power":0},
                    {"name":"Focus Energy","type":"Normal","power":0},
                    {"name":"Pursuit","type":"Dark","power":40}]}]}
"""

private let runFields = """
"id":"aaaaaaaa-0000-4000-8000-00000000aaaa",
"user_id":"00000000-0000-0000-0000-0000000000aa",
"game_id":4,"game_title":"Platinum",
"dupes_clause":true,"battle_style":"set","nicknames_required":true,
"status":"active","started_at":"2026-08-05T09:00:00Z","ended_at":null,
"created_at":"2026-08-05T09:00:00Z","updated_at":"2026-08-11T20:14:00Z"
"""

private let run = "{\(runFields)}"

/// Piplup alive, Starly and Geodude boxed, Bidoof dead, Route 203 run from — and Barry beaten, so
/// Roark is the next checkpoint and the cap reads 14.
///
/// The roster is picked to exercise the coverage warning against Roark's real moveset, whose
/// damaging moves are Rock, Normal and Dark. Piplup (water) resists none of the three, so all
/// three are gaps; boxed Geodude (rock/ground) resists Rock and Normal but not Dark, so two gaps
/// name a bench resister and one has none.
private let runDetail = """
{\(runFields),
 "timeline":[\(timelineEntries)],
 "encounters":[
   {"id":"11111111-0000-4000-8000-00000000e001",
    "run_id":"aaaaaaaa-0000-4000-8000-00000000aaaa","location_slug":"starter",
    "pokemon_id":393,"pokemon_name":"piplup","nickname":"Tuxedo","status":"caught",
    "nature":null,"is_boxed":false,"is_dupe":false,
    "created_at":"2026-08-05T09:10:00Z","updated_at":"2026-08-05T09:10:00Z"},
   {"id":"11111111-0000-4000-8000-00000000e002",
    "run_id":"aaaaaaaa-0000-4000-8000-00000000aaaa","location_slug":"r201",
    "pokemon_id":396,"pokemon_name":"starly","nickname":"Gust","status":"caught",
    "nature":null,"is_boxed":true,"is_dupe":false,
    "created_at":"2026-08-05T09:40:00Z","updated_at":"2026-08-06T10:00:00Z"},
   {"id":"11111111-0000-4000-8000-00000000e003",
    "run_id":"aaaaaaaa-0000-4000-8000-00000000aaaa","location_slug":"r202",
    "pokemon_id":399,"pokemon_name":"bidoof","nickname":"Chomper","status":"fainted",
    "nature":null,"is_boxed":false,"is_dupe":false,
    "created_at":"2026-08-05T10:05:00Z","updated_at":"2026-08-07T18:22:00Z"},
   {"id":"11111111-0000-4000-8000-00000000e004",
    "run_id":"aaaaaaaa-0000-4000-8000-00000000aaaa","location_slug":"r203",
    "pokemon_id":null,"pokemon_name":null,"nickname":null,"status":"ran",
    "nature":null,"is_boxed":false,"is_dupe":false,
    "created_at":"2026-08-06T11:00:00Z","updated_at":"2026-08-06T11:00:00Z"},
   {"id":"11111111-0000-4000-8000-00000000e005",
    "run_id":"aaaaaaaa-0000-4000-8000-00000000aaaa","location_slug":"gate",
    "pokemon_id":74,"pokemon_name":"geodude","nickname":"Pebble","status":"caught",
    "nature":null,"is_boxed":true,"is_dupe":false,
    "created_at":"2026-08-08T14:00:00Z","updated_at":"2026-08-08T14:00:00Z"}
 ],
 "boss_progress":[{"boss_slug":"rival1","beaten":true}]}
"""

/// What a `PUT`/`PATCH` answers with: no `pokemon_name`, because neither response joins it.
private let writtenEncounter = """
{"id":"11111111-0000-4000-8000-00000000e005",
 "run_id":"aaaaaaaa-0000-4000-8000-00000000aaaa","location_slug":"gate",
 "pokemon_id":74,"nickname":"Pebble","status":"caught",
 "nature":null,"is_boxed":false,"is_dupe":false,
 "created_at":"2026-08-11T20:20:00Z","updated_at":"2026-08-11T20:20:00Z"}
"""
#endif
