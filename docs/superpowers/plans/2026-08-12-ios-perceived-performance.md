# iOS Perceived Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the iOS app feel fast within a session — no blanked screens on tab switch, no per-frame rescans behind the Nuzlocke timeline, no sprites popping in twice.

**Architecture:** Three independent client-side fixes, one per reported symptom. No schema, no API, no writes touched. Each task ships on its own and can be judged on its own.

**Tech Stack:** Swift 6, SwiftUI, `@Observable` `@MainActor` models, local SPM packages (`ShinyTrackerAPI`, `ShinyTrackerUI`, `ShinyTrackerKit`, `ShinyTrackerAuth`), XcodeGen.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-12-ios-perceived-performance-design.md`.
- **The app target has no test target and this plan does not add one.** Verification is by build plus the DEBUG preview harnesses driven through `simctl`. Do not invent a test target; do not add a test framework. Package tests (`swift test`) must stay green but are not extended here.
- Do not touch writes, the API client's request/response types, the Go backend, or any migration.
- Follow the codebase's existing comment idiom: explain *why*, not *what*. Load-bearing decisions get a sentence; obvious code gets nothing.
- `Dictionary(_:uniquingKeysWith:)` never `Dictionary(uniqueKeysWithValues:)` — the latter traps on a duplicate key, and this codebase has an explicit convention against it (`GameLibraryModel.load`).
- Simulator UDID used throughout: `5E394296-95FD-4790-8862-3D6B6BC503C2` (iPhone 15 Pro). Bundle id: `com.casperkarlsen.shinytracker`.
- Run all `xcodebuild`/`xcodegen`/`swift` commands from `ios/`.

---

### Task 1: Warm-path loading — stop blanking screens that already have data

**Files:**
- Modify: `ios/App/Hunt/HuntListModel.swift` (add `appear()` after `refresh()`, ~line 117)
- Modify: `ios/App/Nuzlocke/NuzlockeModel.swift` (add `appear()` after `refresh()`, ~line 52)
- Modify: `ios/App/Dex/DexModel.swift` (`load()` at line 109 becomes `load(quiet:)`, plus `refresh()`/`appear()`)
- Modify: `ios/App/Hunt/GamesTab.swift` (`GameLibraryModel.load()` at line 30 becomes `load(quiet:)`, plus `refresh()`/`appear()`)
- Modify: `ios/App/Hunt/HuntScreen.swift` lines 35, 38, 251, 289
- Modify: `ios/App/Dex/DexScreen.swift` lines 31, 278
- Modify: `ios/App/Nuzlocke/NuzlockeScreen.swift` line 24
- Modify: `ios/App/Hunt/GamesTab.swift` line 173

**Interfaces:**
- Produces: `func appear() async` on `HuntListModel`, `DexModel`, `NuzlockeModel`, `GameLibraryModel`. Also `refresh()` on `DexModel` and `GameLibraryModel`, which did not have one.
- Consumes: the existing `LoadState` enum (`ios/App/Hunt/HuntListModel.swift:67`), which is `Equatable`, so `state == .ready` compiles.

- [ ] **Step 1: Add `appear()` to the two models that already have a quiet path**

In `HuntListModel.swift`, directly after the existing `refresh()` (line 117):

```swift
    /// What a screen's `.task` calls. Reloading from scratch every time a tab is shown throws
    /// away a screen that is already correct: `AppShell` holds these models as `@State`, so the
    /// data survives the switch even though the view does not. Only a cold model shows a spinner.
    func appear() async {
        state == .ready ? await refresh() : await load()
    }
