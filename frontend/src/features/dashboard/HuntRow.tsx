import type React from "react";
import { SparkSm, IcPin } from "../../components/ui/icons";
import { calculateOdds } from "../../utils/odds";
import type { Hunt } from "../../types/models";

function fmtNum(n: number) {
	return n.toLocaleString("en-US");
}

function fmtHM(s: number) {
	const h = Math.floor(s / 3600);
	const m = Math.floor((s % 3600) / 60);
	if (h > 0) return `${h}h ${m}m`;
	return `${m}m`;
}

function gameShort(title: string | null): string {
	if (!title) return "—";
	const map: Record<string, string> = {
		"Scarlet/Violet": "SV",
		"Sword/Shield": "SW",
		Sword: "SW",
		Shield: "SH",
		"Brilliant Diamond/Shining Pearl": "BD",
		BDSP: "BD",
		"Legends: Arceus": "LA",
		"Omega Ruby/Alpha Sapphire": "OR",
		"Omega Ruby": "OR",
		"Alpha Sapphire": "AS",
		"HeartGold/SoulSilver": "HG",
		"Let's Go Pikachu/Eevee": "LG",
		"X/Y": "XY",
		"Ultra Sun/Ultra Moon": "US",
		"Sun/Moon": "SM",
		"Black 2/White 2": "B2",
		"Black/White": "BW",
		"Diamond/Pearl": "DP",
		Platinum: "Pt",
		Crystal: "C",
		"Gold/Silver": "GS",
		"Red/Blue/Yellow": "RB",
	};
	return map[title] || title.slice(0, 2).toUpperCase();
}

function getLuckLabel(pct: number): string {
	if (pct < 0.33) return "running lucky";
	if (pct < 0.67) return "about average";
	if (pct < 0.90) return "pushing your luck";
	return "overdue";
}

export function HuntRow({
	hunt,
	onIncrement,
	onComplete,
	onPhase,
	onPin,
}: {
	hunt: Hunt;
	onIncrement: (id: string, e: React.MouseEvent) => void;
	onComplete: (id: string) => void;
	onPhase: (hunt: Hunt) => void;
	onPin: (id: string) => void;
}) {
	const { denominator: expected } = calculateOdds(
		hunt.formula_type,
		hunt.encounter_count,
		hunt.has_shiny_charm || false,
		hunt.base_odds || 4096,
		hunt.base_rolls || 1,
		hunt.charm_rolls || 0,
		(hunt.hunt_parameters as Record<string, any>) || {}
	);
	const isOver = hunt.encounter_count > expected;
	
	let cumP: number | null = null;
	if (hunt.base_odds != null) {
		let currentNotShiny = 1;
		for (let e = 1; e <= hunt.encounter_count; e++) {
			const { denominator } = calculateOdds(
				hunt.formula_type,
				e,
				hunt.has_shiny_charm || false,
				hunt.base_odds,
				hunt.base_rolls || 1,
				hunt.charm_rolls || 0,
				(hunt.hunt_parameters as Record<string, any>) || {}
			);
			currentNotShiny *= (1 - (1 / Math.max(1, denominator)));
		}
		cumP = 1 - currentNotShiny;
	}

	const spriteUrl = `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/${hunt.pokemon_id}.png`;

	return (
		<div className="hunt-row hunt-row-clickable" onClick={() => onPin(hunt.id)} title="Promote to main hunt">
			<div className="sprite-wrap">
				<img src={spriteUrl} alt={hunt.pokemon_name} />
			</div>
			<div>
				<div className="nm" style={{ display: "flex", alignItems: "center", gap: 8 }}>
					{hunt.pokemon_name}
					{isOver && <span className="over-pill">Over</span>}
					{hunt.phase_count > 0 && <span className="phase-pill">P{hunt.phase_count + 1}</span>}
				</div>
				<div className="meta">
					<span className="pill">{hunt.custom_method_name ? "Custom" : gameShort(hunt.game_title)}</span>
					<span>{hunt.custom_method_name || hunt.method_name || "—"}</span>
					{hunt.has_shiny_charm && (
						<span className="charm-pill">
							<SparkSm size={8} />
						</span>
					)}
				</div>
			</div>
			<div className="col-num">
				{fmtNum(hunt.encounter_count)}
				<small>encounters</small>
			</div>
			<div className="col-num col-time">
				{fmtHM(hunt.total_time_seconds)}
				<small>hunted</small>
			</div>
			<div className="col-bar">
				{cumP != null ? (
					<>
						<div className="barwrap">
							<span style={{ width: `${Math.min(cumP * 100, 100)}%`, background: "var(--gold)", opacity: 0.8 }} />
						</div>
						<div
							style={{
								fontFamily: "var(--font-mono)",
								fontSize: 10,
								color: "var(--ink-3)",
								marginTop: 4,
								letterSpacing: "0.04em",
								display: "flex",
								gap: 6,
							}}
						>
							<span style={{ color: "var(--ink-2)" }}>{(cumP * 100).toFixed(1)}%</span>
							{hunt.encounter_count > 0 && <span>· {getLuckLabel(cumP)}</span>}
						</div>
					</>
				) : (
					<div style={{ fontFamily: "var(--font-mono)", fontSize: 10, color: "var(--ink-4)" }}>—</div>
				)}
			</div>
			<div style={{ display: "flex", gap: 6, justifyContent: "flex-end" }}>
				<button
					className="btn ghost"
					style={{ padding: "6px 8px" }}
					onClick={(e) => {
						e.stopPropagation();
						onPin(hunt.id);
					}}
					title="Make this the main hunt"
				>
					<IcPin />
				</button>
				<button
					className="btn"
					style={{ padding: "6px 10px" }}
					onClick={(e) => {
						e.stopPropagation();
						onIncrement(hunt.id, e);
					}}
				>
					+1
				</button>
				<button
					className="btn ghost"
					style={{ padding: "6px 8px" }}
					onClick={(e) => {
						e.stopPropagation();
						onPhase(hunt);
					}}
					title="Log phase"
				>
					<SparkSm size={10} color="var(--violet)" />
				</button>
				<button
					className="btn ghost"
					style={{ padding: "6px 8px" }}
					onClick={(e) => {
						e.stopPropagation();
						onComplete(hunt.id);
					}}
					title="Found it"
				>
					<SparkSm size={10} color="var(--gold)" />
				</button>
			</div>
		</div>
	);
}
