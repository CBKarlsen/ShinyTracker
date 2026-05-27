import { useEffect, useState } from "react";
import { useAuth } from "../../context/AuthContext";
import type { PokemonRouteResponse } from "../../types/models";

// Fetches GET /api/pokemon/{id}/route. Pass null to fetch nothing.
export function usePokemonRoute(pokemonId: number | null) {
	const { token } = useAuth();
	const [data, setData] = useState<PokemonRouteResponse | null>(null);
	const [loading, setLoading] = useState(false);
	const [error, setError] = useState(false);

	useEffect(() => {
		if (pokemonId == null) {
			setData(null);
			return;
		}
		let active = true;
		setLoading(true);
		setError(false);
		fetch(`http://localhost:8080/api/pokemon/${pokemonId}/route`, {
			headers: { Authorization: `Bearer ${token}` },
		})
			.then((r) => (r.ok ? r.json() : Promise.reject()))
			.then((d: PokemonRouteResponse) => {
				if (active) setData(d);
			})
			.catch(() => {
				if (active) setError(true);
			})
			.finally(() => {
				if (active) setLoading(false);
			});
		return () => {
			active = false;
		};
	}, [pokemonId, token]);

	return {
		status: data?.status ?? null,
		routes: data?.routes ?? [],
		loading,
		error,
	};
}
