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

- **`go build ./...` fails in `backend/`.** Several root-level scratch files
  (`check_charmander.go`, `inspect_pikachu.go`, `migrate.go`, `update_json.go`)
  and `cmd/apply_schema/{main,alter}.go` each declare `func main()` in the same
  package, causing duplicate-`main` compile errors. Individual packages
  (`cmd/seed`, `internal/...`, `cmd/sync_encounters`, `cmd/api`) build fine.
  Cleanup: move scratch files out of buildable packages or behind build tags.

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
