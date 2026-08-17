#if DEBUG
import Foundation
import ShinyTrackerAPI

/// Renders the Teams mode against canned responses, with no session and no server — the same
/// trick as ``HuntPreview``, ``DexPreview`` and ``NuzlockePreview``, riding ``APIClient``'s
/// `HTTPTransport` seam.
///
/// Launch with `-teamsPreview seeded | empty | error`:
/// - `seeded` — one full six-slot Champions team, the fixture the screenshots come from.
/// - `empty` — no teams at all, i.e. the "Build a team" state.
/// - `error` — the load failure path.
///
/// The reference data is generated rather than transcribed: the six species carry their real
/// base stats, their real abilities and the four moves their set uses, plus six filler moves so
/// the move picker is a list rather than four rows. The move *types* are a stand-in — nothing on
/// these screens reads them except the picker's tint.
enum TeamsPreview {
    enum Fixture: String {
        case seeded, empty, error
    }

    static var requested: Fixture? {
        PreviewHarness.argument("-teamsPreview").flatMap(Fixture.init(rawValue:))
    }

    static func client(_ fixture: Fixture) -> APIClient {
        PreviewHarness.client { method, path, _ in
            if fixture == .error, method == "GET", path == "/api/me/teams" {
                return (Data("teams: connection refused".utf8), 503)
            }

            switch (method, path) {
            case (_, "/api/items"):
                return (Data(itemsJSON.utf8), 200)
            case (_, "/api/pokemon"):
                return (Data(speciesJSON.utf8), 200)
            case ("GET", "/api/me/teams"):
                return (Data((fixture == .empty ? "[]" : "[\(team)]").utf8), 200)
            case (_, let detailPath) where detailPath.hasPrefix("/api/pokemon/"):
                let id = Int(detailPath.dropFirst("/api/pokemon/".count)) ?? roster[0].id
                return (Data(detailJSON(id).utf8), 200)
            default:
                // Every write answers with the team it wrote, which is the shape both the
                // create and the update paths re-read.
                return (Data(team.utf8), 200)
            }
        }
    }
}

// MARK: - The roster

/// One species, everything the three endpoints need to say about it.
private struct Entry {
    let id: Int
    let name: String
    let types: [String]
    /// hp, atk, def, spa, spd, spe — real base stats.
    let base: [Int]
    /// `(slug, name, hidden)`.
    let abilities: [(String, String, Bool)]
    /// The set this fixture builds, in slot order.
    let nature: String
    let ability: String
    let item: String
    /// Champions' unified allocation — 65 of the 66 points, the total a fully-trained
    /// mainline transfer arrives with.
    let points: [String: Int]
    /// `(slug, name)` — four moves, which are also the four this species' picker offers first.
    let moves: [(String, String)]
}

private let roster: [Entry] = [
    Entry(
        id: 984, name: "great-tusk", types: ["ground", "fighting"], base: [115, 131, 131, 53, 53, 87],
        abilities: [("protosynthesis", "Protosynthesis", false)],
        nature: "jolly", ability: "protosynthesis", item: "booster-energy",
        points: ["hp": 1, "atk": 32, "def": 0, "spa": 0, "spd": 0, "spe": 32],
        moves: [
            ("headlong-rush", "Headlong Rush"), ("close-combat", "Close Combat"),
            ("ice-spinner", "Ice Spinner"), ("rapid-spin", "Rapid Spin"),
        ]),
    Entry(
        id: 1000, name: "gholdengo", types: ["steel", "ghost"], base: [87, 60, 95, 133, 91, 84],
        abilities: [("good-as-gold", "Good as Gold", false)],
        nature: "timid", ability: "good-as-gold", item: "leftovers",
        points: ["hp": 32, "atk": 0, "def": 0, "spa": 1, "spd": 0, "spe": 32],
        moves: [
            ("make-it-rain", "Make It Rain"), ("shadow-ball", "Shadow Ball"),
            ("nasty-plot", "Nasty Plot"), ("thunder-wave", "Thunder Wave"),
        ]),
    Entry(
        id: 983, name: "kingambit", types: ["dark", "steel"], base: [100, 135, 120, 60, 85, 50],
        abilities: [("defiant", "Defiant", false), ("supreme-overlord", "Supreme Overlord", true)],
        nature: "adamant", ability: "supreme-overlord", item: "black-glasses",
        points: ["hp": 32, "atk": 32, "def": 1, "spa": 0, "spd": 0, "spe": 0],
        moves: [
            ("kowtow-cleave", "Kowtow Cleave"), ("sucker-punch", "Sucker Punch"),
            ("iron-head", "Iron Head"), ("swords-dance", "Swords Dance"),
        ]),
    Entry(
        id: 887, name: "dragapult", types: ["dragon", "ghost"], base: [88, 120, 75, 100, 75, 142],
        abilities: [("clear-body", "Clear Body", false), ("infiltrator", "Infiltrator", false)],
        nature: "timid", ability: "infiltrator", item: "choice-specs",
        points: ["hp": 0, "atk": 0, "def": 0, "spa": 32, "spd": 1, "spe": 32],
        moves: [
            ("shadow-ball", "Shadow Ball"), ("draco-meteor", "Draco Meteor"),
            ("u-turn", "U-turn"), ("flamethrower", "Flamethrower"),
        ]),
    Entry(
        id: 1006, name: "iron-valiant", types: ["fairy", "fighting"], base: [74, 130, 90, 120, 60, 116],
        abilities: [("quark-drive", "Quark Drive", false)],
        // Not a second Booster Energy: Champions forbids two slots holding the same item, and a
        // fixture the screenshots come from has to be a team the editor would let you save.
        nature: "naive", ability: "quark-drive", item: "life-orb",
        points: ["hp": 0, "atk": 16, "def": 0, "spa": 17, "spd": 0, "spe": 32],
        moves: [
            ("moonblast", "Moonblast"), ("close-combat", "Close Combat"),
            ("knock-off", "Knock Off"), ("encore", "Encore"),
        ]),
    Entry(
        id: 591, name: "amoonguss", types: ["grass", "poison"], base: [114, 85, 70, 85, 80, 30],
        abilities: [("effect-spore", "Effect Spore", false), ("regenerator", "Regenerator", true)],
        nature: "bold", ability: "regenerator", item: "black-sludge",
        points: ["hp": 32, "atk": 0, "def": 32, "spa": 0, "spd": 1, "spe": 0],
        moves: [
            ("spore", "Spore"), ("sludge-bomb", "Sludge Bomb"),
            ("giga-drain", "Giga Drain"), ("clear-smog", "Clear Smog"),
        ]),
]

