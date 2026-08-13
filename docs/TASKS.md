# ShinyTracker — backlog

Two tracks now, and they have different shapes:

- **Native iOS client** (`ios/`) — the mobile app, where all recent work has gone. Hunt, Dex and
  Nuzlocke modes ship; it renders offline and counts offline.
- **Web living-dex** (`frontend/`) — the original completionist tooling. Still live, still the only
  client for phases and the absolute-count write path.

Status: ✅ shipped · 🔜 next · ⏳ backlog · 🐞 follow-up

---

## ✅ Shipped — iOS

- **Hunt mode** — list, counter with haptics, new-hunt sheet, found/abandon, games tab.
- **Dex mode** — per-game grid, Living and Shiny checklists, species sheet with type matchups.
- **Nuzlocke mode** — run screen, checkpoint sheet, encounter logging, party/box/graveyard, and a
  coverage warning that reads the next boss's *damaging* moves and names which boxed Pokémon resist.
- **A whole Platinum run seeded** — 62 mandatory stops, 206 pool rows, 28 checkpoints, 104 squad
  members. Encounter pools are **derived from `pokemon_locations`**, not hand-written; rosters are
  researched. Timelines key on **version** (`platinum` ≠ `diamond`) and rival squads on the
  **player's starter**, because both genuinely differ.
- **Perceived performance** — screens no longer blank on tab switch, sprites are cached with a real
  placeholder, and the Nuzlocke timeline stopped rescanning itself once per row per frame.
- **Offline, sub-project A** — `SnapshotStore` renders last-known data on a cold launch; `HuntClock`
  gives the client its own elapsed time (completing D1).
- **Offline, sub-project B** — counting and completing a hunt work with **no signal**. Taps append to
  a durable `WriteQueue` and drain as relative **deltas** with idempotency keys, deduped server-side
  in one transaction.

---

## 🔜 Next up

Three candidates, in the order I'd take them.

### 1. Move the web client to deltas
Half done. The **perimeter is gone** (2026-08-13): `allow_decrease`, `calc.DecideEncounterCount`
and `HuntCountPolicy`'s two permission rules are deleted, because no client ever sent the flag and
the clamp behind it was silently discarding the web's miscount undo.

What remains is the path itself. `frontend/` still PATCHes absolute counts from five sites
(`Dashboard.tsx` flush / revertBurst / break-chain / phase-reset, `useHunts.updateEncounterCount`),
guarded client-side by `seqRef`. Moving them to `encounter_delta` would delete that machinery too
and close the last multi-device gap — two web tabs on one hunt currently last-write-wins.

Note `hunt_parameters.chain_length` is absolute regardless, so `seqRef` cannot go entirely on a
count-only migration.

### 2. Offline, sub-project C — the remaining write paths
Nuzlocke encounters, party/boss progress, dex ticks, charm toggles. Mostly repetition now that the
queue, the idempotency scheme and the drain exist.

The genuinely new part: Nuzlocke's `is_dupe` is computed server-side against every other catch in
the run, and the encounter pool is validated server-side — so an offline catch is **provisional**
until it replays. That was accepted knowingly when "everything writable offline" was chosen.

### 3. Seed more Nuzlocke routes
Platinum is the only game with a timeline. The screen is complete; the data stops after one game.
`pokemon_locations` already holds 58k rows across 12 games, so **pools derive by SQL** — only the
route *order* and the *trainer squads* need research. Gens 8/9 have no location rows at all.

---

## ⏳ Backlog

### iOS
- **Team mode** is still a placeholder, and the design says it is entered *from* a run — the Nuzlocke
  coverage warning is the doorway. No backend exists for it.
