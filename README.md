# ShinyTracker

Track Pokémon shiny hunts: start a hunt, count encounters, mark it found, build a shiny
Living Dex. Three clients over one Go API — a React web app, a native iOS app, and a
Nuzlocke mode that rides the same data.

This file is the entry point. Everything below is either the command you need or a link to
the document that owns the detail.

## Layout

| Path | What it is | Toolchain |
|---|---|---|
| `backend/` | Go API — chi router, raw pgx SQL, no ORM | Go 1.26 |
| `frontend/` | React 19 + TypeScript + Vite web app | **Node 20+** |
| `ios/` | Native SwiftUI app + 4 local Swift packages + a Live Activity widget | Xcode 26, iOS 26 |
| `shared/odds_anchors.json` | The odds contract all three engines are tested against | — |
| `docs/` | Deployment, auth setup, domain audits | — |

The database is Supabase-hosted PostgreSQL (AWS eu-central-1). There is no migration
framework: `backend/schema.sql` is the DDL and `backend/migrations/*.sql` are applied by
hand.

## Run it locally

**Prerequisites:** Go 1.26+, Node 20+, and for iOS: Xcode 26 with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

> **Node 20 is a hard requirement, not a suggestion.** The Vite 8 toolchain crashes on
> Node 19 and below, and `tsc -b` silently no-ops rather than erroring — so an old Node
> looks like a passing build. Check with `node --version` before you debug anything else.

```bash
# 1. Backend  →  http://localhost:8080
cd backend
cp .env.example .env          # fill in DATABASE_URL and SUPABASE_URL
go run ./cmd/api

# 2. Frontend →  http://localhost:5173
cd frontend
cp .env.example .env          # VITE_API_URL, VITE_SUPABASE_*
npm install && npm run dev

# 3. iOS
cd ios
cp App/Config/Secrets.example.xcconfig App/Config/Secrets.xcconfig   # fill in, then:
xcodegen generate             # REQUIRED — the .xcodeproj is gitignored and generated
open ShinyTracker.xcodeproj
```

`xcodegen generate` is the step people miss. `ios/project.yml` is the source of truth; the
`.xcodeproj` is a build artifact. Re-run it after any change to `project.yml` **or after
adding a Swift file**, or the new file won't be in the target.

Auth setup (Supabase providers, redirect URLs, the Apple/Google specifics): **[docs/AUTH-SETUP.md](docs/AUTH-SETUP.md)**.

## Test it

CI (`.github/workflows/ci.yml`) runs exactly these on every push and PR. Run them locally
before pushing and CI holds no surprises.

```bash
# Go — internal/calc is the well-covered part; internal/api is not (see Known gaps)
cd backend && go build ./... && go vet ./... && go test ./... -cover

# Web — there is NO unit test runner here, by decision. Do not add one without asking.
cd frontend && npx tsc -b && npm run build && npm run check:anchors && npm run lint

# Swift — 138 tests across the four packages
cd ios/ShinyTrackerKit  && swift test
cd ios/ShinyTrackerAPI  && swift test
cd ios/ShinyTrackerUI   && swift test
cd ios/ShinyTrackerAuth && swift test

# iOS app target (compiles only — it has no test target)
cd ios && xcodebuild -project ShinyTracker.xcodeproj -scheme ShinyTracker \
  -destination 'generic/platform=iOS Simulator' -configuration Debug build
```

`npm run check:anchors` is not a formality. `shared/odds_anchors.json` is the single source
of truth for every shiny-odds formula, and Go, Swift and TypeScript each assert against it
independently. Without it, three hand-maintained engines drift and the odds a user sees
depend on which client they opened.

## Deploy it

Railway, two services, per-folder Dockerfiles. The full runbook — including the
non-obvious parts (IPv6-only direct DB host, `VITE_*` being build-time not run-time, the
three places the frontend URL must agree) — is **[docs/DEPLOY.md](docs/DEPLOY.md)**.

Deploys trigger on push to `master`. CI runs on the same push but does **not** gate the
deploy — Railway does not wait for it. Check the CI result before treating a deploy as good.

Health check: `GET /healthz` returns `{"status":"ok"}`, or 503 when the DB is unreachable.

### Seeding and migrations

Commands and their required order are in **[backend/CLAUDE.md](backend/CLAUDE.md)**. Two
rules that will bite you:

- **`cmd/seed` runs LAST.** Anything else afterwards leaves `method_availability` empty.
- Seed tools are deliberately not in the deployed image. Data operations run from a laptop
  against the production `DATABASE_URL`.

## Domain accuracy

The odds engine is the product. `docs/audit/ODDS_DOMAIN_REVIEW.md` tracks every known
defect and its status, and `docs/audit/` holds a per-generation data audit.

The warning in [CLAUDE.md](CLAUDE.md) is worth repeating: **passing tests are not evidence
the odds are right.** The three engines are held in agreement by `odds_anchors.json`, so a
wrong anchor reads as consensus across all three. The reference is Bulbapedia/Serebii, not
the other engine.

## Known gaps

Honest state, so nobody rediscovers these the hard way:

- **`internal/api` is ~1% test-covered.** ~48 routes, including `AuthMiddleware` and
  `AdminMiddleware` — which are the *only* thing isolating one user's data from another's,
  because RLS is enabled but bypassed by the backend's `postgres` role. `internal/calc` is
  at 91%; the risk is not where the tests are.
- **No record of which migrations are applied.** `docs/TASKS.md` says 019; 020 and 021 are
  in fact live, and several others are applied but recorded nowhere. Introspect the
  database, don't trust a document.
- **No backups story.** No stated retention, no tested restore.
- **No error tracking anywhere** — backend, web or iOS. A crash on a user's device is
  invisible.
- **`e2e/` does not run.** It authenticates against `/api/auth/register` and
  `/api/auth/login`, which were deleted in the Supabase migration. See `e2e/README.md`.
- **~114 open Biome lint errors** in `frontend/`, down from 163. CI runs `npm run lint` but
  does not gate on it — a permanently red build teaches people to ignore CI. What is left is
  mostly `noExplicitAny` (37), the click-`div` a11y family (~45), `noSvgWithoutTitle` (22)
  and CSS specificity (14). Roughly 18 of the count is pure formatting: `npm run format`
  clears those whenever you want a noisy-but-safe diff.
  - **`a11y/useButtonType` is `"off"` in `biome.json`** — deliberately, and this is the only
    place that fact is written down, because Biome's config is strict JSON and rejects
    comments. The rule guards a `<button>` defaulting to `type="submit"` inside a form. This
    app has **zero** `<form>` elements and zero `onSubmit` handlers, so those 46 violations
    guarded a failure that cannot occur. **Turn it back on the moment a real form appears.**
  - Suppressions must be `biome-ignore`, not `eslint-disable`. The project does not run
    eslint at all, so five `eslint-disable` comments were suppressing nothing — and Biome's
    autofix duly overrode two documented decisions before anyone noticed. All five are
    converted; do not add more.
- **iOS is not App Store submittable** — it is TestFlight-shaped. Account deletion
  (Guideline 5.1.1(v)) does not exist at any layer, and the sprite-IP question is open.
