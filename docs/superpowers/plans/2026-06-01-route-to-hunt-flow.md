# Route-to-Hunt Flow Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make starting a hunt from the Living Dex honest and fast — routes that need no parameters start instantly from the drawer, parameter routes get a slim confirm+params step instead of a duplicate route list, the page no longer hard-reloads, the route list is grouped by game, and each row shows whether the user's Shiny Charm is factored.

**Architecture:** Frontend-first. A shared `startRouteHunt` helper and a `routeNeedsParams` predicate (derived from the same formula list `HuntParametersEditor` already uses) remove duplication. `DexDrawer` branches on `routeNeedsParams`: no-param routes POST directly and refresh the Dashboard via a lifted `huntsVersion` counter (replacing `window.location.reload()`); param routes open `NewHuntModal` pre-driven by the chosen route (no refetch, no loading flash, no duplicate list). `RouteList` groups direct routes by game. One small, clearly-flagged backend addition exposes the already-computed `HasShinyCharm` on the route response so the charm chip is drift-free.

**Tech Stack:** React 19 + TypeScript + Vite (frontend, Biome lint, no unit-test runner), Go + chi + pgx (backend, `go test`).

---

## Conventions & Verification

- **No frontend test runner exists** (per CLAUDE.md). Frontend verification per task = `cd frontend && npm run build` (tsc + vite) and `npm run lint` (Biome) must pass with **no new errors** (the repo already has ~182 pre-existing Biome errors; do not fix unrelated ones, just introduce none). Behavior is verified manually in the dev server in the final task.
- **Backend** has Go tests; verification = `cd backend && go build ./... && go test ./...`.
- Match existing dark-theme tokens (`--bg-*`, `--line-*`, `--ink-*`, `--gold*`, `--font-mono`) and the surrounding code style (tabs, double quotes).
- Commit after each task.

## File Map

**Create:**
- `frontend/src/features/routes/startHunt.ts` — shared POST helper for starting a route hunt.
- `frontend/src/features/new-hunt/ChosenRoute.tsx` — compact confirmation card + params for the prefill path.

**Modify:**
- `frontend/src/utils/odds.ts` — add `PARAM_FORMULAS` + `routeNeedsParams`.
- `frontend/src/components/ui/HuntParametersEditor.tsx` — consume `PARAM_FORMULAS` (DRY).
- `frontend/src/types/models.ts` — add `has_shiny_charm?: boolean` to `PokemonRoute`.
- `frontend/src/App.tsx` — `huntsVersion` counter + `handleHuntStarted`; pass to `Dashboard`, `Collection`, `NewHuntModal`.
- `frontend/src/components/Dashboard.tsx` — accept `refreshKey`, refetch on change.
- `frontend/src/components/Collection.tsx` — thread `onHuntStarted` to `DexDrawer`.
- `frontend/src/components/DexDrawer.tsx` — instant-start branch + `onHuntStarted` prop.
- `frontend/src/components/NewHuntModal.tsx` — use shared helper; `onHuntStarted` instead of reload; prefill drives confirmation; gate the route fetch.
- `frontend/src/features/routes/RouteList.tsx` — group direct routes by game; charm chip; `showGame` row control.
- `frontend/src/index.css` — `.dex-route-charm` chip + `.dex-route-gamehead` subheader.
- `backend/internal/calc/routes.go` — add `HasShinyCharm` field to `Route`; set it in `computeRoute`.

---

## Task 1: Shared route helpers (predicate + POST)

**Files:**
- Modify: `frontend/src/utils/odds.ts` (top of file, after the `OddsResult` interface)
- Modify: `frontend/src/components/ui/HuntParametersEditor.tsx:10-20`
- Create: `frontend/src/features/routes/startHunt.ts`

- [ ] **Step 1: Add `PARAM_FORMULAS` + `routeNeedsParams` to `odds.ts`**

Insert after line 4 (`}` closing `OddsResult`) in `frontend/src/utils/odds.ts`:

```ts
/**
 * Formula types that require user-supplied parameters at hunt start
 * (a chain length, search level, or Sparkling Power). Every other formula
 * derives its odds from the live encounter counter and needs no setup step.
 * This is the single source of truth shared by HuntParametersEditor (which
 * renders the inputs) and the drawer (which decides whether to open the modal).
 */
export const PARAM_FORMULAS = [
	"outbreak_defeats_sv",
	"radar_chain_gen4",
	"sos_chain_gen7",
	"dexnav_gen6",
	"sandwich_power_sv",
] as const;

export function routeNeedsParams(formulaType: string | null | undefined): boolean {
	return !!formulaType && (PARAM_FORMULAS as readonly string[]).includes(formulaType);
}
```

