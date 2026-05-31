# Outbreak + Sandwich Odds Consistency — Design

**Date:** 2026-05-31
**Branch:** `odds-engine-consistency` (off `master`)
**Backlog item:** Odds-engine follow-up — TS/Go drift on SV outbreak + sandwich
**Status:** approved design, pending implementation plan

## Problem

The Go odds engine (`internal/calc/EffectiveOdds`) models an SV Mass Outbreak with a
**Sparkling Power** sandwich: `outbreak_defeats_sv` rolls = base + outbreak(defeats) +
sparkling(level) + charm. So the route **drawer** ranks an SV outbreak at its best case
**1/512** (via `DefaultParams` = defeats 60 + Sparkling Lv3).

The TypeScript engine (`frontend/src/utils/odds.ts`), which powers the **dashboard
live odds** and the params editor, does **not**: its `outbreak_defeats_sv` branch reads
only `defeated_count`, and the outbreak params editor has **no sparkling-power field**.
So when a user actually runs that hunt, the live odds can't reflect the sandwich and
show ~1/2048 — contradicting the drawer's 1/512 promise.

This closes that visible gap. **Frontend-only; no backend, no schema, no API change.**

## Non-goal (decided)

`GetOddsHandler` (`GET /odds`) is **unused by the frontend** (every odds display
computes client-side via `utils/odds.ts`). It is left as-is and noted as unused — no
work, no removal this pass.

## Changes

### 1. `frontend/src/utils/odds.ts` — add the sparkling term
In the `outbreak_defeats_sv` branch, after computing the defeats-based `extraRolls`, add
the Sparkling Power rolls (mirrors Go `EffectiveOdds`):
- `sparkling_power` 1/2/3 → +1/+2/+3 rolls; 0/absent → +0.
- Final: `rolls = baseRolls + defeatRolls + sparklingRolls + (hasShinyCharm ? charmRolls : 0)`.
- Reads `huntParams.sparkling_power` (tolerating absence). Verified target: defeats 60
  (+2) + Sparkling Lv3 (+3) + charm (+2) + base (1) = 8 rolls → `⌊4096/8⌋ = 512`.

### 2. `frontend/src/components/ui/HuntParametersEditor.tsx` — add the editor field
The `outbreak_defeats_sv` case currently renders only the defeated-count radios. Add a
**Sparkling Power** `<select>` (options 0–3) beneath them, writing
`huntParams.sparkling_power` — reusing the exact control already used by the
`sandwich_power_sv` case. Keep the existing defeated-count control unchanged.

### 3. Thread `huntParams` into active-hunt odds displays
`HeroHunt` already passes `hunt.hunt_parameters` as the 7th arg to `calculateOdds`.
Audit the other active-hunt call sites — `OddsCurve` and `HuntRow` — and pass the same
`hunt.hunt_parameters` where missing, so the live odds/curve reflect the sandwich after
changes 1–2. (Without this, the editor would update odds in `HeroHunt` but not in the
curve.)

## Data flow (unchanged plumbing)

User edits params on the active hunt → `HuntParametersEditor` updates `huntParams` →
existing PATCH persists `hunt_parameters` (works today) → `calculateOdds` recomputes
with the new sparkling term. No new endpoints or state.

## Error handling / edge cases

- `sparkling_power` absent/non-numeric → treated as 0 (no boost), matching the existing
  `typeof … === "number"` guards in `utils/odds.ts`.
- Other formula types unchanged — the new term lives only in the
  `outbreak_defeats_sv` branch.
- Charm still additive as today.

## Validation & testing

No JS test framework configured; validate by build + lint + behavior:
1. `cd frontend && npm run build && npm run lint` — clean.
2. Behavior: on an SV Mass Outbreak hunt, set Defeats 60+ and Sparkling Lv3 with Shiny
   Charm → live odds + curve read **1/512**, matching the route drawer. Outbreak-only
   (Sparkling 0) reads its current value (e.g. 60 defeats + charm → ⌊4096/5⌋ = 819).
   Toggling Sparkling 0→3 visibly improves the odds.
3. Drawer/hunt parity: the SV outbreak best-route odds (1/512) now equal a fully-stacked
   active hunt's live odds.

## Out of scope

- `GetOddsHandler` / `/odds` endpoint (unused; left as-is).
- `OddsCalculator`'s separate inline param inputs (uses live `encounters` as the chain
  proxy; not the dashboard path).
- Any backend or schema change.

## Sources

Go reference: `backend/internal/calc/methods.go` `EffectiveOdds` (`outbreak_defeats_sv`
branch + `sparklingRolls`). The 1/512 stack is the same one shipped in the modern-odds
spec (`docs/superpowers/specs/2026-05-31-modern-method-odds-design.md`).
