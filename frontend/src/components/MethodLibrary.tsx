import { useEffect, useState } from "react";

interface Game {
	id: number;
	title: string;
}

interface MethodRow {
	id: number;
	game_id: number;
	game_title: string;
	method_name: string;
	base_rolls: number;
	charm_rolls: number;
	avg_time_seconds: number;
	is_recommended: boolean;
	formula_type?: string;
}

function fmtMethodName(name: string) {
	return name.replace(/-/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function fmtTime(seconds: number) {
	if (seconds < 60) return `${seconds}s`;
	const m = Math.floor(seconds / 60);
	const s = seconds % 60;
	return s > 0 ? `${m}m ${s}s` : `${m}m`;
}

export default function MethodLibrary() {
	const [games, setGames] = useState<Game[]>([]);
	const [gameId, setGameId] = useState<number | "">("");
	const [methods, setMethods] = useState<MethodRow[]>([]);
	const [loading, setLoading] = useState(true);

	useEffect(() => {
		fetch("http://localhost:8080/api/games")
			.then((r) => r.json())
			.then(setGames)
			.catch(() => {});
	}, []);

	useEffect(() => {
		setLoading(true);
		const url = gameId
			? `http://localhost:8080/api/methods?game_id=${gameId}`
			: "http://localhost:8080/api/methods";
		fetch(url)
			.then((r) => r.json())
			.then((data: MethodRow[]) => setMethods(data ?? []))
			.catch(() => setMethods([]))
			.finally(() => setLoading(false));
	}, [gameId]);

	const grouped = methods.reduce<Record<string, MethodRow[]>>((acc, m) => {
		const key = m.game_title;
		if (!acc[key]) acc[key] = [];
		acc[key].push(m);
		return acc;
	}, {});

	return (
		<div className="page">
			<div className="page-head">
				<div>
					<div className="sub">Workspace · Tools</div>
					<h1>Method Library</h1>
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 11,
							color: "var(--ink-3)",
							marginTop: 8,
							letterSpacing: "0.04em",
						}}
					>
						Browse encounter methods, rolls, and timing across all games
					</div>
				</div>
				<div className="ctas">
					<select
						className="btn"
						value={gameId}
						onChange={(e) =>
							setGameId(e.target.value ? Number(e.target.value) : "")
						}
						style={{ paddingRight: 20 }}
					>
						<option value="">All games</option>
						{games.map((g) => (
							<option key={g.id} value={g.id}>
								{g.title}
							</option>
						))}
					</select>
				</div>
			</div>

			{loading ? (
				<div className="empty">Loading methods…</div>
			) : methods.length === 0 ? (
				<div className="empty">No methods found</div>
			) : gameId ? (
				<div className="card flush">
					<div className="card-head">
						<h3>{games.find((g) => g.id === gameId)?.title ?? "Methods"}</h3>
						<span
							className="right t-mono"
							style={{ fontSize: 11, color: "var(--ink-3)" }}
						>
							{methods.length} method{methods.length !== 1 ? "s" : ""}
						</span>
					</div>
					<MethodTable rows={methods} />
				</div>
			) : (
				<div style={{ display: "flex", flexDirection: "column", gap: 14 }}>
					{Object.entries(grouped).map(([gameTitle, rows]) => (
						<div key={gameTitle} className="card flush">
							<div className="card-head">
								<h3>{gameTitle}</h3>
								<span
									className="right t-mono"
									style={{ fontSize: 11, color: "var(--ink-3)" }}
								>
									{rows.length} method{rows.length !== 1 ? "s" : ""}
								</span>
							</div>
							<MethodTable rows={rows} />
						</div>
					))}
				</div>
			)}
		</div>
	);
}

function MethodTable({ rows }: { rows: MethodRow[] }) {
	return (
		<table className="method-table">
			<thead>
				<tr>
					<th>Method</th>
					<th>Base rolls</th>
					<th>Charm rolls</th>
					<th>Avg time/enc</th>
					<th />
				</tr>
			</thead>
			<tbody>
				{rows.map((m) => (
					<tr key={m.id}>
						<td className="method-name">
							<div>{fmtMethodName(m.method_name)}</div>
							{m.formula_type && m.formula_type !== "static" && (
								<div
									style={{
										fontSize: "9px",
										color: "var(--blue)",
										background: "var(--blue-soft)",
										border: "1px solid var(--blue-line)",
										padding: "1px 5px",
										borderRadius: "3px",
										display: "inline-block",
										marginTop: "4px",
										fontFamily: "var(--font-mono)",
										textTransform: "uppercase",
										letterSpacing: "0.04em",
									}}
								>
									{m.formula_type === "radar_chain_gen4" && "Gen 4 PokéRadar"}
									{m.formula_type === "catch_combo_lgpe" && "LGPE Catch Combo"}
									{m.formula_type === "outbreak_defeats_sv" && "SV Outbreak"}{" "}
									{m.formula_type === "chain_fishing_gen6" && "Gen 6 Chain Fishing"}{" "}
									scaling
								</div>
							)}
						</td>
						<td className="t-mono">{m.base_rolls}×</td>
						<td className="t-mono">
							{m.charm_rolls > 0 ? `+${m.charm_rolls}` : "—"}
						</td>
						<td className="t-mono">{fmtTime(m.avg_time_seconds)}</td>
						<td>
							{m.is_recommended && <span className="reco-badge">★ Best</span>}
						</td>
					</tr>
				))}
			</tbody>
		</table>
	);
}
