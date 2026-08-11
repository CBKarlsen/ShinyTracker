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
