# ⌘K Pokémon Command Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the decorative `readOnly` topbar search with a working ⌘K command-palette overlay that searches Pokémon and lets the user start a hunt (Enter) or view the Pokémon in the Living Dex (secondary).

**Architecture:** A new `CommandSearch` overlay component backed by a shared, debounced `usePokemonSearch` hook (calls the existing `GET /api/pokemon?q=`). `App.tsx` owns open/close state + the global ⌘K shortcut and wires the two result actions into machinery it already has (`huntPrefill` + New Hunt modal; `setRoute("dex")` + a new `focusPokemonId` on `Collection`). `NewHuntModal`'s `prefill` is widened to accept a Pokémon without a pre-chosen route.

**Tech Stack:** React 19 + TypeScript + Vite. No test framework is configured (per CLAUDE.md), so verification per task is `npm run build` (tsc typecheck) + `npm run lint` (Biome) clean, plus manual smoke at the end. Run all `npm` commands from `frontend/`.

**Spec:** `docs/superpowers/specs/2026-05-31-topbar-search-design.md`

**Branch:** `shiny-charm-icon-and-pro-removal`

---

## File Structure

- **Create** `frontend/src/hooks/usePokemonSearch.ts` — debounced authed Pokémon search hook. One responsibility: turn a query string into `{ results, loading }`.
- **Create** `frontend/src/components/search/CommandSearch.tsx` — the overlay UI + keyboard handling. Presentational + interaction only; receives action callbacks as props.
- **Modify** `frontend/src/App.tsx` — overlay open state, global ⌘K listener, render `CommandSearch`, route-less `huntPrefill`, `focusPokemonId` state for Dex.
- **Modify** `frontend/src/components/Topbar.tsx` — search box becomes a trigger button (`onOpenSearch` prop).
- **Modify** `frontend/src/components/NewHuntModal.tsx` — `prefill` route becomes optional; default-route effect runs for route-less prefills.
- **Modify** `frontend/src/components/Collection.tsx` — `focusPokemonId` + `onFocusHandled` props to open a specific Pokémon's drawer from outside.
- **Modify** `frontend/src/index.css` — command-palette panel styling.

Task order is dependency-first: the hook and the two enabling integration changes (New Hunt prefill, Collection focus) land before the component that uses them, then the App/Topbar wiring connects everything. Each task leaves the app building.

---

### Task 1: `usePokemonSearch` debounced hook

**Files:**
- Create: `frontend/src/hooks/usePokemonSearch.ts`

- [ ] **Step 1: Create the hook**

```ts
import { useEffect, useRef, useState } from "react";
import { API_BASE } from "../config";
import { useAuth } from "../context/AuthContext";
import type { Pokemon } from "../types/models";
import { authedFetch } from "../utils/authedFetch";

/**
 * Debounced Pokémon search against GET /api/pokemon?q=.
 * Returns an empty list for blank queries and discards stale responses so
 * fast typing never shows results for an older query.
 */
export function usePokemonSearch(query: string): {
	results: Pokemon[];
	loading: boolean;
} {
	const { token, logout } = useAuth();
	const [results, setResults] = useState<Pokemon[]>([]);
	const [loading, setLoading] = useState(false);
	const seqRef = useRef(0);

	useEffect(() => {
		const q = query.trim();
		if (!q) {
			setResults([]);
			setLoading(false);
			return;
		}
		setLoading(true);
		const seq = ++seqRef.current;
		const timer = setTimeout(async () => {
			try {
				const res = await authedFetch(
					`${API_BASE}/api/pokemon?q=${encodeURIComponent(q)}`,
					token,
					{},
					logout,
				);
				const data = res.ok ? ((await res.json()) as Pokemon[]) || [] : [];
				if (seq === seqRef.current) setResults(data);
			} catch {
				if (seq === seqRef.current) setResults([]);
			} finally {
				if (seq === seqRef.current) setLoading(false);
			}
		}, 200);
		return () => clearTimeout(timer);
	}, [query, token, logout]);

	return { results, loading };
}
```

