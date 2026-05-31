# Scarlet/Violet Wild/Overworld Eligibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Scarlet/Violet overworld-spawnable species huntable via Random Encounter, Sandwich Hunting, and a single Mass Outbreak method by seeding curated `kind=wild` rows from the SV regional dex.

**Architecture:** Reuse `kind='wild'` (no DDL). A new game-keyed `seeds/overworld_species.json` lists SV regional-dex IDs; a new `seedOverworldSpecies` step in `cmd/seed` inserts wild rows (guarded against legendaries); the existing derivation + `reconcileAvailability` do the rest. The three area-outbreak methods collapse into one.

**Tech Stack:** Go seed CLI (`cmd/seed`), pgx raw SQL, JSON seed files, `jq`. PostgreSQL (shared Supabase) only for the DB-side verification task. Web research for the dex list.

**Spec:** `docs/superpowers/specs/2026-05-31-sv-overworld-eligibility-design.md`

**Working directory:** main repo `/Users/casper/Fritidsprosjekt/ShinyTracker`, branch `gen89-overworld-eligibility`. Run `go`/`jq` from `backend/`.

---

## Task 1: Collapse the three SV outbreak methods into one

**Files:**
- Modify: `backend/seeds/hunt_methods.json`

- [ ] **Step 1: Baseline — confirm there are 3 SV outbreak methods**

Run:
```bash
cd backend && jq '[.[] | select(.formula_type=="outbreak_defeats_sv")] | length' seeds/hunt_methods.json
```
Expected NOW: `3` (Paldea / Kitakami / Terarium).

- [ ] **Step 2: Replace the three entries with one**

In `backend/seeds/hunt_methods.json`, delete these three objects:
`outbreak_paldea_sv` ("Paldea Mass Outbreak"), `outbreak_kitakami_sv`
("Kitakami Mass Outbreak"), `outbreak_terarium_sv` ("Terarium Mass Outbreak").
Insert this single object in their place (keep surrounding commas valid):

```json
  {
    "id": "outbreak_sv",
    "games": ["Scarlet/Violet"],
    "method_name": "Mass Outbreak",
    "avg_time_seconds": 15,
    "base_rolls": 1,
    "charm_rolls": 2,
    "formula_type": "outbreak_defeats_sv",
    "requires_kind": "wild"
  }
```

- [ ] **Step 3: Validate the collapse**

Run:
```bash
cd backend && jq empty seeds/hunt_methods.json && \
jq '[.[] | select(.formula_type=="outbreak_defeats_sv")] | length' seeds/hunt_methods.json && \
jq -r '.[] | select(.formula_type=="outbreak_defeats_sv") | "\(.id) | \(.method_name) | \(.games|join(","))"' seeds/hunt_methods.json
```
Expected: VALID JSON, count `1`, and one line `outbreak_sv | Mass Outbreak | Scarlet/Violet`.

- [ ] **Step 4: Commit**

```bash
git add backend/seeds/hunt_methods.json
git commit -m "Collapse SV area-outbreak methods into one Mass Outbreak (SV)"
```

---

## Task 2: Gather the SV regional-dex species list (data)

**Files:**
- Create: `backend/seeds/overworld_species.json`

This is a **web-research data task**. Produce the union of National-Dex IDs that are
members of the three SV regional dexes — they stand in for "wild/overworld-available
in SV."

- [ ] **Step 1: Source the three regional dexes**

Web-source the species lists for:
- **Paldea Pokédex** (base SV regional dex, ~400 entries)
- **Kitakami Pokédex** (The Teal Mask DLC, ~200 entries)
- **Blueberry Pokédex** (The Indigo Disk DLC, ~240 entries)

Use Bulbapedia ("List of Pokémon by Paldea / Kitakami / Blueberry Pokédex number") or
Serebii's SV dex pages. Map each entry to its **National-Dex number** (not regional
number).

- [ ] **Step 2: Build the file**

