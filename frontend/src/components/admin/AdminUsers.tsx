import { useEffect, useState } from "react";
import { useAuth } from "../../context/AuthContext";

interface UserRow {
	id: string;
	username: string;
	email: string;
	is_admin: boolean;
	created_at: string;
}

const API = "http://localhost:8080";
function authHeaders(token: string) {
	return {
		Authorization: `Bearer ${token}`,
		"Content-Type": "application/json",
	};
}

export default function AdminUsers() {
	const { token, userId } = useAuth();
	const [users, setUsers] = useState<UserRow[]>([]);
	const [error, setError] = useState("");

	useEffect(() => {
		fetch(`${API}/api/admin/users`, { headers: authHeaders(token!) })
			.then((r) => r.json())
			.then((d) => setUsers(d ?? []))
			.catch(() => {});
	}, [token]);

	const toggleAdmin = async (user: UserRow) => {
		if (user.id === userId && user.is_admin) {
			setError("You cannot remove your own admin privileges");
			return;
		}
		const res = await fetch(`${API}/api/admin/users/${user.id}`, {
			method: "PATCH",
			headers: authHeaders(token!),
			body: JSON.stringify({ is_admin: !user.is_admin }),
		});
		if (!res.ok) {
			const t = await res.text();
			setError(t);
			return;
		}
		setUsers((prev) =>
			prev.map((u) => (u.id === user.id ? { ...u, is_admin: !u.is_admin } : u)),
		);
	};

	return (
		<div>
			{error && (
				<div className="admin-error" onClick={() => setError("")}>
					{error} ✕
				</div>
			)}

			<div className="card flush">
				<table className="method-table">
					<thead>
						<tr>
							<th>Username</th>
							<th>Email</th>
							<th>Joined</th>
							<th>Admin</th>
						</tr>
					</thead>
					<tbody>
						{users.map((u) => (
							<tr key={u.id}>
								<td className="method-name">
									{u.username}
									{u.id === userId && (
										<span
											className="tag-badge"
											style={{
												marginLeft: 8,
												background: "var(--blue-soft)",
												color: "var(--blue)",
												borderColor: "var(--blue-line)",
											}}
										>
											you
										</span>
									)}
								</td>
								<td
									className="t-mono"
									style={{ fontSize: 12, color: "var(--ink-2)" }}
								>
									{u.email}
								</td>
								<td
									className="t-mono"
									style={{ fontSize: 11, color: "var(--ink-3)" }}
								>
									{new Date(u.created_at).toLocaleDateString()}
								</td>
								<td>
									<button
										className={`btn ${u.is_admin ? "gold" : "ghost"}`}
										style={{ padding: "4px 12px", fontSize: 12 }}
										onClick={() => toggleAdmin(u)}
										disabled={u.id === userId && u.is_admin}
										title={
											u.id === userId && u.is_admin
												? "Cannot remove your own admin"
												: undefined
										}
									>
										{u.is_admin ? "Admin" : "User"}
									</button>
								</td>
							</tr>
						))}
						{users.length === 0 && (
							<tr>
								<td
									colSpan={4}
									className="empty"
									style={{ padding: "20px 16px" }}
								>
									No users found
								</td>
							</tr>
						)}
					</tbody>
				</table>
			</div>
		</div>
	);
}
