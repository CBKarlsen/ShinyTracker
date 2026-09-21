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

// paramBool reads a boolean param, tolerating bool. Missing/!bool -> false.
func paramBool(params map[string]any, key string) bool {
	v, ok := params[key]
	if !ok {
		return false
	}
	b, ok := v.(bool)
	return ok && b
}

// plaResearchRolls returns base rolls plus Legends:Arceus dex-research bonuses.
// Research Lv10 (+1) and Perfect (+2) STACK (matches RotomLabs' published 1/128
// for Mass Outbreak + perfect + charm = 32 rolls). The OUTBREAK bonus is NOT here:
// it is encoded by the formula_type (pla_mass_outbreak = +25, pla_massive_outbreak
// = +12), because the outbreak is a property of where you hunt, not a per-hunt
// parameter. MMO is intentionally worse per-encounter than MO — MMO's advantage is
// spawn volume, which lives in avg_time_seconds. PLA charm is +3 (base.CharmRolls).
func plaResearchRolls(params map[string]any, baseRolls int) int {
	rolls := baseRolls
	if paramInt(params, "research_level", 0) >= 10 {
		rolls++
	}
	if paramBool(params, "dex_perfect") {
		rolls += 2
	}
	return rolls
}

// EffectiveOdds returns the integer "1 / N" denominator for a method. It mirrors
// calculateOdds() in frontend/src/utils/odds.ts. Known intentional divergence:
// catch_combo_lgpe/chain_fishing_gen6 read their count from the "count" param in
// Go (route ranking supplies it via DefaultParams) but from the live encounter
// counter in TS. Both engines now add the SV sparkling term. ultra_wormhole and
// pla_research are also mirrored in both. Unknown formulas behave as "static".
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
		// DPPt ONLY. Bulbapedia: numerator = ceil(65535 / (8200 - 200*chain)); rate = numerator / 65536.
		// chain 0 -> 1/8192 (base Gen 4 odds); chain 40 (cap) -> 1/200. base_odds is intentionally NOT
		// read: the curve already encodes 1/8192 at chain 0. Shiny Charm is intentionally IGNORED — it
		// does not exist in Gen IV. This is correct BY DESIGN, do not "fix" it by threading the charm in.
		// X/Y and BDSP have their own formula_types (radar_chain_xy, radar_chain_bdsp) below, since
		// all three Radar mechanics are genuinely different, not one curve with a scale factor.
		chain := max(0, min(paramInt(params, "chain_length", 0), 40))
		d := 8200 - 200*chain
		numerator := ceilDiv(65535, d)
		return roundDiv(65536, numerator)

	case "radar_chain_xy":
		// X/Y ONLY. Bulbapedia: a chain-dependent "sparkle" check (8100 - 200*chain at chain 0..40)
		// is rolled independently of, and in addition to, the normal roll-count check. Shiny Charm
		// affects ONLY the normal-roll side (pNormal), never the sparkle probability itself.
		chain := max(0, min(paramInt(params, "chain_length", 0), 40))
		sparkleD := 8100 - 200*chain
		pSparkle := 1.0 / float64(sparkleD)
		rolls := base.BaseRolls + charmRolls
		pNormal := float64(rolls) / float64(base.BaseOdds)
		pTotal := pSparkle + (1-pSparkle)*pNormal
		return int(math.Round(1 / pTotal))

	case "radar_chain_bdsp":
		// BDSP ONLY. Bulbapedia (https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9_Radar): the
		// numerator/65536 table has two discontinuities (chain 30 and chain 36) and is not a closed
		// form, so it is looked up rather than computed. numerator[0] = 16 already IS 1/4096, so
		// base_odds is intentionally NOT read. Shiny Charm is intentionally IGNORED here — datamined,
		// the BDSP Shiny Charm affects breeding ONLY (see seeds/hunt_methods.json for the other rows
		// this touches).
		chain := max(0, min(paramInt(params, "chain_length", 0), 40))
		return roundDiv(65536, bdspRadarNumerators[chain])

	case "catch_combo_lgpe":
		// The combo arrives under two historical key names: stored hunt_parameters
		// written by the frontend use "chain_length", while route ranking supplies
		// "count" via DefaultParams. Precedence is chain_length > count: the former
		// is live per-hunt state, the latter only ever a synthetic default. Both
		// engines MUST agree on this order — see shared/odds_anchors.json.
		combo := max(0, paramInt(params, "chain_length", paramInt(params, "count", 0)))
		extra := 0
		switch {
		case combo >= 31:
			extra = 11
		case combo >= 21:
			extra = 7
		case combo >= 11:
			extra = 3
		}
		// An active Lure adds exactly one roll. Verified: combo 31+ (12) + charm (2) + lure (1)
		// = 15 rolls -> 1/273.
		lure := 0
		if paramBool(params, "lure_active") {
			lure = 1
		}
		return floorDiv(base.BaseRolls + extra + charmRolls + lure)

	case "brilliant_swsh":
		// SwSh Brilliant (sparkle-aura) Pokemon. Rolls scale with how many of that
		// species the player has battled. Bulbapedia and Serebii agree row for row:
		// https://bulbapedia.bulbagarden.net/wiki/Brilliant_Pok%C3%A9mon
		// Charm is additive on top. Odds are PER BRILLIANT ENCOUNTER -- the brilliant
		// spawn rate itself is only 1.5-3%, which is why avg_time_seconds is high.
		// number_battled is NOT a chain: it never resets, so it does not go through
		// the chain_length/count precedence rule the streak formulas use.
		battled := max(0, paramInt(params, "number_battled", 0))
		extra := 0
		switch {
		case battled >= 500:
			extra = 6
		case battled >= 300:
			extra = 5
		case battled >= 200:
			extra = 4
		case battled >= 100:
			extra = 3
		case battled >= 50:
			extra = 2
		case battled >= 1:
			extra = 1
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
		// Sandwich Sparkling Power stacks additively (mirrored in TS calculateOdds).
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
			// Bulbapedia: dexnav_level = (tiered search-level points) / 100, and the
			// per-check forced-shiny probability is dexnav_level / 10000. The earlier
			// code dropped the /100, making this 100x too high (8% vs the real 0.08%
			// at search level 200) — which produced the bogus 1/12 best case.
			probDexNav = (tt / 100) / 10000
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
		// Same two-key situation as catch_combo_lgpe: stored hunt_parameters use
		// "chain_length", route ranking supplies "count" via DefaultParams.
		// Precedence must match that formula exactly — chain_length > count.
		// (Go has no live encounter counter to fall back to; EffectiveOdds is only
		// ever called with DefaultParams for ranking. TS falls back to the counter.)
		chain := max(0, min(paramInt(params, "chain_length", paramInt(params, "count", 0)), 20))
		return floorDiv(base.BaseRolls + chain*2 + charmRolls)

	case "ultra_wormhole":
		// USUM Ultra Warp Ride (non-legendary). Shiny percent scales with distance
		// (capped at 5000 ly, k<=9) and ring rarity; Shiny Charm has NO effect.
		// Legendary wormhole encounters are soft-resets and use "static", not this.
		ring := paramInt(params, "wormhole_ring_type", 4)
		k := max(0, min(paramInt(params, "wormhole_distance_ly", 0)/500-1, 9))
		percent := 1
		switch ring {
		case 2:
			percent = min(10, 1+1*k)
		case 3:
			percent = min(19, 1+2*k)
		case 4:
			percent = min(36, 1+4*k)
		default: // ring 1 (or unknown): flat 1%
			percent = 1
		}
		if percent < 1 {
			percent = 1
		}
		return int(math.Round(100.0 / float64(percent)))

	case "pla_research":
		return floorDiv(plaResearchRolls(params, base.BaseRolls) + charmRolls)
	case "pla_mass_outbreak":
		return floorDiv(plaResearchRolls(params, base.BaseRolls) + 25 + charmRolls)
	case "pla_massive_outbreak":
		return floorDiv(plaResearchRolls(params, base.BaseRolls) + 12 + charmRolls)

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

// ceilDiv and roundDiv are integer-only equivalents of math.Ceil/math.Round for
// positive-int division, used where the result must be bit-identical to the TS
// mirror: Go's math.Round is half-away-from-zero and JS's Math.round is half-up,
// and floats disagree at these magnitudes often enough to matter.
func ceilDiv(a, b int) int {
	return (a + b - 1) / b
}

func roundDiv(a, b int) int {
	return (2*a + b) / (2 * b)
}

// bdspRadarNumerators is the Poké Radar chain -> numerator/65536 table for BDSP.
// Bulbapedia: https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9_Radar
// Not a closed form — two discontinuities at chain 30 and chain 36 — so it is
// looked up rather than computed. Index = clamp(chain_length, 0, 40).
var bdspRadarNumerators = [41]int{
	16, 17, 18, 19, 20, 21, 22, 23, 24, 25, // chain  0- 9
	26, 27, 28, 29, 30, 31, 32, 33, 34, 35, // chain 10-19
	36, 37, 38, 39, 40, 41, 42, 43, 44, 45, // chain 20-29
	50, 51, 52, 53, 54, 55, // chain 30-35
	66, 82, 164, 328, 662, // chain 36-40
}

// DefaultParams returns each method's achievable-best parameters, used for
// route ranking (where no per-hunt params exist yet).
func DefaultParams(formulaType string) map[string]any {
	switch formulaType {
	case "brilliant_swsh":
		return map[string]any{"number_battled": 500}
	case "outbreak_defeats_sv":
		return map[string]any{"defeated_count": 60, "sparkling_power": 3}
	case "sandwich_power_sv":
		return map[string]any{"sparkling_power": 3}
	case "sos_chain_gen7":
		return map[string]any{"chain_length": 31}
	case "radar_chain_gen4", "radar_chain_xy", "radar_chain_bdsp":
		return map[string]any{"chain_length": 40}
	// search_level 200 is a typical mid/late-game value, not the theoretical
	// cap (which would push DexNav near 1/1 and dominate ranking unrealistically).
	case "dexnav_gen6":
		return map[string]any{"search_level": 200, "chain_length": 100}
	case "catch_combo_lgpe":
		return map[string]any{"count": 31}
	case "chain_fishing_gen6":
		return map[string]any{"count": 20}
	case "pla_research", "pla_mass_outbreak", "pla_massive_outbreak":
		// Best realistic case: Perfect research. The outbreak bonus (if any) is
		// implied by the formula_type, so it is not a param here.
		return map[string]any{"research_level": 10, "dex_perfect": true}
	case "ultra_wormhole":
		return map[string]any{"wormhole_ring_type": 4, "wormhole_distance_ly": 5000}
	default: // static, dynamax_adventures_gen8 (no params)
		return map[string]any{}
	}
}
