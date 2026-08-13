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
    /// Sub-second remainder. Rounding each gap independently compounds: at a steady 6.6s cadence
    /// over 10,000 encounters that is an hour of invented time. Whole seconds move to
    /// `totalSeconds`, the remainder stays here.
    private var carry: Double

    public init(totalSeconds: Int = 0, lastEncounterAt: Date? = nil) {
        self.totalSeconds = totalSeconds
        self.lastEncounterAt = lastEncounterAt
        self.carry = 0
    }

    // Nothing has persisted a HuntClock yet (Task 5 wires that up), so this isn't a real
    // migration — just cheap insurance so an old decoded blob defaults `carry` to 0 instead of
    // failing to decode once this field exists.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalSeconds = try container.decode(Int.self, forKey: .totalSeconds)
        lastEncounterAt = try container.decodeIfPresent(Date.self, forKey: .lastEncounterAt)
        carry = try container.decodeIfPresent(Double.self, forKey: .carry) ?? 0
    }

    /// Banks the gap since the previous encounter, if it looks like hunting rather than a pause.
    ///
    /// A gap longer than the threshold contributes nothing and simply restarts the clock — the
    /// hunter put the phone down, and crediting that time is how a hunt ends up claiming eight
    /// hours it did not have.
    public mutating func record(at now: Date, idleThreshold: TimeInterval) {
        guard let last = lastEncounterAt else {
            lastEncounterAt = now
            return
        }
        let gap = now.timeIntervalSince(last)
        // A backwards clock leaves the anchor alone: advancing it here would make the next
        // legitimate encounter measure against a too-early timestamp and bank the difference as
        // phantom hunting time.
        guard gap > 0 else { return }
        defer { lastEncounterAt = now }
        guard gap <= idleThreshold else { return }
        carry += gap
        let whole = carry.rounded(.down)
        totalSeconds += Int(whole)
        carry -= whole
    }

    /// Lifts the clock to a server total that is ahead of it.
    ///
    /// `calc.DecideTotalTime` stores the larger of stored-and-sent, so a client sitting behind the
    /// server — another device counted, this one's snapshot was lost — has everything it sends
    /// swallowed until it organically overtakes that total again. Hours of real hunting can be
    /// credited as nothing. Adopting the server's number on read makes the next flush additive.
    public mutating func raise(to seconds: Int) {
        totalSeconds = max(totalSeconds, seconds)
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
