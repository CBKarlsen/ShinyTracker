import { useEffect, useState } from "react";
import Admin from "./components/admin/Admin";
import Collection from "./components/Collection";
import CollectionManager from "./components/CollectionManager";
import Dashboard from "./components/Dashboard";
import HistoricHunts from "./components/HistoricHunts";
import Login from "./components/Login";
import MethodLibrary from "./components/MethodLibrary";
import NewHuntModal from "./components/NewHuntModal";
import BottomNav from "./components/nav/BottomNav";
import MoreSheet from "./components/nav/MoreSheet";
import OddsCalculator from "./components/OddsCalculator";
import Sidebar from "./components/Sidebar";
import Stats from "./components/Stats";
import CommandSearch from "./components/search/CommandSearch";
import Topbar from "./components/Topbar";
import { useAuth } from "./context/AuthContext";
import type { Pokemon, PokemonRoute } from "./types/models";

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
	const { token, loading, logout } = useAuth();
	const [route, setRoute] = useState<Route>("dash");
	const [newHuntOpen, setNewHuntOpen] = useState(false);
	const [huntPrefill, setHuntPrefill] = useState<{
		pokemon: Pokemon;
		route?: PokemonRoute;
	} | null>(null);
	const [activeHuntCount, setActiveHuntCount] = useState(0);
	const [huntsVersion, setHuntsVersion] = useState(0);
	const handleHuntStarted = () => setHuntsVersion((v) => v + 1);
	const [moreOpen, setMoreOpen] = useState(false);
	const [searchOpen, setSearchOpen] = useState(false);
	const [focusPokemonId, setFocusPokemonId] = useState<number | null>(null);

	useEffect(() => {
		const onKey = (e: KeyboardEvent) => {
			// Ignore ⌘K while the user is typing in an unrelated input, but NOT
			// the palette's own input — otherwise ⌘K could open the palette but
			// never close it, since opening moves focus into that input.
			const t = e.target as HTMLElement | null;
			const insidePalette = !!t?.closest(".cmd-panel");
			if (
				t &&
				!insidePalette &&
				(t.tagName === "INPUT" ||
					t.tagName === "TEXTAREA" ||
					t.isContentEditable)
			)
				return;
			if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
				e.preventDefault();
				setSearchOpen((o) => !o);
			}
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, []);

	// Wait for the Supabase session to resolve before rendering — avoids
	// flashing the login screen for an already-authenticated user.
	if (loading) return null;
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
				<Topbar
					route={route}
					onNew={() => setNewHuntOpen(true)}
					onMoreOpen={() => setMoreOpen(true)}
					onOpenSearch={() => setSearchOpen(true)}
				/>
				<div style={{ display: route === "dash" ? "contents" : "none" }}>
					<Dashboard
						onNewHunt={() => setNewHuntOpen(true)}
						onHuntCountChange={setActiveHuntCount}
						refreshKey={huntsVersion}
					/>
				</div>
				{route === "historic" && <HistoricHunts />}
				{route === "dex" && (
					<Collection
						focusPokemonId={focusPokemonId}
						onFocusHandled={() => setFocusPokemonId(null)}
						onStartHunt={(pokemon, pokemonRoute) => {
							setHuntPrefill({ pokemon, route: pokemonRoute });
							setNewHuntOpen(true);
						}}
					/>
				)}
				{route === "games" && <CollectionManager />}
				{route === "stats" && <Stats />}
				{route === "odds-calc" && <OddsCalculator />}
				{route === "method-library" && <MethodLibrary />}
				{route === "admin" && <Admin />}
			</div>

			{/* Mobile bottom navigation bar */}
			<BottomNav
				route={route}
				setRoute={setRoute}
				activeHuntCount={activeHuntCount}
			/>

			{/* Mobile "More" sheet — Tools, Admin, Account */}
			<MoreSheet
				open={moreOpen}
				onClose={() => setMoreOpen(false)}
				route={route}
				setRoute={setRoute}
				onLogout={logout}
			/>

			<NewHuntModal
				open={newHuntOpen}
				onClose={() => {
					setNewHuntOpen(false);
					setHuntPrefill(null);
				}}
				onGoToGames={() => {
					setNewHuntOpen(false);
					setHuntPrefill(null);
					setRoute("games");
				}}
				onHuntStarted={handleHuntStarted}
				prefill={huntPrefill}
			/>

			<CommandSearch
				open={searchOpen}
				onClose={() => setSearchOpen(false)}
				onStartHunt={(p) => {
					setHuntPrefill({ pokemon: p });
					setNewHuntOpen(true);
					setSearchOpen(false);
				}}
				onViewInDex={(p) => {
					setRoute("dex");
					setFocusPokemonId(p.id);
					setSearchOpen(false);
				}}
			/>
		</div>
	);
}

export default App;
