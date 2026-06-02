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
	variant?: "launch" | "select";
}

interface GameGroup {
	gameId: number;
	gameTitle: string;
	routes: PokemonRoute[];
}

// Groups routes by game, orders games by their best (lowest) odds, and keeps
// the backend's ascending-odds order within each game.
function groupByGame(routes: PokemonRoute[]): GameGroup[] {
	const map = new Map<number, PokemonRoute[]>();
	for (const r of routes) {
		const arr = map.get(r.game_id);
		if (arr) arr.push(r);
		else map.set(r.game_id, [r]);
	}
	const groups: GameGroup[] = Array.from(map.entries()).map(([gameId, rs]) => ({
		gameId,
		gameTitle: rs[0].game_title,
		routes: rs,
	}));
	groups.sort(
		(a, b) =>
			Math.min(...a.routes.map((r) => r.odds)) - Math.min(...b.routes.map((r) => r.odds)),
	);
	return groups;
}

const RouteList: React.FC<Props> = ({ routes, selectedKey, onRouteClick, variant = "launch" }) => {
	const direct = routes.filter((r) => r.kind === "direct");
	const evolve = routes.filter((r) => r.kind === "evolve");
	return (
		<>
			{direct.length > 0 && (
				<div style={{ marginBottom: 14 }}>
					<div className="t-label" style={{ marginBottom: 8 }}>
						Routes in your games
					</div>
					{groupByGame(direct).map((g) => (
						<div key={g.gameId} style={{ marginBottom: 10 }}>
							<div className="dex-route-gamehead">{g.gameTitle}</div>
							{g.routes.map((r) => (
								<Row
									key={routeKey(r)}
									route={r}
									showGame={false}
									selectedKey={selectedKey}
									onRouteClick={onRouteClick}
									variant={variant}
								/>
							))}
						</div>
					))}
				</div>
			)}
			{evolve.length > 0 && (
				<div style={{ marginBottom: 14 }}>
					<div className="t-label" style={{ marginBottom: 8 }}>
						Hunt a pre-evolution
					</div>
					{evolve.map((r) => (
						<Row
							key={routeKey(r)}
							route={r}
							showGame={true}
							selectedKey={selectedKey}
							onRouteClick={onRouteClick}
							variant={variant}
						/>
					))}
				</div>
			)}
		</>
	);
};

const Row: React.FC<{
	route: PokemonRoute;
	showGame: boolean;
	selectedKey?: string;
	onRouteClick: (route: PokemonRoute) => void;
	variant?: "launch" | "select";
}> = ({ route: r, showGame, selectedKey, onRouteClick, variant }) => {
	const key = routeKey(r);
	return (
		<div
			className={`dex-route ${selectedKey === key ? "sel" : ""}`}
			onClick={() => onRouteClick(r)}
		>
			<div>
				<div className="dex-route-name">{r.method_name}</div>
				{showGame && (
					<div className="dex-route-game">
						{r.evolve_from ? `${r.evolve_from.name} · ${r.game_title}` : r.game_title}
					</div>
				)}
				{r.evolve_from && <div className="dex-route-evo">↳ then evolve</div>}
			</div>
			<div style={{ textAlign: "right" }}>
				<div className="dex-route-odds">1 / {r.odds.toLocaleString()}</div>
				{r.has_shiny_charm && <div className="dex-route-charm">✦ Charm</div>}
				<div className="dex-route-eta" style={{ opacity: 0.65 }}>best case</div>
				<div className="dex-route-eta">~{r.eta_hours.toFixed(1)} h</div>
				{variant === "launch" && <div className="dex-route-start">▸ Start</div>}
			</div>
		</div>
	);
};

export default RouteList;
