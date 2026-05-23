import { useEffect, useState } from "react";
import { useAuth } from "../../context/AuthContext";

interface GameRow {
	id: number;
	title: string;
	generation: number;
	base_odds: number;
	supports_breeding: boolean;
}

const API = "http://localhost:8080";
function authHeaders(token: string) {
	return {
		Authorization: `Bearer ${token}`,
		"Content-Type": "application/json",
	};
}

export default function AdminGames() {
	const { token } = useAuth();
	const [games, setGames] = useState<GameRow[]>([]);
	const [editId, setEditId] = useState<number | null>(null);
	const [editData, setEditData] = useState<Partial<GameRow>>({});
	const [adding, setAdding] = useState(false);
	const [newRow, setNewRow] = useState({
		title: "",
		generation: "1",
		base_odds: "4096",
		supports_breeding: false,
	});
	const [error, setError] = useState("");

	useEffect(() => {
		fetch(`${API}/api/admin/games`, { headers: authHeaders(token!) })
			.then((r) => r.json())
			.then((d) => setGames(d ?? []))
			.catch(() => {});
	}, [token]);

	const saveEdit = async (id: number) => {
		const res = await fetch(`${API}/api/admin/games/${id}`, {
			method: "PUT",
			headers: authHeaders(token!),
			body: JSON.stringify(editData),
		});
		if (!res.ok) {
			setError("Failed to update game");
			return;
		}
		setGames((prev) =>
			prev.map((g) => (g.id === id ? ({ ...g, ...editData } as GameRow) : g)),
		);
		setEditId(null);
		setEditData({});
	};

	const deleteGame = async (id: number) => {
		if (!confirm("Delete this game?")) return;
		const res = await fetch(`${API}/api/admin/games/${id}`, {
			method: "DELETE",
			headers: authHeaders(token!),
		});
		if (!res.ok) {
			const t = await res.text();
			setError(t);
			return;
		}
		setGames((prev) => prev.filter((g) => g.id !== id));
	};

	const addGame = async () => {
		if (!newRow.title) {
			setError("Title is required");
			return;
		}
		const body = {
			title: newRow.title,
			generation: Number(newRow.generation),
			base_odds: Number(newRow.base_odds),
			supports_breeding: newRow.supports_breeding,
		};
		const res = await fetch(`${API}/api/admin/games`, {
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
		setGames((prev) => [...prev, { ...body, id }]);
		setAdding(false);
		setNewRow({
			title: "",
			generation: "1",
			base_odds: "4096",
			supports_breeding: false,
		});
	};

	return (
		<div>
			{error && (
				<div className="admin-error" onClick={() => setError("")}>
					{error} ✕
				</div>
			)}

			<div
				style={{
					display: "flex",
					justifyContent: "flex-end",
					marginBottom: 12,
				}}
			>
				<button
					className="btn primary"
					onClick={() => {
						setAdding(true);
						setError("");
					}}
				>
					+ Add Game
				</button>
			</div>

			<div className="card flush">
				{adding && (
					<div className="admin-add-row">
						<input
							className="input"
							placeholder="Title"
							value={newRow.title}
							onChange={(e) =>
								setNewRow((p) => ({ ...p, title: e.target.value }))
							}
							style={{ flex: 2 }}
						/>
						<input
							className="input"
							type="number"
							placeholder="Generation"
							value={newRow.generation}
							onChange={(e) =>
								setNewRow((p) => ({ ...p, generation: e.target.value }))
							}
							style={{ width: 100 }}
						/>
						<input
							className="input"
							type="number"
							placeholder="Base odds"
							value={newRow.base_odds}
							onChange={(e) =>
								setNewRow((p) => ({ ...p, base_odds: e.target.value }))
							}
							style={{ width: 100 }}
						/>
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
								checked={newRow.supports_breeding}
								onChange={(e) =>
									setNewRow((p) => ({
										...p,
										supports_breeding: e.target.checked,
									}))
								}
								style={{ accentColor: "var(--gold)" }}
							/>
							Breeding
						</label>
						<button className="btn primary" onClick={addGame}>
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
							<th>Title</th>
							<th>Gen</th>
							<th>Base odds</th>
							<th>Breeding</th>
							<th />
						</tr>
					</thead>
					<tbody>
						{games.map((g) => (
							<tr key={g.id}>
								{editId === g.id ? (
									<>
										<td>
											<input
												className="input"
												style={{ padding: "4px 6px", fontSize: 12 }}
												value={editData.title ?? g.title}
												onChange={(e) =>
													setEditData((p) => ({ ...p, title: e.target.value }))
												}
											/>
										</td>
										<td>
											<input
												className="input"
												type="number"
												style={{ padding: "4px 6px", fontSize: 12, width: 60 }}
												value={editData.generation ?? g.generation}
												onChange={(e) =>
													setEditData((p) => ({
														...p,
														generation: Number(e.target.value),
													}))
												}
											/>
										</td>
										<td>
											<input
												className="input"
												type="number"
												style={{ padding: "4px 6px", fontSize: 12, width: 80 }}
												value={editData.base_odds ?? g.base_odds}
												onChange={(e) =>
													setEditData((p) => ({
														...p,
														base_odds: Number(e.target.value),
													}))
												}
											/>
										</td>
										<td>
											<input
												type="checkbox"
												checked={
													editData.supports_breeding ?? g.supports_breeding
												}
												onChange={(e) =>
													setEditData((p) => ({
														...p,
														supports_breeding: e.target.checked,
													}))
												}
												style={{ accentColor: "var(--gold)" }}
											/>
										</td>
										<td style={{ display: "flex", gap: 6 }}>
											<button
												className="btn primary"
												style={{ padding: "4px 10px", fontSize: 12 }}
												onClick={() => saveEdit(g.id)}
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
										<td className="method-name">{g.title}</td>
										<td className="t-mono">Gen {g.generation}</td>
										<td className="t-mono">1/{g.base_odds}</td>
										<td>{g.supports_breeding ? "✓" : "—"}</td>
										<td style={{ display: "flex", gap: 6 }}>
											<button
												className="btn ghost"
												style={{ padding: "4px 10px", fontSize: 12 }}
												onClick={() => {
													setEditId(g.id);
													setEditData({ ...g });
												}}
											>
												Edit
											</button>
											<button
												className="btn danger"
												style={{ padding: "4px 10px", fontSize: 12 }}
												onClick={() => deleteGame(g.id)}
											>
												Delete
											</button>
										</td>
									</>
								)}
							</tr>
						))}
						{games.length === 0 && (
							<tr>
								<td
									colSpan={5}
									className="empty"
									style={{ padding: "20px 16px" }}
								>
									No games yet
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	);
}
