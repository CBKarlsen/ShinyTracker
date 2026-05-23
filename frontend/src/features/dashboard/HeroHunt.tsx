import type React from "react";
import { useEffect, useRef, useState } from "react";
import { SparkSm, IcPlus } from "../../components/ui/icons";
import { TimerDisplay, type TimerStatus } from "../../components/ui/TimerDisplay";
import { OddsCurve } from "./OddsCurve";
import { getShowdownGif } from "../../utils/pokemon";
import { calculateOdds } from "../../utils/odds";
import type { Hunt } from "../../types/models";

function fmtNum(n: number) {
	return n.toLocaleString("en-US");
}

function getLuckLabel(pct: number): string {
	if (pct < 0.33) return "running lucky";
	if (pct < 0.67) return "about average";
	if (pct < 0.90) return "pushing your luck";
	return "overdue";
}

export function HeroHunt({
	hunt,
	onIncrement,
	onComplete,
	onPhase,
}: {
	hunt: Hunt;
	onIncrement: (id: string, e: React.MouseEvent) => void;
	onComplete: (id: string) => void;
	onPhase: (hunt: Hunt) => void;
}) {
	const { denominator: expected } = calculateOdds(
		hunt.formula_type,
		hunt.encounter_count,
		hunt.has_shiny_charm || false,
		hunt.base_odds || 4096,
		hunt.base_rolls || 1,
		hunt.charm_rolls || 0
	);
	const isOver = hunt.encounter_count > expected;
	const ratio = expected ? Math.min(hunt.encounter_count / expected, 1) : 0;
	
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
				hunt.charm_rolls || 0
			);
			currentNotShiny *= (1 - (1 / Math.max(1, denominator)));
		}
		cumP = 1 - currentNotShiny;
	}

	const btnRef = useRef<HTMLButtonElement>(null);
	const [bumping, setBumping] = useState(false);

	// Smart timer
	const [sessionSec, setSessionSec] = useState(0);
	const [manualPaused, setManualPaused] = useState(false);
	const [lastPing, setLastPing] = useState(Date.now());
	const idleMs = Math.max(45, Math.min(180, (hunt.avg_time_seconds || 8) * 6)) * 1000;

	useEffect(() => {
		const id = setInterval(() => {
			if (manualPaused) return;
			if (Date.now() - lastPing > idleMs) return;
			setSessionSec((s) => s + 1);
		}, 1000);
		return () => clearInterval(id);
	}, [manualPaused, lastPing, idleMs]);

	const timerStatus: TimerStatus =
		manualPaused ? "paused" : Date.now() - lastPing > idleMs ? "idle" : "live";

	const totalSeconds = hunt.total_time_seconds + sessionSec;

	const handlePlus = (e: React.MouseEvent) => {
		setLastPing(Date.now());
		setBumping(true);
		setTimeout(() => setBumping(false), 250);
		const btn = btnRef.current;
		if (btn) {
			const rect = btn.getBoundingClientRect();
			const r = document.createElement("span");
			r.className = "ripple";
			r.style.left = `${e.clientX - rect.left}px`;
			r.style.top = `${e.clientY - rect.top}px`;
			btn.appendChild(r);
			setTimeout(() => r.remove(), 600);
		}
		onIncrement(hunt.id, e);
	};

	const gifUrl = getShowdownGif(hunt.pokemon_name);
	const spriteUrl = `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/${hunt.pokemon_id}.png`;

	return (
		<div className="hero">
			<div className="hero-left">
				<div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
					<div className="hero-tag">
						<SparkSm size={9} /> Active Hunt · Pinned
					</div>
					{hunt.has_shiny_charm && (
						<div
							className="hero-tag"
							style={{ color: "var(--gold)", borderColor: "var(--gold-line)", background: "transparent" }}
						>
							Charm
						</div>
					)}
					{hunt.phase_count > 0 && (
						<span className="phase-pill">
							<SparkSm size={8} color="var(--violet)" /> Phase {hunt.phase_count + 1}
						</span>
					)}
					{isOver && <span className="over-pill">Over odds</span>}
				</div>

				<div className="hero-title">
					<div>
						<div className="pname">{hunt.pokemon_name}</div>
						<div className="hero-meta">
							<span>
								{hunt.custom_method_name
									? `Custom · ${hunt.custom_method_name}`
									: `${hunt.game_title} · ${hunt.method_name}`}
							</span>
						</div>

						{(hunt.formula_type === 'outbreak_defeats_sv' || hunt.formula_type === 'radar_chain_gen4') && (
							<div style={{ marginTop: 12 }}>
								<button 
									className="btn ghost" 
									style={{ fontSize: 11, padding: '4px 8px' }}
									onClick={() => setBumping(!bumping)}
								>
									Edit Method Parameters
								</button>
								<div style={{ marginTop: 8, background: 'var(--bg-card)', padding: 12, borderRadius: 8, border: '1px solid var(--line-1)' }}>
									<div style={{ fontSize: 11, color: "var(--ink-3)", fontFamily: "var(--font-mono)" }}>
										(UI ready! API integration for updating hunt_parameters dynamically during the hunt will be connected next.)
									</div>
								</div>
							</div>
						)}

						<div className="pmeta" style={{ marginTop: 4 }}>
							<span>
								Hunt #{hunt.id.slice(-4)} · since{" "}
								{new Date(hunt.created_at).toLocaleDateString()}
							</span>
						</div>
					</div>
				</div>

				<div className="hero-counter">
					<span className="num">{fmtNum(hunt.encounter_count)}</span>
					<span className="lbl">encounters</span>
					<TimerDisplay
						sessionSec={sessionSec}
						totalSec={totalSeconds}
						status={timerStatus}
						onToggle={() => setManualPaused((p) => !p)}
						onReset={() => setSessionSec(0)}
					/>
				</div>

				<div>
					<div className={`hero-progress${isOver ? " over" : ""}`}>
						<span style={{ width: `${(isOver ? 1 : ratio) * 100}%` }} />
					</div>
					<div className="hero-progress-meta">
						<span>
							{cumP != null ? (
								hunt.encounter_count > 0 ? getLuckLabel(cumP) : "—"
							) : "no odds data"}
						</span>
						{isOver ? (
							<span className="over">
								+{fmtNum(hunt.encounter_count - (expected ?? 0))} over ·{" "}
								{(((hunt.encounter_count - (expected ?? 0)) / (expected ?? 1)) * 100).toFixed(0)}%
							</span>
						) : expected != null ? (
							<span>~{fmtNum(expected - hunt.encounter_count)} to expected</span>
						) : null}
					</div>
				</div>

				<div className="hero-actions">
					<button
						ref={btnRef}
						className={`plus-btn${bumping ? " plus-bump" : ""}`}
						onClick={handlePlus}
					>
						<IcPlus /> +1 encounter <span className="key">SPACE</span>
					</button>
					<button className="btn" onClick={() => onPhase(hunt)}>
						<SparkSm size={9} color="var(--violet)" /> Log phase
					</button>
					<button className="btn gold" onClick={() => onComplete(hunt.id)}>
						<SparkSm size={9} /> Found it!
					</button>
				</div>
			</div>

			<div className="hero-right">
				<div className="hero-sprite">
					<div className="hero-sparks">
						<span className="s">
							<SparkSm size={12} color="var(--gold)" />
						</span>
						<span className="s">
							<SparkSm size={10} color="var(--gold)" />
						</span>
						<span className="s">
							<SparkSm size={8} color="var(--gold)" />
						</span>
						<span className="s">
							<SparkSm size={10} color="var(--gold)" />
						</span>
					</div>
					<img
						src={gifUrl}
						alt={hunt.pokemon_name}
						onError={(e) => {
							e.currentTarget.onerror = null;
							e.currentTarget.src = spriteUrl;
						}}
					/>
				</div>
				{hunt.custom_method_name ? (
					<div style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: "var(--ink-3)", marginTop: 8 }}>
						Custom method — no odds data
					</div>
				) : hunt.base_odds != null ? (
					<OddsCurve hunt={hunt} />
				) : null}
			</div>
		</div>
	);
}
