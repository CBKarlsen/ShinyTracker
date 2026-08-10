export interface OddsResult {
	rolls: number;
	denominator: number;
}

// Integer ceil/round division. Must match Go's integer math bit-for-bit: JS
// `Math.round` rounds half-up, Go rounds half-away-from-zero, and for the
// positive-only inputs here that's the same rule as `Math.floor((2a+b)/(2b))`.
// Do not swap these for `Math.ceil`/`Math.round` on the float division.
function ceilDiv(a: number, b: number): number {
	return Math.floor((a + b - 1) / b);
}
function roundDiv(a: number, b: number): number {
	return Math.floor((2 * a + b) / (2 * b));
}

// Bulbapedia: https://bulbapedia.bulbagarden.net/wiki/Pok%C3%A9_Radar
// BDSP Poké Radar numerator per chain length (rate = numerator / 65536).
// Two real discontinuities (chain 30, chain 36) -- not a closed form.
const BDSP_RADAR_NUMERATORS = [
	16, 17, 18, 19, 20, 21, 22, 23, 24, 25, // chain  0- 9
	26, 27, 28, 29, 30, 31, 32, 33, 34, 35, // chain 10-19
	36, 37, 38, 39, 40, 41, 42, 43, 44, 45, // chain 20-29
	50, 51, 52, 53, 54, 55, // chain 30-35
	66, 82, 164, 328, 662, // chain 36-40
];

/**
 * Formula types that require user-supplied parameters at hunt start
 * (a chain length, search level, or Sparkling Power). Every other formula
 * derives its odds from the live encounter counter and needs no setup step.
 * This is the single source of truth shared by HuntParametersEditor (which
 * renders the inputs) and the drawer (which decides whether to open the modal).
 */
export const PARAM_FORMULAS = [
	"brilliant_swsh",
	"outbreak_defeats_sv",
	"radar_chain_gen4",
	"radar_chain_xy",
	"radar_chain_bdsp",
	"sos_chain_gen7",
	"dexnav_gen6",
	"sandwich_power_sv",
	"pla_research",
	"pla_mass_outbreak",
	"pla_massive_outbreak",
	"ultra_wormhole",
] as const;

export function routeNeedsParams(formulaType: string | null | undefined): boolean {
	return !!formulaType && (PARAM_FORMULAS as readonly string[]).includes(formulaType);
}

/**
 * Formula types whose odds come from a *consecutive chain* that the player
 * builds up and that resets to zero when broken. These are the only methods
 * that track a live `hunt_parameters.chain_length` separate from the lifetime
 * encounter total, and the only ones that show a "Break chain" control.
 *
 * Note: `chain_fishing_gen6` and `catch_combo_lgpe` are streak methods but are
 * NOT in `PARAM_FORMULAS` — their chain is incremented live by the dashboard,
 * not configured up-front via HuntParametersEditor.
 */
export const STREAK_FORMULAS = [
	"chain_fishing_gen6",
	"catch_combo_lgpe",
	"sos_chain_gen7",
	"radar_chain_gen4",
	"radar_chain_xy",
	"radar_chain_bdsp",
	"dexnav_gen6",
] as const;

export function isStreakMethod(formulaType: string | null | undefined): boolean {
	return !!formulaType && (STREAK_FORMULAS as readonly string[]).includes(formulaType);
}

/**
 * Returns the canonical default hunt_parameters for a given formula_type.
 * Used both in NewHuntModal (so we POST non-empty params from the start)
 * and as a fallback in dashboard components for hunts stored with empty params.
 *
 * Rule: only seed defaults for params whose value is NOT derived from the
 * encounter counter. Methods like radar_chain_gen4, sos_chain_gen7, dexnav_gen6,
 * catch_combo_lgpe, and chain_fishing_gen6 all fall back to `encounters` when
 * chain_length is absent — seeding a numeric 0 would disable that fallback and
 * pin those hunts at base odds forever. Return {} for them so calculateOdds
 * keeps using the live encounter count.
 */
