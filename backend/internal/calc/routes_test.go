package calc

import "testing"

func TestComputeRouteOddsWithAndWithoutCharm(t *testing.T) {
	// base_odds 4096, base_rolls 1, charm_rolls 2
	noCharm := computeRoute(MethodCandidate{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2, HasShinyCharm: false})
	if noCharm.Odds != 4096 {
		t.Fatalf("no-charm odds = %d, want 4096", noCharm.Odds)
	}
	withCharm := computeRoute(MethodCandidate{BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2, HasShinyCharm: true})
	if withCharm.Odds != 1365 { // 4096 / (1+2)
		t.Fatalf("charm odds = %d, want 1365", withCharm.Odds)
	}
}

func TestRankDirectRoutesSortsAscendingByOdds(t *testing.T) {
	cands := []MethodCandidate{
		{GameID: 1, MethodName: "Wild", BaseOdds: 4096, BaseRolls: 1},
		{GameID: 2, MethodName: "Masuda", BaseOdds: 4096, BaseRolls: 6},
	}
	routes := RankDirectRoutes(cands)
	if len(routes) != 2 {
		t.Fatalf("got %d routes, want 2", len(routes))
	}
	if routes[0].MethodName != "Masuda" {
		t.Fatalf("best route = %q, want Masuda (better odds)", routes[0].MethodName)
	}
	if routes[0].Kind != "direct" {
		t.Fatalf("kind = %q, want direct", routes[0].Kind)
	}
}

func TestIsLockedEverywhere(t *testing.T) {
	if !IsLockedEverywhere([]int{3, 5}, []int{3, 5}) {
		t.Fatal("available in {3,5}, locked in {3,5} should be locked everywhere")
	}
	if IsLockedEverywhere([]int{3, 5}, []int{3}) {
		t.Fatal("available in {3,5} but locked only in {3} should NOT be locked everywhere")
	}
	if IsLockedEverywhere(nil, []int{3}) {
		t.Fatal("no availability should NOT be locked everywhere")
	}
}

func TestShouldIncludeEvolveRoute(t *testing.T) {
	ancestor := Route{Odds: 683}
	if !ShouldIncludeEvolveRoute(nil, ancestor) {
		t.Fatal("no target routes -> evolve route should be included")
	}
	worse := []Route{{Odds: 500}}
	if ShouldIncludeEvolveRoute(worse, ancestor) {
		t.Fatal("ancestor odds 683 worse than target best 500 -> should NOT include")
	}
	better := []Route{{Odds: 4096}}
	if !ShouldIncludeEvolveRoute(better, ancestor) {
		t.Fatal("ancestor odds 683 beats target best 4096 -> should include")
	}
}

func TestComputeRouteGuardsZeroRolls(t *testing.T) {
	// BaseRolls 0 and no charm -> totalRolls guarded to 1, no divide-by-zero.
	r := computeRoute(MethodCandidate{BaseOdds: 4096, BaseRolls: 0, CharmRolls: 0, HasShinyCharm: false})
	if r.Odds != 4096 {
		t.Fatalf("zero-rolls odds = %d, want 4096", r.Odds)
	}
}

func TestIsLockedEverywhereAvailableButNothingLocked(t *testing.T) {
	if IsLockedEverywhere([]int{3}, nil) {
		t.Fatal("available in {3} with no locks should NOT be locked everywhere")
	}
}

func TestComputeRouteCarriesMethodIDAndFormula(t *testing.T) {
	r := computeRoute(MethodCandidate{
		MethodID: 42, FormulaType: "masuda",
		BaseOdds: 4096, BaseRolls: 6, HasShinyCharm: false,
	})
	if r.MethodID != 42 {
		t.Fatalf("MethodID = %d, want 42", r.MethodID)
	}
	if r.FormulaType != "masuda" {
		t.Fatalf("FormulaType = %q, want masuda", r.FormulaType)
	}
}

