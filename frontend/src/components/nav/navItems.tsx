import type { Route } from "../../App";

// Shared icon set — single source of truth for Sidebar, BottomNav, MoreSheet
export const Ic = {
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
	menu: (
		<svg
			viewBox="0 0 16 16"
			width="16"
			height="16"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.5"
		>
			<path d="M2 4h12M2 8h12M2 12h12" />
		</svg>
	),
	close: (
		<svg
			viewBox="0 0 16 16"
			width="14"
			height="14"
			fill="none"
			stroke="currentColor"
			strokeWidth="1.5"
		>
			<path d="M3 3l10 10M13 3L3 13" />
		</svg>
	),
};

export interface WorkspaceItem {
	id: Route;
	label: string;
	shortLabel: string;
	icon: React.ReactNode;
	badge?: "activeHuntCount";
}

export interface NavItem {
	id: Route;
	label: string;
	icon: React.ReactNode;
}

export const workspaceItems: WorkspaceItem[] = [
	{
		id: "dash",
		label: "Dashboard",
		shortLabel: "Dashboard",
		icon: Ic.dash,
		badge: "activeHuntCount",
	},
	{
		id: "historic",
		label: "Historic Hunts",
		shortLabel: "Historic",
		icon: Ic.history,
	},
	{ id: "dex", label: "Living Dex", shortLabel: "Living Dex", icon: Ic.dex },
	{ id: "games", label: "Games", shortLabel: "Games", icon: Ic.games },
	{ id: "stats", label: "Stats", shortLabel: "Stats", icon: Ic.stats },
];

export const toolItems: NavItem[] = [
	{ id: "odds-calc", label: "Odds Calculator", icon: Ic.calc },
	{ id: "method-library", label: "Method Library", icon: Ic.book },
];

export const adminItems: NavItem[] = [
	{ id: "admin", label: "Admin Panel", icon: Ic.admin },
];
