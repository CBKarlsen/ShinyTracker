package calc

import "sort"

// MethodCandidate is one huntable method for a Pokemon in a specific game,
// before odds are computed.
type MethodCandidate struct {
	GameID          int
	GameTitle       string
	MethodName      string
	MethodID        int
	FormulaType     string
	BaseOdds        int
	BaseRolls       int
	CharmRolls      int
	HasShinyCharm   bool
	AvgTimeSeconds  int
	RequiresKind    string // 'wild' | 'static' | 'raid' | 'egg'
	RequiresTerrain string // "" means "any terrain"
}

// EvolveFrom identifies the pre-evolution to hunt for an "evolve" route.
type EvolveFrom struct {
	PokemonID int    `json:"pokemon_id"`
	Name      string `json:"name"`
}

// Route is a computed, rankable way to obtain a shiny.
type Route struct {
	Kind            string      `json:"kind"` // "direct" or "evolve"
	GameID          int         `json:"game_id"`
	GameTitle       string      `json:"game_title"`
	MethodName      string      `json:"method_name"`
	MethodID        int         `json:"method_id"`
	FormulaType     string      `json:"formula_type"`
	Odds            int         `json:"odds"` // integer-floored denominator of the 1/Odds probability (matches the displayed "1 / N"); ETAHours keeps full precision
	ETAHours        float64     `json:"eta_hours"`
	EvolveFrom      *EvolveFrom `json:"evolve_from,omitempty"`
	HasShinyCharm   bool        `json:"has_shiny_charm"`
	RequiresKind    string      `json:"requires_kind"`
	RequiresTerrain string      `json:"-"`
	Locations       []Location  `json:"locations"`
}

// computeRoute turns a candidate into a Route (Kind/EvolveFrom set by callers).
func computeRoute(c MethodCandidate) Route {
	base := OddsConfig{
		BaseOdds:       c.BaseOdds,
		BaseRolls:      c.BaseRolls,
		CharmRolls:     c.CharmRolls,
		HasShinyCharm:  c.HasShinyCharm,
		AvgTimeSeconds: c.AvgTimeSeconds,
	}
	odds := EffectiveOdds(c.FormulaType, DefaultParams(c.FormulaType), base, c.HasShinyCharm)
	if odds < 1 {
		odds = 1
	}
	// ETA: expected encounters (= odds denominator) * avg_time.
	eta := float64(odds) * float64(c.AvgTimeSeconds) / 3600.0
	return Route{
		GameID:          c.GameID,
		GameTitle:       c.GameTitle,
		MethodName:      c.MethodName,
		MethodID:        c.MethodID,
		FormulaType:     c.FormulaType,
		Odds:            odds,
		ETAHours:        eta,
		HasShinyCharm:   c.HasShinyCharm,
		RequiresKind:    c.RequiresKind,
		RequiresTerrain: c.RequiresTerrain,
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

// Location is one place a Pokemon can be encountered, for a specific version.
// GameID is a matching input, not part of the API payload.
type Location struct {
	GameID     int      `json:"-"`
	Area       string   `json:"area"`
	Version    string   `json:"version"`
	Terrain    string   `json:"terrain"`
	MinLevel   int      `json:"min_level"`
	MaxLevel   int      `json:"max_level"`
	Chance     int      `json:"chance"`
	Conditions []string `json:"conditions"`
}

// MatchLocations selects the locations that apply to one route, capped at max
// and ordered by encounter chance descending (then area, for stability).
//
// The terrain rule is copied verbatim from computeAvailability in
// cmd/seed/main.go: an explicit requires_terrain matches that terrain exactly,
// while a generic method (no requirement) matches every terrain EXCEPT
// friend_safari, which is a dedicated pool rather than a real terrain.
//
// Non-wild methods (egg/static/raid) have no location: Masuda breeding and
// soft-resetting do not happen at a place on the map.
func MatchLocations(r Route, locs []Location, max int) []Location {
	if r.RequiresKind != "wild" {
		return nil
	}
	out := make([]Location, 0, len(locs))
	for _, l := range locs {
		if l.GameID != r.GameID {
			continue
		}
		if r.RequiresTerrain != "" {
			if l.Terrain != r.RequiresTerrain {
				continue
			}
		} else if l.Terrain == "friend_safari" {
			continue
		}
		out = append(out, l)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].Chance != out[j].Chance {
			return out[i].Chance > out[j].Chance
		}
		return out[i].Area < out[j].Area
	})
	if len(out) > max {
		out = out[:max]
	}
	return out
}
