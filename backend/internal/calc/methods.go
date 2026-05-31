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

// EffectiveOdds returns the integer "1 / N" denominator for a method, mirroring
// calculateOdds() in frontend/src/utils/odds.ts. Unknown formulas behave as "static".
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
		chain := clampInt(paramInt(params, "chain_length", 0), 0, 40)
		den := int(math.Round(65536 - 1635.925*float64(chain)))
		if den < 99 {
			den = 99
		}
		return den

	case "catch_combo_lgpe":
		combo := maxInt(0, paramInt(params, "count", 0))
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
		defeats := maxInt(0, paramInt(params, "defeated_count", 0))
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
		chain := maxInt(0, paramInt(params, "chain_length", 0)) % 255
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
		searchLevel := maxInt(0, paramInt(params, "search_level", 0))
		chain := maxInt(0, paramInt(params, "chain_length", 0))
		tt := 0.0
		if searchLevel > 0 {
			tt += float64(minInt(searchLevel, 100)) * 6
		}
		if searchLevel > 100 {
			tt += float64(minInt(searchLevel-100, 100)) * 2
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
		chain := clampInt(paramInt(params, "count", 0), 0, 20)
		return floorDiv(base.BaseRolls + chain*2 + charmRolls)

	default: // "static" and any unknown formula
		return floorDiv(base.BaseRolls + charmRolls)
	}
}

func sparklingRolls(power int) int {
	switch power {
	case 1:
		return 1
	case 2:
		return 2
	case 3:
		return 3
	}
	return 0
}

func clampInt(v, lo, hi int) int { return maxInt(lo, minInt(v, hi)) }
func maxInt(a, b int) int {
	if a > b {
		return a
	}
	return b
}
func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}
