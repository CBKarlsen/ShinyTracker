import React, { useEffect, useState } from "react";
import { Box, Typography, CircularProgress, Tooltip, ToggleButtonGroup, ToggleButton, Dialog, DialogTitle, DialogContent, DialogContentText, DialogActions, Button } from "@mui/material";
import { useAuth } from "../context/AuthContext";
import type { HuntDetail } from "./HistoricHunts";

interface Pokemon {
	id: number;
	name: string;
}

const Collection: React.FC = () => {
	const { token } = useAuth();
	const [pokemon, setPokemon] = useState<Pokemon[]>([]);
	const [caughtIds, setCaughtIds] = useState<Set<number>>(new Set());
	const [loading, setLoading] = useState(true);
	const [filterMode, setFilterMode] = useState<"all" | "owned">("all");
	const [dialogOpen, setDialogOpen] = useState(false);
	const [selectedPokemonId, setSelectedPokemonId] = useState<number | null>(null);

	useEffect(() => {
		const fetchData = async () => {
			try {
				const [pokeRes, huntsRes] = await Promise.all([
					fetch("http://localhost:8080/api/pokemon?limit=all"),
					fetch("http://localhost:8080/api/hunts", {
						headers: { Authorization: `Bearer ${token}` },
					}),
				]);

				if (pokeRes.ok && huntsRes.ok) {
					const pokeData = (await pokeRes.json()) || [];
					const huntsData = (await huntsRes.json()) || [];

					setPokemon(pokeData);

					const caught = new Set<number>();
					huntsData.forEach((h: HuntDetail) => {
						if (h.status === "completed") {
							caught.add(h.pokemon_id);
						}
					});
					setCaughtIds(caught);
				}
			} catch (err) {
				console.error(err);
			} finally {
				setLoading(false);
			}
		};
		fetchData();
	}, [token]);

	const handleCatchToggle = async (pokemonId: number, isCurrentlyCaught: boolean) => {
		if (isCurrentlyCaught) {
			setSelectedPokemonId(pokemonId);
			setDialogOpen(true);
			return;
		}

		// Optimistic update for un-caught -> caught
		const prev = new Set(caughtIds);
		const next = new Set(caughtIds);
		next.add(pokemonId);
		setCaughtIds(next);

		try {
			const res = await fetch("http://localhost:8080/api/hunts/manual", {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({ pokemon_id: pokemonId }),
			});
			if (!res.ok) throw new Error("Failed to catch");
		} catch (err) {
			console.error(err);
			setCaughtIds(prev); // Revert
		}
	};

	const confirmRemoveCatch = async () => {
		if (selectedPokemonId === null) return;
		const pid = selectedPokemonId;
		
		setDialogOpen(false);
		setSelectedPokemonId(null);

		// Optimistic update for caught -> un-caught
		const prev = new Set(caughtIds);
		const next = new Set(caughtIds);
		next.delete(pid);
		setCaughtIds(next);

		try {
			const res = await fetch(`http://localhost:8080/api/hunts/manual/${pid}`, {
				method: "DELETE",
				headers: { Authorization: `Bearer ${token}` },
			});
			if (!res.ok) throw new Error("Failed to remove catch");
		} catch (err) {
			console.error(err);
			setCaughtIds(prev); // Revert
		}
	};

	if (loading) return <CircularProgress />;

	const displayedPokemon = pokemon.filter((p) => {
		if (filterMode === "owned") return caughtIds.has(p.id);
		return true;
	});

	return (
		<Box>
			<Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 3 }}>
				<Typography variant="h4">Shiny Living Dex</Typography>
				
				<Box sx={{ display: 'flex', alignItems: 'center', gap: 3 }}>
					<ToggleButtonGroup
						value={filterMode}
						exclusive
						onChange={(_, newVal) => { if (newVal) setFilterMode(newVal); }}
						size="small"
					>
						<ToggleButton value="all">Show All</ToggleButton>
						<ToggleButton value="owned">Owned Only</ToggleButton>
					</ToggleButtonGroup>

					<Typography variant="h6" color="primary" sx={{ fontWeight: 'bold' }}>
						Caught: {caughtIds.size} / {pokemon.length}
					</Typography>
				</Box>
			</Box>
			
			<Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1 }}>
				{displayedPokemon.map((p) => {
					const isCaught = caughtIds.has(p.id);
					return (
						<Tooltip key={p.id} title={p.name.charAt(0).toUpperCase() + p.name.slice(1)} arrow>
							<Box
								onClick={() => handleCatchToggle(p.id, isCaught)}
								sx={{
									width: 64,
									height: 64,
									display: 'flex',
									justifyContent: 'center',
									alignItems: 'center',
									bgcolor: isCaught ? 'primary.light' : 'background.paper',
									borderRadius: 2,
									border: '1px solid',
									borderColor: isCaught ? 'primary.main' : 'divider',
									cursor: 'pointer',
									transition: 'all 0.2s',
									'&:hover': {
										transform: 'scale(1.1)',
										zIndex: 1,
										boxShadow: 3
									}
								}}
							>
								<img
									src={isCaught 
										? `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/shiny/${p.id}.png`
										: `https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/${p.id}.png`}
									alt={p.name}
									width={56}
									height={56}
									style={{ 
										imageRendering: "pixelated",
										filter: isCaught ? 'none' : 'brightness(0) opacity(0.3)',
									}}
								/>
							</Box>
						</Tooltip>
					);
				})}
			</Box>

			<Dialog open={dialogOpen} onClose={() => setDialogOpen(false)}>
				<DialogTitle>Remove Shiny?</DialogTitle>
				<DialogContent>
					<DialogContentText>
						Are you sure you want to remove this Pokémon from your caught list? This action will delete the completed hunt record.
					</DialogContentText>
				</DialogContent>
				<DialogActions>
					<Button onClick={() => setDialogOpen(false)} color="inherit">Cancel</Button>
					<Button onClick={confirmRemoveCatch} color="error" variant="contained">Remove</Button>
				</DialogActions>
			</Dialog>
		</Box>
	);
};

export default Collection;
