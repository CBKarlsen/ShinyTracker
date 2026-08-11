# Backend

## Seed / migrate commands

```bash
go run ./cmd/api/main.go              # API server on :8080
go run ./cmd/seed/main.go             # Seed Pokemon + encounters from PokeAPI
go run ./cmd/seed_availability/main.go # Populate pokemon_availability table
go run ./cmd/seed_fulldex/main.go     # Seed recommended methods from FullDexMethods.csv
go run ./cmd/seed_methods/main.go     # Seed encounter methods from CSV
go run ./cmd/truncate_encounters/main.go # Clear encounters for re-seeding
go run ./cmd/migrate_locations/main.go  # Create pokemon_locations (additive, safe to re-run)
go run ./cmd/seed_locations/main.go     # Seed Gen 2-7 encounter locations from PokeAPI
go run ./cmd/seed_moves/main.go         # Seed base stats, abilities (full) + Platinum/Scarlet-Violet movesets from PokeAPI
```

## Retired one-off commands

These `cmd/` tools were deleted in the 2026-08-11 cleanup. Each was a one-shot
migration whose change is now baked into `schema.sql` and verified present in the
live database, so re-running them would at best be a no-op:

| Retired | What it did | Now |
|---|---|---|
| `migrate_phases` | created `hunt_phases` | table exists |
| `migrate_total_time` | added `user_hunts.total_time_seconds` | column exists |
| `migrate_custom_method` | added `user_hunts.custom_method_name` | column exists |
| `migrate_encounter_kind` | added `pokemon_game_encounter.kind` | column exists |
| `migrate_supabase_auth` | swapped local users for Supabase Auth | `profiles` exists, `users` dropped |
| `verify_auth_migration` | checked the above | its subject is done |
| `seed_methods` | CSV importer | dead: inserted into `hunt_methods.pokemon_id`, a column that no longer exists |
| `migrate_schema` | early schema rebuild | **`DROP TABLE user_hunts CASCADE` with no confirmation** — deleted every hunt if run. Removed as a hazard, not just as clutter. |

Schema changes now go through numbered files in `backend/migrations/`, applied by
the operator. Do not reintroduce ad-hoc drop-and-recreate tools.
