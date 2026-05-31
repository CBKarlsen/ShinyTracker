import type React from "react";
import { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";
import { useNotification } from "../context/NotificationContext";
import { API_BASE } from "../config";
import { getShowdownGif } from "../utils/pokemon";
import { defaultParamsFor } from "../utils/odds";
import type { Pokemon, PokemonRoute } from "../types/models";
import { IcClose, IcPlus } from "./ui/icons";
import { PokemonSearchStep } from "../features/new-hunt/PokemonSearchStep";
import { MethodPreview } from "../features/new-hunt/MethodPreview";
import { usePokemonRoute } from "../features/routes/usePokemonRoute";
import RouteList, { routeKey } from "../features/routes/RouteList";

interface Props {
	open: boolean;
	onClose: () => void;
	onGoToGames?: () => void;
	prefill?: { pokemon: Pokemon; route?: PokemonRoute } | null;
}

const NewHuntModal: React.FC<Props> = ({ open, onClose, onGoToGames, prefill }) => {
	const { token, userId } = useAuth();
	const { showError } = useNotification();
	const [step, setStep] = useState(1);
	const [search, setSearch] = useState("");
	const [options, setOptions] = useState<Pokemon[]>([]);
	const [selectedPokemon, setSelectedPokemon] = useState<Pokemon | null>(null);
	const [selectedRoute, setSelectedRoute] = useState<PokemonRoute | null>(null);
	const [useCustomMethod, setUseCustomMethod] = useState(false);
	const [customMethodName, setCustomMethodName] = useState("");
	const [huntParams, setHuntParams] = useState<Record<string, any>>({});
	const [userGameCount, setUserGameCount] = useState<number | null>(null);
	const [loadingSearch, setLoadingSearch] = useState(false);
	const [starting, setStarting] = useState(false);

	const { status, routes, loading: loadingRoutes } = usePokemonRoute(selectedPokemon?.id ?? null);

	const [recentPokemon, setRecentPokemon] = useState<Pokemon[]>([]);

	useEffect(() => {
		if (!open) {
			setStep(1);
			setSearch("");
			setOptions([]);
			setSelectedPokemon(null);
			setSelectedRoute(null);
			setUseCustomMethod(false);
			setCustomMethodName("");
			setHuntParams({});
			setRecentPokemon([]); // clear so stale chips don't flash on re-open
			return;
		}
		// Fetch recent hunts lazily when the modal opens.
		if (!token) return;
		const controller = new AbortController();
		fetch(`${API_BASE}/api/hunts`, {
			headers: { Authorization: `Bearer ${token}` },
			signal: controller.signal,
		})
			.then((r) => (r.ok ? r.json() : Promise.reject()))
			.then((hunts: Array<{ pokemon_id: number; pokemon_name: string; updated_at?: string; created_at?: string }>) => {
				const seen = new Set<number>();
				const recent: Pokemon[] = [];
				// Sort by most-recent first (updated_at preferred, fallback created_at).
				const sorted = [...hunts].sort((a, b) => {
					const ta = new Date(a.updated_at ?? a.created_at ?? 0).getTime();
					const tb = new Date(b.updated_at ?? b.created_at ?? 0).getTime();
					return tb - ta;
				});
				for (const h of sorted) {
					if (seen.has(h.pokemon_id)) continue;
					seen.add(h.pokemon_id);
					// /api/hunts has no sprite_url on the row; PokemonSearchStep falls back.
					recent.push({ id: h.pokemon_id, name: h.pokemon_name, sprite_url: "" });
					if (recent.length >= 6) break;
				}
				setRecentPokemon(recent);
			})
			.catch(() => {
				if (!controller.signal.aborted) setRecentPokemon([]);
			});
		return () => controller.abort();
	}, [open, token]);

	// When opened with prefill, jump to step 2 with the target Pokémon pre-selected.
	useEffect(() => {
		if (open && prefill) {
			setSelectedPokemon(prefill.pokemon);
			setStep(2);
		}
	}, [open, prefill]);

	// Default selection — only when no prefill is active (or prefill has no route) so it doesn't fight the prefill effect.
	// selectedRoute intentionally omitted: sets only the initial default.
	useEffect(() => {
		const prefillHasRoute = !!prefill?.route;
		if (!prefillHasRoute && !useCustomMethod && routes.length > 0 && !selectedRoute) {
			setSelectedRoute(routes[0]);
			setHuntParams(defaultParamsFor(routes[0].formula_type));
		}
	}, [routes, prefill, useCustomMethod, selectedRoute]); // eslint-disable-line react-hooks/exhaustive-deps

	// Once routes load, select the prefill route by key (only when a route was provided).
	useEffect(() => {
		if (prefill?.route && routes.length > 0) {
			const r =
				routes.find((r) => routeKey(r) === routeKey(prefill.route!)) ??
				prefill.route!;
			setSelectedRoute(r);
			setHuntParams(defaultParamsFor(r.formula_type));
		}
	}, [prefill, routes]); // eslint-disable-line react-hooks/exhaustive-deps

	// Pokémon search
	useEffect(() => {
		if (!open) return;
		const timer = setTimeout(async () => {
			setLoadingSearch(true);
			try {
				const res = await fetch(`${API_BASE}/api/pokemon?q=${search}`);
				if (res.ok) setOptions((await res.json()) || []);
			} catch (err: any) {
				showError(err.message || "Failed to search Pokemon.");
			}
			setLoadingSearch(false);
		}, 300);
		return () => clearTimeout(timer);
	}, [search, open]);

	// Fetch user game count (needed only to determine "no games" empty state).
	useEffect(() => {
		if (!selectedPokemon || !token || !userId) return;
		fetch(`${API_BASE}/api/user/${userId}/games`, {
			headers: { Authorization: `Bearer ${token}` },
		})
			.then((r) => (r.ok ? r.json() : Promise.reject()))
			.then((games) => setUserGameCount((games || []).length))
			.catch(() => setUserGameCount(null));
	}, [selectedPokemon, token, userId]);

	const startHunt = async (route: PokemonRoute) => {
		if (!selectedPokemon) return;
		setStarting(true);
		try {
			const res = await fetch(`${API_BASE}/api/hunts`, {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({
					hunt_method_id: route.method_id,
					pokemon_id: route.evolve_from ? route.evolve_from.pokemon_id : selectedPokemon.id,
					game_id: route.game_id,
					method_name: route.method_name,
					hunt_parameters: huntParams,
				}),
			});
			if (res.ok) {
				onClose();
				window.location.reload();
			} else {
				showError((await res.text()) || "Failed to start hunt.");
			}
		} catch (err: any) {
			showError(err.message || "Failed to start hunt.");
		}
		setStarting(false);
	};

	const startCustomHunt = async () => {
		if (!selectedPokemon || !customMethodName.trim()) return;
		setStarting(true);
		try {
			const res = await fetch(`${API_BASE}/api/hunts`, {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({
					pokemon_id: selectedPokemon.id,
					custom_method_name: customMethodName.trim(),
				}),
			});
			if (res.ok) {
				onClose();
				window.location.reload();
			} else {
				showError((await res.text()) || "Failed to start custom hunt.");
			}
		} catch (err: any) {
			showError(err.message || "Failed to start custom hunt.");
		}
		setStarting(false);
	};

	const handleStartSelected = () => {
		if (useCustomMethod) startCustomHunt();
		else if (selectedRoute) startHunt(selectedRoute);
	};

	if (!open) return null;

	const gifUrl = selectedPokemon ? getShowdownGif(selectedPokemon.name) : "";

	return (
		<div className="scrim" onClick={onClose}>
			<div className="drawer" onClick={(e) => e.stopPropagation()}>
				<div className="drawer-head">
					<h2>Start a new hunt</h2>
					<div
						style={{
							display: "flex",
							alignItems: "center",
							gap: 4,
							marginLeft: 12,
						}}
					>
						{[1, 2].map((s) => (
							<span
								key={s}
								style={{
									width: 22,
									height: 5,
									borderRadius: 99,
									background: s <= step ? "var(--gold)" : "var(--bg-3)",
									transition: "background .2s ease",
								}}
							/>
						))}
					</div>
					<button className="close" onClick={onClose}>
						<IcClose />
					</button>
				</div>

				<div className="drawer-body">
					{step === 1 && (
						<PokemonSearchStep
							search={search}
							setSearch={setSearch}
							loadingSearch={loadingSearch}
							options={options}
							recentPokemon={recentPokemon}
							onSelect={(p) => {
								setSelectedPokemon(p);
								setStep(2);
							}}
						/>
					)}

					{/* Step 2: Method */}
					{step === 2 && selectedPokemon && (
						<div>
							<div
								style={{
									display: "flex",
									alignItems: "center",
									gap: 14,
									marginBottom: 18,
								}}
							>
								<div
									style={{
										width: 64,
										height: 64,
										background: "var(--bg-2)",
										border: "1px solid var(--line-1)",
										borderRadius: 12,
										display: "grid",
										placeItems: "center",
										position: "relative",
										overflow: "hidden",
									}}
								>
									<div
										style={{
											position: "absolute",
											inset: 0,
											background:
												"radial-gradient(circle at 30% 30%, var(--gold-soft), transparent 70%)",
										}}
									/>
									<img
										src={gifUrl}
										alt={selectedPokemon.name}
										style={{
											width: 56,
											height: 56,
											imageRendering: "pixelated",
											position: "relative",
											objectFit: "contain",
										}}
										onError={(e) => {
											e.currentTarget.onerror = null;
											e.currentTarget.src = selectedPokemon.sprite_url;
										}}
									/>
								</div>
								<div>
									<div className="t-label">Hunting</div>
									<div
										style={{
											fontFamily: "var(--font-display)",
											fontSize: 22,
											fontWeight: 600,
											letterSpacing: "-0.02em",
											textTransform: "capitalize",
											display: "flex",
											alignItems: "center",
											gap: 8,
										}}
									>
										{selectedPokemon.name}
										{(selectedPokemon.is_legendary || selectedPokemon.is_mythical) && (
											<div
												style={{
													fontSize: 10,
													textTransform: "uppercase",
													letterSpacing: "0.06em",
													fontWeight: 700,
													background: "var(--gold-soft)",
													color: "var(--gold)",
													border: "1px solid var(--gold-line)",
													padding: "2px 6px",
													borderRadius: 4,
													fontFamily: "var(--font-mono)",
												}}
											>
												Legendary
											</div>
										)}
									</div>
								</div>
								<button
									className="btn ghost"
									style={{ marginLeft: "auto", fontSize: 11.5 }}
									onClick={() => setStep(1)}
								>
									Change
								</button>
							</div>

							{loadingRoutes && (
								<div className="empty" style={{ padding: 20 }}>
									Loading methods…
								</div>
							)}

							{!loadingRoutes && routes.length > 0 && (
								<RouteList
									routes={routes}
									variant="select"
									selectedKey={selectedRoute && !useCustomMethod ? routeKey(selectedRoute) : undefined}
									onRouteClick={(r) => {
										setSelectedRoute(r);
										setUseCustomMethod(false);
										setHuntParams(defaultParamsFor(r.formula_type));
									}}
								/>
							)}

							{!loadingRoutes && userGameCount === 0 && routes.length === 0 && (
								<div
									className="empty"
									style={{ textAlign: "center", padding: "20px 0" }}
								>
									<div style={{ marginBottom: 6 }}>
										You haven't added any games yet.
									</div>
									<div className="t-label" style={{ marginBottom: 14 }}>
										Add a game to your library to see available hunt methods.
									</div>
									{onGoToGames && (
										<button className="btn gold" onClick={onGoToGames}>
											Go to Game Library →
										</button>
									)}
								</div>
							)}

							{!loadingRoutes && status === "not_in_your_games" && userGameCount !== null && userGameCount > 0 && (
								<div
									className="empty"
									style={{ textAlign: "center", padding: "20px 0" }}
								>
									<div
										style={{ marginBottom: 6, textTransform: "capitalize" }}
									>
										{selectedPokemon.name} isn't available in your games.
									</div>
									<div className="t-label" style={{ marginBottom: 14 }}>
										Try adding a game that includes it, or it may be shiny-locked.
									</div>
									{onGoToGames && (
										<button
											className="btn ghost"
											onClick={onGoToGames}
											style={{ fontSize: 12 }}
										>
											Manage games →
										</button>
									)}
								</div>
							)}

							{!loadingRoutes && status === "locked_everywhere" && (
								<div
									className="empty"
									style={{ textAlign: "center", padding: "20px 0", textTransform: "capitalize" }}
								>
									{selectedPokemon.name} is shiny-locked in every game it appears in — obtain it by trading or transferring from Pokémon HOME.
								</div>
							)}

							{!loadingRoutes && status === "available" && routes.length === 0 && (
								<div className="empty" style={{ textAlign: "center", padding: "20px 0" }}>
									Available in your games, but no hunt method recorded yet.
								</div>
							)}

							{!loadingRoutes && (
								<>
									<div className="t-label" style={{ margin: "12px 0 6px" }}>
										Custom method
									</div>
									<div
										className={`opt-row ${useCustomMethod ? "sel" : ""}`}
										onClick={() => {
											setUseCustomMethod(true);
											setSelectedRoute(null);
										}}
										style={{ alignItems: "center", gap: 8 }}
									>
										<div className="method" style={{ flex: 1 }}>
											Use custom method
										</div>
										<div className="t-label" style={{ fontSize: 11 }}>
											no odds data
										</div>
									</div>
									{useCustomMethod && (
										<input
											className="input"
											placeholder="e.g. Chain fishing, DexNav, Outbreak…"
											value={customMethodName}
											onChange={(e) => setCustomMethodName(e.target.value)}
											style={{ marginTop: 8 }}
											autoFocus
										/>
									)}
								</>
							)}

							{/* Inline Preview Section */}
							<MethodPreview
								selectedPokemon={selectedPokemon}
								selectedRoute={selectedRoute}
								useCustomMethod={useCustomMethod}
								customMethodName={customMethodName}
								gifUrl={gifUrl}
								huntParams={huntParams}
								setHuntParams={setHuntParams}
							/>

							{selectedRoute?.evolve_from && !useCustomMethod && (
								<div className="t-label" style={{ marginTop: 10 }}>
									You'll hunt {selectedRoute.evolve_from.name}, then evolve into {selectedPokemon.name}.
								</div>
							)}

							<div
								style={{
									display: "flex",
									gap: 8,
									marginTop: 18,
									justifyContent: "flex-end",
								}}
							>
								<button className="btn ghost" onClick={onClose}>
									Cancel
								</button>
								<button
									className="btn gold"
									disabled={
										starting ||
										(useCustomMethod
											? !customMethodName.trim()
											: !selectedRoute)
									}
									onClick={handleStartSelected}
									style={
										(
											useCustomMethod
												? !customMethodName.trim()
												: !selectedRoute
										)
											? { opacity: 0.4, pointerEvents: "none" }
											: {}
									}
								>
									{starting ? (
										"Starting…"
									) : (
										<>
											<IcPlus /> Start hunt
										</>
									)}
								</button>
							</div>
						</div>
					)}
				</div>
			</div>
		</div>
	);
};

export default NewHuntModal;
