# e2e — quarantined, does not run

**This suite has not passed since the Supabase auth migration. It is deliberately not in
CI.** Read this before assuming any of it is coverage.

It is kept rather than deleted because the 55 tests are a genuinely good specification of
the web app's user flows, and that is worth more than the stale selectors are worth
deleting. But nothing here is verifying anything today.

## Why it is broken

Four separate breakages, in increasing order of effort to fix:

1. **`helpers.ts` posts to `/api/auth/register` and `/api/auth/login`.** Those routes were
   deleted with the hand-rolled JWT+bcrypt auth. `grep` the Go source — they do not exist.
2. **`helpers.ts` reads `localStorage.getItem("token")` / `"userId"`.** That was the old
   auth's storage. Supabase stores a session blob under `sb-<project-ref>-auth-token`.
3. **`cleanupUserGames` calls `/api/user/{id}/games`.** Renamed to `/api/me/games` — the
   user id came out of the path because it only ever had to equal the token's subject.
4. **`auth.spec.ts` is obsolete outright.** Its 11 tests drive a "Sign in / Register" tabbed
   form with email+password fields. `frontend/src/components/Login.tsx` is now OAuth-only
   (`supabase.auth.signInWithOAuth`) — there is no register form, no password field, and no
   "Register" tab to click. These flows are gone, not moved.

Beyond auth: the frontend had a full redesign (MUI dropped, custom CSS, left-sidebar
layout) after these tests were written, so assume the selectors in the other five specs
have drifted too. Nobody has checked.

## What it would take

The blocker is a test identity. OAuth cannot be driven headlessly, but Supabase will still
issue a session for a password user even though the UI does not offer one:

1. Create a dedicated test user in the Supabase dashboard with a password. Do **not** reuse
   a real account — the helpers delete the user's games and complete their active hunts.
2. Put `E2E_TEST_EMAIL`, `E2E_TEST_PASSWORD`, `VITE_SUPABASE_URL` and the anon key in the
   environment.
3. Rewrite `login()` to call `supabase.auth.signInWithPassword`, then write the returned
   session into `localStorage` under `sb-<project-ref>-auth-token` before `page.reload()`.
4. Fix `cleanupUserGames` to use `/api/me/games`.
5. Delete `auth.spec.ts`.
6. Run the other five specs and repair selectors until green — this is the unbounded part.

Steps 1–5 are an hour. Step 6 is unknown and is the reason this has not been done.

## What it covers (worth preserving even if rebuilt from scratch)

- `games.spec.ts` — library add/remove, Shiny Charm toggle, summary stats
- `hunt.spec.ts` — create a hunt, +1 and SPACE increment, pause/resume, log phase, "Found
  it!", completed hunt reaching Historic Hunts, dynamic odds updating as the count rises
- `hunt-methods-improvements.spec.ts` — Mewtwo has no breeding methods; Magikarp shows
  Breeding in Gen 3 and Masuda in Gen 9; Relicanth Gen 6 Chain Fishing odds scale
- `navigation.spec.ts` — every page loads, Odds Calculator and Method Library behaviour
- `auth.spec.ts` — **obsolete**, see above

The `hunt-methods-improvements` assertions are the valuable ones: they encode real domain
facts, and those facts do not go stale even when the selectors do.
