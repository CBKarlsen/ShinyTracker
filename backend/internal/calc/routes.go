package calc

import "sort"

// MethodCandidate is one huntable method for a Pokemon in a specific game,
// before odds are computed.
type MethodCandidate struct {
	GameID         int
	GameTitle      string
	MethodName     string
	MethodID       int
	FormulaType    string
	BaseOdds       int
	BaseRolls      int
	CharmRolls     int
	HasShinyCharm  bool
	AvgTimeSeconds int
}

// EvolveFrom identifies the pre-evolution to hunt for an "evolve" route.
type EvolveFrom struct {
	PokemonID int    `json:"pokemon_id"`
	Name      string `json:"name"`
}

// Route is a computed, rankable way to obtain a shiny.
type Route struct {
	Kind        string      `json:"kind"` // "direct" or "evolve"
	GameID      int         `json:"game_id"`
	GameTitle   string      `json:"game_title"`
	MethodName  string      `json:"method_name"`
	MethodID    int         `json:"method_id"`
	FormulaType string      `json:"formula_type"`
	Odds        int         `json:"odds"` // integer-floored denominator of the 1/Odds probability (matches the displayed "1 / N"); ETAHours keeps full precision
	ETAHours    float64     `json:"eta_hours"`
	EvolveFrom  *EvolveFrom `json:"evolve_from,omitempty"`
}

// computeRoute turns a candidate into a Route (Kind/EvolveFrom set by callers).
func computeRoute(c MethodCandidate) Route {
	totalRolls := c.BaseRolls
	if c.HasShinyCharm {
		totalRolls += c.CharmRolls
	}
	if totalRolls <= 0 {
		totalRolls = 1
	}
	odds := c.BaseOdds / totalRolls
	if odds < 1 {
		odds = 1
	}
	eta := CalculateEstimatedTimeHours(OddsConfig{
		BaseOdds:       c.BaseOdds,
		BaseRolls:      c.BaseRolls,
		CharmRolls:     c.CharmRolls,
		HasShinyCharm:  c.HasShinyCharm,
		AvgTimeSeconds: c.AvgTimeSeconds,
	})
	return Route{
		GameID:      c.GameID,
		GameTitle:   c.GameTitle,
		MethodName:  c.MethodName,
		MethodID:    c.MethodID,
		FormulaType: c.FormulaType,
		Odds:        odds,
		ETAHours:    eta,
	}
}

// RankDirectRoutes computes direct routes and sorts them ascending by odds.
func RankDirectRoutes(cands []MethodCandidate) []Route {
	routes := make([]Route, 0, len(cands))
	for _, c := range cands {
		r := computeRoute(c)
		r.Kind = "direct"
		routes = append(routes, r)
	}
	sort.SliceStable(routes, func(i, j int) bool { return routes[i].Odds < routes[j].Odds })
	return routes
}

// BestRoute returns the lowest-odds candidate as an evolve route for the given
// ancestor, plus ok=false when the ancestor has no candidates. It ranks the
// candidates internally via RankDirectRoutes, so callers may pass an unsorted slice.
func BestRoute(cands []MethodCandidate, from EvolveFrom) (Route, bool) {
	ranked := RankDirectRoutes(cands)
	if len(ranked) == 0 {
		return Route{}, false
	}
	r := ranked[0]
	r.Kind = "evolve"
	r.EvolveFrom = &from
	return r, true
}

// IsLockedEverywhere reports whether a Pokemon is shiny-locked in every game it
// is available in. Returns false when there is no availability.
func IsLockedEverywhere(availGames, lockedGames []int) bool {
	if len(availGames) == 0 {
		return false
	}
	locked := make(map[int]bool, len(lockedGames))
	for _, g := range lockedGames {
		locked[g] = true
	}
	for _, g := range availGames {
		if !locked[g] {
			return false
		}
	}
	return true
}

// ShouldIncludeEvolveRoute decides whether to surface an evolve route: include
// it when the target has no direct route, or the ancestor's odds beat the
// target's best (targetRoutes must be sorted ascending by odds).
func ShouldIncludeEvolveRoute(targetRoutes []Route, ancestorBest Route) bool {
	if len(targetRoutes) == 0 {
		return true
	}
	return ancestorBest.Odds < targetRoutes[0].Odds
}
