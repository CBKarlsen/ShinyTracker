# Live Chain Tracking + Break-Chain for Streak Methods — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give streak-based hunting methods a live "current chain" that advances with each encounter and can be reset to zero (Break chain) without losing the lifetime encounter total.

**Architecture:** Frontend-only. The current chain is stored in the existing `hunt_parameters.chain_length` (JSONB). `frontend/src/utils/odds.ts` derives streak-method odds from `chain_length` with an `?? encounters` fallback for legacy hunts. `Dashboard.tsx` tracks the chain optimistically in parallel with its existing `localCounts`, advances it on `+1`, exposes a Break handler, and includes `hunt_parameters` in its PATCH bodies only when the chain changes (the backend preserves `hunt_parameters` when the field is omitted). `HeroHunt.tsx` and `HuntRow.tsx` render the chain readout and Break button for streak hunts only.

**Tech Stack:** React 19 + TypeScript + Vite; Biome for lint/format. No frontend test framework is configured, so each task is verified with `npm run build` (tsc typecheck), `npm run lint`, and explicit manual checks with concrete expected odds values.

**Reference spec:** `docs/superpowers/specs/2026-06-02-chain-tracking-streak-methods-design.md`

---

## File Structure

- **Modify** `frontend/src/utils/odds.ts` — add `STREAK_FORMULAS` + `isStreakMethod()`; make `chain_fishing_gen6` and `catch_combo_lgpe` read `huntParams.chain_length ?? encounters`.
- **Modify** `frontend/src/components/Dashboard.tsx` — parallel `localChains` optimistic state; advance chain on `+1`; include `hunt_parameters` in the debounced flush and heartbeat PATCHes for streak hunts; `handleBreakChain`; pass live `chain_length` and `onBreakChain` to the cards; reset chain on complete/phase.
- **Modify** `frontend/src/features/dashboard/HeroHunt.tsx` — chain readout + Break button (streak only); accept `onBreakChain` prop.
- **Modify** `frontend/src/features/dashboard/HuntRow.tsx` — chain readout + Break button (streak only); accept `onBreakChain` prop.

All commits happen on a feature branch (created in Task 0), never on `master`.

---

### Task 0: Branch

- [ ] **Step 1: Create and switch to a feature branch**

Run:
```bash
cd /Users/casper/Fritidsprosjekt/ShinyTracker
git checkout -b feat/chain-tracking
```
Expected: `Switched to a new branch 'feat/chain-tracking'`

- [ ] **Step 2: Commit the already-written design spec**

```bash
git add docs/superpowers/specs/2026-06-02-chain-tracking-streak-methods-design.md docs/superpowers/plans/2026-06-02-chain-tracking-streak-methods.md
git commit -m "docs: chain-tracking design spec and implementation plan"
```

---

### Task 1: Streak-method helper + unify the two outlier formulas

**Files:**
- Modify: `frontend/src/utils/odds.ts` (add helper after `routeNeedsParams`, ~line 23; edit `chain_fishing_gen6` block ~lines 162-167; edit `catch_combo_lgpe` block ~lines 85-96)

- [ ] **Step 1: Add `STREAK_FORMULAS` and `isStreakMethod`**

Insert immediately after the `routeNeedsParams` function (after line 23, before the `defaultParamsFor` doc comment):

```ts
/**
 * Formula types whose odds come from a *consecutive chain* that the player
 * builds up and that resets to zero when broken. These are the only methods
 * that track a live `hunt_parameters.chain_length` separate from the lifetime
 * encounter total, and the only ones that show a "Break chain" control.
 */
export const STREAK_FORMULAS = [
	"chain_fishing_gen6",
	"catch_combo_lgpe",
	"sos_chain_gen7",
	"radar_chain_gen4",
	"dexnav_gen6",
] as const;

export function isStreakMethod(formulaType: string | null | undefined): boolean {
	return !!formulaType && (STREAK_FORMULAS as readonly string[]).includes(formulaType);
}
```

