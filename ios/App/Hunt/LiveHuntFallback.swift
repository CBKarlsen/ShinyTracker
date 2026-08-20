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
        let stored = await store(for: userID).mutate(
            WriteQueue.self, as: .pendingWrites, default: WriteQueue()
        ) {
            $0.enqueue(.count(delta: step), for: huntID)
        }
        // A save can fail for a reason that does not pass — a full disk, or file protection before
        // the first unlock after a reboot. Moving the card anyway would be the worst outcome this
        // path can produce: the hunter watches the number climb to 8,000 while nothing at all is
        // recorded. A card that visibly stops moving is the honest signal, and it is the one thing
        // that makes them check.
        guard stored else { return }

        // Without this the card freezes: the count is recorded, the Lock Screen keeps showing the
        // old number, and the hunter presses again because it looks like the tap was dropped. Over
        // an 8,000-encounter hunt that is not a cosmetic bug, it is a systematic *over*count — the
        // frozen display manufactures the extra presses.
        await raiseCard(huntID, by: step)
    }

    /// The number this hunt's card should be showing, per press.
    ///
    /// Separate from the queue because the two answer different questions: the queue owns what the
    /// server is owed, this owns what the Lock Screen is displaying. They are reconciled the next
    /// time the app actually loads, when the model pushes a full state it computed from the server's
    /// count plus everything still queued.
    private static var target: [UUID: Int] = [:]
    /// Hunts with a push in flight. One pusher at a time, so two `update` calls cannot land out of
    /// order and leave the lower number on screen.
    private static var pushing: Set<UUID> = []

    /// Raises the card to a target this press computes, rather than adding to what the card reads.
    ///
    /// Every line up to the `guard` runs without suspending, which is what makes it correct: two
    /// presses a few hundred milliseconds apart are two independent Tasks, and `@MainActor` alone
    /// would not save them — MainActor is reentrant at every `await`, so both could read the same
    /// card count and both write count+1. Reading and raising `target` in one synchronous stretch
    /// means the second press always sees the first press's number.
    ///
    /// `max(card, target)` because either can be the stale one: `target` is empty on a fresh
    /// background launch and the card is authoritative, while after a press the card may not yet
    /// reflect an `update` that has already returned.
    ///
    /// The loop is a coalescer, not a retry. While one press is awaiting its push another can raise
    /// `target`; re-reading it after the await delivers the newer number on the same pusher instead
    /// of racing a second one against it.
    private static func raiseCard(_ huntID: UUID, by step: Int) async {
        let card = HuntActivityBridge.currentCount(huntID) ?? 0
        target[huntID] = max(card, target[huntID] ?? 0) + step
        guard !pushing.contains(huntID) else { return }
        pushing.insert(huntID)
        defer { pushing.remove(huntID) }

        var pushed: Int?
        while let want = target[huntID], want != pushed {
            pushed = want
            await HuntActivityBridge.set(huntID, count: want)
        }
    }
}
