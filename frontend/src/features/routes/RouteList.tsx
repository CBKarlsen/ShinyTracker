import type React from "react";
import type { PokemonRoute } from "../../types/models";

// Stable identity for a route, used for selection highlighting.
// Assumes (kind, game_id, method_id) is unique per route — method_id is unique
// per game, so do not weaken this to method_name.
export function routeKey(r: PokemonRoute): string {
	return `${r.kind}-${r.game_id}-${r.method_id}`;
}

interface Props {
	routes: PokemonRoute[];
	selectedKey?: string;
	onRouteClick: (route: PokemonRoute) => void;
}

const RouteList: React.FC<Props> = ({ routes, selectedKey, onRouteClick }) => {
	const direct = routes.filter((r) => r.kind === "direct");
	const evolve = routes.filter((r) => r.kind === "evolve");
	return (
		<>
			{direct.length > 0 && (
				<Section label="Routes in your games" routes={direct} selectedKey={selectedKey} onRouteClick={onRouteClick} />
			)}
			{evolve.length > 0 && (
				<Section label="Hunt a pre-evolution" routes={evolve} selectedKey={selectedKey} onRouteClick={onRouteClick} />
			)}
		</>
	);
};

const Section: React.FC<Props & { label: string }> = ({ label, routes, selectedKey, onRouteClick }) => (
	<div style={{ marginBottom: 14 }}>
		<div className="t-label" style={{ marginBottom: 8 }}>{label}</div>
		{routes.map((r) => {
			const key = routeKey(r);
			return (
				<div
					key={key}
					className={`dex-route ${selectedKey === key ? "sel" : ""}`}
					onClick={() => onRouteClick(r)}
				>
					<div>
						<div className="dex-route-name">{r.method_name}</div>
						<div className="dex-route-game">
							{r.evolve_from ? `${r.evolve_from.name} · ${r.game_title}` : r.game_title}
						</div>
						{r.evolve_from && <div className="dex-route-evo">↳ then evolve</div>}
					</div>
					<div style={{ textAlign: "right" }}>
						<div className="dex-route-odds">1 / {r.odds.toLocaleString()}</div>
						<div className="dex-route-eta">~{r.eta_hours.toFixed(1)} h</div>
					</div>
				</div>
			);
		})}
	</div>
);

export default RouteList;
