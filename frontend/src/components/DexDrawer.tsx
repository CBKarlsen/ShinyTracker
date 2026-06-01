import type React from "react";
import { useEffect, useRef, useState } from "react";
import { API_BASE } from "../config";
import { useAuth } from "../context/AuthContext";
import { useNotification } from "../context/NotificationContext";
import RouteList from "../features/routes/RouteList";
import { startRouteHunt } from "../features/routes/startHunt";
import { usePokemonRoute } from "../features/routes/usePokemonRoute";
import { defaultParamsFor, routeNeedsParams } from "../utils/odds";
import type { Pokemon, PokemonRoute } from "../types/models";

interface Props {
	pokemon: Pokemon;
	caught: boolean;
	onClose: () => void;
	onCaughtChange: (pokemonId: number, caught: boolean) => void;
	onStartHunt: (pokemon: Pokemon, route: PokemonRoute) => void;
	onHuntStarted?: () => void;
}

const DexDrawer: React.FC<Props> = ({
	pokemon,
	caught,
	onClose,
	onCaughtChange,
	onStartHunt,
	onHuntStarted,
}) => {
	const { token } = useAuth();
	const { showError, showSuccess } = useNotification();
	const { status, routes, loading, error } = usePokemonRoute(pokemon.id);

	const bodyRef = useRef<HTMLDivElement>(null);
	const [hasFade, setHasFade] = useState(false);
	const [starting, setStarting] = useState(false);

	// biome-ignore lint/correctness/useExhaustiveDependencies: routes/status changes alter content height; re-run is intentional
	useEffect(() => {
		const el = bodyRef.current;
		if (!el) return;

		const check = () => {
			setHasFade(el.scrollHeight - el.scrollTop - el.clientHeight > 1);
		};

		check();
		el.addEventListener("scroll", check, { passive: true });

		const ro = new ResizeObserver(check);
		ro.observe(el);

		return () => {
			el.removeEventListener("scroll", check);
			ro.disconnect();
		};
	}, [routes, status]);

	const markCaught = async () => {
		onCaughtChange(pokemon.id, true);
		try {
			const res = await fetch(`${API_BASE}/api/hunts/manual`, {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
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

	const handleRouteClick = async (route: PokemonRoute) => {
		// Parameter routes (chain/power) need the modal's setup step.
		if (routeNeedsParams(route.formula_type)) {
			onStartHunt(pokemon, route);
			return;
		}
		// Everything else starts immediately — no modal, no reload.
		if (starting) return;
		setStarting(true);
		try {
			const res = await startRouteHunt(
				route,
				pokemon,
				defaultParamsFor(route.formula_type),
				token,
			);
			if (!res.ok)
				throw new Error((await res.text()) || "Failed to start hunt.");
			showSuccess(`Started hunt · ${route.method_name}`);
			onHuntStarted?.();
			onClose();
		} catch (err) {
			showError((err as Error).message || "Failed to start hunt.");
			setStarting(false);
		}
	};

	return (
		<div className="scrim" onClick={onClose}>
			<div
				className="drawer"
				onClick={(e) => e.stopPropagation()}
				style={{ width: 360, padding: 0 }}
			>
				<div className="dex-drawer-head">
					<img
						src={`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${caught ? "shiny/" : ""}${pokemon.id}.png`}
						alt={pokemon.name}
						width={60}
						height={60}
					/>
					<div>
						<div className="dex-drawer-name">{pokemon.name}</div>
						<div className="dex-drawer-dex">#{pokemon.id}</div>
						<span
							className={`dex-badge ${caught ? "b-caught" : (status ?? "")}`}
						>
							{caught
								? "✓ Caught"
								: status === "locked_everywhere"
									? "🔒 Shiny-locked"
									: status === "not_in_your_games"
										? "🚫 Not in your games"
										: "● Missing"}
						</span>
					</div>
				</div>
				<div
					ref={bodyRef}
					className={`dex-drawer-body${hasFade ? " has-fade" : ""}`}
				>
					{loading && <div className="t-mono">Loading routes…</div>}
					{error && (
						<div className="t-mono">
							Couldn't load routes — you can still mark it caught.
						</div>
					)}
					{!loading &&
						!error &&
						status === "available" &&
						routes.length === 0 && (
							<div className="t-mono" style={{ marginBottom: 12 }}>
								Available in your games, but no hunt method recorded yet.
							</div>
						)}
					{!loading && !error && routes.length > 0 && (
						<RouteList routes={routes} onRouteClick={handleRouteClick} />
					)}
					{!loading && !error && status === "locked_everywhere" && (
						<div className="t-mono">
							Shiny-locked in every game it appears in. Obtain it by trading or
							transferring from Pokémon HOME.
						</div>
					)}
					{!loading && !error && status === "not_in_your_games" && (
						<div className="t-mono">
							Not available in any game you own. Add a game to your library, or
							trade for it.
						</div>
					)}
				</div>
				<div className="dex-drawer-foot">
					{caught ? (
						<button
							className="btn danger"
							style={{ width: "100%" }}
							onClick={removeCaught}
						>
							Remove from dex
						</button>
					) : (
						<button
							className="btn ghost"
							style={{ width: "100%" }}
							onClick={markCaught}
						>
							Mark as caught
						</button>
					)}
				</div>
			</div>
		</div>
	);
};

export default DexDrawer;
