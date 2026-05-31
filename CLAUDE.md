# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

ShinyTracker is a full-stack web app for tracking Pokemon shiny hunts. Users start hunts, increment encounter counters, and mark Pokemon as found — building a shiny Living Dex. The backend serves a REST API; the frontend is a React SPA.

## Commands

### Frontend (`/frontend`)
```bash
npm run dev       # Vite dev server on http://localhost:5173
npm run build     # tsc -b && vite build
npm run lint      # Biome check
npm run format    # Biome format --write .
```

### Backend (`/backend`)
```bash
go run ./cmd/api/main.go              # API server on :8080
go run ./cmd/seed/main.go             # Seed Pokemon + encounters from PokeAPI
go run ./cmd/seed_availability/main.go # Populate pokemon_availability table
go run ./cmd/seed_fulldex/main.go     # Seed recommended methods from FullDexMethods.csv
go run ./cmd/seed_methods/main.go     # Seed encounter methods from CSV
go run ./cmd/truncate_encounters/main.go # Clear encounters for re-seeding
```

No test framework is configured in either frontend or backend.

## Architecture

### Data Flow
1. Backend reads `DATABASE_URL` from `.env` (Supabase-hosted PostgreSQL, AWS EU Central-1).
2. Frontend hardcodes `http://localhost:8080` as the API base; all requests include `Authorization: Bearer <token>`.
3. Auth middleware extracts the JWT and injects `X-User-ID` into the request context.

### Key Backend Files
- `cmd/api/main.go` — startup, DB connection, router mount
- `internal/api/router.go` — chi routes, CORS (`localhost:5173`), auth middleware
- `internal/api/handlers.go` — auth, Pokemon search, game/encounter endpoints
- `internal/api/hunts.go` — hunt CRUD (create, patch encounter count, complete, delete)
- `internal/api/auth.go` — JWT (HS256) + bcrypt; `JWT_SECRET` env var, defaults to a dev string
- `internal/database/db.go` — pgx connection pool
- `internal/models/models.go` — shared structs (User, Pokemon, Hunt, Encounter)
- `internal/services/pokeapi.go` — 5-worker pool fetches all 1025+ Pokemon; version name mapping
- `internal/calc/odds.go` — shiny odds (base × rolls) and ETA calculation
- `schema.sql` — full DDL; no migration framework, schema changes are manual SQL

### Key Frontend Files
- `src/main.tsx` — React root, AuthProvider, MUI theme, CSS vars
- `src/App.tsx` — top-level layout: AppBar + tabs (Dashboard / Historic / Collection / Games)
- `src/context/AuthContext.tsx` — token + userId in localStorage
- `src/components/Dashboard.tsx` — active hunts; optimistic `+1` increments debounced 1.5 s before PATCH
- `src/components/NewHuntModal.tsx` — Pokemon search → game → method picker (recommended methods highlighted)
- `src/components/Collection.tsx` — shiny Living Dex grid; click to toggle ownership
- `src/palette.ts` + `src/theme.ts` — dark-mode design tokens (blue/slate/emerald), MUI theme

### Database Schema (key tables)
```
users            id (uuid), username, email, password_hash
pokemon          id (int), name, sprite_url, types[]
games            id (int), title, generation, base_odds, supports_breeding
user_games       user_id, game_id, has_shiny_charm
encounters       id, pokemon_id, game_id, method_name, avg_time_seconds, base_rolls, charm_rolls
user_hunts       id (uuid), user_id, pokemon_id, encounter_id, encounter_count, status (active|completed),
                 acquisition_type (HUNTED|EVOLVED|MANUAL_OVERRIDE|TRADED), hunt_parameters (JSONB)
pokemon_availability  pokemon_id, game_id  -- legal availability per game
```

### Patterns to Know
- **No ORM** — all queries are raw SQL via pgx with `$1/$2` placeholders.
- **Upserts** use `ON CONFLICT ... DO UPDATE` for idempotent seeding.
- **Masuda Method** encounters are injected synthetically for games where a Pokemon is available but has no wild encounter row.
- The frontend does **optimistic updates** for encounter counts and rolls back on API error.
- `acquisition_type` and `hunt_parameters` (JSONB) are the extension points for non-standard acquisitions.

## Agent Orchestration

Act as the orchestrator. Before doing substantial work yourself, check whether a specialized subagent in `.claude/agents/` fits, and delegate to it. Subagents run in isolated context, so delegating keeps this session's context clean.

Routing rules:

| Work | Delegate to |
|------|-------------|
| Changes under `backend/` — handlers, routes, pgx SQL, `internal/*`, `cmd/*` seed/migrate tools | `backend-specialist` |
| Changes under `frontend/src/` — React/TS components, styling, the API client | `frontend-specialist` |
| Reviewing a diff/branch before commit or PR (correctness, security, idiom) | `code-reviewer` |
| Encounter / method / availability data health, seeding gaps, pre/post re-seed validation | `data-seed-auditor` |
| Brainstorming new features, hunting-mechanics questions, judging if an idea reflects real shiny hunting | `shiny-hunt-expert` |

How to orchestrate:
- **Delegate** the matching work; for a feature spanning layers, dispatch `backend-specialist` and `frontend-specialist` **in parallel** (separate worktrees) and integrate their results.
- After an implementation subagent finishes a change, run `code-reviewer` on the diff before considering it done.
- **Handle directly** (don't delegate): one-line answers, reading a single known file, trivial edits, and the orchestration/integration itself.
- Always tell the user which subagent you're dispatching and why. Relay the subagent's conclusion — its output isn't shown to the user directly.
