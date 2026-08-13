# Offline Write Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Counting and completing a hunt work with no signal, and reach the server when one returns.

**Architecture:** Two fully testable units first (the queue's rules in `ShinyTrackerKit`, the delta+dedupe path in Go), then the API surface, then the app wiring that consumes them. The count becomes a **delta** with a client-generated idempotency key; time stays absolute and `max`-merged, which is idempotent already.

**Tech Stack:** Swift 6, SwiftUI, local SPM packages, Go + pgx + Postgres, XcodeGen.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-13-offline-write-queue-design.md`.
- **Tasks 1-3 have test targets and MUST be test-driven** — failing test first. This is why those units live where they do; sub-project A's five fix passes all landed on untestable app-target code.
- **Tasks 4-5 touch the app target, which has NO test target. Do not add one.** Verify by build plus the DEBUG preview harnesses through `simctl`.
- **No agent in this environment can drive simulator gestures or toggle airplane mode** — no `idb`, no `cliclick`, no touch injection. State plainly what you verified versus reasoned about. Never imply you tapped, scrolled, or went offline.
- Do NOT touch Nuzlocke, dex or charm write paths (sub-project C).
- Do NOT remove `allow_decrease`, `serverBacked`, or `HuntCountPolicy`. They guard the absolute path, which the web client still uses. Retiring them is a later, separate change.
- Comment idiom: explain *why*, not *what*.
- Swift commands from `ios/`; Go commands from `backend/`.
- Simulator UDID `5E394296-95FD-4790-8862-3D6B6BC503C2`, bundle id `com.casperkarlsen.shinytracker`.

---

### Task 1: `PendingWrite` and `WriteQueue` in `ShinyTrackerKit`

**Files:**
- Create: `ios/ShinyTrackerKit/Sources/ShinyTrackerKit/WriteQueue.swift`
- Create: `ios/ShinyTrackerKit/Tests/ShinyTrackerKitTests/WriteQueueTests.swift`

**Interfaces:**
- Produces: `struct PendingWrite` (`id`, `huntID`, `kind`, `attempted`, `failures`) with `enum Kind { case count(delta: Int); case found }`; `struct WriteQueue: Codable, Equatable` with:

```swift
public init()
public private(set) var entries: [PendingWrite]
public var next: PendingWrite? { entries.first }
public mutating func enqueue(_ kind: PendingWrite.Kind, for huntID: UUID)
public mutating func markAttempted(_ id: UUID)
public mutating func markFailed(_ id: UUID)
public mutating func remove(_ id: UUID)
```
- Consumes: nothing.

**The rule that is easy to get wrong, and the reason this task is test-driven:** an entry that has been **attempted** must never be merged into again, and must never be removed by coalescing. A request can apply server-side while its response is lost, so once an id has been sent the server may already hold it — merging `+5` into that id would have the dedupe table swallow the five silently. After an attempt, new counts start a fresh entry with a fresh id.

- [ ] **Step 1: Write the failing tests**

Create `WriteQueueTests.swift`:

```swift
import Foundation
import Testing

@testable import ShinyTrackerKit

private let huntA = UUID()
private let huntB = UUID()

/// Five hundred taps must become one request, not five hundred.
@Test func consecutiveCountsForOneHuntMerge() {
    var queue = WriteQueue()
    for _ in 0..<500 { queue.enqueue(.count(delta: 1), for: huntA) }
    #expect(queue.entries.count == 1)
    #expect(queue.entries[0].kind == .count(delta: 500))
}

@Test func upsAndDownsMergeToTheirNet() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 5), for: huntA)
    queue.enqueue(.count(delta: -2), for: huntA)
    #expect(queue.entries[0].kind == .count(delta: 3))
}

/// A net-zero delta is not a write. Sending it would burn an idempotency key to do nothing.
@Test func aNetZeroDeltaDisappears() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 3), for: huntA)
    queue.enqueue(.count(delta: -3), for: huntA)
    #expect(queue.entries.isEmpty)
}

