import type React from "react";
import { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";
import type { HuntDetail } from "./HistoricHunts";

interface Pokemon {
	id: number;
	name: string;
}

const GEN_RANGES: [number, number, number][] = [
	[1, 1, 151],
	[2, 152, 251],
	[3, 252, 386],
	[4, 387, 493],
	[5, 494, 649],
	[6, 650, 721],
	[7, 722, 809],
	[8, 810, 905],
	[9, 906, 1025],
];
const ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"];

const Collection: React.FC = () => {
	const { token } = useAuth();
	const [pokemon, setPokemon] = useState<Pokemon[]>([]);
	const [caughtIds, setCaughtIds] = useState<Set<number>>(new Set());
	const [loading, setLoading] = useState(true);
	const [filter, setFilter] = useState<"all" | "owned" | "missing">("all");
	const [removeTarget, setRemoveTarget] = useState<number | null>(null);

	useEffect(() => {
		const fetchData = async () => {
			try {
				const [pokeRes, huntsRes] = await Promise.all([
					fetch("http://localhost:8080/api/pokemon?limit=all"),
					fetch("http://localhost:8080/api/hunts", {
						headers: { Authorization: `Bearer ${token}` },
					}),
				]);
				if (pokeRes.ok && huntsRes.ok) {
					const pokeData: Pokemon[] = (await pokeRes.json()) || [];
					const huntsData: HuntDetail[] = (await huntsRes.json()) || [];
					setPokemon(pokeData);
					const caught = new Set<number>();
					for (const h of huntsData) {
						if (h.status === "completed") caught.add(h.pokemon_id);
					}
					setCaughtIds(caught);
				}
			} catch (err) {
				console.error(err);
			} finally {
				setLoading(false);
			}
		};
		fetchData();
	}, [token]);

	const handleToggle = async (pokemonId: number, isCaught: boolean) => {
		if (isCaught) {
			setRemoveTarget(pokemonId);
			return;
		}
		const prev = new Set(caughtIds);
		const next = new Set(caughtIds);
		next.add(pokemonId);
		setCaughtIds(next);
		try {
			const res = await fetch("http://localhost:8080/api/hunts/manual", {
				method: "POST",
				headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
				body: JSON.stringify({ pokemon_id: pokemonId }),
			});
			if (!res.ok) throw new Error();
		} catch {
			setCaughtIds(prev);
		}
	};

	const confirmRemove = async () => {
		if (removeTarget === null) return;
		const pid = removeTarget;
		setRemoveTarget(null);
		const prev = new Set(caughtIds);
		const next = new Set(caughtIds);
		next.delete(pid);
		setCaughtIds(next);
		try {
			const res = await fetch(`http://localhost:8080/api/hunts/manual/${pid}`, {
				method: "DELETE",
				headers: { Authorization: `Bearer ${token}` },
			});
			if (!res.ok) throw new Error();
		} catch {
			setCaughtIds(prev);
		}
	};

	if (loading) {
		return (
			<div className="page" style={{ color: "var(--ink-3)", fontFamily: "var(--font-mono)", fontSize: 12 }}>
				Loading Pokédex…
			</div>
		);
	}

	const total = pokemon.length || 1025;
	const caughtCount = caughtIds.size;

	return (
		<div className="page">
			<div className="page-head">
				<div>
					<div className="sub">Workspace · Collection</div>
					<h1>Shiny Living Dex</h1>
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 11,
							color: "var(--ink-3)",
							marginTop: 8,
							letterSpacing: "0.04em",
						}}
					>
						{caughtCount} of {total} shinies · {((caughtCount / total) * 100).toFixed(1)}% complete
					</div>
				</div>
				<div className="ctas">
					<div
						style={{
							display: "flex",
							gap: 6,
							background: "var(--bg-2)",
							border: "1px solid var(--line-1)",
							borderRadius: 8,
							padding: 3,
						}}
					>
						{(["all", "owned", "missing"] as const).map((f) => (
							<button
								key={f}
								onClick={() => setFilter(f)}
								className="btn ghost"
								style={{
									padding: "6px 12px",
									fontSize: 11.5,
									textTransform: "capitalize",
									background: filter === f ? "var(--bg-3)" : "transparent",
									color: filter === f ? "var(--ink-1)" : "var(--ink-3)",
									boxShadow: filter === f ? "inset 0 0 0 1px var(--line-2)" : "none",
								}}
							>
								{f}
							</button>
						))}
					</div>
				</div>
			</div>

			{/* Completion bar */}
			<div className="card" style={{ marginBottom: 20, padding: 18 }}>
				<div
					style={{
						display: "flex",
						alignItems: "center",
						justifyContent: "space-between",
						marginBottom: 10,
					}}
				>
					<div className="t-label">Completion progress</div>
					<div className="t-mono" style={{ fontSize: 12, color: "var(--gold)" }}>
						{caughtCount} / {total}
					</div>
				</div>
				<div style={{ height: 6, background: "var(--bg-3)", borderRadius: 99, overflow: "hidden" }}>
					<div
						style={{
							height: "100%",
							width: `${(caughtCount / total) * 100}%`,
							background: "linear-gradient(90deg, var(--gold), #FFE08A)",
							borderRadius: 99,
						}}
					/>
				</div>
				<div
					style={{
						display: "flex",
						justifyContent: "space-between",
						marginTop: 10,
						fontFamily: "var(--font-mono)",
						fontSize: 10.5,
						color: "var(--ink-3)",
						letterSpacing: "0.04em",
					}}
				>
					{GEN_RANGES.map(([gen, lo, hi]) => {
						const count = Array.from(caughtIds).filter((id) => id >= lo && id <= hi).length;
						return (
							<div key={gen} style={{ textAlign: "center" }}>
								<div>Gen {ROMAN[gen]}</div>
								<div style={{ color: count > 0 ? "var(--gold)" : "var(--ink-4)", marginTop: 2 }}>
									{count}/{hi - lo + 1}
								</div>
							</div>
						);
					})}
				</div>
			</div>

			{/* Grid by generation */}
			{GEN_RANGES.map(([gen, lo, hi]) => {
				const cellsInGen = pokemon
					.filter((p) => p.id >= lo && p.id <= hi)
					.filter((p) => {
						const caught = caughtIds.has(p.id);
						if (filter === "owned") return caught;
						if (filter === "missing") return !caught;
						return true;
					});
				if (cellsInGen.length === 0) return null;
				const caughtInGen = Array.from(caughtIds).filter((id) => id >= lo && id <= hi).length;
				return (
					<div key={gen}>
						<div className="gen-head">
							<span className="lbl">Generation {ROMAN[gen]}</span>
							<span className="line" />
							<span className="count">
								<b>{caughtInGen}</b> / {hi - lo + 1}
							</span>
						</div>
						<div className="dex-grid">
							{cellsInGen.map((p) => {
								const caught = caughtIds.has(p.id);
								return (
									<div
										key={p.id}
										className={`dex-cell ${caught ? "caught" : "uncaught"}`}
										onClick={() => handleToggle(p.id, caught)}
										title={p.name}
									>
										<img
											src={`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${caught ? "shiny/" : ""}${p.id}.png`}
											alt={p.name}
											loading="lazy"
										/>
									</div>
								);
							})}
						</div>
					</div>
				);
			})}

			{/* Remove confirmation */}
			{removeTarget !== null && (
				<div className="scrim" onClick={() => setRemoveTarget(null)}>
					<div
						className="drawer"
						onClick={(e) => e.stopPropagation()}
						style={{ width: 380, padding: 28 }}
					>
						<div style={{ fontFamily: "var(--font-display)", fontSize: 18, fontWeight: 600, marginBottom: 12 }}>
							Remove shiny?
						</div>
						<div style={{ color: "var(--ink-3)", fontSize: 13, marginBottom: 24 }}>
							This will delete the completed hunt record for this Pokémon.
						</div>
						<div style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}>
							<button className="btn ghost" onClick={() => setRemoveTarget(null)}>
								Cancel
							</button>
							<button className="btn danger" onClick={confirmRemove}>
								Remove
							</button>
						</div>
					</div>
				</div>
			)}
		</div>
	);
};

export default Collection;
