import { useState, useEffect, useCallback } from "react";
import { useAuth } from "../../context/AuthContext";
import { useNotification } from "../../context/NotificationContext";
import type { Hunt } from "../../types/models";

export function useHunts() {
	const { token } = useAuth();
	const { showError } = useNotification();

	const [hunts, setHunts] = useState<Hunt[]>([]);
	const [loading, setLoading] = useState(true);

	const fetchHunts = useCallback(async () => {
		if (!token) return;
		try {
			const res = await fetch("http://localhost:8080/api/hunts", {
				headers: { Authorization: `Bearer ${token}` },
			});
			if (res.ok) {
				const data = await res.json();
				setHunts(data || []);
			} else {
				showError("Failed to fetch hunts.");
			}
		} catch (err: any) {
			showError(err.message || "Failed to fetch hunts.");
		} finally {
			setLoading(false);
		}
	}, [token, showError]);

	useEffect(() => {
		fetchHunts();
	}, [fetchHunts]);

	const updateHuntParameters = async (huntId: string, params: Record<string, any>) => {
		try {
			const res = await fetch(`http://localhost:8080/api/hunts/${huntId}`, {
				method: "PATCH",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({ hunt_parameters: params }),
			});
			if (res.ok) {
				setHunts((prev) =>
					prev.map((h) => (h.id === huntId ? { ...h, hunt_parameters: params } : h))
				);
			} else {
				showError("Failed to update parameters.");
			}
		} catch (err: any) {
			showError(err.message || "Failed to update parameters.");
		}
	};

	const updateEncounterCount = async (huntId: string, newCount: number) => {
		try {
			const res = await fetch(`http://localhost:8080/api/hunts/${huntId}`, {
				method: "PATCH",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({ encounter_count: newCount }),
			});
			if (!res.ok) throw new Error("Update failed");
		} catch (err: any) {
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