- [ ] **Step 2: Typecheck**

Run: `npm run build`
Expected: PASS (no TS errors). The hook is unused so far; that is fine.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/hooks/usePokemonSearch.ts
git commit -m "feat(search): add debounced usePokemonSearch hook"
```

---

### Task 2: Allow a route-less Pokémon prefill in New Hunt

This enables "Enter = start a hunt" to open the modal with just a Pokémon and let it pick a default route, without breaking the existing Collection → start-hunt path (which passes a full route).

**Files:**
- Modify: `frontend/src/components/NewHuntModal.tsx` (prefill type ~line 19; prefill effect ~line 86-92; default-route effect ~line 94-101; route-by-key effect ~line 103-110)
- Modify: `frontend/src/App.tsx` (`huntPrefill` state type ~line 31)

- [ ] **Step 1: Widen the `prefill` prop type in NewHuntModal**

In `frontend/src/components/NewHuntModal.tsx`, change the prop type (originally `prefill?: { pokemon: Pokemon; route: PokemonRoute } | null;`):

```ts
	prefill?: { pokemon: Pokemon; route?: PokemonRoute } | null;
```

- [ ] **Step 2: Make the default-route effect run for route-less prefills**

The existing default-route effect is gated on `!prefill` so it does not fight a full prefill. Change the guard so it also runs when a prefill has no route. Replace the effect body's condition (originally `if (!prefill && !useCustomMethod && routes.length > 0 && !selectedRoute)`):

```ts
	useEffect(() => {
		const prefillHasRoute = !!prefill?.route;
		if (!prefillHasRoute && !useCustomMethod && routes.length > 0 && !selectedRoute) {
			setSelectedRoute(routes[0]);
		}
	}, [routes, prefill, useCustomMethod, selectedRoute]); // eslint-disable-line react-hooks/exhaustive-deps
```

- [ ] **Step 3: Guard the route-by-key effect against a missing route**

The effect that matches the prefill route by key (originally `if (prefill && routes.length > 0) { const r = routes.find(... routeKey(prefill.route) ...) ?? prefill.route; ... }`) must not run when there is no route. Change its guard:

```ts
	useEffect(() => {
		if (prefill?.route && routes.length > 0) {
			const r =
				routes.find((r) => routeKey(r) === routeKey(prefill.route!)) ??
				prefill.route!;
			setSelectedRoute(r);
		}
	}, [prefill, routes]); // eslint-disable-line react-hooks/exhaustive-deps
```

(The prefill effect at ~line 86 that sets `selectedPokemon` and jumps to step 2 needs no change — it only depends on `prefill.pokemon`. Verify it does not dereference `prefill.route`.)

- [ ] **Step 4: Widen the `huntPrefill` state type in App**

In `frontend/src/App.tsx`, change the state declaration (originally `useState<{ pokemon: Pokemon; route: PokemonRoute } | null>(null)`):

```tsx
	const [huntPrefill, setHuntPrefill] = useState<{
		pokemon: Pokemon;
		route?: PokemonRoute;
	} | null>(null);
```

- [ ] **Step 5: Typecheck**

Run: `npm run build`
Expected: PASS.

- [ ] **Step 6: Manual regression check (existing path still works)**

Confirm the Collection → "Start hunt" path is unaffected by reading the call site in `Collection.tsx` (~line 268): it still passes `{ pokemon, route }`, which satisfies the widened type. No behavioral change expected there.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/components/NewHuntModal.tsx frontend/src/App.tsx
git commit -m "feat(hunt): accept a route-less Pokémon prefill in New Hunt modal"
```

---

### Task 3: Open a specific Pokémon's Dex drawer from outside

**Files:**
- Modify: `frontend/src/components/Collection.tsx` (component signature ~line 23; add an effect near the `drawerId` state ~line 31)

