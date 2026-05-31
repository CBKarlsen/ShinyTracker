package calc

import "math"

// paramInt reads an integer param, tolerating float64 (JSON numbers decode to
// float64 through map[string]any) and int. Missing/!numeric -> fallback.
func paramInt(params map[string]any, key string, fallback int) int {
	v, ok := params[key]
	if !ok {
		return fallback
	}
	switch n := v.(type) {
	case int:
		return n
	case int64:
		return int(n)
	case float64:
		return int(n)
	}
	return fallback
}

// EffectiveOdds returns the integer "1 / N" denominator for a method. It mostly
// mirrors calculateOdds() in frontend/src/utils/odds.ts, with two known
// divergences: outbreak_defeats_sv also adds a sparkling_power term (TS doesn't
// yet — tracked follow-up), and catch_combo_lgpe/chain_fishing_gen6 read their
// count from the "count" param instead of the live encounter arg. Unknown
// formulas behave as "static".
func EffectiveOdds(formulaType string, params map[string]any, base OddsConfig, hasCharm bool) int {
	if params == nil {
		params = map[string]any{}
	}
	t := formulaType
	if t == "" {
		t = "static"
	}
	charmRolls := 0
	if hasCharm {
		charmRolls = base.CharmRolls
	}
	floorDiv := func(rolls int) int {
		if rolls <= 0 {
			rolls = 1
		}
		return base.BaseOdds / rolls
	}

	switch t {
	case "radar_chain_gen4":
		// Bulbapedia: numerator = ceil(65535 / (8200 - 200*chain)); rate = numerator / 65536.
		// chain 0 -> 1/8192 (base Gen 4 odds); chain 40 (cap) -> 1/200. No Shiny Charm in Gen 4.
		chain := max(0, min(paramInt(params, "chain_length", 0), 40))
		numerator := int(math.Ceil(65535.0 / float64(8200-200*chain)))
		return int(math.Round(65536.0 / float64(numerator)))

	case "catch_combo_lgpe":
		// NOTE: TS reads the live encounter counter here; the Go engine takes the count via the "count" param (route ranking supplies it through DefaultParams).
		combo := max(0, paramInt(params, "count", 0))
		extra := 0
		switch {
		case combo >= 31:
			extra = 11
		case combo >= 21:
			extra = 7
		case combo >= 11:
			extra = 3
		}
		return floorDiv(base.BaseRolls + extra + charmRolls)

	case "outbreak_defeats_sv":
		defeats := max(0, paramInt(params, "defeated_count", 0))
		extra := 0
		switch {
		case defeats >= 60:
			extra = 2
		case defeats >= 30:
			extra = 1
		}
		// New term (not yet in TS): sandwich Sparkling Power stacks additively.
		extra += sparklingRolls(paramInt(params, "sparkling_power", 0))
		return floorDiv(base.BaseRolls + extra + charmRolls)

	case "sos_chain_gen7":
		chain := max(0, paramInt(params, "chain_length", 0)) % 255
		extra := 0
		switch {
		case chain >= 31:
			extra = 12
		case chain >= 21:
			extra = 8
		case chain >= 11:
			extra = 4
		}
		return floorDiv(base.BaseRolls + extra + charmRolls)

	case "dexnav_gen6":
		searchLevel := max(0, paramInt(params, "search_level", 0))
		chain := max(0, paramInt(params, "chain_length", 0))
		// Piecewise search-level -> points: 6/level up to 100, 2/level for 101-200, 1/level beyond; /10000 = probability.
		tt := 0.0
		if searchLevel > 0 {
			tt += float64(min(searchLevel, 100)) * 6
		}
		if searchLevel > 100 {
			tt += float64(min(searchLevel-100, 100)) * 2
		}
		if searchLevel > 200 {
			tt += float64(searchLevel-200) * 1
		}
		probDexNav := 0.0
		if searchLevel > 0 {
			probDexNav = tt / 10000
		}
		extra := 0
		if chain > 0 && chain%100 == 0 {
			extra = 10
		} else if chain > 0 && chain%50 == 0 {
			extra = 5
		}
		rolls := base.BaseRolls + extra + charmRolls
		probStandard := float64(rolls) / float64(base.BaseOdds)
		totalProb := probDexNav + (1-probDexNav)*probStandard
		if totalProb <= 0 {
			return base.BaseOdds
		}
		return int(math.Round(1 / totalProb))

	case "sandwich_power_sv":
		extra := sparklingRolls(paramInt(params, "sparkling_power", 0))
		return floorDiv(base.BaseRolls + extra + charmRolls)

	case "dynamax_adventures_gen8":
		if hasCharm {
			return 100
		}
		return 300

	case "chain_fishing_gen6":
		// NOTE: TS reads the live encounter counter here; the Go engine takes the count via the "count" param (route ranking supplies it through DefaultParams).
		chain := max(0, min(paramInt(params, "count", 0), 20))
		return floorDiv(base.BaseRolls + chain*2 + charmRolls)

	default: // "static" and any unknown formula
		return floorDiv(base.BaseRolls + charmRolls)
	}
}

func sparklingRolls(power int) int {
	if power >= 1 && power <= 3 {
		return power
	}
	return 0
}

// DefaultParams returns each method's achievable-best parameters, used for
// route ranking (where no per-hunt params exist yet). avg_time keeps ETA honest.
func DefaultParams(formulaType string) map[string]any {
	switch formulaType {
	case "outbreak_defeats_sv":
		return map[string]any{"defeated_count": 60, "sparkling_power": 3}
	case "sandwich_power_sv":
		return map[string]any{"sparkling_power": 3}
	case "sos_chain_gen7":
		return map[string]any{"chain_length": 31}
	case "radar_chain_gen4":
		return map[string]any{"chain_length": 40}
	// search_level 200 is a typical mid/late-game value, not the theoretical
	// cap (which would push DexNav near 1/1 and dominate ranking unrealistically).
	case "dexnav_gen6":
		return map[string]any{"search_level": 200, "chain_length": 100}
	case "catch_combo_lgpe":
		return map[string]any{"count": 31}
	case "chain_fishing_gen6":
		return map[string]any{"count": 20}
	default: // static, dynamax_adventures_gen8 (no params)
		return map[string]any{}
	}
}
