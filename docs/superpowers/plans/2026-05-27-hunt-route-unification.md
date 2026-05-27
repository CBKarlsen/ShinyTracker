# Hunt Route Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The New Hunt modal and the dex detail drawer render the same routes from the same endpoint via one shared component, so they look identical and never disagree.

**Architecture:** Extend the backend `Route` with `method_id` + `formula_type` (sourced from the existing candidate query). On the frontend, add a `usePokemonRoute` hook + a presentational `<RouteList>` (lifted from the drawer), and point both the drawer and the modal's step 2 at them. The modal keeps its shell (search, custom method, params, Start) and starts via `route.method_id` (the ancestor's, for evolve routes); the drawer stays a launcher.

**Tech Stack:** Go 1.26 (pgx, built-in `testing`); React 19 + TypeScript + Vite + Biome.

**Reference spec:** `docs/superpowers/specs/2026-05-27-hunt-route-unification-design.md`

**Conventions:** No ORM (raw SQL, `$1/$2`). Backend pure logic is TDD'd with `go test`; frontend has no test framework — verify with `npm run build` (the gate) + not increasing lint errors materially (baseline ~160). Commit after each task. Run all git/build commands with absolute paths into the worktree `/Users/casper/Fritidsprosjekt/ShinyTracker/.claude/worktrees/dex-completion-engine`.

---

## File Structure

**Backend**
- `backend/internal/calc/routes.go` — add `MethodID`/`FormulaType` to `MethodCandidate` + `Route` (MODIFY)
- `backend/internal/calc/routes_test.go` — assert the new fields propagate (MODIFY)
- `backend/internal/api/dex.go` — `fetchMethodCandidates` SELECT/Scan add `hm.id`, `hm.formula_type` (MODIFY)

**Frontend**
- `frontend/src/types/models.ts` — `PokemonRoute` gains `method_id`, `formula_type` (MODIFY)
- `frontend/src/features/routes/usePokemonRoute.ts` — shared fetch hook (CREATE)
- `frontend/src/features/routes/RouteList.tsx` — shared presentational route list + `routeKey` (CREATE)
- `frontend/src/index.css` — `.dex-route.sel` selection style (MODIFY)
- `frontend/src/components/DexDrawer.tsx` — use hook + `<RouteList>` (MODIFY)
- `frontend/src/components/NewHuntModal.tsx` — step 2 on route data + `<RouteList>`; delete client odds; status blocked states; start via `method_id`/ancestor (MODIFY)
- `frontend/src/features/new-hunt/MethodPreview.tsx` — consume the selected `PokemonRoute` (MODIFY)
- `frontend/src/App.tsx` — `huntPrefill` becomes `{ pokemon, route }` (MODIFY)

---

## Task 1: Backend — add MethodID + FormulaType to calc routes (TDD)

**Files:**
- Modify: `backend/internal/calc/routes.go`
- Test: `backend/internal/calc/routes_test.go`

- [ ] **Step 1: Add the failing tests**

Append to `backend/internal/calc/routes_test.go`:

```go
func TestComputeRouteCarriesMethodIDAndFormula(t *testing.T) {
	r := computeRoute(MethodCandidate{
		MethodID: 42, FormulaType: "masuda",
		BaseOdds: 4096, BaseRolls: 6, HasShinyCharm: false,
	})
	if r.MethodID != 42 {
		t.Fatalf("MethodID = %d, want 42", r.MethodID)
	}
	if r.FormulaType != "masuda" {
		t.Fatalf("FormulaType = %q, want masuda", r.FormulaType)
	}
}

func TestBestRouteCarriesAncestorMethodFields(t *testing.T) {
	best, ok := BestRoute(
		[]MethodCandidate{{MethodID: 7, FormulaType: "wild", BaseOdds: 4096, BaseRolls: 1}},
		EvolveFrom{PokemonID: 129, Name: "magikarp"},
	)
	if !ok {
		t.Fatal("expected ok=true")
	}
	if best.MethodID != 7 || best.FormulaType != "wild" {
		t.Fatalf("got MethodID=%d FormulaType=%q, want 7/wild", best.MethodID, best.FormulaType)
	}
	if best.Kind != "evolve" || best.EvolveFrom == nil {
		t.Fatal("expected an evolve route with EvolveFrom set")
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd backend && go test ./internal/calc/ -run 'MethodIDAndFormula|AncestorMethod' -v`
Expected: FAIL — `unknown field 'MethodID' in struct literal of type MethodCandidate` (and `FormulaType`).

