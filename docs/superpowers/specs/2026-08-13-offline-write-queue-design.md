# Offline write queue (sub-project B) — design

**Status:** proposed 2026-08-13.

Second of three toward offline support. Sub-project A made the app **readable** offline; counting
— the app's core activity — still fails without a connection. This makes hunt counting and
completion work with no signal, and syncs them when one returns.

---

## The decision that shapes everything: deltas, not absolute counts

`PATCH /api/hunts/{id}` takes an **absolute** `encounter_count`. That is why sub-project A needed
five fix passes: a stale local number could overwrite a good server number, and `allow_decrease`,
`serverBacked`, the press-time gate and the `max` reconciliation are all a defensive perimeter
around that one property.

A delta has no such failure mode. "Apply −1 to whatever you have" is correct no matter what the
client believes the count to be, so stale state cannot corrupt anything. It is also the only model
in which two offline sessions on the same hunt both survive — phone plus Apple Watch, which D1
names as an explicitly planned configuration and which absolute writes cannot serve.

**Consequence to state plainly:** once counting goes through deltas, the absolute-count path has no
iOS caller. Retiring it is a stated goal, not part of this slice — it stays as the safety net while
the queue is unproven, and the web client still uses it.

**Time is the opposite case and needs no queueing.** `total_time_seconds` is already absolute and
already merged with `max` server-side (`calc.DecideTotalTime`), which makes it idempotent by
construction. A replay simply sends the clock's current total. Count is delta + dedupe; time is
absolute + max. Neither needs the other's machinery.

## Scope

