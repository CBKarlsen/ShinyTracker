// The server is the preferred sprite source: sprite_url/shiny_sprite_url ride
// along on pokemon, hunt and phase responses, so the host lives in the
// database. ponytail: the hardcoded host survives only as the fallback, because
// the shiny column is filled by migration 016's backfill — a server that hasn't
// run it yet answers "". Mirrors ios/App/SpriteSource.swift.
//
// jsDelivr, not raw.githubusercontent.com. Same repo, byte-identical files
// (verified by hash), but raw.githubusercontent is a source-code endpoint, not a
// CDN: GitHub's ToS disallows using it as asset hosting and it rate-limits under
// load, with no SLA. jsDelivr exists to serve GitHub content and caches for a
// week. The served URLs move via migration 022; this is only the fallback.
//
// This does NOT change the copyright position — the artwork is still Nintendo's.
// See README "Known gaps".
const SPRITE_BASE =
	"https://cdn.jsdelivr.net/gh/PokeAPI/sprites@master/sprites/pokemon/";

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

/**
 * Dex search: case-insensitive substring match on name, OR an exact dex-number
 * match. "#025", "025" and "25" all mean number 25. The number half is exact,
 * not a substring: "1" as a substring matches a third of the dex, which makes
 * the grid flash to near-everything on the first keystroke.
 */
export function matchesSearch(
	query: string,
	name: string,
	dexNumber: number,
): boolean {
	const q = query.trim().toLowerCase();
	if (!q) return true;
	if (name.toLowerCase().includes(q)) return true;
	const num = q.replace(/^#/, "");
	return /^\d+$/.test(num) && Number(num) === dexNumber;
}
