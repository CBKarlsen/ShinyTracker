import type React from "react";
import { useEffect, useRef, useState } from "react";
import { useAuth } from "../context/AuthContext";
import { getShowdownGif } from "../utils/pokemon";

interface HuntPhase {
	id: string;
	hunt_id: string;
	pokemon_id: number;
	pokemon_name: string;
	sprite_url: string;
	encounter_count_at_phase: number;
	created_at: string;
}

interface Hunt {
	id: string;
	hunt_method_id: number | null;
	encounter_count: number;
	phase_count: number;
	phases: HuntPhase[];
	status: string;
	acquisition_type: string;
	hunt_parameters: unknown;
	created_at: string;
	updated_at: string;
	pokemon_id: number;
	pokemon_name: string;
	method_name: string | null;
	game_title: string | null;
	total_time_seconds: number;
	base_rolls: number | null;
	charm_rolls: number | null;
	avg_time_seconds: number | null;
	base_odds: number | null;
	has_shiny_charm: boolean | null;
}

interface PokemonOption {
	id: number;
	name: string;
	sprite_url: string;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

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

function computeExpected(hunt: Hunt): number | null {
	if (!hunt.base_odds || !hunt.base_rolls || !hunt.charm_rolls) return null;
	const rolls = hunt.base_rolls + (hunt.has_shiny_charm ? hunt.charm_rolls : 0);
	if (rolls <= 0) return null;
	return Math.floor(hunt.base_odds / rolls);
}

// ── SparkSm icon ─────────────────────────────────────────────────────────────

const SparkSm = ({ size = 10, color }: { size?: number; color?: string }) => (
	<svg viewBox="0 0 12 12" width={size} height={size} aria-hidden>
		<path d="M6 0 L7 5 L12 6 L7 7 L6 12 L5 7 L0 6 L5 5 Z" fill={color || "currentColor"} />
	</svg>
);

// ── Icons ─────────────────────────────────────────────────────────────────────

const IcPlay = () => (
	<svg viewBox="0 0 16 16" width="11" height="11" fill="currentColor">
		<path d="M4 3l9 5-9 5z" />
	</svg>
);
const IcPause = () => (
	<svg viewBox="0 0 16 16" width="11" height="11" fill="currentColor">
		<rect x="4" y="3" width="3" height="10" rx="0.5" />
		<rect x="9" y="3" width="3" height="10" rx="0.5" />
	</svg>
);
const IcPin = () => (
	<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round">
		<path d="M8 1.5l2.4 4.3 2.6.6-1.8 2 .4 2.6L8 9.8 4.4 11l.4-2.6L3 6.4l2.6-.6L8 1.5z" />
	</svg>
);
const IcPlus = () => (
	<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2">
		<path d="M8 3v10M3 8h10" />
	</svg>
);
const IcClose = () => (
	<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.5">
		<path d="M3 3l10 10M13 3L3 13" />
	</svg>
);

// ── Timer Display ─────────────────────────────────────────────────────────────

type TimerStatus = "live" | "idle" | "paused";

function TimerDisplay({
	sessionSec,
	status,
	onToggle,
	onReset,
}: {
	sessionSec: number;
	status: TimerStatus;
	onToggle: () => void;
	onReset: () => void;
}) {
	const m = Math.floor(sessionSec / 60);
	const s = sessionSec % 60;
	const hh = Math.floor(m / 60);
	const mm = m % 60;
	const display =
		hh > 0
			? `${hh}:${String(mm).padStart(2, "0")}:${String(s).padStart(2, "0")}`
			: `${String(mm).padStart(2, "0")}:${String(s).padStart(2, "0")}`;

	const labels: Record<TimerStatus, string> = {
		live: "recording",
		idle: "idle · auto-paused",
		paused: "paused",
	};

	return (
		<div className="timer-display">
			<div className="timer-row">
				<span className={`timer-dot timer-dot-${status}`} />
				<span className="timer-clock">{display}</span>
				<button className="timer-btn" onClick={onToggle} title={status === "paused" ? "Resume" : "Pause"}>
					{status === "paused" ? <IcPlay /> : <IcPause />}
				</button>
			</div>
			<div className="timer-meta">
				<span>session · {labels[status]}</span>
				{sessionSec > 0 && status !== "live" && (
					<button className="timer-link" onClick={onReset} title="Reset session timer">
						reset
					</button>
				)}
			</div>
		</div>
	);
}

// ── Odds Curve (SVG sparkline) ────────────────────────────────────────────────

function OddsCurve({ hunt }: { hunt: Hunt }) {
	const odds = hunt.base_odds || 4096;
	const rolls = (hunt.base_rolls || 1) + (hunt.has_shiny_charm ? hunt.charm_rolls || 0 : 0);
	const expected = Math.floor(odds / rolls);
	const max = Math.max(expected * 3, hunt.encounter_count * 1.4, 100);
	const W = 600;
	const H = 60;
	const N = 60;

	const points: [number, number][] = [];
	for (let i = 0; i <= N; i++) {
		const n = (i / N) * max;
		const p = 1 - Math.pow(1 - rolls / odds, n);
		points.push([(i / N) * W, H - p * H]);
	}
	const pathD = points.map((p, i) => `${i === 0 ? "M" : "L"} ${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(" ");
	const fillD = `${pathD} L ${W} ${H} L 0 ${H} Z`;

	const youX = Math.min((hunt.encounter_count / max) * W, W - 1);
	const youP = 1 - Math.pow(1 - rolls / odds, hunt.encounter_count);
	const youY = H - youP * H;
	const expX = (expected / max) * W;

	return (
		<div className="odds-curve">
			<div className="odds-curve-head">
				<div className="ttl">
					Cumulative probability — {(youP * 100).toFixed(1)}% of hunters caught by now
				</div>
				<div className="pct">
					1 / {odds.toLocaleString()} · {rolls} rolls
				</div>
			</div>
			<svg className="odds-curve-svg" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none">
				<defs>
					<linearGradient id="curveFill" x1="0" y1="0" x2="0" y2="1">
						<stop offset="0%" stopColor="var(--gold)" stopOpacity="0.35" />
						<stop offset="100%" stopColor="var(--gold)" stopOpacity="0" />
					</linearGradient>
				</defs>
				<path d={fillD} fill="url(#curveFill)" />
				<path d={pathD} fill="none" stroke="var(--gold)" strokeWidth="1.5" />
				<line x1={expX} y1="0" x2={expX} y2={H} stroke="var(--ink-4)" strokeWidth="1" strokeDasharray="2 3" />
				<line x1={youX} y1="0" x2={youX} y2={H} stroke="var(--ink-1)" strokeWidth="1" />
				<circle cx={youX} cy={youY} r="3" fill="var(--ink-1)" />
				<text x={expX + 4} y="11" fill="var(--ink-3)" fontSize="9" fontFamily="JetBrains Mono">
					expected · {expected.toLocaleString()}
				</text>
				<text x={youX + 4} y={Math.max(youY - 6, 14)} fill="var(--ink-1)" fontSize="9" fontFamily="JetBrains Mono">
					you · {hunt.encounter_count.toLocaleString()}
				</text>
			</svg>
		</div>
	);
}

// ── Hero Hunt ─────────────────────────────────────────────────────────────────

function HeroHunt({
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
	const expected = computeExpected(hunt);
	const isOver = expected !== null && hunt.encounter_count > expected;
	const ratio = expected ? Math.min(hunt.encounter_count / expected, 1) : 0;
	const odds = hunt.base_odds || 4096;
	const rolls = (hunt.base_rolls || 1) + (hunt.has_shiny_charm ? hunt.charm_rolls || 0 : 0);
	const cumP = 1 - Math.pow(1 - rolls / odds, hunt.encounter_count);

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
						<div className="pmeta" style={{ marginTop: 4 }}>
							<span>
								<b>{hunt.game_title || "Manual"}</b>
								{hunt.method_name ? ` · ${hunt.method_name}` : ""}
							</span>
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
							{(cumP * 100).toFixed(1)}% cumulative · {fmtHM(totalSeconds)} hunted
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
				{hunt.base_odds != null && <OddsCurve hunt={hunt} />}
			</div>
		</div>
	);
}

// ── Hunt Row ──────────────────────────────────────────────────────────────────

function HuntRow({
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
	const expected = computeExpected(hunt);
	const isOver = expected !== null && hunt.encounter_count > expected;
	const ratio = expected ? Math.min(hunt.encounter_count / expected, 1) : 0;
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
					<span className="pill">{gameShort(hunt.game_title)}</span>
					<span>{hunt.method_name || "—"}</span>
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
				<div className={`barwrap${isOver ? " over" : ""}`}>
					<span style={{ width: `${(isOver ? 1 : ratio) * 100}%` }} />
				</div>
				<div
					style={{
						fontFamily: "var(--font-mono)",
						fontSize: 10,
						color: "var(--ink-3)",
						marginTop: 4,
						letterSpacing: "0.04em",
					}}
				>
					{expected ? `${((hunt.encounter_count / expected) * 100).toFixed(0)}% of expected` : "—"}
				</div>
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

// ── Phase Modal ───────────────────────────────────────────────────────────────

function PhaseModal({ hunt, token, onClose, onSuccess }: {
	hunt: Hunt;
	token: string;
	onClose: () => void;
	onSuccess: (updated: Hunt) => void;
}) {
	const [search, setSearch] = useState("");
	const [options, setOptions] = useState<PokemonOption[]>([]);
	const [submitting, setSubmitting] = useState(false);

	useEffect(() => {
		const timer = setTimeout(async () => {
			try {
				const res = await fetch(`http://localhost:8080/api/pokemon?q=${search}`);
				if (res.ok) setOptions((await res.json()) || []);
			} catch { /* ignore */ }
		}, 300);
		return () => clearTimeout(timer);
	}, [search]);

	const handleSelect = async (pokemon: PokemonOption) => {
		setSubmitting(true);
		try {
			const res = await fetch(`http://localhost:8080/api/hunts/${hunt.id}/phases`, {
				method: "POST",
				headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
				body: JSON.stringify({ pokemon_id: pokemon.id }),
			});
			if (res.ok) {
				const updated: Hunt = await res.json();
				onSuccess(updated);
			}
		} catch { /* ignore */ }
		setSubmitting(false);
	};

	return (
		<div className="scrim" onClick={onClose}>
			<div className="drawer" onClick={(e) => e.stopPropagation()} style={{ width: 420 }}>
				<div className="drawer-head">
					<h2>Log phase</h2>
					<button className="close" onClick={onClose}>
						<IcClose />
					</button>
				</div>
				<div className="drawer-body">
					<div style={{ color: "var(--ink-3)", fontSize: 12.5, marginBottom: 16, lineHeight: 1.55 }}>
						Hunting <b style={{ color: "var(--ink-1)" }}>{hunt.pokemon_name}</b> — which shiny did you
						encounter? Your count of{" "}
						<b style={{ color: "var(--gold)" }}>{fmtNum(hunt.encounter_count)}</b> will be saved as a
						phase and reset to 0.
					</div>
					<div className="field">
						<label>Phase Pokémon</label>
						<input
							className="input"
							placeholder="Search…"
							value={search}
							onChange={(e) => setSearch(e.target.value)}
							autoFocus
						/>
					</div>
					<div className="poke-search-results">
						{options.slice(0, 8).map((p) => (
							<div
								key={p.id}
								className="row"
								onClick={() => !submitting && handleSelect(p)}
								style={{ opacity: submitting ? 0.5 : 1 }}
							>
								<img src={p.sprite_url || `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${p.id}.png`} alt={p.name} />
								<div className="nm">{p.name}</div>
								<div className="id">#{String(p.id).padStart(4, "0")}</div>
							</div>
						))}
						{options.length === 0 && search.length > 0 && (
							<div className="empty">No matches</div>
						)}
					</div>
				</div>
			</div>
		</div>
	);
}

