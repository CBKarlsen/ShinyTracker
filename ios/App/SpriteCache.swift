import SwiftUI
import UIKit

/// A decoded-image cache in front of the sprite CDN.
///
/// `AsyncImage` keeps no decoded cache: scrolling a row off screen and back re-fetches and
/// re-decodes it, which is why sprites pop in twice on the same list. Every sprite is also an
/// external request — `sprite_url` points at PokeAPI's CDN and ``SpriteSource`` falls back to the
/// same host — so the round trip is real.
///
/// An actor *around* `NSCache`, not instead of it. The actor is for the fetch: two rows asking for
/// the same URL at once must not both hit the network, and `inFlight` is what makes the second one
/// wait. The storage underneath is `NSCache` because a plain dictionary never gives anything back —
/// scrolling the full dex decodes ~2,600 sprites and the app simply keeps them all, on the order of
/// 100MB, until the system kills it. `NSCache` evicts under memory pressure by itself, which is the
/// entire reason to use it here: no memory-warning observer, no LRU, no eviction policy to write.
///
/// `UIKit` is imported unguarded, unlike ``Haptics``: this type's whole surface is `UIImage`, so a
/// `#if canImport(UIKit)` would delete the method its only caller depends on rather than degrade.
/// The app target is iOS-only (`project.yml`), so there is no platform to degrade for.
///
/// ponytail: no third-party image library. This is one app's worth of sprites at two fixed sizes.
actor SpriteCache {
    static let shared = SpriteCache()

    // NSURL, not URL: NSCache keys must be objects. No countLimit or totalCostLimit is set on
    // purpose — the system's own pressure signal is a better bound than any number picked here,
    // and a hard cap would evict on a device with memory to spare.
    private let cached = NSCache<NSURL, UIImage>()
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    func image(for url: URL) async -> UIImage? {
        if let hit = cached.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return await running.value }

        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return UIImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        // A miss is not cached: a sprite that 404s today may exist after the next backfill, and
        // the URLCache below already absorbs the repeated request cheaply.
        if let image { cached.setObject(image, forKey: url as NSURL) }
        return image
    }
}