- [ ] **Step 3: Add the fields and copy them in computeRoute**

In `backend/internal/calc/routes.go`, add two fields to `MethodCandidate`:

```go
type MethodCandidate struct {
	GameID         int
	GameTitle      string
	MethodName     string
	MethodID       int
	FormulaType    string
	BaseOdds       int
	BaseRolls      int
	CharmRolls     int
	HasShinyCharm  bool
	AvgTimeSeconds int
}
```

Add two fields to `Route` (place them after `MethodName`):

```go
type Route struct {
	Kind        string      `json:"kind"`
	GameID      int         `json:"game_id"`
	GameTitle   string      `json:"game_title"`
	MethodName  string      `json:"method_name"`
	MethodID    int         `json:"method_id"`
	FormulaType string      `json:"formula_type"`
	Odds        int         `json:"odds"`
	ETAHours    float64     `json:"eta_hours"`
	EvolveFrom  *EvolveFrom `json:"evolve_from,omitempty"`
}
```

In `computeRoute`, copy them into the returned `Route` (add to the struct literal):

```go
	return Route{
		GameID:      c.GameID,
		GameTitle:   c.GameTitle,
		MethodName:  c.MethodName,
		MethodID:    c.MethodID,
		FormulaType: c.FormulaType,
		Odds:        odds,
		ETAHours:    eta,
	}
```

(`RankDirectRoutes` and `BestRoute` already build on `computeRoute`, so they carry the new fields automatically.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd backend && go test ./internal/calc/ -v`
Expected: PASS (all tests, including the two new ones). Then `go build ./...` — clean.

- [ ] **Step 5: Commit**

```bash
cd /Users/casper/Fritidsprosjekt/ShinyTracker/.claude/worktrees/dex-completion-engine
git add backend/internal/calc/routes.go backend/internal/calc/routes_test.go
git commit -m "Add method_id + formula_type to calc Route/MethodCandidate"
```

---

## Task 2: Backend — surface method id + formula_type from the candidate query

**Files:**
- Modify: `backend/internal/api/dex.go`

- [ ] **Step 1: Extend the SELECT and Scan in fetchMethodCandidates**

In `backend/internal/api/dex.go`, replace the query + scan in `fetchMethodCandidates` with (adds `hm.id` and `hm.formula_type`, keeping SELECT and Scan column order aligned):

```go
	rows, err := database.DB.Query(ctx, `
		SELECT hm.id, g.id, g.title, hm.method_name, g.base_odds,
		       hm.base_rolls, hm.charm_rolls, hm.avg_time_seconds, ug.has_shiny_charm, hm.formula_type
		FROM method_availability ma
		JOIN hunt_methods hm ON ma.method_id = hm.id
		JOIN games g         ON g.id = ma.game_id
		JOIN user_games ug   ON ug.game_id = g.id
		WHERE ma.pokemon_id = $1 AND ug.user_id = $2
		ORDER BY g.generation ASC, g.id ASC
	`, pokemonID, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var cands []calc.MethodCandidate
	for rows.Next() {
		var c calc.MethodCandidate
		if err := rows.Scan(&c.MethodID, &c.GameID, &c.GameTitle, &c.MethodName, &c.BaseOdds,
			&c.BaseRolls, &c.CharmRolls, &c.AvgTimeSeconds, &c.HasShinyCharm, &c.FormulaType); err != nil {
			return nil, err
		}
		cands = append(cands, c)
	}
	return cands, rows.Err()
```

- [ ] **Step 2: Build + confirm calc tests still pass**

Run: `cd backend && go build ./... && go test ./internal/calc/...`
Expected: build clean; calc tests PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/casper/Fritidsprosjekt/ShinyTracker/.claude/worktrees/dex-completion-engine
git add backend/internal/api/dex.go
git commit -m "Surface method_id + formula_type in route candidate query"
```

---

## Task 3: Frontend — route types, shared hook, shared RouteList

**Files:**
- Modify: `frontend/src/types/models.ts`
- Create: `frontend/src/features/routes/usePokemonRoute.ts`
- Create: `frontend/src/features/routes/RouteList.tsx`
- Modify: `frontend/src/index.css`

- [ ] **Step 1: Extend the PokemonRoute type**

In `frontend/src/types/models.ts`, add `method_id` and `formula_type` to `PokemonRoute`:

```ts
export interface PokemonRoute {
	kind: "direct" | "evolve";
	game_id: number;
	game_title: string;
	method_name: string;
	method_id: number;
	formula_type: string;
	odds: number;
	eta_hours: number;
	evolve_from?: { pokemon_id: number; name: string };
}
```

- [ ] **Step 2: Create the shared fetch hook**

Create `frontend/src/features/routes/usePokemonRoute.ts`:

```ts
import { useEffect, useState } from "react";
import { useAuth } from "../../context/AuthContext";
import type { PokemonRouteResponse } from "../../types/models";

// Fetches GET /api/pokemon/{id}/route. Pass null to fetch nothing.
export function usePokemonRoute(pokemonId: number | null) {
	const { token } = useAuth();
	const [data, setData] = useState<PokemonRouteResponse | null>(null);
	const [loading, setLoading] = useState(false);
	const [error, setError] = useState(false);

	useEffect(() => {
		if (pokemonId == null) {
			setData(null);
			return;
		}
		let active = true;
		setLoading(true);
		setError(false);
		fetch(`http://localhost:8080/api/pokemon/${pokemonId}/route`, {
			headers: { Authorization: `Bearer ${token}` },
		})
			.then((r) => (r.ok ? r.json() : Promise.reject()))
			.then((d: PokemonRouteResponse) => {
				if (active) setData(d);
			})
			.catch(() => {
				if (active) setError(true);
			})
			.finally(() => {
				if (active) setLoading(false);
			});
		return () => {
			active = false;
		};
	}, [pokemonId, token]);

	return {
		status: data?.status ?? null,
		routes: data?.routes ?? [],
		loading,
		error,
	};
}
```

- [ ] **Step 3: Create the shared RouteList component**

Create `frontend/src/features/routes/RouteList.tsx`:

```tsx
import type React from "react";
import type { PokemonRoute } from "../../types/models";