/// THE subtle rule. An attempted entry may already be applied server-side with its response lost,
/// so merging into it would have the dedupe table swallow the new work.
@Test func anAttemptedEntryIsFrozenAndNeverMergedInto() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 10), for: huntA)
    let first = try! #require(queue.next)
    queue.markAttempted(first.id)

    queue.enqueue(.count(delta: 5), for: huntA)
    #expect(queue.entries.count == 2)
    #expect(queue.entries[0].kind == .count(delta: 10))
    #expect(queue.entries[1].kind == .count(delta: 5))
    #expect(queue.entries[1].id != first.id)
}

/// Same rule from the other direction: an attempted entry must not be collapsed away either.
@Test func anAttemptedEntryIsNotRemovedByANetZero() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 3), for: huntA)
    let first = try! #require(queue.next)
    queue.markAttempted(first.id)
    queue.enqueue(.count(delta: -3), for: huntA)
    #expect(queue.entries.count == 2)
}

/// A completion is a barrier: the hunt would otherwise complete at the wrong number.
@Test func aFoundBlocksMergingAcrossIt() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 4), for: huntA)
    queue.enqueue(.found, for: huntA)
    queue.enqueue(.count(delta: 2), for: huntA)
    #expect(queue.entries.count == 3)
    #expect(queue.entries[0].kind == .count(delta: 4))
    #expect(queue.entries[1].kind == .found)
    #expect(queue.entries[2].kind == .count(delta: 2))
}

/// Counts enqueued before a completion must go out before it.
@Test func countsBeforeAFoundDrainFirst() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 4), for: huntA)
    queue.enqueue(.found, for: huntA)
    #expect(queue.next?.kind == .count(delta: 4))
}

/// Two hunts counted alternately must not merge into each other, and each must keep its own order.
@Test func interleavedHuntsKeepPerHuntOrder() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 1), for: huntA)
    queue.enqueue(.count(delta: 1), for: huntB)
    queue.enqueue(.count(delta: 1), for: huntA)
    #expect(queue.entries.count == 3)
    #expect(queue.entries.map(\.huntID) == [huntA, huntB, huntA])
}

/// Draining removes the front, so the next drain sees the next entry.
@Test func removingTheFrontAdvancesTheQueue() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 1), for: huntA)
    queue.enqueue(.found, for: huntA)
    let first = try! #require(queue.next)
    queue.remove(first.id)
    #expect(queue.next?.kind == .found)
}

/// Failures accumulate so a write that can never succeed stops being retried forever.
@Test func failuresAccumulatePerEntry() {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 1), for: huntA)
    let first = try! #require(queue.next)
    queue.markFailed(first.id)
    queue.markFailed(first.id)
    #expect(queue.entries[0].failures == 2)
}

