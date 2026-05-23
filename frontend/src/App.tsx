import { useState } from "react";
import Admin from "./components/admin/Admin";
import Collection from "./components/Collection";
import CollectionManager from "./components/CollectionManager";
import Dashboard from "./components/Dashboard";
import HistoricHunts from "./components/HistoricHunts";
import Login from "./components/Login";
import MethodLibrary from "./components/MethodLibrary";
import NewHuntModal from "./components/NewHuntModal";
import OddsCalculator from "./components/OddsCalculator";
import Sidebar from "./components/Sidebar";
import Stats from "./components/Stats";
import Topbar from "./components/Topbar";
import { useAuth } from "./context/AuthContext";

export type Route =
	| "dash"
	| "historic"
	| "dex"
	| "games"
	| "stats"
	| "odds-calc"
	| "method-library"
	| "admin";

function App() {
	const { token, logout } = useAuth();
	const [route, setRoute] = useState<Route>("dash");
	const [newHuntOpen, setNewHuntOpen] = useState(false);
	const [activeHuntCount, setActiveHuntCount] = useState(0);

	if (!token) return <Login />;

	return (
		<div className="app">
			<Sidebar
				route={route}
				setRoute={setRoute}
				onLogout={logout}
				activeHuntCount={activeHuntCount}
			/>
			<div className="main" id="main-scroll">
				<Topbar route={route} onNew={() => setNewHuntOpen(true)} />
				<div style={{ display: route === "dash" ? "contents" : "none" }}>
					<Dashboard
						onNewHunt={() => setNewHuntOpen(true)}
						onHuntCountChange={setActiveHuntCount}
					/>
				</div>
				{route === "historic" && <HistoricHunts />}
				{route === "dex" && <Collection />}
				{route === "games" && <CollectionManager />}
				{route === "stats" && <Stats />}
				{route === "odds-calc" && <OddsCalculator />}
				{route === "method-library" && <MethodLibrary />}
				{route === "admin" && <Admin />}
			</div>
			<NewHuntModal
				open={newHuntOpen}
				onClose={() => setNewHuntOpen(false)}
				onGoToGames={() => {
					setNewHuntOpen(false);
					setRoute("games");
				}}
			/>
		</div>
	);
}

export default App;
