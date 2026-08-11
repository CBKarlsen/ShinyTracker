#if DEBUG
import Foundation
import ShinyTrackerAPI

/// Renders the Dex against canned responses, with no session and no server — the same trick as
/// ``HuntPreview``, riding ``APIClient``'s `HTTPTransport` seam.
///
/// Launch with `-dexPreview seeded | full | error`:
/// - `seeded` — 32 real species across four generations, with hunt-derived shinies, manual
///   registrations, an out-of-library species and a shiny-locked one. This is the fixture the
///   screenshots come from.
/// - `full` — all 1,025 ids, so the grid is exercised at real size. **Only the 32 species above
///   have real names and types**; the rest are filled in as `Species 512` placeholders, because
///   a full name table is server data and does not belong in a debug fixture. Use it to judge
///   scrolling and sprite loading, not the copy.
/// - `error` — the load failure path.
enum DexPreview {
    enum Fixture: String {
        case seeded, full, error
    }

    static var requested: Fixture? {
        argument(after: "-dexPreview").flatMap(Fixture.init(rawValue:))
    }

    /// `-dexView living|shiny` — which segment to start on, so each state is screenshottable
    /// without a way to tap in `simctl`.
    static var initialView: DexModel.DexView? {
        guard let raw = argument(after: "-dexView")?.lowercased() else { return nil }
        return DexModel.DexView.allCases.first { $0.rawValue.lowercased() == raw }
    }

    /// `-dexSpecies 443` — open that species' sheet as soon as the grid has loaded.
    static var openSpeciesID: Int? {
        argument(after: "-dexSpecies").flatMap(Int.init)
    }

    /// `-dexGame 4` — start with a game picked, which is what scopes locations and movesets.
    static var initialGameID: Int? {
        argument(after: "-dexGame").flatMap(Int.init)
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
            transport: DexStubTransport(fixture: fixture)
        )
    }
}

/// id, name, types — enough to draw a tile and compute a matchup.
private let seededSpecies: [(id: Int, name: String, types: [String])] = [
    (1, "bulbasaur", ["grass", "poison"]),
    (4, "charmander", ["fire"]),
    (7, "squirtle", ["water"]),
    (25, "pikachu", ["electric"]),
    (59, "arcanine", ["fire"]),
    (94, "gengar", ["ghost", "poison"]),
    (130, "gyarados", ["water", "flying"]),
    (133, "eevee", ["normal"]),
    (143, "snorlax", ["normal"]),
    (149, "dragonite", ["dragon", "flying"]),
    (150, "mewtwo", ["psychic"]),
    (151, "mew", ["psychic"]),
    (197, "umbreon", ["dark"]),
    (212, "scizor", ["bug", "steel"]),
    (227, "skarmory", ["steel", "flying"]),
    (248, "tyranitar", ["rock", "dark"]),
    (282, "gardevoir", ["psychic", "fairy"]),
    (334, "altaria", ["dragon", "flying"]),
    (359, "absol", ["dark"]),
    (376, "metagross", ["steel", "psychic"]),
    (385, "jirachi", ["steel", "psychic"]),
    (387, "turtwig", ["grass"]),
    (390, "chimchar", ["fire"]),
    (393, "piplup", ["water"]),
    (405, "luxray", ["electric"]),
    (443, "gible", ["dragon", "ground"]),
    (444, "gabite", ["dragon", "ground"]),
    (445, "garchomp", ["dragon", "ground"]),
    (447, "riolu", ["fighting"]),
    (448, "lucario", ["fighting", "steel"]),
    (906, "sprigatito", ["grass"]),
    (999, "gimmighoul", ["ghost"]),
]

private struct DexStubTransport: HTTPTransport {
    let fixture: DexPreview.Fixture

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        // A beat of latency so the loading state is real rather than skipped.
        try? await Task.sleep(for: .milliseconds(200))

        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"

        if fixture == .error, method == "GET" {
            return (Data("pokemon: connection refused".utf8), 503)
        }