func TestBestRouteCarriesAncestorMethodFields(t *testing.T) {
	best, ok := BestRoute(
		[]MethodCandidate{{MethodID: 7, FormulaType: "wild", BaseOdds: 4096, BaseRolls: 1}},
		EvolveFrom{PokemonID: 129, Name: "magikarp"},
	)
	if !ok {
		t.Fatal("expected ok=true")
	}
	if best.MethodID != 7 || best.FormulaType != "wild" {
		t.Fatalf("got MethodID=%d FormulaType=%q, want 7/wild", best.MethodID, best.FormulaType)
	}
	if best.Kind != "evolve" || best.EvolveFrom == nil {
		t.Fatal("expected an evolve route with EvolveFrom set")
	}
}

func TestRankUsesEffectiveOddsForModernMethods(t *testing.T) {
	// Both have the charm: static wild is 1/1365, the outbreak (default best
	// params + charm) is 1/512, so the method-aware engine must rank it first.
	cands := []MethodCandidate{
		{GameID: 1, MethodName: "Random Encounter", FormulaType: "static", BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2, HasShinyCharm: true},
		{GameID: 1, MethodName: "Paldea Mass Outbreak", FormulaType: "outbreak_defeats_sv", BaseOdds: 4096, BaseRolls: 1, CharmRolls: 2, HasShinyCharm: true},
	}
	routes := RankDirectRoutes(cands)
	if routes[0].MethodName != "Paldea Mass Outbreak" {
		t.Fatalf("best route = %q, want the outbreak (better effective odds)", routes[0].MethodName)
	}
	if routes[0].Odds != 512 {
		t.Fatalf("outbreak odds = %d, want 512 (default best params + charm)", routes[0].Odds)
	}
}

func TestMatchLocationsTerrainRule(t *testing.T) {
	locs := []Location{
		{GameID: 4, Area: "route-210-area", Terrain: "grass", Chance: 15},
		{GameID: 4, Area: "lake-verity-area", Terrain: "surf", Chance: 60},
		{GameID: 4, Area: "friend-safari", Terrain: "friend_safari", Chance: 50},
		{GameID: 9, Area: "other-game-area", Terrain: "grass", Chance: 99},
	}

	// A terrain-restricted method takes only its own terrain, in its own game.
	radar := Route{GameID: 4, RequiresKind: "wild", RequiresTerrain: "grass"}
	got := MatchLocations(radar, locs, 5)
	if len(got) != 1 || got[0].Area != "route-210-area" {
		t.Fatalf("grass-restricted route: got %+v", got)
	}

	// A generic method (no terrain requirement) takes every terrain EXCEPT
	// friend_safari, mirroring computeAvailability in cmd/seed/main.go.
	generic := Route{GameID: 4, RequiresKind: "wild", RequiresTerrain: ""}
	got = MatchLocations(generic, locs, 5)
	if len(got) != 2 {
		t.Fatalf("generic route: want 2 (grass+surf, not friend_safari), got %+v", got)
	}
	// Ordered by chance descending.
	if got[0].Area != "lake-verity-area" {
		t.Errorf("want highest chance first, got %q", got[0].Area)
	}
}

func TestMatchLocationsNonWildKindsHaveNone(t *testing.T) {
	locs := []Location{{GameID: 4, Area: "route-210-area", Terrain: "grass", Chance: 15}}
	for _, kind := range []string{"egg", "static", "raid"} {
		r := Route{GameID: 4, RequiresKind: kind}
		if got := MatchLocations(r, locs, 5); len(got) != 0 {
			t.Errorf("kind %q: want no locations, got %+v", kind, got)
		}
	}
}

func TestMatchLocationsCaps(t *testing.T) {
	var locs []Location
	for i := 0; i < 20; i++ {
		locs = append(locs, Location{GameID: 4, Area: "a", Terrain: "grass", Chance: i})
	}
	r := Route{GameID: 4, RequiresKind: "wild"}
	if got := MatchLocations(r, locs, 5); len(got) != 5 {
		t.Fatalf("want cap of 5, got %d", len(got))
	}
}
