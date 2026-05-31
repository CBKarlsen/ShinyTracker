import type React from "react";
import { useCallback, useEffect, useRef, useState } from "react";
import { API_BASE } from "../config";
import { useAuth } from "../context/AuthContext";
import { HeroHunt } from "../features/dashboard/HeroHunt";
import { HuntRow } from "../features/dashboard/HuntRow";
import { PhaseModal } from "../features/dashboard/PhaseModal";
import type { Hunt } from "../types/models";
import { authedFetch, SessionExpiredError } from "../utils/authedFetch";
import { EmptyState } from "./ui/EmptyState";
import { ErrorBanner } from "./ui/ErrorBanner";
import { IcPlus, SparkSm } from "./ui/icons";
import { Stat } from "./ui/Stat";

function fmtNum(n: number) {
	return n.toLocaleString("en-US");
}

function fmtHM(s: number) {
	const h = Math.floor(s / 3600);
	const m = Math.floor((s % 3600) / 60);
	if (h > 0) return `${h}h ${m}m`;
	return `${m}m`;
}

// ── Dashboard ─────────────────────────────────────────────────────────────────

interface Props {
	onNewHunt: () => void;
	onHuntCountChange: (n: number) => void;
}

const Dashboard: React.FC<Props> = ({ onNewHunt, onHuntCountChange }) => {
	const { token, logout } = useAuth();
	const [hunts, setHunts] = useState<Hunt[]>([]);
	const [loading, setLoading] = useState(true);
	const [localCounts, setLocalCounts] = useState<Record<string, number>>({});
	const committedRef = useRef<Record<string, number>>({});
	const timers = useRef<Record<string, ReturnType<typeof setTimeout>>>({});
	const [pinnedId, setPinnedId] = useState<string | null>(null);
	const [phaseHunt, setPhaseHunt] = useState<Hunt | null>(null);
	const [errorMsg, setErrorMsg] = useState<string | null>(null);

	const handleSessionExpired = useCallback(() => {
		logout();
		setErrorMsg("Your session expired — please sign in again.");
	}, [logout]);

	const fetchHunts = async () => {
		try {
			const res = await authedFetch(`${API_BASE}/api/hunts`, token, {}, handleSessionExpired);
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
			if (err instanceof SessionExpiredError) return;
			console.error(err);
		} finally {
			setLoading(false);
		}
	};

	useEffect(() => {
		fetchHunts();
	}, [token]);

	// Heartbeat: flush current encounter counts every 60s so total_time_seconds
	// stays accurate and counts survive a refresh even between +1 clicks.
	useEffect(() => {
		const id = setInterval(async () => {
			const active = Object.entries(localCounts);
			if (active.length === 0) return;
			await Promise.allSettled(
				active.map(([huntId, count]) => {
					const hunt = hunts.find((h) => h.id === huntId);
					if (!hunt) return Promise.resolve();
					return authedFetch(
						`${API_BASE}/api/hunts/${huntId}`,
						token,
						{
							method: "PATCH",
							headers: { "Content-Type": "application/json" },
							body: JSON.stringify({ encounter_count: count, status: hunt.status }),
						},
						handleSessionExpired,
					).then((res) => {
						if (res.ok) committedRef.current[huntId] = count;
					}).catch((err) => {
						if (err instanceof SessionExpiredError) return;
						console.error(err);
					});
				}),
			);
		}, 60_000);
		return () => clearInterval(id);
	}, [localCounts, hunts, token, handleSessionExpired]);

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
				const res = await authedFetch(
					`${API_BASE}/api/hunts/${id}`,
					token,
					{
						method: "PATCH",
						headers: { "Content-Type": "application/json" },
						body: JSON.stringify({ encounter_count: newCount, status: hunt.status }),
					},
					handleSessionExpired,
				);
				if (res.ok) {
					committedRef.current[id] = newCount;
					setHunts((prev) => prev.map((h) => (h.id === id ? { ...h, encounter_count: newCount } : h)));
				} else {
					setLocalCounts((prev) => ({ ...prev, [id]: committedRef.current[id] ?? 0 }));
					setErrorMsg("Sync failed — clicks weren't saved.");
				}
			} catch (err) {
				if (err instanceof SessionExpiredError) return;
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
			const res = await authedFetch(
				`${API_BASE}/api/hunts/${id}`,
				token,
				{
					method: "PATCH",
					headers: { "Content-Type": "application/json" },
					body: JSON.stringify({ encounter_count: currentCount, status: "completed" }),
				},
				handleSessionExpired,
			);
			if (res.ok) {
				setHunts((prev) => prev.filter((h) => h.id !== id));
				onHuntCountChange(hunts.length - 1);
				if (pinnedId === id) setPinnedId(null);
			}
		} catch (err) {
			if (err instanceof SessionExpiredError) return;
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
				<EmptyState
					icon={<SparkSm size={28} />}
					title="Start your first hunt"
					description="Pick a Pokémon, choose a method, and we'll track odds, encounters and ETA. Hit SPACE to count."
					action={
						<button className="btn gold" onClick={onNewHunt}>
							<IcPlus /> New hunt
						</button>
					}
				/>
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

			<ErrorBanner message={errorMsg || ""} onDismiss={() => setErrorMsg(null)} />

			<HeroHunt
				key={primary.id}
				hunt={primaryWithCount}
				onIncrement={handleIncrement}
				onComplete={handleComplete}
				onPhase={setPhaseHunt}
				onUpdate={(updated) => setHunts((prev) => prev.map((h) => (h.id === updated.id ? { ...h, ...updated } : h)))}
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

		</div>
	);
};

export default Dashboard;
