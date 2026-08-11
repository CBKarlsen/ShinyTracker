# ShinyTracker — UX/QA Critique

## Methodology
Explored the app via Playwright (logged in as a fresh account and a seeded account).
Audited every screen: Login, Register, Dashboard, New Hunt modal (3 steps), Game Library,
Historic Hunts, Living Dex, Stats, Odds Calculator, Method Library.

---

## 1. Critical Issues (Broken or Blocking)

### 1a. "No available methods found" is a dead end with no recovery path
**Before the fix implemented during this session** the message was identical for three very
different states:
- User owns 0 games → they don't know they need to add one
- User owns games, Pokémon not in them → they need a different game
- Pokémon is genuinely shiny-locked → nothing they can do

A new user creating their first hunt hits this wall immediately (Pikachu is not in
Sword/Shield encounter data), sees a vague error, and has no path forward.

**Status:** Partially fixed — contextual messages + CTA buttons now navigate to Game Library.
Still needs: back-end distinction between "not available in owned games" vs genuinely shiny-locked.

### 1b. Game requirement is entirely implicit
The app silently gates all hunt methods behind game ownership with zero upfront explanation.
There is no tooltip, no onboarding callout, no help text on the Dashboard that says
"Add games you own to unlock hunt methods." The first experience for any new user is:
land on Dashboard → New Hunt → pick Pokémon → hit a wall.

**Recommendation:** One sentence on the empty Dashboard state: *"Add games you own in the
Game Library to start tracking hunts."*

### 1c. Session persistence is all-or-nothing localStorage
JWT and userId sit in `localStorage` with no expiry logic in the frontend. A tab left open
indefinitely will eventually make API calls with an expired token and silently fail — the
UI shows no "session expired" state, it just refuses to load data. Needs an interceptor
that detects 401 responses and redirects to login.

### 1d. All API errors are silently swallowed
Every `catch { /* ignore */ }` block in the frontend means failed requests produce no
user-visible feedback. A network blip during encounter increment, a failed hunt creation,
a failed shiny charm toggle — all are silent. The user has no idea if their action was
saved or lost.

---

## 2. UX Friction Points

### 2a. New Hunt modal: 3-step flow for a 2-step task
Step 1 = pick Pokémon, Step 2 = pick method, Step 3 = confirm. The confirm step just
repeats information already visible in step 2 (game, method, odds). It adds a click with
no new information. Power users doing multiple hunts per session feel this every time.

**Recommendation:** Collapse step 3 into step 2 — show odds inline as the method is
highlighted, then let "Start hunt" be available directly. Reserve the confirm step for
edge-case methods that need extra parameters (e.g., phase hunting).

### 2b. No keyboard shortcut to open New Hunt
SPACE is wired to increment encounters — good. But there is no keyboard shortcut to open
the New Hunt modal, navigate between tabs, or trigger "Found it!". Power users who want
to stay on keyboard hit a dead end immediately after the SPACE shortcut.

**Recommendation:** `N` → open New Hunt, `F` → Found it! (with a guard modal), number
keys or arrow keys to switch active hunts when multiple are pinned.

### 2c. The progress bar / step indicator in the modal is cosmetic only
Three colored pills show step progress but are not interactive — you cannot click pill 1
to jump back to Pokémon selection. Users have to find and click "Change" or "Back".

### 2d. No inline odds preview when browsing methods in step 2
The opt-row shows game, method name, avg seconds, and base rolls — but not the actual
shiny odds. A user comparing Masuda Method (6r) vs Soft Reset (1r) has to mentally
calculate `4096 / rolls` or open the Odds Calculator in another tab.

**Recommendation:** Add a `1 / N` odds column to the opt-row, calculated live.

### 2e. "Log phase" has no confirmation or visible outcome
Clicking "Log phase" does something (increments `phase_count`) but the button gives no
visual feedback and there is no toast/notification. Users don't know if the click
registered.

### 2f. Removing a game is not confirmed
Clicking an owned game immediately removes it. If a user has hunts tied to that game,
losing the game association is silent and confusing. A single "Are you sure? This removes
method data from X active hunts." confirmation would prevent accidental data loss.

### 2g. Living Dex Pokémon are click-targets with no affordance
The dex grid cells look like static images. Nothing indicates they are clickable or that
clicking toggles ownership. No hover state documentation, no tooltip. First-time users
cannot discover this by looking.

### 2h. Stats page "Method Breakdown" shows "Unknown" for Masuda Method hunts
Hunts using the synthetically injected Masuda Method entry store the method string
differently than the backend query expects, so the breakdown bins them as "Unknown".
This is a data quality bug — all Masuda Method hunts are miscategorised.

---

## 3. Persona Critique — Hardcore Shiny Hunter

> *"I have 847 hours in Sword/Shield. I do 6-hour Masuda sessions. I track encounter pace,
> lucky-roll distribution, and phase counts for every Pokémon. I use a clicker, a timer,
> and a notebook. ShinyTracker is supposed to replace the notebook."*

### What the app gets right
- **SPACE to count** — the single most important interaction is keyboard-accessible. ✓
- **Masuda Method auto-injected** — no manual setup for Breeding hunts. ✓
- **Shiny Charm applied to odds** — accounts for the most common boost correctly. ✓
- **Historic Hunts log** — gives an audit trail of completed hunts. ✓

