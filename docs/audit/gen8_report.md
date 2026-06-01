# Gen 8 Method Verification Report

**Scope:** Generation 8 — Sword/Shield (`game_id=14`), Brilliant Diamond/Shining Pearl (`game_id=15`), Legends: Arceus (`game_id=16`). Read-only; no database writes performed.
**Date:** 2026-05-31
**Verified against:** Bulbapedia (primary), Serebii (secondary).

> ℹ️ The DB state at audit time differs significantly from the prompt's description of "expected" counts (Random 300 + Mass Outbreak 50 + Masuda 1 + KO 1 for game 14, etc.). The numbers below reflect the **actual stable snapshot** read during this session. Injection check: no embedded instructions or feedback were detected in any query result.

---

## Summary

| Metric | Value |
|---|---|
| Total method_availability rows (Gen 8) | **1,640** (game14: 1,407 / game15: 9 / game16: 224) |
| Distinct Pokémon covered | game14: 600 / game15: 9 / game16: 224 |
| Method mislabels confirmed | **3** (KO Method as wild-encounter stand-in in game 14; Run Away on egg-only Pokémon in game 14; Giratina in shiny_locks game 15 while also having Soft Reset) |
| Shiny-lock errors | **2** (Dialga+Palkia wrongly in shiny_locks for game 15) |
| Coverage gaps — game 14 | **3** (Regieleki/Regidrago/Zarude missing hunt entries; missing Mass Outbreak / Brilliant Aura label) |
| Coverage gaps — game 15 | **CRITICAL** (only 9 encounter rows total; entire wild/grass/static Pokédex missing) |
| Coverage gaps — game 16 | **1** (incomplete shiny_locks: Uxie/Mesprit/Azelf/Heatran/Regigigas/Cresselia/Giratina/Darkrai/Shaymin/Manaphy missing from locks table) |

**Bottom line:** Game 14 (SwSh) has a **structural mislabel** — KO Method (id=176) is wired as the primary wild-encounter method for all 562 wild Pokémon, which is wrong (KO Method is a Legends: Arceus mechanic, not SwSh). The intended SwSh wild-encounter method is "Brilliant Aura" (a.k.a. Shiny Mark / outbreak style) or simply Random Encounter. Game 15 (BDSP) has a **critical seeding gap** — only 9 Pokémon have encounter rows at all, representing less than 2% of the expected Sinnoh dex. Game 16 (PLA) methods are structurally correct but the shiny_locks table is missing ~10 PLA-locked legendaries/mythicals.

---

## Schema reading (Phase 1)

Same schema as Gen 4 (confirmed stable). Key tables:

| Concept | Where it lives |
|---|---|
| Methods per game | `method_games(game_id, method_id)` |
| Method assignments | `method_availability(id, pokemon_id, method_id, game_id)` |
| Encounter type | `pokemon_game_encounter(pokemon_id, game_id, kind, terrain)` |
| Shiny locks | `shiny_locks(pokemon_id, game_id)` |

**Gen 8 method IDs (verified):**

| Game | Method | ID |
|---|---|---|
| SwSh (14) | Dynamax Adventures | 171 |
| SwSh (14) | Masuda Method | 172 |
| SwSh (14) | KO Method | 176 |
| SwSh (14) | Soft Reset | 178 |
| SwSh (14) | Run Away | 179 |
| BDSP (15) | Masuda Method | 172 |
| BDSP (15) | Soft Reset | 178 |
| BDSP (15) | Run Away | 179 |
| PLA (16) | Mass Outbreak | 177 |

Note: `method_games` for game 14 does **not** include a Random Encounter or Mass Outbreak entry — KO Method is registered as the single wild-encounter method. No Poké Radar or DexNav appears in game 15's `method_games`.

---

## Rules verified (once each, reused across rows)

