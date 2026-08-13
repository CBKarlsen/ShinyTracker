# Offline foundation (sub-project A) — design

**Status:** proposed 2026-08-12.

First of three sequenced sub-projects toward "everything writable offline". This one makes the
app **readable** offline and completes D1, so that the write queue in sub-project B has a floor to
stand on. It adds no queue and changes no write semantics beyond D1's own.

---

## Why this is first

A queue that replays into today's `UpdateHuntHandler` would destroy the thing it exists to
protect. Two reasons, one already fixed and one not:

- **Time — already handled.** `DECISIONS.md` D1 says the client owns elapsed time. Its status line
  reads "Not yet implemented" and **that line is stale**: migration `012_add_client_owns_time.sql`
  added the per-hunt latch, `calc.DecideTotalTime` exists with tests, and `hunts.go` wires it in.
  A PATCH carrying `total_time_seconds` latches that hunt client-authoritative permanently. What
  is missing is a client that actually sends it. (This spec also corrects the stale status line.)
- **Count — not handled.** The same UPDATE does a plain `SET encounter_count = $1`. That is
  last-write-wins, which D1 explicitly forbids: *"Never overwrite a higher server value with a
  lower local one without an explicit user decision… Losing a long hunt is the one unforgivable
  failure in this app."* A replayed offline burst racing a second device does exactly that today.

## Scope

In: a snapshot store, cold-launch rendering from it, client-side time accumulation, and the
monotonic count guard. Out: the write queue, retry, replay ordering, and any offline *writing* —
all sub-project B. Out: Nuzlocke/dex/charm write paths — sub-project C.

---

## 1. `SnapshotStore` — in `ShinyTrackerAPI`, not the app target

The package that owns the `Codable` payloads owns persisting them. This placement is the load-bearing
decision: **the package has a test target and the app target does not.** The previous slice had to
record an untestable derivation as debt; persistence — silent corruption, a key collision across
accounts, a partial write — is the last code that should be unverified.

```swift
public actor SnapshotStore {
    public init(userID: UUID?, directory: URL? = nil)      // nil directory = Application Support
    public func save<T: Encodable>(_ value: T, as key: SnapshotKey) async
    public func load<T: Decodable>(_ type: T.Type, as key: SnapshotKey) async -> T?
    public func clear() async                              // sign-out
}
public struct SnapshotKey: Hashable, Sendable {
    public let filename: String                            // validated: [a-z0-9-] only
    public static let hunts   = SnapshotKey("hunts")
    public static let games   = SnapshotKey("games")
    public static let species = SnapshotKey("species")     // GET /api/pokemon?limit=all
    public static let dex     = SnapshotKey("dex")         // /dex/status + availability
    public static let runs    = SnapshotKey("runs")
    public static func run(_ id: UUID) -> SnapshotKey      // one file per run's detail
}
```

A struct rather than a `String` enum because one key is parameterised: `GET /api/runs/{id}`
returns a whole timeline per run, and a single `run` file would thrash every time the user switched
runs. The filename is validated to `[a-z0-9-]` so an id can never escape the directory.

`species` is one key, not two: the Dex grid and the Nuzlocke coverage warning both derive from the
same `GET /api/pokemon?limit=all` payload, and caching it twice would double the largest file in
the store for no benefit.

**Keyed by user id.** Files live under `Application Support/ShinyTracker/Snapshots/<userID>/`.
`DexModel`'s existing UserDefaults store already documents why: an unscoped key shows one account
another's dex after a sign-out/sign-in on the same device. A nil user id (preview harnesses) gets
an ephemeral directory and never touches the real one.

**A miss is the only failure mode.** Every read path returns `T?`. A corrupt file, a truncated
write, a payload whose shape has changed server-side, a version mismatch — all return `nil` and
the caller falls back to the network. Persistence must never produce an error screen or a crash;
the worst outcome it is allowed to cause is the spinner the user would have seen anyway.

**Writes are atomic** — encode to a temporary file in the same directory, then `replaceItem`. A
crash or a kill mid-write leaves the previous snapshot intact rather than a half-file that decodes
into a plausible-but-wrong screen.

**Envelope carries a schema version.** Bumping it discards every snapshot rather than attempting
migration. These are caches, not records; the server is the source of truth and a refetch costs one
request.

**File protection `.completeUntilFirstUserAuthentication`** — encrypted at rest, still readable
after a reboot before unlock, which background sync in sub-project B will need.

## 2. Cold-launch rendering

Each model's cold path gains a step before the network:

