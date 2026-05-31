import { useState, useEffect, useCallback } from "react";
import { useAuth } from "../../context/AuthContext";
import { useNotification } from "../../context/NotificationContext";
import type { Hunt } from "../../types/models";
import { API_BASE } from "../../config";
import { authedFetch, SessionExpiredError } from "../../utils/authedFetch";

export function useHunts() {
	const { token, logout } = useAuth();
	const { showError } = useNotification();

	const [hunts, setHunts] = useState<Hunt[]>([]);
	const [loading, setLoading] = useState(true);

	// Centralised 401 handler: log out and show a clear message.
	const handleSessionExpired = useCallback(() => {
		logout();
		showError("Your session expired — please sign in again.");
	}, [logout, showError]);

	const fetchHunts = useCallback(async () => {
		if (!token) return;
		try {
			const res = await authedFetch(
				`${API_BASE}/api/hunts`,
				token,
				{},
				handleSessionExpired,
			);
			if (res.ok) {
				const data = await res.json();
				setHunts(data || []);
			} else {
				showError("Failed to fetch hunts.");
			}
		} catch (err: any) {
			if (err instanceof SessionExpiredError) return;
			showError(err.message || "Failed to fetch hunts.");
		} finally {
			setLoading(false);
		}
	}, [token, showError, handleSessionExpired]);

	useEffect(() => {
		fetchHunts();
	}, [fetchHunts]);

	const updateHuntParameters = async (huntId: string, params: Record<string, any>) => {
		try {
			const res = await authedFetch(
				`${API_BASE}/api/hunts/${huntId}`,
				token,
				{
					method: "PATCH",
					headers: { "Content-Type": "application/json" },
					body: JSON.stringify({ hunt_parameters: params }),
				},
				handleSessionExpired,
			);
			if (res.ok) {
				setHunts((prev) =>
					prev.map((h) => (h.id === huntId ? { ...h, hunt_parameters: params } : h))
				);
			} else {
				showError("Failed to update parameters.");
			}
		} catch (err: any) {
			if (err instanceof SessionExpiredError) return;
			showError(err.message || "Failed to update parameters.");
		}
	};

	const updateEncounterCount = async (huntId: string, newCount: number) => {
		try {
			const res = await authedFetch(
				`${API_BASE}/api/hunts/${huntId}`,
				token,
				{
					method: "PATCH",
					headers: { "Content-Type": "application/json" },
					body: JSON.stringify({ encounter_count: newCount }),
				},
				handleSessionExpired,
			);
			if (!res.ok) throw new Error("Update failed");
		} catch (err: any) {
			if (err instanceof SessionExpiredError) return;
			console.error(err);
		}
	};

	const incrementEncounter = (huntId: string) => {
		setHunts((prev) =>
			prev.map((h) => {
				if (h.id === huntId) {
					const newCount = h.encounter_count + 1;
					updateEncounterCount(huntId, newCount);
					return { ...h, encounter_count: newCount };
				}
				return h;
			})
		);
	};

	return {
		hunts,
		loading,
		setHunts,
		fetchHunts,
		updateHuntParameters,
		incrementEncounter,
	};
}