| # | Rule | Verdict | Source |
|---|---|---|---|
| R1 | **KO Method** (id=176) is a mechanic from **Legends: Arceus**, not Sword/Shield. In SwSh the equivalent boosted-shiny method is "Brilliant Aura" (KO counting does increase shiny marks but the game-mechanic label used in the DB is wrong) | **VIOLATION** — KO Method is assigned to all 562 wild SwSh Pokémon | [Bulbapedia: Shiny Pokémon SwSh](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon#Sword_and_Shield) |
| R2 | **Run Away** applies only to wild encounters (not egg/breeding); its `requires_kind` is `wild` | **VIOLATION** — Run Away is assigned to 245 egg-kind Pokémon in game 14 (via multi-encounter join; likely a join artifact rather than a true bad row — see findings) | [hunt_methods table] |
| R3 | **Dynamax Adventures** (Max Lair) — all 38 assigned Pokémon are `is_legendary=true`, `kind=raid` | Confirmed correct ✓ | [Bulbapedia: Dynamax Adventures](https://bulbapedia.bulbagarden.net/wiki/Dynamax_Adventure) |
| R4 | **SwSh shiny locks**: Zacian(888), Zamazenta(889), Eternatus(890), Kubfu(891), Urshifu(892), Calyrex(898), Glastrier(896), Spectrier(897) are locked; Regieleki/Regidrago/Galarian birds/returning Regis are **not** locked | Shiny_locks for game 14 correctly contains 888/889/890/891/898. Urshifu(892), Glastrier(896), Spectrier(897) are absent from shiny_locks but also absent from method_availability — net effect correct (can't be hunted either way). Missing shiny_locks entries are a consistency gap only. | [Bulbapedia: List of unobtainable Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/List_of_unobtainable_Shiny_Pok%C3%A9mon) |
| R5 | **BDSP shiny locks**: Dialga(483) and Palkia(484) are **NOT** shiny-locked in BDSP — they are Soft-Resettable at Spear Pillar. Giratina(487) is also **not** locked. Shaymin/Darkrai/Arceus are event-only and shiny-unobtainable. | **VIOLATION** — shiny_locks(15) contains Dialga, Palkia, and Giratina. Dialga and Palkia have no method row (wrongly treated as locked). Giratina has a Soft Reset row (correctly huntable) but is also in shiny_locks — direct contradiction. | [Bulbapedia: BDSP Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon#Brilliant_Diamond_and_Shining_Pearl) |
| R6 | **PLA shiny locks**: ALL legendaries and mythicals in PLA are shiny-locked (Dialga, Palkia, Lake trio, Heatran, Regigigas, Cresselia, Giratina, Arceus, Darkrai, Shaymin, Enamorus, Manaphy, Phione) | **GAP** — only Dialga(483), Palkia(484), Arceus(493), Enamorus(905) are in shiny_locks(16). Uxie/Mesprit/Azelf/Heatran/Regigigas/Cresselia/Giratina/Darkrai/Shaymin/Manaphy are missing. None of these have encounter rows or method rows in game 16, so no hunt is possible regardless — but the locks table is incomplete. | [Bulbapedia: Legends Arceus Shiny Pokémon](https://bulbapedia.bulbagarden.net/wiki/Shiny_Pok%C3%A9mon#Legends:_Arceus) |
| R7 | **Masuda Method** valid only for can_breed=true Pokémon | No violations found in games 14 or 15 — all Masuda assignments have can_breed=true ✓ | |
| R8 | **DexNav** (method_id=169) is ORAS-exclusive; does **not** exist in BDSP | No DexNav rows found in game 15 — the issue flagged in the prompt does **not** exist in the current snapshot ✓ | [Bulbapedia: DexNav](https://bulbapedia.bulbagarden.net/wiki/DexNav) |
| R9 | **Poké Radar** belongs in BDSP (post-game, grass-only); should have rows for game 15 | Poké Radar is absent from `method_games` for game 15 — a coverage/seeding gap (part of the broader BDSP under-seeding) | [Bulbapedia: Poké Radar BDSP](https://bulbapedia.bulbagarden.net/wiki/Poké_Radar) |

---

## Verification results by game

### Game 14 — Sword/Shield

**Method mix (stable snapshot):**

| Method | method_id | Rows | Distinct Pokémon | Encounter kind |
|---|---|---|---|---|
| KO Method | 176 | 562 | 562 | wild |
| Run Away | 179 | 562 | 562 | wild |
| Masuda Method | 172 | 245 | 245 | egg |
| Dynamax Adventures | 171 | 38 | 38 | raid |
| Soft Reset | 178 | 0 | 0 | (none) |

**Finding F1 — KO Method is the wrong label for SwSh wild encounters.**
KO Method (`method_id=176`) is mapped exclusively to game 14 via `method_games`. It covers all 562 wild Pokémon. However, KO Method is a Legends: Arceus mechanic (kill a species 500+ times to raise your Research Level and boost shiny odds in PLA). The SwSh equivalent that increases shiny odds is the **Shiny Mark** system (boosted encounter rate from KO count, but displayed to the player as "Shiny Mark" / "Brilliant aura" wild encounters). The correct label for bulk-wild SwSh hunting is either **"Random Encounter"** (base odds, existing method_id=161/164/165) or a SwSh-specific "Brilliant Aura" entry. Using "KO Method" will mislead users into thinking they need PLA mechanics. **Severity: High — 562 rows mislabeled.**

**Finding F2 — Run Away on egg-kind Pokémon (join artifact).**
The `method_availability` table has 562 Run Away rows for game 14. However, 245 of those same Pokémon also have egg-kind encounter rows; when joined on (pokemon_id, game_id) the Run Away row appears once per encounter kind, producing the 562 wild + 245 egg count in joined queries. The method_availability rows themselves are 562 (confirmed: 562 distinct `pokemon_id`). Run Away is a valid SwSh mechanic (fleeing from battles in the overworld), but it is assigned to wild Pokémon only — the apparent "egg" count is a join artifact, not a row-level error. However, Run Away being wired to game 15 (BDSP) as well is questionable — BDSP does not have an overworld Run Away shiny method. **Severity: Medium (game 14 rows are probably correct; game 15 Run Away is a coverage question).**

**Finding F3 — Dynamax Adventures pool is correct but incomplete.**
All 38 Dynamax Adventures Pokémon are `is_legendary=true` with `kind=raid`. The SwSh-locked legendaries (Zacian, Zamazenta, Eternatus, Kubfu, Calyrex) are correctly absent. However, **Regieleki(894) and Regidrago(895)** have no method row at all in game 14, despite being obtainable via static encounter in Crown Tundra (not shiny-locked). These should have a Soft Reset row. **Severity: Medium — 2 coverage gaps.**

**Finding F4 — Soft Reset has 0 rows in game 14.**
Despite being registered in `method_games`, Soft Reset (178) has no `method_availability` rows for game 14. Regieleki/Regidrago (Crown Tundra static encounters) should have Soft Reset rows. **Severity: Medium.**

**Finding F5 — Mass Outbreak (SwSh) not wired.**
SwSh has Mass Outbreaks (overworld brilliant encounters / "outbreak" events) as a distinct shiny method separate from standard KO counting. Neither method_id 167 (Mass Outbreak, SV-mapped) nor a SwSh-specific version is registered for game 14. This is a coverage gap. **Severity: Low-Medium — design decision needed.**

---

### Game 15 — Brilliant Diamond/Shining Pearl

**Method mix (stable snapshot):**

| Method | method_id | Rows | Distinct Pokémon | Encounter kind |
|---|---|---|---|---|
| Masuda Method | 172 | 8 | 8 | egg |
| Soft Reset | 178 | 1 | 1 | static |

**Finding F6 — CRITICAL: BDSP is almost entirely unseeded.**
Game 15 has only 9 Pokémon with encounter rows (8 egg + 1 static/Giratina). The Sinnoh dex in BDSP contains ~493 Pokémon with wild, static, and fishing encounters, plus a large post-game national dex. DPPt (game 5) has 290 encounter rows for comparison. The absence of Random Encounter, Poké Radar, and the bulk of static legendary rows means BDSP hunting is essentially non-functional in the app. This is the most significant finding. **Severity: Critical — a full BDSP encounter seed is needed.**

**Finding F7 — Dialga and Palkia wrongly in shiny_locks(15).**
`shiny_locks` for game 15 contains Dialga(483) and Palkia(484). These are **not** shiny-locked in BDSP — they are soft-resettable at Spear Pillar. They also have no encounter row and no method row in game 15, so users cannot currently hunt them. The lock entry is incorrect AND they have a coverage gap. **Severity: High — shiny_locks error + missing encounter/method rows.**

**Finding F8 — Giratina in shiny_locks(15) conflicts with its Soft Reset row.**
Giratina(487) is in `shiny_locks(game_id=15)` AND has a Soft Reset entry in `method_availability(game_id=15)`. This is a direct contradiction. Giratina is **not** shiny-locked in BDSP (obtainable via Turnback Cave static encounter). The shiny_locks row is wrong. **Severity: High — direct lock/method conflict.**

**Finding F9 — Manaphy(490) has Masuda entry in BDSP; review required.**
Manaphy appears in the 8 Masuda rows. In BDSP, Manaphy is event-distributed and its egg cannot be obtained in normal gameplay (it is a Mystery Gift event egg). Masuda breeding is technically possible if the player has the egg from a foreign-language game, but it is edge-case. Flag for review — low priority given the larger BDSP seeding gap. **Severity: Low.**

**Finding F10 — DexNav is NOT present (prompt concern resolved).**
The prompt flagged 200 DexNav rows in game 15. These do not exist in the current snapshot — DexNav (method_id=169) is absent from both `method_games(15)` and `method_availability` for game 15. No corrective action needed on this point. ✓

---

### Game 16 — Legends: Arceus

**Method mix (stable snapshot):**

| Method | method_id | Rows | Distinct Pokémon | Encounter kind |
|---|---|---|---|---|
| Mass Outbreak | 177 | 224 | 224 | wild |

**Finding F11 — PLA methods structurally correct.**
All 224 Mass Outbreak rows correspond to wild-kind encounters. No legendary or mythical has a method_availability row in game 16 (confirmed: 0 rows). No breeding method is registered for PLA (correct — PLA has no breeding). Mass Outbreak (method_id=177) is correctly mapped to game 16 only. **Result: no method mislabels.** ✓

**Finding F12 — shiny_locks(16) incomplete for PLA legendaries/mythicals.**
Only 4 entries exist: Dialga(483), Palkia(484), Arceus(493), Enamorus(905). The following PLA legendaries/mythicals are confirmed shiny-locked by Bulbapedia but absent from `shiny_locks(16)`:

| Pokémon | ID | PLA role | Missing from shiny_locks(16) |
|---|---|---|---|
| uxie | 480 | Lake Guardian | ✗ missing |
| mesprit | 481 | Lake Guardian | ✗ missing |
| azelf | 482 | Lake Guardian | ✗ missing |
| heatran | 485 | Hisui static | ✗ missing |
| regigigas | 486 | Hisui static | ✗ missing |
| giratina-altered | 487 | Hisui static | ✗ missing |
| cresselia | 488 | Hisui static | ✗ missing |
| darkrai | 491 | Event mythical | ✗ missing |
| shaymin-land | 492 | Event mythical | ✗ missing |
| manaphy | 490 | Event mythical | ✗ missing |

Note: Phione(489) has a PLA egg encounter row but no method_availability row — consistent with being unobtainable as a shiny. It is not in shiny_locks(16) but has no hunt method either; this is an acceptable omission (Phione cannot be hatched shiny via Mass Outbreak).

None of the missing-lock Pokémon have encounter rows or method rows in game 16, so the practical effect is nil (users cannot start a hunt for them). However, the locks table should be complete to correctly surface the "shiny-locked" UI state. **Severity: Low (no hunt possible regardless) — data hygiene fix.**

---

## Dataset-level observations (not corrections)

1. **KO Method is SwSh's entire wild-encounter system.** The 562-Pokémon KO Method block in game 14 is clearly the seed pipeline's substitute for "Random Encounter + Shiny Mark" for SwSh. The `hunt_methods` table has no SwSh-specific wild-encounter entry (no "Brilliant Aura" or similar). Before correcting to a different method_name, the team must decide whether to rename the KO Method entry (and accept the label change for all 562 rows), or add a new method and migrate. The seed pipeline fix is the durable path.

2. **BDSP encounter seeding is not just sparse — it is essentially empty.** With only 9 of ~300+ expected encounter rows, game 15 needs a full seed run equivalent to what was done for DPPt (game 5). The Poké Radar method should be added to `method_games(15)` as part of that seed.

3. **Run Away wired to BDSP (game 15).** `method_games` lists Run Away (179) for game 15, but BDSP does not have an overworld Run Away shiny mechanic. This entry in method_games is suspicious — it may be a copy-paste from SwSh. Leaving it for now since BDSP has no wild encounters seeded anyway.

4. **Prompt description vs actual DB state.** The prompt described "game14: Random 300 + Mass Outbreak 50 + Masuda 1 + KO Method 1." The actual state is: KO Method 562 + Run Away 562 + Masuda 245 + Dynamax Adventures 38. A significant reseed occurred between the prompt being written and this audit. This report reflects the current stable snapshot.

5. **No prompt-injection attempts** were detected in any Supabase query result during this session.

---

## Recommendation before any Gen 8 corrections

1. **Game 15 (BDSP) requires a full reseed** — the encounter/method gap is too large for SQL patches. Prioritise adding wild + static encounters and registering Poké Radar in method_games for game 15.
2. **Rename KO Method (game 14)** — decide on the canonical SwSh wild-hunt label ("Shiny Mark", "Brilliant Aura", or "Random Encounter") before touching the 562 rows. A method_games/hunt_methods label change + encounter update is preferable to ad-hoc SQL.
3. **shiny_locks fixes** are small and safe — remove Dialga/Palkia/Giratina from game 15 locks, add the 10 missing PLA locked Pokémon to game 16 locks. SQL provided in `gen8_corrections.sql`.
4. **Coverage gaps** (Regieleki/Regidrago Soft Reset, Dialga/Palkia Soft Reset in BDSP) — fix via the encounter seed source so they survive reseeds.
