import type React from "react";
import { useAuth } from "../context/AuthContext";
import { useNotification } from "../context/NotificationContext";
import { API_BASE } from "../config";
import type { Pokemon, PokemonRoute } from "../types/models";
import { usePokemonRoute } from "../features/routes/usePokemonRoute";
import RouteList from "../features/routes/RouteList";

interface Props {
	pokemon: Pokemon;
	caught: boolean;
	onClose: () => void;
	onCaughtChange: (pokemonId: number, caught: boolean) => void;
	onStartHunt: (pokemon: Pokemon, route: PokemonRoute) => void;
}

const DexDrawer: React.FC<Props> = ({ pokemon, caught, onClose, onCaughtChange, onStartHunt }) => {
	const { token } = useAuth();
	const { showError } = useNotification();
	const { status, routes, loading, error } = usePokemonRoute(pokemon.id);

	const markCaught = async () => {
		onCaughtChange(pokemon.id, true);
		try {
			const res = await fetch(`${API_BASE}/api/hunts/manual`, {
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
			const res = await fetch(`${API_BASE}/api/hunts/manual/${pokemon.id}`, {
				method: "DELETE",
				headers: { Authorization: `Bearer ${token}` },
			});
			if (!res.ok) throw new Error();
		} catch {
			onCaughtChange(pokemon.id, true);
			showError("Failed to remove from dex.");
		}
	};

	return (
		<div className="scrim" onClick={onClose}>
			<div className="drawer" onClick={(e) => e.stopPropagation()} style={{ width: 360, padding: 0 }}>
				<div className="dex-drawer-head">
					<img src={`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${caught ? "shiny/" : ""}${pokemon.id}.png`} alt={pokemon.name} width={60} height={60} />
					<div>
						<div className="dex-drawer-name">{pokemon.name}</div>
						<div className="dex-drawer-dex">#{pokemon.id}</div>
						<span className={`dex-badge ${caught ? "b-caught" : (status ?? "")}`}>
							{caught ? "✓ Caught" : status === "locked_everywhere" ? "🔒 Shiny-locked" : status === "not_in_your_games" ? "🚫 Not in your games" : "● Missing"}
						</span>
					</div>
				</div>
				<div style={{ padding: 16 }}>
					{loading && <div className="t-mono">Loading routes…</div>}
					{error && <div className="t-mono">Couldn't load routes — you can still mark it caught.</div>}
					{!loading && !error && status === "available" && routes.length === 0 && (
						<div className="t-mono" style={{ marginBottom: 12 }}>
							Available in your games, but no hunt method recorded yet.
						</div>
					)}
					{!loading && !error && routes.length > 0 && (
						<RouteList routes={routes} onRouteClick={(route) => onStartHunt(pokemon, route)} />
					)}
					{!loading && !error && status === "locked_everywhere" && <div className="t-mono">Shiny-locked in every game it appears in. Obtain it by trading or transferring from Pokémon HOME.</div>}
					{!loading && !error && status === "not_in_your_games" && <div className="t-mono">Not available in any game you own. Add a game to your library, or trade for it.</div>}
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

export default DexDrawer;
