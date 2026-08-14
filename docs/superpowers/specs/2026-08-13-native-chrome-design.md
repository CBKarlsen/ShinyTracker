# Native iOS chrome: the app shell — design

**Status:** proposed 2026-08-13.

The iOS app draws its own shell. `ModeTabBar` is a hand-built `HStack` of pills over
`.ultraThinMaterial`, and its comments name their source: `// blur(24px)`,
`// linear-gradient(135deg,#26262e,#1a1a24)`, `// the prototype hardcodes "T"`. It is a web design
transcribed into SwiftUI.

Counted across `App/`, the app uses **zero** `NavigationStack`, `navigationTitle`, `toolbar`,
`searchable` and `TabView`. It reaches for Apple's components only where a `List` or `.sheet` was
unavoidable. That is why it does not feel like an iOS app, and why the bar is not Liquid Glass:
`.ultraThinMaterial` is a frosted blur from iOS 15, with no specular edge, no refraction and no
response to what passes beneath it.

Nothing is blocking the fix. Xcode 26.6 builds against the iOS 26 SDK and the app does not set
`UIDesignRequiresCompatibility`, so native components render in Liquid Glass **today**. The app
simply never asks for them.

This spec covers the **shell only** — the tab bar and what sits above it. Adopting `NavigationStack`,
toolbars and `searchable` inside each screen is a separate, larger piece of work.

---

## Scope

**In:** replacing `ModeTabBar` with a real `TabView`; the bottom accessory carrying the live hunt;
the tab set; raising the deployment target to iOS 26.

**Out:** navigation chrome inside the screens (nav bars, toolbars, `searchable`); any change to
Hunt, Dex or Nuzlocke screen internals beyond deleting bottom padding the tab bar no longer needs;
Team mode.

## 1. The shell

`AppShell.body` today is a `Group` switching on `mode`, with `.safeAreaInset(edge: .bottom)`
attaching `ModeTabBar`. It becomes a `TabView` with a `selection` binding to the same
`@State private var mode: AppMode`, so both `init(client:mode:userID:)` and the three DEBUG preview
harnesses keep working unchanged — they already pass an initial `mode`.

Deleted outright:

| Symbol | Lines | Why |
|---|---|---|
| `ModeTabBar` | `ShinyTrackerApp.swift:228-253` | `TabView` replaces it |
| `pill(_:)` | `:257-280` | `Tab` replaces it |
| `profileTile` | `:284-303` | decoration: no `Button`, no action, `accessibilityHidden(true)` |
| `ModePlaceholder` | referenced `:181` | its only caller was the Team tab |

That is roughly 90 lines of transcribed CSS removed for four `Tab` declarations.

`.tabBarMinimizeBehavior(.onScrollDown)` makes the bar shrink to a pill as content scrolls. This
does more to signal "iOS 26" than the material does, and it gives the content back its full height.

### Keeping the app's identity

Native chrome must not mean generic chrome. `AppMode.accent` survives as `.tint()` on the
`TabView`, so the selected tab still carries Hunt-purple, Nuzlocke-red and Dex-blue.
`ScreenBackground()` stays behind the `TabView` — glass refracts what is beneath it, and over a flat
black the effect is invisible. `.preferredColorScheme(.dark)` is unchanged.

## 2. The tab set

`AppMode` loses `.team` and gains `.you`:

| Tab | Symbol | Screen |
|---|---|---|
| Hunt | `sparkles` | `HuntScreen` (unchanged) |
| Nuzlocke | `list.bullet.rectangle` | `NuzlockeScreen` (unchanged) |
| Dex | `square.split.1x2` | `DexScreen` (unchanged) |
| You | `person.crop.circle` | `YouScreen` (new) |

**Team is dropped** until it has a backend. A tab that opens "coming soon" is the least
Apple-feeling thing in the app. Its enum case, palette entry and placeholder screen go; the backlog
entry in `docs/TASKS.md` already records that Team needs a backend before it needs a tab.

**`YouScreen` is deliberately minimal:** the signed-in account and a sign-out button calling the
existing `AuthSession.signOut()`. The app currently has **no way to sign out at all** — this closes
that gap as a side effect rather than as its own project. The shiny-charm toggles stay in the Games
tab, where they already work and where the new-hunt sheet reads them.

## 3. The accessory

`.tabViewBottomAccessory` renders `LiveHuntAccessory` above the tab bar on every screen, the way
Music's mini-player does.

