# Native Chrome Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ShinyTracker iOS's hand-drawn tab bar with a real `TabView`, so the app renders in Liquid Glass and gains a live-hunt accessory you can count from on any screen.

**Architecture:** `AppShell.body` becomes a `TabView` bound to the existing `@State mode`, with four `Tab` declarations replacing ~90 lines of transcribed CSS. A `.tabViewBottomAccessory` reads the existing `liveHuntID` and calls the existing `bump(_:by:)`, so counting from the Dex flows through the offline write queue with no new plumbing. The deployment target rises to iOS 26, which the codebase can absorb because it contains zero availability guards.

**Tech Stack:** Swift 6, SwiftUI (iOS 26 SDK), XcodeGen, swift-testing.

**Spec:** `docs/superpowers/specs/2026-08-13-native-chrome-design.md`

## Global Constraints

- Deployment target is **iOS 26.0**. Every API used here is unconditional — **no `#available` guards anywhere**. The codebase currently has zero and must still have zero when this is done.
- The **app target (`ios/App/`) has no test target and must not gain one.** Do not add one, do not suggest one. Verification is `xcodebuild`, `swift test` on the packages, and the DEBUG preview harnesses.
- The four local packages (`ShinyTrackerKit`, `ShinyTrackerAPI`, `ShinyTrackerUI`, `ShinyTrackerAuth`) **do** have test targets. `swift test` must stay green in all four.
- `ios/ShinyTracker.xcodeproj` and `Secrets.xcconfig` are **gitignored and generated**. Never commit them. Regenerate with `xcodegen generate` run inside `ios/`.
- **Do not add a dependency.** Everything here is SwiftUI and the existing local packages.
- Nothing visual can be verified in this environment — no simulator control, no gestures, no screenshots. Report appearance claims as intent, never as verified.
- Reuse before writing: `SpriteTile`, `Typography`, `Palette`, `Metrics` already exist and must be used rather than re-implemented.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `ios/project.yml` | XcodeGen source of truth | deployment target 17.0 → 26.0 |
| `ios/App/ShinyTrackerApp.swift` | App shell, `AppMode`, tab bar | `TabView` replaces `ModeTabBar`; `AppMode` drops `.team`, gains `.you`; ~90 lines deleted |
| `ios/App/You/YouScreen.swift` | **New.** Account + sign-out | created in Task 3 |
| `ios/App/Hunt/LiveHuntAccessory.swift` | **New.** The bottom accessory | created in Task 4 |
| `ios/App/Hunt/HuntListModel.swift` | Hunt list state | gains a `liveRow` computed property |
| `ios/App/Dex/DexScreen.swift` | Dex grid | one stale comment naming `safeAreaInset` |
| `ios/ShinyTrackerUI/Sources/ShinyTrackerUI/DesignTokens.swift` | Design tokens | delete the four tab-bar tokens |
| `docs/TASKS.md` | Backlog | record shipped work + Team's tab removal |

---

## Task 1: Raise the deployment target to iOS 26

Done first and alone. Everything downstream needs it, and if raising it breaks something unrelated, that must be visible on its own rather than tangled with a UI rewrite.

**Files:**
- Modify: `ios/project.yml:8-9`

**Interfaces:**
- Consumes: nothing.
- Produces: an iOS 26 build environment. Tasks 2-5 rely on `TabView`'s Liquid Glass, `Tab(_:systemImage:value:)`, `.tabViewBottomAccessory`, and `.tabBarMinimizeBehavior` all being available unconditionally.

- [ ] **Step 1: Confirm the toolchain can build for iOS 26**

Run: `xcodebuild -version`

Expected: `Xcode 26.x`. If it prints anything lower, stop — the rest of this plan cannot be built and the human partner needs to know before any code changes.

- [ ] **Step 2: Confirm the codebase has no availability guards to update**

Run:
```bash
cd ios && grep -rn "#available\|@available" App ShinyTrackerKit/Sources ShinyTrackerAPI/Sources ShinyTrackerUI/Sources ShinyTrackerAuth/Sources --include="*.swift"
```

Expected: **no output.** If this prints anything, the guards must be evaluated before raising the floor — report it rather than deleting them blind.

- [ ] **Step 3: Raise the target**

In `ios/project.yml`, change:

```yaml
options:
  bundleIdPrefix: com.casperkarlsen
  deploymentTarget:
    iOS: "17.0"
```

to:

