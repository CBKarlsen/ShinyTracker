# Offline Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app render instantly from disk on a cold launch, and complete D1 — the client accumulates its own elapsed time, and the server refuses to lower an encounter count unless the user explicitly asked.

**Architecture:** Three self-contained, fully testable units first (a snapshot store in `ShinyTrackerAPI`, a clock in `ShinyTrackerKit`, a count decision in `internal/calc`), then two app-target wiring tasks that consume them. No write queue — that is sub-project B.

**Tech Stack:** Swift 6, SwiftUI, local SPM packages, Go 1.x + pgx, XcodeGen.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-12-offline-foundation-design.md`.
- **Tasks 1-3 have test targets and MUST be test-driven** — write the failing test first. This is the whole reason those units live in packages rather than the app target.
- **Tasks 4-5 touch the app target, which has NO test target. Do not add one.** Verify by build plus the DEBUG preview harnesses through `simctl`.
- **No agent in this environment can drive simulator gestures** — no `idb`, no `cliclick`, `simctl` has no touch injection. State plainly what you verified versus what you reasoned about. Never imply you tapped or scrolled.
- Do not build a write queue, retry, or replay. A write with no connection still fails exactly as it does today.
- Do not touch the Nuzlocke, dex or charm write paths (sub-project C).
- Comment idiom: explain *why*, not *what*.
- `Dictionary(_:uniquingKeysWith:)` never `Dictionary(uniqueKeysWithValues:)`.
- Swift commands run from `ios/`; Go commands from `backend/`.
- Simulator UDID `5E394296-95FD-4790-8862-3D6B6BC503C2`, bundle id `com.casperkarlsen.shinytracker`.

---

### Task 1: `SnapshotStore` in `ShinyTrackerAPI`

**Files:**
- Create: `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/SnapshotStore.swift`
- Create: `ios/ShinyTrackerAPI/Tests/ShinyTrackerAPITests/SnapshotStoreTests.swift`

**Interfaces:**
- Produces: `actor SnapshotStore` with `init(userID:containerDirectory:)`, `save<T: Codable>(_:as:)`, `load<T: Codable>(_:as:) -> T?`, `clear()`; and `struct SnapshotKey` with statics `.hunts`, `.games`, `.species`, `.dex`, `.runs` and `static func run(_ id: UUID) -> SnapshotKey`.
- Consumes: nothing.

**Two traps that will cost you an hour if you miss them:**
1. `swift test` builds this package for **macOS**. `Data.WritingOptions.completeFileProtectionUntilFirstUserAuthentication` is iOS-only and will not compile on macOS — it must sit behind `#if os(iOS)`.
2. Do **not** reuse the API's `JSONDecoder` (`decodeGoTimestamp`). That strategy parses Go's RFC 3339 strings. Snapshots are written and read by this store alone, so a plain `JSONEncoder`/`JSONDecoder` pair round-trips `Date` consistently. Mixing them silently fails to decode every snapshot containing a date.

- [ ] **Step 1: Write the failing tests**

Create `SnapshotStoreTests.swift`:

