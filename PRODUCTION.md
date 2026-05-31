# ShinyTracker — Production Readiness Checklist

The goal: get ShinyTracker off `localhost` and into a state where **you can use it daily to
hunt**, safely, from any device. This is distinct from `TASKS.md` (forward-looking
completionist *features*) — this doc only tracks what blocks real-world use.

Ordered by priority. Don't start a lower tier until the tier above is green.

Status: ☐ todo · ◐ partial · ✅ done

Legend for effort: **S** < 1h · **M** a few hours · **L** a day+

---

## P0 — Deploy blockers (the app literally can't run off your machine)

- [x] ✅ **Centralize the API base URL.** Done — `frontend/src/config.ts` exports
      `API_BASE = import.meta.env.VITE_API_URL ?? "http://localhost:8080"`; all 19 call-site
      files now reference it (incl. 4 admin files that used a local `const API`). Added
      `vite-env.d.ts` typing (`VITE_API_URL?: string`) and `frontend/.env` gitignored.
- [x] ✅ **Read `PORT` from env in the backend.** Done — `backend/cmd/api/main.go` now does
      `port := os.Getenv("PORT")` with an `8080` fallback; `os` imported.
- [x] ✅ **Pick + configure hosting.** Decided: **Railway** for both services. Added
      `backend/Dockerfile`, `frontend/Dockerfile` (+ `nginx.conf.template` so the SPA binds
      `$PORT`), `.dockerignore`s, and a full `DEPLOY.md` walkthrough. ⚠️ Images not built
      locally (Docker daemon down) — Railway builds them remotely; underlying `go build` and
      `npm run build` are both verified green. DB instance choice deferred to P1.
- [x] ✅ **Add `.env.example` files.** Done — `backend/.env.example` (`DATABASE_URL`,
      `JWT_SECRET`, `PORT`) and `frontend/.env.example` (`VITE_API_URL`, no-trailing-slash note).

## P1 — Security must-fix before it's on the public internet

- [ ] **Require `JWT_SECRET`; remove the dev default.** `backend/internal/api/auth.go:21`
      falls back to `"super_secret_default_key"`. In prod that = anyone can forge a token for
      any account. Fail-fast (`log.Fatal`) if the env var is empty when not in dev.
      *Effort: S.*
- [ ] **Lock down CORS.** `backend/internal/api/router.go:15` allows
      `{"http://localhost:5173", "*"}`. The `"*"` must go in prod — restrict to your deployed
      frontend origin (drive it from an env var). *Effort: S.*
- [ ] **Decide DB posture.** You're pointed at the **shared dev Supabase** instance. For
      personal-prod use that's probably fine, but: confirm row-level isolation by `user_id`,
      take a backup before go-live, and rotate the DB password if it's ever been shared.
      *Effort: S–M.*
- [ ] **Force HTTPS** end to end (host-provided certs handle this; just verify the API base
      uses `https://`, not `http://`). *Effort: S.*

## P2 — Hunt-reliability bugs (these bite you mid-session)

**Live-tested 2026-05-31** via Playwright against a fresh account (qa_tester) +
SV + a Pikachu Mass Outbreak hunt. The critique was largely stale — most items are
already fixed. Verified statuses below.

- [x] ✅ **B2 — Silent API errors — FIXED.** Forced a PATCH 500 mid-hunt: app showed a
      **"Sync failed — clicks weren't saved" toast** *and* rolled the optimistic count back
      to the server-confirmed value. Critique's #1 item is done for the core increment path.
      (Evidence: `b2-sync-failed-toast.png`.)
- [x] ✅ **1c — Expired-token (401) handling — FIXED & verified.** Added shared
      `utils/authedFetch.ts` (injects auth header, on 401 calls `onSessionExpired` + throws
      `SessionExpiredError`); wired into `Dashboard.tsx` (the live increment/heartbeat/complete
      PATCHes + fetch), `useHunts.ts`, and `HeroHunt.tsx`. Forced a 401 on increment →
      token cleared + redirected to Login, generic toast suppressed. *Minor follow-up: the
      "session expired" message doesn't persist onto the login screen (Dashboard unmounts).*
- [x] ✅ **B4 — Session timer persists across reload — FIXED & verified.** `HeroHunt.tsx`
      persists session start in `localStorage` keyed by hunt id (+ paused flag), cleared on
      complete. Verified: timer survived multiple reloads + a re-login (read 11:35, not 00:00).