In: counting (`+`/`−`) and marking a hunt found, offline, with durable replay. Out: starting a hunt
offline (needs client-generated hunt ids and the method/game pickers' data cached); background
sync; Nuzlocke, dex and charm writes (sub-project C).

---

## 1. The queue

An ordered list of pending operations, persisted through `SnapshotStore` under one key. Tens of
entries at most, so an array rewritten atomically on change is the right structure — no log, no
database.

```swift
public struct PendingWrite: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID            // the idempotency key, generated at enqueue
    public let huntID: UUID
    public private(set) var kind: Kind
    /// Set the first time this entry is sent. An attempted entry is frozen — see below.
    public private(set) var attempted: Bool
    /// Consecutive failed drains. Past a limit the entry is treated as permanent.
    public private(set) var failures: Int

    public enum Kind: Codable, Equatable, Sendable {
        case count(delta: Int)
        case found
    }
}
```

`found` carries no payload: the completing request sends the clock's current total, which is
correct at replay time rather than at enqueue time.

### Coalescing and ordering

- Consecutive `.count` writes for the same hunt **merge into one delta**. Five hundred taps become
  `+500`, not five hundred requests. This is the queue's main job.
- **An entry that has been attempted never merges again, and is never removed by coalescing.**
  This is the subtle one. A request can land and apply server-side while its response is lost, so
  once an id has been sent the server may already hold it. Merging `+5` into that id would have
  the server dedupe the whole thing and silently discard the five. After an attempt, new counts
  start a fresh entry with a fresh id; the frozen one is resolved on its own terms by the next
  drain, where the dedupe table makes a re-send harmless.
- A `.found` is a **barrier**: nothing merges across it, and every `.count` enqueued before it must
  replay first, or the hunt completes at the wrong number.
- Coalescing that produces a delta of zero (three up, three down) removes the entry entirely —
  but only while it is unattempted, for the reason above.
- Ordering is global FIFO. Per-hunt ordering is what actually matters, and global FIFO gives it
  without the bookkeeping of parallel queues.

These rules are pure functions of a queue and an operation, so they live in `ShinyTrackerKit`
beside `HuntCountPolicy` and are tested from the first commit. That is the lesson of sub-project A
applied up front: the decisions that broke five times were untestable because they lived in the
app target.

## 2. Idempotency — non-negotiable with deltas

A retried request that actually succeeded must not apply twice. With absolute counts this was free;
with deltas, `+500` landing twice invents 500 encounters. An offline queue retries by definition.

So every write carries its `id`, and the server records applied ids:

```sql
CREATE TABLE hunt_writes (
    write_id   UUID PRIMARY KEY,
    user_id    UUID NOT NULL,
    hunt_id    UUID NOT NULL REFERENCES user_hunts(id) ON DELETE CASCADE,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

The insert and the count update happen **in one transaction**. `INSERT … ON CONFLICT DO NOTHING`;
if it inserted nothing the write is a replay, so the handler skips the update and returns the
current state. Two transactions would leave a window where a crash between them either double-
applies or loses the write.

## 3. The API change

`PATCH /api/hunts/{id}` gains two optional fields rather than growing a new endpoint — the same
request already carries `status` and `total_time_seconds`, and a completion needs all three
together.

- `encounter_delta` (int, optional): when present, the count moves by this amount and
  `encounter_count` is ignored.
- `write_id` (uuid, optional): required whenever `encounter_delta` is present, meaningless without
  it.

Absent both, the handler behaves exactly as today, so the web client is untouched and
`calc.DecideEncounterCount` keeps guarding the absolute path.

The response returns the stored count, as it does now, so the client reconciles rather than
assuming.

## 4. Replay

On foreground with connectivity, drain FIFO, **stopping at the first failure** so ordering is never
broken. Classification decides what happens next:

| Outcome | Action |
|---|---|
| 2xx | Remove from queue, reconcile the row with the returned count |
| 401 | `APIClient` already refreshes once and retries; a second 401 stops the drain |
| 5xx, timeout, offline | Leave queued, stop the drain, try again next foreground |
| 404 or 4xx that cannot succeed | **Permanent**: remove and surface to the user |

A permanent failure is never silently dropped. A hunt deleted on the web while you counted it
offline is exactly the case where quietly discarding the work is worst — the user counted those
encounters and deserves to be told they cannot land.

Retries are bounded by a failure count on each entry; past the limit an entry is treated as
permanent rather than retried forever.

## 5. What the user sees

- A hunt with queued work shows its local count normally, plus a quiet pending marker. Nothing
  spins and nothing blocks — the whole point is that counting feels identical offline.
- A permanently failed write produces a real message naming the hunt, not a generic banner.
- The existing `syncError` line is not reused for queued work: "couldn't save that count" is now
  wrong, because it will save, later.

## Testing

**`ShinyTrackerKit`** — `WriteQueue`'s rules, which is most of the risk: consecutive counts merge;
a `found` blocks merging across it; counts before a `found` replay first; a net-zero delta
disappears; interleaved hunts keep per-hunt order; a coalesced entry keeps a single stable id.

**Go** — the dedupe path: a second apply of the same `write_id` changes nothing and returns the
stored count; a delta with no `write_id` is rejected; the absolute path is unaffected by the new
columns; the transaction rolls back as a unit.

**Not mechanically tested:** the replay driver and the enqueue call sites, which live in the app
target. Verified by build, the preview harnesses, and on device — where the queue is finally
exercisable by turning on airplane mode, which no agent in this environment can do.

## Deferred

- **Background sync.** Replay happens on foreground. A landed plane syncs when the app is next
  opened, which is what a hunter does anyway.
- **Starting a hunt offline** — needs client-generated hunt ids the server accepts.
- **Nuzlocke, dex and charm writes** — sub-project C, which reuses this queue.
- **Retiring the absolute-count path** and the perimeter around it (`allow_decrease`,
  `serverBacked`) once the web client also moves to deltas.

## Related

- `docs/superpowers/specs/2026-08-12-offline-foundation-design.md` — sub-project A
- `docs/handoff/DECISIONS.md` — D1 (monotonic counter, client-owned time)
- `ios/ShinyTrackerKit/Sources/ShinyTrackerKit/HuntCountPolicy.swift` — the absolute-path rules this
  slice makes redundant for iOS
