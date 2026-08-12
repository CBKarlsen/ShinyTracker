import Foundation

/// Where a species' sprite comes from.
///
/// The server is the preferred source: `pokemon.sprite_url` and `shiny_sprite_url` ride along on
/// the pokemon, hunt and phase responses, so the host lives in the database and changing it (a
/// mirror, a CDN, bundled assets) is a data change rather than an app release.
///
/// ponytail: the hardcoded PokeAPI host survives only as the fallback, because the shiny column
/// is filled by migration 016's backfill — a server that has not run it yet answers `""`, and a
/// blank tile is worse than a sprite from the old place. Delete ``base`` once every deployment
/// has the backfill; nothing else has to change when you do.
enum SpriteSource {
    private static let base = "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/"

    /// - Parameter served: what the API returned for this species, if anything. Blank and nil are
    ///   the same thing — the API COALESCEs a missing sprite to `""`.
    static func url(id: Int, shiny: Bool, served: String? = nil) -> URL? {
        if let served, !served.isEmpty {
            return URL(string: served)
        }
        return URL(string: base + (shiny ? "shiny/" : "") + "\(id).png")
    }
}
