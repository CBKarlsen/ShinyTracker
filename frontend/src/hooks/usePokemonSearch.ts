import { useEffect, useRef, useState } from "react";
import { API_BASE } from "../config";
import { useAuth } from "../context/AuthContext";
import type { Pokemon } from "../types/models";
import { authedFetch } from "../utils/authedFetch";

/**
 * Debounced Pokémon search against GET /api/pokemon?q=.
 * Returns an empty list for blank queries and discards stale responses so
 * fast typing never shows results for an older query.
 */
export function usePokemonSearch(query: string): {
	results: Pokemon[];
	loading: boolean;
} {
	const { token, logout } = useAuth();
	const [results, setResults] = useState<Pokemon[]>([]);
	const [loading, setLoading] = useState(false);
	const seqRef = useRef(0);

	// biome-ignore lint/correctness/useExhaustiveDependencies: logout identity churns on AuthProvider re-renders; omitting it is intentional
	useEffect(() => {
		const q = query.trim();
		if (!q) {
			setResults([]);
			setLoading(false);
			return;
		}
		setLoading(true);
		const seq = ++seqRef.current;
		const timer = setTimeout(async () => {
			try {
				const res = await authedFetch(
					`${API_BASE}/api/pokemon?q=${encodeURIComponent(q)}`,
					token,
					{},
					logout,
				);
				const data = res.ok ? ((await res.json()) as Pokemon[]) || [] : [];
				if (seq === seqRef.current) setResults(data);
			} catch {
				if (seq === seqRef.current) setResults([]);
			} finally {
				if (seq === seqRef.current) setLoading(false);
			}
		}, 200);
		return () => clearTimeout(timer);
		// biome-ignore lint/correctness/useExhaustiveDependencies: query and token are the trigger; the debounce timer owns the rest and re-running on its identity would reset the debounce every render.
	}, [query, token]);

	return { results, loading };
}