/// The queue is persisted between launches, so it has to survive a round trip intact — including
/// the attempted flag, or a resumed launch would merge into an already-sent entry.
@Test func theQueueRoundTripsThroughCodable() throws {
    var queue = WriteQueue()
    queue.enqueue(.count(delta: 7), for: huntA)
    let first = try #require(queue.next)
    queue.markAttempted(first.id)
    queue.enqueue(.found, for: huntB)
    let replayed = try JSONDecoder().decode(WriteQueue.self, from: JSONEncoder().encode(queue))
    #expect(replayed == queue)
    #expect(replayed.entries[0].attempted)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ios && swift test --package-path ShinyTrackerKit 2>&1 | tail -20`
Expected: compile failure — `cannot find 'WriteQueue' in scope`.

- [ ] **Step 3: Write the implementation**

**Deliberately not handed to you as code, unlike the earlier plans in this project.** In
sub-project A every plan-supplied implementation was transcribed faithfully and the *plan's* code
carried the bugs — two in the clock's arithmetic alone, both found only because that unit had
tests. Here the eleven tests above are the specification, and they cover the subtle rule from both
directions. Write it to satisfy them.

Create `WriteQueue.swift`. The rules, stated precisely so you implement intent rather than
test-shapes:

- `enqueue(_ kind:for:)` appends, except that a `.count` merges into the **last** entry when that entry is for the same hunt, is also a `.count`, and is **not attempted**. Merging sums the deltas and keeps the existing entry's `id`.
- A merge producing `delta == 0` removes that entry, again only when unattempted.
- `.found` never merges and nothing merges across it, because it is a different `Kind` — the "last entry is a `.count`" condition already gives you this; do not add a special case, and say so in a comment so nobody adds one later.
- `next` is `entries.first`.
- `markAttempted`, `markFailed`, `remove` address entries by `id`, never by index — a drain awaits between reads and the array can change underneath.
- `PendingWrite.id` is the idempotency key. It is generated once at enqueue and **never regenerated**, including across a merge.

Document on the type why `attempted` exists, in the codebase's why-not-what idiom: a request can apply server-side while its response is lost, so a sent id may already be held by the server, and merging into it would have the dedupe swallow the new work.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ios && swift test --package-path ShinyTrackerKit 2>&1 | grep -E "✘|Test run with"`
Expected: one passing line, 42 tests (31 existing + 11 new), no `✘`.

- [ ] **Step 5: Commit**

```bash
git add ios/ShinyTrackerKit
git commit -m "feat(ios): a durable queue of pending hunt writes

The rules that decide what gets sent live where they can be executed.
Sub-project A's five fix passes all landed on app-target code with no
test target, and every claim about them was derived by reading.

The rule worth the test suite: an attempted entry is frozen. A request
can apply server-side while its response is lost, so once an id has been
sent the server may already hold it — merging into that id would have the
dedupe table swallow the new work silently. After an attempt, new counts
start a fresh entry with a fresh id."
```

---

### Task 2: The delta path and its dedupe, in Go

**Files:**
- Create: `backend/migrations/019_add_hunt_writes.sql`
- Create: `backend/internal/calc/huntdelta.go`
- Create: `backend/internal/calc/huntdelta_test.go`
- Modify: `backend/internal/api/hunts.go` (`UpdateHuntHandler`)
- Modify: `backend/schema.sql`

**Interfaces:**
- Produces: `calc.ApplyEncounterDelta(stored, delta int) int`; `hunt_writes` table; `encounter_delta` and `write_id` accepted by `PATCH /api/hunts/{id}`.
- Consumes: nothing from Task 1.

**Why a `calc` function for something this small:** the same reason `DecideTotalTime` and `DecideEncounterCount` are functions — it is a rule about the count, and rules about the count get tests. It also gives the clamp a home: a delta must never drive the stored count below zero.

- [ ] **Step 1: Write the failing Go test**

Create `backend/internal/calc/huntdelta_test.go`:

```go
package calc

import "testing"

func TestApplyEncounterDelta(t *testing.T) {
	cases := []struct {
		name   string
		stored int
		delta  int
		want   int
	}{
		{"an increment adds", 2847, 500, 3347},
		{"a decrement subtracts", 2847, -1, 2846},
		{"a zero delta is a no-op", 2847, 0, 2847},
		// A delta is relative, so it cannot be stale — but it can still be wrong, and the
		// column has no CHECK. Clamping here keeps a bad client from writing nonsense.
		{"the count never goes below zero", 3, -10, 0},
		{"a decrement to exactly zero is allowed", 3, -3, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := ApplyEncounterDelta(c.stored, c.delta); got != c.want {
				t.Errorf("ApplyEncounterDelta(%d, %d) = %d, want %d", c.stored, c.delta, got, c.want)
			}
		})
	}
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd backend && go test ./internal/calc/ -run TestApplyEncounterDelta 2>&1 | tail -5`
Expected: `undefined: ApplyEncounterDelta`

- [ ] **Step 3: Write the implementation**

Create `backend/internal/calc/huntdelta.go`:

```go
package calc

// ApplyEncounterDelta moves a stored encounter count by a relative amount.
//
// Deltas exist because an offline client cannot know the current count. An
// absolute write from a stale client overwrites whatever the server holds,
// which is the failure D1 calls unforgivable and which the iOS client spent
// five fix passes defending against; a relative one cannot, whatever the
// client believes.
//
// The clamp is the one guard a delta still needs: relative writes cannot be
// stale, but they can be wrong, and encounter_count has no CHECK constraint.
func ApplyEncounterDelta(stored, delta int) int {
	next := stored + delta
	if next < 0 {
		return 0
	}
	return next
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd backend && go test ./internal/calc/ 2>&1 | tail -3`
Expected: `ok  	github.com/casper/shinytracker/internal/calc`

- [ ] **Step 5: Write the migration**

Create `backend/migrations/019_add_hunt_writes.sql`:

```sql
-- 019_add_hunt_writes.sql
--
-- Idempotency keys for relative encounter-count writes.
--
-- A delta is the only write model in which two offline sessions on one hunt
-- both survive (D1 names phone + Apple Watch as planned), but it is not
-- naturally idempotent: an offline queue retries by definition, and a "+500"
-- that lands twice invents 500 encounters. The client generates a UUID per
-- write and the server records the ones it has applied.
--
-- Written in the SAME transaction as the count update. Two transactions leave
-- a window where a crash between them either double-applies the delta or
-- loses it.
--
-- Purely additive: no existing column or row changes, and the absolute-count
-- path is untouched.

CREATE TABLE IF NOT EXISTS hunt_writes (
    write_id   UUID PRIMARY KEY,
    user_id    UUID NOT NULL,
    -- CASCADE, unlike the reference-data tables: these rows are meaningless
    -- once the hunt is gone, and a replayed write for a deleted hunt should
    -- fail on the hunt's own absence rather than dedupe against a ghost.
    hunt_id    UUID NOT NULL REFERENCES user_hunts(id) ON DELETE CASCADE,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_hunt_writes_hunt ON hunt_writes (hunt_id);

ALTER TABLE hunt_writes ENABLE ROW LEVEL SECURITY;
```

Apply it against the live database, then mirror the DDL into `backend/schema.sql` beside the other hunt tables, comments included.

- [ ] **Step 6: Wire the handler**

In `UpdateHuntHandler` (`backend/internal/api/hunts.go`):

(a) Add to the request struct, after `AllowDecrease`:

```go
		// A relative count change. When present, encounter_count is ignored and
		// the count moves by this amount instead — see calc.ApplyEncounterDelta.
		EncounterDelta *int `json:"encounter_delta"`
		// The idempotency key for that delta. Required with it, meaningless
		// without it: a retried delta that already landed must not apply twice.
		WriteID *string `json:"write_id"`
```

(b) Validate: `EncounterDelta` present without a non-empty `WriteID` is a 400 (`"write_id is required with encounter_delta"`). `WriteID` without `EncounterDelta` is ignored.

(c) When `EncounterDelta` is present, the count decision and the dedupe happen together, in one transaction, replacing the `calc.DecideEncounterCount` call for that branch only:

- `BEGIN`
- `INSERT INTO hunt_writes (write_id, user_id, hunt_id) VALUES ($1,$2,$3) ON CONFLICT (write_id) DO NOTHING`
- If it inserted **0** rows, this is a replay: skip the count change entirely, keep the count as stored, and continue with the rest of the update (status, time, nickname) as normal.
- Otherwise the new count is `calc.ApplyEncounterDelta(storedCount, *req.EncounterDelta)`.
- `COMMIT`

Use `pgx`'s transaction API and make sure every early return inside the transaction rolls back. The absolute path (no `encounter_delta`) must keep running `calc.DecideEncounterCount` exactly as it does now.

Leave a comment at the branch explaining why replay skips only the count and still applies status/time: time is `max`-merged and idempotent already, and a replayed completion must still be able to complete a hunt whose first attempt's response was lost.

- [ ] **Step 7: Verify**

```bash
cd backend && go build ./... && go vet ./... && go test ./... 2>&1 | grep -v "no test files"
```
Expected: `ok` for `internal/api`, `internal/calc`, `internal/services`.

- [ ] **Step 8: Commit**

```bash
git add backend
git commit -m "feat(api): relative encounter writes with idempotency keys

A delta cannot be corrupted by a stale client, which is the whole failure
class the absolute path needed a defensive perimeter for, and it is the
only model in which two offline sessions on one hunt both survive.

What it costs is idempotency: a retried +500 that already landed invents
500 encounters, and an offline queue retries by definition. So the client
generates a write id and the server records applied ids in the SAME
transaction as the update — two transactions leave a window where a crash
either double-applies or loses the write.

A replay skips only the count. Time is max-merged and idempotent already,
and a replayed completion must still be able to complete a hunt whose
first response was lost.

The absolute path is untouched: the web client still uses it, and
DecideEncounterCount still guards it."
```

---

### Task 3: The API client's delta fields

**Files:**
- Modify: `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/Models.swift` (`UpdateHuntRequest`)
- Modify: `ios/ShinyTrackerAPI/Tests/ShinyTrackerAPITests/DecodingTests.swift`

**Interfaces:**
- Produces: `UpdateHuntRequest.encounterDelta: Int?` and `.writeID: UUID?`, encoding as `encounter_delta` / `write_id`.
- Consumes: Task 2's field names.

- [ ] **Step 1: Write the failing test**

Append to `DecodingTests.swift`:

```swift
/// A delta write must carry its idempotency key and must NOT carry an absolute count — the
/// server ignores `encounter_count` when a delta is present, and sending a stale one anyway
/// would be a lie in the payload.
@Test func deltaWriteCarriesItsKeyAndOmitsTheAbsoluteCount() throws {
    let key = UUID()
    let body = UpdateHuntRequest(
        status: .active, encounterDelta: 500, writeID: key, totalTimeSeconds: 4200)
    let json = try #require(String(data: JSONEncoder().encode(body), encoding: .utf8))
    #expect(json.contains("\"encounter_delta\":500"))
    #expect(json.contains("\"write_id\":\"\(key.uuidString.lowercased())\""))
    #expect(!json.contains("encounter_count"))
    #expect(json.contains("\"total_time_seconds\":4200"))
}

/// The absolute path is unchanged, and a delta write never leaks into it.
@Test func absoluteWriteStillOmitsTheDeltaFields() throws {
    let body = UpdateHuntRequest(encounterCount: 12, status: .active)
    let json = try #require(String(data: JSONEncoder().encode(body), encoding: .utf8))
    #expect(json.contains("\"encounter_count\":12"))
    #expect(!json.contains("encounter_delta"))
    #expect(!json.contains("write_id"))
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd ios && swift test --package-path ShinyTrackerAPI 2>&1 | tail -20`
Expected: a compile error — there is no initialiser taking `encounterDelta`.

- [ ] **Step 3: Implement**

`UpdateHuntRequest` currently requires `encounterCount: Int`. Make it `Int?` and add `encounterDelta: Int?` and `writeID: UUID?`, with `CodingKeys` entries `encounter_delta` and `write_id`. Give the type **two initialisers** rather than one with everything optional, so a caller cannot express "both" or "neither":

```swift
    /// The absolute path, still used by the web client's shape and by any caller that knows the
    /// true count. Guarded server-side by `calc.DecideEncounterCount`.
    public init(encounterCount: Int, status: HuntStatus, huntParameters: [String: ParamValue]? = nil,
                totalTimeSeconds: Int? = nil, allowDecrease: Bool? = nil)

    /// The relative path, for queued writes. `writeID` is the idempotency key: a retried delta
    /// that already landed must not apply twice.
    public init(status: HuntStatus, encounterDelta: Int, writeID: UUID,
                huntParameters: [String: ParamValue]? = nil, totalTimeSeconds: Int? = nil)
```

`writeID` encodes as a lowercased uuid string, matching how `APIClient.id(_:)` already lowercases path uuids for the Supabase `sub` comparison.

Every existing call site passes `encounterCount:` first, so the absolute initialiser keeps them compiling unchanged.

- [ ] **Step 4: Run the tests**

Run: `cd ios && swift test --package-path ShinyTrackerAPI 2>&1 | grep -E "✘|Test run with"`
Expected: 48 tests (46 existing + 2 new), no `✘`.

- [ ] **Step 5: Commit**

```bash
git add ios/ShinyTrackerAPI
git commit -m "feat(ios): delta and idempotency-key fields on the hunt PATCH

Two initialisers rather than one with everything optional: a caller
cannot express 'both an absolute count and a delta' or 'neither', which
are the two states the server would have to reject at runtime."
```

---

### Task 4: Enqueue instead of writing, and drain on foreground

**Files:**
- Modify: `ios/App/Hunt/HuntListModel.swift` (`bump`, `scheduleSync`, `flush`, `markFound`, plus queue state)
- Modify: `ios/ShinyTrackerAPI/Sources/ShinyTrackerAPI/SnapshotStore.swift` (add the `.pendingWrites` key)
- Modify: `ios/App/ShinyTrackerApp.swift` (drain on foreground)

**Interfaces:**
- Consumes: `WriteQueue`/`PendingWrite` (Task 1), `UpdateHuntRequest`'s delta initialiser (Task 3), `SnapshotStore` (sub-project A).

**No test target here.** Verify by build and the preview harnesses; the queue's own rules are already covered by Task 1.

- [ ] **Step 1: Add the store key**

In `SnapshotStore.swift`, beside the existing statics:

```swift
    /// Hunt writes made but not yet accepted by the server. Durable because its whole purpose is
    /// surviving the app being killed between counting and connectivity returning.
    public static let pendingWrites = SnapshotKey("pending-writes")
```

- [ ] **Step 2: Enqueue on `bump` rather than debouncing a PATCH**

`bump` currently updates the row and calls `scheduleSync`, which debounces a `flush` that PATCHes an absolute count. Replace that mechanism for counting:

- `bump` still updates `rows[index].count` optimistically and records the clock exactly as it does now.
- Instead of `scheduleSync`, it calls `queue.enqueue(.count(delta: delta), for: id)` and persists the queue.
- The 400 ms debounce is no longer needed for coalescing — `WriteQueue.enqueue` merges — but a drain should not run on every tap. Drain on a short debounce (keep the existing 400 ms timer, now driving `drain()` rather than `flush`).

Delete the now-unreachable absolute-count `flush` path for counting **only if** nothing else calls it; `markFound` uses its own request. Say in your report which of `preBurstCount`/`preBurstClock`/`loweredByUser`/`serverBacked` are still reachable afterwards — several exist purely to defend the absolute path and may now be dead. **Do not delete any of them in this task**; report them.

- [ ] **Step 3: Enqueue on `markFound`**

`markFound` enqueues `.found` and returns `true` immediately — the hunt moves to History optimistically, because the user watching a shiny appear must not be told to wait for a network round trip. The drain sends the completion when it can.

- [ ] **Step 4: Write `drain()`**

On `HuntListModel`:

```swift
    /// Sends queued writes in order, stopping at the first that cannot be sent — order matters
    /// (a completion must follow the counts it completes), so a failure must not let later
    /// entries overtake it.
    func drain() async
```

Per entry: `markAttempted` and persist **before** sending (a crash mid-request must not leave an entry that looks unsent, or it would be merged into and the server would dedupe the merge away). Then:

- **2xx** → `remove(id)`, persist, and reconcile the row's count with the response using `HuntCountPolicy.reconciled`.
- **401 twice / transport / 5xx** → `markFailed(id)`, persist, stop the drain.
- **4xx that cannot succeed, or `failures` past the limit (use 5)** → remove it and surface a message naming the hunt. Never drop silently.

- [ ] **Step 5: Drain on foreground and after a successful load**

Add a `.onChange(of: scenePhase)` in `ShinyTrackerApp` (or `AppShell`) that calls `drain()` when the phase becomes `.active`, and call it at the end of a successful `load`. Do not add a timer or a network-reachability observer — a failed drain simply waits for the next foreground.

- [ ] **Step 6: Build and verify**

```bash
cd ios && xcodegen generate && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker \
  -destination 'platform=iOS Simulator,id=5E394296-95FD-4790-8862-3D6B6BC503C2' build 2>&1 | tail -3
SIM=5E394296-95FD-4790-8862-3D6B6BC503C2
xcrun simctl launch $SIM com.casperkarlsen.shinytracker -huntPreview hunts
xcrun simctl io $SIM screenshot /tmp/task4-hunts.png
```
Expected: `** BUILD SUCCEEDED **` and the Hunt list rendering.

You cannot tap `+`, cannot go offline, and cannot observe a drain. Say so plainly; the queue's behaviour here is code-reasoned, and the user exercises it on device.

- [ ] **Step 7: Commit**

```bash
git add ios/App ios/ShinyTrackerAPI
git commit -m "feat(ios): count into a durable queue instead of straight to the server

Counting and completing no longer require a connection. A tap updates the
row and appends to a queue that survives the app being killed; a drain on
foreground sends it in order, stopping at the first entry it cannot send
so a completion never overtakes the counts it completes.

An entry is marked attempted and persisted BEFORE the request goes out. A
crash mid-request must not leave it looking unsent, or the next tap would
merge into an id the server may already hold and the dedupe would swallow
the merge."
```

---

### Task 5: Show pending work, and speak plainly when it cannot land

**Files:**
- Modify: `ios/App/Hunt/HuntCard.swift` (pending marker)
- Modify: `ios/App/Hunt/HuntScreen.swift` (failed-write message)
- Modify: `ios/App/Hunt/HuntListModel.swift` (expose what is pending and what failed)

**Interfaces:**
- Consumes: Task 4's queue state.

- [ ] **Step 1: Expose the two facts the UI needs**

On `HuntListModel`: `func hasPendingWrites(_ id: UUID) -> Bool` and `private(set) var failedWrites: [String]` (user-facing sentences, already naming the hunt).

- [ ] **Step 2: The pending marker**

In `HuntCard`, a quiet indicator when that hunt has queued work — same visual weight as the existing timer badge, using `Palette.textMuted`, not an alert colour. Queued work is normal, not a problem. Do **not** disable the counter buttons or show a spinner: counting must feel identical offline, which is the entire point.

- [ ] **Step 3: Permanent failures get a real message**

In `HuntScreen`, render `failedWrites` above the list in `Palette.danger`, one line each, naming the hunt. This is not the `syncError` line — that says "couldn't save that count", which is now wrong for queued work because it *will* save, later. Give the user a way to dismiss.

- [ ] **Step 4: Build and screenshot**

```bash
cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker \
  -destination 'platform=iOS Simulator,id=5E394296-95FD-4790-8862-3D6B6BC503C2' build 2>&1 | tail -3
SIM=5E394296-95FD-4790-8862-3D6B6BC503C2
xcrun simctl launch $SIM com.casperkarlsen.shinytracker -huntPreview hunts
xcrun simctl io $SIM screenshot /tmp/task5-hunts.png
```
Expected: `** BUILD SUCCEEDED **`, list renders. The harness has an empty queue, so no marker shows — say so rather than implying you saw one.

- [ ] **Step 5: Commit**

```bash
git add ios/App
git commit -m "feat(ios): show queued work, and say plainly when it cannot land

A pending marker at the weight of the timer badge, not an alert colour:
queued work is normal. The counter buttons stay live and nothing spins,
because counting has to feel identical offline.

A write that can never land gets its own message naming the hunt. It does
not reuse the syncError line, which says 'couldn't save that count' — now
wrong for queued work, because it will save, later."
```

---

## Verification of the whole slice

Packages: `swift test` across all four, `go test ./...`. Then the checks only the user can run, on device:

1. **Airplane mode, count a hunt.** The number moves, nothing errors, a pending marker appears.
2. **Force-quit while still offline, reopen.** The count and the marker are both still there — the queue is durable.
3. **Turn signal back on and foreground the app.** The marker clears and the web app shows the new total.
4. **Airplane mode, mark a hunt found.** It moves to History immediately; it reaches the server on reconnect.

## Known gaps

- **No background sync.** A landed plane syncs when the app is next opened.
- **The drain and the enqueue call sites have no mechanical test**, being app-target code. The queue's rules — the part that broke in A's equivalent — are tested in `ShinyTrackerKit`.
- **The absolute-count path and its perimeter stay.** `allow_decrease`, `serverBacked` and `HuntCountPolicy` still guard the web client's writes. Retiring them needs the web client on deltas first, and is a separate change.
