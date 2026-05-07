import AutoAwesomeIcon from "@mui/icons-material/AutoAwesome";
import {
	Autocomplete,
	Box,
	Button,
	CircularProgress,
	Dialog,
	DialogContent,
	Divider,
	TextField,
	Typography,
} from "@mui/material";
import { motion } from "framer-motion";
import React, { useEffect, useMemo, useState } from "react";
import { useAuth } from "../context/AuthContext";
import { colors } from "../palette";
import { getShowdownGif } from "../utils/pokemon";


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
	is_recommended: boolean;
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
	const [startingRecommended, setStartingRecommended] = useState(false);

	const showdownGifUrl = useMemo(
		() => (selectedPokemon ? getShowdownGif(selectedPokemon.name) : ""),
		[selectedPokemon],
	);

	const recommendedEncounter = useMemo(
		() => encountersData.find((e) => e.is_recommended) ?? null,
		[encountersData],
	);

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
			setStartingRecommended(false);
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

	const startHunt = async (encounter: EncounterDetail) => {
		if (!selectedPokemon) return;
		try {
			const res = await fetch("http://localhost:8080/api/hunts", {
				method: "POST",
				headers: {
					"Content-Type": "application/json",
					Authorization: `Bearer ${token}`,
				},
				body: JSON.stringify({
					encounter_id: encounter.id,
					pokemon_id: selectedPokemon.id,
					method_name: encounter.method_name,
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

	const handleStart = async () => {
		if (!selectedMethod) return;
		await startHunt(selectedMethod);
	};

	const handleStartRecommended = async () => {
		if (!recommendedEncounter) return;
		setStartingRecommended(true);
		await startHunt(recommendedEncounter);
		setStartingRecommended(false);
	};

	return (
		<Dialog
			open={open}
			onClose={onClose}
			maxWidth="sm"
			fullWidth
			scroll="paper"
			slotProps={{ paper: { sx: { borderRadius: 4, mt: "6vh" } } }}
		>
			<DialogContent>
				<Box
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
							<Typography sx={{ textTransform: "capitalize" }} color="text.primary">
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

				{/* ── Pokémon GIF Showcase ── */}
				{selectedPokemon && (
					<Box
						component={motion.div}
						key={selectedPokemon.id}
						initial={{ opacity: 0, scale: 0.85 }}
						animate={{ opacity: 1, scale: 1 }}
						transition={{ duration: 0.3, ease: "easeOut" }}
						sx={{
							mt: 1,
							mb: 1,
							display: "flex",
							flexDirection: "column",
							alignItems: "center",
							gap: 0.5,
							py: 2,
							borderRadius: 3,
							bgcolor: colors.bgSubtle,
							border: `1px solid ${colors.border}`,
						}}
					>
						<img
							src={showdownGifUrl}
							alt={selectedPokemon.name}
							width={120}
							height={120}
							style={{ objectFit: "contain" }}
							onError={(e) => {
								e.currentTarget.onerror = null;
								e.currentTarget.src = selectedPokemon.sprite_url;
							}}
						/>
						<Typography
							variant="subtitle1"
							sx={{
								textTransform: "capitalize",
								fontWeight: 600,
								color: colors.textPrimary,
								letterSpacing: "0.5px",
							}}
						>
							{selectedPokemon.name}
						</Typography>
					</Box>
				)}

				{/* Loading state */}
				{loadingEncounters && selectedPokemon && (
					<Box sx={{ display: "flex", justifyContent: "center", py: 3 }}>
						<CircularProgress size={28} />
					</Box>
				)}

				{/* ── Recommended Hunt Card ── */}
				{!loadingEncounters && recommendedEncounter && selectedPokemon && (
					<Box
						component={motion.div}
						initial={{ opacity: 0, y: 12 }}
						animate={{ opacity: 1, y: 0 }}
						transition={{ duration: 0.35, ease: "easeOut" }}
						sx={{
							mt: 2.5,
							p: 2.5,
							borderRadius: 3,
							border: `1.5px solid ${colors.warning}`,
							background: `linear-gradient(135deg, ${colors.warning}08 0%, ${colors.warning}14 100%)`,
							boxShadow: `0 0 20px ${colors.warning}18, 0 2px 8px rgba(0,0,0,0.3)`,
							position: "relative",
							overflow: "hidden",
							"&::before": {
								content: '""',
								position: "absolute",
								top: 0,
								left: 0,
								right: 0,
								height: "2px",
								background: `linear-gradient(90deg, transparent, ${colors.warning}, transparent)`,
								opacity: 0.6,
							},
						}}
					>
						<Box sx={{ display: "flex", alignItems: "center", gap: 1, mb: 1.5 }}>
							<AutoAwesomeIcon sx={{ color: colors.warning, fontSize: 20 }} />
							<Typography
								variant="subtitle2"
								sx={{
									color: colors.warning,
									fontWeight: 700,
									letterSpacing: "0.5px",
									textTransform: "uppercase",
									fontSize: "0.75rem",
								}}
							>
								Recommended Hunt
							</Typography>
						</Box>

						<Box sx={{ display: "flex", alignItems: "center", gap: 2, mb: 2 }}>
							<img
								src={showdownGifUrl}
								alt={selectedPokemon.name}
								width={56}
								height={56}
								style={{ objectFit: "contain" }}
								onError={(e) => {
									e.currentTarget.onerror = null;
									e.currentTarget.src = selectedPokemon.sprite_url;
								}}
							/>
							<Box>
								<Typography
									variant="body1"
									sx={{ fontWeight: 600, color: colors.textPrimary }}
								>
									{recommendedEncounter.game_title}
								</Typography>
								<Typography
									variant="body2"
									sx={{ color: colors.textSecondary }}
								>
									{recommendedEncounter.method_name}
								</Typography>
							</Box>
						</Box>

						<Button
							variant="contained"
							fullWidth
							onClick={handleStartRecommended}
							disabled={startingRecommended}
							startIcon={
								startingRecommended ? (
									<CircularProgress size={16} color="inherit" />
								) : (
									<AutoAwesomeIcon />
								)
							}
							sx={{
								background: `linear-gradient(135deg, ${colors.warning} 0%, #D97706 100%)`,
								color: "#1a1a1a",
								fontWeight: 700,
								fontSize: "0.9rem",
								py: 1.2,
								boxShadow: `0 4px 14px ${colors.warning}40`,
								"&:hover": {
									background: `linear-gradient(135deg, #FBBF24 0%, ${colors.warning} 100%)`,
									boxShadow: `0 6px 20px ${colors.warning}60`,
								},
								"&:disabled": {
									background: colors.bgSubtle,
									color: colors.textSecondary,
								},
							}}
						>
							{startingRecommended ? "Starting…" : "Start Recommended Hunt"}
						</Button>
					</Box>
				)}

				{/* ── Divider between recommended and manual ── */}
				{!loadingEncounters && recommendedEncounter && selectedPokemon && (
					<Divider
						sx={{
							mt: 3,
							mb: 2,
							"&::before, &::after": {
								borderColor: colors.border,
							},
						}}
					>
						<Typography
							variant="caption"
							sx={{
								color: colors.textSecondary,
								fontWeight: 500,
								letterSpacing: "0.3px",
								px: 1,
							}}
						>
							Or choose manually
						</Typography>
					</Divider>
				)}

				{/* ── Manual Selection: Game ── */}
				{!loadingEncounters && (
					<Box sx={{ mt: recommendedEncounter && selectedPokemon ? 0 : 2 }}>
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
				)}

				{/* ── Manual Selection: Method ── */}
				{!loadingEncounters && (
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
				)}

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
			</DialogContent>
		</Dialog>
	);
};

export default NewHuntModal;