```yaml
options:
  bundleIdPrefix: com.casperkarlsen
  deploymentTarget:
    # iOS 26: the app is built around Liquid Glass and TabView's bottom accessory
    # (docs/superpowers/specs/2026-08-13-native-chrome-design.md). The codebase carries
    # zero availability guards precisely because the floor moves instead.
    iOS: "26.0"
```

- [ ] **Step 4: Regenerate and build**

Run:
```bash
cd ios && xcodegen generate && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. The app has not changed yet, so any failure here is the target raise alone.

- [ ] **Step 5: Verify the packages still resolve**

Run:
```bash
cd ios && for p in ShinyTrackerKit ShinyTrackerAPI ShinyTrackerUI ShinyTrackerAuth; do (cd $p && swift test 2>&1 | tail -2); done
```

Expected: four passing runs (47, 48, 15, 3 tests respectively). The packages declare their own platforms and are unaffected, so this is a regression check, not a change.

- [ ] **Step 6: Commit**

```bash
git add ios/project.yml
git commit -m "build(ios): raise the deployment target to iOS 26"
```

---

## Task 2: Replace the tab bar with a real TabView

**Files:**
- Modify: `ios/App/ShinyTrackerApp.swift` — `AppMode` (`:86-113`), `AppShell.body` (`:169-190`), delete `ModePlaceholder` (`:202-219`), `ModeTabBar` (`:228-253`), `pill(_:)` (`:257-280`), `profileTile` (`:284-303`)

**Interfaces:**
- Consumes: iOS 26 target from Task 1.
- Produces: `AppMode` with cases `.hunt`, `.nuzlocke`, `.dex` (`.team` removed, `.you` added in Task 3). `AppShell.body` is a `TabView` whose `selection` is `$mode` — Task 4 attaches `.tabViewBottomAccessory` to this same `TabView`.

- [ ] **Step 1: Remove the Team case from `AppMode`**

In `ios/App/ShinyTrackerApp.swift`, delete `case team = "Team"` from the enum, and delete its arm from both `accent` and `symbol`:

```swift
enum AppMode: String, CaseIterable, Identifiable {
    case hunt = "Hunt"
    case nuzlocke = "Nuzlocke"
    case dex = "Dex"

    var id: Self { self }

    var accent: Swatch {
        switch self {
        case .hunt: Palette.hunt
        case .nuzlocke: Palette.nuzlocke
        case .dex: Palette.dex
        }
    }

