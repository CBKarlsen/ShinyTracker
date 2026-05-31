# P1 Auth Migration — Supabase Auth (GitHub + Google)

Moving from the hand-rolled JWT+bcrypt auth to **Supabase Auth** with GitHub & Google
OAuth. This offloads the auth security surface (password reset, rate-limiting, refresh
tokens, token signing) to a managed service you already run.

## No custom domain needed (anywhere)
You do **not** need to own a website domain for any of this. The OAuth callback uses
Supabase's own domain (`...supabase.co/auth/v1/callback`), dev runs on `http://localhost`
(allowed by GitHub/Google/Supabase), and production uses Railway's free `*.up.railway.app`
HTTPS URL. A custom domain is an optional vanity upgrade for later — it changes nothing
about auth or deploy.

## What I already determined (no action needed)
- **Project URL:** `https://fysopyztqmyjyfgrdusx.supabase.co`
- **OAuth callback URL** (used in every provider below):
  `https://fysopyztqmyjyfgrdusx.supabase.co/auth/v1/callback`
- **JWT signing:** asymmetric **ES256** with a published JWKS
  (`/auth/v1/.well-known/jwks.json`). The Go backend will verify tokens against that —
  no shared secret in code.

---

## ☐ Your dashboard setup (only you can do these)

### 1. GitHub OAuth App
GitHub → Settings → Developer settings → **OAuth Apps** → New OAuth App:
- Application name: `ShinyTracker`
- Homepage URL: `http://localhost:5173` (update to the Railway URL later)
- **Authorization callback URL:** `https://fysopyztqmyjyfgrdusx.supabase.co/auth/v1/callback`
- Create → copy **Client ID** + generate a **Client Secret**.

### 2. Google OAuth credentials
Google Cloud Console → APIs & Services:
- **OAuth consent screen**: External, app name `ShinyTracker`, add yourself as a test user
  (keeps it in "testing" mode — fine for personal use, no verification needed).
- **Credentials → Create Credentials → OAuth client ID → Web application**:
  - Authorized redirect URI: `https://fysopyztqmyjyfgrdusx.supabase.co/auth/v1/callback`
  - Create → copy **Client ID** + **Client Secret**.

### 3. Enable providers in Supabase
Supabase dashboard → **Authentication → Providers**:
- **GitHub** → enable → paste the GitHub Client ID + Secret → save.
- **Google** → enable → paste the Google Client ID + Secret → save.

### 4. URL config in Supabase
Supabase → **Authentication → URL Configuration**:
- **Site URL:** `http://localhost:5173`
- **Redirect URLs:** add `http://localhost:5173/**` (and the Railway frontend URL later).

### 5. Send me one value
Supabase → **Project Settings → API** → copy the **anon / public** key (the long
`eyJ...` "publishable" key — it's safe to expose in frontend code; it is NOT the
service_role key, which you should never share). Paste it back to me and I'll wire it in.

> That's the only secret I need. The GitHub/Google client secrets stay in the Supabase
> dashboard — they never touch this repo.

---

## Implementation plan (my side)

### Data model
- Canonical user id becomes `auth.users.id` (the JWT `sub`, a UUID) — Supabase-managed.
- New `public.profiles` table: `id uuid PK references auth.users(id) on delete cascade`,
  `username text`, `is_admin boolean default false`, `created_at`. Upserted on first login
  from OAuth metadata (name/avatar). Replaces the custom `users` table for app data.
- `user_hunts.user_id` / `user_games.user_id` reference the Supabase user UUID. **Only test
  data exists (`qa_tester` + a few hunts), so we wipe and start fresh** — no real migration.
- `is_admin` moves to `profiles`; `AdminMiddleware` checks it there.

### Backend (`backend/internal/api`)
- New JWT verification: validate the Supabase ES256 token against the cached JWKS
  (`auth/v1/.well-known/jwks.json`), assert `aud=authenticated`, issuer, expiry; inject
  `sub` as `X-User-ID`. Replaces `ValidateJWT`/`jwtSecret` in `auth.go`.
- Remove obsolete: `RegisterHandler`, `LoginHandler`, `GenerateJWT`, `HashPassword`,
  `CheckPasswordHash`, the bcrypt dependency, `JWT_SECRET` (the dev-default-secret P1
  risk disappears entirely).
- Add a tiny `POST /api/profile` (or upsert-on-first-authed-request) to create the
  `profiles` row from the verified token.

### Frontend (`frontend/src`)
- Add `@supabase/supabase-js`; client reads `VITE_SUPABASE_URL` + `VITE_SUPABASE_ANON_KEY`.
- `Login.tsx` → "Continue with GitHub" / "Continue with Google" buttons calling
  `supabase.auth.signInWithOAuth({ provider })`; handle the OAuth redirect back.
- `AuthContext` wraps the Supabase session (`onAuthStateChange`, auto refresh); all API
  calls send `session.access_token` as the Bearer token (via the existing `authedFetch`).
- Remove the email/password form (or keep as a Supabase email/password option — TBD; not
  required since you chose GitHub+Google).

### Sequencing (so the app never half-breaks)
1. I build backend verification + profiles migration + frontend supabase-js path on the branch.
2. You finish the dashboard setup + send the anon key.
3. We swap over, wipe test users, and verify GitHub + Google sign-in end-to-end locally.
4. Then the rest of P1: CORS lockdown (env-driven origin), HTTPS, prod-vs-dev DB decision.

### Still part of P1 (auth-independent)
- Lock CORS to the deployed frontend origin (drop the `"*"`).
- HTTPS end-to-end (host certs).
- Decide prod vs dev Supabase instance (the test data lives in the shared dev one).