```swift
import Foundation
import Testing

@testable import ShinyTrackerAPI

/// A throwaway directory per test, so nothing touches the real Application Support.
private func tempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("snapshot-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private struct Fixture: Codable, Equatable {
    let name: String
    let count: Int
    let when: Date
}

private let sample = Fixture(name: "gible", count: 2847, when: Date(timeIntervalSince1970: 1_760_000_000))

@Test func savesAndLoadsARoundTrip() async {
    let user = UUID()
    let store = SnapshotStore(userID: user, containerDirectory: tempDirectory())
    await store.save(sample, as: .hunts)
    #expect(await store.load(Fixture.self, as: .hunts) == sample)
}

@Test func aMissingSnapshotIsNilRatherThanAnError() async {
    let store = SnapshotStore(userID: UUID(), containerDirectory: tempDirectory())
    #expect(await store.load(Fixture.self, as: .games) == nil)
}

/// Corruption must degrade to a cache miss. The worst thing persistence is allowed to cause is
/// the spinner the user would have seen anyway.
@Test func aCorruptFileIsAMissNotACrash() async {
    let dir = tempDirectory()
    let user = UUID()
    let store = SnapshotStore(userID: user, containerDirectory: dir)
    await store.save(sample, as: .hunts)
    let file = dir.appendingPathComponent(user.uuidString.lowercased()).appendingPathComponent("hunts.json")
    try? Data("{ this is not json".utf8).write(to: file)
    #expect(await store.load(Fixture.self, as: .hunts) == nil)
}

@Test func aPayloadOfTheWrongShapeIsAMiss() async {
    let store = SnapshotStore(userID: UUID(), containerDirectory: tempDirectory())
    await store.save(["a", "b"], as: .species)
    #expect(await store.load(Fixture.self, as: .species) == nil)
}

/// The reason snapshots are keyed by user id at all: DexModel's UserDefaults store already
/// documents that an unscoped key shows one account another's data after a sign-out/sign-in.
@Test func twoUsersDoNotSeeEachOthersSnapshots() async {
    let dir = tempDirectory()
    let alice = SnapshotStore(userID: UUID(), containerDirectory: dir)
    let bob = SnapshotStore(userID: UUID(), containerDirectory: dir)
    await alice.save(sample, as: .hunts)
    #expect(await bob.load(Fixture.self, as: .hunts) == nil)
    #expect(await alice.load(Fixture.self, as: .hunts) == sample)
}

@Test func clearRemovesOnlyItsOwnUsersSnapshots() async {
    let dir = tempDirectory()
    let alice = SnapshotStore(userID: UUID(), containerDirectory: dir)
    let bob = SnapshotStore(userID: UUID(), containerDirectory: dir)
    await alice.save(sample, as: .hunts)
    await bob.save(sample, as: .hunts)
    await alice.clear()
    #expect(await alice.load(Fixture.self, as: .hunts) == nil)
    #expect(await bob.load(Fixture.self, as: .hunts) == sample)
}

/// One file per run: a single `run` key would be rewritten every time the user switched runs.
@Test func runKeysAreDistinctPerRun() async {
    let store = SnapshotStore(userID: UUID(), containerDirectory: tempDirectory())
    let first = UUID(), second = UUID()
    await store.save(sample, as: .run(first))
    #expect(await store.load(Fixture.self, as: .run(second)) == nil)
    #expect(await store.load(Fixture.self, as: .run(first)) == sample)
}

/// A store with no user id (the DEBUG preview harnesses) must never write into a real user's
/// directory, or a screenshot run would poison a real account's cache.
@Test func anAnonymousStoreIsIsolatedFromEveryUser() async {
    let dir = tempDirectory()
    let user = UUID()
    let real = SnapshotStore(userID: user, containerDirectory: dir)
    let anonymous = SnapshotStore(userID: nil, containerDirectory: dir)
    await anonymous.save(sample, as: .hunts)
    #expect(await real.load(Fixture.self, as: .hunts) == nil)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios && swift test --package-path ShinyTrackerAPI 2>&1 | tail -20`
Expected: compile failure — `cannot find 'SnapshotStore' in scope`.

- [ ] **Step 3: Write the implementation**

Create `SnapshotStore.swift`:

```swift
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

    /// `uuidString.lowercased()` is `[0-9a-f-]` only, so this cannot produce a traversing path.
    public static func run(_ id: UUID) -> SnapshotKey {
        SnapshotKey("run-\(id.uuidString.lowercased())")
    }
}

/// Last-known API payloads on disk, so a cold launch draws something before the network answers.
///
/// **A miss is the only failure mode.** Corrupt file, truncated write, a payload whose shape
/// changed server-side, a version bump — every one returns nil and the caller falls back to the
/// network. Persistence must never produce an error screen or a crash; the worst outcome it is
/// allowed to cause is the spinner the user would have seen anyway. That is why nothing here
/// throws and every failure path is a silent `return`.
public actor SnapshotStore {
    /// Bumping this discards every snapshot rather than migrating. These are caches, not records
    /// — the server is the source of truth and a refetch costs one request.
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios && swift test --package-path ShinyTrackerAPI 2>&1 | grep -E "✘|Test run with"`
Expected: one passing line, 43 tests (35 existing + 8 new), no `✘`.