- [ ] **Step 1: Add `focusPokemonId` + `onFocusHandled` props and a focus effect**

In `frontend/src/components/Collection.tsx`, change the component signature (originally `const Collection: React.FC<{ onStartHunt?: (pokemon: Pokemon, route: PokemonRoute) => void }> = ({ onStartHunt }) => {`):

```tsx
const Collection: React.FC<{
	onStartHunt?: (pokemon: Pokemon, route: PokemonRoute) => void;
	focusPokemonId?: number | null;
	onFocusHandled?: () => void;
}> = ({ onStartHunt, focusPokemonId, onFocusHandled }) => {
```

Then, immediately after the `const [drawerId, setDrawerId] = useState<number | null>(null);` line, add:

```tsx
	// When asked to focus a specific Pokémon (e.g. from command search),
	// open its drawer, then tell the parent it was handled so it can reset
	// (lets the same Pokémon be focused again later).
	useEffect(() => {
		if (focusPokemonId != null) {
			setDrawerId(focusPokemonId);
			onFocusHandled?.();
		}
	}, [focusPokemonId, onFocusHandled]);
```

(`useEffect` is already imported at the top of the file — verify the import line `import { useEffect, useState } from "react";` is present; it is at ~line 2.)

- [ ] **Step 2: Typecheck**

Run: `npm run build`
Expected: PASS. Props are optional, so the existing `<Collection onStartHunt=… />` usage in `App.tsx` still compiles.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/components/Collection.tsx
git commit -m "feat(dex): let Collection open a specific Pokémon drawer via focusPokemonId"
```

---

### Task 4: `CommandSearch` overlay component + styles

**Files:**
- Create: `frontend/src/components/search/CommandSearch.tsx`
- Modify: `frontend/src/index.css` (append a new section at end of file)

- [ ] **Step 1: Create the component**

```tsx
import { useEffect, useRef, useState } from "react";
import { usePokemonSearch } from "../../hooks/usePokemonSearch";
import type { Pokemon } from "../../types/models";

interface Props {
	open: boolean;
	onClose: () => void;
	onStartHunt: (pokemon: Pokemon) => void;
	onViewInDex: (pokemon: Pokemon) => void;
}

