export interface OddsResult {
	rolls: number;
	denominator: number;
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
		// Capped at 40. formula: 1 / round(65536 - 1640 * chain)
		// Yields 1/99 at chain 40. We use 1635.925 as the step to land exactly on 99.
		denominator = Math.max(99, Math.round(65536 - 1635.925 * chain));
		// Shiny Charm doesn't apply to Gen 4 Pokeradar
		rolls = 1;
	} else if (type === "catch_combo_lgpe") {
		const combo = Math.max(0, encounters);
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
		
		const probDexNav = searchLevel > 0 ? t / 10000 : 0;
		
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
		const chain = Math.max(0, Math.min(encounters, 20));
		const extraRolls = chain * 2;
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = Math.floor(baseOdds / rolls);
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
