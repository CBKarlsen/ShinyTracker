import type React from "react";
import { useEffect, useState } from "react";
import { API_BASE } from "../config";
import { useAuth } from "../context/AuthContext";
import { useNotification } from "../context/NotificationContext";
import { shinyCharmAvailable } from "../utils/games";
import { ConfirmDialog } from "./ui/ConfirmDialog";
import { SparkSm } from "./ui/icons";

interface Game {
	id: number;
	title: string;
	generation: number;
}

interface UserGame {
	game_id: number;
	has_shiny_charm: boolean;
}

const GEN_NAMES: Record<number, string> = {
	1: "Generation I",
	2: "Generation II",
	3: "Generation III",
	4: "Generation IV",
	5: "Generation V",
	6: "Generation VI",
	7: "Generation VII",
	8: "Generation VIII",
	9: "Generation IX",
};

const ROMAN = ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"];

function fmtNum(n: number) {
	return n.toLocaleString("en-US");
}

const CollectionManager: React.FC = () => {
	const { token, userId } = useAuth();
	const { showError } = useNotification();
	const [games, setGames] = useState<Game[]>([]);
	const [userGames, setUserGames] = useState<UserGame[]>([]);
	const [loading, setLoading] = useState(true);
	const [pendingRemoveGameId, setPendingRemoveGameId] = useState<number | null>(
		null,
	);

	useEffect(() => {
		const fetchData = async () => {
			try {
				const [gamesRes, userGamesRes] = await Promise.all([
					fetch(`${API_BASE}/api/games`),
					fetch(`${API_BASE}/api/user/${userId}/games`, {
						headers: { Authorization: `Bearer ${token}` },
					}),
				]);
				if (gamesRes.ok && userGamesRes.ok) {
					setGames(await gamesRes.json());
					setUserGames((await userGamesRes.json()) || []);
				} else {
					showError("Failed to fetch game library information.");
				}
			} catch (err: any) {
				showError(err.message || "Failed to fetch game library information.");
				console.error(err);
			} finally {
				setLoading(false);
			}
		};
		fetchData();
	}, [token, userId]);

	const doRemoveGame = async (gameId: number) => {
		setPendingRemoveGameId(null);
		setUserGames((prev) => prev.filter((ug) => ug.game_id !== gameId));
		try {
			const res = await fetch(
				`${API_BASE}/api/user/${userId}/games/${gameId}`,
				{
					method: "DELETE",
					headers: { Authorization: `Bearer ${token}` },
				},
			);
			if (!res.ok) throw new Error("Could not remove game ownership.");
		} catch (err: any) {
			setUserGames((prev) => [
				...prev,
				{ game_id: gameId, has_shiny_charm: false },
			]);
			showError(err.message || "Failed to remove game.");
		}
	};

	const handleOwnershipToggle = async (gameId: number, isOwned: boolean) => {
		if (isOwned) {
			setPendingRemoveGameId(gameId);
			return;
		}
		// Add path (not destructive — no confirmation needed).
		setUserGames((prev) => [
			...prev,
			{ game_id: gameId, has_shiny_charm: false },
		]);
		try {
			const res = await fetch(
				`${API_BASE}/api/user/${userId}/games/${gameId}`,
				{
					method: "POST",
					headers: {
						"Content-Type": "application/json",
						Authorization: `Bearer ${token}`,
					},
					body: JSON.stringify({ has_shiny_charm: false }),
				},
			);
			if (!res.ok) throw new Error("Could not add game ownership.");
		} catch (err: any) {
			setUserGames((prev) => prev.filter((ug) => ug.game_id !== gameId));
			showError(err.message || "Failed to add game.");
		}
	};

	const handleCharmToggle = async (
		e: React.MouseEvent,
		gameId: number,
		currentCharm: boolean,
	) => {
		e.stopPropagation();
		const newCharm = !currentCharm;
		setUserGames((prev) =>
			prev.map((ug) =>
				ug.game_id === gameId ? { ...ug, has_shiny_charm: newCharm } : ug,
			),
		);
		try {
			const res = await fetch(
				`${API_BASE}/api/user/${userId}/games/${gameId}`,
				{
					method: "POST",
					headers: {
						"Content-Type": "application/json",
						Authorization: `Bearer ${token}`,
					},
					body: JSON.stringify({ has_shiny_charm: newCharm }),
				},
			);
			if (!res.ok) throw new Error("Could not update Shiny Charm status.");
		} catch (err: any) {
			setUserGames((prev) =>
				prev.map((ug) =>
					ug.game_id === gameId ? { ...ug, has_shiny_charm: currentCharm } : ug,
				),
			);
			showError(err.message || "Failed to toggle Shiny Charm.");
		}
	};

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
				Loading games…
			</div>
		);
	}

	const owned = userGames.length;
	const charms = userGames.filter((ug) => ug.has_shiny_charm).length;
	const byGen = games.reduce<Record<number, Game[]>>((acc, g) => {
		(acc[g.generation] ??= []).push(g);
		return acc;
	}, {});
	const generations = Object.keys(byGen)
		.map(Number)
		.sort((a, b) => a - b);

	return (
		<div className="page">
			<div className="page-head">
				<div>
					<div className="sub">Workspace · Library</div>
					<h1>Game Library</h1>
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 11,
							color: "var(--ink-3)",
							marginTop: 8,
							letterSpacing: "0.04em",
						}}
					>
						{owned} games owned · {charms} shiny charms collected
					</div>
				</div>
			</div>

			<div className="stat-row" style={{ marginBottom: 20 }}>
				<div className="stat-tile">
					<div className="t-label">Games Owned</div>
					<div className="v">
						{owned}
						<span className="unit">/ {games.length}</span>
					</div>
				</div>
				<div className="stat-tile">
					<div className="t-label">Shiny Charms</div>
					<div className="v" style={{ color: "var(--gold)" }}>
						{fmtNum(charms)}
					</div>
				</div>
				<div className="stat-tile">
					<div className="t-label">Charm-Eligible</div>
					<div className="v">
						{userGames.filter((ug) => shinyCharmAvailable(ug.game_id)).length}
						<span className="unit">
							/ {games.filter((g) => shinyCharmAvailable(g.id)).length}
						</span>
					</div>
				</div>
				<div className="stat-tile">
					<div className="t-label">Generations</div>
					<div className="v">
						{
							generations.filter((gen) =>
								byGen[gen].some((g) =>
									userGames.some((ug) => ug.game_id === g.id),
								),
							).length
						}
						<span className="unit">/ 9</span>
					</div>
				</div>
			</div>

			{generations.map((gen) => {
				const genOwned = byGen[gen].filter((g) =>
					userGames.some((ug) => ug.game_id === g.id),
				).length;
				return (
					<div key={gen} style={{ marginBottom: 18 }}>
						<div className="gen-head">
							<span className="lbl">
								{GEN_NAMES[gen] ?? `Generation ${gen}`}
							</span>
							<span className="line" />
							<span className="count">
								<b>{genOwned}</b> / {byGen[gen].length}
							</span>
						</div>
						<div className="game-grid">
							{byGen[gen].map((g) => {
								const ug = userGames.find((u) => u.game_id === g.id);
								const isOwned = !!ug;
								const hasCharm = ug?.has_shiny_charm ?? false;
								const charmSupported = shinyCharmAvailable(g.id);

								return (
									<div
										key={g.id}
										className={`game-card ${isOwned ? "owned" : "uowned"}`}
										onClick={() => handleOwnershipToggle(g.id, isOwned)}
									>
										<div className="ttl">{g.title}</div>
										<div className="gen">
											Gen {ROMAN[g.generation]} ·{" "}
											{isOwned ? "Owned" : "Click to add"}
										</div>
										{charmSupported ? (
											<button
												className={`charm-toggle ${hasCharm ? "active" : ""} ${!isOwned ? "disabled" : ""}`}
												onClick={(e) => handleCharmToggle(e, g.id, hasCharm)}
												title={
													hasCharm ? "Remove Shiny Charm" : "Add Shiny Charm"
												}
											>
												<SparkSm size={11} />
											</button>
										) : isOwned ? (
											<button
												className="charm-toggle disabled"
												onClick={(e) => e.stopPropagation()}
												title="Shiny Charm doesn't exist in this game"
												disabled
												style={{ opacity: 0.3, cursor: "not-allowed" }}
											>
												<SparkSm size={11} />
											</button>
										) : null}
									</div>
								);
							})}
						</div>
					</div>
				);
			})}

			<ConfirmDialog
				open={pendingRemoveGameId !== null}
				title="Remove game?"
				message="Are you sure you want to remove this game from your library? Any active hunts using this game will lose their method data."
				confirmLabel="Remove"
				cancelLabel="Cancel"
				danger
				onConfirm={() => {
					if (pendingRemoveGameId !== null) doRemoveGame(pendingRemoveGameId);
				}}
				onCancel={() => setPendingRemoveGameId(null)}
			/>
		</div>
	);
};

export default CollectionManager;
