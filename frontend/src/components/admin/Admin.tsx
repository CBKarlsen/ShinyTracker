import { useState } from "react";
import AdminAvailability from "./AdminAvailability";
import AdminEncounters from "./AdminEncounters";
import AdminGames from "./AdminGames";
import AdminUsers from "./AdminUsers";

type AdminTab = "hunt-methods" | "games" | "availability" | "users";

const tabs: { id: AdminTab; label: string }[] = [
	{ id: "hunt-methods", label: "Hunt Methods" },
	{ id: "games", label: "Games" },
	{ id: "availability", label: "Availability" },
	{ id: "users", label: "Users" },
];

export default function Admin() {
	const [tab, setTab] = useState<AdminTab>("hunt-methods");

	return (
		<div className="page">
			<div className="page-head">
				<div>
					<div className="sub">Workspace · Admin</div>
					<h1>Admin Panel</h1>
				</div>
			</div>

			<div className="admin-tabs">
				{tabs.map((t) => (
					<button
						key={t.id}
						className={`admin-tab ${tab === t.id ? "active" : ""}`}
						onClick={() => setTab(t.id)}
					>
						{t.label}
					</button>
				))}
			</div>

			<div style={{ marginTop: 20 }}>
				{tab === "hunt-methods" && <AdminEncounters />}
				{tab === "games" && <AdminGames />}
				{tab === "availability" && <AdminAvailability />}
				{tab === "users" && <AdminUsers />}
			</div>
		</div>
	);
}
