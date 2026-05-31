# Outbreak + Sandwich Odds Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the dashboard's live SV Mass Outbreak odds reflect a Sparkling Power sandwich, so they match the route drawer's 1/512 best-case (TS engine + editor were missing the term).

**Architecture:** Frontend-only. Add the `sparkling_power` term to the `outbreak_defeats_sv` branch of `utils/odds.ts` (mirroring Go `EffectiveOdds`), add a Sparkling Power selector to the outbreak case in `HuntParametersEditor`, and thread `hunt.hunt_parameters` into the one `calculateOdds` call site that lacks it (`HuntRow`).

**Tech Stack:** React 19 + TypeScript + Vite; Biome (`npm run lint`); `npm run build` (`tsc -b && vite build`). No JS test framework — validate via build/lint/behavior.

**Spec:** `docs/superpowers/specs/2026-05-31-outbreak-sandwich-odds-consistency-design.md`

**Working directory:** main repo `/Users/casper/Fritidsprosjekt/ShinyTracker`, branch `odds-engine-consistency`. Run `npm` from `frontend/`.

---

## Task 1: Add the Sparkling Power term to the TS odds engine

**Files:**
- Modify: `frontend/src/utils/odds.ts` (the `outbreak_defeats_sv` branch of `calculateOdds`)

- [ ] **Step 1: Replace the outbreak branch**

In `frontend/src/utils/odds.ts`, the current branch reads:
```ts
	} else if (type === "outbreak_defeats_sv") {
		const paramDefeats = typeof huntParams.defeated_count === "number" ? huntParams.defeated_count : encounters;
		const defeats = Math.max(0, paramDefeats);
		let extraRolls = 0;
		if (defeats >= 60) {
			extraRolls = 2;
		} else if (defeats >= 30) {
			extraRolls = 1;
		}
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = Math.floor(baseOdds / rolls);
	}
```
Replace it with (adds the Sparkling Power rolls, mirroring Go `EffectiveOdds`):
```ts
	} else if (type === "outbreak_defeats_sv") {
		const paramDefeats = typeof huntParams.defeated_count === "number" ? huntParams.defeated_count : encounters;
		const defeats = Math.max(0, paramDefeats);
		let extraRolls = 0;
		if (defeats >= 60) {
			extraRolls = 2;
		} else if (defeats >= 30) {
			extraRolls = 1;
		}
		// Sandwich Sparkling Power stacks additively with outbreak defeats (matches
		// Go EffectiveOdds): outbreak 60 + Sparkling Lv3 + charm = 8 rolls -> 1/512.
		const power = typeof huntParams.sparkling_power === "number" ? huntParams.sparkling_power : 0;
		if (power >= 1 && power <= 3) {
			extraRolls += power;
		}
		rolls = baseRolls + extraRolls + (hasShinyCharm ? charmRolls : 0);
		denominator = Math.floor(baseOdds / rolls);
	}
```

- [ ] **Step 2: Verify the build compiles**

Run: `cd frontend && npm run build`
Expected: succeeds (no TS errors).

- [ ] **Step 3: Commit**

```bash
git add frontend/src/utils/odds.ts
git commit -m "Add Sparkling Power term to TS outbreak_defeats_sv (match Go engine)"
```

---

## Task 2: Add the Sparkling Power selector to the outbreak editor

**Files:**
- Modify: `frontend/src/components/ui/HuntParametersEditor.tsx` (the `outbreak_defeats_sv` case)

- [ ] **Step 1: Add the selector after the defeated-count radios**

In `frontend/src/components/ui/HuntParametersEditor.tsx`, the `outbreak_defeats_sv` block
ends with the "60+" radio, its closing `</div>`, then `</>`. Insert a Sparkling Power
`<select>` immediately before that closing `</>` (mirrors the existing
`sandwich_power_sv` control). The end of the block should read:
```tsx
							/>{" "}
							60+
						</label>
					</div>
					<div className="t-label" style={{ marginBottom: 6, marginTop: 10 }}>
						Sparkling Power (Sandwich)
					</div>
					<select
						className="input"
						style={{ padding: "4px 8px", width: "100%" }}
						value={huntParams.sparkling_power || 0}
						onChange={(e) =>
							setHuntParams({
								...huntParams,
								sparkling_power: parseInt(e.target.value) || 0,
							})
						}
					>
						<option value={0}>0</option>
						<option value={1}>1</option>
						<option value={2}>2</option>
						<option value={3}>3</option>
					</select>
				</>
			)}
```
(Only the new `<div className="t-label">…</div>` + `<select>…</select>` are added; the
defeated-count radios above are unchanged.)

- [ ] **Step 2: Build + lint**

