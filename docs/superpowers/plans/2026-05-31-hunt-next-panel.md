# "Hunt Next" Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a server-ranked "Hunt next" panel atop the Collection page that recommends the top 12 huntable-missing Pokémon, each with one-click Start.

**Architecture:** A new `GET /api/dex/suggestions` endpoint runs one bulk query over the user's huntable-missing pool, groups candidates per Pokémon in Go, computes each one's best direct route via the existing `calc` engine, and ranks by best-odds → fewest huntable games → dex order. A pure `calc.RankSuggestions` sorter is unit-tested. The frontend `<HuntNextPanel>` renders the cards and reuses the existing Start flow and route drawer.

**Tech Stack:** Go (chi, pgx, `internal/calc`, `go test`), React + TypeScript (Vite), custom dark-theme CSS.

**Spec:** `docs/superpowers/specs/2026-05-31-hunt-next-panel-design.md`

---

## File Structure

- `backend/internal/calc/suggestions.go` (new) — `SuggestionRank` struct + `RankSuggestions` pure sorter.
- `backend/internal/calc/suggestions_test.go` (new) — unit test for the sort order incl. tie cases.
- `backend/internal/api/dex.go` (modify) — `DexSuggestionsHandler` + `HuntSuggestion`/`HuntSuggestionsResponse` DTOs + bulk query + grouping.
- `backend/internal/api/router.go` (modify, ~line 71) — register `GET /api/dex/suggestions`.
- `frontend/src/types/models.ts` (modify) — `HuntSuggestion`, `HuntSuggestionsResponse`.
- `frontend/src/components/HuntNextPanel.tsx` (new) — panel + card components, self-fetching.
- `frontend/src/components/Collection.tsx` (modify) — render the panel above the grid.
- `frontend/src/index.css` (modify) — panel styles.

No DDL. No odds-formula changes.

---

### Task 1: `calc.RankSuggestions` pure sorter (test-first)

**Files:**
- Create: `backend/internal/calc/suggestions.go`
- Test: `backend/internal/calc/suggestions_test.go`

- [ ] **Step 1: Write the failing test**

Create `backend/internal/calc/suggestions_test.go`:

```go
package calc

import (
	"reflect"
	"testing"
)

func TestRankSuggestions(t *testing.T) {
	// Mixed odds, game counts, and dex ids. Expected order:
	//   odds 512 first, within that fewest games first, within that lowest dex id.
	items := []SuggestionRank{
		{PokemonID: 10, HuntableGameCount: 3, Best: Route{Odds: 512}},
		{PokemonID: 5, HuntableGameCount: 1, Best: Route{Odds: 4096}},
		{PokemonID: 7, HuntableGameCount: 2, Best: Route{Odds: 512}},
		{PokemonID: 3, HuntableGameCount: 1, Best: Route{Odds: 512}},
		{PokemonID: 2, HuntableGameCount: 1, Best: Route{Odds: 512}},
	}
	RankSuggestions(items)
	got := []int{}
	for _, it := range items {
		got = append(got, it.PokemonID)
	}
	want := []int{2, 3, 7, 10, 5}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("order = %v, want %v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd backend && go test ./internal/calc/ -run TestRankSuggestions`
Expected: FAIL to compile — `undefined: SuggestionRank` / `RankSuggestions`.

- [ ] **Step 3: Write the implementation**

Create `backend/internal/calc/suggestions.go`:

```go
package calc

import "sort"

// SuggestionRank is a per-Pokemon best route plus availability breadth, used to
// rank "hunt next" suggestions. Kept free of presentation fields so the sort is
// pure, total, and unit-testable.
type SuggestionRank struct {
	PokemonID         int
	HuntableGameCount int
	Best              Route
}

// RankSuggestions sorts items in place: best odds first (lowest Best.Odds), then
// most constrained (fewest huntable games), then National Dex order (lowest
// PokemonID). PokemonID is unique, so the order is fully deterministic.
func RankSuggestions(items []SuggestionRank) {
	sort.SliceStable(items, func(i, j int) bool {
		a, b := items[i], items[j]
		if a.Best.Odds != b.Best.Odds {
			return a.Best.Odds < b.Best.Odds
		}
		if a.HuntableGameCount != b.HuntableGameCount {
			return a.HuntableGameCount < b.HuntableGameCount
		}
		return a.PokemonID < b.PokemonID
	})
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd backend && go test ./internal/calc/`
Expected: PASS (`ok .../internal/calc`).