export default function CommandSearch({
	open,
	onClose,
	onStartHunt,
	onViewInDex,
}: Props) {
	const [query, setQuery] = useState("");
	const [highlight, setHighlight] = useState(0);
	const inputRef = useRef<HTMLInputElement>(null);
	const { results, loading } = usePokemonSearch(query);

	// Reset state and focus the input each time the palette opens.
	useEffect(() => {
		if (open) {
			setQuery("");
			setHighlight(0);
			// focus after paint so the element exists
			requestAnimationFrame(() => inputRef.current?.focus());
		}
	}, [open]);

	// Keep the highlighted index in range as results change.
	useEffect(() => {
		setHighlight((h) => (results.length === 0 ? 0 : Math.min(h, results.length - 1)));
	}, [results]);

	// Lock body scroll while open.
	useEffect(() => {
		if (!open) return;
		const prev = document.body.style.overflow;
		document.body.style.overflow = "hidden";
		return () => {
			document.body.style.overflow = prev;
		};
	}, [open]);

	if (!open) return null;

	const handleKeyDown = (e: React.KeyboardEvent) => {
		if (e.key === "Escape") {
			e.preventDefault();
			onClose();
		} else if (e.key === "ArrowDown") {
			e.preventDefault();
			if (results.length) setHighlight((h) => (h + 1) % results.length);
		} else if (e.key === "ArrowUp") {
			e.preventDefault();
			if (results.length) setHighlight((h) => (h - 1 + results.length) % results.length);
		} else if (e.key === "Enter") {
			e.preventDefault();
			const p = results[highlight];
			if (p) onStartHunt(p);
		}
	};

	return (
		<div className="cmd-scrim" onClick={onClose}>
			<div
				className="cmd-panel"
				role="dialog"
				aria-modal="true"
				aria-label="Search Pokémon"
				onClick={(e) => e.stopPropagation()}
				onKeyDown={handleKeyDown}
			>
				<div className="cmd-input-row">
					<svg viewBox="0 0 16 16" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
						<circle cx="7" cy="7" r="4.5" />
						<path d="M11 11l3 3" />
					</svg>
					<input
						ref={inputRef}
						className="cmd-input"
						placeholder="Search any Pokémon…"
						value={query}
						onChange={(e) => setQuery(e.target.value)}
					/>
				</div>

				<div className="cmd-results">
					{loading && query.trim() && <div className="cmd-state">Searching…</div>}
					{!loading && query.trim() && results.length === 0 && (
						<div className="cmd-state">No Pokémon found</div>
					)}
					{!query.trim() && (
						<div className="cmd-state">Type to search any Pokémon</div>
					)}
					{results.map((p, i) => (
						<div
							key={p.id}
							className={`cmd-row${i === highlight ? " active" : ""}`}
							onMouseEnter={() => setHighlight(i)}
							onClick={() => onStartHunt(p)}
						>
							<img src={p.sprite_url} alt="" width={28} height={28} />
							<span className="cmd-nm">{p.name}</span>
							<span className="cmd-id">#{String(p.id).padStart(4, "0")}</span>
							<button
								type="button"
								className="cmd-dex-btn"
								onClick={(e) => {
									e.stopPropagation();
									onViewInDex(p);
								}}
							>
								View in Dex
							</button>
						</div>
					))}
				</div>

				<div className="cmd-foot">
					<span>↑↓ move</span>
					<span>↵ start hunt</span>
					<span>esc close</span>
				</div>
			</div>
		</div>
	);
}
```

- [ ] **Step 2: Append palette styles to `index.css`**

Add at the end of `frontend/src/index.css`:

```css
/* ── Command search (⌘K) ── */
.cmd-scrim {
	position: fixed;
	inset: 0;
	background: rgba(0, 0, 0, 0.6);
	backdrop-filter: blur(8px);
	z-index: 70;
	display: flex;
	justify-content: center;
	align-items: flex-start;
	padding: 12vh 16px 16px;
}
.cmd-panel {
	width: 560px;
	max-width: 100%;
	background: var(--bg-1);
	border: 1px solid var(--line-2);
	border-radius: var(--radius-xl);
	box-shadow: 0 30px 80px -20px rgba(0, 0, 0, 0.7);
	display: flex;
	flex-direction: column;
	overflow: hidden;
}
.cmd-input-row {
	display: flex;
	align-items: center;
	gap: 10px;
	padding: 14px 16px;
	border-bottom: 1px solid var(--line-1);
	color: var(--ink-3);
}
.cmd-input {
	flex: 1;
	min-width: 0;
	background: transparent;
	border: 0;
	outline: 0;
	color: var(--ink-1);
	font-size: 15px;
}
.cmd-results {
	max-height: 52vh;
	overflow-y: auto;
	padding: 6px;
}
.cmd-state {
	padding: 18px 12px;
	color: var(--ink-3);
	font-family: var(--font-mono);
	font-size: 12px;
	text-align: center;
}
.cmd-row {
	display: flex;
	align-items: center;
	gap: 10px;
	padding: 8px 10px;
	border-radius: 8px;
	cursor: pointer;
}
.cmd-row.active {
	background: var(--bg-3);
}
.cmd-row img {
	image-rendering: pixelated;
	flex-shrink: 0;
}
.cmd-nm {
	font-size: 14px;
	text-transform: capitalize;
}
.cmd-id {
	margin-left: auto;
	font-family: var(--font-mono);
	font-size: 11px;
	color: var(--ink-3);
}
.cmd-dex-btn {
	font-family: var(--font-mono);
	font-size: 10px;
	letter-spacing: 0.04em;
	text-transform: uppercase;
	color: var(--blue);
	border: 1px solid var(--blue-line);
	background: var(--blue-soft);
	border-radius: 6px;
	padding: 4px 8px;
	opacity: 0;
	transition: opacity 0.12s ease-out;
}
.cmd-row.active .cmd-dex-btn,
.cmd-dex-btn:focus-visible {
	opacity: 1;
}
.cmd-foot {
	display: flex;
	gap: 16px;
	justify-content: center;
	padding: 10px 16px;
	border-top: 1px solid var(--line-1);
	font-family: var(--font-mono);
	font-size: 10px;
	letter-spacing: 0.06em;
	text-transform: uppercase;
	color: var(--ink-4);
}
@media (max-width: 760px) {
	.cmd-scrim {
		padding: 8vh 10px 10px;
	}
	.cmd-dex-btn {
		opacity: 1; /* no hover on touch — always show the action */
	}
}
```

(Note `z-index: 70` sits above the More-sheet scrim at 60, so the palette is always topmost.)

- [ ] **Step 3: Typecheck**

Run: `npm run build`
Expected: PASS. Component is not yet rendered anywhere; that is fine.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/components/search/CommandSearch.tsx frontend/src/index.css
git commit -m "feat(search): add CommandSearch overlay component and styles"
```

