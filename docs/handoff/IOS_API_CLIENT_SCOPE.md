# Scope — iOS API client and auth

The next real step for the native client. Everything here is grounded in the code as of
2026-08-11; where a claim comes from a file, the file is named.

---

## Two prerequisites that are not Swift work

Both block the app entirely. Neither is fixed by writing better Swift.

### P1. The API is not reachable from a phone

`frontend/src/config.ts` defaults `API_BASE` to `http://localhost:8080`, and `cmd/api/main.go`
reads `PORT` with the same default. There is a `backend/Dockerfile`, but no deploy manifest
(`fly.toml`, `render.yaml`, `Procfile`) and no `.github/workflows` anywhere in the repo. Nothing
indicates the Go API is hosted.

A phone on cellular cannot reach `localhost`. **The API must be deployed with a public HTTPS URL**
before the app can do anything at all. HTTPS specifically: App Transport Security rejects cleartext
HTTP by default, and shipping an ATS exception to review invites questions you do not want.

The database is already hosted (Supabase, `eu-central-1`), so this is only the Go service.

### P2. Sign in with Apple is mandatory, and does not exist yet

`frontend/src/components/Login.tsx` offers exactly two providers: `"github" | "google"`. There is
no email/password path.

App Store Review Guideline 4.8 requires offering Sign in with Apple when an app offers other
third-party sign-in. GitHub and Google both count. So Apple must be:

1. enabled as a provider in the Supabase project, and
2. implemented natively in the app (see below).

This is a review blocker, not a nice-to-have. Discovering it at submission costs a cycle.

---

## Auth design

**Use `supabase-swift`, the official SDK.** The backend already trusts Supabase-issued JWTs and
needs no change: `internal/api/supabase_auth.go` validates ES256 against
`<SUPABASE_URL>/auth/v1/.well-known/jwks.json` with audience `authenticated`, and
`AuthMiddleware` (`internal/api/auth.go:36`) turns a valid `Authorization: Bearer <token>` into
`X-User-ID`. The SDK holds exactly that token.

Do not hand-roll the session. Refresh-token rotation, Keychain persistence and PKCE are where
auth bugs live, and the SDK already solves them.

**Sign in with Apple must be native**, not a web redirect: `ASAuthorizationAppleIDProvider` →
identity token → `signInWithIdToken(credentials: .init(provider: .apple, idToken:))`. A web view
for Apple sign-in is both poor UX and a review risk.

**GitHub and Google** go through `ASWebAuthenticationSession` (what the SDK's OAuth flow uses),
with a custom scheme redirect — e.g. `shinytracker://auth-callback`. That scheme must be
registered in the app target *and* added to the Supabase project's allowed redirect URLs. The web
app's `redirectTo: window.location.origin` does not apply on device.

**Verified, so nobody re-litigates it:** `AuthMiddleware` uses `r.Header.Set("X-User-ID", …)`,
which *replaces* any client-supplied value. A native client cannot spoof another user's id by
sending that header — worth confirming explicitly, because a browser cannot set it cross-origin
but a phone can.

---

## API client design

One `APIClient` actor. Small, boring, and wrappable.

- **Bearer injection** from the current Supabase session on every request.
- **401 handling:** refresh the session once, retry the request once, and if that fails emit a
  session-expired event. This mirrors `SessionExpiredError` in the web client — match the
  behaviour so the two clients fail the same way.
- **Codable models** mirroring the Go response structs. Watch the nullables: `game_id` and
  `hunt_method_id` are genuinely nullable on `user_hunts` (custom-method hunts have neither), so
  they are optionals, not defaults.
- **`hunt_parameters` is open JSONB.** Do not invent a second decoder — reuse `ParamValue` from
  `ShinyTrackerKit`, which already decodes it and already survives nulls, strings and
  out-of-range numbers without trapping.
- **Write it so an offline queue can wrap it later.** Request values should be `Codable` and
  replayable. Do not build the queue yet.

### Endpoints needed for v1

The API exposes 24 user-facing routes plus admin. A first working app needs a subset:

| Purpose | Endpoint |
|---|---|
| Session identity | `GET /api/me` |
| Reference data | `GET /api/games`, `GET /api/pokemon`, `GET /api/methods` |
| Pokémon detail | `GET /api/pokemon/{id}` |
| Owned games / charm | `GET /api/user/{id}/games`, `POST`/`DELETE` the same |
| Hunt list | `GET /api/hunts` |
| Hunt lifecycle | `POST /api/hunts`, `PATCH /api/hunts/{id}`, `DELETE /api/hunts/{id}` |
| Phases | `POST /api/hunts/{id}/phases` |
| Method choice | `GET /api/hunt-methods` |

Deliberately out of v1: `/dex/*`, `/stats`, `/export`, `/odds`, all `/admin/*`. Note `/odds` is
not needed at all on device — `ShinyTrackerKit` computes odds locally, which is required anyway
for offline mid-chain display.

---

## Non-goals for this phase

- Offline storage and the outbound sync queue. Depends on D1, which is now implemented
  server-side (`client_owns_time`) but has no client half.
- Live Activity / Dynamic Island, Apple Watch, Bluetooth HID counting.
- Sprite bundling. Real, and flagged in `IOS_HANDOVER.md` — `SPRITE_BASE` points at
  `raw.githubusercontent.com`, which is rate-limited and useless offline — but it is an asset
  pipeline decision, not an API-client one.

---

## Order of work

1. **Deploy the Go API** with a public HTTPS URL (P1). Nothing below is testable on device first.
2. **Enable Apple** in Supabase; add the iOS redirect URL for GitHub/Google (P2).
3. **Create the Xcode app target**, adding `ShinyTrackerKit` as a *local* package dependency —
   see `DECISIONS.md` D2 for why it must stay local.
4. **Auth module**: native Sign in with Apple, plus GitHub/Google via `ASWebAuthenticationSession`.
5. **`APIClient` + models** for the v1 endpoints above.
6. **One end-to-end screen** — the hunt list — to prove auth, networking and decoding together
   before any UI is built on top.
7. Only then the counter UI, and only then offline.

Steps 1 and 2 are the ones that will surprise you if left late.