- [ ] **Step 2: Make `chain_fishing_gen6` read the chain param with an encounters fallback**

Replace the existing block (currently lines ~162-167):

```ts
	} else if (type === "chain_fishing_gen6") {
		const chain = Math.max(0, Math.min(encounters, 20));
		const extraRolls = chain * 2;
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = Math.floor(baseOdds / rolls);
	}
```

with:

```ts
	} else if (type === "chain_fishing_gen6") {
		// chain_length is the live current chain; fall back to the encounter
		// counter for legacy hunts created before chain tracking existed.
		const paramChain = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const chain = Math.max(0, Math.min(paramChain, 20));
		const extraRolls = chain * 2;
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = Math.floor(baseOdds / rolls);
	}
```

- [ ] **Step 3: Make `catch_combo_lgpe` read the chain param with an encounters fallback**

Replace the existing block (currently lines ~85-96):

```ts
	} else if (type === "catch_combo_lgpe") {
		const combo = Math.max(0, encounters);
		let extraRolls = 0;
		if (combo >= 31) {
			extraRolls = 11;
		} else if (combo >= 21) {
			extraRolls = 7;
		} else if (combo >= 11) {
			extraRolls = 3;
		}
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = Math.floor(baseOdds / rolls);
	}
```

with:

```ts
	} else if (type === "catch_combo_lgpe") {
		// chain_length is the live catch combo; fall back to the encounter
		// counter for legacy hunts created before chain tracking existed.
		const paramCombo = typeof huntParams.chain_length === "number" ? huntParams.chain_length : encounters;
		const combo = Math.max(0, paramCombo);
		let extraRolls = 0;
		if (combo >= 31) {
			extraRolls = 11;
		} else if (combo >= 21) {
			extraRolls = 7;
		} else if (combo >= 11) {
			extraRolls = 3;
		}
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = Math.floor(baseOdds / rolls);
	}
```

> Do **not** add `chain_length` to `defaultParamsFor` for these methods. The existing `default: return {}` branch is correct — seeding a numeric `0` would disable the `?? encounters` fallback and pin legacy hunts at base odds.

- [ ] **Step 4: Typecheck and lint**

Run:
```bash
cd frontend && npm run build && npm run lint
```
Expected: build succeeds (tsc + vite), Biome reports no errors.

- [ ] **Step 5: Manual odds sanity check (reason through values)**

Confirm by inspection of the edited code:
- `chain_fishing_gen6`, base odds 4096, baseRolls 1, no charm, `huntParams = { chain_length: 0 }` → chain 0 → rolls 1 → denominator `4096` (base, chain reset).
- Same with `huntParams = { chain_length: 20 }` → rolls `1 + 40 = 41` → denominator `floor(4096/41) = 99` (max chain ≈ 1/100).
- Same with `huntParams = {}` and `encounters = 20` → fallback path → denominator `99` (legacy hunt unchanged).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/utils/odds.ts
git commit -m "feat(odds): derive chain-fishing and catch-combo odds from chain_length param"
```

---

### Task 2: Live chain state, chain in PATCH bodies, and Break handler in Dashboard

**Files:**
- Modify: `frontend/src/components/Dashboard.tsx`

Context: `Dashboard` already keeps `localCounts` (optimistic encounter counts), `committedRef`, debounce `timers`, a 60 s heartbeat, and a 1.5 s debounced flush. We add a parallel `localChains` map that advances with `+1` and resets on Break, and we attach `hunt_parameters` to the streak-hunt PATCH bodies.

- [ ] **Step 1: Import the streak helper**

In the import for odds utilities at the top of the file, add `isStreakMethod`. There is currently no odds import in `Dashboard.tsx`; add this import alongside the other `../utils/...` imports (near line 9):

```ts
import { isStreakMethod } from "../utils/odds";
```

- [ ] **Step 2: Add `localChains` state and ref**

Immediately after the `localCountsRef` declaration (line 40), add:

```ts
	const [localChains, setLocalChains] = useState<Record<string, number>>({});
	const localChainsRef = useRef<Record<string, number>>({});