- **Apple Watch companion** (D3's second-best counting interaction). The delta write model was chosen
  specifically to make this possible without a rewrite.
- **Background sync** — a landed plane currently syncs when the app is next opened.
- **Starting a hunt offline** — needs client-generated hunt ids the server accepts.

### Web living-dex
- **#3 Living-dex scope selector** — a game's regional dex vs the National dex. Scope toggle is small.
  **Forms-as-targets** (Alolan/Galarian/Hisuian, Unown) is large — the backend caps at 1025 base
  species, so a shiny Alolan Raichu cannot be represented. Scope deliberately.
- **#5 Completion forecast** — project encounters/hours to finish the chosen dex from best-route ETAs.
- **#6 Acquisition provenance filters** — `acquisition_type` exists, just is not surfaced.
- **#7 Bulk import** — CSV / Home-export to mark many owned shinies at once.
- **Shiny-lock accuracy audit** — `backend/seeds/shiny_locks.json` (28 entries) is a ~50-60% starter
  set. Verify Tapu Koko/Lele/Bulu/Fini (#785-788, likely soft-resettable in SM/USUM), Necrozma
  SM-only (#800), Cosmog (#789); find missing gift-starter and Gen 3-5 story locks.

---

## 🐞 Known issues and deferred debt

### Offline programme (A and B)
Recorded here because it exists nowhere else in the repo — the reviews that found it were the only
place it lived.

- **A failed write against a *responding* server will not retry for 30 s**, including via
  pull-to-refresh, which is therefore silently a no-op. The cooldown is deliberate: without it, five
  answered failures cost ~3 seconds of tapping and the queue was deleted. A "waiting to retry" line
  in the pending marker is the cheap fix.
- **`failures` never decays** beyond that cooldown, so five 5xx spread over days still drop an entry.
- **`hunt_writes` grows unboundedly.** ⚠️ **Naive pruning is unsafe** — deleting a `write_id` whose
  entry is still queued on a device re-arms a double-apply. Client-side expiry has to come first.
- **`LogPhaseHandler` can deadlock** against the delta path's `FOR UPDATE` (it takes `FOR KEY SHARE`
  via an FK then upgrades). Recoverable via retry; the fix is to take the row lock first.
- **`failedWrites` is memory-only** — a permanent-failure message can be lost on force-quit.
- **A hunt completed offline shows no pending marker in History**, because `HistoryRow` never asks.
- **`.pendingWrites` is records, not cache**, but lives in a store documented as discardable. The
  comments say so now; the real fix is a separate versioning scheme.
- **`load()` has no reentrancy guard** (unlike `drain()`). Re-verified as not currently racing, but it
  is the first place to look if the hunt list ever shows a wrong count.

### Data and odds
- **`GetOddsHandler` (`GET /odds`) is unused** — every odds display computes client-side. Dead but
  harmless; route through `calc.EffectiveOdds` or delete if revived.
- **Radar chain-0 quirk** — `radar_chain_gen4` returns 1/65536 at chain 0, mirrored in Go for parity.
  Revisit whether the base should track the game's 1/8192.
- **Masuda labeling** — correct but broad for base forms; the evolve-from flow could read clearer.
- **Forms / regional variants** — not representable (see #3). Larger data-model change.
- **Nuzlocke rosters are single-sourced on movesets.** Levels and order were cross-validated by two
  independent research passes; Serebii publishes no movesets, so abilities and moves came from
  Bulbapedia alone. Three details remain disputed between Bulbapedia's own pages: Cyrus's Golbat's
  third move, his Houndoom's ability, and slot order for Aaron/Bertha/Barry's final team.

### Method eligibility — pass complete
A (SV/SwSh/LA) ✅ · B dropped (Poké Radar draws the full grass table, so attaching it broadly is
correct) · C (ORAS fishing) ✅ · D (Dynamax Adventures) ✅.

Remaining: the 9 DA Ultra Beasts; home-game static coverage for the 24 DA legends; per-species
wild-curation refinement of the dex-membership proxies via `method_exceptions`.

---

## Operational notes (re-seeding the shared Supabase DB)

- **Seed order matters:** `cmd/sync` truncates `hunt_methods` (cascading `method_availability` to 0).
  Always run **`cmd/seed` LAST**. Full rebuild: `apply_schema` → `cmd/sync` (slow PokeAPI crawl;
  populates `evolves_from_id`) → `cmd/seed` → `cmd/seed_shiny_locks`.
- `cmd/apply_schema` is destructive to the method tables; `cmd/seed` rebuilds them.
- Health check: `go run ./cmd/audit_methods/main.go` (Section B = real availability inconsistencies).
- **`cmd/seed_locations` is independent of the order above.** It touches only `pokemon_locations`,
  never `hunt_methods`, so it is safe to re-run at any time. Exits non-zero if any Gen 2-7 game ends
  up with zero rows.
- **`cmd/seed_nuzlocke` no longer reads the design prototype.** `seeds/nuzlocke_*.json` is maintained
  research data: it carries species and move **names**, and the seeder resolves ids, move
  type/power/damage-class and each stop's encounter pool from the database. Unknown names are fatal.

## Migrations

No migration runner — numbered files in `backend/migrations/` are applied by the operator. Applied
through **019** (`hunt_writes`). `backend/schema.sql` is the full DDL and is kept in step by hand.
