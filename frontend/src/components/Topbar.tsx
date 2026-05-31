import type { Route } from "../App";
import { Ic } from "./nav/navItems";

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
	onMoreOpen: () => void;
	onOpenSearch: () => void;
}

export default function Topbar({
	route,
	onNew,
	onMoreOpen,
	onOpenSearch,
}: Props) {
	return (
		<div className="topbar">
			{/* Hamburger — visible only on mobile (≤760px) */}
			<button
				type="button"
				className="topbar-menu-btn"
				onClick={onMoreOpen}
				aria-label="Open more options"
			>
				{Ic.menu}
			</button>

			<div className="crumb">
				<span className="topbar-workspace-crumb">Workspace</span>
				<span className="sep topbar-workspace-crumb">/</span>
				<span className="here">{routeLabels[route]}</span>
			</div>
			<div className="spacer" />
			<button type="button" className="searchbox" onClick={onOpenSearch}>
				<svg
					viewBox="0 0 16 16"
					width="14"
					height="14"
					fill="none"
					stroke="currentColor"
					strokeWidth="1.5"
					aria-hidden="true"
				>
					<circle cx="7" cy="7" r="4.5" />
					<path d="M11 11l3 3" />
				</svg>
				<span className="searchbox-placeholder">Search Pokémon…</span>
				<kbd>⌘K</kbd>
			</button>
			<button type="button" className="btn gold" onClick={onNew}>
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
