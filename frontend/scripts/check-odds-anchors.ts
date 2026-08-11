/**
 * Asserts the TypeScript odds engine against shared/odds_anchors.json.
 *
 * Why this exists: the odds engine is implemented three times — Go
 * (backend/internal/calc/methods.go), TypeScript (src/utils/odds.ts) and Swift
 * (ios/ShinyTrackerKit). Go and Swift both assert the shared anchors in their
 * own test suites. TypeScript did not, so it was the one engine free to drift
 * unnoticed — which is precisely the failure the fixture exists to prevent.
 * An identical bug in two engines reads as consensus; only the anchors are
 * evidence.
 *
 * Deliberately a plain script, not a test framework. The frontend has no test
 * runner and does not need one for this.
 *
 *   npm run check:anchors
 *
 * Exits non-zero on any mismatch so CI fails loudly.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { calculateOdds } from "../src/utils/odds";

interface Anchor {
	name: string;
	formula: string;
	params: Record<string, unknown>;
	base_odds: number;
	base_rolls: number;
	charm_rolls: number;
	has_charm: boolean;
	expected: number;
	tolerance: number;
}

const here = dirname(fileURLToPath(import.meta.url));
const fixturePath = resolve(here, "../../shared/odds_anchors.json");

let anchors: Anchor[];
try {
	anchors = JSON.parse(readFileSync(fixturePath, "utf8")).anchors;
} catch (err) {
	console.error(`FATAL: could not read ${fixturePath}\n${err}`);
	process.exit(1);
}

// A missing or truncated fixture must fail loudly rather than "pass" with
// nothing asserted. Raise this alongside the Go and Swift guards when anchors
// are added; a drop should be a deliberate, visible edit.
const MIN_ANCHORS = 61;
if (!Array.isArray(anchors) || anchors.length < MIN_ANCHORS) {
	console.error(`FATAL: expected >= ${MIN_ANCHORS} anchors, loaded ${anchors?.length ?? 0} — fixture truncated?`);
	process.exit(1);
}

let failed = 0;
for (const a of anchors) {
	const { denominator } = calculateOdds(
		a.formula,
		0,
		a.has_charm,
		a.base_odds,
		a.base_rolls,
		a.charm_rolls,
		{ ...a.params },
	);
	if (Math.abs(denominator - a.expected) > a.tolerance) {
		failed++;
		console.error(`FAIL  ${a.name}: got 1/${denominator}, want 1/${a.expected} (tolerance ${a.tolerance})`);
	}
}

if (failed > 0) {
	console.error(`\n${failed}/${anchors.length} anchors FAILED — the TS engine disagrees with shared/odds_anchors.json.`);
	console.error("The anchors are the source of truth, not this engine. Fix odds.ts, not the fixture.");
	process.exit(1);
}

console.log(`${anchors.length}/${anchors.length} odds anchors pass`);
