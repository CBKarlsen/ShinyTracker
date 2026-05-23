import { useEffect, useRef, useState } from "react";
import { useAuth } from "../../context/AuthContext";

interface Pokemon {
	id: number;
	name: string;
	sprite_url: string;
}
interface Game {
	id: number;
	title: string;
}
interface HuntMethodRow {
	id: number;
	pokemon_id: number;
	game_id: number;
	game_title: string;
	method_name: string;
	base_rolls: number;
	charm_rolls: number;
	avg_time_seconds: number;
	is_recommended: boolean;
	formula_type: string;
}
interface ImportResult {
	row_number: number;
	status: "inserted" | "skipped" | "error";
	message?: string;
}

const API = "http://localhost:8080";

function authHeaders(token: string) {
	return {
		Authorization: `Bearer ${token}`,
		"Content-Type": "application/json",
	};
}

export default function AdminEncounters() {
	const { token } = useAuth();
	const [query, setQuery] = useState("");
	const [results, setResults] = useState<Pokemon[]>([]);
	const [selected, setSelected] = useState<Pokemon | null>(null);
	const [huntMethods, setHuntMethods] = useState<HuntMethodRow[]>([]);
	const [games, setGames] = useState<Game[]>([]);
	const [editId, setEditId] = useState<number | null>(null);
	const [editData, setEditData] = useState<Partial<HuntMethodRow>>({});
	const [adding, setAdding] = useState(false);
	const [newRow, setNewRow] = useState({
		game_id: "",
		method_name: "",
		base_rolls: "1",
		charm_rolls: "0",
		avg_time_seconds: "30",
		is_recommended: false,
		formula_type: "static",
	});
	const [error, setError] = useState("");
	const [csvText, setCsvText] = useState("");
	const [importing, setImporting] = useState(false);
	const [importResults, setImportResults] = useState<ImportResult[] | null>(
		null,
	);
	const searchRef = useRef<ReturnType<typeof setTimeout> | null>(null);

	useEffect(() => {
		fetch(`${API}/api/admin/games`, { headers: authHeaders(token!) })
			.then((r) => r.json())
			.then(setGames)
			.catch(() => {});
	}, [token]);

	useEffect(() => {
		if (!query.trim()) {
			setResults([]);
			return;
		}
		if (searchRef.current) clearTimeout(searchRef.current);
		searchRef.current = setTimeout(() => {
			fetch(`${API}/api/pokemon?q=${encodeURIComponent(query)}`)
				.then((r) => r.json())
				.then((d) => setResults(d ?? []))
				.catch(() => {});
		}, 300);
	}, [query]);

	const loadEncounters = (pokemon: Pokemon) => {
		setSelected(pokemon);
		setResults([]);
		setQuery(pokemon.name);
		setAdding(false);
		setEditId(null);
		fetch(`${API}/api/admin/hunt-methods?pokemon_id=${pokemon.id}`, {
			headers: authHeaders(token!),
		})
			.then((r) => r.json())
			.then((d) => setHuntMethods(d ?? []))
			.catch(() => {});
	};

	const saveEdit = async (id: number) => {
		const res = await fetch(`${API}/api/admin/hunt-methods/${id}`, {
			method: "PUT",
			headers: authHeaders(token!),
			body: JSON.stringify(editData),
		});
		if (!res.ok) {
			setError("Failed to update");
			return;
		}
		setHuntMethods((prev) =>
			prev.map((e) =>
				e.id === id ? ({ ...e, ...editData } as HuntMethodRow) : e,
			),
		);
		setEditId(null);
		setEditData({});
	};

	const deleteEncounter = async (id: number) => {
		if (!confirm("Delete this encounter?")) return;
		const res = await fetch(`${API}/api/admin/hunt-methods/${id}`, {
			method: "DELETE",
			headers: authHeaders(token!),
		});
		if (!res.ok) {
			setError("Failed to delete");
			return;
		}
		setHuntMethods((prev) => prev.filter((e) => e.id !== id));
	};

	const addEncounter = async () => {
		if (!selected || !newRow.game_id || !newRow.method_name) {
			setError("Game and method name are required");
			return;
		}
		const body = {
			pokemon_id: selected.id,
			game_id: Number(newRow.game_id),
			method_name: newRow.method_name,
			base_rolls: Number(newRow.base_rolls),
			charm_rolls: Number(newRow.charm_rolls),
			avg_time_seconds: Number(newRow.avg_time_seconds),
			is_recommended: newRow.is_recommended,
			formula_type: newRow.formula_type,
		};
		const res = await fetch(`${API}/api/admin/hunt-methods`, {
			method: "POST",
			headers: authHeaders(token!),
			body: JSON.stringify(body),
		});
		if (!res.ok) {
			const t = await res.text();
			setError(t);
			return;
		}
		const { id } = await res.json();
		const game = games.find((g) => g.id === body.game_id);
		setHuntMethods((prev) => [
			...prev,
			{ ...body, id, game_title: game?.title ?? "" } as HuntMethodRow,
		]);
		setAdding(false);
		setNewRow({
			game_id: "",
			method_name: "",
			base_rolls: "1",
			charm_rolls: "0",
			avg_time_seconds: "30",
			is_recommended: false,
			formula_type: "static",
		});
	};

	const importCsv = async () => {
		if (!csvText.trim()) return;
		setImporting(true);
		setImportResults(null);
		try {
			const res = await fetch(`${API}/api/admin/hunt-methods/import`, {
				method: "POST",
				headers: {
					Authorization: `Bearer ${token!}`,
					"Content-Type": "text/csv",
				},
				body: csvText,
			});
			if (!res.ok) {
				const msg = await res.text();
				setError(msg || "Import failed");
			} else {
				const data: ImportResult[] = await res.json();
				setImportResults(data);
			}
		} catch {
			setError("Import request failed");
		}
		setImporting(false);
	};

	const statusColor = (s: ImportResult["status"]) => {
		if (s === "inserted") return "var(--emerald, #10b981)";
		if (s === "skipped") return "var(--ink-3)";
		return "var(--red, #ef4444)";
	};

	return (
		<div>
			{error && (
				<div className="admin-error" onClick={() => setError("")}>
					{error} ✕
				</div>
			)}

			<div className="admin-search-wrap">
				<input
					className="input"
					placeholder="Search Pokémon…"
					value={query}
					onChange={(e) => {
						setQuery(e.target.value);
						setSelected(null);
					}}
					style={{ maxWidth: 320 }}
				/>
				{results.length > 0 && (
					<div
						className="poke-search-results"
						style={{ maxWidth: 320, position: "absolute", zIndex: 10 }}
					>
						{results.slice(0, 8).map((p) => (
							<div key={p.id} className="row" onClick={() => loadEncounters(p)}>
								<img src={p.sprite_url} alt={p.name} />
								<span className="nm">{p.name}</span>
								<span className="id">#{p.id}</span>
							</div>
						))}
					</div>
				)}
			</div>

			<div className="card flush" style={{ marginTop: 24 }}>
				<div className="card-head">
					<h3>CSV Bulk Import</h3>
				</div>
				<div style={{ padding: "12px 16px" }}>
					<div
						style={{
							display: "grid",
							gridTemplateColumns: "1fr 1fr",
							gap: 16,
							marginBottom: 14,
						}}
					>
						<div>
							<div className="t-label" style={{ marginBottom: 6 }}>
								Column reference
							</div>
							<table
								style={{
									width: "100%",
									fontSize: 12,
									borderCollapse: "collapse",
								}}
							>
								<tbody>
									{[
										["pokemon_id", "Pokémon's numeric ID (see search above)"],
										["game_id", "Game ID — see table to the right"],
										["method_name", 'Free text, e.g. "Wild encounter"'],
										[
											"base_rolls",
											"Shiny rolls per encounter without Charm (usually 1)",
										],
										[
											"charm_rolls",
											"Extra rolls added by Shiny Charm (e.g. 2)",
										],
										["avg_time_seconds", "Seconds per encounter on average"],
										[
											"is_recommended",
											"true or false — marks the fastest method",
										],
										[
											"formula_type",
											"Formula: static, radar_chain_gen4, catch_combo_lgpe, outbreak_defeats_sv, chain_fishing_gen6",
										],
									].map(([col, desc]) => (
										<tr key={col}>
											<td
												style={{
													fontFamily: "var(--font-mono)",
													color: "var(--gold)",
													paddingRight: 10,
													whiteSpace: "nowrap",
													verticalAlign: "top",
													paddingBottom: 4,
												}}
											>
												{col}
											</td>
											<td
												style={{
													color: "var(--ink-3)",
													verticalAlign: "top",
													paddingBottom: 4,
												}}
											>
												{desc}
											</td>
										</tr>
									))}
								</tbody>
							</table>
						</div>
						<div>
							<div className="t-label" style={{ marginBottom: 6 }}>
								Game IDs
							</div>
							<table
								style={{
									width: "100%",
									fontSize: 12,
									borderCollapse: "collapse",
								}}
							>
								<tbody>
									{games.map((g) => (
										<tr key={g.id}>
											<td
												className="t-mono"
												style={{
													color: "var(--gold)",
													paddingRight: 10,
													paddingBottom: 3,
												}}
											>
												{g.id}
											</td>
											<td style={{ color: "var(--ink-3)", paddingBottom: 3 }}>
												{g.title}
											</td>
										</tr>
									))}
									{games.length === 0 && (
										<tr>
											<td colSpan={2} style={{ color: "var(--ink-3)" }}>
												Loading…
											</td>
										</tr>
									)}
								</tbody>
							</table>
						</div>
					</div>
					<textarea
						className="input"
						rows={6}
						placeholder={
							"pokemon_id,game_id,method_name,base_rolls,charm_rolls,avg_time_seconds,is_recommended,formula_type\n1,1,Wild encounter,1,2,15,true,static"
						}
						value={csvText}
						onChange={(e) => setCsvText(e.target.value)}
						style={{
							width: "100%",
							fontFamily: "var(--font-mono)",
							fontSize: 12,
							resize: "vertical",
							boxSizing: "border-box",
						}}
					/>
					<button
						className="btn primary"
						style={{ marginTop: 8 }}
						onClick={importCsv}
						disabled={importing || !csvText.trim()}
					>
						{importing ? "Importing…" : "Import CSV"}
					</button>
					{importResults && (
						<table className="method-table" style={{ marginTop: 16 }}>
							<thead>
								<tr>
									<th>#</th>
									<th>Status</th>
									<th>Message</th>
								</tr>
							</thead>
							<tbody>
								{importResults.map((r) => (
									<tr key={r.row_number}>
										<td className="t-mono">{r.row_number}</td>
										<td
											style={{
												color: statusColor(r.status),
												fontWeight: 600,
												fontFamily: "var(--font-mono)",
												fontSize: 12,
											}}
										>
											{r.status}
										</td>
										<td style={{ fontSize: 12, color: "var(--ink-3)" }}>
											{r.message || "—"}
										</td>
									</tr>
								))}
							</tbody>
						</table>
					)}
				</div>
			</div>

			{selected && (
				<div className="card flush" style={{ marginTop: 16 }}>
					<div className="card-head">
						<img
							src={selected.sprite_url}
							alt={selected.name}
							style={{ width: 28, height: 28, imageRendering: "pixelated" }}
						/>
						<h3 style={{ textTransform: "capitalize" }}>{selected.name}</h3>
						<span
							className="right t-mono"
							style={{ fontSize: 11, color: "var(--ink-3)" }}
						>
							{huntMethods.length} method{huntMethods.length !== 1 ? "s" : ""}
						</span>
						<button
							className="btn"
							style={{ marginLeft: 8 }}
							onClick={() => {
								setAdding(true);
								setError("");
							}}
						>
							+ Add
						</button>
					</div>

					{adding && (
						<div className="admin-add-row">
							<select
								className="input"
								value={newRow.game_id}
								onChange={(e) =>
									setNewRow((p) => ({ ...p, game_id: e.target.value }))
								}
							>
								<option value="">Game…</option>
								{games.map((g) => (
									<option key={g.id} value={g.id}>
										{g.title}
									</option>
								))}
							</select>
							<input
								className="input"
								placeholder="Method name"
								value={newRow.method_name}
								onChange={(e) =>
									setNewRow((p) => ({ ...p, method_name: e.target.value }))
								}
							/>
							<input
								className="input"
								type="number"
								placeholder="Base rolls"
								value={newRow.base_rolls}
								onChange={(e) =>
									setNewRow((p) => ({ ...p, base_rolls: e.target.value }))
								}
								style={{ width: 90 }}
							/>
							<input
								className="input"
								type="number"
								placeholder="Charm rolls"
								value={newRow.charm_rolls}
								onChange={(e) =>
									setNewRow((p) => ({ ...p, charm_rolls: e.target.value }))
								}
								style={{ width: 90 }}
							/>
							<input
								className="input"
								type="number"
								placeholder="Avg time (s)"
								value={newRow.avg_time_seconds}
								onChange={(e) =>
									setNewRow((p) => ({ ...p, avg_time_seconds: e.target.value }))
								}
								style={{ width: 100 }}
							/>
							<select
								className="input"
								value={newRow.formula_type}
								onChange={(e) =>
									setNewRow((p) => ({ ...p, formula_type: e.target.value }))
								}
								style={{ width: 150 }}
							>
								<option value="static">Static Odds</option>
								<option value="radar_chain_gen4">Gen 4 Poké Radar</option>
								<option value="catch_combo_lgpe">LGPE Catch Combo</option>
								<option value="outbreak_defeats_sv">SV Outbreak Defeats</option>
								<option value="chain_fishing_gen6">Gen 6 Chain Fishing</option>
							</select>
							<label
								style={{
									display: "flex",
									alignItems: "center",
									gap: 5,
									fontSize: 12,
									whiteSpace: "nowrap",
								}}
							>
								<input
									type="checkbox"
									checked={newRow.is_recommended}
									onChange={(e) =>
										setNewRow((p) => ({
											...p,
											is_recommended: e.target.checked,
										}))
									}
									style={{ accentColor: "var(--gold)" }}
								/>
								Best
							</label>
							<button className="btn primary" onClick={addEncounter}>
								Save
							</button>
							<button className="btn ghost" onClick={() => setAdding(false)}>
								Cancel
							</button>
						</div>
					)}

					<table className="method-table">
						<thead>
							<tr>
								<th>Game</th>
								<th>Method</th>
								<th>Base</th>
								<th>Charm</th>
								<th>Time (s)</th>
								<th>Formula</th>
								<th>Best</th>
								<th />
							</tr>
						</thead>
						<tbody>
							{huntMethods.map((enc) => (
								<tr key={enc.id}>
									{editId === enc.id ? (
										<>
											<td>
												<select
													className="input"
													style={{ padding: "4px 6px", fontSize: 12 }}
													value={editData.game_id ?? enc.game_id}
													onChange={(e) =>
														setEditData((p) => ({
															...p,
															game_id: Number(e.target.value),
														}))
													}
												>
													{games.map((g) => (
														<option key={g.id} value={g.id}>
															{g.title}
														</option>
													))}
												</select>
											</td>
											<td>
												<input
													className="input"
													style={{ padding: "4px 6px", fontSize: 12 }}
													value={editData.method_name ?? enc.method_name}
													onChange={(e) =>
														setEditData((p) => ({
															...p,
															method_name: e.target.value,
														}))
													}
												/>
											</td>
											<td>
												<input
													className="input"
													type="number"
													style={{
														padding: "4px 6px",
														fontSize: 12,
														width: 60,
													}}
													value={editData.base_rolls ?? enc.base_rolls}
													onChange={(e) =>
														setEditData((p) => ({
															...p,
															base_rolls: Number(e.target.value),
														}))
													}
												/>
											</td>
											<td>
												<input
													className="input"
													type="number"
													style={{
														padding: "4px 6px",
														fontSize: 12,
														width: 60,
													}}
													value={editData.charm_rolls ?? enc.charm_rolls}
													onChange={(e) =>
														setEditData((p) => ({
															...p,
															charm_rolls: Number(e.target.value),
														}))
													}
												/>
											</td>
											<td>
												<input
													className="input"
													type="number"
													style={{
														padding: "4px 6px",
														fontSize: 12,
														width: 80,
													}}
													value={
														editData.avg_time_seconds ?? enc.avg_time_seconds
													}
													onChange={(e) =>
														setEditData((p) => ({
															...p,
															avg_time_seconds: Number(e.target.value),
														}))
													}
												/>
											</td>
											<td>
												<select
													className="input"
													style={{ padding: "4px 6px", fontSize: 12 }}
													value={editData.formula_type ?? enc.formula_type}
													onChange={(e) =>
														setEditData((p) => ({
															...p,
															formula_type: e.target.value,
														}))
													}
												>
													<option value="static">Static</option>
													<option value="radar_chain_gen4">Gen 4 Radar</option>
													<option value="catch_combo_lgpe">Catch Combo</option>
													<option value="outbreak_defeats_sv">SV Outbreaks</option>
													<option value="chain_fishing_gen6">Gen 6 Chain Fishing</option>
												</select>
											</td>
											<td>
												<input
													type="checkbox"
													checked={
														editData.is_recommended ?? enc.is_recommended
													}
													onChange={(e) =>
														setEditData((p) => ({
															...p,
															is_recommended: e.target.checked,
														}))
													}
													style={{ accentColor: "var(--gold)" }}
												/>
											</td>
											<td style={{ display: "flex", gap: 6 }}>
												<button
													className="btn primary"
													style={{ padding: "4px 10px", fontSize: 12 }}
													onClick={() => saveEdit(enc.id)}
												>
													Save
												</button>
												<button
													className="btn ghost"
													style={{ padding: "4px 10px", fontSize: 12 }}
													onClick={() => {
														setEditId(null);
														setEditData({});
													}}
												>
													Cancel
												</button>
											</td>
										</>
									) : (
										<>
											<td>{enc.game_title}</td>
											<td className="method-name">{enc.method_name}</td>
											<td className="t-mono">{enc.base_rolls}×</td>
											<td className="t-mono">
												{enc.charm_rolls > 0 ? `+${enc.charm_rolls}` : "—"}
											</td>
											<td className="t-mono">{enc.avg_time_seconds}</td>
											<td>
												{enc.formula_type === "static" ? "Static" :
												 enc.formula_type === "radar_chain_gen4" ? "Poké Radar" :
												 enc.formula_type === "catch_combo_lgpe" ? "Catch Combo" :
												 enc.formula_type === "outbreak_defeats_sv" ? "SV Outbreak" :
												 enc.formula_type === "chain_fishing_gen6" ? "Gen 6 Chain Fishing" :
												 enc.formula_type || "Static"}
											</td>
											<td>
												{enc.is_recommended && (
													<span className="reco-badge">★</span>
												)}
											</td>
											<td style={{ display: "flex", gap: 6 }}>
												<button
													className="btn ghost"
													style={{ padding: "4px 10px", fontSize: 12 }}
													onClick={() => {
														setEditId(enc.id);
														setEditData({ ...enc });
													}}
												>
													Edit
												</button>
												<button
													className="btn danger"
													style={{ padding: "4px 10px", fontSize: 12 }}
													onClick={() => deleteEncounter(enc.id)}
												>
													Delete
												</button>
											</td>
										</>
									)}
								</tr>
							))}
							{huntMethods.length === 0 && (
								<tr>
									<td
										colSpan={8}
										className="empty"
										style={{ padding: "20px 16px" }}
									>
										No hunt methods — click + Add to create one
									</td>
								</tr>
							)}
						</tbody>
					</table>
				</div>
			)}
		</div>
	);
}