- [ ] **Step 5: Commit**

```bash
git add ios/ShinyTrackerAPI
git commit -m "feat(ios): a snapshot store for last-known API payloads

Lives in ShinyTrackerAPI rather than the app target for one reason that
outweighs the rest: the package has a test target and the app does not.
Partial writes, cross-account key collisions and silent corruption are
the last things that should ship unverified.

A miss is the only failure mode. Corrupt file, truncated write, changed
server shape, version bump — all return nil and the caller falls back to
the network. The worst outcome persistence is allowed to cause is the
spinner the user would have seen anyway, so nothing here throws.

Writes go to a sibling temp file and are moved into place, so a kill
mid-write leaves the previous snapshot rather than a half-file that
decodes into a plausible-but-wrong screen."
```

---

### Task 2: `HuntClock` in `ShinyTrackerKit`

**Files:**
- Create: `ios/ShinyTrackerKit/Sources/ShinyTrackerKit/HuntClock.swift`
- Create: `ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/HuntClockTests.swift`

**Interfaces:**
- Produces: `struct HuntClock: Codable, Sendable, Equatable` with `totalSeconds`, `lastEncounterAt`, `init(totalSeconds:lastEncounterAt:)`, `mutating func record(at:idleThreshold:)`, `static func idleThreshold(avgTimeSeconds:) -> TimeInterval`.
- Consumes: nothing.

- [ ] **Step 1: Write the failing tests**

Create `HuntClockTests.swift`:

```swift
import Foundation
import Testing

@testable import ShinyTrackerKit

private let t0 = Date(timeIntervalSince1970: 1_760_000_000)

@Test func theFirstEncounterContributesNoTime() {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    #expect(clock.totalSeconds == 0)
    #expect(clock.lastEncounterAt == t0)
}

@Test func aGapUnderTheThresholdAccumulates() {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(7), idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(14), idleThreshold: 600)
    #expect(clock.totalSeconds == 14)
}

/// The whole point of the threshold: a phone put down mid-hunt must not bank the hours it spent
/// in a pocket.
@Test func aGapOverTheThresholdContributesNothingButRestartsTheClock() {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(4000), idleThreshold: 600)
    #expect(clock.totalSeconds == 0)
    clock.record(at: t0.addingTimeInterval(4010), idleThreshold: 600)
    #expect(clock.totalSeconds == 10)
}

/// Clock changes and a stale timestamp must not bank negative time.
@Test func aBackwardsClockContributesNothing() {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(-50), idleThreshold: 600)
    #expect(clock.totalSeconds == 0)
}

/// Per-method rather than fixed: a soft-reset hunt's normal cadence is minutes and a wild
/// encounter's is seconds, so one constant cannot serve both.
@Test func theIdleThresholdScalesWithTheMethodAndClampsAtBothEnds() {
    #expect(HuntClock.idleThreshold(avgTimeSeconds: 30) == 600)      // 30 x 20
    #expect(HuntClock.idleThreshold(avgTimeSeconds: 3) == 120)       // 60 clamped up to 2 min
    #expect(HuntClock.idleThreshold(avgTimeSeconds: 300) == 900)     // 6000 clamped to 15 min
}

/// A custom-method hunt has no method row and therefore no avg_time_seconds.
@Test func theIdleThresholdFallsBackWithoutAMethod() {
    #expect(HuntClock.idleThreshold(avgTimeSeconds: nil) == 600)
    #expect(HuntClock.idleThreshold(avgTimeSeconds: 0) == 600)
}

/// The clock is persisted between launches, so it has to survive a round trip intact.
@Test func theClockRoundTripsThroughCodable() throws {
    var clock = HuntClock()
    clock.record(at: t0, idleThreshold: 600)
    clock.record(at: t0.addingTimeInterval(9), idleThreshold: 600)
    let replayed = try JSONDecoder().decode(
        HuntClock.self, from: JSONEncoder().encode(clock))
    #expect(replayed == clock)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios && swift test --package-path ShinyTrackerKit 2>&1 | tail -20`
