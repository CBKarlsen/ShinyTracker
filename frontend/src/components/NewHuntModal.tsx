import type React from "react";
import { useEffect, useMemo, useState } from "react";
import { useAuth } from "../context/AuthContext";
import { getShowdownGif } from "../utils/pokemon";

interface Pokemon {
	id: number;
	name: string;
	sprite_url: string;
}

interface HuntMethod {
	id: number;
	pokemon_id: number;
	game_id: number;
	game_title: string;
	method_name: string;
	avg_time_seconds: number;
	base_rolls: number;
	charm_rolls: number;
	is_recommended: boolean;
}

interface Props {
	open: boolean;
	onClose: () => void;
	onGoToGames?: () => void;
}

const SparkSm = ({ size = 9, color }: { size?: number; color?: string }) => (
	<svg viewBox="0 0 12 12" width={size} height={size} aria-hidden>
		<path d="M6 0 L7 5 L12 6 L7 7 L6 12 L5 7 L0 6 L5 5 Z" fill={color || "currentColor"} />
	</svg>
);

const IcClose = () => (
	<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="1.5">
		<path d="M3 3l10 10M13 3L3 13" />
	</svg>
);

const IcPlus = () => (
	<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" strokeWidth="2">
		<path d="M8 3v10M3 8h10" />
	</svg>
);

