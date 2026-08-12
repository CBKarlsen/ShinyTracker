import SwiftUI
import UIKit

/// A decoded-image cache in front of the sprite CDN.
///
/// `AsyncImage` keeps no decoded cache: scrolling a row off screen and back re-fetches and
/// re-decodes it, which is why sprites pop in twice on the same list. Every sprite is also an
/// external request — `sprite_url` points at PokeAPI's CDN and ``SpriteSource`` falls back to the
/// same host — so the round trip is real.
///
/// An actor rather than `NSCache`: the values are fetched asynchronously and two rows asking for
/// the same URL at once must not both fetch it. `inFlight` is what makes the second one wait.
///
/// `UIKit` is imported unguarded, unlike ``Haptics``: this type's whole surface is `UIImage`, so a
/// `#if canImport(UIKit)` would delete the method its only caller depends on rather than degrade.
/// The app target is iOS-only (`project.yml`), so there is no platform to degrade for.
///
/// ponytail: no third-party image library. This is one app's worth of sprites at two fixed sizes.
actor SpriteCache {
    static let shared = SpriteCache()

    private var cached: [URL: UIImage] = [:]
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    func image(for url: URL) async -> UIImage? {
        if let hit = cached[url] { return hit }
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
        if let image { cached[url] = image }
        return image
    }
}
