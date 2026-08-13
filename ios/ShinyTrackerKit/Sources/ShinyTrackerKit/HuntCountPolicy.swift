import Foundation

/// Which encounter count a hunt row should show, when the client's number and the server's
/// disagree.
///
/// These live here, apart from the view model that applies them, for one reason: they are the
/// rules that broke. Five separate fix passes on `HuntListModel` each closed one scenario without
/// closing the class, and none of it was testable — the model lives in the app target, which has
/// no test target. Every claim about it was derived by reading. The decisions themselves are pure
/// functions of a few integers and booleans, so they belong somewhere they can be executed.
///
/// It is deliberately the same shape as the server's `calc.DecideTotalTime`: small named decisions
/// with tests on both sides of the wire, rather than conditionals buried in a request builder.
///
/// The invariant all of it serves, from `docs/handoff/DECISIONS.md` D1: *"Never overwrite a higher
/// server value with a lower local one without an explicit user decision… Losing a long hunt is
/// the one unforgivable failure in this app."* Writing is no longer part of that — counting goes
/// through deltas, which compose correctly by construction. What is left here is display.
public enum HuntCountPolicy {

    /// What a list rebuild should show for one hunt, and whether that number counts as confirmed.
    ///
    /// The two travel together on purpose. They were separate expressions reading the same state,
    /// and a review found the pairing — a count the client never confirmed, marked confirmed — is
    /// exactly what arms a destructive decrease.
    public struct Rebuild: Equatable, Sendable {
        public let count: Int
        /// Whether this row may now be treated as carrying a server-confirmed number.
        public let isServerBacked: Bool
    }

    /// Resolves one row against a `GET /api/hunts` response.
    ///
    /// - `hasUnflushedBurst`: the user has tapped since the last successful write, so the local
    ///   count is newer than anything the server can report. It wins, and the row stays unconfirmed
    ///   until its own write lands.
    /// - `isServerBacked`: this client has already confirmed a number for this row *this launch*.
    ///   Only then does `max` apply, and only to stop an out-of-order response lowering a count the
    ///   client confirmed.
    ///
    /// A count this client never confirmed gets no such standing. The server may have lowered it
    /// legitimately — `LogPhaseHandler` resets it to 0, and iOS has no `logPhase` call site, so
    /// that reset always arrives as someone else's write. Letting a snapshot outrank it would undo
    /// the phase on the next increment.
    public static func rebuild(
        response: Int,
        onScreen: Int?,
        hasUnflushedBurst: Bool,
        isServerBacked: Bool
    ) -> Rebuild {
        if hasUnflushedBurst {
            return Rebuild(count: onScreen ?? response, isServerBacked: false)
        }
        if isServerBacked {
            return Rebuild(count: max(response, onScreen ?? 0), isServerBacked: true)
        }
        return Rebuild(count: response, isServerBacked: true)
    }

    /// What to display after a write, given what the server says it stored.
    ///
    /// `max`, not the server's value outright: taps made while the request was in flight are real
    /// and must not be discarded. The server's number is a floor, not a replacement.
    public static func reconciled(local: Int, stored: Int) -> Int {
        max(local, stored)
    }
}