Expected: compile failure — `cannot find 'HuntClock' in scope`.

- [ ] **Step 3: Write the implementation**

Create `HuntClock.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios && swift test --package-path ShinyTrackerKit 2>&1 | grep -E "✘|Test run with"`
Expected: one passing line, 13 tests (6 existing + 7 new), no `✘`.

- [ ] **Step 5: Commit**

```bash
git add ios/ShinyTrackerKit
git commit -m "feat(ios): HuntClock, client-side active time for D1

The server cannot derive this. It only sees PATCHes, so a session counted
offline is invisible and the catch-up PATCH afterwards looks like one
enormous gap — which is exactly the case DecideTotalTime's latch exists
to hand over to the client.

Holds timestamps, never a running Timer: iOS suspends the app and a Timer
stops with it, so a foreground recompute is just another record().

The idle threshold is derived per method from avg_time_seconds rather
than fixed, because a soft-reset hunt's normal cadence is minutes and a
wild encounter's is seconds, and one constant cannot serve both."
```

---

### Task 3: The monotonic count guard

**Files:**
- Create: `backend/internal/calc/huntcount.go`
- Create: `backend/internal/calc/huntcount_test.go`
- Modify: `backend/internal/api/hunts.go` (`UpdateHuntHandler`: request struct, the state SELECT, the UPDATE)
- Modify: `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/Models.swift` (`UpdateHuntRequest`)
- Modify: `ios/ShinyTrackerAPI/Tests/ShinyTrackerAPITests/DecodingTests.swift`

**Interfaces:**
- Produces: `calc.DecideEncounterCount(stored, submitted int, allowDecrease bool) int`; `UpdateHuntRequest.allowDecrease: Bool?` encoding as `allow_decrease`.
- Consumes: nothing from Tasks 1-2.

**Why a Go function rather than SQL `GREATEST`:** the same reason `DecideTotalTime` is a function. A `CASE WHEN` inside the UPDATE cannot be unit-tested without a database, and this is the rule protecting the app's "one unforgivable failure". `UpdateHuntHandler` already SELECTs prior state for the time decision, so reading `encounter_count` there costs nothing.

- [ ] **Step 1: Write the failing Go test**

Create `backend/internal/calc/huntcount_test.go`:

```go
package calc

import "testing"

func TestDecideEncounterCount(t *testing.T) {
	cases := []struct {
		name          string
		stored        int
		submitted     int
		allowDecrease bool
		want          int
	}{
		{"a higher count always writes", 100, 250, false, 250},
		{"an equal count writes", 100, 100, false, 100},
		// The rule D1 exists for: a stale or replayed write must never lose counted encounters.
		{"a lower count is refused without permission", 2847, 12, false, 2847},
		{"a lower count is honoured when the user asked", 2847, 2846, true, 2846},
		{"the minus button can reach zero", 1, 0, true, 0},
		{"permission does not raise a lower stored value", 5, 9, true, 9},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := DecideEncounterCount(c.stored, c.submitted, c.allowDecrease); got != c.want {
				t.Errorf("DecideEncounterCount(%d, %d, %v) = %d, want %d",
					c.stored, c.submitted, c.allowDecrease, got, c.want)
			}
		})
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/calc/ -run TestDecideEncounterCount 2>&1 | tail -5`
Expected: `undefined: DecideEncounterCount`

- [ ] **Step 3: Write the implementation**

Create `backend/internal/calc/huntcount.go`:

```go
package calc

// DecideEncounterCount resolves a submitted encounter count against the stored
// one.
//
// D1 (docs/handoff/DECISIONS.md): the count is a monotonic counter. "Never
// overwrite a higher server value with a lower local one without an explicit
// user decision… Losing a long hunt is the one unforgivable failure in this
// app." A sync, a replayed offline burst, or a second device counting the same
// hunt can therefore only ever raise it.
//
// allowDecrease is that explicit decision, and it travels with the request
// because the app has a "−" control and legitimate decrements exist. A bare
// GREATEST would silently break that button; only the minus control sets this,
// never sync and never replay.
func DecideEncounterCount(stored, submitted int, allowDecrease bool) int {
	if allowDecrease {
		return submitted
	}
	if submitted > stored {
		return submitted
	}
	return stored
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd backend && go test ./internal/calc/ 2>&1 | tail -3`
Expected: `ok  	github.com/casper/shinytracker/internal/calc`

- [ ] **Step 5: Wire it into the handler**

In `backend/internal/api/hunts.go`, `UpdateHuntHandler`:

(a) Add the field to the request struct, after `Nickname`:

```go
		// The "−" control's explicit permission to lower the count. Absent means
		// no: a sync or a replayed offline burst can only ever raise it. See
		// calc.DecideEncounterCount.
		AllowDecrease bool `json:"allow_decrease"`
```

(b) The SELECT of prior state currently reads:

```go
		`SELECT updated_at, total_time_seconds, client_owns_time, hunt_parameters FROM user_hunts WHERE id = $1 AND user_id = $2`,
```

Add `encounter_count` to it and scan it into a new `var storedCount int`, alongside the existing scanned variables. Keep the existing column order and append the new column last so the scan targets stay aligned.

(c) Immediately after the existing `calc.DecideTotalTime` call, add:

```go
	newEncounterCount := calc.DecideEncounterCount(storedCount, req.EncounterCount, req.AllowDecrease)
```

(d) In the UPDATE, replace `req.EncounterCount` in the argument list with `newEncounterCount`. The SQL text itself does not change — `SET encounter_count = $1` stays, it is the value bound to `$1` that is now guarded.

- [ ] **Step 6: Add `allowDecrease` to the Swift request**

In `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/Models.swift`, `UpdateHuntRequest`: add the stored property, the initialiser parameter (defaulting to `nil`), and the coding key.

```swift
    /// Explicit permission to lower the count, set only by the "−" control. Omitted everywhere
    /// else, so a sync or a replayed offline burst can only ever raise it — `calc.DecideEncounterCount`.
    public let allowDecrease: Bool?
```

Initialiser gains `allowDecrease: Bool? = nil` (place it last, after `totalTimeSeconds`), and `CodingKeys` gains `case allowDecrease = "allow_decrease"`.

- [ ] **Step 7: Add the Swift encoding test**

Append to `ios/ShinyTrackerAPI/Tests/ShinyTrackerAPITests/DecodingTests.swift`:

```swift
/// Omitted means "no" on the wire, which is what makes the guard safe by default: every caller
/// that is not the "−" button gets monotonic behaviour without opting into it.
@Test func updateHuntBodyOmitsAllowDecreaseUnlessAsked() throws {
    let encoder = JSONEncoder()
    let plain = UpdateHuntRequest(encounterCount: 12, status: .active)
    #expect(!(try #require(String(data: encoder.encode(plain), encoding: .utf8))
        .contains("allow_decrease")))

    let lowering = UpdateHuntRequest(encounterCount: 11, status: .active, allowDecrease: true)
    #expect(try #require(String(data: encoder.encode(lowering), encoding: .utf8))
        .contains("\"allow_decrease\":true"))
}
```

- [ ] **Step 8: Run everything**

```bash
cd backend && go build ./... && go vet ./... && go test ./... 2>&1 | grep -v "no test files"
cd ../ios && swift test --package-path ShinyTrackerAPI 2>&1 | grep -E "✘|Test run with"
```
Expected: Go `ok` for `internal/api`, `internal/calc`, `internal/services`; Swift 44 tests passing.

- [ ] **Step 9: Commit**

