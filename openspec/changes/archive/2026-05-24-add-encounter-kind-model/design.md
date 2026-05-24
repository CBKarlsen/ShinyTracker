## Context

`method_availability(pokemon_id, method_id, game_id)` is the precomputed source of truth read by `GetHuntMethodsHandler` and `/api/methods`. It is built once in `cmd/seed/main.go:computeAvailability` from three inputs:

1. `method_games` — which games a method maps to (kept; correct).
2. `method_rules` — a flag condition per method (`always_true`, `is_breedable`, `not_legendary_or_mythical`).
3. `method_exceptions` — 585 per-Pokémon include/exclude patches.

The rule join (`cmd/seed/main.go:167`) inserts `(pokemon, method, game)` for every game a method maps to whenever its flag condition passes. `always_true` methods (Soft Reset, Dynamax Adventures, Sandwich) therefore attach to *every* Pokémon in their listed games, and the join never references `pokemon_availability`. This produces the Rayquaza-in-SwSh bug and is unscalable: correctness depends on hand-patching exceptions.

The real-world fact is a three-way relationship — a method is valid for a Pokémon in a game only if that Pokémon is encountered *in a way the method consumes* in that game. Flags approximate this and break at the edges.

## Goals / Non-Goals

**Goals:**
- Make `method_availability` derived from encounter facts, not flag heuristics.
- Auto-derive the high-volume kinds (`wild`, `egg`) so they need zero manual upkeep.
- Reduce `static`/`raid` curation to a compact, templated per-Pokémon entry.
- Catch inconsistent availability at seed time instead of in production.
- Keep the existing API contracts (`/api/hunt-methods`, `/api/methods`) unchanged.

**Non-Goals:**
- No changes to odds/ETA math (`internal/calc/odds.go`) or `formula_type`.
- No frontend behavior change beyond more accurate method lists.
- Not modeling sub-kinds (fishing/surfing) — those stay attributes of `wild` if needed later.
- Not curating every static/gift in the dex up front; legendaries/mythicals first, ordinary statics can be added incrementally.

## Decisions

### Decision 1: A `pokemon_game_encounter(pokemon_id, game_id, kind)` table as the new fact source
`kind` is a constrained enum: `wild | static | raid | egg`. Availability becomes:
```sql
INSERT INTO method_availability (pokemon_id, method_id, game_id)
SELECT pge.pokemon_id, hm.id, pge.game_id
FROM pokemon_game_encounter pge
JOIN hunt_methods hm   ON hm.requires_kind = pge.kind
JOIN method_games mg   ON mg.method_id = hm.id AND mg.game_id = pge.game_id
ON CONFLICT DO NOTHING;
```
A method appears only where the Pokémon actually has the consumed kind **and** the method is mapped to that game. `pokemon_availability` is implicitly respected because every `pge` row is gated by real availability when derived/curated.

*Alternative considered:* keep flags but add per-game flag overrides. Rejected — it grows the exception problem rather than removing it.

### Decision 2: `hunt_methods.requires_kind` column instead of a separate mapping table
Each method consumes exactly one kind, so a column is simpler than a join table. Mapping: Random Encounter / SOS / Poké Radar / DexNav / Friend Safari / Catch Combo / Chain Fishing / Mass Outbreak / Sandwich → `wild`; Soft Reset → `static`; Dynamax Adventures / KO Method → `raid`; Masuda Method → `egg`. Stored in `hunt_methods.json`.

### Decision 3: Auto-derive `wild` and `egg`
- `wild`: from PokeAPI `/pokemon/{id}/encounters`. Any encounter whose version belongs to game G ⇒ `(pokemon, G, wild)`. Version→game mapping reuses the existing logic in `internal/services/pokeapi.go`. **Legendaries/mythicals are excluded** — PokeAPI reports their stationary encounters as location encounters, which would be misclassified as wild; their kinds come solely from curated `static`/`raid` records. (The seed also purges any pre-existing legendary `wild` rows so a re-seed is self-correcting without re-syncing.)
- `egg`: a species in a breedable egg group (not `no-eggs`/`undiscovered`) whose base form is available in G ⇒ `(base_form? no — the species being hunted, pokemon_id, G, egg)`. Derived by joining species egg groups with `pokemon_availability`.