---

### Task 5: Wire the palette into App + Topbar

**Files:**
- Modify: `frontend/src/App.tsx` (imports; new state; ⌘K effect; render `CommandSearch`; pass props to `Topbar` and `Collection`)
- Modify: `frontend/src/components/Topbar.tsx` (props; search box → button)

- [ ] **Step 1: Add state, shortcut, and render in App**

In `frontend/src/App.tsx`:

a) Add imports near the other component imports:

```tsx
import CommandSearch from "./components/search/CommandSearch";
import { useEffect } from "react";
```

(If `useState` is already imported from "react", change that import to `import { useEffect, useState } from "react";` instead of adding a duplicate line.)

b) Add state alongside the existing `useState` hooks:

```tsx
	const [searchOpen, setSearchOpen] = useState(false);
	const [focusPokemonId, setFocusPokemonId] = useState<number | null>(null);
```

c) Add the global ⌘K / Ctrl+K listener (place after the existing hooks, before the `if (loading)` guard):

```tsx
	useEffect(() => {
		const onKey = (e: KeyboardEvent) => {
			if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
				e.preventDefault();
				setSearchOpen((o) => !o);
			}
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, []);
```

d) Pass `onOpenSearch` to `Topbar` (originally `<Topbar route={route} onNew={() => setNewHuntOpen(true)} />`):

```tsx
				<Topbar
					route={route}
					onNew={() => setNewHuntOpen(true)}
					onOpenSearch={() => setSearchOpen(true)}
				/>
```

e) Pass focus props to the Dex `Collection` (originally the `route === "dex"` block):

```tsx
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
```

f) Render `CommandSearch` next to `NewHuntModal` (inside the top-level `<div className="app">`, after `NewHuntModal`):

```tsx
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
```

- [ ] **Step 2: Make the Topbar search box a trigger button**

In `frontend/src/components/Topbar.tsx`:

a) Add `onOpenSearch` to `Props` (originally `interface Props { route: Route; onNew: () => void; onMoreOpen: () => void; }`):

```tsx
interface Props {
	route: Route;
	onNew: () => void;
	onMoreOpen: () => void;
	onOpenSearch: () => void;
}
```

b) Update the function signature: `export default function Topbar({ route, onNew, onMoreOpen, onOpenSearch }: Props) {`

c) Replace the `<div className="searchbox">…</div>` block (the one containing the `readOnly` `<input>` and the `<kbd>⌘K</kbd>`) with a button:

