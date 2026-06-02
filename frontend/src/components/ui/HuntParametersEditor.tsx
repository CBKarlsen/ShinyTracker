import { routeNeedsParams } from "../../utils/odds";

interface Props {
	formulaType: string | null | undefined;
	huntParams: Record<string, any>;
	setHuntParams: (params: Record<string, any>) => void;
	inline?: boolean;
}

export function HuntParametersEditor({ formulaType, huntParams, setHuntParams, inline }: Props) {
	if (!formulaType || !routeNeedsParams(formulaType)) {
		return null;
	}

	return (
		<div
			style={{
				marginTop: inline ? 0 : 14,
				paddingTop: inline ? 0 : 14,
				borderTop: inline ? "none" : "1px solid var(--line-1)",
			}}
		>
			{formulaType === "outbreak_defeats_sv" && (
				<>
					<div className="t-label" style={{ marginBottom: 6 }}>
						Outbreak Defeats
					</div>
					<div style={{ display: "flex", gap: 12 }}>
						<label
							style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}
						>
							<input
								type="radio"
								name="defeated_count"
								checked={
									huntParams.defeated_count === 0 ||
									!huntParams.defeated_count
								}
								onChange={() =>
									setHuntParams({ ...huntParams, defeated_count: 0 })
								}
							/>{" "}
							0-29
						</label>
						<label
							style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}
						>
							<input
								type="radio"
								name="defeated_count"
								checked={huntParams.defeated_count === 30}
								onChange={() =>
									setHuntParams({ ...huntParams, defeated_count: 30 })
								}
							/>{" "}
							30-59
						</label>
						<label
							style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}
						>
							<input
								type="radio"
								name="defeated_count"
								checked={huntParams.defeated_count === 60}
								onChange={() =>
									setHuntParams({ ...huntParams, defeated_count: 60 })
								}
							/>{" "}
							60+
						</label>
					</div>
					<div className="t-label" style={{ marginBottom: 6, marginTop: 10 }}>
						Sparkling Power (Sandwich)
					</div>
					<select
						className="input"
						style={{ padding: "4px 8px", width: "100%" }}
						value={huntParams.sparkling_power || 0}
						onChange={(e) =>
							setHuntParams({
								...huntParams,
								sparkling_power: parseInt(e.target.value) || 0,
							})
						}
					>
						<option value={0}>0</option>
						<option value={1}>1</option>
						<option value={2}>2</option>
						<option value={3}>3</option>
					</select>
				</>
			)}
			{formulaType === "radar_chain_gen4" && (
				<>
					<div className="t-label" style={{ marginBottom: 6 }}>
						Chain Length
					</div>
					<input
						type="number"
						min={0}
						max={40}
						className="input"
						style={{ width: 80, padding: "4px 8px" }}
						value={huntParams.chain_length || 0}
						onChange={(e) =>
							setHuntParams({
								...huntParams,
								chain_length: parseInt(e.target.value) || 0,
							})
						}
					/>
				</>
			)}
			{formulaType === "sos_chain_gen7" && (
				<>
					<div className="t-label" style={{ marginBottom: 6 }}>
						SOS Chain Length
					</div>
					<input
						type="number"
						min={0}
						max={255}
						className="input"
						style={{ width: 80, padding: "4px 8px" }}
						value={huntParams.chain_length || 0}
						onChange={(e) =>
							setHuntParams({
								...huntParams,
								chain_length: parseInt(e.target.value) || 0,
							})
						}
					/>
				</>
			)}
			{formulaType === "dexnav_gen6" && (
				<div style={{ display: "flex", gap: 16 }}>
					<div>
						<div className="t-label" style={{ marginBottom: 6 }}>
							Search Level
						</div>
						<input
							type="number"
							min={0}
							max={999}
							className="input"
							style={{ width: 80, padding: "4px 8px" }}
							value={huntParams.search_level || 0}
							onChange={(e) =>
								setHuntParams({
									...huntParams,
									search_level: parseInt(e.target.value) || 0,
								})
							}
						/>
					</div>
					<div>
						<div className="t-label" style={{ marginBottom: 6 }}>
							Chain Length
						</div>
						<input
							type="number"
							min={0}
							max={100}
							className="input"
							style={{ width: 80, padding: "4px 8px" }}
							value={huntParams.chain_length || 0}
							onChange={(e) =>
								setHuntParams({
									...huntParams,
									chain_length: parseInt(e.target.value) || 0,
								})
							}
						/>
					</div>
				</div>
			)}
			{formulaType === "sandwich_power_sv" && (
				<>
					<div className="t-label" style={{ marginBottom: 6 }}>
						Sparkling Power
					</div>
					<select
						className="input"
						style={{ padding: "4px 8px", width: "100%" }}
						value={huntParams.sparkling_power || 0}
						onChange={(e) =>
							setHuntParams({
								...huntParams,
								sparkling_power: parseInt(e.target.value) || 0,
							})
						}
					>
						<option value={0}>0</option>
						<option value={1}>1</option>
						<option value={2}>2</option>
						<option value={3}>3</option>
					</select>
				</>
			)}
		</div>
	);
}
