# Pokémon Locations (Layer 0) — Design

**Date:** 2026-08-09
**Branch:** spec committed on `fix/security-hardening`; implementation branches fresh from `master` as `feat/pokemon-locations`
**Backlog item:** new — first slice of the three-persona product expansion
**Status:** approved design, pending implementation plan

## Context: why this slice exists

ShinyTracker is being expanded from a shiny-hunt tracker into a single app serving
three audiences:

- **Nuzlockers** — run tracking, per-route first encounters
- **Normal players** — game information without googling
- **Shiny hunters** — the existing product

All three need the same missing foundation: **where a Pokémon can actually be
found, per game**. Nothing above this layer works without it. The persona
surfaces (nuzlocke run tracker, dex browser) are separate later slices, each with
its own spec.

The strategic bet is *personalized* reference data, not reference data. Serebii
and Bulbapedia answer "where do I find Gible". They cannot answer "where do I
find Gible in the three games you own, which you still need shiny".

## Problem

The app has **no location data at all**. A route today says "Poké Radar in
Diamond/Pearl/Platinum, 1/2048, ~4.2h" — it never says *where to stand*.

The data is already flowing through the crawler and being discarded.
`internal/services/pokeapi.go` fetches `/pokemon/{id}/encounters` in
`syncWildEncounters` (line ~341), and `PokeAPIEncounter` (line 40) already
decodes `location_area.name`. The response also carries `min_level`, `max_level`,
`chance`, and `condition_values`, which the struct does not decode. All of it is
collapsed into a boolean "has a wild encounter here" plus a terrain bucket, then
thrown away.

So this is not a data-sourcing project for Gen 2–7. It is a struct widening, a
table, and a seed command over a crawl that already runs.

## Decisions (locked during brainstorming)

- **Version column, not a games-table split.** Location rows carry both `game_id`
  and a `version` string (`'platinum'`). The `games` table groups versions
  (`versionMap` maps diamond/pearl/platinum onto one row), which is correct for
  odds and methods but wrong for locations — Platinum rebuilt much of Sinnoh's
  encounter tables and D/P exclusives differ. The version column is lossless and
  requires no migration to `games`, `user_games`, `pokemon_availability`,
  `method_availability`, `shiny_locks`, `user_hunts`, or the odds engine.
- **Gen 2–7 only. Gen 1 deferred.** PokeAPI has encounter data for Gen 1–7, but
  `SeedGames` deliberately has **no Red/Blue/Yellow row** (no shinies in Gen 1).
  Locations key off `game_id`, so Gen 1 would require creating that row, which
  then appears in the game picker, `user_games`, and the `pokemon_availability`
  denominators `DexStatusHandler` computes over — offering a shiny-hunting UI a
  game without shinies. Gen 1 gets its own later slice together with a
  `games.supports_shinies` flag.
- **Gen 8/9, BDSP, LGPE, LA render an honest empty state**, and are excluded from
  seeding by an explicit `generation BETWEEN 2 AND 7` filter.

  > **Correction (found during the whole-branch review).** This decision was
  > originally justified by two claims that are both false: that PokeAPI has no
  > encounter data for those games, and that they "fall out naturally" because
  > `versionMap` has no keys for them. `versionMap` in fact contains `sword`,
  > `shield`, `scarlet`, `violet`, `legends-arceus`, `brilliant-diamond`,
  > `shining-pearl` and `lets-go-*`, and PokeAPI genuinely serves SwSh and LGPE
  > encounters (Pikachu returns 11 SwSh rows).
  >
  > The exclusion is kept, but for the real reason: coverage would be **silently
  > partial**. The DLC version names (`the-isle-of-armor-sword` / `-shield`, and
  > the Crown Tundra equivalents) are absent from `versionMap`, so those areas
  > would be dropped without warning, and Max Raid dens would be presented as wild
  > spots. Half-covered data that looks complete is worse than an honest gap.
  >
  > Gen 8 is therefore cheap follow-up work, not a data-sourcing project: add the
  > DLC version keys, widen the generation filter, and verify BDSP/LA/SV coverage
  > (SV and LA appear to have no PokeAPI encounter data; SwSh and LGPE do).
- **Separate seed command, not an extension of `cmd/sync`.** `cmd/sync` truncates
  `hunt_methods` (cascading `method_availability` to 0), and re-running it on the
  live shared DB is flagged unsafe. A standalone command is independently
  re-runnable.
- **No new API endpoint.** Locations ride along on the existing route response.
- **UI surfaces via `RouteList` only.** The reverse index (area → species) is the
  nuzlocke primitive and the schema supports it, but nothing consumes it until
  the nuzlocke tracker exists. Not built now.

## Design

### 1. Schema

One new table. No changes to any existing table.

```sql
CREATE TABLE IF NOT EXISTS pokemon_locations (
    id             SERIAL PRIMARY KEY,
    pokemon_id     INTEGER NOT NULL REFERENCES pokemon(id) ON DELETE CASCADE,
    game_id        INTEGER NOT NULL REFERENCES games(id)   ON DELETE CASCADE,
    version        TEXT    NOT NULL,   -- PokeAPI version name, e.g. 'platinum'
    area           TEXT    NOT NULL,   -- PokeAPI slug, e.g. 'route-210-area'
    terrain        TEXT    NOT NULL,   -- from the existing terrainForMethod bucketer
    pokeapi_method TEXT    NOT NULL,   -- 'walk', 'surf', 'old-rod', ...
    min_level      INTEGER,
    max_level      INTEGER,
    chance         INTEGER,            -- percent
    conditions     TEXT[]              -- 'time-night', 'season-spring', ...
);

CREATE INDEX IF NOT EXISTS idx_pokemon_locations_pokemon_game
    ON pokemon_locations (pokemon_id, game_id);
CREATE INDEX IF NOT EXISTS idx_pokemon_locations_game_area
    ON pokemon_locations (game_id, area);
```