```

In `NuzlockeModel.swift`, directly after the existing `refresh()` (line 52), add the identical method with the same doc comment.

- [ ] **Step 2: Give `DexModel` a quiet path**

In `DexModel.swift`, replace the `func load() async {` signature at line 109 and its `state = .loading` / `catch` block so the whole method reads:

```swift
    func load() async { await load(quiet: false) }

    func refresh() async { await load(quiet: true) }

    /// See `HuntListModel.appear()`.
    func appear() async {
        state == .ready ? await refresh() : await load()
    }

    /// `quiet` skips the loading state, for a reload behind a screen the user is already
    /// reading. A failure then reports inline instead of replacing the grid with an error page —
    /// the grid on screen is still perfectly good data.
    private func load(quiet: Bool) async {
        if !quiet { state = .loading }
        syncError = nil
        do {
            // Three independent GETs; the species list is the big one (1,025 rows) and there is
            // no reason for the other two to wait behind it.
            async let speciesTask = client.pokemon(all: true)
            async let gamesTask = client.games()
            async let huntsTask = client.hunts()
            async let statusTask = client.dexStatus()

            let species = try await speciesTask
            let games = try await gamesTask
            let hunts = try await huntsTask
            // `/api/dex/status` is the only blocked-state source; if it fails the grid is still
            // usable, so it degrades to "nothing is known to be blocked" instead of failing
            // the whole screen.
            let status = try? await statusTask

            sections = Self.group(species)
            self.games = games
            apply(hunts: hunts)
            notInYourGames = Set(status?.notInYourGames ?? [])
            lockedEverywhere = Set(status?.lockedEverywhere ?? [])
            await loadAvailability()
            state = .ready
        } catch {
            if quiet {
                syncError = "Couldn't refresh the dex. \(userFacingMessage(for: error))"
            } else {
                state = .failed(userFacingMessage(for: error))
            }
        }
    }
```

- [ ] **Step 3: Give `GameLibraryModel` a quiet path**

In `GamesTab.swift`, replace `func load() async {` (line 30) so the method reads:

```swift
    func load() async { await load(quiet: false) }

    func refresh() async { await load(quiet: true) }

    /// See `HuntListModel.appear()`.
    func appear() async {
        state == .ready ? await refresh() : await load()
    }

    private func load(quiet: Bool) async {
        if !quiet { state = .loading }
        syncError = nil
        do {
            let id = try await resolveUserID()
            async let all = client.games()
            async let mine = client.userGames(userID: id)
            games = try await all.sorted { ($0.generation, $0.id) < ($1.generation, $1.id) }
            // Not `uniqueKeysWithValues`: that TRAPS on a duplicate key. `user_games` is keyed
            // (user_id, game_id) so duplicates should be impossible, and a crash is the wrong
            // way to find out that they were not.
            owned = Dictionary(
                try await mine.map { ($0.gameID, $0.hasShinyCharm) }, uniquingKeysWith: { _, b in b }
            )
            state = .ready
        } catch {
            if quiet {
                syncError = "Couldn't refresh your games. \(userFacingMessage(for: error))"
            } else {
                state = .failed(userFacingMessage(for: error))
            }
        }
    }
```

Note: `syncError` already exists on this model (line 21). Do not add it again.

- [ ] **Step 4: Point every `.task` and `.refreshable` at the right path**

Exact replacements:

| File | Line | From | To |
|---|---|---|---|
| `App/Hunt/HuntScreen.swift` | 35 | `.task { await model.load() }` | `.task { await model.appear() }` |
| `App/Hunt/HuntScreen.swift` | 38 | `.task { await library.load() }` | `.task { await library.appear() }` |
| `App/Hunt/HuntScreen.swift` | 251 | `.refreshable { await model.load() }` | `.refreshable { await model.refresh() }` |
| `App/Hunt/HuntScreen.swift` | 289 | `.refreshable { await model.load() }` | `.refreshable { await model.refresh() }` |
| `App/Dex/DexScreen.swift` | 31 | `await model.load()` | `await model.appear()` |
| `App/Dex/DexScreen.swift` | 278 | `.refreshable { await model.load() }` | `.refreshable { await model.refresh() }` |
| `App/Nuzlocke/NuzlockeScreen.swift` | 24 | `.task { await model.load() }` | `.task { await model.appear() }` |
| `App/Hunt/GamesTab.swift` | 173 | `.refreshable { await library.load() }` | `.refreshable { await library.refresh() }` |

Leave every `Button("Try again") { Task { await model.load() } }` alone — those are the cold path on a failed screen and *should* show the spinner.

Pull-to-refresh moves to the quiet path because SwiftUI already draws its own spinner for it; replacing the whole screen with a second one is the bug being fixed.

- [ ] **Step 5: Build**

```bash
cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker \
  -destination 'platform=iOS Simulator,id=5E394296-95FD-4790-8862-3D6B6BC503C2' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Verify the warm path in the simulator**

```bash
SIM=5E394296-95FD-4790-8862-3D6B6BC503C2
APP=$(xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker \
  -destination "platform=iOS Simulator,id=$SIM" -showBuildSettings 2>/dev/null \
  | awk -F'= ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)
xcrun simctl install $SIM "$APP/ShinyTracker.app"
xcrun simctl launch $SIM com.casperkarlsen.shinytracker -nuzlockePreview seeded
```

The harness stubs a 200ms delay per request, so a cold load visibly spins. Tap to the Hunt tab and back to Nuzlocke. Expected: the run screen reappears **immediately with content**, no spinner. Before this change it spun for ~200ms and flashed empty every time.

Screenshot for the record:

```bash
xcrun simctl io $SIM screenshot /tmp/warm-path.png
```

- [ ] **Step 7: Commit**

```bash
git add ios/App
git commit -m "perf(ios): stop blanking screens that are already loaded

AppShell holds every model as @State, so a tab switch keeps the data and
throws away only the view — but each screen's .task called load(), which
sets state = .loading unconditionally and rebuilt a correct screen from a
spinner.

appear() takes the warm path when there is already data and the cold path
when there is not. Pull-to-refresh moves to the quiet path too: SwiftUI
draws its own spinner for it, and replacing the whole screen with a second
one is the thing being fixed. Try again stays cold — that screen genuinely
has nothing.

DexModel and GameLibraryModel gain the load(quiet:)/refresh() split that
HuntListModel and NuzlockeModel already had."
```

---

### Task 2: Derive the Nuzlocke row data once per change, not once per row

**Files:**
- Modify: `ios/App/Nuzlocke/NuzlockeModel.swift` (stored derived state + `rebuild()`; replaces `log(at:)`, `option(for:)`, `currentLocationSlug`, `coverageGaps`)
- Modify: `ios/App/Nuzlocke/NuzlockeScreen.swift` (lines 239, 348, 368, 369, 372 — the per-row call sites)
- Modify: `ios/App/Nuzlocke/EncounterSheet.swift` (uses `model.log(at:)` in `preload()` and `speciesTile`)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: on `NuzlockeModel` — `logsBySlug: [String: NuzlockeEncounterLog]`, `optionsBySlug: [String: [Int: NuzlockeEncounterOption]]`, `currentSlug: String?`, `coverage: [CoverageGap]`. `log(at:)` is **kept** as a one-line dictionary lookup because `EncounterSheet` and `speciesName(for:)` call it; `currentLocationSlug` and `coverageGaps` are **removed** so nothing can reach the slow path.

- [ ] **Step 1: Add the stored derived state**

In `NuzlockeModel.swift`, immediately after the `beaten` property declaration (~line 30):

```swift
    // MARK: Derived row state
    //
    // Built once per data change by `rebuild()` rather than computed per access. These were
    // computed properties, and `NuzlockeScreen` read `currentLocationSlug` inside the row builder
    // — so every redraw scanned the whole timeline, and for each entry scanned the encounters,
    // once for each of 62 rows. That was invisible at the 13 stops the prototype seeded and
    // became the dominant cost the day the timeline reached 62.

    private(set) var logsBySlug: [String: NuzlockeEncounterLog] = [:]
    /// `location slug -> pokemon id -> pool entry`, for the sprite and name of a logged catch.
    private(set) var optionsBySlug: [String: [Int: NuzlockeEncounterOption]] = [:]
    /// "you're here" — the first location with nothing logged against it.
    private(set) var currentSlug: String?
    private(set) var coverage: [CoverageGap] = []
```

- [ ] **Step 2: Add `rebuild()` and make it the only producer of that state**

Add to `NuzlockeModel`, in the `// MARK: Reading the timeline` section:

```swift
    /// Recomputes every derived value. Called from each of the four seams that can change what it
    /// depends on — see the call sites. Cheap enough to run whole: the timeline is ~62 entries.
    private func rebuild() {
        // Not `uniqueKeysWithValues`: it traps on a duplicate key, and the server's one-row-per-
        // (run, location) guarantee is not worth a crash to re-verify.
        logsBySlug = Dictionary(
            encounters.map { ($0.locationSlug, $0) }, uniquingKeysWith: { _, second in second })
        optionsBySlug = Dictionary(
            timeline.map { entry in
                (entry.slug,
                 Dictionary((entry.encounters ?? []).map { ($0.pokemonID, $0) },
                            uniquingKeysWith: { _, second in second }))
            },
            uniquingKeysWith: { _, second in second })
        currentSlug = timeline.first { !$0.isBoss && logsBySlug[$0.slug] == nil }?.slug
        coverage = computeCoverage()
    }
```

- [ ] **Step 3: Replace the four computed properties**

Delete `var currentLocationSlug: String?` and `var coverageGaps: [CoverageGap]` entirely. Replace the bodies of `log(at:)` and `option(for:)` with lookups, keeping their doc comments:

```swift
    func log(at locationSlug: String) -> NuzlockeEncounterLog? { logsBySlug[locationSlug] }

    func option(for log: NuzlockeEncounterLog) -> NuzlockeEncounterOption? {
        guard let pokemonID = log.pokemonID else { return nil }
        return optionsBySlug[log.locationSlug]?[pokemonID]
    }
```

Rename the old `coverageGaps` body to `private func computeCoverage() -> [CoverageGap]`, changing only its declaration line — the body is unchanged and keeps its existing doc comment about damage class and the unknown-types guard.

- [ ] **Step 4: Call `rebuild()` from all four seams**

Add `rebuild()` as the last statement of each:

1. `open(_:)` — after `beaten = Set(...)`
2. `apply(_:)` — after the `if/else` that upserts the row
3. `setBoss(_:beaten:)` — after the optimistic mutation **and** in the `catch` after the rollback. Both, or a failed tick leaves the coverage warning describing a checkpoint you have not beaten.
4. `loadSpeciesTypes()` — after `loadedSpeciesTypes = true`

Also add it to `clearOpenRun()` so switching to "no run" does not leave a stale timeline's derived state behind.

- [ ] **Step 5: Point the view at the stored values**

In `NuzlockeScreen.swift`:

- line 239: `let gaps = model.coverageGaps` → `let gaps = model.coverage`
- line 369: `let isCurrent = model.currentLocationSlug == entry.slug` → `let isCurrent = model.currentSlug == entry.slug`

Lines 348, 368 and 372 call `option(for:)` and `log(at:)`, which are now O(1); leave them as they are.

In `EncounterSheet.swift`, `preload()` and `speciesTile` call `model.log(at:)` — also now O(1), leave them.

- [ ] **Step 6: Build and verify no stale-state regression**

```bash
cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker \
  -destination 'platform=iOS Simulator,id=5E394296-95FD-4790-8862-3D6B6BC503C2' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

Then, in the simulator with `-nuzlockePreview seeded`: the coverage card must show **Dark / Normal / Rock**, with Pebble named as a bench resister on Normal and Rock and none on Dark. That is the same output as before this task — if it changed, `rebuild()` is being called in the wrong place or `computeCoverage()` was altered.

Tap Oreburgh Gate's row, log a catch, and confirm the row updates and the "you're here" ring moves to the next unlogged route. That exercises `apply(_:)` → `rebuild()`.

- [ ] **Step 7: Commit**

```bash
git add ios/App/Nuzlocke
git commit -m "perf(ios): derive the Nuzlocke row data once, not once per row

NuzlockeScreen read currentLocationSlug inside the row builder. That
property scanned the whole timeline and, for each entry, scanned the
logged encounters — so one redraw was roughly 62 x 62 x encounters on the
main actor, and coverageGaps recomputed a TypeChart matchup per party
member per threat on top of it.

It was cheap at the 13 stops the design prototype seeded, and became the
dominant cost the day the timeline reached 62.

rebuild() now produces the lookups once per data change, from four seams:
open, apply, setBoss (including its rollback — a failed tick must not
leave the warning describing a checkpoint you have not beaten) and
loadSpeciesTypes. The computed properties are removed rather than kept
alongside, so nothing can reach the slow path by accident."
```

---

### Task 3: Cache sprites and give them a real placeholder

**Files:**
- Create: `ios/App/SpriteCache.swift`
- Modify: `ios/App/Dex/DexScreen.swift` (`DexSprite`, lines 365-388)
- Modify: `ios/App/ShinyTrackerApp.swift` (raise `URLCache` at launch, in `ShinyTrackerApp.init`)

**Interfaces:**
- Consumes: `SpriteSource.url(id:shiny:served:)` (`ios/App/SpriteSource.swift`), unchanged.
- Produces: `actor SpriteCache` with `static let shared` and `func image(for url: URL) async -> UIImage?`; `DexSprite` keeps its exact existing initialiser signature (`pokemonID:shiny:size:dimmed:served:`) so no call site changes.

- [ ] **Step 1: Write the cache**

Create `ios/App/SpriteCache.swift`:

```swift
import SwiftUI
import UIKit

/// A decoded-image cache in front of the sprite CDN.
///
/// `AsyncImage` keeps no decoded cache: scrolling a row off screen and back re-fetches and
/// re-decodes it, which is why sprites pop in twice on the same list. Every sprite is also an
/// external request — `sprite_url` points at PokeAPI's CDN and ``SpriteSource`` falls back to the
/// same host — so the round trip is real.
///
/// An actor rather than `NSCache`: the values are fetched asynchronously and two rows asking for
/// the same URL at once must not both fetch it. `inFlight` is what makes the second one wait.
///
/// `UIKit` is imported unguarded, unlike ``Haptics``: this type's whole surface is `UIImage`, so a
/// `#if canImport(UIKit)` would delete the method its only caller depends on rather than degrade.
/// The app target is iOS-only (`project.yml`), so there is no platform to degrade for.
///
/// ponytail: no third-party image library. This is one app's worth of sprites at two fixed sizes.
actor SpriteCache {
    static let shared = SpriteCache()

    private var cached: [URL: UIImage] = [:]
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    func image(for url: URL) async -> UIImage? {
        if let hit = cached[url] { return hit }
        if let running = inFlight[url] { return await running.value }

        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return UIImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        // A miss is not cached: a sprite that 404s today may exist after the next backfill, and
        // the URLCache below already absorbs the repeated request cheaply.
        if let image { cached[url] = image }
        return image
    }
}
```

- [ ] **Step 2: Raise the HTTP cache at launch**

In `ShinyTrackerApp.swift`, add an `init()` to the `ShinyTrackerApp` struct, directly above `var body: some Scene`:

```swift
    init() {
        // The default shared URLCache is small enough that a full dex scroll evicts its own
        // sprites. These are tiny immutable PNGs on a CDN, so the disk copy is the cheap win and
        // ``SpriteCache`` sits in front of it holding the decoded images.
        URLCache.shared = URLCache(
            memoryCapacity: 32 * 1024 * 1024, diskCapacity: 256 * 1024 * 1024)
    }
```

- [ ] **Step 3: Rewrite `DexSprite` to use the cache and a real placeholder**

In `DexScreen.swift`, keep `DexSprite`'s existing stored properties (`pokemonID`, `shiny`, `size`,
`dimmed`, `served`) and its `url` computed property exactly as they are. **Add** the `@State`
below and **replace** `body`:

```swift
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            // The sprite plate, always. `Color.clear` left a hole while loading, which is what
            // makes a list look like it is still working after the text has arrived.
            RoundedRectangle(cornerRadius: Radii.sprite(size))
                .fill(
                    RadialGradient(
                        colors: [Palette.spriteTileInner.color, Palette.spriteTileOuter.color],
                        center: UnitPoint(x: 0.5, y: 0.42),
                        startRadius: 0,
                        endRadius: size * 0.72
                    )
                )
            if let image {
                Image(uiImage: image)
                    .resizable().interpolation(.none).scaledToFit()   // image-rendering:pixelated
            }
        }
        .frame(width: size, height: size)
        .grayscale(dimmed ? 1 : 0)
        .opacity(dimmed ? 0.6 : 1)
        .task(id: url) {
            guard let url else { return }
            image = await SpriteCache.shared.image(for: url)
        }
        .accessibilityHidden(true)
    }
