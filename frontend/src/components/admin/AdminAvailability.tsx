import { useEffect, useRef, useState } from "react";
import { useAuth } from "../../context/AuthContext";

interface Pokemon {
	id: number;
	name: string;
	sprite_url: string;
}
interface AvailRow {
	game_id: number;
	game_title: string;
	available: boolean;
}

const API = "http://localhost:8080";
function authHeaders(token: string) {
	return {
		Authorization: `Bearer ${token}`,
		"Content-Type": "application/json",
	};
}

export default function AdminAvailability() {
	const { token } = useAuth();
	const [query, setQuery] = useState("");
	const [results, setResults] = useState<Pokemon[]>([]);
	const [selected, setSelected] = useState<Pokemon | null>(null);
	const [availability, setAvailability] = useState<AvailRow[]>([]);
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

	const loadAvailability = (pokemon: Pokemon) => {
		setSelected(pokemon);
		setResults([]);
		setQuery(pokemon.name);
		fetch(`${API}/api/admin/availability?pokemon_id=${pokemon.id}`, {
			headers: authHeaders(token!),
		})
			.then((r) => r.json())
			.then((d) => setAvailability(d ?? []))
			.catch(() => {});
	};

	const toggle = async (gameId: number, current: boolean) => {
		if (!selected) return;
		const res = await fetch(`${API}/api/admin/availability`, {
			method: "PUT",
			headers: authHeaders(token!),
			body: JSON.stringify({
				pokemon_id: selected.id,
				game_id: gameId,
				available: !current,
			}),
		});
		if (!res.ok) {
			setError("Failed to update availability");
			return;
		}
		setAvailability((prev) =>
			prev.map((a) =>
				a.game_id === gameId ? { ...a, available: !current } : a,
			),
		);
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
							<div
								key={p.id}
								className="row"
								onClick={() => loadAvailability(p)}
							>
								<img src={p.sprite_url} alt={p.name} />
								<span className="nm">{p.name}</span>
								<span className="id">#{p.id}</span>
							</div>
						))}
					</div>
				)}
			</div>

			{selected && availability.length > 0 && (
				<div
					className="card"
					style={{
						marginTop: 16,
						display: "flex",
						flexDirection: "column",
						gap: 10,
					}}
				>
					<div
						style={{
							display: "flex",
							alignItems: "center",
							gap: 10,
							marginBottom: 6,
						}}
					>
						<img
							src={selected.sprite_url}
							alt={selected.name}
							style={{ width: 32, height: 32, imageRendering: "pixelated" }}
						/>
						<span
							style={{
								fontFamily: "var(--font-display)",
								fontWeight: 600,
								textTransform: "capitalize",
							}}
						>
							{selected.name}
						</span>
						<span
							className="t-mono"
							style={{
								fontSize: 11,
								color: "var(--ink-3)",
								marginLeft: "auto",
							}}
						>
							{availability.filter((a) => a.available).length}/
							{availability.length} games
						</span>
					</div>
					<div
						style={{
							display: "grid",
							gridTemplateColumns: "repeat(auto-fill, minmax(200px, 1fr))",
							gap: 8,
						}}
					>
						{availability.map((a) => (
							<label
								key={a.game_id}
								style={{
									display: "flex",
									alignItems: "center",
									gap: 8,
									padding: "8px 12px",
									background: a.available ? "var(--blue-soft)" : "var(--bg-2)",
									border: `1px solid ${a.available ? "var(--blue-line)" : "var(--line-1)"}`,
									borderRadius: 8,
									cursor: "pointer",
									transition: "all .12s",
								}}
							>
								<input
									type="checkbox"
									checked={a.available}
									onChange={() => toggle(a.game_id, a.available)}
									style={{ accentColor: "var(--blue)", flexShrink: 0 }}
								/>
								<span style={{ fontSize: 12.5 }}>{a.game_title}</span>
							</label>
						))}
					</div>
				</div>
			)}
		</div>
	);
}
