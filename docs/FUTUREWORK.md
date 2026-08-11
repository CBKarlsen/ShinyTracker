# Future Work

Known limitations and follow-ups, recorded so they aren't lost.

## Hunt-method availability (terrain granularity)

The wild-encounter terrain model (`pokemon_game_encounter.terrain` +
`hunt_methods.requires_terrain`) restricts Poké Radar to `grass` and Chain
Fishing to `fishing`. Remaining gaps:

- **PokeAPI `walk` conflates grass and caves.** The terrain bucketer maps the
  PokeAPI `walk` method to `grass`, but `walk` also covers cave floors. So a
  cave-only Pokémon is classified `grass` and will still incorrectly show Poké
  Radar (which only works in tall grass). Fixing this needs location-area /
  encounter-condition parsing from PokeAPI, not just the method name.
  - Code: `backend/internal/services/pokeapi.go` (`methodTerrain`, `terrainForMethod`).

- **Friend Safari (X/Y) is over-broad.** Friend Safari is a type-based pool, not
  a terrain, so it currently attaches to every X/Y wild Pokémon. Scoping it
  correctly requires a curated per-type pool (a separate data source), not the
  terrain mechanism. It is intentionally left as `requires_terrain = NULL`.

- **Gen 8/9 (SwSh / BDSP / SV / Legends: Arceus) have no terrain data.** PokeAPI
  does not expose wild encounters for these games, so their wild rows carry no
  real terrain. No current method is terrain-restricted in those generations, so
  there is no present impact — but any future terrain-restricted Gen 8/9 method
  would need another data source.

- **`requires_terrain` is single-valued.** A method can require exactly one
  terrain or any. If a future method needs "grass OR surf but not fishing", this
  must become a method↔terrain many-to-many. Deferred (YAGNI).

## Pre-existing issues discovered (unrelated to the terrain change)

- ✅ **`go build ./...` duplicate-`main` failure — FIXED.** The root-level scratch
  files (`check_charmander.go`, `check_encounters.go`, `inspect_pikachu.go`,
  `migrate.go`, `update_json.go`) and `cmd/apply_schema/alter.go` all carry
  `//go:build ignore` and are excluded from the build; run them with `go run`.
  Verified 2026-08-09: `go build ./...`, `go vet ./...`, and `go test ./...` are
  all clean.

## Toolchain

- **Node must be arm64 and >= 20.19.** `/usr/local/bin/node` is an **x64** Node
  19 running under Rosetta, which breaks the frontend two ways at once:
  `npm run build` fails (Vite 8 requires Node 20.19+/22.12+), and `npm run lint`
  fails to resolve its native binary (Biome picks a platform package from
  `process.arch`, so an x64 process looks for `@biomejs/cli-darwin-x64` while
  only `cli-darwin-arm64` is installed). Use the arm64 Homebrew build:
  `export PATH="/opt/homebrew/opt/node@20/bin:$PATH"` (v20.19.2). Both commands
  pass under it.

- **The frontend has never been linted on this machine**, because of the above.
  With Biome actually running there are 184 errors / 69 warnings, all
  pre-existing. Dominated by accessibility: `useButtonType` (52),
  `useKeyWithClickEvents` (25), `noStaticElementInteractions` (24),
  `noSvgWithoutTitle` (22) — which sits badly against the WCAG AA and
  keyboard-accessibility commitments in `PRODUCT.md`. Then `noExplicitAny` (36),
  `noNonNullAssertion` (14), `organizeImports` (14),
  `useExhaustiveDependencies` (8). Note that `biome check --write` also applies
  the **formatter**, which rewrites ~760 lines across 31 previously-unformatted
  files including `utils/odds.ts` — do that as its own isolated commit, never
  mixed into a feature branch.

- **Admin hunt-methods is now read-only + global-edit (was schema-broken).**
  The old admin "encounters per Pokémon" CRUD assumed the pre-migration
  `hunt_methods(pokemon_id, game_id, ...)` shape. It has been reworked for the
  rules-based model: the per-Pokémon list is a read-only view of derived
  `method_availability`, and edit/delete act on the GLOBAL method by id. The
  create endpoint and CSV import were removed (per-Pokémon method rows are no
  longer meaningful — methods are global and availability is computed by
  `cmd/seed`). Future work: a proper global Method Library editor (create
  methods + `method_games` mappings) if admin method authoring is needed.

- **`backend/update_json.go` is an orphaned generator.** It still uses the
  defunct `Generation` / `method_rules` / `method_exceptions` model and no longer
  matches the current `hunt_methods.json` shape.

## Non-shiny ("just catch it") lookups — blockers found 2026-08-10

Scoping a catch-oriented mode surfaced three facts about the shipped code. The
design was parked, but these are properties of the codebase, not opinions:

- **Shiny locks block catch lookups.** `computeAvailability` (`cmd/seed/main.go`)
  excludes shiny-locked `(pokemon, game)` pairs from `method_availability`
  entirely, and `PokemonRouteHandler` returns `locked_everywhere` with zero
  routes. A shiny-locked Pokémon is still catchable normally, so any catch-mode
  feature must read `pokemon_locations` directly and ignore both `shiny_locks`
  and `method_availability`.

- **Gift/static/raid encounters are discarded at ingest.** `ParseLocations`
  (`internal/services/pokeapi.go`) drops `gift`, `gift-egg`, `static`,
  `wanderer`, `max-raid`, `only-one` and `colosseum-*`. That is correct for wild
  shiny routes — they were ranking a Game Corner prize counter as the best place
  to stand — but it means the data cannot answer "how do I get Charmander"
  (a gift starter). Fixing it means an `encounter_kind` column and a re-seed
  rather than a denylist at parse time; the seed is idempotent and takes ~22s.

- **Encounter rates are per slot and are displayed unaggregated.** A species
  occupying two fishing slots on one route renders as two rows (e.g. Kalos Route
  22 at 60% and again at 35%) when the honest figure is one row at 95%. The rod
  (`pokeapi_method`) is stored but never displayed, so those rows look like
  duplicates and a player cannot tell which rod is required. Fix: group by
  `(area, kind, method, levels, conditions)` and sum chances after the version
  dedup, and render the method label when it is not `walk`.