```

- [ ] **Step 3: Add a payload helper just below the refs**

Add this helper inside the component, after the `handleSessionExpired` callback (after line 49). It returns the `hunt_parameters` object to send for a streak hunt, or `undefined` for non-streak hunts (so their PATCH bodies stay byte-for-byte as today):

```ts
	// For streak hunts, build the hunt_parameters payload carrying the live
	// chain so PATCHes advance/reset chain_length. Returns undefined for
	// non-streak hunts (their hunt_parameters must be left untouched — the
	// backend preserves existing params when the field is omitted).
	const streakParams = useCallback(
		(hunt: Hunt, chain: number): Record<string, any> | undefined => {
			if (!isStreakMethod(hunt.formula_type)) return undefined;
			const stored = (hunt.hunt_parameters as Record<string, any>) || {};
			return { ...stored, chain_length: Math.max(0, chain) };
		},
		[],
	);
```

- [ ] **Step 4: Initialize `localChains` in `fetchHunts`**

In `fetchHunts`, right after the `initial` encounter-count map is built and `setLocalCounts(initial)` is called (lines 58-62), add chain initialization. Replace:

```ts
				const initial: Record<string, number> = {};
				for (const h of active) initial[h.id] = h.encounter_count;
				setLocalCounts(initial);
				committedRef.current = { ...initial };
				localCountsRef.current = { ...initial };
				onHuntCountChange(active.length);
```

with:

```ts
				const initial: Record<string, number> = {};
				const initialChains: Record<string, number> = {};
				for (const h of active) {
					initial[h.id] = h.encounter_count;
					// Seed the chain from stored chain_length, falling back to the
					// encounter count for legacy hunts (matches the odds fallback).
					const stored = (h.hunt_parameters as Record<string, any>) || {};
					initialChains[h.id] =
						typeof stored.chain_length === "number" ? stored.chain_length : h.encounter_count;
				}
				setLocalCounts(initial);
				setLocalChains(initialChains);
				committedRef.current = { ...initial };
				localCountsRef.current = { ...initial };
				localChainsRef.current = { ...initialChains };
				onHuntCountChange(active.length);
```

- [ ] **Step 5: Keep `localChainsRef` in sync**

Just after the existing effect that syncs `localCountsRef` (line 110), add:

```ts
	useEffect(() => { localChainsRef.current = localChains; }, [localChains]);
```

- [ ] **Step 6: Advance the chain on `+1` and send it in the debounced flush**

Replace the `increment` callback body (lines 112-153). The two changes: bump `localChains` alongside `localCounts`, and attach `hunt_parameters` to the flush body for streak hunts.

```ts
	const increment = useCallback((id: string) => {
		setLocalCounts((prev) => {
			const next = { ...prev, [id]: (prev[id] ?? 0) + 1 };
			localCountsRef.current = next;
			return next;
		});
		setLocalChains((prev) => {
			const next = { ...prev, [id]: (prev[id] ?? 0) + 1 };
			localChainsRef.current = next;
			return next;
		});
		if (timers.current[id]) clearTimeout(timers.current[id]);
		timers.current[id] = setTimeout(async () => {
			const count = localCountsRef.current[id] ?? 0;
			const chain = localChainsRef.current[id] ?? 0;
			const hunt = hunts.find((h) => h.id === id);
			const params = hunt ? streakParams(hunt, chain) : undefined;
			try {
				const res = await authedFetch(
					`${API_BASE}/api/hunts/${id}`,
					token,
					{
						method: "PATCH",
						headers: { "Content-Type": "application/json" },
						body: JSON.stringify({
							encounter_count: count,
							status: "active",
							...(params ? { hunt_parameters: params } : {}),
						}),
					},
					handleSessionExpired,
				);
				if (res.ok) {
					committedRef.current[id] = count;
					setHunts((prev) =>
						prev.map((h) =>
							h.id === id
								? { ...h, encounter_count: count, ...(params ? { hunt_parameters: params } : {}) }
								: h,
						),
					);
				} else {
					setLocalCounts((prev) => {
						const reverted = { ...prev, [id]: committedRef.current[id] ?? 0 };
						localCountsRef.current = reverted;
						return reverted;
					});
					setErrorMsg("Sync failed — clicks weren't saved.");
				}
			} catch (err) {
				if (err instanceof SessionExpiredError) return;
				setLocalCounts((prev) => {
					const reverted = { ...prev, [id]: committedRef.current[id] ?? 0 };
					localCountsRef.current = reverted;
					return reverted;
				});
				setErrorMsg("Sync failed — clicks weren't saved.");
			}
		}, 1500);
	}, [token, handleSessionExpired, hunts, streakParams]);