/// Offered by every species, so the move picker is not four rows long.
private let filler: [(String, String)] = [
    ("protect", "Protect"), ("substitute", "Substitute"), ("rest", "Rest"),
    ("sleep-talk", "Sleep Talk"), ("toxic", "Toxic"), ("facade", "Facade"),
]

// MARK: - Responses

private let team: String = {
    let members = roster.enumerated().map { index, entry in
        """
        {"slot":\(index + 1),"pokemon_id":\(entry.id),"nickname":null,
         "nature":"\(entry.nature)","ability_slug":"\(entry.ability)",
         "item_slug":"\(entry.item)","level":50,
         "stat_points":\(json(entry.points)),
         "moves":[\(entry.moves.map { "\"\($0.0)\"" }.joined(separator: ","))]}
        """
    }
    return """
        {"id":"cccccccc-0000-4000-8000-00000000cccc","name":"Regulation H",
         "game_id":18,"members":[\(members.joined(separator: ","))]}
        """
}()

private let speciesJSON: String = {
    let rows = roster.map {
        """
        {"id":\($0.id),"name":"\($0.name)","sprite_url":"",
         "types":[\($0.types.map { "\"\($0)\"" }.joined(separator: ","))],
         "is_legendary":false,"is_mythical":false}
        """
    }
    return "[\(rows.joined(separator: ","))]"
}()

private let itemsJSON: String = {
    let held = [
        ("booster-energy", "Booster Energy", "Activates Protosynthesis or Quark Drive once."),
        ("leftovers", "Leftovers", "Restores a little HP every turn."),
        ("black-glasses", "Black Glasses", "Boosts Dark-type moves."),
        ("choice-specs", "Choice Specs", "Boosts Sp. Atk, but locks the holder into one move."),
        ("black-sludge", "Black Sludge", "Restores HP to Poison types, hurts everything else."),
        ("choice-band", "Choice Band", "Boosts Attack, but locks the holder into one move."),
        ("choice-scarf", "Choice Scarf", "Boosts Speed, but locks the holder into one move."),
        ("life-orb", "Life Orb", "Boosts damage at the cost of a little HP each hit."),
        ("rocky-helmet", "Rocky Helmet", "Hurts attackers that make contact."),
        ("focus-sash", "Focus Sash", "Survives one otherwise fatal hit at full HP."),
        ("heavy-duty-boots", "Heavy-Duty Boots", "Ignores entry hazards."),
        ("assault-vest", "Assault Vest", "Boosts Sp. Def, but bars status moves."),
    ]
    let rows = held.map {
        #"{"slug":"\#($0.0)","name":"\#($0.1)","sprite_url":"","description":"\#($0.2)"}"#
    }
    return "[\(rows.joined(separator: ","))]"
}()

private func detailJSON(_ id: Int) -> String {
    let entry = roster.first { $0.id == id } ?? roster[0]
    let abilities = entry.abilities.enumerated().map { index, ability in
        """
        {"slug":"\(ability.0)","name":"\(ability.1)","effect":"",
         "slot":\(index + 1),"is_hidden":\(ability.2)}
        """
    }
    let moves = (entry.moves + filler).map {
        """
        {"slug":"\($0.0)","name":"\($0.1)","type":"\(entry.types[0])",
         "damage_class":"physical","power":80,"accuracy":100,"pp":10,
         "effect":"","method":"level-up","level":1}
        """
    }
    return """
        {"id":\(entry.id),"name":"\(entry.name)","sprite_url":"",
         "types":[\(entry.types.map { "\"\($0)\"" }.joined(separator: ","))],
         "can_breed":true,"is_legendary":false,"is_mythical":false,
         "evolves_from_id":null,"evolves_from":[],"evolves_to":[],"locations":[],
         "stats":{"hp":\(entry.base[0]),"attack":\(entry.base[1]),"defense":\(entry.base[2]),
                  "special_attack":\(entry.base[3]),"special_defense":\(entry.base[4]),
                  "speed":\(entry.base[5])},
         "abilities":[\(abilities.joined(separator: ","))],
         "moves":[\(moves.joined(separator: ","))]}
        """
}

/// `Stat.rawValue` order, so the fixture reads the way every stat block in the app prints.
private func json(_ spread: [String: Int]) -> String {
    let parts = ["hp", "atk", "def", "spa", "spd", "spe"].map { "\"\($0)\":\(spread[$0] ?? 0)" }
    return "{\(parts.joined(separator: ","))}"
}
#endif