It reads `hunts.liveHuntID` — an existing first-class concept, maintained at six seams in
`HuntListModel` — and resolves it to a `HuntRow`. When there is no live hunt it renders `EmptyView`,
so the accessory disappears rather than showing an empty frame or an advertisement to start a hunt.

Contents, all reusing what exists:

- `SpriteTile(pokemonID:size:served:)` from `HuntCard.swift:315` — already handles the 404 and
  loading cases by keeping its gradient tile behind the image.
- `row.name` for the title, matching the active hunt card. Nicknames are deliberately **not** used:
  `HuntScreen.swift:391` shows them in History only, and the accessory should match the card it
  mirrors, not the history row.
- `row.count`, formatted as the cards format it.
- A `+` button calling `hunts.bump(id, by: 1)`.

Wiring `+` to `bump` rather than to a new path is the whole point: counting from the Dex then goes
through the existing write queue, so it is offline-safe, coalesced and idempotent **for free**. No
new networking, no new persistence, no new failure mode.

Tapping the row sets `mode = .hunt`.

## 4. Insets

`TabView` insets its content automatically. That deletes the problem documented at
`ShinyTrackerApp.swift:171` — the comment explains that a ZStack overlay clipped the last card and
`safeAreaInset` was the fix — and the hand-tuned padding it forced at `DexScreen.swift:274`. Both
comments go with the code they justify.

Every screen's own `padding(.bottom, …)` is reviewed against the new insets and removed where it was
compensating for the old bar. Padding that is internal spacing (`GamesTab.swift:200`,
`SpeciesSheet.swift:280`) stays.

## 5. Deployment target

`project.yml`: `iOS: "17.0"` → `"26.0"`, then regenerate the project with XcodeGen.

The codebase contains **zero** `#available` and `@available` annotations, so nothing is orphaned and
no compatibility branch is needed anywhere. Every API in this spec — `tabViewBottomAccessory`,
`tabBarMinimizeBehavior`, Liquid Glass on `TabView` — becomes unconditional.

**Hard precondition:** the target iPhone must be running iOS 26 or the build will not install.

## Error handling

The accessory has one failure mode worth naming: `+` can be tapped for a hunt that is being removed
concurrently (found, abandoned, or dropped by a refresh). `bump` already handles an unknown id — it
is the same call the card's `+` makes, and `drop(_:)` clears `liveHuntID` — so the accessory needs
no guard of its own beyond resolving `liveHuntID` to a row each render and rendering nothing when it
does not resolve.

Sign-out failure in `YouScreen` surfaces inline; `signOut()` is `async throws`.

## Testing

The app target has **no test target and must not gain one** — that constraint is unchanged.

Nothing in this spec is worth extracting to a testable package. The accessory adds no logic: it
reads an existing published id and calls an existing method. Inventing a `LiveHuntPolicy` to hold
`liveHuntID != nil` would be ceremony, not coverage.

Verification is therefore:

- `xcodebuild` against a device destination — proves the iOS 26 APIs compile and the target raise is
  clean.
- `swift test` in all four packages — proves nothing regressed in `ShinyTrackerKit`,
  `ShinyTrackerAPI`, `ShinyTrackerUI`, `ShinyTrackerAuth`. None of them should be touched.
- The DEBUG preview harnesses (`HuntPreview`, `DexPreview`, `NuzlockePreview`) still launch, which
  exercises the `TabView` selection binding against canned data.

**Explicitly not verifiable here:** anything visual. No agent in this environment can drive the
simulator, inject gestures or capture screenshots — the same standing limitation recorded in the
sub-project B spec, where the queue could only be exercised by airplane mode on a real phone.
Whether the glass looks right, whether the accessory crowds the bar on a small screen, and whether
minimize-on-scroll feels good are the owner's judgement on device. Claims in this spec about
appearance are design intent, not verified results.

## Deferred

- **`NavigationStack`, toolbars and `searchable` inside the screens.** The larger half of "use
  Apple's components". `searchable` in particular would replace the Dex's custom filtering.
- **Team mode**, and its tab, until a backend exists.
- **Richer `YouScreen`** — profile editing, stats, charm toggles moved in from Games.
- **The accessory's expanded placement.** iOS 26 offers `TabViewBottomAccessoryPlacement`, letting
  the accessory render larger when the bar is minimized. Worth revisiting once the inline version
  has been used on device.

## Related

- `docs/superpowers/specs/2026-08-13-offline-write-queue-design.md` — the write queue the
  accessory's `+` reaches through `bump`, and the standing note on what cannot be verified here
- `docs/TASKS.md` — Team mode's backlog entry
- `App/ShinyTrackerApp.swift` — the whole shell being replaced