        switch (method, path) {
        case ("POST", "/api/hunts/manual"):
            return (Data(manualHunt.utf8), 200)
        case ("DELETE", _):
            return (Data(#"{"message":"Catch removed successfully"}"#.utf8), 200)
        case (_, "/api/games"):
            return (Data(games.utf8), 200)
        case (_, "/api/hunts"):
            return (Data(hunts.utf8), 200)
        case (_, "/api/dex/status"):
            return (Data(dexStatus.utf8), 200)
        case (_, "/api/pokemon"):
            return (Data(speciesList(fixture).utf8), 200)
        default:
            // /api/pokemon/{id}
            let id = Int(path.split(separator: "/").last ?? "") ?? 443
            let asked = request.url?.query?.contains("game_id") ?? false
            return (Data(detail(id: id, withMoves: asked).utf8), 200)
        }
    }
}

private func speciesList(_ fixture: DexPreview.Fixture) -> String {
    let known = Dictionary(uniqueKeysWithValues: seededSpecies.map { ($0.id, $0) })
    let ids = fixture == .full ? Array(1...1025) : seededSpecies.map(\.id)
    let rows = ids.map { id -> String in
        let species = known[id]
        let name = species?.name ?? "species \(id)"
        let types = (species?.types ?? []).map { "\"\($0)\"" }.joined(separator: ",")
        return """
            {"id":\(id),"name":"\(name)","sprite_url":"","types":[\(types)],
             "is_legendary":false,"is_mythical":false}
            """
    }
    return "[\(rows.joined(separator: ","))]"
}

/// Two finished hunts (Gible, Lucario — un-untickable), one still active, and one manual
/// registration (Eevee — tickable both ways).
private let hunts = """
[
  {"id":"11111111-1111-1111-1111-111111111111",
   "user_id":"00000000-0000-0000-0000-0000000000aa",
   "pokemon_id":443,"game_id":4,"hunt_method_id":1,
   "encounter_count":2847,"phase_count":0,"status":"completed","acquisition_type":"HUNTED",
   "hunt_parameters":null,
   "created_at":"2026-06-01T09:00:00Z","updated_at":"2026-08-01T18:12:00Z",
   "pokemon_name":"gible","method_name":"Full odds — wild","custom_method_name":null,
   "game_title":"Platinum","total_time_seconds":22320,
   "base_rolls":1,"charm_rolls":0,"avg_time_seconds":7,"base_odds":8192,
   "has_shiny_charm":false,"formula_type":"static","phases":[]},
  {"id":"22222222-2222-2222-2222-222222222222",
   "user_id":"00000000-0000-0000-0000-0000000000aa",
   "pokemon_id":448,"game_id":4,"hunt_method_id":1,
   "encounter_count":1455,"phase_count":0,"status":"completed","acquisition_type":"HUNTED",
   "hunt_parameters":null,
   "created_at":"2026-05-01T09:00:00Z","updated_at":"2026-07-01T18:12:00Z",
   "pokemon_name":"lucario","method_name":"Full odds — wild","custom_method_name":null,
   "game_title":"Platinum","total_time_seconds":18000,
   "base_rolls":1,"charm_rolls":0,"avg_time_seconds":7,"base_odds":8192,
   "has_shiny_charm":false,"formula_type":"static","phases":[]},
  {"id":"33333333-3333-3333-3333-333333333333",
   "user_id":"00000000-0000-0000-0000-0000000000aa",
   "pokemon_id":133,"game_id":null,"hunt_method_id":null,
   "encounter_count":1,"phase_count":0,"status":"completed","acquisition_type":"MANUAL_OVERRIDE",
   "hunt_parameters":{"manual":true},
   "created_at":"2026-04-01T09:00:00Z","updated_at":"2026-04-01T09:00:00Z",
   "pokemon_name":"eevee","method_name":null,"custom_method_name":null,"game_title":null,
   "total_time_seconds":0,
   "base_rolls":null,"charm_rolls":null,"avg_time_seconds":null,"base_odds":null,
   "has_shiny_charm":null,"formula_type":null,"phases":[]},
  {"id":"44444444-4444-4444-4444-444444444444",
   "user_id":"00000000-0000-0000-0000-0000000000aa",
   "pokemon_id":447,"game_id":4,"hunt_method_id":2,
   "encounter_count":218,"phase_count":0,"status":"active","acquisition_type":"HUNTED",
   "hunt_parameters":null,
   "created_at":"2026-07-20T09:00:00Z","updated_at":"2026-08-10T18:12:00Z",
   "pokemon_name":"riolu","method_name":"Masuda breeding","custom_method_name":null,
   "game_title":"Platinum","total_time_seconds":2460,
   "base_rolls":6,"charm_rolls":3,"avg_time_seconds":26,"base_odds":4096,
   "has_shiny_charm":false,"formula_type":"static","phases":[]}
]
"""

/// Mew is in no game the user owns; Jirachi is shiny locked wherever it appears.
private let dexStatus = """
{"not_in_your_games":[151, 999],"locked_everywhere":[385]}
"""

private let games = """
[
  {"id":4,"title":"Platinum","generation":4,"base_odds":8192},
  {"id":15,"title":"Brilliant Diamond","generation":8,"base_odds":4096},
  {"id":31,"title":"Scarlet","generation":9,"base_odds":4096}
]
"""

private let manualHunt = """
{"id":"55555555-5555-5555-5555-555555555555",
 "user_id":"00000000-0000-0000-0000-0000000000aa",
 "pokemon_id":0,"game_id":null,"hunt_method_id":null,
 "encounter_count":1,"phase_count":0,"status":"completed","acquisition_type":"MANUAL_OVERRIDE",
 "hunt_parameters":{"manual":true},
 "created_at":"2026-08-11T09:00:00Z","updated_at":"2026-08-11T09:00:00Z"}
"""

/// Gible in Platinum, with everything the sheet renders. Any other id gets the same shape with
/// its own number so the evolution row can be walked.
private func detail(id: Int, withMoves: Bool) -> String {
    let known = Dictionary(uniqueKeysWithValues: seededSpecies.map { ($0.id, $0) })
    let species = known[id]
    let name = species?.name ?? "species \(id)"
    let types = (species?.types ?? []).map { "\"\($0)\"" }.joined(separator: ",")
    let evolvesFrom = id == 444 || id == 445 ? #"[{"pokemon_id":443,"name":"gible"}]"# : "[]"
    let evolvesTo =
        id == 443
        ? #"[{"pokemon_id":444,"name":"gabite"}]"#
        : id == 444 ? #"[{"pokemon_id":445,"name":"garchomp"}]"# : "[]"
    let moves = withMoves ? movesJSON : "null"
    return """
        {"id":\(id),"name":"\(name)","sprite_url":"","types":[\(types)],
         "can_breed":true,"is_legendary":false,"is_mythical":false,
         "evolves_from_id":null,"evolves_from":\(evolvesFrom),"evolves_to":\(evolvesTo),
         "locations":[
           {"game_id":4,"area":"wayward-cave","version":"platinum","terrain":"cave",
            "min_level":15,"max_level":18,"chance":4,"conditions":[]},
           {"game_id":4,"area":"mount-coronet-b1f","version":"platinum","terrain":"cave",
            "min_level":18,"max_level":20,"chance":2,"conditions":["time-night"]}
         ],
         "stats":{"hp":58,"attack":70,"defense":45,"special_attack":40,
                  "special_defense":45,"speed":42},
         "abilities":[
           {"slug":"sand-veil","name":"Sand Veil","effect":"","slot":1,"is_hidden":false},
           {"slug":"rough-skin","name":"Rough Skin","effect":"","slot":3,"is_hidden":true}
         ],
         "moves":\(moves)}
        """
}

private let movesJSON = """
[
 {"slug":"tackle","name":"Tackle","type":"normal","damage_class":"physical",
  "power":40,"accuracy":100,"pp":35,"effect":"","method":"level-up","level":1},
 {"slug":"sand-attack","name":"Sand Attack","type":"ground","damage_class":"status",
  "power":null,"accuracy":100,"pp":15,"effect":"","method":"level-up","level":3},
 {"slug":"dragon-rage","name":"Dragon Rage","type":"dragon","damage_class":"special",
  "power":null,"accuracy":100,"pp":10,"effect":"","method":"level-up","level":7},
 {"slug":"sandstorm","name":"Sandstorm","type":"rock","damage_class":"status",
  "power":null,"accuracy":null,"pp":10,"effect":"","method":"level-up","level":13},
 {"slug":"dig","name":"Dig","type":"ground","damage_class":"physical",
  "power":80,"accuracy":100,"pp":10,"effect":"","method":"level-up","level":19},
 {"slug":"dragon-claw","name":"Dragon Claw","type":"dragon","damage_class":"physical",
  "power":80,"accuracy":100,"pp":15,"effect":"","method":"level-up","level":29},
 {"slug":"earthquake","name":"Earthquake","type":"ground","damage_class":"physical",
  "power":100,"accuracy":100,"pp":10,"effect":"","method":"tm","level":null}
]
"""
#endif
