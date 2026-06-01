import { useEffect, useState } from "react";
import { shinyCharmAvailable } from "../utils/games";
import { calcCumulativeOdds, calculateOdds } from "../utils/odds";
import { API_BASE } from "../config";

interface Game {
	id: number;
	title: string;
}

interface MethodItem {
	id: number;
	method_name: string;
	base_rolls: number;
	charm_rolls: number;
	avg_time_seconds: number;
	formula_type?: string;
	game_title?: string;
}

interface OddsResult {
	fraction: string;
	percentage: string;
	expected_encounters: number;
	eta_hours: number;
	cumulative_percentage: string;
}

function fmtMethodName(name: string) {
	return name.replace(/-/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

const getBaseOdds = (gameTitle: string) => {
	const lower = gameTitle.toLowerCase();
	if (
		lower.includes("red/blue") ||
		lower.includes("gold/silver") ||
		lower.includes("ruby/sapphire") ||
		lower.includes("firered") ||
		lower.includes("diamond/pearl") ||
		lower.includes("heartgold") ||
		lower.includes("black/white") ||
		lower.includes("black 2")
	) {
		return 8192;
	}
	return 4096;
};

export default function OddsCalculator() {
	const [games, setGames] = useState<Game[]>([]);
	const [gameId, setGameId] = useState<number | "">("");
	const [methods, setMethods] = useState<MethodItem[]>([]);
	const [huntMethodId, setHuntMethodId] = useState<number | "">("");
	const [shinyCharm, setShinyCharm] = useState(false);
	const [encounters, setEncounters] = useState<number>(0);
	const [odds, setOdds] = useState<OddsResult | null>(null);

	useEffect(() => {
		fetch(`${API_BASE}/api/games`)
			.then((r) => r.json())
			.then(setGames)
			.catch(() => {});
	}, []);

	useEffect(() => {
		if (!gameId) {
			setMethods([]);
			setHuntMethodId("");
			setOdds(null);
			return;
		}
		fetch(`${API_BASE}/api/methods?game_id=${gameId}`)
			.then((r) => r.json())
			.then((data: MethodItem[]) => setMethods(data ?? []))
			.catch(() => {});
		setHuntMethodId("");
		setOdds(null);
	}, [gameId]);

	const selectedMethod = methods.find((m) => m.id === huntMethodId);

	// Gate the Shiny Charm: only apply it for games where it actually exists.
	const charmAllowed = shinyCharmAvailable(gameId === "" ? null : gameId);
	const effectiveCharm = shinyCharm && charmAllowed;

	useEffect(() => {
		if (!selectedMethod) return;

		let defaultEncounters = 0;
		if (selectedMethod.formula_type === "radar_chain_gen4") {
			defaultEncounters = 40;
		} else if (selectedMethod.formula_type === "catch_combo_lgpe") {
			defaultEncounters = 31;
		} else if (selectedMethod.formula_type === "outbreak_defeats_sv") {
			defaultEncounters = 60;
		} else if (selectedMethod.formula_type === "chain_fishing_gen6") {
			defaultEncounters = 20;
		} else {
			const baseOdds = getBaseOdds(selectedMethod.game_title || "");
			const rolls =
				selectedMethod.base_rolls +
				(effectiveCharm ? selectedMethod.charm_rolls : 0);
			defaultEncounters = Math.floor(baseOdds / Math.max(1, rolls));
		}
		setEncounters(defaultEncounters);
	}, [selectedMethod, effectiveCharm]);

	useEffect(() => {
		if (!selectedMethod) {
			setOdds(null);
			return;
		}

		const baseOdds = getBaseOdds(selectedMethod.game_title || "");
		const { rolls, denominator } = calculateOdds(
			selectedMethod.formula_type,
			encounters,
			effectiveCharm,
			baseOdds,
			selectedMethod.base_rolls,
			selectedMethod.charm_rolls,
		);

		const expectedEncounters = denominator;
		const etaHours =
			(expectedEncounters * selectedMethod.avg_time_seconds) / 3600;
		const percentage = ((rolls / baseOdds) * 100).toFixed(4) + "%";

		const cumProb = calcCumulativeOdds(
			encounters,
			baseOdds,
			rolls,
			selectedMethod.formula_type,
			effectiveCharm,
			selectedMethod.base_rolls,
			selectedMethod.charm_rolls,
		);
		const cumPercentage = (cumProb * 100).toFixed(2) + "%";

		setOdds({
			fraction: `1/${denominator}`,
			percentage,
			expected_encounters: expectedEncounters,
			eta_hours: Math.round(etaHours * 10) / 10,
			cumulative_percentage: cumPercentage,
		});
	}, [selectedMethod, effectiveCharm, encounters]);

	return (
		<div className="page">
			<div className="page-head">
				<div>
					<div className="sub">Workspace · Tools</div>
					<h1>Odds Calculator</h1>
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 11,
							color: "var(--ink-3)",
							marginTop: 8,
							letterSpacing: "0.04em",
						}}
					>
						Estimate shiny odds and hunt duration for any method
					</div>
				</div>
			</div>

			<div className="calc-layout">
				<div
					className="card"
					style={{ display: "flex", flexDirection: "column", gap: 18 }}
				>
					<div className="field">
						<label>Game</label>
						<select
							className="input"
							value={gameId}
							onChange={(e) =>
								setGameId(e.target.value ? Number(e.target.value) : "")
							}
						>
							<option value="">Select a game…</option>
							{games.map((g) => (
								<option key={g.id} value={g.id}>
									{g.title}
								</option>
							))}
						</select>
					</div>

					<div className="field">
						<label>Encounter Method</label>
						{gameId === "" ? (
							<div
								className="input"
								style={{ color: "var(--ink-4)", cursor: "default" }}
							>
								Select a game first
							</div>
						) : methods.length === 0 ? (
							<div
								className="input"
								style={{ color: "var(--ink-4)", cursor: "default" }}
							>
								No methods available for this game
							</div>
						) : (
							<select
								className="input"
								value={huntMethodId}
								onChange={(e) =>
									setHuntMethodId(e.target.value ? Number(e.target.value) : "")
								}
							>
								<option value="">Select a method…</option>
								{methods.map((m) => (
									<option key={m.id} value={m.id}>
										{fmtMethodName(m.method_name)}
									</option>
								))}
							</select>
						)}
					</div>

					<label
						title={!charmAllowed ? "Shiny Charm doesn't exist in this game" : undefined}
						style={{
							display: "flex",
							alignItems: "center",
							gap: 10,
							cursor: charmAllowed ? "pointer" : "not-allowed",
							opacity: charmAllowed ? 1 : 0.4,
						}}
					>
						<input
							type="checkbox"
							checked={shinyCharm}
							disabled={!charmAllowed}
							onChange={(e) => setShinyCharm(e.target.checked)}
							style={{ accentColor: "var(--gold)", width: 15, height: 15, cursor: charmAllowed ? "pointer" : "not-allowed" }}
						/>
						<span style={{ fontSize: 13 }}>Shiny Charm</span>
						{effectiveCharm && selectedMethod && selectedMethod.charm_rolls > 0 && (
							<span className="charm-pill">
								+{selectedMethod.charm_rolls} rolls
							</span>
						)}
					</label>

					{selectedMethod && (
						<div
							className="field"
							style={{
								marginTop: 6,
								borderTop: "1px solid var(--line-1)",
								paddingTop: 14,
							}}
						>
							<label
								style={{
									display: "flex",
									justifyContent: "space-between",
									alignItems: "center",
								}}
							>
								<span style={{ fontSize: 13, fontWeight: 500 }}>
									{selectedMethod.formula_type === "radar_chain_gen4" &&
										"Radar Chain Length"}
									{selectedMethod.formula_type === "catch_combo_lgpe" &&
										"Catch Combo Size"}
									{selectedMethod.formula_type === "outbreak_defeats_sv" &&
										"Outbreak Defeats"}
									{selectedMethod.formula_type === "chain_fishing_gen6" &&
										"Chain Hooks"}
									{(!selectedMethod.formula_type ||
										selectedMethod.formula_type === "static") &&
										"Target Encounters"}
								</span>
								<span
									className="t-mono"
									style={{ color: "var(--gold)", fontWeight: 600 }}
								>
									{encounters}
								</span>
							</label>
							<div
								style={{
									display: "flex",
									alignItems: "center",
									gap: 12,
									marginTop: 6,
								}}
							>
								<input
									type="range"
									min={
										!selectedMethod.formula_type ||
										selectedMethod.formula_type === "static"
											? 1
											: 0
									}
									max={
										selectedMethod.formula_type === "radar_chain_gen4"
											? 40
											: selectedMethod.formula_type === "catch_combo_lgpe"
												? 100
												: selectedMethod.formula_type === "outbreak_defeats_sv"
													? 100
													: selectedMethod.formula_type === "chain_fishing_gen6"
														? 20
														: 20000
									}
									value={encounters}
									onChange={(e) => setEncounters(Number(e.target.value))}
									style={{
										flex: 1,
										accentColor: "var(--gold)",
										cursor: "pointer",
									}}
								/>
								<input
									type="number"
									className="input"
									min={
										!selectedMethod.formula_type ||
										selectedMethod.formula_type === "static"
											? 1
											: 0
									}
									value={encounters}
									onChange={(e) =>
										setEncounters(Math.max(0, Number(e.target.value)))
									}
									style={{
										width: 80,
										textAlign: "center",
										padding: "4px 8px",
										fontSize: 13,
									}}
								/>
							</div>
						</div>
					)}
				</div>

				<div>
					{odds ? (
						<div
							className="card"
							style={{ display: "flex", flexDirection: "column", gap: 0 }}
						>
							<div
								style={{
									fontFamily: "var(--font-mono)",
									fontSize: 10,
									letterSpacing: "0.12em",
									textTransform: "uppercase",
									color: "var(--ink-3)",
									marginBottom: 18,
								}}
							>
								Results
							</div>
							<div
								className="stat-row"
								style={{
									gridTemplateColumns: "repeat(2, 1fr)",
									marginBottom: 0,
								}}
							>
								<div className="stat-tile">
									<div className="t-label">Odds</div>
									<div className="v" style={{ fontSize: 22 }}>
										{odds.fraction}
									</div>
								</div>
								<div className="stat-tile">
									<div className="t-label">Probability</div>
									<div className="v" style={{ fontSize: 22 }}>
										{odds.percentage}
									</div>
								</div>
								<div className="stat-tile">
									<div className="t-label">Expected encounters</div>
									<div className="v" style={{ fontSize: 22 }}>
										{odds.expected_encounters.toLocaleString()}
									</div>
								</div>
								<div
									className="stat-tile"
									style={{
										borderColor: "var(--gold-line)",
										background: "var(--gold-soft)",
									}}
								>
									<div className="t-label" style={{ color: "var(--gold)" }}>
										ETA (estimate)
									</div>
									<div
										className="v"
										style={{ fontSize: 22, color: "var(--gold)" }}
									>
										~{odds.eta_hours}
										<span className="unit">h</span>
									</div>
								</div>
								<div
									className="stat-tile"
									style={{
										gridColumn: "span 2",
										borderColor: "var(--blue-line)",
										background: "var(--blue-soft)",
									}}
								>
									<div className="t-label" style={{ color: "var(--blue)" }}>
										Cumulative Probability
									</div>
									<div
										className="v"
										style={{ fontSize: 22, color: "var(--blue)" }}
									>
										{odds.cumulative_percentage}
									</div>
								</div>
							</div>
						</div>
					) : (
						<div
							className="card empty"
							style={{ minHeight: 160, display: "grid", placeItems: "center" }}
						>
							Select a game and method to see odds
						</div>
					)}
				</div>
			</div>
		</div>
	);
}