- [ ] **Step 5: Commit**

```bash
git add backend/internal/calc/suggestions.go backend/internal/calc/suggestions_test.go
git commit -m "Add calc.RankSuggestions: best-odds -> fewest-games -> dex sorter

Pure, unit-tested ranking core for the Hunt-next panel.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `GET /api/dex/suggestions` endpoint

**Files:**
- Modify: `backend/internal/api/dex.go` (append handler + DTOs)
- Modify: `backend/internal/api/router.go` (~line 71, after the `dex/status` registration)

- [ ] **Step 1: Add the DTOs and handler to `dex.go`**

Append to `backend/internal/api/dex.go` (the file already imports `context`, `encoding/json`, `net/http`, `strconv`, `calc`, `database`):

```go
// HuntSuggestion is one ranked "hunt next" target. The full Route is embedded so
// the frontend can Start without another fetch; odds/eta/method/game are read
// from Route (no projection duplicates -> no drift).
type HuntSuggestion struct {
	PokemonID         int        `json:"pokemon_id"`
	Name              string     `json:"name"`
	SpriteURL         string     `json:"sprite_url"`
	HuntableGameCount int        `json:"huntable_game_count"`
	Route             calc.Route `json:"route"`
}

type HuntSuggestionsResponse struct {
	TotalHuntable int              `json:"total_huntable"`
	Suggestions   []HuntSuggestion `json:"suggestions"`
}

