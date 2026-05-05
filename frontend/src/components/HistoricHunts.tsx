import React, { useEffect, useState } from "react";
import {
	Box,
	Card,
	CardContent,
	CircularProgress,
	Grid,
	Typography,
} from "@mui/material";
import { useAuth } from "../context/AuthContext";

export interface HuntDetail {
	id: string;
	user_id: string;
	encounter_id: number;
	encounter_count: number;
	status: string;
	hunt_parameters: any;
	created_at: string;
	updated_at: string;
	pokemon_id: number;
	pokemon_name: string;
	method_name: string | null;
	game_title: string | null;
}

const HistoricHunts: React.FC = () => {
	const { token } = useAuth();
	const [hunts, setHunts] = useState<HuntDetail[]>([]);
	const [loading, setLoading] = useState(true);

	useEffect(() => {
		const fetchHunts = async () => {
			try {
				const res = await fetch("http://localhost:8080/api/hunts", {
					headers: { Authorization: `Bearer ${token}` },
				});
				if (res.ok) {
					const data = (await res.json()) || [];
					// Filter only completed hunts
					setHunts(data.filter((h: HuntDetail) => h.status === "completed"));
				}
			} catch (err) {
				console.error(err);
			} finally {
				setLoading(false);
			}
		};
		fetchHunts();
	}, [token]);

	if (loading) return <CircularProgress />;

	return (
		<Box>
			<Typography variant="h4" gutterBottom>
				Historic Hunts
			</Typography>
			<Grid container spacing={3}>
				{hunts.length === 0 ? (
					<Grid item xs={12}>
						<Typography variant="body1" color="text.secondary">
							You haven't completed any shiny hunts yet. Get hunting!
						</Typography>
					</Grid>
				) : (
					hunts.map((hunt) => (
						<Grid item xs={12} sm={6} md={4} key={hunt.id}>
							<Card sx={{ border: '2px solid', borderColor: 'success.main' }}>
								<CardContent>
									<Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 2 }}>
										<img
											src={`https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/${hunt.pokemon_id}.png`}
											alt={hunt.pokemon_name}
											width={64}
											height={64}
											style={{ imageRendering: "pixelated" }}
										/>
										<Box>
											<Typography variant="h6" sx={{ textTransform: 'capitalize' }}>
												{hunt.pokemon_name}
											</Typography>
											<Typography variant="body2" color="text.secondary">
												Caught on {new Date(hunt.updated_at).toLocaleDateString()}
											</Typography>
										</Box>
									</Box>
									<Typography variant="body2">
										<strong>Game:</strong> {hunt.game_title || 'Manual Entry'}
									</Typography>
									<Typography variant="body2">
										<strong>Method:</strong> {hunt.method_name || 'Manual Entry'}
									</Typography>
									<Typography variant="body2" color="success.main" fontWeight="bold" sx={{ mt: 1 }}>
										✨ Encounters: {hunt.encounter_count}
									</Typography>
								</CardContent>
							</Card>
						</Grid>
					))
				)}
			</Grid>
		</Box>
	);
};

export default HistoricHunts;