// Stable identity for a route, used for selection highlighting.
export function routeKey(r: PokemonRoute): string {
	return `${r.kind}-${r.game_id}-${r.method_id}`;
}

interface Props {
	routes: PokemonRoute[];
	selectedKey?: string;
	onRouteClick: (route: PokemonRoute) => void;
}

const RouteList: React.FC<Props> = ({ routes, selectedKey, onRouteClick }) => {
	const direct = routes.filter((r) => r.kind === "direct");
	const evolve = routes.filter((r) => r.kind === "evolve");
	return (
		<>
			{direct.length > 0 && (
				<Section
					label="Routes in your games"
					routes={direct}
					selectedKey={selectedKey}
					onRouteClick={onRouteClick}
				/>
			)}
			{evolve.length > 0 && (
				<Section
					label="Hunt a pre-evolution"
					routes={evolve}
					selectedKey={selectedKey}
					onRouteClick={onRouteClick}
				/>
			)}
		</>
	);
};

const Section: React.FC<Props & { label: string }> = ({
	label,
	routes,
	selectedKey,
	onRouteClick,
}) => (
	<div style={{ marginBottom: 14 }}>
		<div className="t-label" style={{ marginBottom: 8 }}>
			{label}
		</div>
		{routes.map((r) => {
			const key = routeKey(r);
			return (
				<div
					key={key}
					className={`dex-route ${selectedKey === key ? "sel" : ""}`}
					onClick={() => onRouteClick(r)}
					style={{ cursor: "pointer" }}
				>
					<div>
						<div className="dex-route-name">{r.method_name}</div>
						<div className="dex-route-game">
							{r.evolve_from ? `${r.evolve_from.name} · ${r.game_title}` : r.game_title}
						</div>
						{r.evolve_from && <div className="dex-route-evo">↳ then evolve</div>}
					</div>
					<div style={{ textAlign: "right" }}>
						<div className="dex-route-odds">1 / {r.odds.toLocaleString()}</div>
						<div className="dex-route-eta">~{r.eta_hours.toFixed(1)} h</div>
					</div>
				</div>
			);
		})}
	</div>
);

