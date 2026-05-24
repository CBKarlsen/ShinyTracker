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

- **`internal/api/admin.go` references columns the schema no longer has.** Its
  queries use `hm.generation`, `hunt_methods.pokemon_id`, `hunt_methods.game_id`,
  and an `ON CONFLICT (pokemon_id, game_id, method_name)` constraint that does
  not exist in the current rules-based schema. Admin encounter create/import
  likely fail at runtime independent of recent changes.

- **`backend/update_json.go` is an orphaned generator.** It still uses the
  defunct `Generation` / `method_rules` / `method_exceptions` model and no longer
  matches the current `hunt_methods.json` shape.
