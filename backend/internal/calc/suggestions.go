package calc

import "sort"

// SuggestionRank is a per-Pokemon best route plus availability breadth, used to
// rank "hunt next" suggestions. Kept free of presentation fields so the sort is
// pure, total, and unit-testable.
type SuggestionRank struct {
	PokemonID         int
	HuntableGameCount int
	Best              Route
}

// RankSuggestions sorts items in place: best odds first (lowest Best.Odds), then
// most constrained (fewest huntable games), then National Dex order (lowest
// PokemonID). PokemonID is unique, so the order is fully deterministic.
func RankSuggestions(items []SuggestionRank) {
	sort.SliceStable(items, func(i, j int) bool {
		a, b := items[i], items[j]
		if a.Best.Odds != b.Best.Odds {
			return a.Best.Odds < b.Best.Odds
		}
		if a.HuntableGameCount != b.HuntableGameCount {
			return a.HuntableGameCount < b.HuntableGameCount
		}
		return a.PokemonID < b.PokemonID
	})
}
