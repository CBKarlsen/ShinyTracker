import Foundation

/// Where a species' sprite comes from.
///
/// The server is the preferred source: `pokemon.sprite_url` and `shiny_sprite_url` ride along on
/// the pokemon, hunt and phase responses, so the host lives in the database and changing it (a
/// mirror, a CDN, bundled assets) is a data change rather than an app release.
///
/// ponytail: the hardcoded host survives only as the fallback, because the shiny column is filled
/// by migration 016's backfill — a server that has not run it yet answers `""`, and a blank tile is
/// worse than a sprite from the old place. Delete ``base`` once every deployment has the backfill;
/// nothing else has to change when you do.
///
/// jsDelivr rather than `raw.githubusercontent.com`: same repo, byte-identical files, but raw
/// GitHub is a source-code endpoint, not a CDN. Its ToS disallows using it as asset hosting and it
/// rate-limits under load. jsDelivr is built for this and caches for a week. Changing the host for
/// *served* sprites needs no app release at all — it is migration 022, one UPDATE.
///
/// Neither host changes the copyright position; the artwork is still Nintendo's.
enum SpriteSource {
    private static let base = "https://cdn.jsdelivr.net/gh/PokeAPI/sprites@master/sprites/pokemon/"

    /// - Parameter served: what the API returned for this species, if anything. Blank and nil are
    ///   the same thing — the API COALESCEs a missing sprite to `""`.
    static func url(id: Int, shiny: Bool, served: String? = nil) -> URL? {
        if let served, !served.isEmpty {
            return URL(string: served)
        }
        return URL(string: base + (shiny ? "shiny/" : "") + "\(id).png")
    }
}
