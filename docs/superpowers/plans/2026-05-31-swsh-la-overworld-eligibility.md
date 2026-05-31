# Sword/Shield + Legends: Arceus Overworld Eligibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Sword/Shield and Legends: Arceus overworld species huntable via their wild methods (KO Method, Run Away; Mass Outbreak) by adding two game keys to `overworld_species.json`.

**Architecture:** Pure data + re-seed. The `seedOverworldSpecies` loader and the game-keyed `seeds/overworld_species.json` already exist (SV slice). Add `"Sword/Shield"` and `"Legends: Arceus"` keys; the existing seed step + derivation do the rest. **No code or schema changes.**

**Tech Stack:** JSON seed file, `jq`, Go seed CLI (`cmd/seed`, `cmd/audit_methods`). Shared Supabase DB only for the gated verification task. Web research for the two dex lists.

**Spec:** `docs/superpowers/specs/2026-05-31-swsh-la-overworld-eligibility-design.md`

**Working directory:** main repo `/Users/casper/Fritidsprosjekt/ShinyTracker`, branch `gen89-overworld-eligibility`. Run `go`/`jq` from `backend/`.

---

## Task 1: Add Galar + Hisui dex lists to overworld_species.json (data)

**Files:**
- Modify: `backend/seeds/overworld_species.json` (add two keys alongside the existing `"Scarlet/Violet"`)

Web-research task. The file currently has one key (`"Scarlet/Violet"`). Add two more.

- [ ] **Step 1: Source the dexes**

Web-source these regional dexes and map every entry to its **National-Dex number**:
- **Sword/Shield:** union of the **Galar Pokédex** (base, ~400) + **Isle of Armor Pokédex** + **Crown Tundra Pokédex**.
- **Legends: Arceus:** the **Hisui Pokédex** (~242).

Use Bulbapedia ("List of Pokémon by Galar / Isle of Armor / Crown Tundra / Hisui Pokédex number") or the PokeAPI pokédex endpoints (`galar`, `isle-of-armor`, `crown-tundra`, `hisui`) — the same source used for the SV list.

- [ ] **Step 2: Exclude legendaries/mythicals per game**