export function defaultParamsFor(formulaType: string | null | undefined): Record<string, any> {
	switch (formulaType) {
		case "outbreak_defeats_sv":
			// defeated_count and sparkling_power are user-set, not derived from encounters.
			return { defeated_count: 0, sparkling_power: 0 };
		case "sandwich_power_sv":
			// sparkling_power is user-set.
			return { sparkling_power: 0 };
		case "pla_research":
		case "pla_mass_outbreak":
		case "pla_massive_outbreak":
			// research_level/dex_perfect are user-set; the outbreak bonus is implied
			// by the formula_type (which method row was chosen), not a param.
			return { research_level: 0, dex_perfect: false };
		case "ultra_wormhole":
			return { wormhole_ring_type: 4, wormhole_distance_ly: 0 };
		case "radar_chain_xy":
		case "radar_chain_bdsp":
			return { chain_length: 40 };
		// number_battled is a persistent per-species tally, not a resettable chain,
		// so it IS seeded as a default (unlike the streak formulas below).
		case "brilliant_swsh":
			return { number_battled: 500 };
		default:
			// radar_chain_gen4, sos_chain_gen7, dexnav_gen6, catch_combo_lgpe,
			// chain_fishing_gen6, static, dynamax_adventures_gen8, etc. all either
			// use encounters directly or need no seeded defaults.
			return {};
	}
}

/**
 * Calculates rolls and final denominator for a given encounter formula.
 */
