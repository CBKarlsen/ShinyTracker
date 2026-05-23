import type { Pokemon } from "../../types/models";

interface Props {
	search: string;
	setSearch: (s: string) => void;
	loadingSearch: boolean;
	options: Pokemon[];
	onSelect: (p: Pokemon) => void;
}

export function PokemonSearchStep({
	search,
	setSearch,
	loadingSearch,
	options,
	onSelect,
}: Props) {
	return (
		<div>
			<div className="field">
				<label>1 · Pokémon</label>
				<input
					className="input"
					placeholder="Search any Pokémon…"
					value={search}
					onChange={(e) => setSearch(e.target.value)}
					autoFocus
				/>
			</div>
			<div className="poke-search-results">
				{loadingSearch && (
					<div className="empty" style={{ padding: 16 }}>
						Searching…
					</div>
				)}
				{!loadingSearch && options.length === 0 && (
					<div className="empty">
						{search.length > 0 ? "No matches" : "Type to search"}
					</div>
				)}
				{options.map((p) => (
					<div key={p.id} className="row" onClick={() => onSelect(p)}>
						<img
							src={
								p.sprite_url ||
								`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${p.id}.png`
							}
							alt={p.name}
						/>
						<div className="nm">{p.name}</div>
						<div className="id">#{String(p.id).padStart(4, "0")}</div>
					</div>
				))}
			</div>
		</div>
	);
}
