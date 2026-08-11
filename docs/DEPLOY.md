# Deploying ShinyTracker to Railway

Two services from this one repo, both built from Dockerfiles:

| Service  | Root dir   | Builds via            | Serves                    |
|----------|------------|-----------------------|---------------------------|
| backend  | `backend`  | `backend/Dockerfile`  | Go API on `$PORT`         |
| frontend | `frontend` | `frontend/Dockerfile` | nginx static SPA on `$PORT` |

Each service must have its **Root Directory** set (`backend` / `frontend`) so Railway uses
that folder's Dockerfile; otherwise it falls back to its **Railpack** auto-builder on the
repo root (which has a Playwright `package.json`) and fails with "No start command detected."
**Auth is Supabase** (GitHub + Google OAuth); the **database** is Supabase Postgres. You host
only the two app services on Railway.

**Live deployment (reference):** backend `https://shinytracker-production.up.railway.app`,
frontend `https://shinytracker.up.railway.app`.

> ⚠️ **Gotchas that cost us the first time — read these:**
> - **Use the Supabase POOLER `DATABASE_URL`**, not the direct one. Pooler =
>   `postgresql://postgres.<ref>:<pwd>@aws-…pooler.supabase.com:5432/postgres`. The direct
>   `db.<ref>.supabase.co` host is **IPv6-only** and Railway (IPv4) can't reach it.
> - **DB password: alphanumeric only.** Symbols (`$ # @ / ?`) break URL parsing
>   (`net/url: invalid userinfo`) and Railway's variable editor mangles `$` (interpolation)
>   and `#` (comment in the raw editor). Reset it in Supabase → Database → Reset password.
>   Add secrets via the **single-variable field**, not the raw editor.
> - **Pin the port:** set a `PORT` variable AND the service's **target port** to the same
>   number (we use `8080` for both services). Mismatch → 502 "application failed to respond."
> - **CORS origin = scheme+host only**, no trailing slash, no `/**` path. The `/**` form is
>   only for Supabase's Redirect URLs.
> - **Build order + Vite:** `VITE_*` vars are inlined at *build* time → build the frontend
>   *after* the backend URL exists; redeploy the frontend whenever you change a `VITE_*` var.
> - **Three places must agree on the frontend URL:** backend `CORS_ALLOWED_ORIGINS` and
>   Supabase's **Site URL** + **Redirect URLs**. Miss one → login or API calls silently fail.

---

## 0. Prerequisites
- Push this repo to GitHub (Railway deploys from a connected GitHub repo).
- A Railway account + project: <https://railway.app>.
- Your Supabase **`DATABASE_URL`**, **project URL** (`https://<ref>.supabase.co`), and
  **anon/publishable key** (`sb_publishable_...`) — all from the Supabase dashboard.
- GitHub + Google OAuth already configured in Supabase (see `AUTH-SETUP.md`).

