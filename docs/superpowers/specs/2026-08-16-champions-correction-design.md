# Pokémon Champions correction — design

The team builder merged in `0a84cb1` builds Scarlet/Violet teams. The target is
**Pokémon Champions**, which uses different mechanics on three of the axes that matter.
This spec corrects those three and adds the two team rules Champions enforces that
Scarlet/Violet does not.

It is a correction, not a rewrite. The structure — tables, API, Swift client, snapshot
caching, UI shell, pickers — is game-agnostic and stands.

## What went wrong, so it doesn't again

"Team builder for Pokémon champions" was read as *competitive players who are champions*,
not as the product **Pokémon Champions**. The owner's follow-up — "it should only know of
switch games, they are more easily accessible to pokemon champions" — was a statement about
what Champions sources from via Pokémon HOME, and was read as a statement about which games
competitive players own. That misreading produced a Scarlet/Violet scope and survived a
whole spec, plan, and eleven reviewed tasks, because every one of them was checked against
the plan rather than against the game.

**The lesson for this spec: every mechanic below is cited to a source.** Where a claim is
not verified against the live game or PokeAPI, it says so.

## What Pokémon Champions is

Released 8 April 2026 (Switch), 17 June 2026 (mobile). Free-to-start. The official
competitive hub — VGC 2026 Worlds runs on it. Pokémon arrive through Pokémon HOME from the
core series and Pokémon GO, restricted to species that exist in Champions.

## The three corrections

### 1. Mega Evolution replaces Terastallization

Champions' battle gimmick is **Mega Evolution**, enabled by the Omni Ring. There is no
Terastallization at launch (Bulbapedia notes Z-Moves, Dynamax/Gigantamax and Tera "will
also be supported in the future" — so this may change, and the schema should not make that
expensive).

Mega Evolution can be used **once per match**, and a Mega Stone occupies the **held item
slot**. That last detail is why this correction is cheap: `team_members.item_slug` already
carries it. PokeAPI has a `mega-stones` item category with **92 entries** (verified), so
the existing `cmd/seed_items` seeder covers it with one added category.

**Change:** drop `team_members.tera_type` and the Tera picker. Do not add a `mega_stone`
column — holding a Mega Stone *is* the Mega, and a second column would be a second source
of truth for one fact.

### 2. Stat Points replace EVs and IVs

Champions replaces both with a unified **Stat Point (SP)** system:

- **66 SP total per Pokémon, 32 maximum in any one stat**
- **IVs do not exist** — every Pokémon calculates as though it had 31 in all stats
- On transfer from HOME, EVs convert at 4 EVs for the first point in a stat and 8 for each
  additional; 1 SP is worth roughly 8 EVs
- Nature still applies, and can be changed with a Mint

**Change:** `evs` and `ivs` JSONB become a single `stat_points` JSONB, capped 66 total and
32 per stat. The IV editor is deleted outright — it edits a value the game does not have.

The three EV enforcement points become three SP enforcement points, at the same sites:
`evSpreadValid` in Go, `cappedEV` in `MemberSheet`, and `cappedEVs` in `ShowdownBridge`.

**The stat formula needs verification and must not be guessed.** The Gen 3+ formula in
`StatCalculator` takes an EV term; how 66 SP maps onto displayed stats is not established
here, and "1 SP ≈ 8 EVs" is a community approximation, not a source. This is exactly the
shape of problem `shared/odds_anchors.json` exists for: a calculation whose reference is
outside the repo, where agreement between our own implementations proves nothing. Pin it
with `shared/champions_stat_anchors.json`, built from stats read off real Pokémon in-game,
before writing the formula.

### 3. The species pool is Champions', not Scarlet/Violet's

PokeAPI carries the Champions data (verified live):

| Endpoint | Contents |
|---|---|
| `/api/v2/pokedex/champions` | **208 species** |
| `/api/v2/version-group/champions` | version `champions`, generation-ix |
| `/api/v2/item-category/mega-stones` | **92 Mega Stones** |
| Champions movesets | present — `champions` appears in `version_group_details` on moves |

