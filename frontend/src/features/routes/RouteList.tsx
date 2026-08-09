import type React from "react";
import type { PokemonRoute, RouteLocation } from "../../types/models";

// Stable identity for a route, used for selection highlighting.
// Assumes (kind, game_id, method_id) is unique per route — method_id is unique
// per game, so do not weaken this to method_name.
export function routeKey(r: PokemonRoute): string {
	return `${r.kind}-${r.game_id}-${r.method_id}`;
}

// PokeAPI area slugs are kebab-case and often carry a trailing "-area":
// "route-210-area" -> "Route 210". Deliberately not a curated name table.
function formatArea(slug: string): string {
	return slug
		.replace(/-area$/, "")
		.split("-")
		.map((w) => w.charAt(0).toUpperCase() + w.slice(1))
		.join(" ");
}

// "time-night" -> "Night", "season-spring" -> "Spring".
function formatCondition(c: string): string {
	const last = c.split("-").pop() ?? c;
	return last.charAt(0).toUpperCase() + last.slice(1);
}

function formatLevels(l: RouteLocation): string {
	if (!l.min_level && !l.max_level) return "";
	if (l.min_level === l.max_level) return `Lv ${l.min_level}`;
	return `Lv ${l.min_level}-${l.max_level}`;
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

const Locations: React.FC<{ route: PokemonRoute }> = ({ route }) => {
	const locations = route.locations;
	if (locations && locations.length > 0) {
		return (
			<div className="dex-route-locs">
				{locations.map((l, idx) => {
					const parts = [formatLevels(l), l.chance ? `${l.chance}%` : ""]
						.concat(l.conditions.map(formatCondition))
						.filter(Boolean);
					return (
						<div
							className="dex-route-loc"
							key={`${l.version}-${l.area}-${l.terrain}-${l.min_level}-${l.max_level}-${l.chance}-${idx}`}
						>
							<span className="dex-route-loc-area">{formatArea(l.area)}</span>
							{parts.length > 0 && (
								<span className="dex-route-loc-meta"> · {parts.join(" · ")}</span>
							)}
						</div>
					);
				})}
			</div>
		);
	}
	// Breeding, soft-resets and raids have no map location by nature -- say
	// nothing. Anything else with no rows is a genuine data gap (Gen 8/9, BDSP,
	// LGPE, LA) and must say so, rather than read as "nowhere to find it".
	//
	// requires_kind comes from the backend so this check cannot drift from the
	// method data; do not re-derive it from method_name.
	if (route.requires_kind && route.requires_kind !== "wild") return null;
	return <div className="dex-route-loc dex-route-loc-empty">No location data for this game yet</div>;
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
				<Locations route={r} />
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
