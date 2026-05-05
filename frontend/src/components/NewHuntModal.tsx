import {
	Autocomplete,
	Box,
	Button,
	CircularProgress,
	FormControl,
	InputLabel,
	MenuItem,
	Modal,
	Select,
	TextField,
	Typography,
} from "@mui/material";
import { motion } from "framer-motion";
import React, { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";

const style = {
	position: "absolute" as "absolute",
	top: "50%",
	left: "50%",
	transform: "translate(-50%, -50%)",
	width: 500,
	bgcolor: "background.paper",
	borderRadius: 4,
	boxShadow: 24,
	p: 4,
};

interface Pokemon {
	id: number;
	name: string;
	sprite_url: string;
}

interface EncounterDetail {
	id: number;
	pokemon_id: number;
	game_id: number;
	game_title: string;
	method_name: string;
	avg_time_seconds: number;
	base_rolls: number;
	charm_rolls: number;
}

interface Props {
	open: boolean;
	onClose: () => void;
}

const NewHuntModal: React.FC<Props> = ({ open, onClose }) => {
	const { token } = useAuth();
	const [options, setOptions] = useState<Pokemon[]>([]);
	const [selectedPokemon, setSelectedPokemon] = useState<Pokemon | null>(null);
	const [encounters, setEncounters] = useState<EncounterDetail[]>([]);
	const [selectedEncounter, setSelectedEncounter] = useState<EncounterDetail | null>(null);
	const [loadingSearch, setLoadingSearch] = useState(false);
	const [loadingEncounters, setLoadingEncounters] = useState(false);
	const [search, setSearch] = useState("");

	useEffect(() => {
		if (!open) {
			setSelectedPokemon(null);
			setEncounters([]);
			setSelectedEncounter(null);
			setSearch("");
			return;
		}
	}, [open]);

	useEffect(() => {
		const fetchSearch = async () => {
			setLoadingSearch(true);
			try {
				const res = await fetch(
					`http://localhost:8080/api/pokemon?q=${search}`,
				);
				if (res.ok) setOptions((await res.json()) || []);
			} catch (err) {
				console.error(err);
			} finally {
				setLoadingSearch(false);
			}
		};
		const timer = setTimeout(fetchSearch, 300);
		return () => clearTimeout(timer);
	}, [search]);

	useEffect(() => {
		if (!selectedPokemon) {
			setEncounters([]);
			setSelectedEncounter(null);
			return;
		}
		const fetchEncounters = async () => {
			setLoadingEncounters(true);
			try {
				const res = await fetch(
					`http://localhost:8080/api/encounters?pokemon_id=${selectedPokemon.id}`,
					{
						headers: { Authorization: `Bearer ${token}` },
					},
				);
				if (res.ok) {
					const data = (await res.json()) || [];
					setEncounters(data);
					setSelectedEncounter(null);
				}
			} catch (err) {
				console.error(err);
			} finally {
				setLoadingEncounters(false);
			}
		};
		fetchEncounters();
	}, [selectedPokemon, token]);

	const handleStart = async () => {
		if (!selectedEncounter) return;
		try {
			const res = await fetch("http://localhost:8080/api/hunts", {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({
					encounter_id: selectedEncounter.id,
					hunt_parameters: {},
				}),
			});
			if (res.ok) {
				onClose();
				window.location.reload();
			}
		} catch (err) {
			console.error(err);
		}
	};

	return (
		<Modal open={open} onClose={onClose}>
			<Box
				sx={style}
				component={motion.div}
				initial={{ opacity: 0, scale: 0.9 }}
				animate={{ opacity: 1, scale: 1 }}
			>
				<Typography variant="h5" gutterBottom>
					Start a New Hunt
				</Typography>

				<Autocomplete
					options={options}
					getOptionLabel={(option) =>
						option.name.charAt(0).toUpperCase() + option.name.slice(1)
					}
					onChange={(_, value) => setSelectedPokemon(value)}
					onInputChange={(_, value) => setSearch(value)}
					renderOption={(props, option) => (
						<Box
							component="li"
							{...props}
							key={option.id}
							sx={{ display: "flex", alignItems: "center", gap: 2 }}
						>
							<img
								src={option.sprite_url}
								alt={option.name}
								width={40}
								height={40}
								style={{ imageRendering: "pixelated" }}
							/>
							<Typography sx={{ textTransform: "capitalize" }}>
								{option.name}
							</Typography>
						</Box>
					)}
					renderInput={(params) => (
						// @ts-expect-error - MUI v6 TypeScript types are currently misaligned with Autocomplete renderInput
						<TextField
							{...params}
							label="Search Pokémon"
							variant="outlined"
							margin="normal"
							InputProps={{
								...(params as any).InputProps,
								startAdornment: (
									<React.Fragment>
										{selectedPokemon && (
											<img
												src={selectedPokemon.sprite_url}
												alt={selectedPokemon.name}
												width={32}
												height={32}
												style={{
													imageRendering: "pixelated",
													marginLeft: 8,
													marginRight: 8,
												}}
											/>
										)}
										{(params as any).InputProps?.startAdornment}
									</React.Fragment>
								),
								endAdornment: (
									<React.Fragment>
										{loadingSearch ? (
											<CircularProgress color="inherit" size={20} />
										) : null}
										{(params as any).InputProps?.endAdornment}
									</React.Fragment>
								),
							}}
						/>
					)}
				/>

				<Box sx={{ mt: 2 }}>
					<Autocomplete
						options={encounters}
						getOptionLabel={(option) => `${option.game_title} - ${option.method_name}`}
						value={selectedEncounter}
						onChange={(_, value) => setSelectedEncounter(value)}
						disabled={!selectedPokemon || loadingEncounters || (selectedPokemon && encounters.length === 0)}
						renderInput={(params) => (
							<TextField
								{...params}
								label={
									selectedPokemon && encounters.length === 0 && !loadingEncounters
										? "Shiny Locked / Unavailable"
										: "Choose Hunting Method"
								}
								variant="outlined"
								InputProps={{
									...params.InputProps,
									endAdornment: (
										<React.Fragment>
											{loadingEncounters ? (
												<CircularProgress color="inherit" size={20} />
											) : null}
											{params.InputProps.endAdornment}
										</React.Fragment>
									),
								}}
							/>
						)}
					/>
				</Box>

				<Box
					sx={{ mt: 3, display: "flex", justifyContent: "flex-end", gap: 2 }}
				>
					<Button onClick={onClose} color="inherit">
						Cancel
					</Button>
					<Button
						variant="contained"
						color="primary"
						onClick={handleStart}
						disabled={!selectedEncounter}
					>
						Start Hunt
					</Button>
				</Box>
			</Box>
		</Modal>
	);
};

export default NewHuntModal;
