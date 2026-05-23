import type { Route } from "../App";

const routeLabels: Record<Route, string> = {
	dash: "Dashboard",
	historic: "Historic Hunts",
	dex: "Living Dex",
	games: "Game Library",
	stats: "Stats",
	"odds-calc": "Odds Calculator",
	"method-library": "Method Library",
	admin: "Admin",
};

interface Props {
	route: Route;
	onNew: () => void;
}

export default function Topbar({ route, onNew }: Props) {
	return (
		<div className="topbar">
			<div className="crumb">
				<span>Workspace</span>
				<span className="sep">/</span>
				<span className="here">{routeLabels[route]}</span>
			</div>
			<div className="spacer" />
			<div className="searchbox">
				<svg
					viewBox="0 0 16 16"
					width="14"
					height="14"
					fill="none"
					stroke="currentColor"
					strokeWidth="1.5"
				>
					<circle cx="7" cy="7" r="4.5" />
					<path d="M11 11l3 3" />
				</svg>
				<input placeholder="Search hunts, Pokémon…" readOnly />
				<kbd>⌘K</kbd>
			</div>
			<button className="btn gold" onClick={onNew}>
				<svg
					viewBox="0 0 16 16"
					width="14"
					height="14"
					fill="none"
					stroke="currentColor"
					strokeWidth="2"
				>
					<path d="M8 3v10M3 8h10" />
				</svg>
				New Hunt
			</button>
		</div>
	);
}
