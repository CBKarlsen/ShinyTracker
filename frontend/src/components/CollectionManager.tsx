import type React from "react";
import { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";

interface Game {
	id: number;
	title: string;
	generation: number;
}

interface UserGame {
	game_id: number;
	has_shiny_charm: boolean;
}

const supportsShinyCharm = (game: Game): boolean => {
	if (game.generation >= 6) return true;
	if (game.generation === 5 && game.title.includes("Black 2")) return true;
	return false;
};

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

const SparkSm = ({ size = 11 }: { size?: number }) => (
	<svg viewBox="0 0 12 12" width={size} height={size} aria-hidden>
		<path d="M6 0 L7 5 L12 6 L7 7 L6 12 L5 7 L0 6 L5 5 Z" fill="currentColor" />
	</svg>
);

function fmtNum(n: number) {
	return n.toLocaleString("en-US");
}

const CollectionManager: React.FC = () => {
	const { token, userId } = useAuth();
	const [games, setGames] = useState<Game[]>([]);
	const [userGames, setUserGames] = useState<UserGame[]>([]);
	const [loading, setLoading] = useState(true);

	useEffect(() => {
		const fetchData = async () => {
			try {
				const [gamesRes, userGamesRes] = await Promise.all([
					fetch("http://localhost:8080/api/games"),
					fetch(`http://localhost:8080/api/user/${userId}/games`, {
						headers: { Authorization: `Bearer ${token}` },
					}),
				]);
				if (gamesRes.ok && userGamesRes.ok) {
					setGames(await gamesRes.json());
					setUserGames((await userGamesRes.json()) || []);
				}
			} catch (err) {
				console.error(err);
			} finally {
				setLoading(false);
			}
		};
		fetchData();
	}, [token, userId]);

	const handleOwnershipToggle = async (gameId: number, isOwned: boolean) => {
		if (isOwned) {
			setUserGames((prev) => prev.filter((ug) => ug.game_id !== gameId));
			try {
				await fetch(`http://localhost:8080/api/user/${userId}/games/${gameId}`, {
					method: "DELETE",
					headers: { Authorization: `Bearer ${token}` },
				});
			} catch {
				setUserGames((prev) => [...prev, { game_id: gameId, has_shiny_charm: false }]);
			}
		} else {
			setUserGames((prev) => [...prev, { game_id: gameId, has_shiny_charm: false }]);
			try {
				await fetch(`http://localhost:8080/api/user/${userId}/games/${gameId}`, {
					method: "POST",
					headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
					body: JSON.stringify({ has_shiny_charm: false }),
				});
			} catch {
				setUserGames((prev) => prev.filter((ug) => ug.game_id !== gameId));
			}
		}
	};

	const handleCharmToggle = async (e: React.MouseEvent, gameId: number, currentCharm: boolean) => {
		e.stopPropagation();
		const newCharm = !currentCharm;
		setUserGames((prev) =>
			prev.map((ug) => (ug.game_id === gameId ? { ...ug, has_shiny_charm: newCharm } : ug)),
		);
		try {
			await fetch(`http://localhost:8080/api/user/${userId}/games/${gameId}`, {
				method: "POST",
				headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
				body: JSON.stringify({ has_shiny_charm: newCharm }),
			});
		} catch {
			setUserGames((prev) =>
				prev.map((ug) => (ug.game_id === gameId ? { ...ug, has_shiny_charm: currentCharm } : ug)),
			);
		}
	};

	if (loading) {
		return (
			<div className="page" style={{ color: "var(--ink-3)", fontFamily: "var(--font-mono)", fontSize: 12 }}>
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
	const generations = Object.keys(byGen).map(Number).sort((a, b) => a - b);

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
					<div className="v">{owned}<span className="unit">/ {games.length}</span></div>
				</div>
				<div className="stat-tile">
					<div className="t-label">Shiny Charms</div>
					<div className="v" style={{ color: "var(--gold)" }}>{fmtNum(charms)}</div>
				</div>
				<div className="stat-tile">
					<div className="t-label">Charm-Eligible</div>
					<div className="v">
						{userGames.filter((ug) => {
							const g = games.find((g) => g.id === ug.game_id);
							return g && supportsShinyCharm(g);
						}).length}
						<span className="unit">/ {games.filter(supportsShinyCharm).length}</span>
					</div>
				</div>
				<div className="stat-tile">
					<div className="t-label">Generations</div>
					<div className="v">
						{generations.filter((gen) => byGen[gen].some((g) => userGames.some((ug) => ug.game_id === g.id))).length}
						<span className="unit">/ 9</span>
					</div>
				</div>
			</div>

			{generations.map((gen) => {
				const genOwned = byGen[gen].filter((g) => userGames.some((ug) => ug.game_id === g.id)).length;
				return (
					<div key={gen} style={{ marginBottom: 18 }}>
						<div className="gen-head">
							<span className="lbl">{GEN_NAMES[gen] ?? `Generation ${gen}`}</span>
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
								const charmSupported = supportsShinyCharm(g);

								return (
									<div
										key={g.id}
										className={`game-card ${isOwned ? "owned" : "uowned"}`}
										onClick={() => handleOwnershipToggle(g.id, isOwned)}
									>
										<div className="ttl">{g.title}</div>
										<div className="gen">
											Gen {ROMAN[g.generation]} · {isOwned ? "Owned" : "Click to add"}
										</div>
										{charmSupported && (
											<button
												className={`charm-toggle ${hasCharm ? "active" : ""} ${!isOwned ? "disabled" : ""}`}
												onClick={(e) => handleCharmToggle(e, g.id, hasCharm)}
												title={hasCharm ? "Remove Shiny Charm" : "Add Shiny Charm"}
											>
												<SparkSm size={11} />
											</button>
										)}
									</div>
								);
							})}
						</div>
					</div>
				);
			})}
		</div>
	);
};

export default CollectionManager;