- [ ] **Step 2: Make `HuntParametersEditor` consume the shared list**

In `frontend/src/components/ui/HuntParametersEditor.tsx`, replace lines 10-20 (the local `validFormulas` array and the guard) with:

```ts
	if (!formulaType || !routeNeedsParams(formulaType)) {
		return null;
	}
```

Add the import at the top of the file (the file currently has no imports; add this as line 1):

```ts
import { routeNeedsParams } from "../../utils/odds";
```

- [ ] **Step 3: Create the shared `startRouteHunt` helper**

Create `frontend/src/features/routes/startHunt.ts`:

```ts
import { API_BASE } from "../../config";
import type { Pokemon, PokemonRoute } from "../../types/models";

/**
 * POSTs a new hunt for a route. For evolve routes the hunt is created on the
 * pre-evolution (evolve_from), matching the existing NewHuntModal behavior.
 * Returns the raw Response so callers can branch on res.ok and read res.text().
 */
export async function startRouteHunt(
	route: PokemonRoute,
	targetPokemon: Pokemon,
	huntParams: Record<string, unknown>,
	token: string | null,
): Promise<Response> {
	return fetch(`${API_BASE}/api/hunts`, {
		method: "POST",
		headers: {
			"Content-Type": "application/json",
			Authorization: `Bearer ${token}`,
		},
		body: JSON.stringify({
			hunt_method_id: route.method_id,
			pokemon_id: route.evolve_from ? route.evolve_from.pokemon_id : targetPokemon.id,
			game_id: route.game_id,
			method_name: route.method_name,
			hunt_parameters: huntParams,
		}),
	});
}
```

- [ ] **Step 4: Verify build + lint**

Run: `cd frontend && npm run build && npm run lint`
Expected: build succeeds; no new Biome errors referencing `odds.ts`, `HuntParametersEditor.tsx`, or `startHunt.ts`.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/utils/odds.ts frontend/src/components/ui/HuntParametersEditor.tsx frontend/src/features/routes/startHunt.ts
git commit -m "refactor(hunt): extract routeNeedsParams + startRouteHunt helpers"
```

---

## Task 2: Replace page reload with a Dashboard refresh signal

**Files:**
- Modify: `frontend/src/App.tsx:30-41`, `:88-92`, `:127-139`
- Modify: `frontend/src/components/Dashboard.tsx:28-31`, `:72-74`
- Modify: `frontend/src/components/NewHuntModal.tsx:15-22`, `:160-162`, `:187-189`

- [ ] **Step 1: Add the version counter + handler in `App.tsx`**

In `frontend/src/App.tsx`, after line 38 (`const [activeHuntCount, setActiveHuntCount] = useState(0);`) add:

```tsx
	const [huntsVersion, setHuntsVersion] = useState(0);
	const handleHuntStarted = () => setHuntsVersion((v) => v + 1);
```

- [ ] **Step 2: Pass `refreshKey` to `Dashboard`**

Replace lines 88-91 of `App.tsx`:

```tsx
						<Dashboard
							onNewHunt={() => setNewHuntOpen(true)}
							onHuntCountChange={setActiveHuntCount}
							refreshKey={huntsVersion}
						/>
