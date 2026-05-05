import AddIcon from "@mui/icons-material/Add";
import CatchingPokemonIcon from "@mui/icons-material/CatchingPokemon";
import {
	AppBar,
	Box,
	Button,
	Container,
	Tab,
	Tabs,
	Toolbar,
	Typography,
} from "@mui/material";
import { useState } from "react";
import CollectionManager from "./components/CollectionManager";
import Dashboard from "./components/Dashboard";
import HistoricHunts from "./components/HistoricHunts";
import Collection from "./components/Collection";
import Login from "./components/Login";
import NewHuntModal from "./components/NewHuntModal";
import { useAuth } from "./context/AuthContext";

function App() {
	const { token, logout } = useAuth();
	const [tabIndex, setTabIndex] = useState(0);
	const [modalOpen, setModalOpen] = useState(false);

	if (!token) {
		return (
			<Box
				sx={{ flexGrow: 1, minHeight: "100vh", bgcolor: "background.default" }}
			>
				<AppBar
					position="static"
					elevation={0}
					sx={{
						bgcolor: "background.paper",
						borderBottom: 1,
						borderColor: "divider",
					}}
				>
					<Toolbar>
						<CatchingPokemonIcon sx={{ mr: 2, color: "primary.main" }} />
						<Typography
							variant="h6"
							component="div"
							sx={{ flexGrow: 1, fontWeight: 700 }}
						>
							ShinyTracker
						</Typography>
					</Toolbar>
				</AppBar>
				<Login />
			</Box>
		);
	}

	return (
		<Box
			sx={{ flexGrow: 1, minHeight: "100vh", bgcolor: "background.default" }}
		>
			<AppBar
				position="static"
				elevation={0}
				sx={{
					bgcolor: "background.paper",
					borderBottom: 1,
					borderColor: "divider",
				}}
			>
				<Toolbar>
					<CatchingPokemonIcon sx={{ mr: 2, color: "primary.main" }} />
					<Typography
						variant="h6"
						component="div"
						sx={{ flexGrow: 1, fontWeight: 700 }}
					>
						ShinyTracker
					</Typography>
					{/* ── Global CTA: highest visual priority ── */}
					<Button
						variant="contained"
						startIcon={<AddIcon />}
						onClick={() => setModalOpen(true)}
						sx={{
							mr: 2,
							background: "linear-gradient(135deg, #6366F1 0%, #3B82F6 100%)",
							color: "#ffffff",
							fontWeight: 700,
							letterSpacing: "0.3px",
							boxShadow: "0 4px 14px rgba(59, 130, 246, 0.45)",
							"&:hover": {
								background: "linear-gradient(135deg, #4F46E5 0%, #2563EB 100%)",
								boxShadow: "0 6px 20px rgba(59, 130, 246, 0.6)",
							},
						}}
					>
						New Hunt
					</Button>
					<Button color="inherit" onClick={logout}>
						Logout
					</Button>
				</Toolbar>
			</AppBar>

			<Container maxWidth="lg" sx={{ mt: 4 }}>
				<Box sx={{ borderBottom: 1, borderColor: "divider", mb: 3 }}>
					<Tabs
						value={tabIndex}
						onChange={(_, newValue) => setTabIndex(newValue)}
						textColor="primary"
						indicatorColor="primary"
					>
						<Tab label="Dashboard" />
						<Tab label="Historic Hunts" />
						<Tab label="Shiny Collection" />
						<Tab label="Games Owned" />
					</Tabs>
				</Box>

				{tabIndex === 0 && <Dashboard />}
				{tabIndex === 1 && <HistoricHunts />}
				{tabIndex === 2 && <Collection />}
				{tabIndex === 3 && <CollectionManager />}
			</Container>

			<NewHuntModal open={modalOpen} onClose={() => setModalOpen(false)} />
		</Box>
	);
}

export default App;
