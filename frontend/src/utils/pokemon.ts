// The server is the preferred sprite source: sprite_url/shiny_sprite_url ride
// along on pokemon, hunt and phase responses, so the host lives in the
// database. ponytail: the hardcoded PokeAPI host survives only as the
// fallback, because the shiny column is filled by migration 016's backfill —
// a server that hasn't run it yet answers "". Mirrors ios/App/SpriteSource.swift.
const SPRITE_BASE =
	"https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/";

export const getSpriteUrl = (
	id: number,
	shiny: boolean,
	served?: string,
): string => {
	if (served) return served;
	return `${SPRITE_BASE}${shiny ? "shiny/" : ""}${id}.png`;
};

// Pokémon Showdown drops gender hyphens (nidoran-f → nidoranf) and strips
// special characters that don't appear in their sprite filenames.
export const getShowdownGif = (pokemonName: string): string => {
	if (!pokemonName) return "";
	const name = pokemonName
		.toLowerCase()
		.replace(/♀/g, "f")
		.replace(/♂/g, "m")
		.replace(/[éèêë]/g, "e")
		.replace(/[áàâä]/g, "a")
		.replace(/[íìîï]/g, "i")
		.replace(/[óòôö]/g, "o")
		.replace(/[úùûü]/g, "u")
		.replace(/-([mf])$/, "$1")
		.replace(/[':]/g, "")
		.replace(/\./g, "")
		.replace(/\s+/g, "-")
		.replace(/-+/g, "-");
	return `https://play.pokemonshowdown.com/sprites/ani-shiny/${name}.gif`;
};