```bash
git add backend ios/ShinyTrackerAPI
git commit -m "feat(api): refuse to lower an encounter count unless asked

D1 called the count a monotonic counter and the UPDATE was a plain
SET encounter_count = \$1 — last-write-wins, the one thing D1 says must
never happen: 'losing a long hunt is the one unforgivable failure in
this app.' A replayed offline burst racing a second device did exactly
that.

A bare SQL GREATEST would have silently broken the '−' button, which is
a legitimate decrement. So the intent travels with the request instead:
allow_decrease absent means the count can only rise, and only the minus
control ever sets it — never sync, never replay.

The decision is a Go function rather than a CASE WHEN for the same
reason DecideTotalTime is: a rule this load-bearing needs a test, and
SQL inside a handler cannot have one."
```

---

### Task 4: Render from disk on a cold launch

**Files:**
- Modify: `ios/App/ShinyTrackerApp.swift` (`AppShell` builds one `SnapshotStore` and passes it to every model)
- Modify: `ios/App/Hunt/HuntListModel.swift`, `ios/App/Dex/DexModel.swift`, `ios/App/Nuzlocke/NuzlockeModel.swift`, `ios/App/Hunt/GamesTab.swift`

**Interfaces:**
- Consumes: `SnapshotStore`, `SnapshotKey` from Task 1.
- Produces: nothing later tasks depend on.

**No test target here.** Verify by build and the preview harnesses. State plainly what you did and did not exercise.

- [ ] **Step 1: Give every model a store**

Each model's `init` gains `store: SnapshotStore`. `AppShell` builds exactly one — `SnapshotStore(userID: auth.userID)` in the session initialiser and `SnapshotStore(userID: nil)` in the `#if DEBUG` preview initialiser — and passes the same instance to all four. One store, four keys.

- [ ] **Step 2: Read the snapshot before the network, in each model's cold path**

The shape, using `HuntListModel` as the worked example. Inside `load(quiet:)`, before the `do` block:

```swift
        // Draw last-known data immediately rather than a spinner. The refresh below always runs,
        // so this is never shown without being corrected in the same breath — the trade is that a
        // cold launch briefly shows stale data, which is what "opens instantly" costs.
        if !quiet, state != .ready, let cached: [HuntDetail] = await store.load([HuntDetail].self, as: .hunts) {
            rows = cached.filter { $0.status == "active" }.map { HuntRow(detail: $0, count: $0.encounterCount) }
            history = cached.filter { $0.status == "completed" }.map { HuntRow(detail: $0, count: $0.encounterCount) }
            state = .ready
        }
```

Apply that same guard-and-populate shape to the other three. Exactly what each must restore:

| Model | Key(s) | Populates | Then sets |
|---|---|---|---|
| `DexModel` | `.species` → `[Pokemon]`, `.dex` → `DexStatus` | `sections = Self.group(species)`; `notInYourGames`/`lockedEverywhere` from the status | `state = .ready` |
| `GameLibraryModel` | `.games` → `[Game]` | `games` (already generation-sorted when saved) | `state = .ready` |
| `NuzlockeModel` | `.runs` → `[NuzlockeRun]`, then `.run(id)` for the run it selects | `runs`; then `timeline`/`encounters`/`beaten` from the detail, **followed by `rebuild()`** | `state = .ready` |

`NuzlockeModel` is the one with a trap: its derived state (`logsBySlug`, `currentSlug`, `coverage`) is built by `rebuild()`, so restoring a snapshot without calling it renders a run with an empty timeline and no coverage warning. `open(_:)` already ends in `rebuild()` — reuse that path rather than assigning the three stores directly.

`DexModel` does not restore `availableInGame`: it is derived per selected game by `loadAvailability()` and is cheap to refetch. `GameLibraryModel` does not restore `owned`, which needs a user id it resolves at load time.

- [ ] **Step 3: Save after every successful load**

At the end of each model's successful `do` block, save what it just fetched, keyed as above. Save the raw API payload, not the derived view state — the derived state is rebuilt on load and would otherwise be a second thing to keep in sync.

- [ ] **Step 4: Failures with a snapshot showing report inline**

In each model's `catch`, if `state == .ready` (a snapshot is on screen), report through `syncError` rather than `state = .failed`. Cached data plus a quiet warning beats an error page. The four models all already have a `syncError` property and render it.

- [ ] **Step 5: Do NOT wire sign-out — there is nothing to wire**

