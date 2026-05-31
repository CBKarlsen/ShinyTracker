import type { Route } from "../App";
import { useAuth } from "../context/AuthContext";
import { Ic, toolItems, workspaceItems } from "./nav/navItems";
import { SparkSm } from "./ui/icons";

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
					{workspaceItems.map((it) => {
						const badgeCount =
							it.badge === "activeHuntCount" ? activeHuntCount : 0;
						return (
							<button
								key={it.id}
								className={route === it.id ? "active" : ""}
								onClick={() => setRoute(it.id)}
							>
								{it.icon}
								<span>{it.label}</span>
								{badgeCount > 0 ? (
									<span className="badge">{badgeCount}</span>
								) : null}
							</button>
						);
					})}
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
