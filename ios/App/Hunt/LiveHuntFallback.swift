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

    static func count(_ huntID: UUID, by step: Int) async {
        guard let raw = UserDefaults.standard.string(forKey: userIDKey),
            let userID = UUID(uuidString: raw)
        else { return }

        let store = SnapshotStore(userID: userID)
        var queue = await store.load(WriteQueue.self, as: .pendingWrites) ?? WriteQueue()
        queue.enqueue(.count(delta: step), for: huntID)
        await store.save(queue, as: .pendingWrites)
    }
}