`AuthSession.signOut()` exists (`ShinyTrackerAuth/Sources/ShinyTrackerAuth/AuthSession.swift:98`) but **has no caller anywhere in the app** — there is no sign-out control. Do not invent one, and do not hook `clear()` to `markSessionExpired()`: expiry is a token blip, not a sign-out, and wiping the cache there would blank every screen on a routine refresh failure.

`SnapshotStore.clear()` therefore ships unused in this slice. That is deliberate and safe: snapshots are keyed by user id, so a second account never reads the first one's files — which is exactly why the keying exists. Note in your report that wiring `clear()` belongs with whatever change adds a sign-out control.

- [ ] **Step 6: Build and verify**

```bash
cd ios && xcodegen generate && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker \
  -destination 'platform=iOS Simulator,id=5E394296-95FD-4790-8862-3D6B6BC503C2' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`

Then confirm the preview harnesses still render, since they now construct an anonymous store:

```bash
SIM=5E394296-95FD-4790-8862-3D6B6BC503C2
xcrun simctl launch $SIM com.casperkarlsen.shinytracker -nuzlockePreview seeded
xcrun simctl io $SIM screenshot /tmp/task4-nuzlocke.png
xcrun simctl terminate $SIM com.casperkarlsen.shinytracker
xcrun simctl launch $SIM com.casperkarlsen.shinytracker -dexPreview seeded
xcrun simctl io $SIM screenshot /tmp/task4-dex.png
```
Expected: both render as before. A harness writing into a real user's cache would be a defect — the anonymous store exists to prevent it.

- [ ] **Step 7: Commit**

```bash
git add ios/App
git commit -m "feat(ios): draw last-known data on a cold launch

Every model now reads its snapshot before the network and renders it
immediately, then refreshes. A failed refresh with a snapshot on screen
reports inline instead of replacing readable data with an error page.

The trade is explicit: a cold launch briefly shows stale data. That is
what 'opens instantly' costs, and the refresh always runs in the same
breath, so it is never shown without being corrected.

The preview harnesses get an anonymous store — a screenshot run must not
be able to poison a real account's cache."
```

---

### Task 5: Send client-owned time, and let only the minus button lower the count

**Files:**
- Modify: `ios/App/Hunt/HuntListModel.swift` (`bump`, `flush`, `markFound`, plus the new stored properties)
- Modify: `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/SnapshotStore.swift` (add the `.clocks` key)

**Interfaces:**
- Consumes: `HuntClock` (Task 2), `UpdateHuntRequest.allowDecrease` (Task 3), `SnapshotStore` (Task 1).

- [ ] **Step 1: Hold a clock per hunt and persist it**

Add to `HuntListModel`: `private var clocks: [UUID: HuntClock]`, loaded from the store on first load and saved whenever it changes.

This needs a new key. `SnapshotKey` is a **struct with static members**, not an enum — add one beside the others:

```swift
    /// Per-hunt client-owned elapsed time (`HuntClock`). Persisted so time survives a relaunch;
    /// the server only learns it on the next flush.
    public static let clocks = SnapshotKey("clocks")
```

`[UUID: HuntClock]` is `Codable`, but note that `JSONEncoder` encodes a dictionary with non-`String` keys as a **flat array** of alternating keys and values. That round-trips correctly through `JSONDecoder`, so it works — it just does not look like an object on disk. Do not "fix" it by stringifying the keys.

Seed a hunt's clock from the server's `totalTimeSeconds` the first time it is seen, so a hunt that was being timed server-side does not restart from zero when this client takes over.

- [ ] **Step 2: Record an encounter in `bump`**

In `bump(_:by:)`, after the count changes and before `scheduleSync`:

```swift
        // D1: the client owns elapsed time. The threshold comes from the method's own cadence —
        // avg_time_seconds is already on HuntDetail, so this needs no request.
        let threshold = HuntClock.idleThreshold(avgTimeSeconds: rows[index].detail.avgTimeSeconds)
        clocks[id, default: HuntClock(totalSeconds: rows[index].detail.totalTimeSeconds)]
            .record(at: Date(), idleThreshold: threshold)
```

