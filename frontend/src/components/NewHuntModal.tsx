import {
	Autocomplete,
	Box,
	Button,
	CircularProgress,
	Modal,
	TextField,
	Typography,
} from "@mui/material";
import { motion } from "framer-motion";
import React, { useEffect, useMemo, useState } from "react";
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
	const [encountersData, setEncountersData] = useState<EncounterDetail[]>([]);
	const [selectedGame, setSelectedGame] = useState<string | null>(null);
	const [selectedMethod, setSelectedMethod] = useState<EncounterDetail | null>(null);
	const [loadingSearch, setLoadingSearch] = useState(false);
	const [loadingEncounters, setLoadingEncounters] = useState(false);
	const [search, setSearch] = useState("");

	const gameOptions = useMemo(() => {
		const seen = new Set<string>();
		return encountersData
			.filter((e) => {
				if (seen.has(e.game_title)) return false;
				seen.add(e.game_title);
				return true;
			})
			.map((e) => e.game_title);
	}, [encountersData]);

	const methodOptions = useMemo(
		() => encountersData.filter((e) => e.game_title === selectedGame),
		[encountersData, selectedGame],
	);

	useEffect(() => {
		if (!open) {
			setSelectedPokemon(null);
			setEncountersData([]);
			setSelectedGame(null);
			setSelectedMethod(null);
			setSearch("");
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
			setEncountersData([]);
			setSelectedGame(null);
			setSelectedMethod(null);
			return;
		}
		const fetchEncounters = async () => {
			setLoadingEncounters(true);
			try {
				const res = await fetch(
					`http://localhost:8080/api/encounters?pokemon_id=${selectedPokemon.id}`,
					{ headers: { Authorization: `Bearer ${token}` } },
				);
				if (res.ok) {
					setEncountersData((await res.json()) || []);
					setSelectedGame(null);
					setSelectedMethod(null);
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
		if (!selectedMethod || !selectedPokemon) return;
		try {
			const res = await fetch("http://localhost:8080/api/hunts", {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({
					encounter_id: selectedMethod.id,
					pokemon_id: selectedPokemon.id,
					method_name: selectedMethod.method_name,
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

				{/* Step 1: Pokémon */}
				<Autocomplete
					options={options}
					getOptionLabel={(option) =>
						typeof option === "string" ? option : option.name || ""
					}
					isOptionEqualToValue={(option, value) =>
						value ? option.id === value.id : false
					}
					onChange={(_, value) => setSelectedPokemon(value)}
					onInputChange={(_, value) => setSearch(value)}
					renderOption={(props, option) => (
						<Box
							component="li"
							{...props}
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
					renderInput={(params) => {
						const { InputProps, ...rest } = params;
						return (
							<TextField
								{...rest}
								label="Search Pokémon"
								variant="outlined"
								margin="normal"
								InputProps={{
									...InputProps,
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
											{InputProps?.startAdornment}
										</React.Fragment>
									),
									endAdornment: (
										<React.Fragment>
											{loadingSearch ? (
												<CircularProgress color="inherit" size={20} />
											) : null}
											{InputProps?.endAdornment}
										</React.Fragment>
									),
								}}
							/>
						);
					}}
				/>

				{/* Step 2: Game */}
				<Box sx={{ mt: 2 }}>
					<Autocomplete
						options={gameOptions}
						value={selectedGame}
						onChange={(_, value) => {
							setSelectedGame(value);
							setSelectedMethod(null);
						}}
						disabled={encountersData.length === 0}
						renderInput={(params) => {
							const { InputProps, ...rest } = params;
							return (
								<TextField
									{...rest}
									label={
										selectedPokemon &&
										encountersData.length === 0 &&
										!loadingEncounters
											? "Shiny Locked / Unavailable"
											: "Choose Game"
									}
									variant="outlined"
									InputProps={{
										...InputProps,
										endAdornment: (
											<React.Fragment>
												{loadingEncounters ? (
													<CircularProgress color="inherit" size={20} />
												) : null}
												{InputProps?.endAdornment}
											</React.Fragment>
										),
									}}
								/>
							);
						}}
					/>
				</Box>

				{/* Step 3: Method */}
				<Box sx={{ mt: 2 }}>
					<Autocomplete
						options={methodOptions}
						getOptionLabel={(option) =>
							typeof option === "string" ? option : option.method_name || ""
						}
						isOptionEqualToValue={(option, value) =>
							value ? option.id === value.id : false
						}
						value={selectedMethod}
						onChange={(_, value) => setSelectedMethod(value)}
						disabled={!selectedGame}
						renderInput={(params) => {
							const { InputProps, ...rest } = params;
							return (
								<TextField
									{...rest}
									label="Choose Method"
									variant="outlined"
									InputProps={{ ...InputProps }}
								/>
							);
						}}
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
						disabled={!selectedMethod}
					>
						Start Hunt
					</Button>
				</Box>
			</Box>
		</Modal>
	);
};

export default NewHuntModal;
