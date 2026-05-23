import type React from "react";
import { useEffect, useMemo, useState } from "react";
import { useAuth } from "../context/AuthContext";
import { useNotification } from "../context/NotificationContext";
import { calculateOdds } from "../utils/odds";
import { getShowdownGif } from "../utils/pokemon";
import type { Pokemon, HuntMethod } from "../types/models";

interface Props {
	open: boolean;
	onClose: () => void;
	onGoToGames?: () => void;
}
import { SparkSm, IcClose, IcPlus } from "./ui/icons";
import { PokemonSearchStep } from "../features/new-hunt/PokemonSearchStep";
import { MethodPreview } from "../features/new-hunt/MethodPreview";

const NewHuntModal: React.FC<Props> = ({ open, onClose, onGoToGames }) => {
	const { token, userId } = useAuth();
	const { showError } = useNotification();
	const [step, setStep] = useState(1);
	const [search, setSearch] = useState("");
	const [options, setOptions] = useState<Pokemon[]>([]);
	const [selectedPokemon, setSelectedPokemon] = useState<Pokemon | null>(null);
	const [huntMethods, setHuntMethods] = useState<HuntMethod[]>([]);
	const [selectedMethod, setSelectedMethod] = useState<HuntMethod | null>(null);
	const [useCustomMethod, setUseCustomMethod] = useState(false);
	const [customMethodName, setCustomMethodName] = useState("");
	const [huntParams, setHuntParams] = useState<Record<string, any>>({});
	const [userGameCount, setUserGameCount] = useState<number | null>(null);
	const [userGames, setUserGames] = useState<
		{ game_id: number; has_shiny_charm: boolean }[]
	>([]);
	const [loadingSearch, setLoadingSearch] = useState(false);
	const [loadingEncounters, setLoadingEncounters] = useState(false);
	const [starting, setStarting] = useState(false);

	useEffect(() => {
		if (!open) {
			setStep(1);
			setSearch("");
			setOptions([]);
			setSelectedPokemon(null);
			setHuntMethods([]);
			setSelectedMethod(null);
			setUseCustomMethod(false);
			setCustomMethodName("");
			setHuntParams({});
		}
	}, [open]);

	// Pokémon search
	useEffect(() => {
		if (!open) return;
		const timer = setTimeout(async () => {
			setLoadingSearch(true);
			try {
				const res = await fetch(
					`http://localhost:8080/api/pokemon?q=${search}`,
				);
				if (res.ok) setOptions((await res.json()) || []);
			} catch (err: any) {
				showError(err.message || "Failed to search Pokemon.");
			}
			setLoadingSearch(false);
		}, 300);
		return () => clearTimeout(timer);
	}, [search, open]);

	// Hunt methods + user game count for selected Pokémon
	useEffect(() => {
		if (!selectedPokemon || !token || !userId) return;
		const fetchData = async () => {
			setLoadingEncounters(true);
			try {
				const [methodsRes, gamesRes] = await Promise.all([
					fetch(
						`http://localhost:8080/api/hunt-methods?pokemon_id=${selectedPokemon.id}`,
						{ headers: { Authorization: `Bearer ${token}` } },
					),
					fetch(`http://localhost:8080/api/user/${userId}/games`, {
						headers: { Authorization: `Bearer ${token}` },
					}),
				]);
				if (methodsRes.ok) {
					setHuntMethods((await methodsRes.json()) || []);
					setSelectedMethod(null);
				}
				if (gamesRes.ok) {
					const games = await gamesRes.json();
					setUserGames(games || []);
					setUserGameCount((games || []).length);
				}
			} catch (err: any) {
				showError(err.message || "Failed to fetch method information.");
			}
			setLoadingEncounters(false);
		};
		fetchData();
	}, [selectedPokemon, token, userId]);

	const recommended = useMemo(
		() => huntMethods.find((e) => e.is_recommended) ?? null,
		[huntMethods],
	);

	const getBaseOdds = (gameTitle: string) => {
		const lower = gameTitle.toLowerCase();
		if (
			lower.includes("red/blue") ||
			lower.includes("gold/silver") ||
			lower.includes("ruby/sapphire") ||
			lower.includes("firered") ||
			lower.includes("diamond/pearl") ||
			lower.includes("heartgold") ||
			lower.includes("black/white") ||
			lower.includes("black 2")
		) {
			return 8192;
		}
		return 4096;
	};

	const getOddsForMethod = (method: HuntMethod) => {
		const userGame = userGames.find((ug) => ug.game_id === method.game_id);
		const hasCharm = userGame?.has_shiny_charm ?? false;
		const base = getBaseOdds(method.game_title);
		const { denominator } = calculateOdds(
			method.formula_type,
			0, // starting encounters is 0
			hasCharm,
			base,
			method.base_rolls,
			method.charm_rolls,
		);
		return denominator;
	};

	const startHunt = async (method: HuntMethod) => {
		if (!selectedPokemon) return;
		setStarting(true);
		try {
			const res = await fetch("http://localhost:8080/api/hunts", {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({
					hunt_method_id: method.id,
					pokemon_id: selectedPokemon.id,
					game_id: method.game_id,
					method_name: method.method_name,
					hunt_parameters: huntParams,
				}),
			});
			if (res.ok) {
				onClose();
				window.location.reload();
			} else {
				const errText = await res.text();
				showError(errText || "Failed to start hunt.");
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
			const res = await fetch("http://localhost:8080/api/hunts", {
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
				const errText = await res.text();
				showError(errText || "Failed to start custom hunt.");
			}
		} catch (err: any) {
			showError(err.message || "Failed to start custom hunt.");
		}
		setStarting(false);
	};

	const handleStartSelected = () => {
		if (useCustomMethod) startCustomHunt();
		else if (selectedMethod) startHunt(selectedMethod);
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
										}}
									>
										{selectedPokemon.name}
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

							{loadingEncounters && (
								<div className="empty" style={{ padding: 20 }}>
									Loading methods…
								</div>
							)}

							{!loadingEncounters && recommended && (
								<div className="reco">
									<div className="lbl">
										<SparkSm size={9} color="var(--gold)" /> Recommended
									</div>
									<div
										className={`row ${selectedMethod?.id === recommended.id ? "sel" : ""}`}
										style={{
											cursor: "pointer",
											display: "flex",
											alignItems: "center",
											gap: 10,
											padding: "6px 8px",
											borderRadius: 8,
											border:
												selectedMethod?.id === recommended.id
													? "1px solid var(--blue-line)"
													: "1px solid transparent",
											background:
												selectedMethod?.id === recommended.id
													? "var(--blue-soft)"
													: "transparent",
										}}
										onClick={() => {
											setSelectedMethod(recommended);
											setUseCustomMethod(false);
										}}
									>
										<img
											src={selectedPokemon.sprite_url}
											alt=""
											style={{ imageRendering: "pixelated" }}
										/>
										<div style={{ flex: 1 }}>
											<div className="nm">{recommended.game_title}</div>
											<div className="meta">
												{recommended.method_name} · ~
												{recommended.avg_time_seconds}s/enc · 1/
												{getOddsForMethod(recommended).toLocaleString()} odds
											</div>
										</div>
										<button
											className="btn gold"
											onClick={(e) => {
												e.stopPropagation();
												startHunt(recommended);
											}}
										>
											Start <span style={{ opacity: 0.6 }}>→</span>
										</button>
									</div>
								</div>
							)}

							{!loadingEncounters &&
								huntMethods.filter((e) => e.id !== recommended?.id).length > 0 && (
									<>
										<div className="t-label" style={{ margin: "4px 0 8px" }}>
											All methods
										</div>
										<div className="opt-list">
											{huntMethods
												.filter((e) => e.id !== recommended?.id)
												.map((e) => (
													<div
														key={e.id}
														className={`opt-row ${selectedMethod?.id === e.id && !useCustomMethod ? "sel" : ""}`}
														onClick={() => {
															setSelectedMethod(e);
															setUseCustomMethod(false);
														}}
													>
														<div className="game">{e.game_title}</div>
														<div className="method">{e.method_name}</div>
														<div className="num">~{e.avg_time_seconds}s</div>
														<div
															className="num"
															style={{ color: "var(--gold)", fontWeight: 500 }}
														>
															1/{getOddsForMethod(e).toLocaleString()}
														</div>
													</div>
												))}
										</div>
									</>
								)}

							{!loadingEncounters &&
								huntMethods.length === 0 &&
								userGameCount === 0 && (
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

							{!loadingEncounters &&
								huntMethods.length === 0 &&
								userGameCount !== null &&
								userGameCount > 0 && (
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
											Try adding a game that includes it, or it may be
											shiny-locked.
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

							{!loadingEncounters && (
								<>
									<div className="t-label" style={{ margin: "12px 0 6px" }}>
										Custom method
									</div>
									<div
										className={`opt-row ${useCustomMethod ? "sel" : ""}`}
										onClick={() => {
											setUseCustomMethod(true);
											setSelectedMethod(null);
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
								selectedMethod={selectedMethod}
								useCustomMethod={useCustomMethod}
								customMethodName={customMethodName}
								gifUrl={gifUrl}
								huntParams={huntParams}
								setHuntParams={setHuntParams}
								getBaseOdds={getBaseOdds}
								getOddsForMethod={getOddsForMethod}
							/>

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
											: !selectedMethod)
									}
									onClick={handleStartSelected}
									style={
										(
											useCustomMethod
												? !customMethodName.trim()
												: !selectedMethod
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
