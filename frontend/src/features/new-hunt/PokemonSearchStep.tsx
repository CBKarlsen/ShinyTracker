import type { Pokemon } from "../../types/models";
import { getSpriteUrl } from "../../utils/pokemon";

interface Props {
	search: string;
	setSearch: (s: string) => void;
	loadingSearch: boolean;
	options: Pokemon[];
	onSelect: (p: Pokemon) => void;
	recentPokemon?: Pokemon[];
}

export function PokemonSearchStep({
	search,
	setSearch,
	loadingSearch,
	options,
	onSelect,
	recentPokemon = [],
}: Props) {
	const showRecent = search.length === 0 && recentPokemon.length > 0;

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

			{showRecent && (
				<div style={{ marginBottom: 12 }}>
					<div className="t-label" style={{ marginBottom: 8 }}>
						Recently hunted
					</div>
					<div
						style={{
							display: "flex",
							flexWrap: "wrap",
							gap: 6,
						}}
					>
						{recentPokemon.map((p) => (
							<button
								key={p.id}
								type="button"
								onClick={() => onSelect(p)}
								style={{
									display: "flex",
									alignItems: "center",
									gap: 5,
									padding: "3px 8px 3px 4px",
									background: "var(--bg-2)",
									border: "1px solid var(--line-1)",
									borderRadius: 99,
									cursor: "pointer",
									fontSize: 12,
									color: "var(--ink-2)",
									fontFamily: "var(--font-body)",
									transition: "border-color .15s, color .15s",
								}}
								onMouseEnter={(e) => {
									e.currentTarget.style.borderColor = "var(--gold)";
									e.currentTarget.style.color = "var(--ink-1)";
								}}
								onMouseLeave={(e) => {
									e.currentTarget.style.borderColor = "var(--line-1)";
									e.currentTarget.style.color = "var(--ink-2)";
								}}
							>
								<img
									src={getSpriteUrl(p.id, false, p.sprite_url)}
									alt={p.name}
									style={{ width: 22, height: 22, imageRendering: "pixelated" }}
								/>
								<span style={{ textTransform: "capitalize" }}>{p.name}</span>
							</button>
						))}
					</div>
				</div>
			)}

			<div className="poke-search-results">
				{loadingSearch && (
					<div className="empty" style={{ padding: 16 }}>
						Searching…
					</div>
				)}
				{!loadingSearch && options.length === 0 && search.length > 0 && (
					<div className="empty">No matches</div>
				)}
				{!loadingSearch &&
					options.length === 0 &&
					search.length === 0 &&
					!showRecent && <div className="empty">Type to search</div>}
				{options.map((p) => (
					<div
						key={p.id}
						className="row"
						onClick={() => onSelect(p)}
						onKeyDown={(e) => {
							if (e.key === "Enter" || e.key === " ") {
								e.preventDefault();
								onSelect(p);
							}
						}}
						role="button"
						tabIndex={0}
					>
						<img src={getSpriteUrl(p.id, false, p.sprite_url)} alt={p.name} />
						<div className="nm">{p.name}</div>
						<div className="id">#{String(p.id).padStart(4, "0")}</div>
					</div>
				))}
			</div>
		</div>
	);
}
