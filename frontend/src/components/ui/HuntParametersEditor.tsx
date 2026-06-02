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
			{formulaType === "pla_research" && (
				<>
					<div className="t-label" style={{ marginBottom: 6 }}>
						Research
					</div>
					<div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
						<label style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}>
							<input
								type="checkbox"
								checked={huntParams.research_level >= 10}
								onChange={(e) =>
									setHuntParams({ ...huntParams, research_level: e.target.checked ? 10 : 0 })
								}
							/>{" "}
							Research Lv.10
						</label>
						<label style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}>
							<input
								type="checkbox"
								checked={huntParams.dex_perfect === true}
								onChange={(e) =>
									setHuntParams({ ...huntParams, dex_perfect: e.target.checked })
								}
							/>{" "}
							Perfect research
						</label>
					</div>
					<div className="t-label" style={{ marginBottom: 6, marginTop: 10 }}>
						Outbreak
					</div>
					<div style={{ display: "flex", gap: 12 }}>
						<label style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}>
							<input
								type="radio"
								name="pla_outbreak"
								checked={!huntParams.mass_outbreak && !huntParams.massive_outbreak}
								onChange={() =>
									setHuntParams({ ...huntParams, mass_outbreak: false, massive_outbreak: false })
								}
							/>{" "}
							None
						</label>
						<label style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}>
							<input
								type="radio"
								name="pla_outbreak"
								checked={huntParams.mass_outbreak === true}
								onChange={() =>
									setHuntParams({ ...huntParams, mass_outbreak: true, massive_outbreak: false })
								}
							/>{" "}
							Mass Outbreak
						</label>
						<label style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 4 }}>
							<input
								type="radio"
								name="pla_outbreak"
								checked={huntParams.massive_outbreak === true}
								onChange={() =>
									setHuntParams({ ...huntParams, massive_outbreak: true, mass_outbreak: false })
								}
							/>{" "}
							Massive Mass Outbreak
						</label>
					</div>
				</>
			)}
			{formulaType === "ultra_wormhole" && (
				<div style={{ display: "flex", gap: 16 }}>
					<div>
						<div className="t-label" style={{ marginBottom: 6 }}>
							Ring Type (rarity)
						</div>
						<select
							className="input"
							style={{ padding: "4px 8px" }}
							value={huntParams.wormhole_ring_type || 4}
							onChange={(e) =>
								setHuntParams({ ...huntParams, wormhole_ring_type: parseInt(e.target.value, 10) || 4 })
							}
						>
							<option value={1}>1 ring</option>
							<option value={2}>2 rings</option>
							<option value={3}>3 rings</option>
							<option value={4}>4 rings</option>
						</select>
					</div>
					<div>
						<div className="t-label" style={{ marginBottom: 6 }}>
							Distance (light-years)
						</div>
						<input
							type="number"
							min={0}
							max={9999}
							className="input"
							style={{ width: 90, padding: "4px 8px" }}
							value={huntParams.wormhole_distance_ly || 0}
							onChange={(e) =>
								setHuntParams({ ...huntParams, wormhole_distance_ly: parseInt(e.target.value, 10) || 0 })
							}
						/>
					</div>
				</div>
			)}
		</div>
	);
}