Omit legendaries/mythicals from both lists (a seed-time DB guard backstops this, but exclude in-file for clarity):
- **Sword/Shield:** Zacian (888), Zamazenta (889), Eternatus (890), Kubfu (891), Urshifu (892) [story gift — keep OUT of wild], Calyrex (898), Glastrier (896), Spectrier (897), Regieleki (894), Regidrago (895), Regis (377–379, 486), Keldeo (647), Cosmog (789) if present, and the 38 Dynamax Adventure legendaries (they are `is_legendary` and already seeded as `raid`). The Galarian birds and Galarian legendary forms are not separate base IDs, so no extra handling.
- **Legends: Arceus:** Arceus (493), the Lake trio (480–482), Dialga/Palkia (483/484), Heatran (485), Regigigas (486), Cresselia (488), Darkrai (491), Shaymin (492), Manaphy/Phione (490/489), Enamorus (905), and the noble/Hisui legendary statics. Keep ordinary wild Hisui species (e.g. Bidoof #399, Kricketot, the Hisui regional evolutions' base IDs).

- [ ] **Step 3: Write the two keys**

Edit `backend/seeds/overworld_species.json` so it reads (Scarlet/Violet array unchanged):
```json
{
  "Scarlet/Violet": [ ...existing 650... ],
  "Sword/Shield": [1, 4, 7, ...],
  "Legends: Arceus": [25, 35, 396, 399, ...]
}
```
Arrays sorted ascending, unique integers, in range 1–1025. The `...` must be replaced
with the complete sourced lists — no ellipsis in the file.

- [ ] **Step 4: Validate**

Run:
```bash
cd backend && jq empty seeds/overworld_species.json && \
jq 'to_entries | map({game: .key, count: (.value|length), oob: ([.value[]|select(.<1 or .>1025)]|length), unique: (.value|unique|length)})' seeds/overworld_species.json
```
Expected: valid JSON; for every game `oob == 0` and `unique == count`; `Sword/Shield`
count ~**350–420**; `Legends: Arceus` count ~**220–242**; `Scarlet/Violet` still **650**.
If a count is far outside its band, re-check the sourcing.

- [ ] **Step 5: Commit**

```bash
git add backend/seeds/overworld_species.json
git commit -m "Add Galar + Hisui dex species lists for SwSh/LA overworld eligibility"
```

---

## Task 2: Re-seed and verify (DB-gated)

**Writes to the shared Supabase DB — requires explicit operator go-ahead AND the user's
review of both lists from Task 1.** Task 1 stands alone (statically validated).

**Files:** none (operational verification)

- [ ] **Step 1: Confirm go-ahead + list review, then re-seed**

```bash
cd backend && go run ./cmd/seed/main.go
```
Expected: clean run; the "Inserted N overworld wild encounter rows" line rises by the
SwSh + LA seeded counts (minus any legendaries filtered); invariant checks pass.

- [ ] **Step 2: Assert coverage rose from ~0**

Confirm via a count (psql isn't installed; use `cmd/audit_methods` output or a throwaway
Go query mirroring the SV verification, then delete it):
```sql
SELECT g.title, hm.method_name, COUNT(*) FROM method_availability ma
JOIN hunt_methods hm ON hm.id = ma.method_id
JOIN games g ON g.id = ma.game_id
WHERE g.title IN ('Sword/Shield','Legends: Arceus')
  AND hm.method_name IN ('KO Method','Run Away','Mass Outbreak')
GROUP BY g.title, hm.method_name ORDER BY g.title, hm.method_name;
-- expected: SwSh KO Method & Run Away each ≈ SwSh seeded count; LA Mass Outbreak ≈ LA seeded count; all non-zero
```
If a throwaway verifier is created under `backend/cmd/`, remove it before finishing and
confirm `git status` shows no leftover.

- [ ] **Step 3: Assert Section A dropped and audit clean**

```bash
cd backend && go run ./cmd/audit_methods/main.go
```
Expected: Section A "Sword/Shield … missing" drops from **133**, "Legends: Arceus" from
**213** (residual = evolve-only/legendary species — expected). Sections B and C clean
(no new inconsistencies; orphans = 0).

- [ ] **Step 4: Spot-checks**

`GET /api/pokemon/831/route` (Wooloo) for a Sword/Shield owner shows **KO Method + Run
Away**; `GET /api/pokemon/399/route` (Bidoof) for a Legends: Arceus owner shows **Mass
Outbreak**.

---

## Task 3: Record progress in TASKS.md

**Files:**
- Modify: `TASKS.md`

- [ ] **Step 1: Mark slice A complete**

In `TASKS.md`, update the slice-A entry: change the SwSh/LA sub-line from `⏳` to `✅`
and mark slice A done across all three games. Replace the line that currently reads:

```markdown
    - ⏳ **Sword/Shield** (KO Method, Run Away) and **Legends: Arceus** (Mass Outbreak) — add their species lists to `overworld_species.json` (the loader is game-keyed and reusable).
```
with:
```markdown
    - ✅ **Sword/Shield** (KO Method, Run Away) and **Legends: Arceus** (Mass Outbreak) — Galar + Hisui dex species lists added to `overworld_species.json`; methods now attach. SwSh/LA Section-A gaps cleared (spec/plan `docs/superpowers/*/2026-05-31-swsh-la-overworld-eligibility*`). **Slice A complete across SV/SwSh/LA.**
```
Also change the slice-A header line from `🟡` to `✅`.

- [ ] **Step 2: Commit**

```bash
git add TASKS.md
git commit -m "Record SwSh + LA overworld eligibility (slice A complete) in TASKS.md"
```

---

## Final verification

- [ ] `overworld_species.json` valid; all three game arrays unique + in-range; SwSh ~350–420, LA ~220–242, SV 650 (Task 1).
- [ ] (If DB available) SwSh KO Method/Run Away and LA Mass Outbreak attach to their seeded species; Section A SwSh 133→low, LA 213→low; audit B/C clean (Task 2).
- [ ] TASKS.md marks slice A complete (Task 3).
