import {
	Box,
	Button,
	Card,
	CardContent,
	CircularProgress,
	Grid,
	LinearProgress,
	Typography,
} from "@mui/material";
import type React from "react";
import { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";

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
}

const Dashboard: React.FC = () => {
	const { token } = useAuth();
	const [hunts, setHunts] = useState<Hunt[]>([]);
	const [loading, setLoading] = useState(true);

	useEffect(() => {
		const fetchHunts = async () => {
			try {
				const res = await fetch("http://localhost:8080/api/hunts", {
					headers: { Authorization: `Bearer ${token}` },
				});
				if (res.ok) {
					const data = (await res.json()) || [];
					setHunts(data.filter((h: Hunt) => h.status === "active"));
				}
			} catch (err) {
				console.error(err);
			} finally {
				setLoading(false);
			}
		};
		fetchHunts();
	}, [token]);

	const handleIncrement = async (hunt: Hunt) => {
		try {
			const res = await fetch(`http://localhost:8080/api/hunts/${hunt.id}`, {
				method: "PATCH",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({
					encounter_count: hunt.encounter_count + 1,
					status: hunt.status,
				}),
			});
			if (res.ok) {
				setHunts(
					hunts.map((h) =>
						h.id === hunt.id
							? { ...h, encounter_count: h.encounter_count + 1 }
							: h,
					),
				);
			}
		} catch (err) {
			console.error(err);
		}
	};

	const handleComplete = async (hunt: Hunt) => {
		try {
			const res = await fetch(`http://localhost:8080/api/hunts/${hunt.id}`, {
				method: "PATCH",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({
					encounter_count: hunt.encounter_count,
					status: "completed",
				}),
			});
			if (res.ok) {
				setHunts(
					hunts.map((h) =>
						h.id === hunt.id ? { ...h, status: "completed" } : h,
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
					hunts.map((hunt) => (
						<Grid size={{ xs: 12, sm: 6, md: 4 }} key={hunt.id}>
							<Card>
								<CardContent>
									<Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 2 }}>
										<img
											src={`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/${hunt.pokemon_id}.png`}
											alt={hunt.pokemon_name}
											width={56}
											height={56}
											style={{ imageRendering: "pixelated" }}
										/>
										<Box>
											<Typography variant="h6" color="primary" sx={{ textTransform: 'capitalize' }}>
												{hunt.pokemon_name}
											</Typography>
											<Typography variant="body2" color="text.secondary">
												Hunt #{hunt.id.substring(0, 6)}
											</Typography>
										</Box>
									</Box>
									
									<Typography variant="body2">
										<strong>Game:</strong> {hunt.game_title || 'Manual'}
									</Typography>
									<Typography variant="body2" sx={{ mb: 1 }}>
										<strong>Method:</strong> {hunt.method_name || 'N/A'}
									</Typography>
									<Box sx={{ mt: 2, mb: 1 }}>
										<Typography variant="body1">
											Encounters: {hunt.encounter_count}
										</Typography>
									</Box>
									<Box sx={{ display: "flex", alignItems: "center" }}>
										<Box sx={{ width: "100%", mr: 1 }}>
											<LinearProgress
												variant="determinate"
												value={Math.min(
													(hunt.encounter_count / 4096) * 100,
													100,
												)}
												color="secondary"
											/>
										</Box>
										<Box sx={{ minWidth: 35 }}>
											<Typography variant="body2" color="text.secondary">
												{Math.min(
													(hunt.encounter_count / 4096) * 100,
													100,
												).toFixed(1)}
												%
											</Typography>
										</Box>
									</Box>

									{hunt.status !== "completed" ? (
										<Box sx={{ mt: 2, display: "flex", gap: 1 }}>
											<Button
												variant="contained"
												color="primary"
												fullWidth
												onClick={() => handleIncrement(hunt)}
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
												fontWeight="bold"
												align="center"
											>
												✨ Shiny Found! ✨
											</Typography>
										</Box>
									)}
								</CardContent>
							</Card>
						</Grid>
					))
				)}
			</Grid>
		</Box>
	);
};

export default Dashboard;
