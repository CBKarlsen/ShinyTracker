import type React from "react";
import { useCallback, useEffect, useRef, useState } from "react";
import { SparkSm, IcPlus } from "../../components/ui/icons";
import { TimerDisplay, type TimerStatus } from "../../components/ui/TimerDisplay";
import { OddsCurve } from "./OddsCurve";
import { getShowdownGif } from "../../utils/pokemon";
import { calculateOdds, defaultParamsFor } from "../../utils/odds";
import { HuntParametersEditor } from "../../components/ui/HuntParametersEditor";
import { ConfirmDialog } from "../../components/ui/ConfirmDialog";
import { useAuth } from "../../context/AuthContext";
import { useNotification } from "../../context/NotificationContext";
import type { Hunt } from "../../types/models";
import { API_BASE } from "../../config";
import { authedFetch, SessionExpiredError } from "../../utils/authedFetch";
import { playFoundItChime, isSoundEnabled, setSoundEnabled } from "../../utils/sound";

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
	onUpdate,
}: {
	hunt: Hunt;
	onIncrement: (id: string, e: React.MouseEvent) => void;
	onComplete: (id: string) => void;
	onPhase: (hunt: Hunt) => void;
	onUpdate?: (hunt: Hunt) => void;
}) {
	const { token, logout } = useAuth();
	const { showError } = useNotification();
	const [showParams, setShowParams] = useState(false);
	const [huntParams, setHuntParams] = useState<Record<string, any>>(
		(hunt.hunt_parameters as Record<string, any>) || {}
	);
	const [savingParams, setSavingParams] = useState(false);
	const [confirmComplete, setConfirmComplete] = useState(false);
	const [soundOn, setSoundOn] = useState<boolean>(isSoundEnabled);

	// Sync local state when prop updates
	useEffect(() => {
		setHuntParams((hunt.hunt_parameters as Record<string, any>) || {});
	}, [hunt.hunt_parameters]);

	const handleSessionExpired = useCallback(() => {
		logout();
		showError("Your session expired — please sign in again.");
	}, [logout, showError]);

	const handleSaveParams = async () => {
		setSavingParams(true);
		try {
			const res = await authedFetch(
				`${API_BASE}/api/hunts/${hunt.id}`,
				token,
				{
					method: "PATCH",
					headers: { "Content-Type": "application/json" },
					body: JSON.stringify({
						encounter_count: hunt.encounter_count,
						status: hunt.status,
						hunt_parameters: huntParams,
					}),
				},
				handleSessionExpired,
			);
			if (res.ok) {
				const updatedHunt = await res.json();
				if (onUpdate) onUpdate(updatedHunt);
				setShowParams(false);
			}
		} catch (err) {
			if (err instanceof SessionExpiredError) return;
			console.error("Failed to update parameters", err);
		} finally {
			setSavingParams(false);
		}
	};
	// Resolve params: prefer stored values, fall back to formula defaults so
	// hunts created before fix-1 (empty hunt_parameters) still show correct odds.
	const storedParams = (hunt.hunt_parameters as Record<string, any>) || {};
	const resolvedHuntParams = Object.keys(storedParams).length > 0
		? storedParams
		: defaultParamsFor(hunt.formula_type);

	const { denominator: expected } = calculateOdds(
		hunt.formula_type,
		hunt.encounter_count,
		hunt.has_shiny_charm || false,
		hunt.base_odds || 4096,
		hunt.base_rolls || 1,
		hunt.charm_rolls || 0,
		resolvedHuntParams
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
				hunt.charm_rolls || 0,
				resolvedHuntParams
			);
			currentNotShiny *= (1 - (1 / Math.max(1, denominator)));
		}
		cumP = 1 - currentNotShiny;
	}

	const btnRef = useRef<HTMLButtonElement>(null);
	const [bumping, setBumping] = useState(false);

	// Smart timer — session start is persisted to localStorage so a reload
	// restores elapsed session time rather than resetting to 0.
	const sessionKey = `session_start_${hunt.id}`;
	const pausedKey = `session_paused_${hunt.id}`;

	const [manualPaused, setManualPaused] = useState<boolean>(() => {
		return localStorage.getItem(pausedKey) === "1";
	});

	const [sessionSec, setSessionSec] = useState<number>(() => {
		const stored = localStorage.getItem(sessionKey);
		if (!stored) return 0;
		const startTs = parseInt(stored, 10);
		if (Number.isNaN(startTs)) return 0;
		return Math.floor((Date.now() - startTs) / 1000);
	});

	// Stamp session start on first mount if not already set and not paused.
	useEffect(() => {
		if (!localStorage.getItem(sessionKey) && !manualPaused) {
			localStorage.setItem(sessionKey, String(Date.now() - sessionSec * 1000));
		}
	// eslint-disable-next-line react-hooks/exhaustive-deps
	}, []);

	const [lastPing, setLastPing] = useState(Date.now());
	const idleMs = Math.max(45, Math.min(180, (hunt.avg_time_seconds || 8) * 6)) * 1000;

	useEffect(() => {
		const id = setInterval(() => {
			if (manualPaused) return;
			if (Date.now() - lastPing > idleMs) return;
			setSessionSec((s) => {
				const next = s + 1;
				// Keep the stored start timestamp in sync with elapsed seconds so
				// on the next reload the restored value is always consistent.
				const startTs = Date.now() - next * 1000;
				localStorage.setItem(sessionKey, String(startTs));
				return next;
			});
		}, 1000);
		return () => clearInterval(id);
	}, [manualPaused, lastPing, idleMs, sessionKey]);

	const timerStatus: TimerStatus =
		manualPaused ? "paused" : Date.now() - lastPing > idleMs ? "idle" : "live";

	const totalSeconds = hunt.total_time_seconds + sessionSec;

	// Pace: enc/hr over total time INCLUDING the live session, so it stays accurate
	// while hunting (not frozen until the next server commit). -1 = sentinel for "—".
	const pacePerHour: number | null = (() => {
		if (totalSeconds < 60) return -1;
		return Math.round(hunt.encounter_count / (totalSeconds / 3600));
	})();

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

	const clearSessionStorage = () => {
		localStorage.removeItem(sessionKey);
		localStorage.removeItem(pausedKey);
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
									onClick={() => setShowParams(!showParams)}
								>
									Edit Method Parameters
								</button>
								{showParams && (
									<div style={{ marginTop: 8, background: 'var(--bg-card)', padding: 12, borderRadius: 8, border: '1px solid var(--line-1)' }}>
										<HuntParametersEditor 
											formulaType={hunt.formula_type} 
											huntParams={huntParams} 
											setHuntParams={setHuntParams} 
											inline={true} 
										/>
										<div style={{ marginTop: 12, display: 'flex', gap: 8 }}>
											<button 
												className="btn gold" 
												style={{ fontSize: 11, padding: '4px 12px' }}
												onClick={handleSaveParams}
												disabled={savingParams}
											>
												{savingParams ? 'Saving...' : 'Save Parameters'}
											</button>
											<button 
												className="btn ghost" 
												style={{ fontSize: 11, padding: '4px 12px' }}
												onClick={() => {
													setHuntParams((hunt.hunt_parameters as Record<string, any>) || {});
													setShowParams(false);
												}}
												disabled={savingParams}
											>
												Cancel
											</button>
										</div>
									</div>
								)}
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
						pacePerHour={pacePerHour}
						onToggle={() => {
							setManualPaused((p) => {
								const next = !p;
								if (next) {
									// Pausing: remember paused state, remove start stamp
									localStorage.setItem(pausedKey, "1");
									localStorage.removeItem(sessionKey);
								} else {
									// Resuming: stamp a new start from current elapsed
									localStorage.removeItem(pausedKey);
									localStorage.setItem(sessionKey, String(Date.now() - sessionSec * 1000));
								}
								return next;
							});
						}}
						onReset={() => {
							setSessionSec(0);
							localStorage.removeItem(sessionKey);
							if (!manualPaused) {
								localStorage.setItem(sessionKey, String(Date.now()));
							}
						}}
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
					<button className="btn gold" onClick={() => setConfirmComplete(true)}>
						<SparkSm size={9} /> Found it!
					</button>
					<button
						className="btn"
						title={soundOn ? "Mute found-it chime" : "Unmute found-it chime"}
						onClick={() => {
							const next = !soundOn;
							setSoundOn(next);
							setSoundEnabled(next);
						}}
						style={{ padding: "0 8px", minWidth: 32, color: soundOn ? "var(--ink-2)" : "var(--ink-4)" }}
					>
						{soundOn ? (
							<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
								<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
								<path d="M15.54 8.46a5 5 0 0 1 0 7.07" />
								<path d="M19.07 4.93a10 10 0 0 1 0 14.14" />
							</svg>
						) : (
							<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
								<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5" />
								<line x1="23" y1="9" x2="17" y2="15" />
								<line x1="17" y1="9" x2="23" y2="15" />
							</svg>
						)}
					</button>
				</div>
			</div>

			<div className="hero-right">
				<div className="hero-sprite">
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

			<ConfirmDialog
				open={confirmComplete}
				title="Mark as found?"
				message={`Mark ${hunt.pokemon_name} as found? This will complete the hunt.`}
				confirmLabel="Yes, found it!"
				onConfirm={() => {
					setConfirmComplete(false);
					clearSessionStorage();
					playFoundItChime();
					onComplete(hunt.id);
				}}
				onCancel={() => setConfirmComplete(false)}
			/>
		</div>
	);
}
