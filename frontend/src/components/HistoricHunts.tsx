import type React from "react";
import { useCallback, useEffect, useState } from "react";
import { API_BASE } from "../config";
import { useAuth } from "../context/AuthContext";
import { useNotification } from "../context/NotificationContext";
import { authedFetch, SessionExpiredError } from "../utils/authedFetch";
import { getSpriteUrl } from "../utils/pokemon";
import { SparkSm } from "./ui/icons";

export interface HuntDetail {
	id: string;
	user_id: string;
	hunt_method_id: number;
	encounter_count: number;
	phase_count: number;
	status: string;
	acquisition_type: string;
	hunt_parameters: unknown;
	created_at: string;
	updated_at: string;
	pokemon_id: number;
	pokemon_name: string;
	/** The species' shiny sprite. Optional: older servers don't send it. */
	shiny_sprite_url?: string;
	method_name: string | null;
	game_title: string | null;
	total_time_seconds: number;
}

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
	const { token, logout } = useAuth();
	const { showError } = useNotification();
	const [hunts, setHunts] = useState<HuntDetail[]>([]);
	const [loading, setLoading] = useState(true);

	const handleSessionExpired = useCallback(() => {
		logout();
		showError("Your session expired — please sign in again.");
	}, [logout, showError]);

	useEffect(() => {
		const fetchHunts = async () => {
			try {
				const res = await authedFetch(
					`${API_BASE}/api/hunts`,
					token,
					{},
					handleSessionExpired,
				);
				if (res.ok) {
					const data = (await res.json()) || [];
					// Manual overrides (collection-only "mark as caught") are not real
					// hunts — exclude them from the hunt history. They still count
					// toward the Collection living-dex (which keys on any completed hunt).
					setHunts(
						data.filter(
							(h: HuntDetail) =>
								h.status === "completed" &&
								h.acquisition_type !== "MANUAL_OVERRIDE",
						),
					);
				}
			} catch (err) {
				if (err instanceof SessionExpiredError) return;
				console.error(err);
			} finally {
				setLoading(false);
			}
		};
		fetchHunts();
	}, [token, handleSessionExpired]);

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
							{hunts.length} shinies caught · {fmtNum(total)} encounters ·{" "}
							{fmtHM(totalTime)} total
						</div>
					)}
				</div>
			</div>

			{hunts.length === 0 ? (
				<div className="card" style={{ padding: 48, textAlign: "center" }}>
					<div
						style={{
							color: "var(--ink-3)",
							fontFamily: "var(--font-mono)",
							fontSize: 12,
							letterSpacing: "0.06em",
						}}
					>
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
											src={getSpriteUrl(h.pokemon_id, true, h.shiny_sprite_url)}
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
									<div
										style={{ display: "flex", alignItems: "center", gap: 6 }}
									>
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
										{h.acquisition_type === "PHASE" && (
											<span className="phase-pill">Phase</span>
										)}
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
