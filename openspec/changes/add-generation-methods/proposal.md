## Why

ShinyTracker's main value is displaying live, dynamic odds for hunts. However, only a handful of methods (e.g., Gen 4 PokeRadar, SV Outbreaks, LGPE Catch Combo) are currently supported with dynamic formulas. Hunters using iconic methods from other generations (like Gen 7 SOS Chaining, Gen 6 DexNav, or Gen 9 Sandwich Power) must rely on the "Custom Method" fallback. This removes the ability to see the expected encounters or the beautiful cumulative probability curve, degrading the experience.

## What Changes

- Add Gen 7 SOS Chaining logic (`sos_chain_gen7` formula type) where odds scale based on chain length (11-20, 21-30, 31+).
- Add Gen 6 DexNav logic (`dexnav_gen6` formula type) combining search level and chain bonuses.
- Add Gen 9 Sandwich Power logic (`sandwich_power_sv` formula type) supporting Sparking Power 1, 2, and 3 via `hunt_parameters`.
- Add static methods like Masuda Method and Dynamax Adventures which just require the correct database seeds.
- Seed the database (`FullDexMethods.csv` or equivalent) with these new methods so they appear in the UI.
- Update the `HuntParametersEditor` UI component to include inputs for SOS chain length, DexNav search level, and Sandwich Power.

## Capabilities

### New Capabilities
- `sos-chaining`: Support for tracking and calculating odds for Gen 7 SOS battles based on chain length.
- `dexnav-hunting`: Support for calculating Gen 6 DexNav odds factoring in search level and chain.
- `sandwich-power`: Support for factoring Gen 9 Sandwich Sparkling Power levels into odds.

### Modified Capabilities
- `odds-calculator`: Must correctly apply the new `sos_chain_gen7`, `dexnav_gen6`, and `sandwich_power_sv` formulas using `hunt_parameters`.

## Impact

- Frontend: `utils/odds.ts` will expand significantly to implement the complex DexNav and SOS chaining math. `HuntParametersEditor.tsx` will need new UI states.
- Backend/DB: Needs new seed data (CSV) to introduce the method options to the users and tie them to the correct games and Pokémon.
