## 1. Database Seeding

- [x] 1.1 Update `backend/FullDexMethods.csv` (or equivalent seeder script) to include "SOS Chaining" for Gen 7 with `sos_chain_gen7` formula type.
- [x] 1.2 Add "DexNav" for Gen 6 (ORAS) with `dexnav_gen6` formula type.
- [x] 1.3 Add "Sandwich Power" for Gen 9 with `sandwich_power_sv` formula type.
- [x] 1.4 Add static methods like "Masuda Method" and "Dynamax Adventures".
- [x] 1.5 Run the backend seeder to apply these new methods to the database.

## 2. Frontend Odds Engine (`utils/odds.ts`)

- [x] 2.1 Implement `sos_chain_gen7` logic in `calculateOdds` (adding 4, 8, or 12 rolls based on `hunt_parameters.chain_length`).
- [x] 2.2 Implement `dexnav_gen6` logic in `calculateOdds` (factoring in `search_level` and applying flat bonuses at chain 50/100).
- [x] 2.3 Implement `sandwich_power_sv` logic (adding 1, 2, or 3 rolls based on `sparkling_power`).

## 3. Frontend UI (`HuntParametersEditor.tsx`)

- [x] 3.1 Update `HuntParametersEditor.tsx` to render a number input for `chain_length` when `formulaType === 'sos_chain_gen7'`.
- [x] 3.2 Add number inputs for `search_level` and `chain_length` when `formulaType === 'dexnav_gen6'`.
- [x] 3.3 Add a dropdown for `sparkling_power` (0, 1, 2, 3) when `formulaType === 'sandwich_power_sv'`.

## 4. Verification

- [x] 4.1 Start the frontend and backend servers.
- [x] 4.2 Test creating a new SOS Chain hunt and verifying that modifying `chain_length` dynamically updates the odds.
- [x] 4.3 Verify that the Odds Calculator in the sidebar correctly processes the new methods when provided with parameters.
