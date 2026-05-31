# Deploying ShinyTracker to Railway

Two services from this one repo, both built from Dockerfiles:

| Service  | Root dir   | Builds via            | Serves                    |
|----------|------------|-----------------------|---------------------------|
| backend  | `backend`  | `backend/Dockerfile`  | Go API on `$PORT`         |
| frontend | `frontend` | `frontend/Dockerfile` | nginx static SPA on `$PORT` |

Railway auto-detects each Dockerfile, injects `$PORT`, and gives each service a
`*.up.railway.app` domain. **Auth is Supabase** (GitHub + Google OAuth); the **database**
is Supabase Postgres. You host only the two app services on Railway.

> ⚠️ **Build order + Vite env vars.** Vite inlines `VITE_*` vars at *build* time, so the
> frontend must be (re)built *after* you know the backend's public URL. Deploy backend
> first, grab its domain, then build the frontend with all three `VITE_*` vars set.
>
> ⚠️ **Three places must agree on the frontend URL:** the backend `CORS_ALLOWED_ORIGINS`,
> and Supabase's **Site URL / Redirect URLs**. If any is missing the prod frontend URL,
> login or API calls silently fail.

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
3. **Variables** (Settings → Variables):
   - `DATABASE_URL` = your Supabase connection string
   - `SUPABASE_URL` = `https://fysopyztqmyjyfgrdusx.supabase.co` (required — the backend
     verifies tokens against this project's JWKS; it fails fast if unset)
   - `CORS_ALLOWED_ORIGINS` = the **frontend** Railway URL (you'll have it after step 2;
     set it then and redeploy). Comma-separated if more than one origin.
   - *(Do **not** set `PORT` — Railway provides it; `main.go` falls back to 8080 locally.)*
4. **Settings → Networking → Generate Domain.** Copy it, e.g.
   `https://shinytracker-backend-production.up.railway.app`.
5. Confirm: deploy logs show `Server starting on port …`; `<backend>/api/hunts` returns 401
   (no token) — that means auth is live.

## 2. Frontend service
1. Same Railway project → **New** → **GitHub Repo** → same repo (second service).
2. Service settings → **Root Directory** = `frontend` (detects `frontend/Dockerfile`).
3. **Variables** (Railway passes these to the Docker build as ARGs):
   - `VITE_API_URL` = the backend domain from step 1.4 (no trailing slash)
   - `VITE_SUPABASE_URL` = `https://fysopyztqmyjyfgrdusx.supabase.co`
   - `VITE_SUPABASE_ANON_KEY` = your `sb_publishable_...` key
4. **Generate Domain** for the frontend — that's the URL you open to use the app.
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
- **DB instance:** test data has been wiped from the shared dev Supabase. For prod, decide
  whether to keep it or spin up a dedicated project, and rotate the DB password before
  go-live (`PRODUCTION.md` P1).
- **Seeding:** `cmd/*` seed tools aren't in the image — run them from your machine against
  `DATABASE_URL` (`TASKS.md` → "Operational notes"). Note `cmd/seed` LAST.
