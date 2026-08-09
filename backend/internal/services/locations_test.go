package services

import (
	"encoding/json"
	"testing"
)

// A trimmed real-shaped /pokemon/{id}/encounters payload. Covers: a mapped
// version (platinum -> Diamond/Pearl/Platinum), an unmapped version (red, Gen 1,
// deliberately absent from versionMap), two terrains, and condition values.
const samplePayload = `[
  {
    "location_area": {"name": "route-210-area"},
    "version_details": [
      {
        "version": {"name": "platinum"},
        "encounter_details": [
          {"method": {"name": "walk"}, "min_level": 20, "max_level": 24,
           "chance": 15, "condition_values": [{"name": "time-night"}]},
          {"method": {"name": "walk"}, "min_level": 20, "max_level": 24,
           "chance": 15, "condition_values": [{"name": "time-night"}]}
        ]
      },
      {
        "version": {"name": "red"},
        "encounter_details": [
          {"method": {"name": "walk"}, "min_level": 5, "max_level": 7,
           "chance": 20, "condition_values": []}
        ]
      }
    ]
  },
  {
    "location_area": {"name": "lake-verity-area"},
    "version_details": [
      {
        "version": {"name": "platinum"},
        "encounter_details": [
          {"method": {"name": "surf"}, "min_level": 10, "max_level": 20,
           "chance": 60, "condition_values": []}
        ]
      }
    ]
  }
]`

func TestParseLocations(t *testing.T) {
	var encounters []PokeAPIEncounter
	if err := json.Unmarshal([]byte(samplePayload), &encounters); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	gameIDs := map[string]int{"Diamond/Pearl/Platinum": 4}

	rows := ParseLocations(129, encounters, gameIDs)

	// The duplicate walk slot is deduped; the Gen-1 'red' row is skipped
	// because versionMap has no entry for it.
	if len(rows) != 2 {
		t.Fatalf("want 2 rows, got %d: %+v", len(rows), rows)
	}

	byArea := map[string]LocationRow{}
	for _, r := range rows {
		byArea[r.Area] = r
	}

	walk, ok := byArea["route-210-area"]
	if !ok {
		t.Fatal("missing route-210-area")
	}
	if walk.PokemonID != 129 {
		t.Errorf("PokemonID = %d, want 129", walk.PokemonID)
	}
	if walk.GameID != 4 {
		t.Errorf("GameID = %d, want 4", walk.GameID)
	}
	if walk.Version != "platinum" {
		t.Errorf("Version = %q, want platinum", walk.Version)
	}
	if walk.Terrain != "grass" {
		t.Errorf("Terrain = %q, want grass (walk buckets to grass)", walk.Terrain)
	}
	if walk.PokeAPIMethod != "walk" {
		t.Errorf("PokeAPIMethod = %q, want walk", walk.PokeAPIMethod)
	}
	if walk.MinLevel != 20 || walk.MaxLevel != 24 {
		t.Errorf("levels = %d-%d, want 20-24", walk.MinLevel, walk.MaxLevel)
	}
	if walk.Chance != 15 {
		t.Errorf("Chance = %d, want 15", walk.Chance)
	}
	if len(walk.Conditions) != 1 || walk.Conditions[0] != "time-night" {
		t.Errorf("Conditions = %v, want [time-night]", walk.Conditions)
	}

	surf, ok := byArea["lake-verity-area"]
	if !ok {
		t.Fatal("missing lake-verity-area")
	}
	if surf.Terrain != "surf" {
		t.Errorf("Terrain = %q, want surf", surf.Terrain)
	}
	if len(surf.Conditions) != 0 {
		t.Errorf("Conditions = %v, want empty", surf.Conditions)
	}
}

// A version present in versionMap but whose game title is absent from the
// gameIDs map (e.g. the game row was never seeded) must be skipped, not
// defaulted to game 0.
func TestParseLocationsSkipsUnknownGameTitle(t *testing.T) {
	var encounters []PokeAPIEncounter
	if err := json.Unmarshal([]byte(samplePayload), &encounters); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	rows := ParseLocations(129, encounters, map[string]int{})
	if len(rows) != 0 {
		t.Fatalf("want 0 rows when no game IDs are known, got %d", len(rows))
	}
}