const NewHuntModal: React.FC<Props> = ({ open, onClose, onGoToGames }) => {
	const { token, userId } = useAuth();
	const [step, setStep] = useState(1);
	const [search, setSearch] = useState("");
	const [options, setOptions] = useState<Pokemon[]>([]);
	const [selectedPokemon, setSelectedPokemon] = useState<Pokemon | null>(null);
	const [huntMethods, setHuntMethods] = useState<HuntMethod[]>([]);
	const [selectedMethod, setSelectedMethod] = useState<HuntMethod | null>(null);
	const [userGameCount, setUserGameCount] = useState<number | null>(null);
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
		}
	}, [open]);

	// Pokémon search
	useEffect(() => {
		if (!open) return;
		const timer = setTimeout(async () => {
			setLoadingSearch(true);
			try {
				const res = await fetch(`http://localhost:8080/api/pokemon?q=${search}`);
				if (res.ok) setOptions((await res.json()) || []);
			} catch { /* ignore */ }
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
					fetch(
						`http://localhost:8080/api/user/${userId}/games`,
						{ headers: { Authorization: `Bearer ${token}` } },
					),
				]);
				if (methodsRes.ok) {
					setHuntMethods((await methodsRes.json()) || []);
					setSelectedMethod(null);
				}
				if (gamesRes.ok) {
					const games = await gamesRes.json();
					setUserGameCount((games || []).length);
				}
			} catch { /* ignore */ }
			setLoadingEncounters(false);
		};
		fetchData();
	}, [selectedPokemon, token, userId]);

	const recommended = useMemo(
		() => huntMethods.find((e) => e.is_recommended) ?? null,
		[huntMethods],
	);

	const startHunt = async (method: HuntMethod) => {
		if (!selectedPokemon) return;
		setStarting(true);
		try {
			const res = await fetch("http://localhost:8080/api/hunts", {
				method: "POST",
				headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
				body: JSON.stringify({
					hunt_method_id: method.id,
					pokemon_id: selectedPokemon.id,
					method_name: method.method_name,
				}),
			});
			if (res.ok) {
				onClose();
				window.location.reload();
			}
		} catch { /* ignore */ }
		setStarting(false);
	};

	const handleStartSelected = () => {
		if (selectedMethod) startHunt(selectedMethod);
	};

	if (!open) return null;

	const gifUrl = selectedPokemon ? getShowdownGif(selectedPokemon.name) : "";
	const baseOdds = 4096;

	return (
		<div className="scrim" onClick={onClose}>
			<div className="drawer" onClick={(e) => e.stopPropagation()}>
				<div className="drawer-head">
					<h2>Start a new hunt</h2>
					<div style={{ display: "flex", alignItems: "center", gap: 4, marginLeft: 12 }}>
						{[1, 2, 3].map((s) => (
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
					{/* Step 1: Pokémon */}
					{step === 1 && (
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
									<div className="empty" style={{ padding: 16 }}>Searching…</div>
								)}
								{!loadingSearch && options.length === 0 && (
									<div className="empty">
										{search.length > 0 ? "No matches" : "Type to search"}
									</div>
								)}
								{options.map((p) => (
									<div
										key={p.id}
										className="row"
										onClick={() => {
											setSelectedPokemon(p);
											setStep(2);
										}}
									>
										<img
											src={p.sprite_url || `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${p.id}.png`}
											alt={p.name}
										/>
										<div className="nm">{p.name}</div>
										<div className="id">#{String(p.id).padStart(4, "0")}</div>
									</div>
								))}
							</div>
						</div>
					)}

					{/* Step 2: Method */}
					{step === 2 && selectedPokemon && (
						<div>
							<div style={{ display: "flex", alignItems: "center", gap: 14, marginBottom: 18 }}>
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
											background: "radial-gradient(circle at 30% 30%, var(--gold-soft), transparent 70%)",
										}}
									/>
									<img
										src={gifUrl}
										alt={selectedPokemon.name}
										style={{ width: 56, height: 56, imageRendering: "pixelated", position: "relative", objectFit: "contain" }}
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
								<div className="empty" style={{ padding: 20 }}>Loading methods…</div>
							)}

							{!loadingEncounters && recommended && (
								<div className="reco">
									<div className="lbl">
										<SparkSm size={9} color="var(--gold)" /> Recommended
									</div>
									<div className="row">
										<img
											src={selectedPokemon.sprite_url}
											alt=""
											style={{ imageRendering: "pixelated" }}
										/>
										<div style={{ flex: 1 }}>
											<div className="nm">{recommended.game_title}</div>
											<div className="meta">
												{recommended.method_name} · ~{recommended.avg_time_seconds}s/enc · 1/
												{Math.floor(baseOdds / (recommended.base_rolls + recommended.charm_rolls))} odds w/ charm
											</div>
										</div>
										<button
											className="btn gold"
											onClick={() => {
												setSelectedMethod(recommended);
												setStep(3);
											}}
										>
											Start <span style={{ opacity: 0.6 }}>→</span>
										</button>
									</div>
								</div>
							)}

							{!loadingEncounters && huntMethods.filter((e) => !e.is_recommended).length > 0 && (
								<>
									<div className="t-label" style={{ margin: "4px 0 8px" }}>
										All methods
									</div>
									<div className="opt-list">
										{huntMethods
											.filter((e) => !e.is_recommended)
											.map((e) => (
												<div
													key={e.id}
													className={`opt-row ${selectedMethod?.id === e.id ? "sel" : ""}`}
													onClick={() => setSelectedMethod(e)}
												>
													<div className="game">{e.game_title}</div>
													<div className="method">{e.method_name}</div>
													<div className="num">~{e.avg_time_seconds}s</div>
													<div className="num">{e.base_rolls}r</div>
												</div>
											))}
									</div>
								</>
							)}

							{!loadingEncounters && huntMethods.length === 0 && userGameCount === 0 && (
								<div className="empty" style={{ textAlign: "center", padding: "20px 0" }}>
									<div style={{ marginBottom: 6 }}>You haven't added any games yet.</div>
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

							{!loadingEncounters && huntMethods.length === 0 && userGameCount !== null && userGameCount > 0 && (
								<div className="empty" style={{ textAlign: "center", padding: "20px 0" }}>
									<div style={{ marginBottom: 6, textTransform: "capitalize" }}>
										{selectedPokemon.name} isn't available in your games.
									</div>
									<div className="t-label" style={{ marginBottom: 14 }}>
										Try adding a game that includes it, or it may be shiny-locked.
									</div>
									{onGoToGames && (
										<button className="btn ghost" onClick={onGoToGames} style={{ fontSize: 12 }}>
											Manage games →
										</button>
									)}
								</div>
							)}

							<div
								style={{ display: "flex", gap: 8, marginTop: 18, justifyContent: "flex-end" }}
							>
								<button className="btn ghost" onClick={onClose}>
									Cancel
								</button>
								<button
									className="btn gold"
									disabled={!selectedMethod}
									onClick={() => selectedMethod && setStep(3)}
									style={!selectedMethod ? { opacity: 0.4, pointerEvents: "none" } : {}}
								>
									Configure →
								</button>
							</div>
						</div>
					)}

					{/* Step 3: Confirm */}
					{step === 3 && selectedPokemon && selectedMethod && (
						<div>
							<div className="t-label" style={{ marginBottom: 14 }}>
								Confirm hunt
							</div>
							<div
								style={{
									padding: 16,
									background: "var(--bg-2)",
									border: "1px solid var(--line-1)",
									borderRadius: 12,
									marginBottom: 16,
								}}
							>
								<div style={{ display: "flex", gap: 14, alignItems: "center" }}>
									<img
										src={gifUrl}
										alt={selectedPokemon.name}
										style={{ width: 72, height: 72, imageRendering: "pixelated", objectFit: "contain" }}
										onError={(e) => {
											e.currentTarget.onerror = null;
											e.currentTarget.src = selectedPokemon.sprite_url;
										}}
									/>
									<div>
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
										<div
											style={{
												fontFamily: "var(--font-mono)",
												fontSize: 11,
												color: "var(--ink-3)",
												marginTop: 4,
											}}
										>
											{selectedMethod.game_title} · {selectedMethod.method_name}
										</div>
									</div>
								</div>
								<div
									style={{
										display: "grid",
										gridTemplateColumns: "1fr 1fr 1fr",
										gap: 8,
										marginTop: 16,
										paddingTop: 16,
										borderTop: "1px solid var(--line-1)",
									}}
								>
									<div>
										<div className="t-label">Base odds</div>
										<div
											className="t-mono"
											style={{ fontSize: 14, marginTop: 2 }}
										>
											1 / {baseOdds.toLocaleString()}
										</div>
									</div>
									<div>
										<div className="t-label">w/ Charm</div>
										<div
											className="t-mono"
											style={{ fontSize: 14, marginTop: 2, color: "var(--gold)" }}
										>
											1 /{" "}
											{Math.floor(
												baseOdds /
													(selectedMethod.base_rolls + selectedMethod.charm_rolls),
											).toLocaleString()}
										</div>
									</div>
									<div>
										<div className="t-label">ETA expected</div>
										<div className="t-mono" style={{ fontSize: 14, marginTop: 2 }}>
											~
											{Math.round(
												(baseOdds /
													(selectedMethod.base_rolls + selectedMethod.charm_rolls)) *
													selectedMethod.avg_time_seconds /
													3600,
											)}
											h
										</div>
									</div>
								</div>
							</div>
							<div
								style={{ display: "flex", gap: 8, justifyContent: "flex-end" }}
							>
								<button className="btn ghost" onClick={() => setStep(2)}>
									Back
								</button>
								<button
									className="btn gold"
									onClick={handleStartSelected}
									disabled={starting}
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
