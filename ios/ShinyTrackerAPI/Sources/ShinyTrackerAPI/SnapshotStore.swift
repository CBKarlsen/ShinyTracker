import Foundation

/// Which cached payload a file holds.
///
/// A struct rather than a `String` enum because one key is parameterised: `GET /api/runs/{id}`
/// returns a whole timeline per run, and a single shared `run` file would be rewritten every time
/// the user switched runs. There is deliberately no public string initialiser — every key is
/// constructed here, so a filename can never contain a path separator and escape the directory.
public struct SnapshotKey: Hashable, Sendable {
    public let filename: String

    private init(_ filename: String) { self.filename = filename }

    public static let hunts = SnapshotKey("hunts")
    public static let games = SnapshotKey("games")
    /// `GET /api/pokemon?limit=all`. One key, not two: the Dex grid and the Nuzlocke coverage
    /// warning derive from the same payload, and it is the largest file in the store.
    public static let species = SnapshotKey("species")
    public static let dex = SnapshotKey("dex")
    public static let runs = SnapshotKey("runs")
    /// `game_id -> has_shiny_charm` for the signed-in user. Cached alongside `.games` because a
    /// games list restored without it renders every row as not-in-your-library — a falsehood
    /// rather than merely stale, and the Games tab is exactly where a user would act on it.
    public static let userGames = SnapshotKey("user-games")
    /// Per-hunt client-owned elapsed time (`HuntClock`). Persisted so time survives a relaunch;
    /// the server only learns it on the next flush.
    public static let clocks = SnapshotKey("clocks")
    /// Hunt writes made but not yet accepted by the server. Durable because its whole purpose is
    /// surviving the app being killed between counting and connectivity returning.
    ///
    /// **The one key here that is records, not cache.** Every other key can be thrown away and
    /// refetched; this one is the *only* copy of encounters the server has never seen, so
    /// discarding it loses a hunt — the failure D1 calls unforgivable. If `PendingWrite`'s shape
    /// ever changes, this key must be migrated (decode the old shape, write the new one), never
    /// dropped with a `schemaVersion` bump. See the note on `SnapshotStore.schemaVersion`.
    public static let pendingWrites = SnapshotKey("pending-writes")

    /// `uuidString.lowercased()` is `[0-9a-f-]` only, so this cannot produce a traversing path.
    public static func run(_ id: UUID) -> SnapshotKey {
        SnapshotKey("run-\(id.uuidString.lowercased())")
    }
}

/// Last-known API payloads on disk, so a cold launch draws something before the network answers.
///
/// **A miss is the only failure mode — for every key except `.pendingWrites`.** Corrupt file,
/// truncated write, a payload whose shape changed server-side, a version bump — every one returns
/// nil and the caller falls back to the network. Persistence must never produce an error screen or
/// a crash; the worst outcome it is allowed to cause is the spinner the user would have seen
/// anyway. That is why nothing here throws and every failure path is a silent `return`.
///
/// `.pendingWrites` is the exception and does not fall back to anything: the network is where its
/// contents were *going*. A miss there is lost encounters, not a spinner.
public actor SnapshotStore {
    /// Bumping this discards every snapshot rather than migrating. Caches, not records — the
    /// server is the source of truth and a refetch costs one request.
    ///
    /// **Except `.pendingWrites`, which the server has never seen.** Bumping this without
    /// migrating that key first deletes every user's unsent hunt counts, including a whole offline
    /// session. Migrate it (read the old shape, write the new) before touching this number.
    static let schemaVersion = 1

    private let directory: URL
    private let fileManager = FileManager.default

    /// `userID` nil means an anonymous store — the DEBUG preview harnesses, which have no
    /// session. It gets its own directory so a screenshot run cannot poison a real account's
    /// cache.
    public init(userID: UUID?, containerDirectory: URL? = nil) {
        let container = containerDirectory
            ?? (try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask,
                appropriateFor: nil, create: true))
            .map { $0.appendingPathComponent("ShinyTracker/Snapshots") }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("ShinyTracker")
        directory = container.appendingPathComponent(userID?.uuidString.lowercased() ?? "anonymous")
    }

    public func save<T: Codable>(_ value: T, as key: SnapshotKey) {
        guard let data = try? JSONEncoder().encode(
            Envelope(version: Self.schemaVersion, value: value))
        else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Written to a sibling temp file and moved into place: a crash or a kill mid-write must
        // leave the previous snapshot intact rather than a half-file that decodes into a
        // plausible-but-wrong screen.
        let destination = url(for: key)
        let temporary = directory.appendingPathComponent("\(key.filename).writing")
        do {
            try data.write(to: temporary, options: writingOptions)
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } catch {
            try? fileManager.removeItem(at: temporary)
        }
    }

    public func load<T: Codable>(_ type: T.Type, as key: SnapshotKey) -> T? {
        guard
            let data = try? Data(contentsOf: url(for: key)),
            let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data),
            envelope.version == Self.schemaVersion
        else { return nil }
        return envelope.value
    }

    /// Sign-out. Removes this user's snapshots and nobody else's.
    public func clear() {
        try? fileManager.removeItem(at: directory)
    }

    private func url(for key: SnapshotKey) -> URL {
        directory.appendingPathComponent("\(key.filename).json")
    }

    /// File protection is iOS-only and does not compile on macOS, where `swift test` runs this
    /// package. `completeUntilFirstUserAuthentication` rather than `complete`: the queue in
    /// sub-project B will need to read these during a background sync, before the device is
    /// unlocked.
    private var writingOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        [.atomic]
        #endif
    }
}

/// Wraps the payload so a schema bump is detectable. Both halves are `Codable` so one type serves
/// reading and writing.
private struct Envelope<T: Codable>: Codable {
    let version: Int
    let value: T
}
