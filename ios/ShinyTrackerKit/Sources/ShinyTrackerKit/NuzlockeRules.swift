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
}
