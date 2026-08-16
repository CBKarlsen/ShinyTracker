import { useCallback, useEffect, useState } from "react";
import { useAuth } from "../../context/AuthContext";
import { useNotification } from "../../context/NotificationContext";
import type { PokemonRouteResponse } from "../../types/models";
import { API_BASE } from "../../config";
import { authedFetch, SessionExpiredError } from "../../utils/authedFetch";

// Fetches GET /api/pokemon/{id}/route. Pass null to fetch nothing.
export function usePokemonRoute(pokemonId: number | null) {
	const { token, logout } = useAuth();
	const { showError } = useNotification();
	const [data, setData] = useState<PokemonRouteResponse | null>(null);
	const [loading, setLoading] = useState(pokemonId != null);
	const [error, setError] = useState(false);

	const handleSessionExpired = useCallback(() => {
		logout();
		showError("Your session expired — please sign in again.");
	}, [logout, showError]);

	useEffect(() => {
		if (pokemonId == null) {
			setData(null);
			return;
		}
		let active = true;
		setLoading(true);
		setError(false);
		authedFetch(
			`${API_BASE}/api/pokemon/${pokemonId}/route`,
			token,
			{},
			handleSessionExpired,
		)
			.then((r) => (r.ok ? r.json() : Promise.reject()))
			.then((d: PokemonRouteResponse) => {
				if (active) setData(d);
			})
			.catch((err) => {
				if (err instanceof SessionExpiredError) return;
				if (active) setError(true);
			})
			.finally(() => {
				if (active) setLoading(false);
			});
		return () => {
			active = false;
		};
	}, [pokemonId, token, handleSessionExpired]);

	return {
		status: data?.status ?? null,
		routes: data?.routes ?? [],
		loading,
		error,
	};
}
