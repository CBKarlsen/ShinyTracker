import type { Route } from "../../App";
import { workspaceItems } from "./navItems";

interface Props {
	route: Route;
	setRoute: (r: Route) => void;
	activeHuntCount: number;
}

export default function BottomNav({ route, setRoute, activeHuntCount }: Props) {
	return (
		<nav className="bottom-nav" aria-label="Main navigation">
			{workspaceItems.map((item) => {
				const isActive = route === item.id;
				const badgeCount =
					item.badge === "activeHuntCount" ? activeHuntCount : 0;
				return (
					<button
						key={item.id}
						type="button"
						className={`bottom-nav-tab${isActive ? " active" : ""}`}
						onClick={() => setRoute(item.id)}
						aria-current={isActive ? "page" : undefined}
					>
						<span className="bottom-nav-icon-wrap">
							{item.icon}
							{badgeCount > 0 && (
								<span className="bottom-nav-badge">{badgeCount}</span>
							)}
						</span>
						<span className="bottom-nav-label">{item.shortLabel}</span>
					</button>
				);
			})}
		</nav>
	);
}
