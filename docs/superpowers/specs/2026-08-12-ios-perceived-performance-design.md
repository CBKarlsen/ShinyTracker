# iOS perceived performance — design

**Status:** approved 2026-08-12. Not yet implemented.

The first slice of a larger "premium and offline" goal. Deliberately the smallest and most
independent piece: pure client work, no schema, no API change, no writes touched.

---

## The problem

Tested on a physical device for the first time on 2026-08-12, against the real API and the fully
seeded Platinum Nuzlocke. Everything worked; nothing felt fast. Three symptoms, reported
independently:

1. Sprites pop in late, leaving holes in lists that fill one by one.
2. Switching tabs shows a spinner or blank screen every time, even for data loaded a minute ago.
3. Taps and scrolling have a beat of lag.

These have three different causes and three different fixes. They are treated separately below.

## Scope

In: the three fixes. Out: cold-launch performance (needs disk persistence — see *Deferred*),
anything touching writes, the API or the schema.

---

## 1. Never blank a screen that is already loaded

### Cause

`AppShell` holds every model as `@State`, so the models — and their data — survive a tab switch.
But each screen's `.task` calls `load()`, which sets `state = .loading` unconditionally. The data
is still in memory; the screen is thrown away anyway and rebuilt from a spinner.

### Fix

One entry point per model:

```swift
func appear() async {
    state == .ready ? await refresh() : await load()
}
```

`load()` is the cold path and shows the spinner. `refresh()` is the warm path: it leaves the
current screen up and surfaces a failure as an inline message rather than an error page.

`HuntListModel` already has both halves and already documents the reasoning — its `refresh()`
comment says blanking the list behind a write "reads as a bug". This generalises that to
`DexModel`, `NuzlockeModel` and `GameLibraryModel`, and screens change
`.task { await model.load() }` to `.task { await model.appear() }`.

### Consequence

Every in-session tab switch becomes instant. A failed warm refresh must never blank a readable
screen — that is the one regression to watch, and it is why the warm path reports through
`syncError` rather than `state = .failed`.

---

## 2. Precompute the Nuzlocke row data

### Cause

`NuzlockeScreen.locationRow` reads `model.currentLocationSlug` for **every one of the 62 rows**.
That property scans the whole timeline, and for each entry calls `log(at:)`, which linearly scans
the logged encounters. One redraw is therefore on the order of `62 × 62 × encounters` operations
on the main actor. `option(for:)` scans the timeline and then a pool, per logged row.
`coverageGaps` — which allocates a `TypeChart.defense` result per party member per threat type —
is a computed property read directly in the view body, so it recomputes on every redraw too.

This is the dominant cost behind symptom 3, and it grew invisible: at 13 seeded stops it was
cheap, and the timeline went to 62 stops on the same day the device test happened.

### Fix

One `rebuild()` on `NuzlockeModel`, producing stored values instead of recomputed ones:

- `logsBySlug: [String: NuzlockeEncounterLog]`
- `optionsBySlug: [String: [Int: NuzlockeEncounterOption]]`
- `currentSlug: String?` — resolved once, not per row
- `coverage: [CoverageGap]` — computed once, not per body evaluation

Rows become dictionary lookups. The existing computed properties are **replaced**, not kept
alongside, so there is one source of truth and no way for a caller to reach the slow path by
accident.

### Rebuild triggers

Correctness here matters more than speed: stale coverage advice after a catch is worse than slow
coverage advice. Every mutation already funnels through a small, enumerable set of seams, so
`rebuild()` is called from exactly four places:

1. `open(_:)` — a run is loaded or switched
2. `apply(_:)` — an encounter is logged, or a party member is boxed or buried
3. `setBoss(_:beaten:)` — changes `nextCheckpoint`, and therefore the whole coverage warning.
   Both the optimistic write **and** its rollback path must rebuild, or a failed tick leaves the
   warning describing a checkpoint you have not actually beaten.
4. `loadSpeciesTypes()` completing — coverage depends on it and it arrives asynchronously, after
   the first rebuild has already run

If a future write path is added, it belongs in this list. That is the whole reason the mutation
seams are kept few.

---

## 3. Sprite cache and a real placeholder

### Cause

`DexSprite` uses `AsyncImage` with `Color.clear` as its placeholder. `AsyncImage` keeps no decoded
image cache, so scrolling away and back re-fetches and re-decodes. Every sprite is an external
request — `sprite_url` points at PokeAPI's CDN, and `SpriteSource` falls back to the same host
when the column is blank — so each one is a network round trip, and a row with no image renders as
a hole.

### Fix

- A small actor-backed `URL → UIImage` cache, checked before any fetch.
- A raised `URLCache` at launch so the underlying HTTP responses survive too.
- `DexSprite`'s placeholder becomes the sprite plate (the existing
  `spriteTileInner`/`spriteTileOuter` gradient) rather than `Color.clear`, so a loading row has
  the right shape and weight instead of a gap.

Deliberately not a third-party image library: this is one screen's worth of sprites at known
sizes, and the cache is a few dozen lines.

---

## Testing

The app target has no test target, and adding one is a structural change outside this slice's
scope. Verification is therefore behavioural and explicit:

- `swift test` for the packages (unchanged by this work, but must stay green).
- Simulator: the existing `-huntPreview`, `-dexPreview` and `-nuzlockePreview seeded` harnesses
  render every affected screen without a server.
- Device, by the user: the symptoms were felt on device and that is where the fix is judged.
  Three specific checks — a tab switch does not blank, scrolling the 62-row timeline is smooth,
  and sprites do not re-pop when scrolling back.

The one piece of logic worth a mechanical check is `rebuild()`'s output, and it lives in the app
target where nothing can reach it. Recorded as a known gap rather than papered over: if it becomes
a recurring risk, the honest fix is extracting the Nuzlocke view-state derivation into a package,
which is a separate change.

---

## Deferred

- **Cold launch still shows a spinner.** Nothing is on disk, so a fresh start has nothing to draw.
  Fixing it means a local read cache — persist the last payload per screen and render it
  immediately. That is the next slice and was consciously deferred when this one was scoped.
- **Offline writes**, which additionally require D1 (`docs/handoff/DECISIONS.md`) to be
  implemented first: the client must own elapsed time and the encounter count must be a monotonic
  counter before any write queue exists, or a synced offline session silently loses its hours.

---

## Related

- `docs/handoff/DECISIONS.md` — D1 (time ownership, monotonic counter), D3 (counting interaction)
- `docs/handoff/IOS_HANDOVER.md` — the offline-counting blocker this slice deliberately does not
  address