Take the **union of unique National-Dex IDs** across the three dexes. **Omit
legendaries and mythicals** (Koraidon, Miraidon, the four Treasures of Ruin, the Loyal
Three + Ogerpon, Terapagos, Pecharunt, and any transferred box legends) — in SV these
are static/shiny-locked, not wild spawns. Write `backend/seeds/overworld_species.json`:

```json
{
  "Scarlet/Violet": [25, 906, 909, 912, 915, 921, ...]
}
```
(Sorted ascending, integers, no duplicates. The `...` is the rest of the sourced list —
the file must contain the complete list, not an ellipsis.)

- [ ] **Step 3: Validate the file**

Run:
```bash
cd backend && jq empty seeds/overworld_species.json && \
jq '.["Scarlet/Violet"] | length as $n | ([.[] | select(. < 1 or . > 1025)] | length) as $oob | ([.[]] | unique | length) as $u | {count:$n, out_of_range:$oob, unique:$u}' seeds/overworld_species.json
```
Expected: valid JSON; `out_of_range: 0`; `unique == count` (no dupes); `count` in the
**~390–450** range (sanity bound for the unioned SV dexes minus legendaries). If `count`
is far outside that range, re-check the sourcing before continuing.

- [ ] **Step 4: Commit**

```bash
git add backend/seeds/overworld_species.json
git commit -m "Add SV regional-dex species list for overworld eligibility"
```

---

## Task 3: Add the overworld-species seed step

**Files:**
- Modify: `backend/cmd/seed/main.go` (add `seedOverworldSpecies`; wire it into `main`)

- [ ] **Step 1: Add the seed function**

Add this function to `backend/cmd/seed/main.go` (near `seedCuratedEncounters`). It
mirrors the existing loader style and reuses `loadGameIDs`:

```go
// seedOverworldSpecies inserts curated wild encounter rows for games where PokeAPI
// provides no wild data (Gen 8/9). The source (seeds/overworld_species.json) maps a
// game title to the National-Dex IDs that are wild/overworld-encounterable there,
// taken from regional-dex membership. Legendaries/mythicals are guarded out — in
// these games they are static/shiny-locked, not wild spawns.
func seedOverworldSpecies(ctx context.Context) {
	data, err := os.ReadFile("seeds/overworld_species.json")
	if err != nil {
		log.Fatal("Failed to read overworld_species.json: ", err)
	}
	var byGame map[string][]int
	if err := json.Unmarshal(data, &byGame); err != nil {
		log.Fatal("JSON parse error in overworld_species.json: ", err)
	}
	gameIDs := loadGameIDs(ctx)
	inserted := 0
	for title, ids := range byGame {
		gameID, ok := gameIDs[title]
		if !ok {
			log.Printf("WARNING: overworld_species.json: unknown game title %q — skipping", title)
			continue
		}
		tag, err := database.DB.Exec(ctx, `
			INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
			SELECT p.id, $1, 'wild', 'none'
			FROM pokemon p
			WHERE p.id = ANY($2::int[]) AND NOT (p.is_legendary OR p.is_mythical)
			ON CONFLICT DO NOTHING
		`, gameID, ids)
		if err != nil {
			log.Fatalf("overworld_species: failed to insert wild rows for %s: %v", title, err)
		}
		inserted += int(tag.RowsAffected())
	}
	log.Printf("Inserted %d overworld wild encounter rows.", inserted)
}
```

- [ ] **Step 2: Wire it into the seed flow**

In `main` (`backend/cmd/seed/main.go`), add the call **after** `seedCuratedEncounters(ctx)`
and **before** `reconcileAvailability(ctx)` (currently around lines 84–88). Insert:

```go
	log.Println("Seeding overworld wild species (Gen 8/9 curated)...")
	seedOverworldSpecies(ctx)
```
so the order reads: `seedCuratedEncounters` → `seedOverworldSpecies` →
`reconcileAvailability` → `computeAvailability`.