## 1. Backend service
1. Railway → **New Project** → **Deploy from GitHub repo** → pick this repo.
2. Service settings → **Root Directory** = `backend` (detects `backend/Dockerfile`).
3. **Variables** (Settings → Variables — use the single-variable field for `DATABASE_URL`):
   - `DATABASE_URL` = the Supabase **pooler** string (alphanumeric password — see gotchas)
   - `SUPABASE_URL` = `https://fysopyztqmyjyfgrdusx.supabase.co` (required — the backend
     verifies tokens against this project's JWKS; it fails fast if unset)
   - `PORT` = `8080`
   - `CORS_ALLOWED_ORIGINS` = the **frontend** Railway URL (you'll have it after step 2;
     set it then and redeploy). Exact origin — no trailing slash/path. Comma-separated for many.
4. **Settings → Networking → Generate Domain**, and set the **target port** to `8080`
   (matches the `PORT` var). Live backend: `https://shinytracker-production.up.railway.app`.
5. Confirm: deploy logs show `Server starting on port …`; `<backend>/api/hunts` returns 401
   (no token) — that means auth is live.

## 2. Frontend service
1. Same Railway project → **New** → **GitHub Repo** → same repo (second service).
2. Service settings → **Root Directory** = `frontend` (detects `frontend/Dockerfile`).
3. **Variables** (the `VITE_*` ones are passed to the Docker build as ARGs):
   - `VITE_API_URL` = the backend domain from step 1.4 (no trailing slash)
   - `VITE_SUPABASE_URL` = `https://fysopyztqmyjyfgrdusx.supabase.co`
   - `VITE_SUPABASE_ANON_KEY` = your `sb_publishable_...` key
   - `PORT` = `8080`
4. **Generate Domain** + set the **target port** to `8080` — that's the URL you open to use
   the app (live: `https://shinytracker.up.railway.app`).
5. Because `VITE_*` is build-time, **redeploy the frontend** any time you change those vars.

## 3. Point everything at the frontend URL
Once the frontend has its `*.up.railway.app` domain:
1. **Backend** → set `CORS_ALLOWED_ORIGINS` = that frontend URL → redeploy backend.
2. **Supabase → Authentication → URL Configuration:**
   - **Site URL** = the frontend Railway URL
   - **Redirect URLs** → add `https://<frontend>.up.railway.app/**` (keep the localhost
     entry too for local dev)
3. **(Optional)** update the GitHub/Google OAuth app **Homepage URL** to the frontend URL.
   The OAuth **callback** stays `https://fysopyztqmyjyfgrdusx.supabase.co/auth/v1/callback`
   — it does **not** change for prod.

## 4. Wire-up checklist
- [ ] Backend deployed; `<backend>/api/hunts` → 401 (auth live); logs show server start.
- [ ] Backend has `DATABASE_URL`, `SUPABASE_URL`, `CORS_ALLOWED_ORIGINS` (= frontend URL).
- [ ] Frontend built with `VITE_API_URL`, `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`.
- [ ] Supabase Site URL + Redirect URLs include the frontend Railway URL.
- [ ] Open the frontend URL → "Continue with GitHub/Google" → lands on the dashboard.

## Local sanity check (optional)
Railway builds the images remotely. To verify locally first:

```bash
# backend
docker build -t st-backend ./backend
docker run --rm \
  -e DATABASE_URL=... \
  -e SUPABASE_URL=https://fysopyztqmyjyfgrdusx.supabase.co \
  -e CORS_ALLOWED_ORIGINS=http://localhost:5173 \
  -e PORT=8080 -p 8080:8080 st-backend

# frontend (build-time VITE_* args)
docker build -t st-frontend \
  --build-arg VITE_API_URL=http://localhost:8080 \
  --build-arg VITE_SUPABASE_URL=https://fysopyztqmyjyfgrdusx.supabase.co \
  --build-arg VITE_SUPABASE_ANON_KEY=sb_publishable_xxx \
  ./frontend
docker run --rm -e PORT=8080 -p 5173:8080 st-frontend
```
> The frontend `Dockerfile` declares `ARG VITE_API_URL`, `VITE_SUPABASE_URL`, and
> `VITE_SUPABASE_ANON_KEY`, so Railway's service variables reach the Vite build.

## Notes / gotchas
- **Go image tag:** Dockerfile pins `golang:1.26-alpine` to match `go 1.26.1`. If Railway
  can't pull it, bump to the latest available `1.26.x` tag.
- **nginx + `$PORT`:** the frontend image renders `nginx.conf.template` via envsubst; only
  `$PORT` is substituted (`$uri` preserved). SPA fallback `try_files … /index.html`.
- **Root Directory is mandatory:** without it Railway runs Railpack on the repo root (finds
  the Playwright `package.json`) and fails with "No start command detected." Set it to
  `backend` / `frontend` so the per-folder Dockerfile is used.
- **DB instance:** test data was wiped from the shared dev Supabase and the DB password was
  rotated to an alphanumeric one during go-live. For a dedicated prod project later, repeat
  the env-var + migration steps against the new instance.
- **Seeding:** `cmd/*` seed tools aren't in the image — run them from your machine against
  `DATABASE_URL` (`TASKS.md` → "Operational notes"). Note `cmd/seed` LAST.
