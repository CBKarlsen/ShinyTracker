import type React from "react";
import { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";
import type { HuntDetail } from "./HistoricHunts";

function fmtNum(n: number) {
	return n.toLocaleString("en-US");
}

function fmtHM(s: number) {
	const h = Math.floor(s / 3600);
	const m = Math.floor((s % 3600) / 60);
	if (h > 0) return `${h}h ${m}m`;
	return `${m}m`;
}

const Stats: React.FC = () => {
	const { token } = useAuth();
	const [hunts, setHunts] = useState<HuntDetail[]>([]);
	const [loading, setLoading] = useState(true);

	useEffect(() => {
		const fetchHunts = async () => {
			try {
				const res = await fetch("http://localhost:8080/api/hunts", {
					headers: { Authorization: `Bearer ${token}` },
				});
				if (res.ok) setHunts((await res.json()) || []);
			} catch (err) {
				console.error(err);
			} finally {
				setLoading(false);
			}
		};
		fetchHunts();
	}, [token]);

	if (loading) {
		return (
			<div
				className="page"
				style={{
					color: "var(--ink-3)",
					fontFamily: "var(--font-mono)",
					fontSize: 12,
				}}
			>
				Loading stats…
			</div>
		);
	}

	const completed = hunts.filter((h) => h.status === "completed");
	const totalShinies = completed.length;
	const totalEncounters = completed.reduce((s, h) => s + h.encounter_count, 0);
	const totalTimeSeconds = completed.reduce(
		(s, h) => s + (h.total_time_seconds ?? 0),
		0,
	);
	const totalHours = Math.round(totalTimeSeconds / 3600);
	const avgPerShiny =
		totalShinies > 0 ? Math.floor(totalEncounters / totalShinies) : 0;

	const luckiest =
		completed.length > 0
			? completed.reduce(
					(min, h) => (h.encounter_count < min.encounter_count ? h : min),
					completed[0],
				)
			: null;
	const unluckiest =
		completed.length > 0
			? completed.reduce(
					(max, h) => (h.encounter_count > max.encounter_count ? h : max),
					completed[0],
				)
			: null;

	// Method breakdown
	const methodMap: Record<string, number> = {};
	for (const h of completed) {
		let m = h.method_name || "";
		if (!m && h.hunt_parameters) {
			try {
				let parsedParams: any = h.hunt_parameters;
				if (typeof h.hunt_parameters === "string") {
					parsedParams = JSON.parse(h.hunt_parameters);
				}
				if (parsedParams && typeof parsedParams === "object" && "method" in parsedParams) {
					m = String((parsedParams as { method: unknown }).method);
				}
			} catch (e) {
				console.error("Failed to parse hunt parameters", e);
			}
		}

		if (!m) {
			m = h.game_title ? "Unknown Method" : "Manual Entry";
		} else {
			m = m.replace(/-/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
		}
		methodMap[m] = (methodMap[m] || 0) + 1;
	}
	const methods = Object.entries(methodMap)
		.sort((a, b) => b[1] - a[1])
		.slice(0, 6);
	const maxMethod = methods[0]?.[1] || 1;

	// Activity chart: group completed hunts by day (last 30 days)
	const now = new Date();
	const dailyCounts: number[] = Array(30).fill(0);
	for (const h of completed) {
		const d = new Date(h.updated_at);
		const diffDays = Math.floor(
			(now.getTime() - d.getTime()) / (1000 * 60 * 60 * 24),
		);
		if (diffDays >= 0 && diffDays < 30) {
			dailyCounts[29 - diffDays] += h.encounter_count;
		}
	}
	const maxDaily = Math.max(...dailyCounts, 1);

	return (
		<div className="page">
			<div className="page-head">
				<div>
					<div className="sub">Workspace · Analytics</div>
					<h1>Stats & Records</h1>
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 11,
							color: "var(--ink-3)",
							marginTop: 8,
							letterSpacing: "0.04em",
						}}
					>
						Lifetime performance
					</div>
				</div>
			</div>

			<div className="stat-row" style={{ marginBottom: 18 }}>
				<div className="stat-tile">
					<div className="t-label">Total Shinies</div>
					<div className="v" style={{ color: "var(--gold)" }}>
						{fmtNum(totalShinies)}
					</div>
				</div>
				<div className="stat-tile">
					<div className="t-label">Total Encounters</div>
					<div className="v">{fmtNum(totalEncounters)}</div>
				</div>
				<div className="stat-tile">
					<div className="t-label">Hunt Hours</div>
					<div className="v">
						{fmtNum(totalHours)}
						<span
							className="unit"
							style={{
								fontFamily: "var(--font-display)",
								fontSize: 14,
								color: "var(--ink-3)",
								marginLeft: 4,
							}}
						>
							h
						</span>
					</div>
				</div>
				<div className="stat-tile">
					<div className="t-label">Avg per Shiny</div>
					<div className="v">{fmtNum(avgPerShiny)}</div>
				</div>
			</div>

			<div className="split-2" style={{ marginBottom: 18 }}>
				<div className="card">
					<div
						style={{
							display: "flex",
							alignItems: "baseline",
							justifyContent: "space-between",
							marginBottom: 14,
						}}
					>
						<h3
							style={{
								fontFamily: "var(--font-display)",
								fontSize: 14,
								fontWeight: 600,
								margin: 0,
							}}
						>
							Encounters · last 30 days
						</h3>
						<div
							className="t-mono"
							style={{ fontSize: 11, color: "var(--ink-3)" }}
						>
							peak {fmtNum(Math.max(...dailyCounts))}
						</div>
					</div>
					<div className="activity">
						{dailyCounts.map((v, i) => (
							<div
								key={i}
								className={`b ${v === 0 ? "zero" : ""}`}
								style={{ height: `${(v / maxDaily) * 100}%` }}
								title={`${v} encounters`}
							/>
						))}
					</div>
					<div
						style={{
							display: "flex",
							justifyContent: "space-between",
							marginTop: 10,
							fontFamily: "var(--font-mono)",
							fontSize: 10,
							color: "var(--ink-3)",
							letterSpacing: "0.06em",
						}}
					>
						<span>30 days ago</span>
						<span>today</span>
					</div>
				</div>

				<div className="card">
					<h3
						style={{
							fontFamily: "var(--font-display)",
							fontSize: 14,
							fontWeight: 600,
							margin: "0 0 14px",
						}}
					>
						Method Breakdown
					</h3>
					{methods.length === 0 ? (
						<div
							style={{
								color: "var(--ink-3)",
								fontFamily: "var(--font-mono)",
								fontSize: 12,
							}}
						>
							No completed hunts yet
						</div>
					) : (
						methods.map(([method, count]) => (
							<div
								key={method}
								style={{
									display: "flex",
									alignItems: "center",
									gap: 10,
									padding: "6px 0",
								}}
							>
								<div
									style={{
										width: 110,
										fontSize: 12.5,
										overflow: "hidden",
										textOverflow: "ellipsis",
										whiteSpace: "nowrap",
									}}
								>
									{method}
								</div>
								<div
									style={{
										flex: 1,
										height: 5,
										background: "var(--bg-3)",
										borderRadius: 99,
										overflow: "hidden",
									}}
								>
									<div
										style={{
											width: `${(count / maxMethod) * 100}%`,
											height: "100%",
											background: "var(--gold)",
											opacity: 0.85,
										}}
									/>
								</div>
								<div
									className="t-mono"
									style={{
										fontSize: 11,
										color: "var(--ink-3)",
										width: 24,
										textAlign: "right",
									}}
								>
									{count}
								</div>
							</div>
						))
					)}
				</div>
			</div>

			{completed.length > 0 && (
				<div className="card flush">
					<div className="card-head">
						<h3>Records</h3>
					</div>
					<div className="records">
						{unluckiest && (
							<div className="record-row">
								<img
									src={`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/${unluckiest.pokemon_id}.png`}
									alt={unluckiest.pokemon_name}
								/>
								<div>
									<div className="lbl">Most encounters</div>
									<div
										style={{
											fontWeight: 600,
											fontFamily: "var(--font-display)",
											textTransform: "capitalize",
										}}
									>
										{unluckiest.pokemon_name}
									</div>
								</div>
								<div className="v">{fmtNum(unluckiest.encounter_count)}</div>
							</div>
						)}
						{luckiest && (
							<div className="record-row">
								<img
									src={`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/${luckiest.pokemon_id}.png`}
									alt={luckiest.pokemon_name}
								/>
								<div>
									<div className="lbl">Luckiest catch</div>
									<div
										style={{
											fontWeight: 600,
											fontFamily: "var(--font-display)",
											textTransform: "capitalize",
										}}
									>
										{luckiest.pokemon_name}
									</div>
								</div>
								<div className="v" style={{ color: "var(--gold)" }}>
									{fmtNum(luckiest.encounter_count)} enc
								</div>
							</div>
						)}
						{completed.length > 0 && (
							<div className="record-row">
								<div
									style={{
										width: 32,
										height: 32,
										background: "var(--bg-2)",
										border: "1px solid var(--line-1)",
										borderRadius: 6,
										display: "grid",
										placeItems: "center",
									}}
								>
									<svg viewBox="0 0 12 12" width="14" height="14" aria-hidden>
										<path
											d="M6 0 L7 5 L12 6 L7 7 L6 12 L5 7 L0 6 L5 5 Z"
											fill="var(--blue)"
										/>
									</svg>
								</div>
								<div>
									<div className="lbl">Total time hunted</div>
									<div
										style={{
											fontWeight: 600,
											fontFamily: "var(--font-display)",
										}}
									>
										All hunts
									</div>
								</div>
								<div className="v">{fmtHM(totalTimeSeconds)}</div>
							</div>
						)}
					</div>
				</div>
			)}
		</div>
	);
};

export default Stats;
