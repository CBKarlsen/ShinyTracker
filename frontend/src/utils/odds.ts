export interface OddsResult {
	rolls: number;
	denominator: number;
}

/**
 * Formula types that require user-supplied parameters at hunt start
 * (a chain length, search level, or Sparkling Power). Every other formula
 * derives its odds from the live encounter counter and needs no setup step.
 * This is the single source of truth shared by HuntParametersEditor (which
 * renders the inputs) and the drawer (which decides whether to open the modal).
 */
export const PARAM_FORMULAS = [
	"outbreak_defeats_sv",
	"radar_chain_gen4",
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

	let rolls = baseRolls;
	let denominator = baseOdds;

	if (type === "static") {
		rolls = baseRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = Math.floor(baseOdds / rolls);
		return { rolls, denominator };
	}

	if (type === "radar_chain_gen4") {
		const paramChain = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const chain = Math.max(0, Math.min(paramChain, 40));
		// Bulbapedia: numerator = ceil(65535 / (8200 - 200*chain)); rate = numerator / 65536.
		// chain 0 -> 1/8192 (base Gen 4 odds); chain 40 (cap) -> 1/200.
		const numerator = Math.ceil(65535 / (8200 - 200 * chain));
		denominator = Math.round(65536 / numerator);
		// Shiny Charm doesn't apply to Gen 4 Pokeradar
		rolls = 1;
	} else if (type === "catch_combo_lgpe") {
		// chain_length is the live catch combo; fall back to the encounter
		// counter for legacy hunts created before chain tracking existed.
		const paramCombo = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const combo = Math.max(0, paramCombo);
		let extraRolls = 0;
		if (combo >= 31) {
			extraRolls = 11;
		} else if (combo >= 21) {
			extraRolls = 7;
		} else if (combo >= 11) {
			extraRolls = 3;
		}
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = Math.floor(baseOdds / rolls);
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
		denominator = Math.floor(baseOdds / rolls);
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
		denominator = Math.floor(baseOdds / rolls);
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
		denominator = Math.floor(baseOdds / rolls);
	} else if (type === "dynamax_adventures_gen8") {
		denominator = hasShinyCharm ? 100 : 300;
		rolls = 1;
	} else if (type === "chain_fishing_gen6") {
		// chain_length is the live current chain; fall back to the encounter
		// counter for legacy hunts created before chain tracking existed.
		const paramChain = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const chain = Math.max(0, Math.min(paramChain, 20));
		const extraRolls = chain * 2;
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = Math.floor(baseOdds / rolls);
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
		denominator = Math.floor(baseOdds / rolls);
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
