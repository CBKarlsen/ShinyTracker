# SV team builder — deferred findings

Everything below was found during review of `docs/superpowers/plans/2026-08-16-sv-team-builder.md`,
judged not worth blocking the merge, and ruled **ship** by the final whole-branch review.
Recorded here because the execution ledger it lived in is scratch and gets deleted.

None of these is a correctness bug in the shipped feature. They are the honest edges.

## Worth doing next

**Species and item lists are re-fetched on every editor and import-sheet open.**
`ios/App/Teams/TeamEditorScreen.swift` and `ios/App/Teams/ImportPasteSheet.swift` both call
`client.pokemon(all: true)` plus `client.items()` from a view `.task`. Every other consumer of
the full dex caches it once on a model — `DexModel` loads it into the model, `NuzlockeModel`
guards with a `loadedSpeciesTypes` flag. Teams pays the whole-dex payload again on each push
and each sheet presentation. Functionally fine (the UI shows `#id` until it lands) but it
diverges from the established idiom without saying why. Fix: hoist onto `TeamsModel` behind a
one-shot flag, same shape as `NuzlockeModel.speciesTypes`.

**Showdown's default-form shorthand does not resolve.**
A paste saying `Deoxys` will not match `deoxys-normal`; same for `Indeedee`, `Toxtricity`,
`Lycanroc`, `Maushold`, `Urshifu`. It degrades correctly — the species is named in the import
warning and the rest of the team imports — but these are common picks. Fix: a base-name →
default-form fallback in the species match in `ImportPasteSheet`.

**Two Showdown fixture cases are missing.**
`shared/showdown_pastes.json` has 5 cases against the ~11 the spec lists. Uncovered anywhere:
*more than six sets in one paste* (the truncation lives in `ImportPasteSheet`, in the untestable
App target) and *unknown lines are skipped, not rejected*. Two more fixture cases would pin both.

**`ParseError.unknownStat` and `.malformedSpreadLine` have no direct test.**
Only `.empty` and `.unknownNature` are exercised. Add coverage if `parseSpread` is touched.

## Accepted as-is, with reasons

- **`StatCalculator` uses `Int(Double(core) * mod)`** rather than integer arithmetic, which
  `ShinyOdds.swift:262` warns against elsewhere. Verified safe: the doubles nearest 0.9 and 1.1
  are both *above* the decimal, so truncation never underflows an exact-integer case.
- **Malformed UUID in a path returns 500, not 404.** House behaviour — `UpdateHuntHandler` does
  the same. Consistency, not a regression.
- **Unknown `pokemon_id` returns 500, not 400.** Unreachable: every id comes from the server's
  own species list.
- **No per-user team cap.** All member free-text is bounded, so the footprint is bounded per team.
- **`GetItemsHandler` swallows per-row scan errors** without checking `rows.Err()`. Matches
  `GetUserGamesHandler` exactly.
- **`GET /api/me/teams/{id}` has no client.** Spec'd, harmless, currently unused surface.
- **Move picker's `.isSelected` is set-wide, not slot-wide** — it marks moves already used on the
  team, not in this slot. Does not affect what is saved.
- **The "None" row ticks on "every slot empty"** rather than "this slot empty", for the move
  picker only. The item picker, where `selected` is 0-or-1, is correct.
- **Species list truncates at 60 with no query** and gives no indication. Search covers it.
- **`slugify` maps an apostrophe to a hyphen** where the repo convention deletes it
  (`king-s-shield` vs `kings-shield`). Unreachable for real names — every apostrophe name
  resolves through `key(_:)` first — so it only shapes junk that will not join anyway.
- **`Nature(rawValue:) ?? .hardy` silently rewrites** an unrecognised stored nature, and export
  omits Hardy, so the nature line vanishes. Only reachable for a row written outside the app;
  the server validates natures.
- **An item with no English `effect_entries`** now keeps its stored description via
  `COALESCE(NULLIF(...))` — fixed, noted here only because the ledger listed it.

## Pre-existing, found in passing, out of scope for this branch

- `backend/cmd/seed_pokedex/main.go:82` has a bare `http.Get` with no timeout — the same bug
  class fixed in `pokeapi.go`. A stalled response hangs that seeder indefinitely.