- [ ] **Step 3: Build and vet**

Run:
```bash
cd backend && go build ./... && go vet ./cmd/seed/ && echo OK
```
Expected: `OK` (no compile/vet errors — confirms `loadGameIDs`/`database`/`os`/`json`
are all in scope, which they are in this file).

- [ ] **Step 4: Commit**

```bash
git add backend/cmd/seed/main.go
git commit -m "Seed curated overworld wild rows for Gen 8/9 games (SV)"
```

---

## Task 4: Re-seed and verify coverage against the database

**This task writes to the shared Supabase DB. Do NOT run it autonomously — it requires
explicit operator go-ahead.** Tasks 1–3 stand on their own (statically validated); this
task makes the change live.

**Files:** none (operational verification)

- [ ] **Step 1: Confirm go-ahead, then re-seed**

```bash
cd backend && go run ./cmd/seed/main.go
```
Expected: completes cleanly; log shows "Inserted N overworld wild encounter rows"
(N ≈ the SV list size minus any legendaries filtered); invariant checks pass; no fatals.

- [ ] **Step 2: Assert SV wild-method coverage rose from ~0**

Confirm (via `cmd/audit_methods` and/or a count) that the three SV wild methods now
attach to the seeded species. Expected counts ≈ the number of non-legendary SV species
seeded:
```sql
SELECT hm.method_name, COUNT(*) FROM method_availability ma
JOIN hunt_methods hm ON hm.id = ma.method_id
JOIN games g ON g.id = ma.game_id
WHERE g.title = 'Scarlet/Violet' AND hm.formula_type IN ('static','outbreak_defeats_sv','sandwich_power_sv')
  AND hm.method_name IN ('Random Encounter','Sandwich Hunting','Mass Outbreak')
GROUP BY hm.method_name;
-- expected: each ≈ seeded-species count, all non-zero
```

- [ ] **Step 3: Assert the Section A gap dropped and no new inconsistencies**

```bash
cd backend && go run ./cmd/audit_methods/main.go
```
Expected: Section A "Scarlet/Violet … missing" drops sharply from **412** (residual =
evolve-only/legendary species with no wild row — expected). Section B does not gain new
SV inconsistencies; Section C orphans = 0.

- [ ] **Step 4: Spot-check a known wild species and route de-duplication**

`GET /api/pokemon/915/route` (Lechonk) for a user owning Scarlet/Violet should return
**Random Encounter, Sandwich Hunting, and exactly one Mass Outbreak** route in SV — not
three outbreak routes.

---

## Task 5: Record slice A (SV) progress in TASKS.md

**Files:**
- Modify: `TASKS.md`

- [ ] **Step 1: Update the eligibility slice list**

Under the method-eligibility follow-up in `TASKS.md`, mark slice A's SV game done and
note the remaining games:

```markdown
  - ✅ **Slice A — Scarlet/Violet** — seeded curated `kind=wild` rows from SV regional-dex
    membership; Random Encounter / Sandwich Hunting / Mass Outbreak now attach. 3 area
    outbreaks collapsed into one. (spec/plan `docs/superpowers/*/2026-05-31-sv-overworld-eligibility*`).
    Remaining slice A games: Sword/Shield (KO Method, Run Away) and Legends: Arceus (Mass Outbreak).
```

- [ ] **Step 2: Commit**

```bash
git add TASKS.md
git commit -m "Record SV overworld eligibility (slice A, game 1) progress in TASKS.md"
```

---

## Final verification

- [ ] Exactly one SV `outbreak_defeats_sv` method named "Mass Outbreak" (Task 1).
- [ ] `overworld_species.json` valid, unique, in-range, ~390–450 SV IDs (Task 2).
- [ ] `go build ./...` + `go vet ./cmd/seed/` clean (Task 3).
- [ ] (If DB available) SV wild methods attach to the seeded species; Section A SV gap drops from 412; one Mass Outbreak route per species (Task 4).
