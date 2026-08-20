import ActivityKit
import AppIntents
import Foundation

/// The live hunt, as the Lock Screen and Dynamic Island see it.
///
/// **This file is compiled into both the app and the widget extension** (see `project.yml`), so it
/// may not reference anything that exists in only one of them — no `HuntListModel`, no `APIClient`.
/// That constraint is the whole reason ``LiveHuntCounter`` is a registry rather than a direct call:
/// the widget needs the *type* of the intent to build its button, while the work the intent does
/// lives in the app.
///
/// `attributes` are fixed for the life of the activity (which hunt, which species); `ContentState`
/// is everything that moves.
struct HuntActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var count: Int
        /// Banked active time, in seconds. A plain number rather than a `Date` the widget could
        /// tick against: ``HuntClock`` only advances when an encounter is recorded, so a running
        /// timer on the Lock Screen would invent time the hunt did not spend.
        var elapsedSeconds: Int
        /// What one press of the button adds — the card's ×N, mirrored so the Lock Screen and the
        /// card cannot disagree about what a tap means.
        var step: Int
        /// `1 / denominator`, absent for a hunt with no game and therefore no honest odds.
        var denominator: Int?
        var cumulativeProbability: Double?
        /// Whether the clock is still banking time. Drives the dot, exactly as on the card.
        var counting: Bool
    }

    var huntID: UUID
    var speciesName: String
    var pokemonID: Int
    /// "Black 2/White 2 · Random Encounter" — the card's meta line.
    var meta: String
}

// MARK: - Driving the activity

/// Starts, updates and ends the hunt's Live Activity.
///
/// Exists as a `nonisolated` bridge for a concurrency reason, and keeps existing for a better one.
///
/// The concurrency reason: ActivityKit's `Activity` is a non-`Sendable` class whose `update` and
/// `end` are `nonisolated async`, so a `@MainActor` model that stored one and awaited on it would
/// be sending it across an isolation boundary — which Swift 6 rejects, correctly. Every `Activity`
/// value stays inside these functions; the caller passes Sendable data in and never sees the object.
///
/// The better reason: with the lookup done through `Activity.activities` there is no stored handle
/// to keep in sync. The system already owns the list of running activities, and it outlives the
/// app's memory — a hunt whose card survived a launch is found here rather than started twice.
enum HuntActivityBridge {
    static func sync(attributes: HuntActivity, state: HuntActivity.ContentState) async {
        if let running = Activity<HuntActivity>.activities.first(
            where: { $0.attributes.huntID == attributes.huntID })
        {
            await running.update(ActivityContent(state: state, staleDate: nil))
            return
        }
        // A different hunt went live. The species and the hunt id are `attributes`, which
        // ActivityKit fixes for the life of an activity precisely so a card cannot start
        // describing something else under the user — so the old card ends rather than changing.
        await endAll()
        // The user can switch Live Activities off for this app. That is not an error worth
        // reporting: everything still works, there is just no card.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        _ = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil))
    }

    /// Moves a running card on by `step`, with no model and no network.
    ///
    /// The killed-app route (``LiveHuntFallback``) has no `HuntListModel` to assemble a state from
    /// and no session to fetch one with — but it does not need either. The number on screen is the
    /// running activity's own content state, which the system kept while the process was dead, so
    /// the press can read it, add its step and push it back.
    ///
    /// **Only the fields derived from the count move.** `cumulativeProbability` is `count`'s
    /// function and would otherwise sit at the probability of a smaller hunt — the most visibly
    /// wrong thing on the card after the count itself. The rest are deliberately carried through
    /// untouched, because moving them here would mean inventing them:
    /// - `elapsedSeconds` — the clock only banks time when an encounter is recorded *by the model*
    ///   (D1), and the app is not running. No time was banked, so none is added.
    /// - `counting` — the same clock's question, and answering it needs the hunt's cadence.
    /// - `step` and `denominator` — owned by the model, which recomputes them from the hunt's
    ///   parameters on the next `syncActivity()`. A chain method's denominator does drift from the
    ///   count, and this path cannot honestly recompute it without `HuntDetail`.
    ///
    /// If no activity is running this is a no-op, and deliberately does not start one: requesting
    /// an activity from a background launch is unreliable, and the queue append the caller has
    /// already made is what actually matters.
    static func advance(_ huntID: UUID, by step: Int) async {
        guard
            let running = Activity<HuntActivity>.activities.first(
                where: { $0.attributes.huntID == huntID })
        else { return }
        var state = running.content.state
        state.count += step
        // Same expression as `HuntRow.cumulativeProbability`, on the two numbers the card carries.
        if let denominator = state.denominator, denominator > 0, state.count > 0 {
            state.cumulativeProbability = 1 - pow(1 - 1 / Double(denominator), Double(state.count))
        }
        await running.update(ActivityContent(state: state, staleDate: nil))
    }

