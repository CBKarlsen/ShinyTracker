// cmd/seed_moves seeds base stats, abilities, and (Platinum + Scarlet/Violet +
// Champions only) movesets from PokeAPI.
//
// RUNBOOK: run after cmd/seed (needs the `pokemon` and `games` tables
// populated) and after migrations/014_add_stats_abilities_moves.sql has been
// applied. Safe to re-run: every write is either an upsert on a stable
// natural key (moves.slug, abilities.slug, pokemon_abilities' (pokemon_id,
// slot) PK) or gated on pokemon.hp IS NULL (species not yet processed) --
// see internal/services/moves.go's SeedSpeciesStatsAndMoves doc comment for
// the resumability contract.
package main

import (
	"context"
	"log"

	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/services"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	ctx := context.Background()

	// Phase 1/2 (small, seeded in full): moves and abilities reference
	// tables. Phase 3 (the row-count risk) needs both id maps to resolve
	// slugs, so it must run after these two complete.
	log.Println("Phase 1/3: moves reference table")
	moveIDs, moveCount, moveErr := services.SeedMoveReference(ctx)

	log.Println("Phase 2/3: abilities reference table")
	abilityIDs, abilityCount, abilityErr := services.SeedAbilityReference(ctx)

	log.Println("Phase 3/3: per-species stats, ability slots, and movesets (Platinum + Scarlet/Violet + Champions)")
	speciesCount, speciesErr := services.SeedSpeciesStatsAndMoves(ctx, moveIDs, abilityIDs)

	log.Printf("Done. moves=%d abilities=%d species_newly_seeded=%d", moveCount, abilityCount, speciesCount)

	// Report every phase's outcome before exiting non-zero, so a failure in
	// phase 1 doesn't hide whether phases 2/3 also had problems.
	if moveErr != nil || abilityErr != nil || speciesErr != nil {
		log.Fatalf("seed_moves finished with errors (re-run to retry incomplete work): moves_err=%v abilities_err=%v species_err=%v",
			moveErr, abilityErr, speciesErr)
	}
}
