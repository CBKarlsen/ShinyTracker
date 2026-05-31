import { useEffect, useRef, useState } from "react";
import { useAuth } from "../../context/AuthContext";
import { API_BASE } from "../../config";

interface Pokemon {
	id: number;
	name: string;
	sprite_url: string;
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
	formula_type: string;
}

const API = API_BASE;

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
	const [editId, setEditId] = useState<number | null>(null);
	const [editData, setEditData] = useState<Partial<HuntMethodRow>>({});
	const [error, setError] = useState("");
	const searchRef = useRef<ReturnType<typeof setTimeout> | null>(null);

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
					</div>

					<div
						className="t-label"
						style={{ padding: "0 16px 10px", color: "var(--ink-3)" }}
					>
						Read-only view of this Pokémon's derived availability. Editing or
						deleting a row changes the global method definition (applies to every
						Pokémon and game).
					</div>

					<table className="method-table">
						<thead>
							<tr>
								<th>Game</th>
								<th>Method</th>
								<th>Base</th>
								<th>Charm</th>
								<th>Time (s)</th>
								<th>Formula</th>
								<th />
							</tr>
						</thead>
						<tbody>
							{huntMethods.map((enc) => (
								<tr key={enc.id}>
									{editId === enc.id ? (
										<>
											{/* Game is derived from availability, not stored on the
											    global method, so it is not editable here. */}
											<td>{enc.game_title}</td>
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
										colSpan={7}
										className="empty"
										style={{ padding: "20px 16px" }}
									>
										No methods available for this Pokémon
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
