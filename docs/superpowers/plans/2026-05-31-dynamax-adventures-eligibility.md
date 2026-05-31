# Dynamax Adventures Eligibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all 38 Dynamax Adventure legendary bosses huntable via `dynamax_adventures_gen8` in Sword/Shield by adding the 24 missing entries to `legendary_encounters.json`.

**Architecture:** Data-only. Add DA-only entries (`"default_kind": "raid"`, `"default_games": []`, `"overrides": {"@swsh-dynamax": "raid"}`) to `backend/seeds/legendary_encounters.json`. The seed's `@swsh-dynamax` alias produces a SwSh `raid` row; `computeAvailability` then attaches the method, and `reconcileAvailability` auto-creates the `pokemon_availability` backing. No Go, schema, or odds changes.

**Tech Stack:** JSON seed file; Go seed CLI (`cmd/seed`, `cmd/audit_methods`); `jq` for validation. PostgreSQL (shared Supabase) only for the DB-side verification task.

**Spec:** `docs/superpowers/specs/2026-05-31-dynamax-adventures-eligibility-design.md`

**Working directory:** main repo `/Users/casper/Fritidsprosjekt/ShinyTracker`, branch `hunt-method-corrections`. Run `jq`/`go` from `backend/` where noted.

---

## Task 1: Add the 24 missing DA legendary entries

**Files:**
- Modify: `backend/seeds/legendary_encounters.json` (append 24 entries before the closing `]`)

- [ ] **Step 1: Establish the validation baseline (failing check)**

From `backend/`, list the dex IDs that currently carry the DA override:

Run:
```bash
cd backend && jq '[.[] | select(.overrides["@swsh-dynamax"] == "raid") | .pokemon_id] | sort' seeds/legendary_encounters.json
```
Expected NOW (before the change): exactly these 14 IDs —
`[144,145,146,150,249,250,382,383,384,487,643,644,716,717]`.
This is the baseline; after Task 1 it must become 38 IDs.

- [ ] **Step 2: Append the 24 new entries**

