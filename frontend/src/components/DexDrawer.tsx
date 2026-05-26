import type React from "react";
import { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";
import { useNotification } from "../context/NotificationContext";
import type { PokemonRouteResponse, PokemonRoute } from "../types/models";

interface Pokemon {
	id: number;
	name: string;
}

interface Props {
	pokemon: Pokemon;
	caught: boolean;
	onClose: () => void;
	onCaughtChange: (pokemonId: number, caught: boolean) => void;
	onStartHunt: (route: PokemonRoute, pokemon: Pokemon) => void;
}

const DexDrawer: React.FC<Props> = ({ pokemon, caught, onClose, onCaughtChange, onStartHunt }) => {
	const { token } = useAuth();
	const { showError } = useNotification();
	const [data, setData] = useState<PokemonRouteResponse | null>(null);
	const [loading, setLoading] = useState(true);
	const [error, setError] = useState(false);

	useEffect(() => {
		let active = true;
		setLoading(true);
		setError(false);
		fetch(`http://localhost:8080/api/pokemon/${pokemon.id}/route`, { headers: { Authorization: `Bearer ${token}` } })
			.then((r) => (r.ok ? r.json() : Promise.reject()))
			.then((d: PokemonRouteResponse) => active && setData(d))
			.catch(() => active && setError(true))
			.finally(() => active && setLoading(false));
		return () => { active = false; };
	}, [pokemon.id, token]);

	const markCaught = async () => {
		onCaughtChange(pokemon.id, true);
		try {
			const res = await fetch("http://localhost:8080/api/hunts/manual", {
				method: "POST",
				headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
				body: JSON.stringify({ pokemon_id: pokemon.id }),
			});
			if (!res.ok) throw new Error();
		} catch {
			onCaughtChange(pokemon.id, false);
			showError("Failed to mark as caught.");
		}
	};

	const removeCaught = async () => {
		onCaughtChange(pokemon.id, false);
		try {
			const res = await fetch(`http://localhost:8080/api/hunts/manual/${pokemon.id}`, {
				method: "DELETE",
				headers: { Authorization: `Bearer ${token}` },
			});
			if (!res.ok) throw new Error();
		} catch {
			onCaughtChange(pokemon.id, true);
			showError("Failed to remove from dex.");
		}
	};

	const direct = data?.routes.filter((r) => r.kind === "direct") ?? [];
	const evolve = data?.routes.filter((r) => r.kind === "evolve") ?? [];

	return (
		<div className="scrim" onClick={onClose}>
			<div className="drawer" onClick={(e) => e.stopPropagation()} style={{ width: 360, padding: 0 }}>
				<div className="dex-drawer-head">
					<img src={`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${caught ? "shiny/" : ""}${pokemon.id}.png`} alt={pokemon.name} width={60} height={60} />
					<div>
						<div className="dex-drawer-name">{pokemon.name}</div>
						<div className="dex-drawer-dex">#{pokemon.id}</div>
						<span className={`dex-badge ${caught ? "b-caught" : (data?.status ?? "")}`}>
							{caught ? "✓ Caught" : data?.status === "locked_everywhere" ? "🔒 Shiny-locked" : data?.status === "not_in_your_games" ? "🚫 Not in your games" : "● Missing"}
						</span>
					</div>
				</div>
				<div style={{ padding: 16 }}>
					{loading && <div className="t-mono">Loading routes…</div>}
					{error && <div className="t-mono">Couldn't load routes — you can still mark it caught.</div>}
					{!loading && !error && data && (
						<>
							{data.status === "available" && direct.length === 0 && evolve.length === 0 && (
								<div className="t-mono" style={{ marginBottom: 12 }}>Available in your games, but no hunt method recorded yet.</div>
							)}
							{direct.length > 0 && <RouteSection label="Routes in your games" routes={direct} onStart={(r) => onStartHunt(r, pokemon)} />}
							{evolve.length > 0 && <RouteSection label="Hunt a pre-evolution" routes={evolve} onStart={(r) => onStartHunt(r, pokemon)} />}
							{data.status === "locked_everywhere" && <div className="t-mono">Shiny-locked in every game it appears in. Obtain it by trading or transferring from Pokémon HOME.</div>}
							{data.status === "not_in_your_games" && <div className="t-mono">Not available in any game you own. Add a game to your library, or trade for it.</div>}
						</>
					)}
					<div style={{ marginTop: 16 }}>
						{caught ? (
							<button className="btn danger" style={{ width: "100%" }} onClick={removeCaught}>Remove from dex</button>
						) : (
							<button className="btn ghost" style={{ width: "100%" }} onClick={markCaught}>Mark as caught</button>
						)}
					</div>
				</div>
			</div>
		</div>
	);
};

const RouteSection: React.FC<{ label: string; routes: PokemonRoute[]; onStart: (r: PokemonRoute) => void }> = ({ label, routes, onStart }) => (
	<div style={{ marginBottom: 14 }}>
		<div className="t-label" style={{ marginBottom: 8 }}>{label}</div>
		{routes.map((r, i) => (
			<div key={`${r.kind}-${r.game_id}-${r.method_name}-${i}`} className="dex-route">
				<div>
					<div className="dex-route-name">{r.method_name}</div>
					<div className="dex-route-game">{r.evolve_from ? `${r.evolve_from.name} · ${r.game_title}` : r.game_title}</div>
					{r.evolve_from && <div className="dex-route-evo">↳ then evolve</div>}
				</div>
				<div style={{ textAlign: "right" }}>
					<div className="dex-route-odds">1 / {r.odds.toLocaleString()}</div>
					<div className="dex-route-eta">~{r.eta_hours.toFixed(1)} h</div>
					<button className="dex-route-start" onClick={() => onStart(r)}>▸ Start</button>
				</div>
			</div>
		))}
	</div>
);

export default DexDrawer;
