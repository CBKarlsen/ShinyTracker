import Foundation
import ShinyTrackerAPI
import ShinyTrackerKit

/// Counting from the Lock Screen when nothing is in memory to count with.
///
/// This is the second of the two routes described on ``LiveHuntCounter``, and it exists for one
/// situation: the app was killed, iOS launched it in the background to perform the intent, and no
/// `HuntListModel` was ever built — or one was, but it had never loaded and did not recognise the
/// hunt. Either way nothing holds the write queue, so appending to the file on disk is safe. It is
/// only ever reached after the model has declined, which is what keeps two writers off one file.
///
/// The append is deliberately the same shape a tap makes: a `.count` delta into the same
/// ``WriteQueue``, under the same key. The next launch's `restoreQueue()` finds it and drains it
/// like any other entry — it does not need to know where it came from.
///
/// `@MainActor` for the store cache below, and it costs nothing: the only caller,
/// ``LiveHuntCounter/count(_:by:)``, is already main-actor isolated, and so is the
/// `ShinyTrackerApp.init()` that installs this as the fallback. No new isolation domain, no
/// `nonisolated(unsafe)` static.
@MainActor
enum LiveHuntFallback {
    /// Where the signed-in user id is left for a launch that has no session yet.
    ///
    /// The queue is stored per user (``SnapshotStore`` keys its directory by id), and a background
    /// launch has no `AuthSession` restored at the moment the intent runs — so without this the
    /// tap would have no idea which directory to append to. Written by `AppShell` on every signed-in
    /// launch; a stale value after a sign-out is harmless, because the hunts of a signed-out user
    /// have no Live Activity to press.
    static let userIDKey = "live-hunt-user-id"

    static func rememberUser(_ id: UUID?) {
        guard let id else { return }
        UserDefaults.standard.set(id.uuidString, forKey: userIDKey)
    }

    /// The one store every press of the `+` writes through, kept alive between presses.
    ///
    /// A fresh `SnapshotStore` per call would defeat ``SnapshotStore/mutate(_:as:default:_:)``
    /// entirely: an actor serialises calls to *itself*, so two instances over the same directory
    /// are two isolation domains and two presses can still interleave read-modify-write and lose
    /// one. One instance, reused, is what makes the mutate atomic against the next press.
    ///
    /// Keyed by user id rather than a plain `static let`, because the id is read from
    /// `UserDefaults` on every call and a sign-out followed by a sign-in changes it — a cached
    /// store would otherwise keep appending this user's encounters into the previous user's
    /// directory.
    private static var cached: (userID: UUID, store: SnapshotStore)?

    private static func store(for userID: UUID) -> SnapshotStore {
        if let cached, cached.userID == userID { return cached.store }
        let store = SnapshotStore(userID: userID)
        cached = (userID, store)
        return store
    }

    static func count(_ huntID: UUID, by step: Int) async {
        guard let raw = UserDefaults.standard.string(forKey: userIDKey),
            let userID = UUID(uuidString: raw)
        else { return }

        // The queue append is the whole point of this path and goes first, unconditionally. It is
        // one call that cannot throw and cannot be skipped by anything below it — the encounter is
        // durable before a single line of cosmetics runs. Everything after this is the card
        // catching up with a number that is already on disk.
        //
        // One `mutate`, not `load` → enqueue → `save`: the latter is two awaits, actors are
        // reentrant at both, and two presses a few hundred milliseconds apart are two independent
        // Tasks. Both would load the same queue, each append its own tap, and the second save would
        // overwrite the first — one tap gone, silently, on the durable path whose entire job is not
        // to lose taps.
        await store(for: userID).mutate(
            WriteQueue.self, as: .pendingWrites, default: WriteQueue()
        ) {
            $0.enqueue(.count(delta: step), for: huntID)
        }

        // Without this the card freezes: the count is recorded, the Lock Screen keeps showing the
        // old number, and the hunter presses again because it looks like the tap was dropped. Over
        // an 8,000-encounter hunt that is not a cosmetic bug, it is a systematic *over*count — the
        // frozen display manufactures the extra presses.
        await HuntActivityBridge.advance(huntID, by: step)
    }
}