```tsx
				<button type="button" className="searchbox" onClick={onOpenSearch}>
					<svg
						viewBox="0 0 16 16"
						width="14"
						height="14"
						fill="none"
						stroke="currentColor"
						strokeWidth="1.5"
						aria-hidden="true"
					>
						<circle cx="7" cy="7" r="4.5" />
						<path d="M11 11l3 3" />
					</svg>
					<span className="searchbox-placeholder">Search Pokémon…</span>
					<kbd>⌘K</kbd>
				</button>
```

d) Add a small style so the button text/placeholder aligns left like the old input. Append to `frontend/src/index.css`:

```css
.searchbox .searchbox-placeholder {
	flex: 1;
	text-align: left;
	color: var(--ink-3);
}
```

(The existing `.searchbox` already lays out its children in a row with the kbd at the end; the placeholder span takes the space the input used to.)

- [ ] **Step 3: Typecheck + lint**

Run: `npm run build`
Expected: PASS.
Run: `npm run lint`
Expected: No NEW errors beyond the project's pre-existing baseline (SVG-title / scrim-interactivity conventions). If lint reports formatting on the changed files, run `npx biome check --write frontend/src` and re-run.

- [ ] **Step 4: Manual smoke test**

Start the app (`npm run dev`, backend running) and verify:
- Pressing ⌘K (or Ctrl+K) opens the palette; the input is focused.
- Clicking the topbar search box also opens it.
- Typing `gible` lists Gible / Gabite / Garchomp with sprites and dex numbers.
- ↑/↓ moves the highlight; Enter opens the New Hunt modal with that Pokémon pre-selected on the game/method step.
- "View in Dex" on a row switches to Living Dex and opens that Pokémon's drawer.
- Esc and click-away close the palette.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/App.tsx frontend/src/components/Topbar.tsx frontend/src/index.css
git commit -m "feat(search): wire ⌘K command palette into App and Topbar"
```

---

### Task 6: Final verification

- [ ] **Step 1: Full build + lint**

Run: `npm run build` → PASS.
Run: `npm run lint` → no new errors vs. baseline.

- [ ] **Step 2: Confirm no regressions in the two reused paths**

- Collection → "Start hunt" (with a chosen route) still opens New Hunt with that route preselected.
- New Hunt opened from the palette (no route) lands on the game/method step with a sensible default route once routes load.

- [ ] **Step 3 (optional follow-up, not required): note the dedup opportunity**

`PhaseModal` and the New Hunt search step still have their own copies of the `/api/pokemon` fetch. Refactoring them onto `usePokemonSearch` is a clean follow-up but out of scope for this feature; leave a one-line note in the PR description rather than expanding scope here.

---

## Self-Review

**Spec coverage:**
- ⌘K overlay surface → Tasks 4, 5. ✓
- Pokémon search via existing endpoint → Task 1 (hook), used in Task 4. ✓
- Enter = start hunt (route-less prefill) → Tasks 2 + 5. ✓
- Secondary "View in Dex" → Tasks 3 + 5. ✓
- Shared `usePokemonSearch` hook → Task 1. ✓
- Topbar trigger replaces readOnly input → Task 5. ✓
- Keyboard nav / focus / scroll-lock / states → Task 4. ✓
- Mobile full-width panel → Task 4 CSS (`@media`). ✓
- Error handling (empty on failure, stale guard) → Task 1. ✓
- z-index above existing overlays (>60) → Task 4 (`z-index: 70`). ✓

**Placeholder scan:** No TBD/TODO; every code step contains full code. ✓

**Type consistency:** `Pokemon {id:number,name,sprite_url}` used consistently; `prefill?: {pokemon; route?}` matches `huntPrefill` widening and the palette's `setHuntPrefill({ pokemon: p })`; `CommandSearch` prop names (`open/onClose/onStartHunt/onViewInDex`) match App's render; `focusPokemonId`/`onFocusHandled` match between Collection and App. ✓
