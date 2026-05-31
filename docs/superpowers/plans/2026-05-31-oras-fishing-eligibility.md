# ORAS Fishing Eligibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make ORAS fishable species huntable via Chain Fishing and DexNav by seeding curated `kind=wild, terrain='fishing'` rows from the ORAS rod roster.

**Architecture:** New game-keyed `seeds/fishing_species.json` + a `seedFishingSpecies` step in `cmd/seed` (a clone of `seedOverworldSpecies` that inserts `terrain='fishing'`). The existing derivation attaches Chain Fishing (terrain=fishing) and DexNav (terrain-any); `reconcileAvailability` backs availability. No schema change.

**Tech Stack:** JSON seed file, Go seed CLI (`cmd/seed`, `cmd/audit_methods`), `jq`. Shared Supabase DB only for the gated verification. Web research for the rod roster.

**Spec:** `docs/superpowers/specs/2026-05-31-oras-fishing-eligibility-design.md`

**Working directory:** main repo `/Users/casper/Fritidsprosjekt/ShinyTracker`, branch `oras-fishing-eligibility`. Run `go`/`jq` from `backend/`.

---

## Task 1: Research the ORAS fishing roster (data)

**Files:**
- Create: `backend/seeds/fishing_species.json`

Web-research task. Build the list of species catchable via **Old Rod, Good Rod, and
Super Rod anywhere in Omega Ruby/Alpha Sapphire** (all routes + Hoenn water areas).

- [ ] **Step 1: Source the roster**

From Bulbapedia/Serebii ORAS fishing tables, collect every species obtainable by any rod
in ORAS. Map to **National-Dex numbers**. Known members to expect (verify + extend):
Magikarp 129, Gyarados 130, Tentacool 72, Tentacruel 73, Wailmer 320, Wailord 321,
Carvanha 318, Sharpedo 319, Luvdisc 370, Corsola 222, Chinchou 170, Lanturn 171,
Clamperl 366, Relicanth 369, Barboach 339, Whiscash 340, Goldeen 118, Seaking 119,
Horsea 116, Seadra 117, Staryu 120, Starmie 121, Remoraid 223, Octillery 224, Feebas 349.
Include any others the tables show (e.g. Sharpedo/Wailord via Super Rod, Corsola areas).

- [ ] **Step 2: Write the file**

```json
{
  "Omega Ruby/Alpha Sapphire": [72, 73, 116, 117, 118, ...]
}
```
Sorted ascending, unique integers, all in range 1–1025. Replace `...` with the complete
roster — no ellipsis in the file.

- [ ] **Step 3: Validate**

```bash
cd backend && jq empty seeds/fishing_species.json && \
jq '.["Omega Ruby/Alpha Sapphire"] | {count: length, oob: ([.[]|select(.<1 or .>1025)]|length), unique: (unique|length)}' seeds/fishing_species.json
```
Expected: valid JSON; `oob == 0`; `unique == count`; `count` ~**20–32** (the rod roster).
If far outside that, re-check.

- [ ] **Step 4: Commit**

```bash
git add backend/seeds/fishing_species.json
git commit -m "Add ORAS fishing roster for Chain Fishing / DexNav eligibility"
```

---

## Task 2: Add the seedFishingSpecies step

**Files:**
- Modify: `backend/cmd/seed/main.go` (add `seedFishingSpecies`; wire into `main`)

- [ ] **Step 1: Add the function**

Add this to `backend/cmd/seed/main.go`, immediately after the existing
`seedOverworldSpecies` function (it is the same loader with `terrain='fishing'`):

```go
// seedFishingSpecies inserts curated wild encounter rows with terrain='fishing' for
// games where PokeAPI lacks fishing-terrain data (e.g. ORAS). Source maps a game title
// to the National-Dex IDs catchable via rods there. Legendaries/mythicals are guarded
// out. This is the terrain='fishing' sibling of seedOverworldSpecies.
func seedFishingSpecies(ctx context.Context) {
	data, err := os.ReadFile("seeds/fishing_species.json")
	if err != nil {
		log.Fatal("Failed to read fishing_species.json: ", err)
	}
	var byGame map[string][]int
	if err := json.Unmarshal(data, &byGame); err != nil {
		log.Fatal("JSON parse error in fishing_species.json: ", err)
	}
	gameIDs := loadGameIDs(ctx)
	inserted := 0
	for title, ids := range byGame {
		gameID, ok := gameIDs[title]
		if !ok {
			log.Printf("WARNING: fishing_species.json: unknown game title %q — skipping", title)
			continue
		}
		tag, err := database.DB.Exec(ctx, `
			INSERT INTO pokemon_game_encounter (pokemon_id, game_id, kind, terrain)
			SELECT p.id, $1, 'wild', 'fishing'
			FROM pokemon p
			WHERE p.id = ANY($2::int[]) AND NOT (p.is_legendary OR p.is_mythical)
			ON CONFLICT DO NOTHING
		`, gameID, ids)
		if err != nil {
			log.Fatalf("fishing_species: failed to insert fishing rows for %s: %v", title, err)
		}
		inserted += int(tag.RowsAffected())
	}
	log.Printf("Inserted %d fishing wild encounter rows.", inserted)
}
```

