# Deploying ShinyTracker to Railway

Two services from this one repo, both built from Dockerfiles:

| Service  | Root dir   | Builds via            | Serves                    |
|----------|------------|-----------------------|---------------------------|
| backend  | `backend`  | `backend/Dockerfile`  | Go API on `$PORT`         |
| frontend | `frontend` | `frontend/Dockerfile` | nginx static SPA on `$PORT` |

Railway auto-detects each Dockerfile, injects `$PORT`, and gives each service a
`*.up.railway.app` domain. DB stays on the existing Supabase instance for now
(the "prod vs dev instance" call was deferred — see `PRODUCTION.md` P1).

> ⚠️ **Build order matters.** Vite inlines `VITE_API_URL` at *build* time, so the
> frontend must be built *after* you know the backend's public URL. Deploy backend
> first, copy its domain, then build the frontend.
>
> ⚠️ **The frontend won't actually load data until P1 CORS is done** — the backend
> currently allows `"*"` (works), but once you lock CORS in P1 you must add the
> frontend domain. Track that coupling.

---

## 0. Prerequisites
- Push this repo to GitHub (Railway deploys from a connected GitHub repo).
- A Railway account + project: <https://railway.app>.
- Have your Supabase `DATABASE_URL` handy.
- Generate a strong JWT secret: `openssl rand -base64 48`.

## 1. Backend service
1. Railway → **New Project** → **Deploy from GitHub repo** → pick this repo.
2. In the service settings → **Root Directory** = `backend`.
   Railway detects `backend/Dockerfile` automatically (Builder = Dockerfile).
3. **Variables** (Settings → Variables):
   - `DATABASE_URL` = your Supabase connection string
   - `JWT_SECRET` = the `openssl rand` output from step 0
   - *(Do **not** set `PORT` — Railway provides it; `main.go` falls back to 8080 locally.)*
4. **Settings → Networking → Generate Domain.** Copy it, e.g.
   `https://shinytracker-backend-production.up.railway.app`.
5. Confirm it's up: open `<backend-domain>/api/...` or check deploy logs for
   `Server starting on port …`.

## 2. Frontend service
1. In the **same** Railway project → **New** → **GitHub Repo** → same repo
   (a second service).
2. Service settings → **Root Directory** = `frontend`
   (detects `frontend/Dockerfile`).
3. **Variables:**
   - `VITE_API_URL` = the backend domain from step 1.4 (no trailing slash).
     Railway passes this to the Docker build as an `ARG` automatically.
4. **Generate Domain** for the frontend too — that's the URL you open to use the app.
5. If you set `VITE_API_URL` *after* the first build, **redeploy** the frontend so
   Vite re-inlines it.

## 3. Wire-up checklist
- [ ] Backend deployed, domain generated, logs show server start.
- [ ] `JWT_SECRET` set on backend (P1 will make this *required*, not just recommended).
- [ ] Frontend `VITE_API_URL` = backend domain, frontend redeployed after setting it.
- [ ] Frontend domain opens the login page.
- [ ] **P1 dependency:** backend CORS allows the frontend domain (until then the
      `"*"` rule lets it work, but that rule is removed in P1).

## Local sanity check (optional)
The Docker daemon was not running when these files were generated, so the images
were **not** built locally — Railway builds them remotely. To verify locally first:

```bash
# backend
docker build -t st-backend ./backend
docker run --rm -e DATABASE_URL=... -e JWT_SECRET=dev -e PORT=8080 -p 8080:8080 st-backend

# frontend (point at a running backend)
docker build -t st-frontend --build-arg VITE_API_URL=http://localhost:8080 ./frontend
docker run --rm -e PORT=8080 -p 5173:8080 st-frontend
```

## Notes / gotchas
- **Go image tag:** Dockerfile pins `golang:1.26-alpine` to match `go 1.26.1` in
  `go.mod`. If Railway can't pull it, bump to the latest available `1.26.x` tag.
- **nginx + `$PORT`:** the frontend image renders `nginx.conf.template` via the
  nginx entrypoint's envsubst; only `$PORT` is substituted (`$uri` is preserved).
- **SPA fallback:** nginx `try_files … /index.html` handles refreshes on any path
  (harmless even though the app is currently tab/state-based, no router).
- **Seeding the DB:** the `cmd/*` seed tools are not part of the deployed image —
  run them from your machine against `DATABASE_URL` as documented in
  `TASKS.md` → "Operational notes".