export function calculateOdds(
	formulaType: string | null | undefined,
	encounters: number,
	hasShinyCharm: boolean,
	baseOdds: number,
	baseRolls: number,
	charmRolls: number,
	huntParams: Record<string, any> = {},
): OddsResult {
	const type = formulaType || "static";

	// Mirrors Go's floorDiv in internal/calc/methods.go: a roll count of 0 or less
	// is clamped to 1 rather than dividing by zero. Without this TS returns Infinity
	// where Go returns baseOdds.
	const floorDiv = (r: number) => Math.floor(baseOdds / (r > 0 ? r : 1));

	let rolls = baseRolls;
	let denominator = baseOdds;

	if (type === "static") {
		rolls = baseRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = floorDiv(rolls);
		return { rolls, denominator };
	}

	if (type === "radar_chain_gen4") {
		// DPPt ONLY -- radar_chain_xy and radar_chain_bdsp (below) are separate
		// formulas: these are three genuinely different mechanics, not one curve
		// with a scale factor.
		const paramChain = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const chain = Math.max(0, Math.min(paramChain, 40));
		// Bulbapedia: numerator = ceil(65535 / (8200 - 200*chain)); rate = numerator / 65536.
		// chain 0 -> 1/8192 (base Gen 4 odds); chain 40 (cap) -> 1/200.
		// base_odds is NOT read -- the curve already encodes 1/8192 at chain 0.
		// Shiny Charm is IGNORED -- it does not exist in Gen IV. Correct by design.
		const d = 8200 - 200 * chain;
		const numerator = ceilDiv(65535, d);
		denominator = roundDiv(65536, numerator);
		rolls = 1;
	} else if (type === "radar_chain_xy") {
		// X/Y ONLY. The only radar formula that reads base_odds / applies the
		// Shiny Charm -- the charm affects the normal-roll probability only,
		// never the sparkle (chain) probability. Same composition shape as
		// dexnav_gen6 below (pSparkle + (1-pSparkle)*pNormal).
		const paramChain = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const chain = Math.max(0, Math.min(paramChain, 40));
		const sparkleD = 8100 - 200 * chain; // 8100 at chain 0, 100 at chain 40
		const pSparkle = 1 / sparkleD;
		rolls = baseRolls + (hasShinyCharm ? charmRolls : 0);
		const pNormal = rolls / baseOdds;
		const pTotal = pSparkle + (1 - pSparkle) * pNormal;
		denominator = pTotal > 0 ? Math.round(1 / pTotal) : baseOdds;
		rolls = 1;
	} else if (type === "radar_chain_bdsp") {
		// BDSP ONLY -- lookup table, see BDSP_RADAR_NUMERATORS above.
		// base_odds is NOT read (numerator[0]=16 already IS 1/4096); Shiny Charm
		// is IGNORED -- BDSP's Shiny Charm effect on the Radar is breeding-only/datamined.
		const paramChain = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const chain = Math.max(0, Math.min(paramChain, 40));
		const numerator = BDSP_RADAR_NUMERATORS[chain];
		denominator = roundDiv(65536, numerator);
		rolls = 1;
	} else if (type === "catch_combo_lgpe") {
		// chain_length is the live catch combo; "count" is the equivalent key used
		// by the Go engine's route ranking and by shared/odds_anchors.json. Accept
		// both so every engine reading the same params agrees. Falls back to the
		// encounter counter for legacy hunts created before chain tracking existed.
		const paramCombo =
			typeof huntParams.chain_length === "number"
				? huntParams.chain_length
				: typeof huntParams.count === "number"
					? huntParams.count
					: encounters;
		const combo = Math.max(0, paramCombo);
		let extraRolls = 0;
		if (combo >= 31) {
			extraRolls = 11;
		} else if (combo >= 21) {
			extraRolls = 7;
		} else if (combo >= 11) {
			extraRolls = 3;
		}
		// An active Lure adds exactly one extra roll.
		const lure = huntParams.lure_active === true;
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0) + (lure ? 1 : 0);
		denominator = floorDiv(rolls);
	} else if (type === "brilliant_swsh") {
		// SwSh Brilliant (sparkle-aura) Pokemon. Rolls scale with how many of that
		// species the player has battled; charm is additive on top.
		// https://bulbapedia.bulbagarden.net/wiki/Brilliant_Pok%C3%A9mon
		// number_battled is NOT a chain -- it never resets, so it defaults to 0
		// rather than falling back to the live encounter counter.
		const battled = Math.max(0, typeof huntParams.number_battled === "number" ? huntParams.number_battled : 0);
		let extraRolls = 0;
		if (battled >= 500) {
			extraRolls = 6;
		} else if (battled >= 300) {
			extraRolls = 5;
		} else if (battled >= 200) {
			extraRolls = 4;
		} else if (battled >= 100) {
			extraRolls = 3;
		} else if (battled >= 50) {
			extraRolls = 2;
		} else if (battled >= 1) {
			extraRolls = 1;
		}
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = floorDiv(rolls);
	} else if (type === "outbreak_defeats_sv") {
		const paramDefeats = typeof huntParams.defeated_count === "number" ? huntParams.defeated_count : encounters;
		const defeats = Math.max(0, paramDefeats);
		let extraRolls = 0;
		if (defeats >= 60) {
			extraRolls = 2;
		} else if (defeats >= 30) {
			extraRolls = 1;
		}
		// Sandwich Sparkling Power stacks additively with outbreak defeats (matches
		// Go EffectiveOdds): outbreak 60 + Sparkling Lv3 + charm = 8 rolls -> 1/512.
		const power = typeof huntParams.sparkling_power === "number" ? huntParams.sparkling_power : 0;
		if (power >= 1 && power <= 3) {
			extraRolls += power;
		}
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = floorDiv(rolls);
	} else if (type === "sos_chain_gen7") {
		const paramChain = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const chain = Math.max(0, paramChain) % 255;
		let extraRolls = 0;
		if (chain >= 31) {
			extraRolls = 12;
		} else if (chain >= 21) {
			extraRolls = 8;
		} else if (chain >= 11) {
			extraRolls = 4;
		}
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = floorDiv(rolls);
	} else if (type === "dexnav_gen6") {
		const searchLevel = Math.max(0, typeof huntParams.search_level === "number" ? huntParams.search_level : 0);
		const paramChain = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const chain = Math.max(0, paramChain);

		let t = 0;
		if (searchLevel > 0) t += Math.min(searchLevel, 100) * 6;
		if (searchLevel > 100) t += Math.min(searchLevel - 100, 100) * 2;
		if (searchLevel > 200) t += (searchLevel - 200) * 1;
		
		// dexnav_level = (tiered points) / 100, per-check shiny prob = dexnav_level / 10000.
		// Mirrors backend calc.EffectiveOdds; the /100 was missing (100x too high → bogus 1/12).
		const probDexNav = searchLevel > 0 ? t / 100 / 10000 : 0;
		
		let extraRolls = 0;
		if (chain > 0 && chain % 100 === 0) extraRolls = 10;
		else if (chain > 0 && chain % 50 === 0) extraRolls = 5;
		
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		const probStandard = rolls / baseOdds;
		
		const totalProb = probDexNav + ((1 - probDexNav) * probStandard);
		denominator = totalProb > 0 ? Math.round(1 / totalProb) : baseOdds;
		rolls = 1;
	} else if (type === "sandwich_power_sv") {
		const power = typeof huntParams.sparkling_power === "number" ? huntParams.sparkling_power : 0;
		let extraRolls = 0;
		if (power === 1) extraRolls = 1;
		else if (power === 2) extraRolls = 2;
		else if (power === 3) extraRolls = 3;
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = floorDiv(rolls);
	} else if (type === "dynamax_adventures_gen8") {
		denominator = hasShinyCharm ? 100 : 300;
		rolls = 1;
	} else if (type === "chain_fishing_gen6") {
		// Same two-key situation as catch_combo_lgpe: chain_length is the live chain
		// from stored hunt_parameters, "count" is what Go's route ranking supplies.
		// Precedence must match that formula exactly -- chain_length > count > the
		// encounter counter (the last for legacy hunts predating chain tracking).
		const paramChain =
			typeof huntParams.chain_length === "number"
				? huntParams.chain_length
				: typeof huntParams.count === "number"
					? huntParams.count
					: encounters;
		const chain = Math.max(0, Math.min(paramChain, 20));
		const extraRolls = chain * 2;
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = floorDiv(rolls);
	} else if (type === "pla_research" || type === "pla_mass_outbreak" || type === "pla_massive_outbreak") {
		// Legends: Arceus additive rolls. Anchors (charmRolls=3, floorDiv):
		// base 4096 | research10 2048 | perfect 1024 | charm-only 1024 |
		// MO 157 | MO+perfect 141 | MO+perfect+charm 128 |
		// MMO 315 | MMO+perfect 256 | MMO+perfect+charm 215.
		// Lv10 (+1) and Perfect (+2) STACK. The outbreak bonus comes from the
		// formula_type (where you hunt), not a param: pla_mass_outbreak +25,
		// pla_massive_outbreak +12. MMO is worse per-encounter than MO by design.
		let extraRolls = 0;
		const research = typeof huntParams.research_level === "number" ? huntParams.research_level : 0;
		if (research >= 10) extraRolls += 1;
		if (huntParams.dex_perfect === true) extraRolls += 2;
		if (type === "pla_mass_outbreak") extraRolls += 25;
		else if (type === "pla_massive_outbreak") extraRolls += 12;
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = floorDiv(rolls);
	} else if (type === "ultra_wormhole") {
		// USUM Ultra Warp Ride (non-legendary). Distance (cap 5000ly, k<=9) x ring rarity.
		// Shiny Charm has NO effect. Anchors: ring4@5000 ->3, ring4@2000 ->8,
		// ring3@5000 ->5, ring2@5000 ->10, ring1 ->100, ring4@0 ->100.
		const ring = typeof huntParams.wormhole_ring_type === "number" ? huntParams.wormhole_ring_type : 4;
		const dist = typeof huntParams.wormhole_distance_ly === "number" ? huntParams.wormhole_distance_ly : 0;
		const k = Math.max(0, Math.min(Math.floor(dist / 500) - 1, 9));
		let percent = 1;
		if (ring === 2) percent = Math.min(10, 1 + 1 * k);
		else if (ring === 3) percent = Math.min(19, 1 + 2 * k);
		else if (ring === 4) percent = Math.min(36, 1 + 4 * k);
		else percent = 1;
		if (percent < 1) percent = 1;
		denominator = Math.round(100 / percent);
		rolls = 1;
	} else {
		// Unknown formula_type -- typically a backend-first deploy that seeded a
		// formula this build doesn't know yet. Fall back to `static`, matching Go's
		// default case and the Swift engine. Returning baseOdds untouched (the old
		// behaviour) silently dropped the Shiny Charm: 1/4096 in the browser vs
		// 1/1365 from the API for the same hunt. Pinned by the "unknown formula
		// falls back to static" anchor in shared/odds_anchors.json.
		rolls = baseRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = floorDiv(rolls);
	}

	return { rolls, denominator };
}

/**
 * Computes the cumulative probability of finding a shiny.
 * For dynamic formulas, it simulates the progression of probabilities.
 */
export function calcCumulativeOdds(
	encounters: number,
	baseOdds: number,
	rolls: number,
	formulaType?: string | null,
	hasShinyCharm?: boolean | null,
	baseRolls?: number | null,
	charmRolls?: number | null,
	huntParams?: Record<string, any>,
): number {
	if (baseOdds <= 0 || encounters <= 0) return 0;

	if (!formulaType || formulaType === "static") {
		if (rolls <= 0) return 0;
		return 1 - (1 - rolls / baseOdds) ** encounters;
	}

	let probNotShiny = 1;
	const bR = baseRolls ?? 1;
	const cR = charmRolls ?? 0;
	const charm = hasShinyCharm ?? false;

	for (let i = 1; i <= encounters; i++) {
		const { denominator } = calculateOdds(
			formulaType,
			i,
			charm,
			baseOdds,
			bR,
			cR,
			huntParams
		);
		const stepDenom = denominator > 0 ? denominator : baseOdds;
		probNotShiny *= 1 - 1 / stepDenom;
	}

	return 1 - probNotShiny;
}
