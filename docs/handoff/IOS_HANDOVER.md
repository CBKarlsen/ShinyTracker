# iOS Handover — native Swift target

Context: the existing frontend is React + TypeScript + Vite. A native Swift iOS client replaces
it for mobile; the Go API and Postgres stay. This file covers what changes because of that, and
is meant to be read alongside `ODDS_DOMAIN_REVIEW.md` and `HANDOFF.md`.

Two items below are **blocking architecture decisions**, not tasks. They should be settled before
any Swift is written.

---

## 🔴 BLOCKER 1 — The server-derived timer is incompatible with offline counting

`openspec/specs/hunt-active-timer` derives `total_time_seconds` on the server from the gap between
PATCH requests, discarding gaps of 600 seconds or more. That works when every increment is an
online PATCH. It breaks completely on a native app, where offline counting is a core expectation.

Concretely: a user counts 500 encounters on a plane, then syncs. The server sees one PATCH with a
delta of several hours, decides the gap exceeds the threshold, and credits **zero** time for the
entire session. Two hours of hunting silently vanishes.

**Decision needed.** The realistic shape is to invert ownership: the client owns time, the server
stores it.

- Client accumulates active time locally from timestamps (never from a running clock — iOS
  suspends the app, and a `Timer` stops with it; compute elapsed from stored dates on foreground).
- Client applies its own inactivity threshold, since only it knows the real encounter cadence.
- Sync sends `total_time_seconds` as a value the server accepts, not one it derives.

This also has to be reconciled with the phase-logging and `updated_at` semantics that currently
depend on PATCH timing.

---

## 🔴 BLOCKER 2 — The odds engine would exist three times

It is already implemented twice (`internal/calc/methods.go`, `frontend/src/utils/odds.ts`), held
in agreement by hand-maintained mirror comments. Finding 1 in `ODDS_DOMAIN_REVIEW.md` is what that
already costs: an identical bug in both copies, with tests passing.

A Swift implementation makes it three, and the odds **must** compute on-device — offline counting
means the app cannot ask the server what the current odds are mid-chain.

**Do this before writing the Swift version:** extract the shared fixture set of
`(formula_type, params, base_odds, base_rolls, charm_rolls, has_charm) → denominator` anchors as
a JSON file in the repo, consumed by `methods_test.go`, a TS test, and a Swift test alike. The
anchors become the source of truth; the three implementations are checked against it rather than
against each other. Several anchors already exist as prose comments in `odds.ts` (the PLA and
ultra-wormhole blocks) and can seed it directly.

Fix the four wrong-number findings **first**, so the fixture is generated from corrected values.

---

## Counting without watching the screen

The need is real — it decides whether someone counts 3,000 encounters in your app or in a physical
tally counter — but **volume-button counting is out of scope.** Apple has historically rejected
apps that repurpose the volume buttons for non-audio actions, and the usual implementation
(observing `AVAudioSession.outputVolume`) is the pattern that draws it. Do not build it, and do not
let the interaction design assume it.

What to build instead, in order of value:

- **Large primary tap target with haptics** — the baseline, and it carries the whole feature. It
  must be reachable one-handed, big enough to hit without looking, and give a distinct impact on
  every increment. Get this excellent before anything else.
- **Apple Watch companion** — Digital Crown or screen tap to count with the phone in a pocket.
  The best answer for long sessions and a genuine differentiator.
- **Bluetooth HID clicker** — cheap page-turner remotes present as keyboards; hunters already buy
  them for exactly this. Handling key events costs little and carries no App Store exposure.
- **Action button** (iPhone 15 Pro+) via App Intents.

---

## Native equivalents of the prototype items

| `HANDOFF.md` item | iOS |
|---|---|
| Screen wake lock | `UIApplication.shared.isIdleTimerDisabled = true` while a hunt is active. No permission, no `visibilitychange` dance. Reset on background. |
| Haptics | `UIImpactFeedbackGenerator(style: .light)` on increment, `.rigid` or a distinct style on decrement. Prepare the generator to avoid first-tap latency. |
| Undo | Same coalescing logic (~2.5s trailing window). Consider `UndoManager`, and shake-to-undo is free if wired. |
| Direct count entry | Numeric keypad; same correction need. |
| Accessibility | VoiceOver labels on counter controls, `.accessibilityValue` for the count, and an announcement on change. **Dynamic Type is required** — the count and odds readouts must survive the largest sizes. 44pt minimum. |

---

## Additional iOS-only work

**Live Activity / Dynamic Island.** A hunt counter is close to the ideal Live Activity: encounter
count, elapsed time, and current odds on the lock screen, countable without unlocking. Strong
enough that it is worth scoping early rather than treating as polish.

**Offline-first storage and sync.** SwiftData or Core Data plus an outbound change queue. Sync
rules that matter: per-hunt last-write-wins, encounter count treated as a monotonic counter (never
overwrite a higher server value with a lower local one without an explicit user decision), and
conflict resolution that never silently discards counts. Losing a long hunt is the one
unforgivable failure in this category.

**Sign in with Apple.** Required by App Store guideline 4.8 if you offer other third-party sign-in
options. Check what the Supabase auth setup currently exposes (`AUTH-SETUP.md`).

**Sprites.** `SPRITE_BASE` currently points at `raw.githubusercontent.com` — rate-limited, no CDN,
useless offline. On mobile this is worse than on web: it costs bandwidth on cellular and breaks
the offline case entirely. Bundle the sprite set in the app, or ship it from your own CDN with an
on-device cache. Decide before the first build, since bundling affects app size and asset
pipeline.

**Background behaviour.** Never rely on a foreground `Timer` for elapsed time. Persist start and
accumulated values, recompute on `willEnterForeground`. Verify counting and timing survive a
force-quit mid-hunt.

**API surface.** The Go handlers currently assume a web client. Worth reviewing whether the
existing endpoints support batched offline sync, or whether a `PUT /api/hunts/:id/sync` taking a
full client-authoritative hunt state is the better fit given Blocker 1.

---

## Suggested order

1. Fix the four wrong-number findings in `ODDS_DOMAIN_REVIEW.md` (small, and they poison the
   fixture otherwise).
2. Extract the odds fixture set — Blocker 2.
3. Settle the time-ownership model — Blocker 1.
4. Decide the counting interaction, given the volume-button constraint.
5. Then build.
