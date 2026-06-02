import { API_BASE } from "../../config";
import type { Pokemon, PokemonRoute } from "../../types/models";

/**
 * POSTs a new hunt for a route. For evolve routes the hunt is created on the
 * pre-evolution (evolve_from), matching the existing NewHuntModal behavior.
 * Returns the raw Response so callers can branch on res.ok and read res.text().
 */
export async function startRouteHunt(
	route: PokemonRoute,
	targetPokemon: Pokemon,
	huntParams: Record<string, unknown>,
	token: string | null,
): Promise<Response> {
	return fetch(`${API_BASE}/api/hunts`, {
		method: "POST",
		headers: {
			"Content-Type": "application/json",
			Authorization: `Bearer ${token}`,
		},
		body: JSON.stringify({
			hunt_method_id: route.method_id,
			pokemon_id: route.evolve_from ? route.evolve_from.pokemon_id : targetPokemon.id,
			game_id: route.game_id,
			method_name: route.method_name,
			hunt_parameters: huntParams,
		}),
	});
}