### What a hardcore hunter will immediately notice is missing

**No encounter rate / pace tracking.**
The dashboard shows cumulative encounter count and a session timer, but no *encounters
per hour* calculation. A grinder's primary metric is not "how many" but "how fast" — are
they averaging 220/hour or have they slowed to 180? No chart, no rolling average, nothing.

**No multi-hunt parallel tracking.**
Serious hunters often run two DS units simultaneously (MMO Masuda + another game).
The dashboard has a single "pinned" hunt slot. There is no way to switch between multiple
active hunts efficiently.

**No phase-based odds view.**
When phase hunting (e.g., hunting a shiny in a chain where you must encounter the
evolved form), each phase resets the encounter count but the cumulative odds compound.
The app logs phases but the Dashboard counter just keeps going — there is no "phase N:
M encounters, cumulative P%" breakdown visible at a glance.

**Timer is session-only, not persistent.**
If you close the tab mid-hunt, the session timer resets. Total time hunted is tracked
server-side (it persists), but the in-page timer always starts at 0:00. A hunter who
pauses for lunch and comes back sees a misleading "0:07" session time while the card
shows "3h 40m hunted" below it. These two numbers coexist on the same card and
contradict each other visually.

**No sound or vibration on "found it".**
Every shiny hunter uses audio cues — the shiny sparkle sound when an encounter begins.
There is no audio feedback anywhere in the app. A simple optional "ding" on Found It
confirmation, or a notification sound, would match physical hunting muscle memory.

**No "shiny odds threshold" alert.**
At 1× odds (4096 encounters at 1/4096), a hunter is "due" statistically — many tools
show a "you've passed the average" indicator. At 2× odds, 3×, etc. These milestones are
psychologically significant to the community. The app shows cumulative % but no visual
milestone markers on the encounter card.

**Search requires typing — there's no quick-add from history.**
A hunter returning to re-hunt a Pokémon (e.g., hunting another shiny Eevee) must type
the name again from scratch. No "recent hunts" shortcut or favourite list.

**No Pokémon Go / HOME transfer tracking.**
Many modern collectors acquire shinies via trade or HOME transfer. The app has an
`acquisition_type` field (HUNTED / EVOLVED / MANUAL_OVERRIDE / TRADED) but none of
these are surfaced in the UI. "Found it!" always implies HUNTED. There is no "I traded
for this" or "I evolved this" option visible to the user.

**Living Dex toggle is discoverable only by accident.**
The grid is the primary tool for checking collection completeness — but clicking a cell
to mark ownership is invisible. There is no "click to mark as owned" label, no hover
cursor change visible in the CSS, no empty-state tooltip.

---

## 4. QA Findings — Bugs and Inconsistencies

| # | Severity | Description |
|---|----------|-------------|
| B1 | High | Pikachu + Sword/Shield → "No methods" even though Masuda Method should be injected if Pikachu is in `pokemon_availability` for SwSh. Data gap to investigate. |
| B2 | High | All API errors silently swallowed (`catch { /* ignore */ }`). Failed saves produce no feedback. |
| B3 | Medium | Stats "Method Breakdown" shows "Unknown" for all hunts using the synthetic Masuda entry. |
| B4 | Medium | Timer resets to 0:00 on page reload / tab close, conflicting with the persistent "total_time_seconds" shown on the same card. |
| B5 | Medium | Log phase has no visual feedback — no toast, no counter update animation. |
| B6 | Low | Register error message says "Invalid credentials or email already taken" (same message as login failure). Should say "Email already registered." |
| B7 | Low | New Hunt modal step indicator pills are purely decorative — not keyboard-accessible, not interactive, no ARIA labels. |
| B8 | Low | Game removal is instant with no confirmation; associated hunt data silently loses its game context. |
| B9 | Low | The sidebar username always shows "Trainer" — the registered username is never displayed. |
| B10 | Low | Odds Calculator method dropdown shows all methods for a game even if user doesn't own that game — inconsistent with New Hunt modal which filters by owned games. |

---

## 5. Positive Signals

- Dark theme, typography, and color palette are premium and consistent.
- `SPACE` for encounter increment is the right instinct.
- The three-tier empty state (Dashboard / New Hunt modal / Game Library) is *almost*
  right — it just needs the messages to guide rather than dead-end.
- Odds calculation with Shiny Charm is correct and shown at the right moment (step 3).
- Sidebar badge count for active hunts is a thoughtful detail.

---

## Priority Recommendations

1. **Fix silent API error handling** — wrap all fetches in a toast/notification layer.
2. **Add encounter pace (enc/hr)** to the active hunt card — the most-wanted power user metric.
3. **Collapse step 3 of New Hunt** into step 2 to remove a redundant click.
4. **Add inline odds to method rows** in step 2 so users can compare without the calculator.
5. **Show username in sidebar** instead of hardcoded "Trainer".
6. **Add a "recently hunted" quick-pick** to the New Hunt modal search.
7. **Fix Stats Method Breakdown** for synthetic Masuda entries.
8. **Milestone markers on the encounter card** (1× odds, 2× odds, etc.) to match community expectations.
