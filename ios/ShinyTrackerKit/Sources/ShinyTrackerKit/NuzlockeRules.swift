import Foundation

/// Rules governing a Nuzlocke run that are pure functions of its progress.
///
/// These live here rather than on `NuzlockeModel` for the reason ``HuntCountPolicy`` does: the
/// model is in the app target, which has no test target, so every claim about it is derived by
/// reading. The level cap is a number the player obeys — being wrong about it costs a Pokémon.
public enum NuzlockeRules {

    /// One checkpoint's contribution to the cap, in timeline order.
    public struct Checkpoint: Equatable, Sendable {
        public let slug: String
        /// Nullable in the schema, so a seeded boss can genuinely have no cap.
        public let levelCap: Int?

        public init(slug: String, levelCap: Int?) {
            self.slug = slug
            self.levelCap = levelCap
        }
    }

    /// The level cap in force: the highest cap of every checkpoint up to and including the next
    /// unbeaten one.
    ///
    /// **Not** simply the next checkpoint's cap, which is what this used to be. Platinum's seeded
    /// caps are not monotonic — they fall three times, because the boss after a gym is often a
    /// weaker Galactic fight:
    ///
    /// | after | next | naive cap |
    /// |---|---|---|
    /// | Wake, 37 | Cyrus at Celestic, 36 | 36 |
    /// | Byron, 41 | Saturn at Valor, 40 | 40 |
    /// | Cyrus at HQ, 46 | Saturn at HQ, 44 | 44 |
    ///
    /// So beating a gym made the displayed cap *drop*, telling the player to un-level a team they
    /// had already levelled. Every Nuzlocke ruleset treats the cap as a ratchet: it is the highest
    /// level you have been cleared for, and clearing a harder fight never lowers it.
    ///
    /// Returns nil when every checkpoint is beaten — the run has no next checkpoint to cap against
    /// — and when no checkpoint up to that point carries a cap at all.
    public static func levelCap(checkpoints: [Checkpoint], beaten: Set<String>) -> Int? {
        guard let next = checkpoints.firstIndex(where: { !beaten.contains($0.slug) }) else {
            return nil
        }
        return checkpoints[...next].compactMap(\.levelCap).max()
    }

    // MARK: - Chapters

    /// One timeline entry, reduced to what grouping needs.
    public struct Row: Equatable, Sendable {
        public let slug: String
        public let isBoss: Bool
        /// A badge fight, as opposed to a rival or a Galactic commander. Chapters break on these.
        public let isGym: Bool
        /// The seeded place — "Oreburgh Gym", "Pokémon League".
        public let place: String?

        public init(slug: String, isBoss: Bool, isGym: Bool, place: String?) {
            self.slug = slug
            self.isBoss = isBoss
            self.isGym = isGym
            self.place = place
        }
    }

    /// A stretch of the run ending at a gym, plus a final chapter for whatever follows the last
    /// one.
    public struct Chapter: Equatable, Sendable, Identifiable {
        /// The terminal entry's slug — stable across reloads, unlike an index.
        public let id: String
        /// "Oreburgh", "Pokémon League".
        public let title: String
        public let rows: [Row]

        public init(id: String, title: String, rows: [Row]) {
            self.id = id
            self.title = title
            self.rows = rows
        }
    }

    /// Groups a timeline into chapters that break **after each gym**.
    ///
    /// Not after each boss, which is the obvious reading and is wrong. Platinum seeds 28 bosses
    /// against 34 locations, and boss-bounded segments leave **13 of 28 with no routes at all** —
    /// the entire endgame from Volkner on becomes six consecutive one-row groups. Gym-bounded
    /// gives 9 chapters of 5–9 rows, every one with routes to work.
    ///
    /// Rivals and Galactic commanders stay as rows *inside* a chapter, which is what they are:
    /// level-cap bumps and prep checks on the way to a badge, not destinations.
    ///
    /// The Elite Four and the Champion are **one** chapter, never five. Once you are in there is
    /// no PC, no shop and no leaving until the Champion is down, so a player preps for all of them
    /// at once; splitting them would misrepresent the hardest part of a run.
    ///
    /// Titles come from the terminal entry's seeded `place` with a trailing " Gym" removed —
    /// "Oreburgh Gym" is how the data names it, "Oreburgh" is how players do.
    public static func chapters(_ rows: [Row]) -> [Chapter] {
        var out: [Chapter] = []
        var current: [Row] = []
        for row in rows {
            current.append(row)
            if row.isBoss, row.isGym {
                out.append(chapter(from: current))
                current = []
            }
        }
        // Everything after the last gym: the League, and any trailing routes.
        if !current.isEmpty { out.append(chapter(from: current)) }
        return out
    }

    private static func chapter(from rows: [Row]) -> Chapter {
        let last = rows[rows.count - 1]
        let place = last.place?.replacingOccurrences(of: " Gym", with: "")
        return Chapter(
            id: last.slug,
            title: place?.isEmpty == false ? place! : last.slug,
            rows: rows
        )
    }

    /// The chapter the run is currently working through: the one holding the first unbeaten boss.
    ///
    /// Derived from the **beaten set**, never from the first unlogged route. Beating bosses is
    /// monotone; logging routes is not. Platinum's Valley Windworks can only be caught on a Friday
    /// after Mars is down, so a player who defers it would otherwise pin the open chapter there
    /// for the rest of the run.
    ///
    /// Nil once every boss is beaten.
    public static func openChapterID(_ chapters: [Chapter], beaten: Set<String>) -> String? {
        chapters.first { chapter in
            chapter.rows.contains { $0.isBoss && !beaten.contains($0.slug) }
        }?.id
    }

    /// Whether a chapter has nothing left owed: every boss beaten **and** every location logged.
    ///
    /// Deliberately not "its gym is beaten". One encounter per route is the rule, so a route you
    /// walked past unresolved stays owed until the run ends — and Platinum guarantees the case,
    /// because Valley Windworks (stop 13) sits *before* the Mars fight (stop 14) that unlocks its
    /// only encounter. Collapsing on the gym would hide that route at the moment it became
    /// catchable, and keep it hidden for up to a week of real time.
    public static func isResolved(
        _ chapter: Chapter, beaten: Set<String>, logged: Set<String>
    ) -> Bool {
        chapter.rows.allSatisfy { row in
            row.isBoss ? beaten.contains(row.slug) : logged.contains(row.slug)
        }
    }

    /// Locations in a chapter with no encounter logged — the debt a collapsed header must show.
    public static func openRouteCount(_ chapter: Chapter, logged: Set<String>) -> Int {
        chapter.rows.count { !$0.isBoss && !logged.contains($0.slug) }
    }
}