    static func endAll() async {
        for running in Activity<HuntActivity>.activities {
            await running.end(nil, dismissalPolicy: .immediate)
        }
    }
}

// MARK: - Formatting

/// `fmtTime` from the prototype: `1h 05m`, `41m`, `3d`. Anything under a minute renders as "—"
/// at the call site, exactly as `elapsed` does there.
///
/// Lives in this file rather than beside the hunt card because the Lock Screen prints the same
/// number, and a second copy of a formatting rule is a rule that drifts.
func formatElapsed(_ seconds: Int) -> String {
    guard seconds >= 60 else { return "—" }
    let hours = seconds / 3600
    let minutes = Int((Double(seconds % 3600) / 60).rounded())
    if hours >= 24 { return "\(Int((Double(hours) / 24).rounded()))d" }
    if hours >= 1 { return String(format: "%dh %02dm", hours, minutes) }
    return "\(max(1, minutes))m"
}

// MARK: - Counting from outside the app

/// Where the Lock Screen's `+` lands.
///
/// A registry, not a call, for two reasons. The compile-time one is above: this file has to build
/// inside the widget extension, which has no model to call. The runtime one matters more — there
/// are two entirely different situations in which the button can be pressed, and only one of them
/// has a `HuntListModel` in memory:
///
/// - **The app is alive** (foregrounded, or backgrounded but not yet killed). Its model holds the
///   write queue in memory and rewrites the whole file on every `bump`. Appending to that file
///   from here would be clobbered by the model's next `persist()`, so the tap *must* go through
///   the model. ``handler`` is that route.
/// - **The app was killed.** iOS launches it in the background to perform the intent, and the
///   view tree that builds `AppShell` — and with it the model — may never be evaluated. Nothing
///   holds the queue, so writing the file directly is not only safe, it is the only option.
///   ``fallback`` is that route, installed from `ShinyTrackerApp.init()`, which runs on every
///   launch including a background one.
///
/// The order is what keeps them from fighting: a live model always wins, and the fallback is only
/// reached when there is provably nothing in memory to diverge from.
@MainActor
final class LiveHuntCounter {
    static let shared = LiveHuntCounter()
    private init() {}

    /// Set by `HuntListModel` while it exists. Returns false when it could not take the tap —
    /// which is not the same as "no model": a background launch can build the model without ever
    /// running `load()`, leaving `rows` empty and the hunt unknown to it. Reporting that honestly
    /// is what lets the durable path pick the tap up instead of it vanishing.
    var handler: ((UUID, Int) async -> Bool)?
    /// Set once by `ShinyTrackerApp.init()`, which runs on every launch including a background
    /// one. Appends straight to the persisted queue, and is reached only when nothing in memory
    /// owns that queue — so there is nothing for it to race.
    var fallback: ((UUID, Int) async -> Void)?

    func count(_ huntID: UUID, by step: Int) async {
        if let handler, await handler(huntID, step) { return }
        await fallback?(huntID, step)
    }
}

/// The `+` on the Lock Screen and in the Dynamic Island.
///
/// `LiveActivityIntent` is the part that makes this work at all: it tells the system to perform the
/// intent **in the app's process** rather than the widget extension's, which is what lets one write
/// queue stay the single owner of every counted encounter. An ordinary `AppIntent` would run in the
/// extension, where the queue is not.
struct LiveHuntCountIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Count an encounter"
    static let description = IntentDescription("Adds encounters to the hunt on your Lock Screen.")
    /// Not something to surface in Shortcuts or Spotlight — it is the button's implementation, and
    /// it means nothing without the Live Activity that carries the hunt it refers to.
    static let isDiscoverable = false

    /// A string, not a `UUID`: `@Parameter` has no UUID representation.
    @Parameter(title: "Hunt") var huntID: String
    @Parameter(title: "Encounters") var step: Int

    init() {}

    init(huntID: UUID, step: Int) {
        self.huntID = huntID.uuidString
        self.step = step
    }

    func perform() async throws -> some IntentResult {
        // A malformed id is not worth throwing over — the button would just fail silently anyway,
        // and there is no user-visible recovery from "the activity carried a bad id".
        if let id = UUID(uuidString: huntID) {
            await LiveHuntCounter.shared.count(id, by: step)
        }
        return .result()
    }
}