// DexSuggestionsHandler ranks the user's huntable-missing Pokemon by best odds,
// then fewest huntable games, then dex order, and returns the top `limit`
// (default 12, max 50). Direct routes only (evolve-only species are omitted; they
// remain reachable via the grid/drawer).
func DexSuggestionsHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	if userID == "" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	limit := 12
	if q := r.URL.Query().Get("limit"); q != "" {
		if n, err := strconv.Atoi(q); err == nil && n > 0 {
			limit = n
			if limit > 50 {
				limit = 50
			}
		}
	}

	ctx := context.Background()

	// One bulk query: all direct method candidates for the huntable-missing pool.
	// Excludes locked (pokemon, game) pairs and any Pokemon already owned/being hunted.
	rows, err := database.DB.Query(ctx, `
		SELECT ma.pokemon_id, p.name, p.sprite_url,
		       hm.id, g.id, g.title, hm.method_name, g.base_odds,
		       hm.base_rolls, hm.charm_rolls, hm.avg_time_seconds, ug.has_shiny_charm, hm.formula_type
		FROM method_availability ma
		JOIN hunt_methods hm ON ma.method_id = hm.id
		JOIN games g         ON g.id = ma.game_id
		JOIN user_games ug   ON ug.game_id = g.id AND ug.user_id = $1
		JOIN pokemon p       ON p.id = ma.pokemon_id
		LEFT JOIN shiny_locks sl ON sl.pokemon_id = ma.pokemon_id AND sl.game_id = ma.game_id
		WHERE sl.pokemon_id IS NULL
		  AND ma.pokemon_id NOT IN (
		      SELECT pokemon_id FROM user_hunts
		      WHERE user_id = $1 AND status IN ('active', 'completed')
		  )
	`, userID)
	if err != nil {
		http.Error(w, "Failed to load suggestions", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type group struct {
		name   string
		sprite string
		games  map[int]bool
		cands  []calc.MethodCandidate
	}
	groups := map[int]*group{}
	for rows.Next() {
		var pid int
		var name, sprite string
		var c calc.MethodCandidate
		if err := rows.Scan(&pid, &name, &sprite,
			&c.MethodID, &c.GameID, &c.GameTitle, &c.MethodName, &c.BaseOdds,
			&c.BaseRolls, &c.CharmRolls, &c.AvgTimeSeconds, &c.HasShinyCharm, &c.FormulaType); err != nil {
			http.Error(w, "Failed to read suggestions", http.StatusInternalServerError)
			return
		}
		g := groups[pid]
		if g == nil {
			g = &group{name: name, sprite: sprite, games: map[int]bool{}}
			groups[pid] = g
		}
		g.games[c.GameID] = true
		g.cands = append(g.cands, c)
	}
	if err := rows.Err(); err != nil {
		http.Error(w, "Failed to read suggestions", http.StatusInternalServerError)
		return
	}

	ranks := make([]calc.SuggestionRank, 0, len(groups))
	meta := map[int]*group{}
	for pid, g := range groups {
		routes := calc.RankDirectRoutes(g.cands)
		if len(routes) == 0 {
			continue
		}
		ranks = append(ranks, calc.SuggestionRank{
			PokemonID:         pid,
			HuntableGameCount: len(g.games),
			Best:              routes[0],
		})
		meta[pid] = g
	}

	calc.RankSuggestions(ranks)
	total := len(ranks)
	if limit < len(ranks) {
		ranks = ranks[:limit]
	}

	suggestions := make([]HuntSuggestion, 0, len(ranks))
	for _, rk := range ranks {
		g := meta[rk.PokemonID]
		suggestions = append(suggestions, HuntSuggestion{
			PokemonID:         rk.PokemonID,
			Name:              g.name,
			SpriteURL:         g.sprite,
			HuntableGameCount: rk.HuntableGameCount,
			Route:             rk.Best,
		})
	}

	resp := HuntSuggestionsResponse{TotalHuntable: total, Suggestions: suggestions}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}
```

- [ ] **Step 2: Register the route**

In `backend/internal/api/router.go`, find the line registering `dex/status` (~line 70):

```go
		r.Get("/dex/status", DexStatusHandler)
```

Add immediately below it:

```go
		r.Get("/dex/suggestions", DexSuggestionsHandler)
```

- [ ] **Step 3: Verify it compiles, vets, and tests pass**

Run: `cd backend && go build ./... && go vet ./... && go test ./internal/calc/`
Expected: build + vet clean (no output), tests PASS.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/api/dex.go backend/internal/api/router.go
git commit -m "Add GET /api/dex/suggestions: ranked hunt-next targets

Bulk-queries the huntable-missing pool, groups per Pokemon, computes
best direct route via calc, ranks via calc.RankSuggestions, returns
top-N (default 12). Excludes owned/active/locked. No DDL.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Frontend types

**Files:**
- Modify: `frontend/src/types/models.ts`

- [ ] **Step 1: Add the interfaces**

In `frontend/src/types/models.ts`, directly after the existing `PokemonRouteResponse` interface, add:

```ts
export interface HuntSuggestion {
	pokemon_id: number;
	name: string;
	sprite_url: string;
	huntable_game_count: number;
	route: PokemonRoute;
}

export interface HuntSuggestionsResponse {
	total_huntable: number;
	suggestions: HuntSuggestion[];
}
```

- [ ] **Step 2: Verify the build typechecks**

Run: `cd frontend && npm run build`
Expected: build succeeds (no type errors).

- [ ] **Step 3: Commit**

```bash
git add frontend/src/types/models.ts
git commit -m "Add HuntSuggestion types mirroring the suggestions DTO

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `HuntNextPanel` component

**Files:**
- Create: `frontend/src/components/HuntNextPanel.tsx`
- Modify: `frontend/src/index.css` (append panel styles)

- [ ] **Step 1: Create the component**

Create `frontend/src/components/HuntNextPanel.tsx`:

```tsx
import type React from "react";
import { useEffect, useState } from "react";
import { useAuth } from "../context/AuthContext";
import { API_BASE } from "../config";
import type { HuntSuggestion, HuntSuggestionsResponse, Pokemon, PokemonRoute } from "../types/models";

const HuntNextPanel: React.FC<{
	onStart: (pokemon: Pokemon, route: PokemonRoute) => void;
	onOpen: (pokemonId: number) => void;
}> = ({ onStart, onOpen }) => {
	const { token } = useAuth();
	const [data, setData] = useState<HuntSuggestionsResponse | null>(null);
	const [loading, setLoading] = useState(true);
	const [error, setError] = useState(false);

	useEffect(() => {
		let cancelled = false;
		setLoading(true);
		setError(false);
		fetch(`${API_BASE}/api/dex/suggestions`, {
			headers: { Authorization: `Bearer ${token}` },
		})
			.then((res) => {
				if (!res.ok) throw new Error("failed");
				return res.json();
			})
			.then((d: HuntSuggestionsResponse) => {
				if (!cancelled) setData(d);
			})
			.catch(() => {
				if (!cancelled) setError(true);
			})
			.finally(() => {
				if (!cancelled) setLoading(false);
			});
		return () => {
			cancelled = true;
		};
	}, [token]);

	if (error) return null;

	if (loading) {
		return (
			<section className="hunt-next">
				<h2 className="hunt-next-title">⭐ Hunt next</h2>
				<div className="hunt-next-grid">
					{Array.from({ length: 12 }).map((_, i) => (
						<div key={i} className="hunt-next-card hunt-next-card--skeleton" />
					))}
				</div>
			</section>
		);
	}

	if (!data || data.total_huntable === 0) {
		return (
			<section className="hunt-next">
				<h2 className="hunt-next-title">⭐ Hunt next</h2>
				<p className="hunt-next-empty">
					No huntable targets left — your dex is complete or the rest are blocked 🎉
				</p>
			</section>
		);
	}

	return (
		<section className="hunt-next">
			<h2 className="hunt-next-title">
				⭐ Hunt next <span className="hunt-next-count">· {data.total_huntable} huntable targets left</span>
			</h2>
			<div className="hunt-next-grid">
				{data.suggestions.map((s) => (
					<HuntNextCard key={s.pokemon_id} s={s} onStart={onStart} onOpen={onOpen} />
				))}
			</div>
		</section>
	);
};

const HuntNextCard: React.FC<{
	s: HuntSuggestion;
	onStart: (pokemon: Pokemon, route: PokemonRoute) => void;
	onOpen: (pokemonId: number) => void;
}> = ({ s, onStart, onOpen }) => {
	const r = s.route;
	const constrained = s.huntable_game_count === 1;
	return (
		<div
			className="hunt-next-card"
			onClick={() => onOpen(s.pokemon_id)}
			onKeyDown={(e) => {
				if (e.key === "Enter") onOpen(s.pokemon_id);
			}}
			role="button"
			tabIndex={0}
		>
			<div className="hunt-next-card-top">
				<img className="hunt-next-sprite" src={s.sprite_url} alt={s.name} loading="lazy" />
				<span className={`hunt-next-badge${constrained ? " hunt-next-badge--hot" : ""}`}>
					{constrained ? "only 1 game" : `${s.huntable_game_count} games`}
				</span>
			</div>
			<div className="hunt-next-name">{s.name}</div>
			<div className="hunt-next-meta">
				{r.game_title} · {r.method_name}
			</div>
			<div className="hunt-next-odds">
				1 / {r.odds.toLocaleString()} <span className="hunt-next-eta">· ~{r.eta_hours.toFixed(1)} h</span>
			</div>
			<button
				type="button"
				className="hunt-next-start"
				onClick={(e) => {
					e.stopPropagation();
					onStart({ id: s.pokemon_id, name: s.name, sprite_url: s.sprite_url }, r);
				}}
			>
				Start
			</button>
		</div>
	);
};

export default HuntNextPanel;
```

- [ ] **Step 2: Add styles**

Append to `frontend/src/index.css`. Use the existing dark-theme CSS variables defined at the top of that file (e.g. surface/border/text/accent tokens) in place of the literal fallbacks below where an equivalent token exists; keep the literals as written if no token matches.

```css
/* Hunt-next panel */
.hunt-next {
	margin-bottom: 24px;
}
.hunt-next-title {
	font-size: 16px;
	font-weight: 700;
	margin: 0 0 12px;
}
.hunt-next-count {
	font-weight: 400;
	opacity: 0.55;
}
.hunt-next-grid {
	display: grid;
	grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
	gap: 10px;
}
.hunt-next-card {
	background: var(--surface-2, #1a2336);
	border: 1px solid var(--border, #2a3550);
	border-radius: 10px;
	padding: 10px;
	cursor: pointer;
	transition: border-color 0.15s ease, transform 0.15s ease;
}
.hunt-next-card:hover {
	border-color: var(--accent, #3b82f6);
	transform: translateY(-2px);
}
.hunt-next-card:focus-visible {
	outline: 2px solid var(--accent, #3b82f6);
	outline-offset: 2px;
}
.hunt-next-card--skeleton {
	height: 150px;
	cursor: default;
	opacity: 0.4;
	animation: hunt-next-pulse 1.2s ease-in-out infinite;
}
@keyframes hunt-next-pulse {
	50% {
		opacity: 0.7;
	}
}
.hunt-next-card-top {
	display: flex;
	justify-content: space-between;
	align-items: flex-start;
}
.hunt-next-sprite {
	width: 48px;
	height: 48px;
	image-rendering: pixelated;
}
.hunt-next-badge {
	font-size: 10px;
	border-radius: 4px;
	padding: 1px 6px;
	background: var(--surface-3, #1e3a5f);
	color: var(--text-dim, #93c5fd);
	white-space: nowrap;
}
.hunt-next-badge--hot {
	background: #7c2d12;
	color: #fdba74;
}
.hunt-next-name {
	font-weight: 700;
	margin-top: 6px;
}
.hunt-next-meta {
	font-size: 11px;
	opacity: 0.6;
	margin-top: 2px;
}
.hunt-next-odds {
	margin-top: 4px;
	font-weight: 600;
	color: var(--success, #34d399);
}
.hunt-next-eta {
	font-weight: 400;
	color: var(--text, #e2e8f0);
	opacity: 0.6;
}
.hunt-next-start {
	display: block;
	width: 100%;
	margin-top: 8px;
	padding: 6px;
	border: none;
	border-radius: 6px;
	background: var(--success, #10b981);
	color: #04231a;
	font-weight: 700;
	cursor: pointer;
}
.hunt-next-start:hover {
	filter: brightness(1.08);
}
.hunt-next-empty {
	opacity: 0.7;
}
```

- [ ] **Step 3: Verify the build passes**

Run: `cd frontend && npm run build`
Expected: build succeeds (component compiles; unused-import/type errors would fail it).

- [ ] **Step 4: Commit**

```bash
git add frontend/src/components/HuntNextPanel.tsx frontend/src/index.css
git commit -m "Add HuntNextPanel component + styles

Self-fetching ranked suggestion cards with one-click Start and
card-body drawer open. Loading skeleton + empty state.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Render the panel in `Collection.tsx`

**Files:**
- Modify: `frontend/src/components/Collection.tsx`

- [ ] **Step 1: Import the panel**

In `frontend/src/components/Collection.tsx`, add to the imports (next to `import DexDrawer from "./DexDrawer";` at line 7):

```tsx
import HuntNextPanel from "./HuntNextPanel";
```

- [ ] **Step 2: Render the panel above the grid**

In the component's returned JSX, render `<HuntNextPanel>` as the first child inside the top-level wrapper element — above the filter controls and the generation grid. It reuses the existing `onStartHunt` prop and the existing `setDrawerId` drawer state:

```tsx
<HuntNextPanel
	onStart={(poke, route) => onStartHunt?.(poke, route)}
	onOpen={(id) => setDrawerId(id)}
/>
```

(Place it just inside the root returned element so it sits at the top of the page. The existing `DexDrawer` block at the bottom already handles `drawerId`, so opening from a card requires no further wiring.)

- [ ] **Step 3: Verify the build passes**

Run: `cd frontend && npm run build`
Expected: build succeeds.

- [ ] **Step 4: Manual smoke check (no automated harness exists)**

With the backend running (`go run ./cmd/api/main.go`) and `npm run dev`, open the Collection tab and confirm:
- The "Hunt next" panel renders up to 12 cards, best odds first, "only 1 game" badge where applicable.
- Clicking **Start** opens the New Hunt modal prefilled with that Pokémon + route.
- Clicking a card body opens the route drawer.
- A user with everything owned/blocked sees the empty-state message.

Note any discrepancy; otherwise proceed.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/components/Collection.tsx
git commit -m "Render HuntNextPanel atop the Collection page

Wires Start to the existing onStartHunt flow and card-open to the
existing route drawer. No new start/drawer logic.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Post-implementation note (not a code task)

No re-seed and no DDL needed — this is read-only over existing tables. The endpoint is live as soon as the backend is redeployed and the frontend rebuilt. Per-session live re-ranking after Start/Mark-caught is intentionally out of scope (v1 reflects changes on next page load).
