import Foundation

/// Active time on one hunt, accumulated on the client.
///
/// D1 (`docs/handoff/DECISIONS.md`): the client owns elapsed time and the server stores it. The
/// server cannot derive this — it only sees PATCHes, so a session counted offline is invisible to
/// it and the single catch-up PATCH afterwards looks like one enormous gap.
///
/// **Never driven by a running `Timer`.** iOS suspends the app and a `Timer` stops with it, so
/// this holds timestamps and computes from them; a foreground recompute is just another
/// ``record(at:idleThreshold:)``.
public struct HuntClock: Codable, Sendable, Equatable {
    public private(set) var totalSeconds: Int
    public private(set) var lastEncounterAt: Date?

    public init(totalSeconds: Int = 0, lastEncounterAt: Date? = nil) {
        self.totalSeconds = totalSeconds
        self.lastEncounterAt = lastEncounterAt
    }

    /// Banks the gap since the previous encounter, if it looks like hunting rather than a pause.
    ///
    /// A gap longer than the threshold contributes nothing and simply restarts the clock — the
    /// hunter put the phone down, and crediting that time is how a hunt ends up claiming eight
    /// hours it did not have.
    public mutating func record(at now: Date, idleThreshold: TimeInterval) {
        defer { lastEncounterAt = now }
        guard let last = lastEncounterAt else { return }
        let gap = now.timeIntervalSince(last)
        // `gap > 0` guards a backwards clock: a device time change must never bank negative time.
        guard gap > 0, gap <= idleThreshold else { return }
        totalSeconds += Int(gap.rounded())
    }

    /// How long a pause may be before it stops counting, derived from the method's own cadence.
    ///
    /// `hunt_methods.avg_time_seconds` is how long one encounter takes — about 7s for a wild
    /// encounter, about 30s for a soft reset — and reaches the client on `HuntDetail`, so no API
    /// change is needed. Twenty encounters' worth of silence is a pause; the clamp stops a
    /// one-second method from stopping the clock almost instantly, and a very slow one from
    /// banking an overnight gap.
    public static func idleThreshold(avgTimeSeconds: Int?) -> TimeInterval {
        guard let average = avgTimeSeconds, average > 0 else { return 600 }
        return min(max(Double(average) * 20, 120), 900)
    }
}
