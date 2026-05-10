import type React from "react";
import { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";

export interface HuntDetail {
	id: string;
	user_id: string;
	hunt_method_id: number;
	encounter_count: number;
	phase_count: number;
	status: string;
	hunt_parameters: unknown;
	created_at: string;
	updated_at: string;
	pokemon_id: number;
	pokemon_name: string;
	method_name: string | null;
	game_title: string | null;
	total_time_seconds: number;
}

const SparkSm = ({ size = 9, color }: { size?: number; color?: string }) => (
	<svg viewBox="0 0 12 12" width={size} height={size} aria-hidden>
		<path d="M6 0 L7 5 L12 6 L7 7 L6 12 L5 7 L0 6 L5 5 Z" fill={color || "currentColor"} />
	</svg>
);

function fmtNum(n: number) {
	return n.toLocaleString("en-US");
}

function fmtHM(s: number) {
	const h = Math.floor(s / 3600);
	const m = Math.floor((s % 3600) / 60);
	if (h > 0) return `${h}h ${m}m`;
	return `${m}m`;
}

const HistoricHunts: React.FC = () => {
	const { token } = useAuth();
	const [hunts, setHunts] = useState<HuntDetail[]>([]);
	const [loading, setLoading] = useState(true);

	useEffect(() => {
		const fetchHunts = async () => {
			try {
				const res = await fetch("http://localhost:8080/api/hunts", {
					headers: { Authorization: `Bearer ${token}` },
				});
				if (res.ok) {
					const data = (await res.json()) || [];
					setHunts(data.filter((h: HuntDetail) => h.status === "completed"));
				}
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
			<div className="page" style={{ color: "var(--ink-3)", fontFamily: "var(--font-mono)", fontSize: 12 }}>
				Loading…
			</div>
		);
	}

	const total = hunts.reduce((s, h) => s + h.encounter_count, 0);
	const totalTime = hunts.reduce((s, h) => s + h.total_time_seconds, 0);

	return (
		<div className="page">
			<div className="page-head">
				<div>
					<div className="sub">Workspace · Trophy Room</div>
					<h1>Historic Hunts</h1>
					{hunts.length > 0 && (
						<div
							style={{
								fontFamily: "var(--font-mono)",
								fontSize: 11,
								color: "var(--ink-3)",
								marginTop: 8,
								letterSpacing: "0.04em",
							}}
						>
							{hunts.length} shinies caught · {fmtNum(total)} encounters · {fmtHM(totalTime)} total
						</div>
					)}
				</div>
			</div>

			{hunts.length === 0 ? (
				<div className="card" style={{ padding: 48, textAlign: "center" }}>
					<div style={{ color: "var(--ink-3)", fontFamily: "var(--font-mono)", fontSize: 12, letterSpacing: "0.06em" }}>
						No completed hunts yet. Keep hunting!
					</div>
				</div>
			) : (
				<div className="card flush">
					<div className="card-head">
						<h3>All-time catches</h3>
						<div className="right">
							<span className="t-label">{hunts.length} total</span>
						</div>
					</div>
					<div className="timeline">
						{hunts.map((h) => {
							const completedDate = new Date(h.updated_at);
							return (
								<div className="tl-row" key={h.id}>
									<div className="date">
										<b>
											{completedDate.toLocaleDateString("en-US", {
												month: "short",
												day: "numeric",
											})}
										</b>
										{completedDate.getFullYear()}
									</div>
									<div className="sprite-wrap">
										<img
											src={`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/${h.pokemon_id}.png`}
											alt={h.pokemon_name}
										/>
									</div>
									<div>
										<div className="nm">{h.pokemon_name}</div>
										<div className="meta">
											{h.game_title || "Manual"} · {h.method_name || "—"}
											{h.phase_count > 0
												? ` · ${h.phase_count} phase${h.phase_count > 1 ? "s" : ""}`
												: ""}
										</div>
									</div>
									<div style={{ display: "flex", alignItems: "center", gap: 6 }}>
										<SparkSm size={9} color="var(--gold)" />
										<span
											style={{
												fontFamily: "var(--font-mono)",
												fontSize: 11,
												color: "var(--gold)",
												letterSpacing: "0.04em",
											}}
										>
											SHINY · {h.method_name?.split(" ")[0] || "Manual"}
										</span>
									</div>
									<div className="num">
										{fmtNum(h.encounter_count)}
										<small>encounters</small>
									</div>
									<div className="num">
										{fmtHM(h.total_time_seconds)}
										<small>hunted</small>
									</div>
								</div>
							);
						})}
					</div>
				</div>
			)}
		</div>
	);
};

export default HistoricHunts;
