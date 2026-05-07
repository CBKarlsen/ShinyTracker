import {
	Alert,
	Box,
	Button,
	Card,
	CardContent,
	CircularProgress,
	Grid,
	Snackbar,
	Typography,
} from "@mui/material";
import type React from "react";
import { useEffect, useRef, useState } from "react";
import { useAuth } from "../context/AuthContext";
import { colors } from "../palette";
import { getShowdownGif } from "../utils/pokemon";

interface Hunt {
	id: string;
	encounter_id: number | null;
	encounter_count: number;
	status: string;
	acquisition_type: string;
	hunt_parameters: any;
	pokemon_id: number;
	pokemon_name: string;
	method_name: string | null;
	game_title: string | null;
	total_time_seconds: number;
	base_rolls: number | null;
	charm_rolls: number | null;
	avg_time_seconds: number | null;
	base_odds: number | null;
	has_shiny_charm: boolean | null;
}

function formatHuntedTime(seconds: number): string {
	const h = Math.floor(seconds / 3600);
	const m = Math.floor((seconds % 3600) / 60);
	if (h > 0) return `${h} h ${m} m`;
	return `${m} m`;
}

function computeExpectedEncounters(hunt: Hunt): number | null {
	if (hunt.base_odds == null || hunt.base_rolls == null || hunt.charm_rolls == null) return null;
	const rolls = hunt.base_rolls + (hunt.has_shiny_charm ? hunt.charm_rolls : 0);
	if (rolls <= 0) return null;
	return Math.floor(hunt.base_odds / rolls);
}

