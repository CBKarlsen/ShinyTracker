package main

import (
	"encoding/json"
	"os"
	"testing"
)

// The seeder reads seeds/ relative to backend/; tests run in cmd/seed.
const seedDir = "../../seeds/"

func loadMethods(t *testing.T) map[string]HuntMethod {
	t.Helper()
	data, err := os.ReadFile(seedDir + "hunt_methods.json")
	if err != nil {
		t.Fatalf("read hunt_methods.json: %v", err)
	}
	var methods []HuntMethod
	if err := json.Unmarshal(data, &methods); err != nil {
		t.Fatalf("parse hunt_methods.json: %v", err)
	}
	bySlug := make(map[string]HuntMethod, len(methods))
	for _, m := range methods {
		if _, dup := bySlug[m.IDStr]; dup {
			t.Errorf("duplicate method id %q", m.IDStr)
		}
		bySlug[m.IDStr] = m
	}
	return bySlug
}

// TestMethodExceptionsReferenceKnownMethods mirrors the log.Fatalf in
// seedMethodExceptions: every correction must name a method id that still
// exists in hunt_methods.json. Catches a rename without a database.
func TestMethodExceptionsReferenceKnownMethods(t *testing.T) {
	methods := loadMethods(t)
	data, err := os.ReadFile(seedDir + "method_exceptions.json")
	if err != nil {
		t.Fatalf("read method_exceptions.json: %v", err)
	}
	var exceptions []MethodExceptionSeed
	if err := json.Unmarshal(data, &exceptions); err != nil {
		t.Fatalf("parse method_exceptions.json: %v", err)
	}
	for _, e := range exceptions {
		if _, ok := methods[e.Method]; !ok {
			t.Errorf("method_exceptions references unknown method id %q (pokemon %d)", e.Method, e.PokemonID)
		}
	}
}

// matchesTerrain mirrors the terrain rule in computeAvailability's join: an
// explicit requires_terrain must equal the encounter row's terrain, and an
// absent one matches any terrain except the dedicated friend_safari.
func matchesTerrain(requiresTerrain, terrain string) bool {
	if requiresTerrain == "" {
		return terrain != "friend_safari"
	}
	return requiresTerrain == terrain
}

// TestRunawayReachesMewAlone pins the scoping of run_away_precharm: Mew is the
// only Gen 3 static that respawns on flee, so it must be the only RSE static
// the method reaches, while Soft Reset must keep reaching all of them
// (including Mew's extra terrain='other' row). The derivation itself is SQL in
// computeAvailability and needs a database; this asserts the two data-side
// facts that decide its outcome — the method's terrain and which encounter
// rows carry that terrain.
func TestRunawayReachesMewAlone(t *testing.T) {
	methods := loadMethods(t)

	runaway, ok := methods["run_away_precharm"]
	if !ok {
		t.Fatal("hunt_methods.json is missing run_away_precharm")
	}
	if runaway.RequiresKind != "static" || runaway.RequiresTerrain != "other" {
		t.Fatalf("run_away_precharm must be static/terrain=other, got %q/%q",
			runaway.RequiresKind, runaway.RequiresTerrain)
	}
	// The Shiny Charm is a Gen 5 item: it must stay inert for Gen 3.
	if runaway.BaseRolls != 1 || runaway.CharmRolls != 0 || runaway.FormulaType != "static" {
		t.Errorf("run_away_precharm odds changed: rolls=%d charm=%d formula=%q (want 1/0/static)",
			runaway.BaseRolls, runaway.CharmRolls, runaway.FormulaType)
	}
	if len(runaway.Games) != 1 || runaway.Games[0] != "Ruby/Sapphire/Emerald" {
		t.Errorf("run_away_precharm games = %v, want [Ruby/Sapphire/Emerald]", runaway.Games)
	}

	// Only verified respawn-on-flee pairs may carry the terrain that unlocks it.
	if len(runawayEncounters) != 1 || runawayEncounters[0].PokemonID != 151 ||
		runawayEncounters[0].Game != "Ruby/Sapphire/Emerald" {
		t.Fatalf("runawayEncounters = %v, want only Mew (151) in Ruby/Sapphire/Emerald "+
			"— adding a pair needs Bulbapedia/Serebii verification for that encounter", runawayEncounters)
	}

	// The other RSE statics only ever get seedCuratedEncounters' default
	// terrain='none' row, so the method must not match it.
	if matchesTerrain(runaway.RequiresTerrain, "none") {
		t.Error("run_away_precharm matches terrain='none': it would attach to every RSE static " +
			"(the Regis, the weather trio, Deoxys, Latios/Latias), which do not respawn on flee")
	}
	if !matchesTerrain(runaway.RequiresTerrain, "other") {
		t.Error("run_away_precharm no longer matches the terrain seedRunawayEncounters writes")
	}

	// Soft Reset stays available for every RSE static, Mew's extra row included.
	softReset, ok := methods["soft_reset_precharm"]
	if !ok {
		t.Fatal("hunt_methods.json is missing soft_reset_precharm")
	}
	for _, terrain := range []string{"none", "other"} {
		if !matchesTerrain(softReset.RequiresTerrain, terrain) {
			t.Errorf("soft_reset_precharm no longer matches terrain=%q", terrain)
		}
	}
}

// The runaway scoping rests on one invariant that lives outside the runaway rows
// themselves: run_away_precharm must be the ONLY static method carrying a
// requires_terrain. computeAvailability matches a terrain-less method against every
// terrain, so any second static+terrain method would attach itself to the runaway
// encounter row and silently reach Mew -- with every other test here still passing.
func TestRunAwayIsTheOnlyTerrainScopedStatic(t *testing.T) {
	for slug, m := range loadMethods(t) {
		if m.RequiresKind != "static" || m.RequiresTerrain == "" {
			continue
		}
		if slug != "run_away_precharm" {
			t.Errorf("%s is a static method with requires_terrain=%q; only run_away_precharm may be, "+
				"or it stops reaching Mew alone", slug, m.RequiresTerrain)
		}
	}
}