So this is a re-point, not a new pipeline. `game_id` stops meaning 17 (Scarlet/Violet) and
means a new Champions row in `games`; the moveset seeder reads the `champions` version group
instead of `scarlet-violet`; a new seeder populates availability from the Champions Pokédex.

Note the pool **grows in batches alongside new Regulation Sets**, so this is not a one-time
seed — it needs re-running when a batch lands, and `cmd/seed_items` and the moveset seeder
must stay idempotent (they are).

## Two team rules Champions enforces

Neither exists in the current builder, and both are cheap:

- **No two Pokémon may hold the same item.** Sharpened by Megas: two Mega Stones on one team
  is legal by this rule but only one Mega can be used per match, which is a strategy note
  rather than a validation rule.
- **No duplicate species on a team.**

Both belong in `validateMembers` beside the existing caps, and both should be surfaced in
the UI before save rather than as a 400.

Also: every Pokémon is **auto-levelled to 50** in battle. The builder already defaults to
level 50, so the level field is now decoration — consider removing it rather than letting a
user set a number the game overrides.

## Format

Teams are **six Pokémon; you bring four** to a battle (4v4 doubles in ranked Regulation
Sets M-A and M-B). The builder's six slots are right. A "bring 4" selection layer is
deliberately **out of scope** — it is a battle-prep concept, not a team-building one, and
nothing in the schema blocks adding it later.

## What stands, unchanged

`teams` and `team_members` (minus the three columns above) · the whole `/api/me/teams` API
and its per-user scoping · the Swift client and models · `SnapshotStore` caching ·
`TeamsModel` and its lifecycle · the Teams tab, editor and member sheet · the species,
ability, item and move pickers · natures (all 25, unchanged in Champions) · level 50 ·
online-write with cached reads.

## The open question: is the Showdown paste parser still worth having?

`ShowdownPaste` and `ShowdownBridge` are the best-tested code in the merge — a shared
fixture, parse, export, and a round-trip property. But Champions is not Pokémon Showdown,
and the paste format encodes EVs, IVs and Tera types, two of which Champions does not have.

Three options, and this is a product call rather than a technical one:

1. **Keep as an import path only.** A user with an existing SV team can paste it in and get
   a starting point, with EVs converted to SP at the documented 4/8 rate and the Tera line
   dropped. Export is removed, because exporting a Champions team as a Showdown paste
   produces a set that misrepresents itself.
2. **Keep both**, and accept that export is lossy in a way the format cannot express.
3. **Remove both**, and revisit if the Champions community settles on a text interchange
   format worth supporting.

**Recommendation: option 1.** Import is genuinely useful — it is how someone brings a team
they already have — and the conversion direction is well-defined. Export is where the
misrepresentation happens, and nothing is lost by dropping it until there is a format to
export *to*. This deletes roughly the export half of `ShowdownBridge` and its round-trip
test; the parser and its fixture stay.

## Deferred, with reasons

| Deferred | Why |
|---|---|
| Regulation Sets as data (M-A, M-B, …) | The pool and its legality are regulation-gated and change on a schedule. This is the same perishable-external-data problem as the odds meta sub-project, and belongs with it. |
| Damage calculation | Unchanged from the original programme — its own sub-project, and Megas make it a bigger one. |
| "Bring 4" selection | Battle prep, not team building. |
| Z-Moves, Dynamax, Tera | Bulbapedia says they are planned for Champions. Do not build for them now; just do not make the schema hostile to a future per-member gimmick column. |
| The shiny bridge | Still deferred, still cheap. |

## Migration note

`teams` and `team_members` are live in production but hold **zero rows** — the feature has
never shipped to a user. So the three column changes can be a plain `ALTER`, with no data
migration and no backfill. That will not be true a second time; this is the free window.

## Related

- `docs/superpowers/specs/2026-08-16-sv-team-builder-design.md` — the design this corrects
- `docs/superpowers/plans/2026-08-16-sv-team-builder-followups.md` — deferred findings, still open
- `shared/odds_anchors.json` — the fixture pattern `champions_stat_anchors.json` should copy