const Dashboard: React.FC = () => {
	const { token } = useAuth();
	const [hunts, setHunts] = useState<Hunt[]>([]);
	const [loading, setLoading] = useState(true);
	const [localCounts, setLocalCounts] = useState<Record<string, number>>({});
	const [gifUrls, setGifUrls] = useState<Record<string, string>>({});
	const committedCountsRef = useRef<Record<string, number>>({});
	const timers = useRef<Record<string, ReturnType<typeof setTimeout>>>({});
	const [errorMsg, setErrorMsg] = useState<string | null>(null);

	useEffect(() => {
		const fetchHunts = async () => {
			try {
				const res = await fetch("http://localhost:8080/api/hunts", {
					headers: { Authorization: `Bearer ${token}` },
				});
				if (res.ok) {
					const data = (await res.json()) || [];
					const active = data.filter((h: Hunt) => h.status === "active");
					setHunts(active);
					const initial: Record<string, number> = {};
					const gifs: Record<string, string> = {};
					for (const h of active) {
						initial[h.id] = h.encounter_count;
						gifs[h.id] = getShowdownGif(h.pokemon_name);
					}
					setLocalCounts(initial);
					setGifUrls(gifs);
					committedCountsRef.current = initial;
				}
			} catch (err) {
				console.error(err);
			} finally {
				setLoading(false);
			}
		};
		fetchHunts();
	}, [token]);

	const handleIncrement = (hunt: Hunt) => {
		const newCount = (localCounts[hunt.id] ?? hunt.encounter_count) + 1;
		setLocalCounts((prev) => ({ ...prev, [hunt.id]: newCount }));

		if (timers.current[hunt.id]) clearTimeout(timers.current[hunt.id]);

		timers.current[hunt.id] = setTimeout(async () => {
			try {
				const res = await fetch(`http://localhost:8080/api/hunts/${hunt.id}`, {
					method: "PATCH",
					headers: {
						"Content-Type": "application/json",
						Authorization: `Bearer ${token}`,
					},
					body: JSON.stringify({ encounter_count: newCount, status: hunt.status }),
				});
				if (res.ok) {
					committedCountsRef.current[hunt.id] = newCount;
					setHunts((prev) =>
						prev.map((h) =>
							h.id === hunt.id ? { ...h, encounter_count: newCount } : h,
						),
					);
				} else {
					setLocalCounts((prev) => ({
						...prev,
						[hunt.id]: committedCountsRef.current[hunt.id] ?? hunt.encounter_count,
					}));
					setErrorMsg("Sync failed — your last clicks weren't saved. Try again.");
				}
			} catch {
				setLocalCounts((prev) => ({
					...prev,
					[hunt.id]: committedCountsRef.current[hunt.id] ?? hunt.encounter_count,
				}));
				setErrorMsg("Sync failed — your last clicks weren't saved. Try again.");
			}
		}, 1500);
	};

	const handleComplete = async (hunt: Hunt) => {
		if (timers.current[hunt.id]) {
			clearTimeout(timers.current[hunt.id]);
			delete timers.current[hunt.id];
		}
		const currentCount = localCounts[hunt.id] ?? hunt.encounter_count;
		try {
			const res = await fetch(`http://localhost:8080/api/hunts/${hunt.id}`, {
				method: "PATCH",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({ encounter_count: currentCount, status: "completed" }),
			});
			if (res.ok) {
				committedCountsRef.current[hunt.id] = currentCount;
				setHunts((prev) =>
					prev.map((h) =>
						h.id === hunt.id
							? { ...h, encounter_count: currentCount, status: "completed" }
							: h,
					),
				);
			}
		} catch (err) {
			console.error(err);
		}
	};

	if (loading) return <CircularProgress />;

	return (
		<Box>
			<Typography variant="h4" gutterBottom>
				Active Hunts
			</Typography>
			<Grid container spacing={3}>
				{hunts.length === 0 ? (
					<Grid size={{ xs: 12 }}>
						<Typography variant="body1" color="text.secondary">
							No active hunts yet. Click 'New Hunt' to start!
						</Typography>
					</Grid>
				) : (
					hunts.map((hunt) => {
						const displayCount = localCounts[hunt.id] ?? hunt.encounter_count;
						const expectedEncounters = computeExpectedEncounters(hunt);
						const isOverOdds = expectedEncounters !== null && displayCount > expectedEncounters;

						return (
							<Grid size={{ xs: 12, sm: 6, md: 4 }} key={hunt.id}>
								<Card
									sx={{
										background: isOverOdds ? "rgba(120, 53, 15, 0.3)" : colors.bgPaper,
										border: isOverOdds
											? "1px solid rgba(251, 146, 60, 0.6)"
											: `1px solid ${colors.border}`,
										borderRadius: "12px",
										"&:hover": {
											background: isOverOdds ? "rgba(120, 53, 15, 0.4)" : colors.bgSubtle,
										},
									}}
								>
									<CardContent>
										<Box sx={{ display: "flex", alignItems: "center", gap: 2, mb: 2 }}>
											<img
												src={gifUrls[hunt.id]}
												alt={hunt.pokemon_name}
												width={72}
												height={72}
												style={{ objectFit: "contain" }}
												onError={(e) => {
													e.currentTarget.onerror = null;
													e.currentTarget.src = `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/${hunt.pokemon_id}.png`;
												}}
											/>
											<Box sx={{ flex: 1 }}>
												<Box sx={{ display: "flex", alignItems: "center", gap: 1 }}>
													<Typography variant="h6" color="primary" sx={{ textTransform: "capitalize" }}>
														{hunt.pokemon_name}
													</Typography>
													{isOverOdds && (
														<Typography variant="caption" sx={{ color: "#fb923c", fontWeight: 700 }}>
															🔥 OVER ODDS
														</Typography>
													)}
												</Box>
												<Typography variant="body2" color="text.secondary">
													Hunt #{hunt.id.substring(0, 6)}
												</Typography>
											</Box>
										</Box>

										<Typography variant="body2">
											<strong>Game:</strong> {hunt.game_title || "Manual"}
										</Typography>
										<Typography variant="body2" sx={{ mb: 1 }}>
											<strong>Method:</strong> {hunt.method_name || "N/A"}
										</Typography>

										<Box sx={{ mt: 2, mb: 1 }}>
											<Typography variant="body1" sx={{ fontWeight: 600 }}>
												{displayCount} encounters
											</Typography>
										</Box>

										<Box sx={{ display: "flex", flexDirection: "column", gap: 0.5, mb: 1 }}>
											<Typography variant="body2" color="text.secondary">
												<strong>Hunted:</strong> {formatHuntedTime(hunt.total_time_seconds)}
											</Typography>
											{expectedEncounters !== null && hunt.avg_time_seconds != null && (
												<Typography variant="body2" color="text.secondary">
													<strong>Expected:</strong> ~{((expectedEncounters * hunt.avg_time_seconds) / 3600).toFixed(1)} h
												</Typography>
											)}
										</Box>

										{hunt.status !== "completed" ? (
											<Box sx={{ mt: 2, display: "flex", gap: 1 }}>
												<Button
													variant="outlined"
													fullWidth
													onClick={() => handleIncrement(hunt)}
													sx={{
														background: "rgba(59, 130, 246, 0.10)",
														color: "#60A5FA",
														borderColor: "rgba(59, 130, 246, 0.25)",
														fontWeight: 600,
														"&:hover": {
															background: "rgba(59, 130, 246, 0.18)",
															borderColor: "rgba(59, 130, 246, 0.45)",
														},
													}}
												>
													+1 Encounter
												</Button>
												<Button
													variant="contained"
													color="success"
													onClick={() => handleComplete(hunt)}
												>
													Found It!
												</Button>
											</Box>
										) : (
											<Box sx={{ mt: 2 }}>
												<Typography
													variant="body2"
													color="success.main"
													sx={{ fontWeight: "bold", textAlign: "center" }}
												>
													✨ Shiny Found! ✨
												</Typography>
											</Box>
										)}
									</CardContent>
								</Card>
							</Grid>
						);
					})
				)}
			</Grid>

			<Snackbar
				open={errorMsg !== null}
				autoHideDuration={4000}
				onClose={() => setErrorMsg(null)}
				anchorOrigin={{ vertical: "bottom", horizontal: "center" }}
			>
				<Alert severity="error" onClose={() => setErrorMsg(null)}>
					{errorMsg}
				</Alert>
			</Snackbar>
		</Box>
	);
};

export default Dashboard;