    /// System symbols standing in for the prototype's inline SVGs.
    var symbol: String {
        switch self {
        case .hunt: "sparkles"
        case .nuzlocke: "list.bullet.rectangle"
        case .dex: "square.split.1x2"
        }
    }
}
```

Leave `Palette.team` in `DesignTokens.swift` untouched — Team mode returns when it has a backend, and the swatch is its design, not dead code.

- [ ] **Step 2: Replace `AppShell.body`**

Replace the whole `body` (the `Group { switch mode … }` plus its `.safeAreaInset`) with:

```swift
    // A real TabView, not a hand-drawn bar: it renders in Liquid Glass on the iOS 26 SDK,
    // insets its own content (which is what the old safeAreaInset was compensating for), and
    // minimizes on scroll. `selection` is the same @State the switch used, so the DEBUG
    // preview harnesses that pass an initial mode still work unchanged.
    var body: some View {
        TabView(selection: $mode) {
            Tab(AppMode.hunt.rawValue, systemImage: AppMode.hunt.symbol, value: AppMode.hunt) {
                HuntScreen(model: hunts, library: library, newHunt: newHunt)
            }
            Tab(AppMode.nuzlocke.rawValue, systemImage: AppMode.nuzlocke.symbol, value: AppMode.nuzlocke) {
                NuzlockeScreen(model: nuzlocke)
            }
            Tab(AppMode.dex.rawValue, systemImage: AppMode.dex.symbol, value: AppMode.dex) {
                DexScreen(model: dex)
            }
        }
        // The selected tab keeps its mode colour — native chrome, not generic chrome.
        .tint(mode.accent.color)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
```

Keep every `@State`, both `init`s and the `#if DEBUG` init exactly as they are. Keep any `.onChange`/`.task` modifiers that were attached below `.safeAreaInset` — move them onto the `TabView`.

- [ ] **Step 3: Delete the dead shell code**

Delete these four declarations entirely, plus the `// MARK: - Tab bar` comment above `ModeTabBar`:

- `struct ModePlaceholder: View` — its only caller was the Team tab
- `struct ModeTabBar: View`
- `private func pill(_ candidate: AppMode) -> some View`
- `private var profileTile: some View`

- [ ] **Step 4: Build**

Run:
```bash
cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

If it fails with an unresolved reference to `ModePlaceholder`, `Radii.tabBar`, `Palette.tabBar`, `Palette.tabBarOpacity` or `Palette.tabBarBorder`, something outside the deleted block was still using it — report which, do not re-add the deleted code.

- [ ] **Step 5: Verify the preview harnesses still launch**

The three DEBUG harnesses construct `AppShell(preview:mode:)` with an explicit mode, which is now the `TabView` selection. Confirm the code path compiles by building the DEBUG configuration:

```bash
cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker -configuration Debug -destination 'generic/platform=iOS' build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/App/ShinyTrackerApp.swift
git commit -m "feat(ios): replace the hand-drawn tab bar with a real TabView"
```

---

## Task 3: The You tab

**Files:**
- Create: `ios/App/You/YouScreen.swift`
- Modify: `ios/App/ShinyTrackerApp.swift` — `AppMode`, `AppShell.body`

**Interfaces:**
- Consumes: `AppMode` and the `TabView` from Task 2. `AuthSession.signOut() async throws` and `AuthSession.userID: UUID?` from `ShinyTrackerAuth`.
- Produces: `AppMode.you`; `YouScreen(auth:)`.

Note `AppShell` currently receives `auth` only in `init(auth:)` and does not store it. This task adds a stored optional so the You tab can sign out, and so the preview harnesses (which have no session) still compile.

- [ ] **Step 1: Add the `.you` case**

In `AppMode`, add the case and its two arms:

```swift
    case you = "You"
```

```swift
        case .you: Palette.dex        // no mode colour of its own; borrows the calmest one
```

```swift
        case .you: "person.crop.circle"
```

- [ ] **Step 2: Store the session on `AppShell`**

Add the property beside the other `@State`s:

```swift
    /// Only the You tab needs it, and only to sign out. Optional because the three DEBUG
    /// preview harnesses construct a shell with no session at all.
    private let auth: AuthSession?
```

Set it in each initialiser: `self.auth = auth` in `init(auth:)`; `self.auth = nil` in `init(client:mode:userID:)` and in the `#if DEBUG` `init(preview:mode:)`.

In `init(auth:)`, the existing body delegates via `self.init(client:userID:)`. Swift does not allow assigning a stored property after a delegating `self.init`, so convert `init(auth:)` to set every property directly rather than delegating — or give `init(client:mode:userID:)` an `auth: AuthSession? = nil` parameter and pass it through. **Take the parameter approach**, it is the smaller change:

```swift
    init(auth: AuthSession) {
        self.init(client: APIClient(auth: .session(auth)), userID: auth.userID, auth: auth)
    }

    init(client: APIClient, mode: AppMode = .hunt, userID: UUID? = nil, auth: AuthSession? = nil) {
        // ... existing body unchanged ...
        self.auth = auth
    }
```

- [ ] **Step 3: Create `YouScreen`**

Create `ios/App/You/YouScreen.swift`:

```swift
import ShinyTrackerAuth
import ShinyTrackerUI
import SwiftUI

/// Account and sign-out. Deliberately minimal: the shiny-charm toggles stay in the Games tab,
/// where the new-hunt sheet already reads them from the same `GameLibraryModel`.
///
/// This screen exists because the app had no way to sign out at all — the old bar's profile tile
/// was decoration with no button behind it.
struct YouScreen: View {
    let auth: AuthSession?

    @State private var signingOut = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            ScreenBackground()
            List {
                Section("Account") {
                    LabeledContent("Signed in as", value: accountLabel)
                }
                Section {
                    Button(role: .destructive) {
                        signOut()
                    } label: {
                        if signingOut {
                            ProgressView()
                        } else {
                            Text("Sign out")
                        }
                    }
                    .disabled(auth == nil || signingOut)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    /// The user id is all the client holds — there is no profile fetch on this screen, and
    /// `GET /api/me` returns a username the shell does not currently load.
    private var accountLabel: String {
        auth?.userID?.uuidString ?? "Not signed in"
    }

    private func signOut() {
        guard let auth else { return }
        signingOut = true
        errorMessage = nil
        Task {
            do {
                try await auth.signOut()
            } catch {
                errorMessage = "Couldn't sign out — \(error.localizedDescription)"
            }
            signingOut = false
        }
    }
}
```

- [ ] **Step 4: Add the tab**

In `AppShell.body`, add a fourth `Tab` after Dex:

```swift
            Tab(AppMode.you.rawValue, systemImage: AppMode.you.symbol, value: AppMode.you) {
                YouScreen(auth: auth)
            }
```

- [ ] **Step 5: Build**

Run:
```bash
cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/App/You/YouScreen.swift ios/App/ShinyTrackerApp.swift
git commit -m "feat(ios): add a You tab with the app's first sign-out"
```

---

## Task 4: The live-hunt accessory

**Files:**
- Create: `ios/App/Hunt/LiveHuntAccessory.swift`
- Modify: `ios/App/Hunt/HuntListModel.swift` — add `liveRow`
- Modify: `ios/App/ShinyTrackerApp.swift` — attach `.tabViewBottomAccessory`

**Interfaces:**
- Consumes: the `TabView` from Task 2. `HuntListModel.liveHuntID: UUID?`, `.rows: [HuntRow]`, `.bump(_ id: UUID, by delta: Int)`. `SpriteTile(pokemonID:size:served:)` from `HuntCard.swift:315`. `HuntRow.name: String`, `.count: Int`, `.detail.pokemonID: Int`, `.detail.shinySpriteURL: String?`.
- Produces: `LiveHuntAccessory(model:onOpen:)`.

- [ ] **Step 1: Add `liveRow` to `HuntListModel`**

`liveHuntID` is stored but never resolved to a row anywhere — `HuntScreen.swift:249` compares ids inline. Add the lookup once, beside the other derived properties:

```swift
    /// The hunt the bottom accessory counts. `liveHuntID` can name a row that a refresh has
    /// since dropped, so this resolves rather than force-unwrapping — the accessory renders
    /// nothing when it comes back nil.
    var liveRow: HuntRow? {
        guard let liveHuntID else { return nil }
        return rows.first { $0.id == liveHuntID }
    }
```

- [ ] **Step 2: Create the accessory**

Create `ios/App/Hunt/LiveHuntAccessory.swift`:

```swift
import ShinyTrackerUI
import SwiftUI

/// The live hunt, docked above the tab bar on every screen — so a hunt can be counted while
/// browsing the Dex or a Nuzlocke run, without switching tabs.
///
/// `+` calls the same ``HuntListModel/bump(_:by:)`` the hunt card calls, which is the whole point:
/// the tap lands in the offline write queue, is coalesced with its neighbours, and carries an
/// idempotency key. Counting from here is offline-safe for free rather than by re-implementation.
///
/// Renders nothing when no hunt is live, so the chrome disappears rather than showing an empty
/// frame or nagging the user to start a hunt.
struct LiveHuntAccessory: View {
    let model: HuntListModel
    /// Switches the shell to the Hunt tab.
    let onOpen: () -> Void

    var body: some View {
        if let row = model.liveRow {
            HStack(spacing: 10) {
                Button(action: onOpen) {
                    HStack(spacing: 10) {
                        SpriteTile(
                            pokemonID: row.detail.pokemonID,
                            size: 28,
                            served: row.detail.shinySpriteURL
                        )
                        Text(row.name)
                            .font(Typography.summary)
                            .foregroundStyle(Palette.textPrimary.color)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(row.count.formatted())
                            .font(Typography.badge)
                            .foregroundStyle(Palette.textSecondary.color)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(row.name), \(row.count) encounters. Open Hunt.")

                Button {
                    model.bump(row.id, by: 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.hunt.color)
                .accessibilityLabel("Add one encounter to \(row.name)")
            }
            .padding(.horizontal, 14)
        }
    }
}
```

- [ ] **Step 3: Attach it to the TabView**

In `AppShell.body`, add below `.tabBarMinimizeBehavior(.onScrollDown)`:

```swift
        .tabViewBottomAccessory {
            LiveHuntAccessory(model: hunts) { mode = .hunt }
        }
```

- [ ] **Step 4: Build**

Run:
```bash
cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add ios/App/Hunt/LiveHuntAccessory.swift ios/App/Hunt/HuntListModel.swift ios/App/ShinyTrackerApp.swift
git commit -m "feat(ios): count the live hunt from any tab via the bottom accessory"
```

---

## Task 5: Retire the old bar's leftovers

**There is no bar-compensating padding to remove.** This was checked while writing the plan: the only place that would have had it, `DexScreen.swift:273-275`, is a comment explaining that the grid deliberately has *no* bottom padding because `safeAreaInset` already insets it. `HuntScreen.swift:438,444` is internal spacing inside an empty-state view (icon → title → message), not bar clearance.

So this task is small: one stale comment, four dead tokens, and the backlog. **Do not go hunting for padding to delete** — the audit is done, and removing legitimate spacing is the likeliest way to break a screen here.

**Files:**
- Modify: `ios/App/Dex/DexScreen.swift:273-275` (comment only)
- Modify: `ios/ShinyTrackerUI/Sources/ShinyTrackerUI/DesignTokens.swift:121-124,167`
- Modify: `docs/TASKS.md`

**Interfaces:**
- Consumes: everything from Tasks 2-4.
- Produces: nothing new.

- [ ] **Step 1: Update the stale Dex comment**

`DexScreen.swift:273-275` currently reads:

```swift
            // No bottom padding for the tab bar: `AppShell` insets this scroll view by the
            // bar's measured height with `safeAreaInset`, and adding the prototype's
            // `padding-bottom:104px` on top of that leaves a dead gap under the last row.
```

`safeAreaInset` no longer exists. Replace with:

```swift
            // No bottom padding for the tab bar: `TabView` insets its own content, and adding
            // the prototype's `padding-bottom:104px` on top of that leaves a dead gap under
            // the last row. The accessory, when a hunt is live, is inset by the same mechanism.
```

- [ ] **Step 2: Confirm no other screen compensated for the bar**

Run:
```bash
cd ios && grep -rn "safeAreaInset\|tab bar\|tabBar" App --include="*.swift"
```

Expected after Step 1: no reference to `safeAreaInset`, and no comment claiming a screen pads for the bar. If a hit appears in a file this plan has not touched, report it rather than editing it blind — it means the audit above missed a screen.

- [ ] **Step 3: Delete the dead tab-bar design tokens**

In `ios/ShinyTrackerUI/Sources/ShinyTrackerUI/DesignTokens.swift`, delete:

```swift
    public static let tabBar = Swatch(0x12121A)
    public static let tabBarOpacity = 0.82
    public static let tabBarBorder = Swatch(0x2A2A36)
```

and from `Radii`:

```swift
    public static let tabBar: CGFloat = 24
```

They described the material of a bar that no longer exists. Keep `Palette.team`.

- [ ] **Step 4: Verify nothing else used them**

Run:
```bash
cd ios && grep -rn "tabBar" App ShinyTracker*/Sources --include="*.swift"
```

Expected: **no output.** Any hit must be resolved before committing.

- [ ] **Step 5: Build and run every package test**

Run:
```bash
cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker -destination 'generic/platform=iOS' build 2>&1 | tail -3
for p in ShinyTrackerKit ShinyTrackerAPI ShinyTrackerUI ShinyTrackerAuth; do (cd $p && swift test 2>&1 | tail -2); done
```

Expected: `** BUILD SUCCEEDED **` and four passing test runs. `ShinyTrackerUI` is the one that actually changed, so its 15 tests are the meaningful check here.

- [ ] **Step 6: Update the backlog**

In `docs/TASKS.md`:

- Add to **✅ Shipped — iOS**: a line recording that the shell is native — `TabView` in Liquid Glass, minimize-on-scroll, and a live-hunt accessory that counts from any tab through the existing write queue.
- Under **⏳ Backlog → iOS**, amend the Team mode entry to record that its *tab* was removed with this change and returns when the backend does.
- Add a backlog entry for the deferred half: `NavigationStack`, toolbars and `searchable` inside the screens, noting `searchable` would replace the Dex's custom filtering.

- [ ] **Step 7: Commit**

```bash
git add ios/App ios/ShinyTrackerUI docs/TASKS.md
git commit -m "refactor(ios): retire the old tab bar's leftover tokens and comments"
```

---

## Final verification

After Task 5, before opening a PR:

- [ ] `cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker -destination 'generic/platform=iOS' build` → `** BUILD SUCCEEDED **`
- [ ] All four packages green under `swift test`
- [ ] `grep -rn "#available\|@available" ios/App ios/ShinyTracker*/Sources --include="*.swift"` → no output (the constraint held)
- [ ] `git status` shows no `ShinyTracker.xcodeproj` or `Secrets.xcconfig` staged
- [ ] Run `code-reviewer` on the full branch diff, per `CLAUDE.md`

**Then hand back to the owner**, stating plainly that nothing visual was verified. The things only they can judge, on a device running iOS 26:

1. Does the bar actually render as Liquid Glass, and does it minimize on scroll down?
2. Does the accessory appear only when a hunt is live, and does its `+` increment from the Dex tab?
3. Does any screen now have a gap or a clipped last row where the old padding was removed?
4. Does sign-out in the You tab return to the login screen?
