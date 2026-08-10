# Handoff — ShinyTracker iOS

Three files:

- **`IOS_HANDOVER.md`** — start here. Native Swift target: two blocking architecture decisions,
  the counting-interaction constraint, and iOS-specific work.
- **`ODDS_DOMAIN_REVIEW.md`** — shiny-mechanics accuracy findings. Drop into the repo at
  `docs/audit/ODDS_DOMAIN_REVIEW.md`.
- **`README.md`** (this file) — design intent from the prototype, and what *not* to rebuild.

Add a pointer in `backend/CLAUDE.md`, or none of this gets read:

```
## Domain accuracy
See docs/audit/ODDS_DOMAIN_REVIEW.md for open odds-engine findings.
Finding 1 requires the same fix in internal/calc/methods.go and frontend/src/utils/odds.ts.
```

Not covered in these files, flagged separately: sprite licensing (bundling Nintendo assets into a
distributed app), and RLS still disabled on all tables per your own audit.

---

## Prototype design intent

**Target is a native Swift iOS app.** Read `handoff/IOS_HANDOVER.md` first — it contains two
blocking architecture decisions that must be settled before any Swift is written. The items below
are the design intent; that file maps them to iOS.

**Read this too:** `Hunt Prototype.dc.html` is a **design artifact**, not source to port. It was
built before the ShinyTracker repo was available, so its storage and timer scaffolding duplicate —
and are worse than — what already exists. `store.js` in this project is throwaway; do not
implement it.

The repo already has: Postgres + migrations, Supabase auth, per-hunt `total_time_seconds` with a
600-second inactivity threshold (`openspec/specs/hunt-active-timer`), phase logging, live chain
tracking, and an odds engine in both Go and TS. Nothing in the prototype improves on those.

What follows is only the part of the prototype that is **not** already in the repo.

---

## 1. Screen Wake Lock — absent from the repo

No `wakeLock` reference exists in `frontend/src`. A phone sleeping mid-hunt is the most common
interruption in a long counting session, and it also silently ends the inferred timer window.

On iOS this is one line — `UIApplication.shared.isIdleTimerDisabled` — set while a hunt is
active and reset on background. No permission prompt, none of the web platform's re-acquisition
handling.

---

## 2. Haptics on count — absent

No `navigator.vibrate` in the repo. An 8ms pulse on increment and 4ms on decrement is what makes
counting possible without watching the screen. Cheap, and it pairs with item 3.

---

## 3. Counting without looking at the screen — absent

`App.tsx` and `Dashboard.tsx` register `keydown` handlers, but they appear to be navigation
shortcuts rather than counting.

The prototype binds Space / ArrowUp to increment and ArrowDown to decrement on the live hunt.
The intent is counting without watching the screen, which is what decides whether someone counts
3,000 encounters in your app or in a physical tally counter.

**Volume-button counting is out of scope on iOS** — it risks App Store rejection. The need is met
by a large haptic tap target as the baseline, with an Apple Watch companion and Bluetooth HID
clicker support as the routes to eyes-free counting. See `IOS_HANDOVER.md`.

---

## 4. Undo — absent

No undo path in the repo. Two cases matter, and they are different:

- **Miscount.** Coalesce a burst of taps into one undo entry with a ~2.5s trailing window, so
  "undo" means *that mistake*, not the last of four hundred taps. The prototype implements this
  in `bump()`.
- **Destructive actions.** Abandoning a hunt or clearing an encounter should be reversible for a
  few seconds rather than confirmed up front. The repo has `ConfirmDialog`; an undo toast is
  usually the better trade for actions that are frequent and recoverable.

---

## 5. Direct count entry — verify

Tapping the count to type a number matters after a miscount, an app crash, or a hunt migrated
from a spreadsheet. Without it the only correction path is tapping −1 repeatedly.

---

## 6. Accessibility pass — partial in the repo

`aria-label` exists on nav, search, and the More sheet. Audit specifically:

- Icon-only **counter** controls (+ / − / step / found) — the highest-traffic buttons in the app.
- An `aria-live="polite"` region announcing the count, so the number is available without sight
  of the screen. This compounds with items 2 and 3.
- 44px minimum on counter controls.
- Contrast on muted text against the dark surface.

---

## Timer: a design difference, not a defect

The repo infers hunting time server-side from PATCH deltas, discarding gaps over 600 seconds. The
prototype instead uses an explicit start/pause the user controls.

The repo's model is better for accuracy and needs no user attention. The gap is that a hunter
cannot **pause** — stepping away for under ten minutes still accrues time, and there is no way to
say "stop counting, I'm done for now." Worth considering an explicit pause on top of the inferred
model rather than replacing it.

---

## Also in this handoff

- `IOS_HANDOVER.md` — **start here.** Native target, two blocking decisions, App Store
  constraint on the counting interaction.
- `ODDS_DOMAIN_REVIEW.md` — shiny-mechanics accuracy findings against `internal/calc`,
  `seeds/hunt_methods.json`, and `frontend/src/utils/odds.ts`. Drop it at
  `docs/audit/ODDS_DOMAIN_REVIEW.md`. Four are wrong numbers shown to users today; one must be
  fixed in every odds engine, which will soon be three.