```

`.task(id: url)` re-runs when a cell is recycled onto a different sprite, which a plain `.task` would not.

- [ ] **Step 4: Build**

```bash
cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker \
  -destination 'platform=iOS Simulator,id=5E394296-95FD-4790-8862-3D6B6BC503C2' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Verify against the biggest sprite surface there is**

```bash
SIM=5E394296-95FD-4790-8862-3D6B6BC503C2
xcrun simctl terminate $SIM com.casperkarlsen.shinytracker 2>/dev/null
xcrun simctl launch $SIM com.casperkarlsen.shinytracker -dexPreview full
```

`full` is all 1,025 tiles. Scroll a long way down, then back up. Expected: tiles that have already loaded are **instantly** populated on the way back, and every not-yet-loaded tile shows the sprite plate rather than a gap.

```bash
xcrun simctl io $SIM screenshot /tmp/sprite-cache.png
```

- [ ] **Step 6: Confirm the packages are untouched and green**

```bash
cd ios
for p in ShinyTrackerAPI ShinyTrackerAuth ShinyTrackerKit ShinyTrackerUI; do
  swift test --package-path $p 2>&1 | grep -E "✘|Test run with"
done
```

Expected: four passing lines, 35 / 3 / 6 / 15 tests. This task changes no package code; a failure here means something unrelated was disturbed.