```

- [ ] **Step 7: Include the chain in the 60 s heartbeat for streak hunts**

In the heartbeat effect, replace the PATCH body construction (lines 86-95). Replace:

```ts
					const hunt = hunts.find((h) => h.id === huntId);
					if (!hunt) return Promise.resolve();
					return authedFetch(
						`${API_BASE}/api/hunts/${huntId}`,
						token,
						{
							method: "PATCH",
							headers: { "Content-Type": "application/json" },
							body: JSON.stringify({ encounter_count: count, status: hunt.status }),
						},
						handleSessionExpired,
					).then((res) => {
```

with:

```ts
					const hunt = hunts.find((h) => h.id === huntId);
					if (!hunt) return Promise.resolve();
					const params = streakParams(hunt, localChainsRef.current[huntId] ?? count);
					return authedFetch(
						`${API_BASE}/api/hunts/${huntId}`,
						token,
						{
							method: "PATCH",
							headers: { "Content-Type": "application/json" },
							body: JSON.stringify({
								encounter_count: count,
								status: hunt.status,
								...(params ? { hunt_parameters: params } : {}),
							}),
						},
						handleSessionExpired,
					).then((res) => {
```

Then add `streakParams` to that effect's dependency array (currently `[localCounts, hunts, token, handleSessionExpired]` on line 107):

```ts
	}, [localCounts, hunts, token, handleSessionExpired, streakParams]);
```

- [ ] **Step 8: Add `handleBreakChain`**

Add this handler next to `handleComplete` (after line 195). It cancels any pending debounce flush (so a stale timer can't re-advance the chain), resets the optimistic chain to 0, and PATCHes full state immediately:

```ts
	const handleBreakChain = async (id: string) => {
		const hunt = hunts.find((h) => h.id === id);
		if (!hunt || !isStreakMethod(hunt.formula_type)) return;
		if (timers.current[id]) { clearTimeout(timers.current[id]); delete timers.current[id]; }
		const count = localCountsRef.current[id] ?? hunt.encounter_count;
		const params = streakParams(hunt, 0)!; // streak-guarded above, never undefined
		setLocalChains((prev) => {
			const next = { ...prev, [id]: 0 };
			localChainsRef.current = next;
			return next;
		});
		try {
			const res = await authedFetch(
				`${API_BASE}/api/hunts/${id}`,
				token,
				{
					method: "PATCH",
					headers: { "Content-Type": "application/json" },
					body: JSON.stringify({ encounter_count: count, status: "active", hunt_parameters: params }),
				},
				handleSessionExpired,
			);
			if (res.ok) {
				setHunts((prev) => prev.map((h) => (h.id === id ? { ...h, hunt_parameters: params } : h)));
			} else {
				setErrorMsg("Break failed — chain wasn't reset.");
			}
		} catch (err) {
			if (err instanceof SessionExpiredError) return;
			setErrorMsg("Break failed — chain wasn't reset.");
		}
	};
```

- [ ] **Step 9: Reset the chain on phase log**

In `handlePhaseSuccess` (lines 202-211), after the `localCountsRef.current[updated.id] = 0;` line, also reset the chain so a new phase starts at chain 0:

```ts
		setLocalChains((prev) => ({ ...prev, [updated.id]: 0 }));
		localChainsRef.current[updated.id] = 0;
```

- [ ] **Step 10: Pass live chain + Break handler to the cards**

Update the merged-hunt objects so the components see the optimistic chain (mirroring how `encounter_count` is overridden), and pass `onBreakChain`.

Replace the `primaryWithCount` definition (line 252):

```ts
	const primaryWithCount = { ...primary, encounter_count: localCounts[primary.id] ?? primary.encounter_count };
```

with:

```ts
	const primaryChain = localChains[primary.id] ?? primary.encounter_count;
	const primaryWithCount = {
		...primary,
		encounter_count: localCounts[primary.id] ?? primary.encounter_count,
		hunt_parameters: isStreakMethod(primary.formula_type)
			? { ...((primary.hunt_parameters as Record<string, any>) || {}), chain_length: primaryChain }
			: primary.hunt_parameters,
	};
```

Update the `<HeroHunt ... />` props (lines 290-297) to add `onBreakChain`:

```tsx
			<HeroHunt
				key={primary.id}
				hunt={primaryWithCount}
				onIncrement={handleIncrement}
				onComplete={handleComplete}
				onPhase={setPhaseHunt}
				onBreakChain={handleBreakChain}
				onUpdate={(updated) => setHunts((prev) => prev.map((h) => (h.id === updated.id ? { ...h, ...updated } : h)))}
			/>
```

Update the `others.map(...)` `<HuntRow ... />` (lines 326-333) to override `hunt_parameters` and pass `onBreakChain`:

```tsx
							{others.map((h) => (
								<HuntRow
									key={h.id}
									hunt={{
										...h,
										encounter_count: localCounts[h.id] ?? h.encounter_count,
										hunt_parameters: isStreakMethod(h.formula_type)
											? { ...((h.hunt_parameters as Record<string, any>) || {}), chain_length: localChains[h.id] ?? h.encounter_count }
											: h.hunt_parameters,
									}}
									onIncrement={handleIncrement}
									onComplete={handleComplete}
									onPhase={setPhaseHunt}
									onBreakChain={handleBreakChain}
									onPin={handlePin}
								/>
							))}
```

- [ ] **Step 11: Typecheck and lint**

Run:
```bash
cd frontend && npm run build && npm run lint
```
Expected: build succeeds, Biome clean. (This will fail to compile until Task 3 adds the `onBreakChain` prop to `HeroHunt` and `HuntRow` — that's expected; proceed to Task 3, then re-run.)

- [ ] **Step 12: Commit (after Task 3 compiles)**

Defer the commit for Dashboard to the end of Task 3, so the tree compiles. (Tasks 2 and 3 are interdependent on the new prop.)

---

### Task 3: Chain readout + Break button in the cards

**Files:**
- Modify: `frontend/src/features/dashboard/HeroHunt.tsx`
- Modify: `frontend/src/features/dashboard/HuntRow.tsx`

- [ ] **Step 1: Add the `onBreakChain` prop and import to `HeroHunt.tsx`**

In the import from `../../utils/odds` (line where `calculateOdds, defaultParamsFor` are imported), add `isStreakMethod`:

```ts
import { calculateOdds, defaultParamsFor, isStreakMethod } from "../../utils/odds";
```

In the props destructure (lines 38-47) add `onBreakChain`, and in the props type (lines 42-47) add its signature:

```ts
		onPhase,
		onUpdate,
		onBreakChain,
	}: {
		hunt: Hunt;
		onIncrement: (id: string, e: React.MouseEvent) => void;
		onComplete: (id: string) => void;
		onPhase: (hunt: Hunt) => void;
		onUpdate?: (hunt: Hunt) => void;
		onBreakChain?: (id: string) => void;
	}) {
```

- [ ] **Step 2: Derive the current chain in `HeroHunt`**

After `resolvedHuntParams` is computed (after line 104), add:

```ts
	const streak = isStreakMethod(hunt.formula_type);
	const currentChain = streak
		? (typeof resolvedHuntParams.chain_length === "number"
			? resolvedHuntParams.chain_length
			: hunt.encounter_count)
		: null;
```

- [ ] **Step 3: Render the chain readout + Break button**

Near the encounter-count display (`<span className="num">{fmtNum(hunt.encounter_count)}</span>` at line 339), add a chain readout adjacent to it, and a Break button. Insert directly after that `num` span:

```tsx
					{streak && (
						<span
							style={{
								fontFamily: "var(--font-mono)",
								fontSize: 12,
								color: "var(--ink-3)",
								marginLeft: 10,
								letterSpacing: "0.04em",
							}}
						>
							chain {fmtNum(currentChain ?? 0)}
						</span>
					)}
```

And add the Break button next to the existing controls. After the `+1` button in `HeroHunt` (the button that calls `onIncrement(hunt.id, e)` at line 218), add:

```tsx
					{streak && onBreakChain && (
						<button
							className="btn ghost"
							style={{ padding: "6px 10px" }}
							onClick={(e) => {
								e.stopPropagation();
								onBreakChain(hunt.id);
							}}
							title="Reset the current chain to 0 (keeps your encounter total)"
						>
							Break chain
						</button>
					)}
```

> Note: place this inside the same control container as the `+1` button so layout/styles match. If the `+1` button is not wrapped in a flex row, wrap both in a `<div style={{ display: "flex", gap: 8 }}>`; otherwise add the button as a sibling.

- [ ] **Step 4: Add the `onBreakChain` prop and import to `HuntRow.tsx`**

In the import from `../../utils/odds` (line 5), add `isStreakMethod`:

```ts
import { calculateOdds, defaultParamsFor, isStreakMethod } from "../../utils/odds";
```

In the props destructure + type (lines 54-66), add `onBreakChain`:

```ts
	export function HuntRow({
		hunt,
		onIncrement,
		onComplete,
		onPhase,
		onPin,
		onBreakChain,
	}: {
		hunt: Hunt;
		onIncrement: (id: string, e: React.MouseEvent) => void;
		onComplete: (id: string) => void;
		onPhase: (hunt: Hunt) => void;
		onPin: (id: string) => void;
		onBreakChain?: (id: string) => void;
	}) {
```

- [ ] **Step 5: Derive the chain and render it in the compact row**

After `resolvedHuntParams` (after line 71), add:

```ts
	const streak = isStreakMethod(hunt.formula_type);
	const currentChain = streak
		? (typeof resolvedHuntParams.chain_length === "number"
			? resolvedHuntParams.chain_length
			: hunt.encounter_count)
		: null;
```

In the `col-num` encounters cell (lines 141-144), add a chain sub-line for streak hunts. Replace:

```tsx
			<div className="col-num">
				{fmtNum(hunt.encounter_count)}
				<small>encounters</small>
			</div>
```

with:

```tsx
			<div className="col-num">
				{fmtNum(hunt.encounter_count)}
				<small>{streak ? `chain ${fmtNum(currentChain ?? 0)}` : "encounters"}</small>
			</div>
```

- [ ] **Step 6: Add the Break button to the row controls**

In the button group (lines 190-234), add a Break button before the `+1` button. Insert directly after the opening `<div style={{ display: "flex", gap: 6, justifyContent: "flex-end" }}>` (line 190) — actually after the pin button (line 201) and before the `+1` button (line 202):

```tsx
					{streak && onBreakChain && (
						<button
							className="btn ghost"
							style={{ padding: "6px 8px", fontSize: 11 }}
							onClick={(e) => {
								e.stopPropagation();
								onBreakChain(hunt.id);
							}}
							title="Reset the current chain to 0 (keeps your encounter total)"
						>
							Break
						</button>
					)}
```

- [ ] **Step 7: Typecheck and lint the full tree**

Run:
```bash
cd frontend && npm run build && npm run lint
```
Expected: build succeeds (Task 2 + Task 3 now compile together), Biome clean.

- [ ] **Step 8: Commit Tasks 2 + 3 together**

```bash
git add frontend/src/components/Dashboard.tsx frontend/src/features/dashboard/HeroHunt.tsx frontend/src/features/dashboard/HuntRow.tsx
git commit -m "feat(dashboard): live chain tracking and Break-chain control for streak hunts"
```

---

### Task 4: Manual end-to-end verification

**Files:** none (runtime check).

- [ ] **Step 1: Start backend and frontend**

Run (two terminals):
```bash
cd backend && go run ./cmd/api/main.go
cd frontend && npm run dev
```
Open http://localhost:5173 and sign in.

- [ ] **Step 2: Verify a chain-fishing hunt shows the chain and Break control**

Open the Dratini (Pokémon Y, chain fishing) hunt in the hero card.
Expected: a `chain N` readout appears next to the encounter total, and a **Break chain** button is visible. A non-streak hunt (e.g. a static-method hunt) shows neither.

- [ ] **Step 3: Verify `+1` advances both total and chain**

Click `+1` a few times.
Expected: both the encounter total and `chain` increment together; the displayed odds (`1/N`) improve as the chain climbs (up to the chain-20 cap of ≈1/100).

- [ ] **Step 4: Verify Break resets the chain but keeps the total**

Click **Break chain**.
Expected: `chain` drops to `0`, the encounter total is unchanged, and the displayed odds return to base (≈1/4096 for chain fishing with no charm). Reload the page and confirm the reset persisted (chain still 0, total intact).

- [ ] **Step 5: Verify the legacy fallback**

Confirm that before clicking anything, a hunt that had no stored `chain_length` still showed correct (pre-feature) odds — i.e. the `?? encounters` fallback held until the first `+1`/Break wrote a `chain_length`.

---

## Self-Review

**Spec coverage:**
- Concept & data model (chain in `hunt_parameters.chain_length`, no schema change) → Task 2 Steps 2-10.
- Odds calc unifies the two outliers with `?? encounters` fallback → Task 1 Steps 2-3.
- `isStreakMethod` single source of truth → Task 1 Step 1; consumed in Tasks 2-3.
- `+1` advances both; Break resets chain only; full-state PATCH → Task 2 Steps 6, 8.
- Backend preserves `hunt_parameters` when omitted (non-streak untouched) → `streakParams` returns `undefined` for non-streak (Task 2 Step 3), guarded in every PATCH site.
- UI readout + Break button in HeroHunt and HuntRow (streak only) → Task 3.
- Cumulative-odds approximation accepted → no task needed; existing loops in HeroHunt/HuntRow now read the single `chain_length` (documented behavior, no code change required beyond what odds.ts already does).
- Dratini fixed via Break button → Task 4 Step 4.

**Placeholder scan:** No TBD/TODO; every code step shows full code. The only prose-only step is Task 3 Step 3's layout note, which gives an explicit conditional instruction (wrap-if-not-flex) rather than a vague directive.

**Type consistency:** `isStreakMethod` / `STREAK_FORMULAS` defined in Task 1, imported identically in Tasks 2-3. `streakParams(hunt, chain)` signature defined once (Task 2 Step 3) and called consistently. `onBreakChain?: (id: string) => void` matches between `Dashboard` call sites and both card prop types. `chain_length` is the single field name used everywhere.

**Known interdependency:** Task 2 will not compile until Task 3 adds `onBreakChain` to the card components; the plan defers the Dashboard commit to the end of Task 3 (Task 2 Step 12 → Task 3 Step 8) and notes the expected transient build failure at Task 2 Step 11.
