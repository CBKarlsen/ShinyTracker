# Architecture decisions

Decisions taken against the two blockers in `IOS_HANDOVER.md`. Reversible until the sync layer
exists; after that they are expensive to change.

---

## D1. Time ownership — the client owns elapsed time, the server stores it

**Status:** decided 2026-08-10. Not yet implemented.

`openspec/specs/hunt-active-timer` derives `total_time_seconds` server-side from the gap between
PATCH requests, discarding gaps ≥600s. This cannot survive offline counting: a session that
produces no PATCHes is invisible to the server, and the single catch-up PATCH that follows looks
like one enormous gap and is discarded. Two hours of hunting silently becomes zero.

There is no variant of server-side inference that fixes this, because the server does not have the
information — only the client knows when encounters actually happened.

So:

- The client accumulates active time locally and applies its own inactivity threshold.
- Sync sends `total_time_seconds` as a value the server **accepts and stores**, not one it derives.
- The client computes elapsed time from stored timestamps, never from a running `Timer` — iOS
  suspends the app and a `Timer` stops with it. Recompute on `willEnterForeground`.

**Consequence for the API:** `PATCH /api/hunts/{id}` currently recomputes `total_time_seconds`
server-side (`UpdateHuntHandler`). That logic has to become "accept the client's value" for
client-authoritative writes, while the web frontend either keeps the old behaviour or moves to the
same model. Reconcile with phase logging and `updated_at`, which also key off PATCH timing.

**Encounter count is a monotonic counter.** Never overwrite a higher server value with a lower
local one without an explicit user decision. Plain last-write-wins is wrong the moment two devices
count the same hunt (phone + Apple Watch is an explicitly planned configuration). Losing a long
hunt is the one unforgivable failure in this app.

---

## D2. Odds engine — three implementations checked against shared anchors

**Status:** done 2026-08-10 (fixture), Swift consumer in progress.

`shared/odds_anchors.json` is the source of truth. Go asserts it in
`backend/internal/calc/anchors_test.go`; the Swift engine asserts the same file. Implementations
are checked against the anchors, never against each other — two engines agreeing is not evidence,
it is how the Poké Radar bug survived a full method audit.

Adding a formula means adding anchors first.

**Monorepo-only test dependency.** `ShinyTrackerKit`'s tests locate the fixture by walking up
from `#filePath` to the repo root, so the anchors stay a single shared file rather than a copy
per language. The consequence: the package must stay a **local** package inside this repo. If it
is ever consumed as a remote/pinned SPM dependency from a separate app repo, the fixture will not
exist in the checkout and the test target goes permanently red. Bundle a resource copy at that
point — and accept that the copy can then drift, which is the thing this file exists to prevent.

---

## D3. Counting interaction — no volume-button counting

**Status:** decided 2026-08-10.

Volume-button counting is the obvious implementation and is not shippable: Apple has historically
rejected apps repurposing volume buttons for non-audio actions, and the usual approach (observing
`AVAudioSession.outputVolume`) is the pattern that draws it. Do not build it, and do not let the
interaction design assume it.

In order of value: a large one-handed haptic tap target (this carries the feature — get it
excellent before anything else), then an Apple Watch companion, then Bluetooth HID clickers
(page-turner remotes already present as keyboards), then the Action button via App Intents.