// ── Stat tile ─────────────────────────────────────────────────────────────────

function Stat({ label, value, unit, accent }: { label: string; value: string | number; unit?: string; accent?: string }) {
	return (
		<div className="stat-tile">
			<div className="t-label">{label}</div>
			<div className="v" style={accent ? { color: accent } : undefined}>
				{value}
				{unit && <span className="unit">{unit}</span>}
			</div>
		</div>
	);
}

// ── Dashboard ─────────────────────────────────────────────────────────────────

interface Props {
	onNewHunt: () => void;
	onHuntCountChange: (n: number) => void;
}

const Dashboard: React.FC<Props> = ({ onNewHunt, onHuntCountChange }) => {
	const { token } = useAuth();
	const [hunts, setHunts] = useState<Hunt[]>([]);
	const [loading, setLoading] = useState(true);
	const [localCounts, setLocalCounts] = useState<Record<string, number>>({});
	const committedRef = useRef<Record<string, number>>({});
	const timers = useRef<Record<string, ReturnType<typeof setTimeout>>>({});
	const [pinnedId, setPinnedId] = useState<string | null>(null);
	const [phaseHunt, setPhaseHunt] = useState<Hunt | null>(null);
	const [errorMsg, setErrorMsg] = useState<string | null>(null);

	const fetchHunts = async () => {
		try {
			const res = await fetch("http://localhost:8080/api/hunts", {
				headers: { Authorization: `Bearer ${token}` },
			});
			if (res.ok) {
				const data: Hunt[] = (await res.json()) || [];
				const active = data.filter((h) => h.status === "active");
				setHunts(active);
				const initial: Record<string, number> = {};
				for (const h of active) initial[h.id] = h.encounter_count;
				setLocalCounts(initial);
				committedRef.current = { ...initial };
				onHuntCountChange(active.length);
			}
		} catch (err) {
			console.error(err);
		} finally {
			setLoading(false);
		}
	};

	useEffect(() => {
		fetchHunts();
	}, [token]);

	// SPACE key → increment primary hunt
	useEffect(() => {
		const onKey = (e: KeyboardEvent) => {
			if (e.code === "Space" && (e.target as HTMLElement).tagName !== "INPUT" && (e.target as HTMLElement).tagName !== "TEXTAREA") {
				e.preventDefault();
				const primary = hunts.find((h) => h.id === pinnedId) || hunts[0];
				if (primary) increment(primary.id);
			}
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [hunts, pinnedId]);

	const increment = (id: string) => {
		const newCount = (localCounts[id] ?? 0) + 1;
		setLocalCounts((prev) => ({ ...prev, [id]: newCount }));
		if (timers.current[id]) clearTimeout(timers.current[id]);
		timers.current[id] = setTimeout(async () => {
			try {
				const hunt = hunts.find((h) => h.id === id);
				if (!hunt) return;
				const res = await fetch(`http://localhost:8080/api/hunts/${id}`, {
					method: "PATCH",
					headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
					body: JSON.stringify({ encounter_count: newCount, status: hunt.status }),
				});
				if (res.ok) {
					committedRef.current[id] = newCount;
					setHunts((prev) => prev.map((h) => (h.id === id ? { ...h, encounter_count: newCount } : h)));
				} else {
					setLocalCounts((prev) => ({ ...prev, [id]: committedRef.current[id] ?? 0 }));
					setErrorMsg("Sync failed — clicks weren't saved.");
				}
			} catch {
				setLocalCounts((prev) => ({ ...prev, [id]: committedRef.current[id] ?? 0 }));
				setErrorMsg("Sync failed — clicks weren't saved.");
			}
		}, 1500);
	};

	const handleIncrement = (id: string) => {
		increment(id);
	};

	const handleComplete = async (id: string) => {
		if (timers.current[id]) { clearTimeout(timers.current[id]); delete timers.current[id]; }
		const currentCount = localCounts[id] ?? 0;
		try {
			const res = await fetch(`http://localhost:8080/api/hunts/${id}`, {
				method: "PATCH",
				headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
				body: JSON.stringify({ encounter_count: currentCount, status: "completed" }),
			});
			if (res.ok) {
				setHunts((prev) => prev.filter((h) => h.id !== id));
				onHuntCountChange(hunts.length - 1);
				if (pinnedId === id) setPinnedId(null);
			}
		} catch (err) {
			console.error(err);
		}
	};

	const handlePin = (id: string) => {
		setPinnedId(id);
		window.scrollTo({ top: 0, behavior: "smooth" });
	};

	const handlePhaseSuccess = (updated: Hunt) => {
		setHunts((prev) => prev.map((h) => (h.id === updated.id ? updated : h)));
		setLocalCounts((prev) => ({ ...prev, [updated.id]: 0 }));
		committedRef.current[updated.id] = 0;
		setPhaseHunt(null);
	};

	if (loading) {
		return (
			<div className="page" style={{ color: "var(--ink-3)", fontFamily: "var(--font-mono)", fontSize: 12 }}>
				Loading hunts…
			</div>
		);
	}

	if (hunts.length === 0) {
		return (
			<div className="page">
				<div className="page-head">
					<div>
						<div className="sub">Workspace · Dashboard</div>
						<h1>No active hunts</h1>
					</div>
					<div className="ctas">
						<button className="btn gold" onClick={onNewHunt}>
							<IcPlus /> Start hunting
						</button>
					</div>
				</div>
				<div className="card" style={{ padding: 60, textAlign: "center" }}>
					<div
						style={{
							display: "inline-grid",
							placeItems: "center",
							width: 64,
							height: 64,
							borderRadius: 16,
							background: "var(--bg-2)",
							border: "1px solid var(--line-1)",
							marginBottom: 16,
							color: "var(--ink-3)",
						}}
					>
						<SparkSm size={28} />
					</div>
					<div
						style={{ fontFamily: "var(--font-display)", fontSize: 22, fontWeight: 600, marginBottom: 6 }}
					>
						Start your first hunt
					</div>
					<div
						style={{
							color: "var(--ink-3)",
							maxWidth: 360,
							margin: "0 auto 18px",
							fontSize: 13,
						}}
					>
						Pick a Pokémon, choose a method, and we'll track odds, encounters and ETA. Hit SPACE to
						count.
					</div>
					<button className="btn gold" onClick={onNewHunt}>
						<IcPlus /> New hunt
					</button>
				</div>
			</div>
		);
	}

	const primary = hunts.find((h) => h.id === pinnedId) || hunts[0];
	const others = hunts.filter((h) => h.id !== primary.id);
	// Merge local counts into primary/others
	const primaryWithCount = { ...primary, encounter_count: localCounts[primary.id] ?? primary.encounter_count };
	const totalEncounters = hunts.reduce((s, h) => s + (localCounts[h.id] ?? h.encounter_count), 0);
	const totalTime = hunts.reduce((s, h) => s + h.total_time_seconds, 0);

	const today = new Date().toLocaleDateString("en-US", {
		weekday: "long",
		month: "long",
		day: "numeric",
	});

	return (
		<div className="page">
			<div className="page-head">
				<div>
					<div className="sub">Workspace · {today}</div>
					<h1>Dashboard</h1>
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 11,
							color: "var(--ink-3)",
							marginTop: 8,
							letterSpacing: "0.04em",
						}}
					>
						{hunts.length} active · {fmtNum(totalEncounters)} encounters · {fmtHM(totalTime)} hunted
					</div>
				</div>
				<div className="ctas">
					<button className="btn ghost">Filter</button>
					<button className="btn gold" onClick={onNewHunt}>
						<IcPlus /> New hunt
					</button>
				</div>
			</div>

			<HeroHunt
				key={primary.id}
				hunt={primaryWithCount}
				onIncrement={handleIncrement}
				onComplete={handleComplete}
				onPhase={setPhaseHunt}
			/>

			<div style={{ height: 22 }} />

			<div className="stat-row">
				<Stat label="Active Hunts" value={hunts.length} accent="var(--blue)" />
				<Stat label="Total Encounters" value={fmtNum(totalEncounters)} />
				<Stat label="Total Hunted" value={fmtHM(totalTime)} />
				<Stat
					label="Avg per Hunt"
					value={hunts.length > 0 ? fmtNum(Math.floor(totalEncounters / hunts.length)) : "0"}
				/>
			</div>

			{others.length > 0 && (
				<>
					<div style={{ height: 22 }} />
					<div className="card flush">
						<div className="card-head">
							<h3>Other active hunts</h3>
							<span className="t-label">{others.length} hunts</span>
							<div className="right">
								<span style={{ fontFamily: "var(--font-mono)", fontSize: 10.5, color: "var(--ink-3)" }}>
									Click row to promote to main
								</span>
							</div>
						</div>
						<div className="hunt-list">
							{others.map((h) => (
								<HuntRow
									key={h.id}
									hunt={{ ...h, encounter_count: localCounts[h.id] ?? h.encounter_count }}
									onIncrement={handleIncrement}
									onComplete={handleComplete}
									onPhase={setPhaseHunt}
									onPin={handlePin}
								/>
							))}
						</div>
					</div>
				</>
			)}

			{phaseHunt && token && (
				<PhaseModal
					hunt={phaseHunt}
					token={token}
					onClose={() => setPhaseHunt(null)}
					onSuccess={handlePhaseSuccess}
				/>
			)}

			{errorMsg && (
				<div
					style={{
						position: "fixed",
						bottom: 24,
						left: "50%",
						transform: "translateX(-50%)",
						background: "var(--red-soft)",
						border: "1px solid var(--red)",
						color: "var(--red)",
						fontFamily: "var(--font-mono)",
						fontSize: 12,
						padding: "10px 18px",
						borderRadius: 8,
						zIndex: 100,
					}}
				>
					{errorMsg}
					<button
						style={{ marginLeft: 12, color: "inherit", textDecoration: "underline", background: "none", border: "none", cursor: "pointer", fontFamily: "inherit" }}
						onClick={() => setErrorMsg(null)}
					>
						dismiss
					</button>
				</div>
			)}
		</div>
	);
};

export default Dashboard;
