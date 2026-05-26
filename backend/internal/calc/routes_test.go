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