These two cover the vast majority of rows with no manual entry.

### Decision 4: Curate `static`/`raid` via `legendary_encounters.json` with a default kind over a listed game set
```json
{
  "pokemon_id": 384,
  "name": "Rayquaza",
  "default_kind": "static",
  "default_games": ["Ruby/Sapphire/Emerald", "Omega Ruby/Alpha Sapphire"],
  "overrides": { "@swsh-dynamax": "raid" }
}
```
The set of games covered is `default_games` (each gets `default_kind`) plus the keys of `overrides` (each gets its override value). Game-group aliases live in `game_groups.json` (`"@swsh-dynamax": ["Sword/Shield"]`) and expand in both `default_games` and `overrides`; an explicit per-game override wins over a group override. `none` suppresses a game pulled in by a group alias. A `pge` row is inserted for every covered game whose resolved kind is not `none`.

**Why not expand against `pokemon_availability`:** that table is only seeded for Switch-era games (`cmd/seed_availability` maps SV/SwSh/PLA/BDSP/LGPE), so a default of "everywhere it's available" would silently drop legitimate static encounters in RSE, ORAS, DPPt, etc. The games where a legendary is a static/raid encounter *is* the curated fact, so it is listed directly and validated against the `games` table. (`egg` derivation still uses `pokemon_availability`, since every Masuda method is mapped only to Switch games anyway.)

*Alternative considered:* one explicit row per `(pokemon, game, kind)`. Rejected — verbose and re-introduces repetition that drifts out of sync.

### Decision 5: Seed-time invariant checks
After `computeAvailability`, assert and fail the seed (non-zero exit) on:
- a `method_availability` row whose method's `requires_kind` has no matching `pge` row (should be impossible by construction — guards regressions),
- any `requires_kind` value not in the enum,
- any `legendary_encounters.json` override referencing an unknown game/group or a game where the Pokémon has no `pokemon_availability` row.
This turns silent data errors into loud build failures.

## Risks / Trade-offs

- **PokeAPI encounters are incomplete for some games/regions** → wild kind may be under-reported. Mitigation: allow `legendary_encounters.json`-style overrides to add `wild` too (a general `encounter_overrides.json`), and surface a gap report.
- **`egg` derivation can over-report** (line available but evolution-locked in that game) → Mitigation: gate on base-form availability and allow explicit `none` overrides; spot-check breeders.
- **Curating static/raid is still manual knowledge** → Mitigation: the default+override format keeps each entry to a few lines; legendaries follow a predictable origin=`static`, later-games=`raid`/`none` pattern; add an admin matrix to eyeball results against Serebii.
- **One-time data migration** rebuilds `method_availability` for all users → Mitigation: it is a pure recompute from seeds + PokeAPI, fully reproducible; no user data is touched (`user_hunts` references `hunt_methods.id`, which is preserved).

## Migration Plan

1. Add schema: `pokemon_game_encounter`, `hunt_methods.requires_kind`; keep old tables temporarily.
2. Extend PokeAPI sync to persist wild encounters + egg groups.
3. Add `legendary_encounters.json` + `game_groups.json`; set `requires_kind` in `hunt_methods.json`.
4. Rewrite `computeAvailability`: derive `wild`/`egg`, expand curated `static`/`raid`, build `method_availability` via the kind join, run invariant checks.
5. Re-seed; verify Rayquaza (Soft Reset/Dynamax gone in SwSh, present where correct) and a sample of legendaries + common wild/breedable Pokémon.
6. Drop `method_rules` and the old flag columns once verified. **Rollback:** revert seed + restore prior `method_availability` snapshot; old tables remain until step 6.

## Open Questions

- Should `requires_kind` be one-to-many eventually (e.g. a method valid for both `static` and `raid`)? Start one-to-one; revisit if a real method needs it.
- Do we curate ordinary (non-legendary) gift/static encounters now, or defer? Proposed: defer; legendaries are the high-value fix.
