import type { Route } from "../App";
import { useAuth } from "../context/AuthContext";
import { SparkSm } from "./ui/icons";

const Ic = {
	dash: (
		<svg
			className="ic"
			viewBox="0 0 16 16"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.5"
		>
			<rect x="2" y="2" width="5" height="6" rx="1" />
			<rect x="9" y="2" width="5" height="3" rx="1" />
			<rect x="9" y="7" width="5" height="7" rx="1" />
			<rect x="2" y="10" width="5" height="4" rx="1" />
		</svg>
	),
	history: (
		<svg
			className="ic"
			viewBox="0 0 16 16"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.5"
		>
			<circle cx="8" cy="8" r="6" />
			<path d="M8 4v4l3 2" />
		</svg>
	),
	dex: (
		<svg
			className="ic"
			viewBox="0 0 16 16"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.5"
		>
			<rect x="2" y="2" width="12" height="12" rx="2" />
			<path d="M2 7h12" />
			<circle cx="5" cy="4.5" r="0.7" fill="currentColor" />
		</svg>
	),
	games: (
		<svg
			className="ic"
			viewBox="0 0 16 16"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.5"
		>
			<rect x="2" y="4" width="12" height="9" rx="2" />
			<path d="M5 8h2M6 7v2M10 7.5h0M11.5 8.5h0" />
		</svg>
	),
	stats: (
		<svg
			className="ic"
			viewBox="0 0 16 16"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.5"
		>
			<path d="M2 13h12M4 11V7M7 11V4M10 11V8M13 11V6" />
		</svg>
	),
	calc: (
		<svg
			className="ic"
			viewBox="0 0 16 16"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.5"
		>
			<rect x="2" y="2" width="12" height="12" rx="2" />
			<path d="M5 5h2M5 8h6M5 11h6M9 5h2" />
		</svg>
	),
	book: (
		<svg
			className="ic"
			viewBox="0 0 16 16"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.5"
		>
			<path d="M3 2h8a1 1 0 011 1v10a1 1 0 01-1 1H3a1 1 0 01-1-1V3a1 1 0 011-1z" />
			<path d="M5 5h6M5 8h6M5 11h4" />
		</svg>
	),
	admin: (
		<svg
			className="ic"
			viewBox="0 0 16 16"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.5"
		>
			<circle cx="8" cy="6" r="2.5" />
			<path d="M3 13c0-2.76 2.24-4 5-4s5 1.24 5 4" />
			<path d="M11 2l.5 1.5L13 4l-1.5.5L11 6l-.5-1.5L9 4l1.5-.5z" />
		</svg>
	),
	logout: (
		<svg
			viewBox="0 0 16 16"
			width="14"
			height="14"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.5"
		>
			<path d="M9 3H4a1 1 0 00-1 1v8a1 1 0 001 1h5" />
			<path d="M11 5l3 3-3 3M14 8H7" />
		</svg>
	),
};

interface Props {
	route: Route;
	setRoute: (r: Route) => void;
	onLogout: () => void;
	activeHuntCount: number;
}

export default function Sidebar({
	route,
	setRoute,
	onLogout,
	activeHuntCount,
}: Props) {
	const { isAdmin, username } = useAuth();
	const workspaceItems: {
		id: Route;
		label: string;
		icon: React.ReactNode;
		badge?: number;
	}[] = [
		{ id: "dash", label: "Dashboard", icon: Ic.dash, badge: activeHuntCount },
		{ id: "historic", label: "Historic Hunts", icon: Ic.history },
		{ id: "dex", label: "Living Dex", icon: Ic.dex },
		{ id: "games", label: "Games", icon: Ic.games },
		{ id: "stats", label: "Stats", icon: Ic.stats },
	];

	const toolItems: { id: Route; label: string; icon: React.ReactNode }[] = [
		{ id: "odds-calc", label: "Odds Calculator", icon: Ic.calc },
		{ id: "method-library", label: "Method Library", icon: Ic.book },
	];

	return (
		<aside className="sidebar">
			<div className="sidebar-brand">
				<div className="mark">
					<SparkSm size={14} color="var(--gold)" />
				</div>
				<div>
					<div className="name">ShinyTracker</div>
				</div>
			</div>

			<div className="sidebar-mid">
				<div className="sidebar-section">Workspace</div>
				<nav>
					{workspaceItems.map((it) => (
						<button
							key={it.id}
							className={route === it.id ? "active" : ""}
							onClick={() => setRoute(it.id)}
						>
							{it.icon}
							<span>{it.label}</span>
							{it.badge != null && it.badge > 0 ? (
								<span className="badge">{it.badge}</span>
							) : null}
						</button>
					))}
				</nav>

				<div className="sidebar-section" style={{ marginTop: 10 }}>
					Tools
				</div>
				<nav>
					{toolItems.map((it) => (
						<button
							key={it.id}
							className={route === it.id ? "active" : ""}
							onClick={() => setRoute(it.id)}
						>
							{it.icon}
							<span>{it.label}</span>
						</button>
					))}
				</nav>

				{isAdmin && (
					<>
						<div className="sidebar-section" style={{ marginTop: 10 }}>
							Admin
						</div>
						<nav>
							<button
								className={route === "admin" ? "active" : ""}
								onClick={() => setRoute("admin")}
							>
								{Ic.admin}
								<span>Admin Panel</span>
							</button>
						</nav>
					</>
				)}
			</div>

			<div className="sidebar-foot">
				<div className="avatar">
					{username ? username.charAt(0).toUpperCase() : "T"}
				</div>
				<div className="meta">
					<div className="nm">{username || "Trainer"}</div>
					<div className="stat">Shiny hunter</div>
				</div>
				<button className="logout" title="Log out" onClick={onLogout}>
					{Ic.logout}
				</button>
			</div>
		</aside>
	);
}
