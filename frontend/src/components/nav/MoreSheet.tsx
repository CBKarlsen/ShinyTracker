import { useEffect } from "react";
import type { Route } from "../../App";
import { useAuth } from "../../context/AuthContext";
import { adminItems, Ic, toolItems } from "./navItems";

interface Props {
	open: boolean;
	onClose: () => void;
	route: Route;
	setRoute: (r: Route) => void;
	onLogout: () => void;
}

export default function MoreSheet({
	open,
	onClose,
	route,
	setRoute,
	onLogout,
}: Props) {
	const { isAdmin, username } = useAuth();

	// Lock body scroll while open
	useEffect(() => {
		if (open) {
			document.body.style.overflow = "hidden";
		} else {
			document.body.style.overflow = "";
		}
		return () => {
			document.body.style.overflow = "";
		};
	}, [open]);

	// Close on Escape
	useEffect(() => {
		if (!open) return;
		const handler = (e: KeyboardEvent) => {
			if (e.key === "Escape") onClose();
		};
		document.addEventListener("keydown", handler);
		return () => document.removeEventListener("keydown", handler);
	}, [open, onClose]);

	if (!open) return null;

	const navigate = (r: Route) => {
		setRoute(r);
		onClose();
	};

	const handleLogout = () => {
		onClose();
		onLogout();
	};

	return (
		<div className="more-sheet-scrim" onClick={onClose}>
			{/* Stop click from propagating through the sheet itself */}
			<div
				className="more-sheet"
				onClick={(e) => e.stopPropagation()}
				role="dialog"
				aria-modal="true"
				aria-label="More options"
			>
				{/* Drag handle visual */}
				<div className="more-sheet-handle" />

				{/* Tools group */}
				<div className="more-sheet-section">Tools</div>
				<nav>
					{toolItems.map((item) => (
						<button
							key={item.id}
							type="button"
							className={`more-sheet-row${route === item.id ? " active" : ""}`}
							onClick={() => navigate(item.id)}
						>
							{item.icon}
							<span>{item.label}</span>
						</button>
					))}
				</nav>

				{/* Admin group — conditional */}
				{isAdmin && (
					<>
						<div className="more-sheet-section">Admin</div>
						<nav>
							{adminItems.map((item) => (
								<button
									key={item.id}
									type="button"
									className={`more-sheet-row${route === item.id ? " active" : ""}`}
									onClick={() => navigate(item.id)}
								>
									{item.icon}
									<span>{item.label}</span>
								</button>
							))}
						</nav>
					</>
				)}

				{/* Account row */}
				<div className="more-sheet-section">Account</div>
				<div className="more-sheet-account">
					<div className="avatar">
						{username ? username.charAt(0).toUpperCase() : "T"}
					</div>
					<div className="more-sheet-account-meta">
						<div className="nm">{username || "Trainer"}</div>
						<div className="stat">Shiny hunter</div>
					</div>
					<button
						type="button"
						className="more-sheet-logout"
						onClick={handleLogout}
						aria-label="Log out"
					>
						{Ic.logout}
						<span>Log out</span>
					</button>
				</div>
			</div>
		</div>
	);
}