- [ ] **Step 7: Commit**

```bash
git add ios/App
git commit -m "perf(ios): cache decoded sprites and stop rendering holes

AsyncImage keeps no decoded cache, so scrolling a row away and back
re-fetched and re-decoded it — every sprite is an external request to the
PokeAPI CDN, so that is a real round trip, and the placeholder was
Color.clear, which renders as a gap.

SpriteCache is an actor so two rows asking for the same URL at once share
one fetch rather than racing. Misses are deliberately not cached: a sprite
that 404s today may exist after the next backfill.

The placeholder becomes the sprite plate the design already uses, so a
loading row has the right shape and weight instead of a hole."
```

---

## Verification of the whole slice

After all three tasks, the user judges it on a physical device — that is where the symptoms were felt and the only place the fix counts. The three checks, in the user's words:

1. Switching tabs does not blank a screen that was already loaded.
2. Scrolling the 62-row Platinum timeline stays smooth, and taps respond immediately.
3. Sprites do not pop in a second time when scrolling back over them.

If any of the three is still wrong, that is the point to profile with Instruments rather than guess again — the cheap, findable causes will have been removed.

## Known gaps

- **Cold launch still spins.** Nothing is persisted, so a fresh start has nothing to draw. Fixing it is the deferred local-read-cache slice, not this one.
- **`rebuild()` has no mechanical test**, because it lives in the app target. Recorded in the spec. If it becomes a recurring source of bugs, the honest fix is extracting the derivation into a package with a test target — a separate change, not a smuggled one.
