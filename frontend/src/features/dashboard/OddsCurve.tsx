import type { Hunt } from "../../types/models";
import { shinyCharmAvailable } from "../../utils/games";
import { calculateOdds, defaultParamsFor } from "../../utils/odds";

function resolvedParams(hunt: Hunt): Record<string, any> {
	const stored = (hunt.hunt_parameters as Record<string, any>) || {};
	if (Object.keys(stored).length > 0) return stored;
	return defaultParamsFor(hunt.formula_type);
}

export function OddsCurve({ hunt }: { hunt: Hunt }) {
	const odds = hunt.base_odds || 4096;
	const params = resolvedParams(hunt);
	// Gate charm: a stale `true` from the DB must not inflate odds for games
	// where the Shiny Charm doesn't exist.
	const effectiveCharm =
		(hunt.has_shiny_charm || false) && shinyCharmAvailable(hunt.game_id);
	const { denominator: currentDenominator } = calculateOdds(
		hunt.formula_type,
		hunt.encounter_count,
		effectiveCharm,
		odds,
		hunt.base_rolls || 1,
		hunt.charm_rolls || 0,
		params,
	);

	const expected = currentDenominator;
	// 3.2× headroom (not 3×) so the 3× milestone marker + its label stay inside the viewbox.
	const max = Math.max(expected * 3.2, hunt.encounter_count * 1.4, 100);
	const W = 600;
	const H = 60;
	const N = 60;

	const points: [number, number][] = [];
	let currentNotShiny = 1;
	let lastN = 0;
	let youP = 0;
	let foundYouP = false;

	for (let i = 0; i <= N; i++) {
		const n = Math.round((i / N) * max);
		for (let e = lastN + 1; e <= n; e++) {
			const { denominator } = calculateOdds(
				hunt.formula_type,
				e,
				effectiveCharm,
				odds,
				hunt.base_rolls || 1,
				hunt.charm_rolls || 0,
				params,
			);
			currentNotShiny *= 1 - 1 / Math.max(1, denominator);
			if (!foundYouP && e === hunt.encounter_count) {
				youP = 1 - currentNotShiny;
				foundYouP = true;
			}
		}
		if (!foundYouP && n >= hunt.encounter_count && hunt.encounter_count === 0) {
			youP = 0;
			foundYouP = true;
		}
		points.push([(i / N) * W, H - (1 - currentNotShiny) * H]);
		lastN = n;
	}

	const pathD = points
		.map(
			(p, i) => `${i === 0 ? "M" : "L"} ${p[0].toFixed(1)} ${p[1].toFixed(1)}`,
		)
		.join(" ");
	const fillD = `${pathD} L ${W} ${H} L 0 ${H} Z`;

	const youX = Math.min((hunt.encounter_count / max) * W, W - 1);
	const youY = H - youP * H;
	const expX = (expected / max) * W;

	// Milestone x-positions for 2× and 3× — only render if within visible range.
	const exp2X = expected * 2 <= max ? ((expected * 2) / max) * W : null;
	const exp3X = expected * 3 <= max ? ((expected * 3) / max) * W : null;

	return (
		<div className="odds-curve">
			<div className="odds-curve-head">
				<div className="ttl">
					Cumulative probability — {(youP * 100).toFixed(1)}% of hunters caught
					by now
				</div>
				<div className="pct">
					1 / {currentDenominator.toLocaleString()} live odds
				</div>
			</div>
			<svg
				className="odds-curve-svg"
				viewBox={`0 0 ${W} ${H}`}
				preserveAspectRatio="none"
			>
				<defs>
					<linearGradient id="curveFill" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0%" stopColor="var(--gold)" stopOpacity="0.35" />
						<stop offset="100%" stopColor="var(--gold)" stopOpacity="0" />
					</linearGradient>
				</defs>
				<path d={fillD} fill="url(#curveFill)" />
				<path d={pathD} fill="none" stroke="var(--gold)" strokeWidth="1.5" />
				{/* 2× milestone */}
				{exp2X != null && (
					<>
						<line
							x1={exp2X}
							y1="0"
							x2={exp2X}
							y2={H}
							stroke="var(--ink-4)"
							strokeWidth="1"
							strokeDasharray="2 4"
							strokeOpacity="0.6"
						/>
						<text
							x={exp2X + 3}
							y="11"
							fill="var(--ink-4)"
							fontSize="9"
							fontFamily="JetBrains Mono"
						>
							2×
						</text>
					</>
				)}
				{/* 3× milestone */}
				{exp3X != null && (
					<>
						<line
							x1={exp3X}
							y1="0"
							x2={exp3X}
							y2={H}
							stroke="var(--ink-4)"
							strokeWidth="1"
							strokeDasharray="2 4"
							strokeOpacity="0.6"
						/>
						<text
							x={exp3X + 3}
							y="11"
							fill="var(--ink-4)"
							fontSize="9"
							fontFamily="JetBrains Mono"
						>
							3×
						</text>
					</>
				)}
				{/* 1× expected line */}
				<line
					x1={expX}
					y1="0"
					x2={expX}
					y2={H}
					stroke="var(--ink-4)"
					strokeWidth="1"
					strokeDasharray="2 3"
				/>
				<line
					x1={youX}
					y1="0"
					x2={youX}
					y2={H}
					stroke="var(--ink-1)"
					strokeWidth="1"
				/>
				<circle cx={youX} cy={youY} r="3" fill="var(--ink-1)" />
				<text
					x={expX + 4}
					y="11"
					fill="var(--ink-3)"
					fontSize="9"
					fontFamily="JetBrains Mono"
				>
					1× · expected
				</text>
				<text
					x={youX + 4}
					y={Math.max(youY - 6, 14)}
					fill="var(--ink-1)"
					fontSize="9"
					fontFamily="JetBrains Mono"
				>
					you · {hunt.encounter_count.toLocaleString()}
				</text>
			</svg>
		</div>
	);
}
