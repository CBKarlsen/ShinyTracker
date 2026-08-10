# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

ShinyTracker is a full-stack web app for tracking Pokemon shiny hunts. Users start hunts, increment encounter counters, and mark Pokemon as found — building a shiny Living Dex. The backend serves a REST API; the frontend is a React SPA.

Test setup is uneven: the Go backend has `go test ./...` (including the shared odds-anchor suite in `internal/calc`), and the Swift package in `ios/` has `swift test`. The **frontend has no test runner** — verify TypeScript changes with `npx tsc -b` and, for non-trivial logic, a throwaway `npx tsx` script. Do not add a frontend test framework without asking.

Backend seed/migrate command notes live in `backend/CLAUDE.md`.

## Architecture

### Data Flow
1. Backend reads `DATABASE_URL` from `.env` (Supabase-hosted PostgreSQL, AWS EU Central-1).
2. Frontend hardcodes `http://localhost:8080` as the API base; all requests include `Authorization: Bearer <token>`.
3. Auth middleware extracts the JWT and injects `X-User-ID` into the request context.

`backend/schema.sql` holds the full DDL — there is no migration framework, schema changes are manual SQL.

### Patterns to Know
- **No ORM** — all queries are raw SQL via pgx with `$1/$2` placeholders.
- **Upserts** use `ON CONFLICT ... DO UPDATE` for idempotent seeding.
- **Masuda Method** encounters are injected synthetically for games where a Pokemon is available but has no wild encounter row.
- The frontend does **optimistic updates** for encounter counts and rolls back on API error.
- `acquisition_type` and `hunt_parameters` (JSONB) are the extension points for non-standard acquisitions.

## Domain accuracy

See `docs/audit/ODDS_DOMAIN_REVIEW.md` for open odds-engine findings.

Finding 1 requires the same fix in `backend/internal/calc/methods.go` **and** `frontend/src/utils/odds.ts` — the two odds engines are independent implementations, so a fix in one is only half the fix.

Note that finding 1 is not detectable from inside the repo: both engines agree with each other and the tests pass. Passing tests are not evidence the odds are right — the reference is Bulbapedia/Serebii, not the other engine.

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
