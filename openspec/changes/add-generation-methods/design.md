## Context

ShinyTracker relies on `formula_type` to calculate expected encounter odds dynamically. We are introducing complex new methods like DexNav (Gen 6) and SOS Chaining (Gen 7) which use parameters (Search Level, Chain Length). These must be integrated smoothly into the new `HuntParametersEditor` and the `calculateOdds` math engine.

## Goals / Non-Goals

**Goals:**
- Implement scalable logic for Gen 6 DexNav, Gen 7 SOS Chaining, and Gen 9 Sandwich Power in `utils/odds.ts`.
- Expose the necessary parameter fields (`search_level`, `chain_length`, `sparkling_power`) in `HuntParametersEditor.tsx`.
- Provide correct DB seed entries for these methods (including flat methods like Masuda Method).

**Non-Goals:**
- Backend architectural changes.
- Modifying how `hunt_parameters` are stored (we will continue using the existing JSONB field).

## Decisions

**1. DexNav Math in odds.ts**
- *Decision*: We will implement DexNav odds logic based on standard formulas (Search Level bonuses applied on top of the base shiny rate, plus flat chain bonuses at chain 50 and 100).
- *Rationale*: DexNav math is notoriously complex, but we will simplify the random number generation aspect into expected averages. The `hunt_parameters` will include `search_level` and `chain_length`.

**2. SOS Chaining**
- *Decision*: `hunt_parameters` will include `chain_length`. Base rolls increase at 11, 21, and 31.
- *Rationale*: SOS chaining resets at 255. We will modulo the `chain_length` by 255 to automatically handle the wrap-around logic.

**3. Sandwich Power**
- *Decision*: `sandwich_power_sv` formula will take `sparkling_power` level (1, 2, or 3) and add 1, 2, or 3 rolls respectively. 
- *Rationale*: It's a flat roll addition on top of base odds.

## Risks / Trade-offs

- **Risk**: Complex math in `calcCumulativeOdds` could slow down the UI rendering since it loops `N` times for dynamic formulas.
  - *Mitigation*: Given JS performance, a loop up to a few thousand encounters takes milliseconds. If we notice lag, we can memoize the results or optimize the cumulative loop.