Edit `backend/seeds/legendary_encounters.json`. The file is a JSON array. Add a comma
after the current final entry's closing `}`, then insert these 24 objects as the last
elements (before the file's closing `]`):

```json
  { "pokemon_id": 243, "name": "Raikou",     "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 244, "name": "Entei",      "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 245, "name": "Suicune",    "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 380, "name": "Latias",     "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 381, "name": "Latios",     "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 480, "name": "Uxie",       "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 481, "name": "Mesprit",    "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 482, "name": "Azelf",      "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 483, "name": "Dialga",     "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 484, "name": "Palkia",     "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 485, "name": "Heatran",    "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 488, "name": "Cresselia",  "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 641, "name": "Tornadus",   "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 642, "name": "Thundurus",  "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 645, "name": "Landorus",   "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 646, "name": "Kyurem",     "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 718, "name": "Zygarde",    "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 785, "name": "Tapu Koko",  "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 786, "name": "Tapu Lele",  "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 787, "name": "Tapu Bulu",  "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 788, "name": "Tapu Fini",  "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 791, "name": "Solgaleo",   "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 792, "name": "Lunala",     "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } },
  { "pokemon_id": 800, "name": "Necrozma",   "default_kind": "raid", "default_games": [], "overrides": { "@swsh-dynamax": "raid" } }
```

- [ ] **Step 3: Validate JSON well-formedness**

Run:
```bash
cd backend && jq empty seeds/legendary_encounters.json && echo "VALID JSON"
```
Expected: `VALID JSON` (no parse error — catches a missing/extra comma).

- [ ] **Step 4: Verify the DA override set is now exactly the 38 expected IDs**

Run:
```bash
cd backend && jq -c '[.[] | select(.overrides["@swsh-dynamax"] == "raid") | .pokemon_id] | sort' seeds/legendary_encounters.json
```
Expected (38 IDs, sorted):
```
[144,145,146,150,243,244,245,249,250,380,381,382,383,384,480,481,482,483,484,485,487,488,641,642,643,644,645,646,716,717,718,785,786,787,788,791,792,800]
```
If the count is not 38 or any ID is missing/duplicated, fix Step 2 before continuing.

- [ ] **Step 5: Shiny-lock safety check — none of the 38 may be locked in Sword/Shield**

Run:
```bash
cd backend && jq -c '[.locks[] | select(.games | index("Sword/Shield")) | .pokemon_id] | sort' seeds/shiny_locks.json
```
Expected: only non-DA story legends, e.g. `[888,889,890,891,898]` (Zacian, Zamazenta, Eternatus, Kubfu, Calyrex).
**Assertion:** the output must contain NONE of the 38 DA IDs from Step 4. If any DA ID
appears here, STOP — a DA boss is wrongly shiny-locked in SwSh and would be suppressed;
escalate rather than silently editing `shiny_locks.json`.

- [ ] **Step 6: Commit**

```bash
git add backend/seeds/legendary_encounters.json
git commit -m "Seed 24 missing Dynamax Adventure legendary bosses (38 total in SwSh)"
```

---

## Task 2: Re-seed and verify coverage against the database

**This task writes to the shared Supabase DB.** Do NOT run it autonomously against the
shared database — it requires explicit operator go-ahead. If no DB is available, this
task is deferred to whoever re-seeds; the data change in Task 1 stands on its own and is
validated statically there.

**Files:** none (operational verification only)

- [ ] **Step 1: Confirm go-ahead to re-seed the shared DB**

Get explicit confirmation before running `cmd/seed` (it rebuilds the method tables).
Respect the seed-order rule: `cmd/seed` runs last.

- [ ] **Step 2: Re-seed**

Run (from `backend/`):
```bash
cd backend && go run ./cmd/seed/main.go
```
Expected: completes with no `unknown game-group alias`, no `default_kind must be static
or raid`, and no invariant-violation fatals. The "Inserted N curated static/raid
encounter rows" line should reflect the 24 new raid rows, and "Reconciled
pokemon_availability (+N rows)" should auto-add SwSh availability for any of the 24 not
already listed.

- [ ] **Step 3: Assert DA coverage is 38 in Sword/Shield**

Run (from `backend/`, using the same `DATABASE_URL` as the app):
```bash
cd backend && go run ./cmd/audit_methods/main.go
```
Then confirm via psql (or the audit output) that the `dynamax_adventures_gen8` method
now has **38** `method_availability` rows in Sword/Shield, e.g.:
```sql
SELECT COUNT(*) FROM method_availability ma
JOIN hunt_methods hm ON hm.id = ma.method_id
JOIN games g ON g.id = ma.game_id
WHERE hm.formula_type = 'dynamax_adventures_gen8' AND g.title = 'Sword/Shield';
-- expected: 38
```
Spot-check a previously missing legend: Necrozma (#800) should now return a DA route
from `GET /api/pokemon/800/route` for a user who owns Sword/Shield.

- [ ] **Step 4: Confirm no new audit regressions**

In the `cmd/audit_methods` output, Section B ("huntable but not legally available") must
not gain entries for any of the 38 DA IDs — `reconcileAvailability` should have backed
them all with `pokemon_availability`. Section C (orphans) must remain 0. If a DA ID
appears in Section B, its SwSh `pokemon_availability` row is missing; investigate
`reconcileAvailability` ordering before hand-adding.

---

## Task 3: Record progress in TASKS.md

**Files:**
- Modify: `TASKS.md`

- [ ] **Step 1: Note slice D shipped under the method-eligibility work**

In `TASKS.md`, under the "Follow-ups / known issues" section where the method-eligibility
pass is referenced, add a line recording that slice D is done and the remaining slices:

```markdown
- **Method eligibility — slice D (Dynamax Adventures) shipped** — all 38 DA legendary
  bosses seeded as SwSh raids in `legendary_encounters.json`
  (spec/plan `docs/superpowers/*/2026-05-31-dynamax-adventures-eligibility*`). Remaining
  eligibility slices: A (Gen 8/9 overworld spawns — SV/SwSh/LA, biggest), B (Poké Radar
  over-broad excludes), C (ORAS fishing terrain gap); plus the 9 DA Ultra Beasts and
  home-game static coverage for the 24 legends.
```

- [ ] **Step 2: Commit**

```bash
git add TASKS.md
git commit -m "Record Dynamax Adventures eligibility (slice D) progress in TASKS.md"
```

---

## Final verification

- [ ] `jq empty backend/seeds/legendary_encounters.json` → VALID (Task 1 Step 3).
- [ ] DA override set == 38 expected IDs (Task 1 Step 4).
- [ ] No DA ID is shiny-locked in Sword/Shield (Task 1 Step 5).
- [ ] (If DB available) `dynamax_adventures_gen8` has 38 SwSh `method_availability` rows; audit Section B/C clean (Task 2).