1. `load()` asks the store for its snapshot.
2. If present, populate state and set `.ready` — the screen draws immediately, from disk.
3. Fetch as today; on success, update state and save the new snapshot.
4. On failure with a snapshot showing, report through `syncError` (the warm-path treatment from
   the perceived-performance slice), **not** `state = .failed`. Cached data plus a quiet warning
   beats an error page.

This composes with `appear()` rather than replacing it: `appear()` decides warm-vs-cold *within* a
session, snapshots decide what a *cold* start draws.

The consequence worth stating: a cold launch shows **stale** data for as long as the refresh takes.
That is the deliberate trade — it is what "opens instantly" means. Snapshots are never shown
without a refresh being started in the same breath.

## 3. The client clock — `HuntClock`, in `ShinyTrackerKit`

Pure domain logic with no UI and no networking, in the package that already holds the odds engine
and its anchor tests.

```swift
public struct HuntClock: Codable, Sendable, Equatable {
    public private(set) var totalSeconds: Int
    public private(set) var lastEncounterAt: Date?
    public mutating func record(at now: Date, idleThreshold: TimeInterval)
    public static func idleThreshold(avgTimeSeconds: Int?) -> TimeInterval
}
```

- `record` adds the gap since the previous encounter **only if that gap is under the threshold**.
  A longer gap contributes nothing and simply restarts the clock.
- **Never a running `Timer`.** iOS suspends the app and a `Timer` stops with it; D1 requires
  elapsed time be computed from stored timestamps. `HuntClock` holds dates, so a foreground
  recompute is just another `record`.
- `idleThreshold` = `20 × avg_time_seconds`, clamped to 2–15 minutes, falling back to 10 minutes
  when `avgTimeSeconds` is nil. Per-method rather than fixed because a soft-reset hunt's normal
  cadence is minutes and a wild-encounter hunt's is seconds — one constant cannot serve both.
  `avg_time_seconds` already reaches the client on `HuntDetail`, so no API change.
- The clock is `Codable` and persists per hunt through `SnapshotStore`, so time survives relaunch.

`HuntListModel.flush` then sends `totalTimeSeconds`, which latches `client_owns_time` for that
hunt. Its current comment — that it must not claim authority it does not have — stops being true
and is removed.

## 4. The monotonic count guard — backend

`SET encounter_count = $1` becomes a guard that cannot lower the count **except when the user
explicitly asked**. The subtlety: the app has a `−` button, so decrements are legitimate. A bare
`GREATEST` would silently break it.

So the intent travels with the request:

- `PATCH /api/hunts/{id}` accepts an optional `allow_decrease` (absent = false).
- Absent/false: `SET encounter_count = GREATEST(encounter_count, $1)`. A sync, a replay, or a
  second device can only ever raise it.
- True: assign exactly. Set only by the `−` control, never by sync or replay.

The response returns the stored count, so a client whose value lost the comparison learns the
truth immediately rather than diverging.

---

## Testing

The first slice in this programme that can be genuinely tested, which is much of why the store
lives where it does.

**`ShinyTrackerAPITests`** — `SnapshotStore` against a temporary directory:
round-trip; corrupt file → nil; truncated file → nil; version mismatch → nil; two user ids do not
see each other's snapshots; `clear()` removes only its own user's; a save interrupted before
`replaceItem` leaves the prior snapshot readable.

**`ShinyTrackerKitTests`** — `HuntClock`: a gap under the threshold accumulates; a gap over it
contributes nothing; the first encounter contributes nothing; threshold derivation clamps at both
ends and falls back on nil; a `Codable` round-trip preserves both fields.

**Go** — `DecideTotalTime`'s suite already exists and must stay green. New table tests for the
count guard: a lower count without `allow_decrease` does not lower the stored value; the same with
`allow_decrease` does; an equal or higher count always writes.

**Not tested mechanically:** the model wiring in step 2, which lives in the app target. Verified by
build plus the preview harnesses, and judged on device — no agent in this environment can drive
simulator gestures.

---

## Deferred

- **The write queue, replay, retry, idempotency** — sub-project B. Nothing here queues anything;
  a write with no connection still fails as it does today.
- **Nuzlocke, dex and charm write paths** — sub-project C.
- **A staleness threshold on `appear()`** — snapshots make a cold start instant but every tab
  switch still re-requests. Worth revisiting once real usage shows what "too old" means.

## Related

- `docs/handoff/DECISIONS.md` — D1 (this spec completes it and corrects its status line), D3
- `docs/superpowers/specs/2026-08-12-ios-perceived-performance-design.md` — the warm/cold `appear()`
  split this builds on