Surrogate primary key rather than a natural one: `min_level`/`max_level` are
nullable and a nullable component in a primary key is a correctness trap.
Seeding is delete-then-insert per Pokémon, so no upsert path is needed.

`terrain` is denormalized onto the row deliberately — it is what the route join
matches on, and recomputing it per query from `pokeapi_method` would duplicate
`terrainForMethod` in SQL.

The `(game_id, area)` index is the reverse lookup. It costs nothing now and is
exactly what the nuzlocke slice will need.

### 2. Crawler widening

Extend `PokeAPIEncounter` in `internal/services/pokeapi.go` to decode the fields
already present in the response body:

```go
EncounterDetails []struct {
    Method          struct{ Name string } `json:"method"`
    MinLevel        int                   `json:"min_level"`
    MaxLevel        int                   `json:"max_level"`
    Chance          int                   `json:"chance"`
    ConditionValues []struct{ Name string } `json:"condition_values"`
}
```

Same endpoint, same request count, same rate limiting. `terrainForMethod` is
reused unchanged so `pokemon_locations.terrain` stays consistent with
`pokemon_game_encounter.terrain`.

`syncWildEncounters` keeps its current behaviour untouched — this slice adds a
reader, it does not change how wild-encounter kinds are derived.

### 3. Seed command

New `cmd/seed_locations`, following the existing 5-worker pool pattern.

Per Pokémon:
1. `GET /pokemon/{id}/encounters`
2. For each `(location_area, version, encounter_detail)`: map `version` →
   `game_id` via a map built from `SELECT id, title FROM games WHERE generation
   BETWEEN 2 AND 7`; skip versions absent from that map (Gen 1 falls out because
   it has no game row; Gen 8/9 are excluded by the generation filter — see the
   correction under Decisions, they do NOT fall out via `versionMap`)
3. `DELETE FROM pokemon_locations WHERE pokemon_id = $1`
4. Batch insert the rows

Idempotent and independently re-runnable. Does not touch `hunt_methods`, so it
carries no seed-order hazard and can run against the live DB without a rebuild.

Logs a per-game row count on completion.

### 4. API

`GET /api/pokemon/{id}/route` is unchanged in shape except that each `Route`
gains a `locations` array.

```go
type Location struct {
    Area       string   `json:"area"`
    Version    string   `json:"version"`
    Terrain    string   `json:"terrain"`
    MinLevel   int      `json:"min_level"`
    MaxLevel   int      `json:"max_level"`
    Chance     int      `json:"chance"`
    Conditions []string `json:"conditions"`
}
// added to calc.Route:
Locations []Location `json:"locations"`
```

Matching reuses existing machinery. A route already knows its `game_id` and its
`hunt_methods.requires_terrain`:

- `requires_terrain` set → locations for that game whose `terrain` matches
- `requires_terrain` NULL (any) → all locations for that game
- routes whose method `requires_kind` is `egg`, `static`, or `raid` → empty list;
  Masuda and soft-resets have no location

Capped at the top 5 per route, ordered by `chance DESC NULLS LAST, area ASC`, so
the payload stays bounded for species with large encounter tables.

Fetched in a single query covering every route in the response (rows grouped by
game and terrain in Go), not one query per route.

### 5. Frontend

- `types/models.ts` — add the `Location` type, add `locations` to `Route`
- `features/routes/RouteList.tsx` — render locations beneath each route. Because
  the drawer and the New Hunt modal already share this component via
  `usePokemonRoute`, both surfaces get it from one change.
- Area slug display: a one-line title-case helper (`route-210-area` →
  "Route 210"), stripping the trailing `-area`. Not a name-mapping table.
- Conditions render as short chips ("Night", "Spring"); level range and chance
  render inline: `Route 210 — tall grass · Lv 20–24 · 15% · Night`
- Games with no location data render a muted "No location data for this game yet"
  rather than an empty region, so a gap never reads as "nowhere to find it"

### 6. Verification

- **Go unit test** over a captured PokeAPI encounter payload fixture, asserting:
  version → `game_id` mapping, terrain bucketing, level/chance/condition parsing,
  and that unmapped versions are skipped rather than defaulted
- **Post-seed SQL check**: row count per game, asserting every Gen 2–7 game is
  non-zero — catches a silently-empty crawl, which is the realistic failure mode
- **Route-join check**: one test that an egg/static/raid route returns an empty
  location list and a terrain-restricted method returns only matching terrain

## Out of scope (each its own later slice)

- Gen 1 locations + `games.supports_shinies`
- Curated Gen 8/9 / BDSP / LGPE / LA location data
- Reverse index UI (area → species) — schema supports it, nothing consumes it yet
- The nuzlocke run model
- Species reference data (stats, abilities, moves, evolution requirements)
- Forms and variants (still capped at 1025 base species)

## Risks

- **Row volume.** Roughly 100k+ rows across Gen 2–7. Trivial for Postgres, but
  the `(pokemon_id, game_id)` index is required, not optional, for the route join.
- **Location slugs are inconsistent.** PokeAPI area names vary in verbosity
  (`kanto-route-2-south-towards-viridian-city`). The title-case helper will
  produce some long labels. Accepted; a curated display-name table is not
  warranted until it demonstrably reads badly.
- **`chance` is per encounter-slot, not per encounter.** PokeAPI reports slot
  rates, so multiple rows for one species in one area can sum above the true
  aggregate. Displayed as-is per row rather than summed, which is what other
  reference sites do.
