import type React from "react";
import { useEffect, useState } from "react";
import { API_BASE } from "../config";
import { useAuth } from "../context/AuthContext";
import { useNotification } from "../context/NotificationContext";
import type {
	DexStatus,
	Game,
	GamePokedexResponse,
	Pokemon,
	PokemonRoute,
} from "../types/models";
import { getSpriteUrl, matchesSearch } from "../utils/pokemon";
import DexDrawer from "./DexDrawer";
import type { HuntDetail } from "./HistoricHunts";
import HuntNextPanel from "./HuntNextPanel";

const GEN_RANGES: [number, number, number][] = [
	[1, 1, 151],
	[2, 152, 251],
	[3, 252, 386],
	[4, 387, 493],
	[5, 494, 649],
	[6, 650, 721],
	[7, 722, 809],
	[8, 810, 905],
	[9, 906, 1025],
];
const ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"];

const GAME_VIEW_KEY = "st_dex_game_view";

const Collection: React.FC<{
	onStartHunt?: (pokemon: Pokemon, route: PokemonRoute) => void;
	focusPokemonId?: number | null;
	onFocusHandled?: () => void;
	onHuntStarted?: () => void;
}> = ({ onStartHunt, focusPokemonId, onFocusHandled, onHuntStarted }) => {
	const { token } = useAuth();
	const { showError } = useNotification();
	const [pokemon, setPokemon] = useState<Pokemon[]>([]);
	const [caughtIds, setCaughtIds] = useState<Set<number>>(new Set());
	const [blocked, setBlocked] = useState<{
		locked: Set<number>;
		notInGames: Set<number>;
	}>({ locked: new Set(), notInGames: new Set() });
	const [loading, setLoading] = useState(true);
	const [filter, setFilter] = useState<"all" | "owned" | "missing">("all");
	const [drawerId, setDrawerId] = useState<number | null>(null);
	const [search, setSearch] = useState("");

	const [games, setGames] = useState<Game[]>([]);
	const [gameView, setGameView] = useState<string>(
		() => localStorage.getItem(GAME_VIEW_KEY) || "national",
	);
	const [gameDex, setGameDex] = useState<GamePokedexResponse | null>(null);
	const [gameDexLoading, setGameDexLoading] = useState(false);

	// When asked to focus a specific Pokémon (e.g. from command search),
	// open its drawer, then tell the parent it was handled so it can reset
	// (lets the same Pokémon be focused again later).
	// biome-ignore lint/correctness/useExhaustiveDependencies: onFocusHandled is an inline arrow that changes every parent render; omitting it is intentional
	useEffect(() => {
		if (focusPokemonId != null) {
			setDrawerId(focusPokemonId);
			onFocusHandled?.();
		}
	}, [focusPokemonId]); // eslint-disable-line react-hooks/exhaustive-deps

	useEffect(() => {
		const fetchData = async () => {
			try {
				const [pokeRes, huntsRes, statusRes, gamesRes] = await Promise.all([
					fetch(`${API_BASE}/api/pokemon?limit=all`),
					fetch(`${API_BASE}/api/hunts`, {
						headers: { Authorization: `Bearer ${token}` },
					}),
					fetch(`${API_BASE}/api/dex/status`, {
						headers: { Authorization: `Bearer ${token}` },
					}),
					fetch(`${API_BASE}/api/games`),
				]);
				if (pokeRes.ok && huntsRes.ok) {
					const pokeData: Pokemon[] = (await pokeRes.json()) || [];
					const huntsData: HuntDetail[] = (await huntsRes.json()) || [];
					setPokemon(pokeData);
					const caught = new Set<number>();
					for (const h of huntsData) {
						if (h.status === "completed") caught.add(h.pokemon_id);
					}
					setCaughtIds(caught);
					if (statusRes.ok) {
						const s: DexStatus = await statusRes.json();
						setBlocked({
							locked: new Set(s.locked_everywhere),
							notInGames: new Set(s.not_in_your_games),
						});
					}
				} else {
					showError("Failed to fetch Pokedex information.");
				}
				if (gamesRes.ok) {
					setGames((await gamesRes.json()) || []);
				}
			} catch (err: unknown) {
				showError(
					(err as Error).message || "Failed to fetch Pokedex information.",
				);
				console.error(err);
			} finally {
				setLoading(false);
			}
		};
		fetchData();
	}, [token]);

	// biome-ignore lint/correctness/useExhaustiveDependencies: showError is a context value that changes identity every render; including it would refetch the dex on every render
	useEffect(() => {
		localStorage.setItem(GAME_VIEW_KEY, gameView);
		if (gameView === "national") {
			setGameDex(null);
			return;
		}
		let cancelled = false;
		setGameDexLoading(true);
		fetch(`${API_BASE}/api/games/${gameView}/pokedex`)
			.then((res) => {
				if (!res.ok) throw new Error();
				return res.json();
			})
			.then((data: GamePokedexResponse) => {
				if (cancelled) return;
				// A game with no seeded rows comes back 200 with an empty list, which
				// would render an empty grid and 0/0. Treat it as a failure.
				if (!data.dexes?.length) throw new Error("no dex entries");
				setGameDex(data);
			})
			.catch(() => {
				if (cancelled) return;
				showError("No Pokédex data for that game yet — showing National.");
				setGameView("national");
			})
			.finally(() => {
				if (!cancelled) setGameDexLoading(false);
			});
		return () => {
			cancelled = true;
		};
		// eslint-disable-next-line react-hooks/exhaustive-deps
	}, [gameView]);

	if (loading) {
		return (
			<div
				className="page"
				style={{
					color: "var(--ink-3)",
					fontFamily: "var(--font-mono)",
					fontSize: 12,
				}}
			>
				Loading Pokédex…
			</div>
		);
	}

	const pokeById = new Map(pokemon.map((p) => [p.id, p]));
	const nationalTotal = pokemon.length || 1025;

	// A species can sit in more than one of a game's dexes with a different
	// number in each (Sword/Shield: 821 entries, 584 unique species), so the
	// headline and progress bar count unique species. The per-dex rows below
	// deliberately do not — an entry per dex is what those sections show.
	const gameSpecies = gameDex
		? new Set(gameDex.dexes.flatMap((d) => d.entries.map((e) => e.pokemon_id)))
		: null;

	const total = gameSpecies ? gameSpecies.size : nationalTotal;
	const caughtCount = gameSpecies
		? Array.from(gameSpecies).filter((id) => caughtIds.has(id)).length
		: caughtIds.size;
	const completionPct = total > 0 ? (caughtCount / total) * 100 : 0;

	// Both views are the same thing — an ordered list of titled sections of
	// cells — so they are normalized here and rendered once below. National
	// sections are generations numbered by national id; game sections are that
	// game's dexes numbered by their own entry_number.
	const sections = gameDex
		? gameDex.dexes.map((d) => ({
				key: d.slug,
				label: d.name,
				short: d.name,
				showNumber: true,
				entries: [...d.entries]
					.sort((a, b) => a.number - b.number)
					.map((e) => ({
						pokemonId: e.pokemon_id,
						number: e.number,
						state: e.shiny_locked ? "locked" : "missing",
					})),
			}))
		: GEN_RANGES.map(([gen, lo, hi]) => ({
				key: `gen-${gen}`,
				label: `Generation ${ROMAN[gen]}`,
				short: `Gen ${ROMAN[gen]}`,
				showNumber: false,
				entries: pokemon
					.filter((p) => p.id >= lo && p.id <= hi)
					.map((p) => ({
						pokemonId: p.id,
						number: p.id,
						state: blocked.locked.has(p.id)
							? "locked"
							: blocked.notInGames.has(p.id)
								? "notgames"
								: "missing",
					})),
			}));

	return (
		<div className="page">
			<HuntNextPanel
				onStart={(poke, route) => onStartHunt?.(poke, route)}
				onOpen={(id) => setDrawerId(id)}
			/>
			<div className="page-head">
				<div>
					<div className="sub">Workspace · Collection</div>
					<h1>Shiny Living Dex</h1>
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 11,
							color: "var(--ink-3)",
							marginTop: 8,
							letterSpacing: "0.04em",
						}}
					>
						{caughtCount} of {total} shinies · {completionPct.toFixed(1)}%
						complete
						<span style={{ color: "var(--ink-4)", marginLeft: 8 }}>
							(Click any Pokémon to view details)
						</span>
					</div>
				</div>
				<div className="ctas">
					<select
						className="btn"
						value={gameView}
						onChange={(e) => setGameView(e.target.value)}
						style={{ paddingRight: 20 }}
					>
						<option value="national">National</option>
						{games.map((g) => (
							<option key={g.id} value={g.id}>
								{g.title}
							</option>
						))}
					</select>
					<input
						className="input"
						placeholder="Search name or #…"
						value={search}
						onChange={(e) => setSearch(e.target.value)}
						style={{ width: 180 }}
					/>
					<div
						style={{
							display: "flex",
							gap: 6,
							background: "var(--bg-2)",
							border: "1px solid var(--line-1)",
							borderRadius: 8,
							padding: 3,
						}}
					>
						{(["all", "owned", "missing"] as const).map((f) => (
							<button
								key={f}
								onClick={() => setFilter(f)}
								className="btn ghost"
								style={{
									padding: "6px 12px",
									fontSize: 11.5,
									textTransform: "capitalize",
									background: filter === f ? "var(--bg-3)" : "transparent",
									color: filter === f ? "var(--ink-1)" : "var(--ink-3)",
									boxShadow:
										filter === f ? "inset 0 0 0 1px var(--line-2)" : "none",
								}}
							>
								{f}
							</button>
						))}
					</div>
				</div>
			</div>

			{/* Completion bar */}
			<div className="card" style={{ marginBottom: 20, padding: 18 }}>
				<div
					style={{
						display: "flex",
						alignItems: "center",
						justifyContent: "space-between",
						marginBottom: 10,
					}}
				>
					<div className="t-label">Completion progress</div>
					<div
						className="t-mono"
						style={{ fontSize: 12, color: "var(--gold)" }}
					>
						{caughtCount} / {total}
					</div>
				</div>
				<div
					style={{
						height: 6,
						background: "var(--bg-3)",
						borderRadius: 99,
						overflow: "hidden",
					}}
				>
					<div
						style={{
							height: "100%",
							width: `${completionPct}%`,
							background: "linear-gradient(90deg, var(--gold), #FFE08A)",
							borderRadius: 99,
						}}
					/>
				</div>
				<div
					style={{
						display: "flex",
						justifyContent: "space-between",
						marginTop: 10,
						fontFamily: "var(--font-mono)",
						fontSize: 10.5,
						color: "var(--ink-3)",
						letterSpacing: "0.04em",
					}}
				>
					{sections.map((s) => {
						const count = s.entries.filter((e) =>
							caughtIds.has(e.pokemonId),
						).length;
						return (
							<div key={s.key} style={{ textAlign: "center" }}>
								<div>{s.short}</div>
								<div
									style={{
										color: count > 0 ? "var(--gold)" : "var(--ink-4)",
										marginTop: 2,
									}}
								>
									{count}/{s.entries.length}
								</div>
							</div>
						);
					})}
				</div>
			</div>

			{gameDexLoading && (
				<div className="empty" style={{ marginBottom: 20 }}>
					Loading game Pokédex…
				</div>
			)}

			{/* One grid, driven by `sections` — per-dex for a game, per-generation for National */}
			{sections.map((s) => {
				const cells = s.entries
					.filter((e) =>
						matchesSearch(
							search,
							pokeById.get(e.pokemonId)?.name ?? "",
							e.number,
						),
					)
					.filter((e) => {
						const caught = caughtIds.has(e.pokemonId);
						if (filter === "owned") return caught;
						if (filter === "missing") return !caught;
						return true;
					});
				if (cells.length === 0) return null;
				const caughtInSection = s.entries.filter((e) =>
					caughtIds.has(e.pokemonId),
				).length;
				return (
					<div key={s.key}>
						<div className="gen-head">
							<span className="lbl">{s.label}</span>
							<span className="line" />
							<span className="count">
								<b>{caughtInSection}</b> / {s.entries.length}
							</span>
						</div>
						<div className="dex-grid">
							{cells.map((e) => {
								const p = pokeById.get(e.pokemonId);
								const caught = caughtIds.has(e.pokemonId);
								const label = p?.name ?? `#${e.number}`;
								return (
									<div
										key={`${s.key}-${e.pokemonId}`}
										className={`dex-cell ${caught ? "caught" : e.state}`}
										onClick={() => setDrawerId(e.pokemonId)}
										title={label}
									>
										<img
											src={getSpriteUrl(
												e.pokemonId,
												caught,
												caught ? p?.shiny_sprite_url : p?.sprite_url,
											)}
											alt={label}
											loading="lazy"
										/>
										{s.showNumber && (
											<span className="dex-num">{e.number}</span>
										)}
									</div>
								);
							})}
						</div>
					</div>
				);
			})}

			{drawerId !== null &&
				(() => {
					const p = pokemon.find((x) => x.id === drawerId);
					if (!p) return null;
					return (
						<DexDrawer
							pokemon={p}
							caught={caughtIds.has(p.id)}
							onClose={() => setDrawerId(null)}
							onCaughtChange={(id, isCaught) => {
								setCaughtIds((prev) => {
									const next = new Set(prev);
									if (isCaught) next.add(id);
									else next.delete(id);
									return next;
								});
							}}
							onStartHunt={(poke, route) => {
								setDrawerId(null);
								onStartHunt?.(poke, route);
							}}
							onHuntStarted={onHuntStarted}
						/>
					);
				})()}
		</div>
	);
};

export default Collection;
