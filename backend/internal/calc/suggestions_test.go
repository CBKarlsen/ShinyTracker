package calc

import (
	"reflect"
	"testing"
)

func TestRankSuggestions(t *testing.T) {
	// Mixed odds, game counts, and dex ids. Expected order:
	//   odds 512 first, within that fewest games first, within that lowest dex id.
	items := []SuggestionRank{
		{PokemonID: 10, HuntableGameCount: 3, Best: Route{Odds: 512}},
		{PokemonID: 5, HuntableGameCount: 1, Best: Route{Odds: 4096}},
		{PokemonID: 7, HuntableGameCount: 2, Best: Route{Odds: 512}},
		{PokemonID: 3, HuntableGameCount: 1, Best: Route{Odds: 512}},
		{PokemonID: 2, HuntableGameCount: 1, Best: Route{Odds: 512}},
	}
	RankSuggestions(items)
	got := []int{}
	for _, it := range items {
		got = append(got, it.PokemonID)
	}
	want := []int{2, 3, 7, 10, 5}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("order = %v, want %v", got, want)
	}
}