```

- [ ] **Step 3: Pass `onHuntStarted` to `NewHuntModal`**

In the `<NewHuntModal ... />` block (lines 127-139 of `App.tsx`), add the prop (keep the existing `open`, `onClose`, `onGoToGames`, `prefill`):

```tsx
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
```

- [ ] **Step 4: Consume `refreshKey` in `Dashboard`**

In `frontend/src/components/Dashboard.tsx`, change the `Props` interface (lines 28-31) to:

```tsx
interface Props {
	onNewHunt: () => void;
	onHuntCountChange: (n: number) => void;
	refreshKey?: number;
}
```

Update the component signature (line 33):

```tsx
const Dashboard: React.FC<Props> = ({ onNewHunt, onHuntCountChange, refreshKey }) => {
```

Update the fetch effect deps (line 72-74):

```tsx
	useEffect(() => {
		fetchHunts();
	}, [token, refreshKey]);
```

> Note: `fetchHunts` is defined inline in the component and intentionally omitted from deps to match the existing pattern (it already omits itself). Keep the existing `// eslint`/biome behavior — do not add `fetchHunts` to the array.

- [ ] **Step 5: Add `onHuntStarted` to `NewHuntModal` props and replace both reloads**

In `frontend/src/components/NewHuntModal.tsx`, extend `Props` (lines 15-20):

```tsx
interface Props {
	open: boolean;
	onClose: () => void;
	onGoToGames?: () => void;
	onHuntStarted?: () => void;
	prefill?: { pokemon: Pokemon; route?: PokemonRoute } | null;
}
```

Update the destructure (line 22):

```tsx
const NewHuntModal: React.FC<Props> = ({ open, onClose, onGoToGames, onHuntStarted, prefill }) => {
```

Replace lines 160-162 (inside `startHunt`):

```tsx
			if (res.ok) {
				onHuntStarted?.();
				onClose();
			} else {
```

Replace lines 187-189 (inside `startCustomHunt`):

```tsx
			if (res.ok) {
				onHuntStarted?.();
				onClose();
			} else {
```

- [ ] **Step 6: Verify build + lint**

Run: `cd frontend && npm run build && npm run lint`
Expected: build succeeds; no new Biome errors.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/App.tsx frontend/src/components/Dashboard.tsx frontend/src/components/NewHuntModal.tsx
git commit -m "feat(hunt): refresh dashboard via version signal instead of full page reload"
```

---

## Task 3: Instant-start no-parameter routes from the drawer

**Files:**
- Modify: `frontend/src/components/DexDrawer.tsx:1-16`, `:18-27`, `:133-138`
- Modify: `frontend/src/components/Collection.tsx:24-28`, `:113-118`, `:292-315`
- Modify: `frontend/src/App.tsx:95-103`

- [ ] **Step 1: Add `onHuntStarted` + instant-start to `DexDrawer`**

In `frontend/src/components/DexDrawer.tsx`, update imports (lines 1-8) to add the helpers:

```tsx
import type React from "react";
import { useEffect, useRef, useState } from "react";
import { API_BASE } from "../config";
import { useAuth } from "../context/AuthContext";
import { useNotification } from "../context/NotificationContext";
import RouteList from "../features/routes/RouteList";
import { startRouteHunt } from "../features/routes/startHunt";
import { usePokemonRoute } from "../features/routes/usePokemonRoute";
import { defaultParamsFor, routeNeedsParams } from "../utils/odds";
import type { Pokemon, PokemonRoute } from "../types/models";
```

Extend `Props` (lines 10-16):

```tsx
interface Props {
	pokemon: Pokemon;
	caught: boolean;
	onClose: () => void;
	onCaughtChange: (pokemonId: number, caught: boolean) => void;
	onStartHunt: (pokemon: Pokemon, route: PokemonRoute) => void;
	onHuntStarted?: () => void;
}
```

Update the destructure (lines 18-24):

```tsx
const DexDrawer: React.FC<Props> = ({
	pokemon,
	caught,
	onClose,
	onCaughtChange,
	onStartHunt,
	onHuntStarted,
}) => {
	const { token } = useAuth();
	const { showError, showSuccess } = useNotification();
```

Add an instant-start handler after the `removeCaught` function (after line 83, before the `return`):

```tsx
	const handleRouteClick = async (route: PokemonRoute) => {
		// Parameter routes (chain/power) need the modal's setup step.
		if (routeNeedsParams(route.formula_type)) {
			onStartHunt(pokemon, route);
			return;
		}
		// Everything else starts immediately — no modal, no reload.
		try {
			const res = await startRouteHunt(route, pokemon, defaultParamsFor(route.formula_type), token);
			if (!res.ok) throw new Error((await res.text()) || "Failed to start hunt.");
			showSuccess(`Started hunt · ${route.method_name}`);
			onHuntStarted?.();
			onClose();
		} catch (err) {
			showError((err as Error).message || "Failed to start hunt.");
		}
	};
```

Wire the list to it (replace lines 133-138):

```tsx
						{!loading && !error && routes.length > 0 && (
							<RouteList routes={routes} onRouteClick={handleRouteClick} />
						)}
```

- [ ] **Step 2: Thread `onHuntStarted` through `Collection`**

In `frontend/src/components/Collection.tsx`, extend the prop type (lines 24-28):

```tsx
const Collection: React.FC<{
	onStartHunt?: (pokemon: Pokemon, route: PokemonRoute) => void;
	onHuntStarted?: () => void;
	focusPokemonId?: number | null;
	onFocusHandled?: () => void;
}> = ({ onStartHunt, onHuntStarted, focusPokemonId, onFocusHandled }) => {
```

Pass it to `DexDrawer` (replace lines 296-313, the `<DexDrawer .../>` element, keeping existing handlers and adding `onHuntStarted`):

```tsx
						<DexDrawer
							pokemon={p}
							caught={caughtIds.has(p.id)}
							onClose={() => setDrawerId(null)}
							onCaughtChange={(id, isCaught) => {
								setCaughtIds((prev) => {
									const next = new Set(prev);
									if (isCaught) next.add(id);
									else next.delete(id);
									return next;
								});
							}}
							onStartHunt={(poke, route) => {
								setDrawerId(null);
								onStartHunt?.(poke, route);
							}}
							onHuntStarted={onHuntStarted}
						/>
```

> Note: `HuntNextPanel` at Collection.tsx:115-118 calls `onStartHunt` for its suggestions — leave it unchanged; those still route through the modal.

- [ ] **Step 3: Pass `onHuntStarted` to `Collection` from `App`**

In `frontend/src/App.tsx`, update the `<Collection .../>` block (lines 95-103):

```tsx
					{route === "dex" && (
						<Collection
							focusPokemonId={focusPokemonId}
							onFocusHandled={() => setFocusPokemonId(null)}
							onStartHunt={(pokemon, pokemonRoute) => {
								setHuntPrefill({ pokemon, route: pokemonRoute });
								setNewHuntOpen(true);
							}}
							onHuntStarted={handleHuntStarted}
						/>
					)}
```

- [ ] **Step 4: Verify build + lint**

Run: `cd frontend && npm run build && npm run lint`
Expected: build succeeds; no new Biome errors.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/DexDrawer.tsx frontend/src/components/Collection.tsx frontend/src/App.tsx
git commit -m "feat(dex): start no-parameter routes instantly from the drawer"
```

---

## Task 4: Slim the modal for prefilled routes (confirm + params, no duplicate list)

After Task 3, a `prefill.route` reaching the modal is always a parameter route. Drive the modal from `prefill.route` directly so there is no loading flash and no second route fetch; only fetch the full list if the user clicks "Change method".

**Files:**
- Create: `frontend/src/features/new-hunt/ChosenRoute.tsx`
- Modify: `frontend/src/components/NewHuntModal.tsx:25-37`, `:86-113`, `:346-466`

- [ ] **Step 1: Create the `ChosenRoute` confirmation component**

Create `frontend/src/features/new-hunt/ChosenRoute.tsx`:

```tsx
import type { PokemonRoute } from "../../types/models";
import { HuntParametersEditor } from "../../components/ui/HuntParametersEditor";

interface Props {
	route: PokemonRoute;
	huntParams: Record<string, any>;
	setHuntParams: (params: Record<string, any>) => void;
	onChange: () => void;
}

/**
 * Compact confirmation for an already-chosen route: method + game + odds/eta,
 * the parameter inputs (if the formula needs them), and a "Change method" link.
 * Replaces the full RouteList in the prefill path so the user isn't re-asked
 * the choice they just made.
 */
export function ChosenRoute({ route, huntParams, setHuntParams, onChange }: Props) {
	return (
		<div
			style={{
				padding: 16,
				background: "var(--bg-2)",
				border: "1px solid var(--line-1)",
				borderRadius: 12,
				marginBottom: 4,
			}}
		>
			<div style={{ display: "flex", alignItems: "flex-start", gap: 8 }}>
				<div style={{ flex: 1 }}>
					<div
						style={{
							fontFamily: "var(--font-display)",
							fontSize: 15,
							fontWeight: 600,
						}}
					>
						{route.method_name}
					</div>
					<div
						style={{
							fontFamily: "var(--font-mono)",
							fontSize: 10.5,
							color: "var(--ink-3)",
							marginTop: 2,
						}}
					>
						{route.evolve_from ? `${route.evolve_from.name} · ${route.game_title}` : route.game_title}
					</div>
					{route.evolve_from && (
						<div className="dex-route-evo">↳ then evolve</div>
					)}
				</div>
				<button
					className="btn ghost"
					style={{ fontSize: 11 }}
					onClick={onChange}
				>
					Change method
				</button>
			</div>

			<div
				style={{
					display: "grid",
					gridTemplateColumns: "1fr 1fr",
					gap: 8,
					marginTop: 14,
					paddingTop: 14,
					borderTop: "1px solid var(--line-1)",
				}}
			>
				<div>
					<div className="t-label">Odds (best case)</div>
					<div
						className="t-mono"
						style={{ fontSize: 13, marginTop: 2, color: "var(--gold)", fontWeight: 600 }}
					>
						1 / {route.odds.toLocaleString()}
					</div>
				</div>
				<div>
					<div className="t-label">ETA expected</div>
					<div className="t-mono" style={{ fontSize: 13, marginTop: 2 }}>
						~{route.eta_hours.toFixed(1)} h
					</div>
				</div>
			</div>

			<HuntParametersEditor
				formulaType={route.formula_type}
				huntParams={huntParams}
				setHuntParams={setHuntParams}
			/>
		</div>
	);
}
```

- [ ] **Step 2: Add `changing` state and gate the route fetch in `NewHuntModal`**

In `frontend/src/components/NewHuntModal.tsx`, add the import (after line 13):

```tsx
import { ChosenRoute } from "../features/new-hunt/ChosenRoute";
```

Add state after line 35 (`const [starting, setStarting] = useState(false);`):

```tsx
	const [changing, setChanging] = useState(false);
```

Replace line 37 (the route hook call) so the prefill path does not fetch until the user changes method:

```tsx
	// In the prefill path the chosen route already carries odds/eta/formula, so
	// we skip the route fetch entirely (no flash, no double-fetch). It only runs
	// once the user clicks "Change method".
	const routeFetchId = prefill?.route && !changing ? null : (selectedPokemon?.id ?? null);
	const { status, routes, loading: loadingRoutes } = usePokemonRoute(routeFetchId);
```

- [ ] **Step 3: Reset `changing` on close and select the prefill route directly**

In the close-reset effect, add `setChanging(false);` alongside the other resets (after line 50, `setHuntParams({});`):

```tsx
			setChanging(false);
```

Replace the prefill effect (lines 86-92) so it selects the route immediately without waiting for a fetch:

```tsx
	// When opened with prefill, jump to step 2 with the target Pokémon pre-selected.
	// If a route was provided, select it directly from the prefill (no fetch needed).
	useEffect(() => {
		if (open && prefill) {
			setSelectedPokemon(prefill.pokemon);
			setStep(2);
			if (prefill.route) {
				setSelectedRoute(prefill.route);
				setHuntParams(defaultParamsFor(prefill.route.formula_type));
			}
		}
	}, [open, prefill]);
```

Delete the now-redundant route-rematch effect (lines 104-113, the `useEffect` commented "Once routes load, select the prefill route by key"). The prefill route is selected directly in the effect above; the rematch is no longer needed and would fight the gated fetch.

> Keep the default-selection effect (lines 96-102) — it still drives the no-prefill search path and is already guarded by `!prefillHasRoute`.

- [ ] **Step 4: Render `ChosenRoute` instead of the list in the prefill path**

In step 2's JSX, the route-picking region currently spans the `loadingRoutes` block through the custom-method block and `MethodPreview` (lines 346-466). Wrap it so the prefill-confirm path replaces it. Replace lines 346-466 with:

```tsx
							{prefill?.route && !changing ? (
								<ChosenRoute
									route={selectedRoute ?? prefill.route}
									huntParams={huntParams}
									setHuntParams={setHuntParams}
									onChange={() => {
										setChanging(true);
										setSelectedRoute(null);
									}}
								/>
							) : (
								<>
									{loadingRoutes && (
										<div className="empty" style={{ padding: 20 }}>
											Loading methods…
										</div>
									)}

									{!loadingRoutes && routes.length > 0 && (
										<RouteList
											routes={routes}
											variant="select"
											selectedKey={selectedRoute && !useCustomMethod ? routeKey(selectedRoute) : undefined}
											onRouteClick={(r) => {
												setSelectedRoute(r);
												setUseCustomMethod(false);
												setHuntParams(defaultParamsFor(r.formula_type));
											}}
										/>
									)}

									{!loadingRoutes && userGameCount === 0 && routes.length === 0 && (
										<div className="empty" style={{ textAlign: "center", padding: "20px 0" }}>
											<div style={{ marginBottom: 6 }}>You haven't added any games yet.</div>
											<div className="t-label" style={{ marginBottom: 14 }}>
												Add a game to your library to see available hunt methods.
											</div>
											{onGoToGames && (
												<button className="btn gold" onClick={onGoToGames}>
													Go to Game Library →
												</button>
											)}
										</div>
									)}

									{!loadingRoutes && status === "not_in_your_games" && userGameCount !== null && userGameCount > 0 && (
										<div className="empty" style={{ textAlign: "center", padding: "20px 0" }}>
											<div style={{ marginBottom: 6, textTransform: "capitalize" }}>
												{selectedPokemon.name} isn't available in your games.
											</div>
											<div className="t-label" style={{ marginBottom: 14 }}>
												Try adding a game that includes it, or it may be shiny-locked.
											</div>
											{onGoToGames && (
												<button className="btn ghost" onClick={onGoToGames} style={{ fontSize: 12 }}>
													Manage games →
												</button>
											)}
										</div>
									)}

									{!loadingRoutes && status === "locked_everywhere" && (
										<div className="empty" style={{ textAlign: "center", padding: "20px 0", textTransform: "capitalize" }}>
											{selectedPokemon.name} is shiny-locked in every game it appears in — obtain it by trading or transferring from Pokémon HOME.
										</div>
									)}

									{!loadingRoutes && status === "available" && routes.length === 0 && (
										<div className="empty" style={{ textAlign: "center", padding: "20px 0" }}>
											Available in your games, but no hunt method recorded yet.
										</div>
									)}

									{!loadingRoutes && (
										<>
											<div className="t-label" style={{ margin: "12px 0 6px" }}>
												Custom method
											</div>
											<div
												className={`opt-row ${useCustomMethod ? "sel" : ""}`}
												onClick={() => {
													setUseCustomMethod(true);
													setSelectedRoute(null);
												}}
												style={{ alignItems: "center", gap: 8 }}
											>
												<div className="method" style={{ flex: 1 }}>
													Use custom method
												</div>
												<div className="t-label" style={{ fontSize: 11 }}>
													no odds data
												</div>
											</div>
											{useCustomMethod && (
												<input
													className="input"
													placeholder="e.g. Chain fishing, DexNav, Outbreak…"
													value={customMethodName}
													onChange={(e) => setCustomMethodName(e.target.value)}
													style={{ marginTop: 8 }}
													autoFocus
												/>
											)}
										</>
									)}

									<MethodPreview
										selectedPokemon={selectedPokemon}
										selectedRoute={selectedRoute}
										useCustomMethod={useCustomMethod}
										customMethodName={customMethodName}
										gifUrl={gifUrl}
										huntParams={huntParams}
										setHuntParams={setHuntParams}
									/>

									{selectedRoute?.evolve_from && !useCustomMethod && (
										<div className="t-label" style={{ marginTop: 10 }}>
											You'll hunt {selectedRoute.evolve_from.name}, then evolve into {selectedPokemon.name}.
										</div>
									)}
								</>
							)}
```

> The Cancel/Start footer block that follows (original lines 474-512) stays exactly as-is — it already reads `selectedRoute`/`useCustomMethod`, both of which are set correctly in the prefill path.

- [ ] **Step 5: Verify build + lint**

Run: `cd frontend && npm run build && npm run lint`
Expected: build succeeds; no new Biome errors. Confirm `RouteList`, `routeKey`, `MethodPreview` are still imported/used (they are, in the non-prefill branch).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/components/NewHuntModal.tsx frontend/src/features/new-hunt/ChosenRoute.tsx
git commit -m "feat(hunt): prefilled routes show confirm+params, not a duplicate list"
```

---

## Task 5: Group the route list by game

**Files:**
- Modify: `frontend/src/features/routes/RouteList.tsx` (whole `Section`/render structure)
- Modify: `frontend/src/index.css` (add `.dex-route-gamehead`)

- [ ] **Step 1: Rework `RouteList` to group direct routes by game**

Replace the entire body of `frontend/src/features/routes/RouteList.tsx` (keep the `routeKey` export unchanged at the top) with:

```tsx
import type React from "react";
import type { PokemonRoute } from "../../types/models";

// Stable identity for a route, used for selection highlighting.
// Assumes (kind, game_id, method_id) is unique per route — method_id is unique
// per game, so do not weaken this to method_name.
export function routeKey(r: PokemonRoute): string {
	return `${r.kind}-${r.game_id}-${r.method_id}`;
}

interface Props {
	routes: PokemonRoute[];
	selectedKey?: string;
	onRouteClick: (route: PokemonRoute) => void;
	variant?: "launch" | "select";
}

interface GameGroup {
	gameId: number;
	gameTitle: string;
	routes: PokemonRoute[];
}

// Groups routes by game, orders games by their best (lowest) odds, and keeps
// the backend's ascending-odds order within each game.
function groupByGame(routes: PokemonRoute[]): GameGroup[] {
	const map = new Map<number, PokemonRoute[]>();
	for (const r of routes) {
		const arr = map.get(r.game_id);
		if (arr) arr.push(r);
		else map.set(r.game_id, [r]);
	}
	const groups: GameGroup[] = Array.from(map.entries()).map(([gameId, rs]) => ({
		gameId,
		gameTitle: rs[0].game_title,
		routes: rs,
	}));
	groups.sort(
		(a, b) =>
			Math.min(...a.routes.map((r) => r.odds)) - Math.min(...b.routes.map((r) => r.odds)),
	);
	return groups;
}

const RouteList: React.FC<Props> = ({ routes, selectedKey, onRouteClick, variant = "launch" }) => {
	const direct = routes.filter((r) => r.kind === "direct");
	const evolve = routes.filter((r) => r.kind === "evolve");
	return (
		<>
			{direct.length > 0 && (
				<div style={{ marginBottom: 14 }}>
					<div className="t-label" style={{ marginBottom: 8 }}>
						Routes in your games
					</div>
					{groupByGame(direct).map((g) => (
						<div key={g.gameId} style={{ marginBottom: 10 }}>
							<div className="dex-route-gamehead">{g.gameTitle}</div>
							{g.routes.map((r) => (
								<Row
									key={routeKey(r)}
									route={r}
									showGame={false}
									selectedKey={selectedKey}
									onRouteClick={onRouteClick}
									variant={variant}
								/>
							))}
						</div>
					))}
				</div>
			)}
			{evolve.length > 0 && (
				<div style={{ marginBottom: 14 }}>
					<div className="t-label" style={{ marginBottom: 8 }}>
						Hunt a pre-evolution
					</div>
					{evolve.map((r) => (
						<Row
							key={routeKey(r)}
							route={r}
							showGame={true}
							selectedKey={selectedKey}
							onRouteClick={onRouteClick}
							variant={variant}
						/>
					))}
				</div>
			)}
		</>
	);
};

const Row: React.FC<{
	route: PokemonRoute;
	showGame: boolean;
	selectedKey?: string;
	onRouteClick: (route: PokemonRoute) => void;
	variant?: "launch" | "select";
}> = ({ route: r, showGame, selectedKey, onRouteClick, variant }) => {
	const key = routeKey(r);
	return (
		<div
			className={`dex-route ${selectedKey === key ? "sel" : ""}`}
			onClick={() => onRouteClick(r)}
		>
			<div>
				<div className="dex-route-name">{r.method_name}</div>
				{showGame && (
					<div className="dex-route-game">
						{r.evolve_from ? `${r.evolve_from.name} · ${r.game_title}` : r.game_title}
					</div>
				)}
				{r.evolve_from && <div className="dex-route-evo">↳ then evolve</div>}
			</div>
			<div style={{ textAlign: "right" }}>
				<div className="dex-route-odds">1 / {r.odds.toLocaleString()}</div>
				{r.has_shiny_charm && <div className="dex-route-charm">✦ Charm</div>}
				<div className="dex-route-eta" style={{ opacity: 0.65 }}>best case</div>
				<div className="dex-route-eta">~{r.eta_hours.toFixed(1)} h</div>
				{variant === "launch" && <div className="dex-route-start">▸ Start</div>}
			</div>
		</div>
	);
};

export default RouteList;
```

> The `.dex-route-charm` class is styled in Task 6. Including the JSX here is harmless until then (it renders nothing because `has_shiny_charm` is undefined until Task 6 adds the field).

- [ ] **Step 2: Add the game-subheader style**

In `frontend/src/index.css`, add immediately before the `.dex-route` rule:

```css
.dex-route-gamehead {
	font-family: var(--font-mono);
	font-size: 10px;
	letter-spacing: 0.06em;
	text-transform: uppercase;
	color: var(--ink-4);
	margin: 0 2px 5px;
}
```

- [ ] **Step 3: Verify build + lint**

Run: `cd frontend && npm run build && npm run lint`
Expected: build succeeds; no new Biome errors.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/features/routes/RouteList.tsx frontend/src/index.css
git commit -m "feat(routes): group route list by game, best odds first"
```

---

## Task 6: Shiny-charm chip (exposes already-computed charm flag)

> **Deviation flag:** the scope choice was "frontend-only, no schema change." This task adds **one JSON field** to the Go route response (no DB migration). It is the correct, drift-free way to show the chip: the backend already gates charm via `ShinyCharmAvailable`, so replicating that on the frontend would risk showing the chip when charm wasn't actually applied. If you'd rather keep it strictly frontend-only, we drop this task (the `has_shiny_charm` JSX added in Task 5 simply stays inert). **Confirm before executing this task.**

**Files:**
- Modify: `backend/internal/calc/routes.go:27-37`, `:54-62`
- Modify: `frontend/src/types/models.ts:75-85`
- Modify: `frontend/src/index.css` (add `.dex-route-charm`)

- [ ] **Step 1: Add the field to the Go `Route` struct**

In `backend/internal/calc/routes.go`, add the field after `EvolveFrom` (line 36):

```go
	EvolveFrom    *EvolveFrom `json:"evolve_from,omitempty"`
	HasShinyCharm bool        `json:"has_shiny_charm"`
```

- [ ] **Step 2: Set it in `computeRoute`**

In `computeRoute`, add to the returned `Route` literal (after `ETAHours: eta,` on line 61):

```go
		Odds:          odds,
		ETAHours:      eta,
		HasShinyCharm: c.HasShinyCharm,
```

> `c.HasShinyCharm` is already correctly gated upstream (`dex.go:115`/`:297`: `c.HasShinyCharm = c.HasShinyCharm && calc.ShinyCharmAvailable(c.GameID)`), so this value reflects exactly what was used to compute `odds`.

- [ ] **Step 3: Verify backend build + tests**

Run: `cd backend && go build ./... && go test ./internal/calc/...`
Expected: build succeeds; existing calc tests pass (they don't assert on `HasShinyCharm` JSON, so adding the field is non-breaking).

- [ ] **Step 4: Add the field to the frontend type**

In `frontend/src/types/models.ts`, add to the `PokemonRoute` interface (after line 84, `evolve_from?: ...`):

```ts
	evolve_from?: { pokemon_id: number; name: string };
	has_shiny_charm?: boolean;
```

- [ ] **Step 5: Style the chip**

In `frontend/src/index.css`, add near the other `.dex-route-*` rules:

```css
.dex-route-charm {
	font-family: var(--font-mono);
	font-size: 9px;
	letter-spacing: 0.04em;
	color: var(--gold);
	margin-top: 1px;
}
```

- [ ] **Step 6: Verify frontend build + lint**

Run: `cd frontend && npm run build && npm run lint`
Expected: build succeeds; no new Biome errors. The "✦ Charm" chip now renders on rows for games where the user owns the (applicable) Shiny Charm.

- [ ] **Step 7: Commit**

```bash
git add backend/internal/calc/routes.go frontend/src/types/models.ts frontend/src/index.css
git commit -m "feat(routes): surface shiny-charm chip on charm-applied routes"
```

---

## Task 7: Integration verification + review

**Files:** none (verification only)

- [ ] **Step 1: Build everything clean**

Run: `cd frontend && npm run build && npm run lint` then `cd ../backend && go build ./... && go test ./...`
Expected: all pass; no new frontend lint errors.

- [ ] **Step 2: Manual flow check in the dev server**

Start backend (`cd backend && go run ./cmd/api/main.go`) and frontend (`cd frontend && npm run dev`), sign in, go to the Collection tab, and verify:

1. Click a Pokémon whose best route is a **no-param** method (e.g. a Masuda/static/Run-Away route). Clicking the row **starts the hunt immediately**, shows a success toast, closes the drawer, and **no full page reload** happens.
2. Switch to the Dashboard tab — the new hunt appears (refresh signal worked) without a manual reload.
3. Click a Pokémon with a **parameter** route (e.g. Caterpie → Poké Radar / SOS Chaining). Clicking it opens the modal showing a **single confirmation card** (method + game + odds + the parameter input) — **not** the full repeated route list — with no "Loading methods…" flash.
4. In that modal, click **Change method** → the full grouped list appears and a different route can be picked.
5. The route list (drawer + modal "change") is **grouped by game** with a game subheader, games ordered best-odds-first.
6. For a game where you own the Shiny Charm, the row shows the **✦ Charm** chip (only if Task 6 was executed).
7. Confirm the unrelated paths still work: Topbar "+New hunt" (search → pick route → start) and ⌘K command search → "start hunt".

- [ ] **Step 3: Code review**

Dispatch `code-reviewer` on the full branch diff (`git diff master`). Address any high/medium findings before merge, per the repo's orchestration rules.

---

## Self-Review Notes (author)

- **Spec coverage:** Core rework = Tasks 1–4 (instant-start, no reload, prefill confirm, no double-fetch via gated fetch). List polish = Task 5 (group by game) + Task 6 (charm chip). All six critique items mapped.
- **"best case" label:** kept — verified accurate (backend `DefaultParams` uses max chain, e.g. radar → 1/200). Charm is communicated via the chip rather than a relabel, since the odds are already charm-adjusted.
- **Double-fetch:** fully eliminated for the prefill path by gating `usePokemonRoute` to `null` until "Change method" (Step 4.2), not merely hidden.
- **Scope deviation:** Task 6 needs a 3-line backend field (no DB change) — flagged for explicit approval; droppable without affecting Tasks 1–5.
- **No new test files:** repo has no frontend test runner (CLAUDE.md); verification is build + lint + manual. Backend reuses existing `go test`.
