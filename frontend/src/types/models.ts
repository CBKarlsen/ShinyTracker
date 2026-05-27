export interface HuntPhase {
	id: string;
	hunt_id: string;
	pokemon_id: number;
	pokemon_name: string;
	sprite_url: string;
	encounter_count_at_phase: number;
	created_at: string;
}

export interface Hunt {
	id: string;
	hunt_method_id: number | null;
	encounter_count: number;
	phase_count: number;
	phases: HuntPhase[];
	status: string;
	acquisition_type: string;
	hunt_parameters: unknown;
	created_at: string;
	updated_at: string;
	pokemon_id: number;
	pokemon_name: string;
	method_name: string | null;
	custom_method_name: string | null;
	game_title: string | null;
	total_time_seconds: number;
	base_rolls: number | null;
	charm_rolls: number | null;
	avg_time_seconds: number | null;
	base_odds: number | null;
	has_shiny_charm: boolean | null;
	formula_type?: string;
}

export interface PokemonOption {
	id: number;
	name: string;
	sprite_url: string;
}

export interface Pokemon {
	id: number;
	name: string;
	sprite_url: string;
	is_legendary?: boolean;
	is_mythical?: boolean;
}

export interface HuntMethod {
	id: number;
	pokemon_id: number;
	game_id: number;
	game_title: string;
	method_name: string;
	avg_time_seconds: number;
	base_rolls: number;
	charm_rolls: number;
	formula_type?: string;
}

export interface Game {
	id: number;
	title: string;
	generation?: number;
	base_odds?: number;
}

export interface DexStatus {
	not_in_your_games: number[];
	locked_everywhere: number[];
}

export interface PokemonRoute {
	kind: "direct" | "evolve";
	game_id: number;
	game_title: string;
	method_name: string;
	method_id: number;
	formula_type: string;
	odds: number;
	eta_hours: number;
	evolve_from?: { pokemon_id: number; name: string };
}

export interface PokemonRouteResponse {
	status: "available" | "not_in_your_games" | "locked_everywhere";
	routes: PokemonRoute[];
}