export default RouteList;
```

- [ ] **Step 4: Add the selection style**

In `frontend/src/index.css`, find the `.dex-route` rule (added for the drawer) and add a selected variant right after it:

```css
.dex-route.sel { border-color: var(--gold); background: var(--gold-soft); }
```

(If `--gold-soft` isn't a defined token, use the same highlight the modal's existing `.opt-row.sel` uses — grep `index.css` for `.opt-row.sel` and match it.)

- [ ] **Step 5: Verify build**

Run: `cd /Users/casper/Fritidsprosjekt/ShinyTracker/.claude/worktrees/dex-completion-engine/frontend && npm run build`
Expected: passes (new files are self-contained; nothing imports them yet).

- [ ] **Step 6: Commit**

```bash
cd /Users/casper/Fritidsprosjekt/ShinyTracker/.claude/worktrees/dex-completion-engine
git add frontend/src/types/models.ts frontend/src/features/routes/ frontend/src/index.css
git commit -m "Add shared usePokemonRoute hook + RouteList component"
```

---

## Task 4: Frontend — DexDrawer uses the shared hook + RouteList

**Files:**
- Modify: `frontend/src/components/DexDrawer.tsx`

- [ ] **Step 1: Read the current DexDrawer**

Run: `cat frontend/src/components/DexDrawer.tsx`. It currently fetches `/api/pokemon/{id}/route` inline, holds `data/loading/error` state, filters `direct`/`evolve`, and renders an inline `RouteSection` subcomponent with per-route `▸ Start`. Its `onStartHunt` prop is `(pokemon: Pokemon, route: PokemonRoute) => void` — preserve that exact argument order (Collection and App rely on it). Confirm by reading the prop declaration before editing.

- [ ] **Step 2: Replace inline fetch + RouteSection with the shared hook + RouteList**

Edit `DexDrawer.tsx`:
- Remove the inline `useEffect` fetch and the `data`/`loading`/`error` `useState`; replace with:
  ```tsx
  import { usePokemonRoute } from "../features/routes/usePokemonRoute";
  import RouteList from "../features/routes/RouteList";
  // ...
  const { status, routes, loading, error } = usePokemonRoute(pokemon.id);
  ```
- Remove the local `direct`/`evolve` `filter` lines and the inline `RouteSection` component definition entirely.
- In the body where routes were rendered, render:
  ```tsx
  {!loading && !error && status === "available" && routes.length === 0 && (
  	<div className="t-mono" style={{ marginBottom: 12 }}>
  		Available in your games, but no hunt method recorded yet.
  	</div>
  )}
  {!loading && !error && routes.length > 0 && (
  	<RouteList routes={routes} onRouteClick={(route) => onStartHunt(pokemon, route)} />
  )}
  ```
  (Use the `onStartHunt` argument order the existing prop declares — keep it consistent with how the prop is typed. Do NOT pass a `selectedKey`; the drawer has no persistent selection — clicking a route launches the modal.)
- Keep the existing header/badge, the `locked_everywhere` / `not_in_your_games` status messages (now reading `status` from the hook), the loading/error lines, and the Mark-as-caught / Remove button exactly as they are.

- [ ] **Step 3: Verify build**

Run: `cd /Users/casper/Fritidsprosjekt/ShinyTracker/.claude/worktrees/dex-completion-engine/frontend && npm run build`
Expected: passes. Confirm no dangling references to the removed `RouteSection`/`data` state (`grep -n "RouteSection\|setData" frontend/src/components/DexDrawer.tsx` returns nothing).

- [ ] **Step 4: Commit**

```bash
cd /Users/casper/Fritidsprosjekt/ShinyTracker/.claude/worktrees/dex-completion-engine
git add frontend/src/components/DexDrawer.tsx
git commit -m "DexDrawer: use shared usePokemonRoute hook + RouteList"
```

---

## Task 5: Frontend — NewHuntModal + MethodPreview + App on shared route data

This is the largest change and lands as one build-green commit (the type changes ripple across these three files).

**Files:**
- Modify: `frontend/src/components/NewHuntModal.tsx`
- Modify: `frontend/src/features/new-hunt/MethodPreview.tsx`
- Modify: `frontend/src/App.tsx`
- Possibly remove: `frontend/src/utils/odds.ts`

- [ ] **Step 1: Read the three files**

Run: `cat frontend/src/components/NewHuntModal.tsx frontend/src/features/new-hunt/MethodPreview.tsx frontend/src/App.tsx`. Understand: the modal's step-2 method list (`opt-row` + `getOddsForMethod`), `getBaseOdds`, the `prefill` prop and its two effects, `startHunt`/`startCustomHunt`/`handleStartSelected`, and how `MethodPreview` currently takes `selectedMethod`/`getBaseOdds`/`getOddsForMethod`.

- [ ] **Step 2: Rework NewHuntModal step 2 onto route data**

In `NewHuntModal.tsx`:
- Add imports: `usePokemonRoute` and `RouteList`, `routeKey` from `../features/routes/...`, and `PokemonRoute` from `../types/models`.
- Replace `selectedMethod` state (a `HuntMethod`) with `const [selectedRoute, setSelectedRoute] = useState<PokemonRoute | null>(null);`. Remove `huntMethods` state and the `/api/hunt-methods` fetch effect.
- Add the hook: `const { status, routes, loading: loadingRoutes } = usePokemonRoute(selectedPokemon?.id ?? null);`
- Default selection: when routes load and nothing is selected, default to `routes[0]` — but skip this when a `prefill` is active so it doesn't fight the prefill-selection effect:
  ```tsx
  useEffect(() => {
  	if (!prefill && routes.length > 0 && !selectedRoute) setSelectedRoute(routes[0]);
  }, [routes, prefill]); // selectedRoute intentionally omitted: sets only the initial default
  ```
- **Prefill:** change the `prefill` prop type to `{ pokemon: Pokemon; route: PokemonRoute } | null`. The open+prefill effect sets `selectedPokemon = prefill.pokemon` and `setStep(2)`; add an effect that, once `routes` load, selects the prefill route by key: `setSelectedRoute(routes.find((r) => routeKey(r) === routeKey(prefill.route)) ?? prefill.route)`.
- Replace the `opt-row` method list block with:
  ```tsx
  {!loadingRoutes && routes.length > 0 && (
  	<RouteList
  		routes={routes}
  		selectedKey={selectedRoute && !useCustomMethod ? routeKey(selectedRoute) : undefined}
  		onRouteClick={(r) => { setSelectedRoute(r); setUseCustomMethod(false); }}
  	/>
  )}
  ```
- **Blocked/empty states** (drive from `status` + game count): keep the lightweight `/api/user/{id}/games` fetch ONLY for the count (`userGameCount`); drop the per-game charm usage. Replace the old empty-state conditions with:
  - `userGameCount === 0` → "You haven't added any games yet" + Go-to-Games (unchanged copy).
  - `status === "not_in_your_games"` → "{name} isn't available in your games." + Manage games.
  - `status === "locked_everywhere"` → "{name} is shiny-locked in every game it appears in — obtain it by trading or transferring from Pokémon HOME." (no Start.)
  - `status === "available" && routes.length === 0` → "Available in your games, but no hunt method recorded yet."
- **Delete** `getOddsForMethod` and `getBaseOdds` functions entirely.
- **Start logic:** rewrite `startHunt` to take the selected route and post the ancestor for evolve routes:
  ```tsx
  const startHunt = async (route: PokemonRoute) => {
  	if (!selectedPokemon) return;
  	setStarting(true);
  	try {
  		const res = await fetch("http://localhost:8080/api/hunts", {
  			method: "POST",
  			headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
  			body: JSON.stringify({
  				hunt_method_id: route.method_id,
  				pokemon_id: route.evolve_from ? route.evolve_from.pokemon_id : selectedPokemon.id,
  				game_id: route.game_id,
  				method_name: route.method_name,
  				hunt_parameters: huntParams,
  			}),
  		});
  		if (res.ok) { onClose(); window.location.reload(); }
  		else { showError((await res.text()) || "Failed to start hunt."); }
  	} catch (err: any) { showError(err.message || "Failed to start hunt."); }
  	setStarting(false);
  };
  ```
  Keep `startCustomHunt` as-is. `handleStartSelected`: `if (useCustomMethod) startCustomHunt(); else if (selectedRoute) startHunt(selectedRoute);`. The Start button's disabled condition uses `!selectedRoute` instead of `!selectedMethod`.
- For an evolve route, show a one-line note above the Start button when `selectedRoute?.evolve_from` is set:
  ```tsx
  {selectedRoute?.evolve_from && !useCustomMethod && (
  	<div className="t-label" style={{ marginTop: 10 }}>
  		You'll hunt {selectedRoute.evolve_from.name}, then evolve into {selectedPokemon.name}.
  	</div>
  )}
  ```

- [ ] **Step 3: Rework MethodPreview to consume the selected route**

In `frontend/src/features/new-hunt/MethodPreview.tsx`:
- Change its props: replace `selectedMethod: HuntMethod | null`, `getBaseOdds`, `getOddsForMethod` with `selectedRoute: PokemonRoute | null`.
- Odds display: use `selectedRoute.odds` (render `1 / {selectedRoute.odds.toLocaleString()}`) instead of `getBaseOdds(...)`/`getOddsForMethod(...)`.
- ETA display: use `selectedRoute.eta_hours` (e.g. `~{selectedRoute.eta_hours.toFixed(1)} h`) instead of recomputing from `avg_time_seconds`.
- `HuntParametersEditor`: pass `formulaType={!useCustomMethod ? (selectedRoute?.formula_type ?? null) : null}` (was `selectedMethod?.formula_type`).
- Update the `NewHuntModal` call site to pass `selectedRoute={selectedRoute}` and drop the `selectedMethod`/`getBaseOdds`/`getOddsForMethod` props.

- [ ] **Step 4: Update App prefill shape**

In `frontend/src/App.tsx`:
- Change `huntPrefill` state type to `{ pokemon: Pokemon; route: PokemonRoute } | null` (import `PokemonRoute`).
- The Collection `onStartHunt` handler becomes:
  ```tsx
  onStartHunt={(pokemon, route) => { setHuntPrefill({ pokemon, route }); setNewHuntOpen(true); }}
  ```
- Pass `prefill={huntPrefill}` (unchanged) and keep clearing `setHuntPrefill(null)` on close.

- [ ] **Step 5: Remove dead odds util if unused**

Run: `grep -rn "from \"../utils/odds\"\|from \"./utils/odds\"\|calculateOdds" frontend/src`.
If `calculateOdds` / `utils/odds.ts` has **no remaining references**, delete `frontend/src/utils/odds.ts`. If anything still imports it, leave it.

- [ ] **Step 6: Verify build + lint**

Run: `cd /Users/casper/Fritidsprosjekt/ShinyTracker/.claude/worktrees/dex-completion-engine/frontend && npm run build`
Expected: passes (tsc + vite). Then `npm run lint` — confirm error count is not materially above the ~160 baseline. Grep for leftovers: `grep -n "getOddsForMethod\|getBaseOdds\|huntMethods\|selectedMethod" frontend/src/components/NewHuntModal.tsx` should return nothing.

- [ ] **Step 7: Manual verification (servers running)**

With backend (`go run ./cmd/api/main.go`) + `npm run dev`:
- Search a Pokémon in the New Hunt modal → routes + odds match its dex drawer exactly.
- A Pokémon obtainable only by evolution (e.g. Blastoise) shows "Hunt a pre-evolution: Squirtle" in the modal; selecting it shows the note and Start creates a **Squirtle** hunt.
- A shiny-locked Pokémon shows the locked message in the modal (no Start); a not-in-your-games one shows that message.
- Custom method still starts. The drawer's route click still opens the modal correctly prefilled.

- [ ] **Step 8: Commit**

```bash
cd /Users/casper/Fritidsprosjekt/ShinyTracker/.claude/worktrees/dex-completion-engine
git add frontend/src
git commit -m "Unify NewHuntModal onto shared route data + RouteList; drop client odds"
```

---

## Final verification

- [ ] `cd backend && go build ./... && go test ./internal/calc/ -v` — all green.
- [ ] `cd frontend && npm run build` — passes; lint not materially worse than baseline.
- [ ] Drawer and modal show identical routes/odds for the same Pokémon; evolve-route Start hunts the ancestor; blocked states consistent across both; `getOddsForMethod`/`getBaseOdds` gone.