Run: `cd frontend && npm run build && npm run lint`
Expected: both clean.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/components/ui/HuntParametersEditor.tsx
git commit -m "Add Sparkling Power field to outbreak params editor"
```

---

## Task 3: Thread huntParams into HuntRow's odds calls

**Files:**
- Modify: `frontend/src/features/dashboard/HuntRow.tsx` (two `calculateOdds` calls)

`OddsCurve` and `HeroHunt` already pass `hunt.hunt_parameters`; `HuntRow` does not, so its
"expected/over-odds" and cumulative figures ignore the sandwich. Add the 7th argument.

- [ ] **Step 1: Add the param arg to the first call (~line 66)**

Change:
```ts
	const { denominator: expected } = calculateOdds(
		hunt.formula_type,
		hunt.encounter_count,
		hunt.has_shiny_charm || false,
		hunt.base_odds || 4096,
		hunt.base_rolls || 1,
		hunt.charm_rolls || 0
	);
```
to:
```ts
	const { denominator: expected } = calculateOdds(
		hunt.formula_type,
		hunt.encounter_count,
		hunt.has_shiny_charm || false,
		hunt.base_odds || 4096,
		hunt.base_rolls || 1,
		hunt.charm_rolls || 0,
		(hunt.hunt_parameters as Record<string, any>) || {}
	);
```

- [ ] **Step 2: Add the param arg to the second call (~line 80, in the cumulative loop)**

Change:
```ts
			const { denominator } = calculateOdds(
				hunt.formula_type,
				e,
				hunt.has_shiny_charm || false,
				hunt.base_odds,
				hunt.base_rolls || 1,
				hunt.charm_rolls || 0
			);
```
to:
```ts
			const { denominator } = calculateOdds(
				hunt.formula_type,
				e,
				hunt.has_shiny_charm || false,
				hunt.base_odds,
				hunt.base_rolls || 1,
				hunt.charm_rolls || 0,
				(hunt.hunt_parameters as Record<string, any>) || {}
			);
```

- [ ] **Step 3: Build + lint**

Run: `cd frontend && npm run build && npm run lint`
Expected: both clean.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/features/dashboard/HuntRow.tsx
git commit -m "Thread hunt_parameters into HuntRow odds calculations"
```

---

## Task 4: Behavior verification

**Files:** none (manual verification)

- [ ] **Step 1: Run the app and check outbreak parity**

Start the frontend (`cd frontend && npm run dev`) against the running backend. On an SV
**Mass Outbreak** hunt (or create one):
- Set Defeats **60+** and Sparkling Power **3**, with the Shiny Charm owned for that
  game → the hunt's live odds (HeroHunt) **and** the odds curve read **1/512**.
- Drop Sparkling Power to **0** → odds fall back to ⌊4096/5⌋ = **1/819** (60 defeats +
  charm, no sandwich). Raising it 0→3 visibly improves the displayed odds.
- The SV outbreak **best-route** odds in the dex drawer (1/512) now equal the
  fully-stacked active hunt's live odds — the inconsistency is closed.

- [ ] **Step 2: Confirm no other method changed**

Pick a `static` and a `sandwich_power_sv` hunt; confirm their odds are unchanged from
before (the new term lives only in the `outbreak_defeats_sv` branch).

---

## Task 5: Update TASKS.md

**Files:**
- Modify: `TASKS.md`

- [ ] **Step 1: Resolve the TS-drift follow-up; note GetOddsHandler unused**

In `TASKS.md`, find the follow-up lines:
```markdown
- **TS/Go odds drift on outbreak+sandwich** — Go `EffectiveOdds` adds a `sparkling_power` term to `outbreak_defeats_sv`; `frontend/src/utils/odds.ts` does not yet. Sync the TS engine + surface the sparkling field in the outbreak editor so dashboard live-odds matches the Go route ranking for stacked outbreak hunts.
- **`GetOddsHandler` not method-aware** — `GET /odds` (`backend/internal/api/handlers.go`) still computes `base_odds/rolls` (only special-casing dynamax), so for modern methods it now disagrees with the route drawer's `EffectiveOdds`-based number. Route it through `calc.EffectiveOdds` for server-side consistency.
```
Replace them with:
```markdown
- ✅ **TS/Go odds drift on outbreak+sandwich — FIXED.** `utils/odds.ts` `outbreak_defeats_sv` now adds the `sparkling_power` term and the outbreak editor has a Sparkling Power field; dashboard live-odds match the route drawer's 1/512. (spec/plan `docs/superpowers/*/2026-05-31-outbreak-sandwich-odds-consistency*`).
- **`GetOddsHandler` (`GET /odds`) is UNUSED by the frontend** — every odds display computes client-side via `utils/odds.ts`. Left as-is (dead but harmless); only special-cases dynamax. Route through `calc.EffectiveOdds` or delete if it's ever revived.
```

- [ ] **Step 2: Commit**

```bash
git add TASKS.md
git commit -m "Mark TS/Go outbreak odds drift fixed; note GetOddsHandler unused"
```

---

## Final verification

- [ ] `cd frontend && npm run build && npm run lint` → both clean.
- [ ] SV outbreak hunt with Defeats 60 + Sparkling 3 + charm shows **1/512**, matching the drawer (Task 4).
- [ ] static / sandwich_power_sv hunts unchanged (Task 4 Step 2).
- [ ] TASKS.md updated (Task 5).