- [ ] **Step 3: Remember that the user lowered the count**

Add `private var loweredByUser: Set<UUID>`. In `bump`, `if delta < 0 { loweredByUser.insert(id) }`. This is the explicit decision `allow_decrease` carries — `HuntCard.swift:174` (`model.bump(row.id, by: -1)`) is the only caller that can produce a negative delta.

- [ ] **Step 4: Send both in `flush`**

Replace the `updateHunt` call. Its current comment says `totalTimeSeconds` is deliberately omitted because there is no client timer — that is no longer true and the comment must go, replaced by one explaining the latch:

```swift
            // Supplying total_time_seconds latches this hunt client-authoritative for good
            // (calc.DecideTotalTime). That is correct now that HuntClock actually tracks it: the
            // server cannot see an offline session, and deriving from PATCH gaps would credit it
            // zero.
            _ = try await client.updateHunt(
                huntID: id,
                UpdateHuntRequest(
                    encounterCount: row.count,
                    status: .active,
                    totalTimeSeconds: clocks[id]?.totalSeconds,
                    allowDecrease: loweredByUser.contains(id) ? true : nil
                )
            )
            loweredByUser.remove(id)
```

Clear `loweredByUser` on a failed flush too — the count is rolled back there, so the permission no longer applies.

- [ ] **Step 5: Do the same in `markFound`**

`markFound` sends its own `UpdateHuntRequest` with the same omitted-time comment. Give it `totalTimeSeconds: clocks[id]?.totalSeconds` so a completed hunt records the time it actually took. It never lowers a count, so it does not send `allowDecrease`.

- [ ] **Step 6: Recompute on foreground**

`HuntClock` computes from stored dates, so nothing accumulates while suspended and no work is needed on resume — but a hunt whose clock was seeded before the app was suspended must not bank the suspended interval. Confirm by reading `record`'s guard that this is already true (a long gap is discarded), and say so in your report rather than adding a scene-phase observer that does nothing.

- [ ] **Step 7: Build and verify**

```bash
cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker \
  -destination 'platform=iOS Simulator,id=5E394296-95FD-4790-8862-3D6B6BC503C2' build 2>&1 | tail -3
SIM=5E394296-95FD-4790-8862-3D6B6BC503C2
xcrun simctl launch $SIM com.casperkarlsen.shinytracker -huntPreview hunts
xcrun simctl io $SIM screenshot /tmp/task5-hunts.png
```
Expected: `** BUILD SUCCEEDED **`, and the Hunt list renders with its cards.

You cannot tap `+`/`−` in the simulator, so the clock and the `allow_decrease` path are code-verified only. Say that plainly.

- [ ] **Step 8: Commit**

```bash
git add ios/App ios/ShinyTrackerAPI
git commit -m "feat(ios): the client now owns hunt time, and guards the count

HuntListModel accumulates a HuntClock per hunt and sends
total_time_seconds, which latches the hunt client-authoritative
(calc.DecideTotalTime). The flush comment saying it must not claim
authority it does not have is gone — it now does.

allow_decrease is set only when the user pressed '−'. Every other write,
including whatever the sync layer becomes, can therefore only raise the
count."
```

---

## Verification of the whole slice

1. Packages: `swift test` for all four, plus `go test ./...` — the new units carry real tests, which is the point of where they live.
2. Cold launch on device, judged by the user: force-quit and reopen. The Hunt list, Dex grid and Nuzlocke run should draw immediately with last-known data rather than a spinner.
3. Airplane mode on device, judged by the user: the app should open and be readable. Writes will still fail — that is sub-project B.

## Known gaps

- **Nothing queues.** A write with no connection fails as it does today.
- **Task 4 and 5's wiring has no mechanical test**, being app-target code. Recorded in the spec.
- **`allow_decrease` is a new API field the web frontend does not send** — which is correct and intentional: it means the web client also gets monotonic behaviour for free, and its own decrement control (if it has one) would need the same field before it can lower a count. Flag it if the web app turns out to have one.
