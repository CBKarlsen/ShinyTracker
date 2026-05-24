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