- [x] ✅ **B3 — Masuda "Unknown" in Stats — FIXED (verified).** Completed a Grookey →
      Sword/Shield **Masuda Method** hunt; Stats Method Breakdown showed "Masuda Method 1",
      not "Unknown". Synthetic Masuda entries now bin correctly. No fix needed.
- [x] ✅ **B9 — Sidebar username — FIXED.** Sidebar renders "qa_tester", not "Trainer".

### Also confirmed fixed while testing (were in CRITIQUE)
- ✅ **1a/1b — gameless dead-end:** New Hunt now shows "You haven't added any games yet" +
  a **"Go to Game Library →"** CTA + a "Use custom method" escape — not a vague wall.
- ✅ **2a/2d — New Hunt modal:** routes show **inline odds + ETA** (1/682, 1/1024, 1/4096)
  with method params inline; effectively a 2-step flow now.

### New issues found this pass (not in CRITIQUE)
- [x] ✅ **Dashboard live odds now method-aware — FIXED & verified.** Root cause: the create
      path persisted `hunt_parameters: {}` (huntParams never initialized from the route's
      defaults), so `calculateOdds` fell back to base 4096. Fix: `defaultParamsFor()` seeds
      params on hunt creation + a defensive fallback on the dashboard. Verified: a fresh SV
      outbreak hunt shows 1/4,096 at 0 defeats and drops to **1/682** when defeats→60+ &
      sparkling→3, live. Code-review caught (and we fixed) a regression where seeding defaults
      for *chain-based* methods (radar/SOS/dexnav) would have disabled their encounter-driven
      odds — `defaultParamsFor` now only seeds outbreak/sandwich.
      **⚠️ Product decision still open (see below): best-achievable vs current-state odds.**
- [x] ✅ **"Found it!" confirmation guard — FIXED & verified.** New `ui/ConfirmDialog.tsx`;
      "Found it!" now prompts "Mark <pokemon> as found? This completes the hunt." (Enter/Esc).
- [ ] ⚠️ Minor (open): top-bar "Total Hunted 0m" vs hunt-card "total · 1m" disagree while
      hunting; "session expired" toast doesn't carry onto the login screen. Both cosmetic.

### ⚠️ Open product decision — odds semantics (surfaced by the dynamic-odds fix)
The dashboard now shows **current-state** odds (a brand-new SV outbreak hunt at 0 defeats is
genuinely 1/4,096, improving as you grind). But the **New Hunt route picker** shows
**best-achievable** odds (1/682) — it ranks routes using the Go backend's
`DefaultParams = {defeated_count:60, sparkling_power:3}`. So the picker says "Mass Outbreak
1/682" while the freshly-started card says 1/4,096 until you set your real defeats. Both are
"correct" but the gap can confuse. Decide how to reconcile: (a) make the picker reflect the
params you'll start with / label its odds as "best achievable", or (b) default new outbreak
hunts to a chosen baseline. Not a blocker — flagged for a UX call.

## P3 — Polish (defer until you've actually hunted a few times)

Pulled from `CRITIQUE.md` §2–3; none block use.

- [ ] Encounter pace (enc/hr) on the active hunt card — top power-user metric.
- [ ] Inline `1/N` odds on New Hunt method rows (avoid the calculator round-trip).
- [ ] Collapse New Hunt step 3 into step 2.
- [ ] Milestone markers (1×/2×/3× odds) on the encounter card.
- [ ] Optional "ding" / sound on Found It.
- [ ] "Recently hunted" quick-pick in New Hunt search.
- [ ] Confirm-on-remove for owned games (B8); Log-phase feedback (B5); register error copy (B6).

## Data correctness (parallel track — see TASKS.md "Next up")

- [ ] **Shiny-lock accuracy audit.** Lock dataset (`backend/seeds/shiny_locks.json`) is a
      ~50–60% starter set; some Pokémon show wrong lock states until verified vs
      Bulbapedia/Serebii, then re-seed via `cmd/seed_shiny_locks`. Affects trust, not uptime.

---

## Suggested go-live sequence

1. **P0** → app runs on a real URL (still effectively private).
2. **P1** → safe to leave reachable on the internet.
3. **P2** → reliable enough for a real 6-hour hunt session.
4. Start hunting. Knock out **P3** as the friction annoys you.
5. **Shiny-lock audit** whenever; it only affects dex-state accuracy.

> Re-verify P2 items against the live code first — `CRITIQUE.md` predates some fixes
> (401 handling and username storage already partially landed).