- [ ] **Step 2: Wire it into main()**

In `main` (`backend/cmd/seed/main.go`), the current order is:
```go
	log.Println("Seeding overworld wild species (Gen 8/9 curated)...")
	seedOverworldSpecies(ctx)

	log.Println("Reconciling pokemon_availability with encounters...")
	reconcileAvailability(ctx)
```
Insert the fishing step between them:
```go
	log.Println("Seeding fishing wild species (curated terrain=fishing)...")
	seedFishingSpecies(ctx)
```
Final order: `seedOverworldSpecies` → `seedFishingSpecies` → `reconcileAvailability` → `computeAvailability`.

- [ ] **Step 3: Build & vet**

```bash
cd backend && go build ./... && go vet ./cmd/seed/ && echo OK
```
Expected: `OK` (no new imports needed — same as `seedOverworldSpecies`).

- [ ] **Step 4: Commit**

```bash
git add backend/cmd/seed/main.go
git commit -m "Seed curated fishing-terrain wild rows (ORAS)"
```

---

## Task 3: Re-seed and verify (DB-gated)

**Writes to the shared Supabase DB — requires explicit operator go-ahead AND the user's
review of the roster from Task 1.** Tasks 1–2 stand alone (statically validated).

**Files:** none (operational verification)

- [ ] **Step 1: Confirm go-ahead + roster review, then re-seed**

```bash
cd backend && go run ./cmd/seed/main.go
```
Expected: clean run; "Inserted N fishing wild encounter rows" (N ≈ roster size);
invariant checks pass.

- [ ] **Step 2: Assert coverage rose from 0**

Confirm via `cmd/audit_methods` and/or a throwaway Go query (mirror the prior SV/SwSh
verifiers, then delete it). Targets:
```sql
SELECT hm.method_name, COUNT(*) FROM method_availability ma
JOIN hunt_methods hm ON hm.id = ma.method_id
JOIN games g ON g.id = ma.game_id
WHERE g.title = 'Omega Ruby/Alpha Sapphire' AND hm.method_name IN ('Chain Fishing','DexNav')
GROUP BY hm.method_name;
-- expected: Chain Fishing ≈ roster size (was 0); DexNav rises above its prior 108
```
If a throwaway verifier is created under `backend/cmd/`, remove it and confirm
`git status` shows no leftover.

- [ ] **Step 3: Audit clean**

```bash
cd backend && go run ./cmd/audit_methods/main.go
```
Expected: ORAS Section A "missing" drops from **36**; Sections B and C clean.

- [ ] **Step 4: Spot-check**

`GET /api/pokemon/129/route` (Magikarp) for an ORAS owner shows **Chain Fishing + DexNav**.

---

## Task 4: Record slice C + close out the eligibility pass in TASKS.md

**Files:**
- Modify: `TASKS.md`

- [ ] **Step 1: Mark slice C done and slice B dropped**

In `TASKS.md`, replace the Slice B and Slice C lines:
```markdown
  - ⏳ **Slice B** — Poké Radar over-broad (curate `method_exceptions` excludes to ~50-60 grass-patch species).
  - ⏳ **Slice C** — ORAS fishing terrain gap (Chain Fishing / DexNav-fishing have 0 fishing rows).
```
with:
```markdown
  - ❌ **Slice B — Poké Radar over-broad: DROPPED.** shiny-hunt-expert confirmed Radar draws from the full route grass table, so attaching it to all grass species is correct; an exclude list would wrongly remove chainable swarm/Trophy-Garden species. No change.
  - ✅ **Slice C — ORAS fishing** — `seeds/fishing_species.json` + `seedFishingSpecies` step seed `terrain='fishing'` wild rows for the ORAS rod roster; Chain Fishing now attaches in ORAS and DexNav picks up fishing-only species. (spec/plan `docs/superpowers/*/2026-05-31-oras-fishing-eligibility*`).
```

- [ ] **Step 2: Commit**

```bash
git add TASKS.md
git commit -m "Record ORAS fishing (slice C) done + Poké Radar (slice B) dropped"
```

---

## Final verification

- [ ] `fishing_species.json` valid; ORAS array unique, in-range, ~20–32 IDs (Task 1).
- [ ] `go build ./...` + `go vet ./cmd/seed/` clean (Task 2).
- [ ] (If DB available) ORAS Chain Fishing attaches to the roster, DexNav rises, Section A ORAS drops, audit B/C clean (Task 3).
- [ ] TASKS.md records slice C done + slice B dropped (Task 4).
