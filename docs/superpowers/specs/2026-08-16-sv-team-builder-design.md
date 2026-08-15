# Scarlet/Violet team builder — design

The first slice of a competitive-play mode: build a six-Pokémon Scarlet/Violet team,
save it, and move it in and out of Pokémon Showdown paste format.

This is sub-project 1 of a four-part programme (see [Programme context](#programme-context)).
It deliberately does **not** calculate damage, know about tiers or usage, or read your
shiny collection. Each of those is its own spec.

## Why this first

The competitive audience is not the collecting audience, and the two halves of this app
will always be in tension. This slice is chosen because it is the one with **no external
dependency and no formula to get wrong**: it is storage, a picker, and a text format.

It also rides data that already exists. `pokemon_moves` holds **733 species and 45,969 move
rows for Scarlet/Violet** — seeded, live, and the only Switch title with move data at all
(SwSh, BDSP, Legends: Arceus and Let's Go are all zero). Scoping to SV is therefore not a
compromise; it is the only Switch scope that needs no new seeding job, and it happens to be
where current VGC is played.

## Scope

**In:**

- Six team slots, each: species · nature · ability · held item · up to four moves · Tera type
- EV and IV spreads, with the game's own caps enforced (508 EV total, 252 per stat, 31 IV)
- Computed final stats at level 50 and level 100
- Named teams, created/renamed/deleted, persisted server-side and cached offline
- Showdown paste **import** and **export**, round-tripping

**Out, and each is a later spec:**

- Damage calculation (sub-project 2)
- Tiers, usage statistics, format legality beyond "exists in SV" (sub-project 3)
- The "only my shinies" filter (sub-project 4 — explicitly deferred by the owner)
- Any game other than Scarlet/Violet
- Sharing teams between users

## Programme context

| # | Sub-project | Status |
|---|---|---|
| 0 | Rename + app shell | **Blocked on a name.** Must land before the first TestFlight upload — the bundle identifier is permanent from that point. |
| 1 | **SV team builder** | This spec |
| 2 | Damage calculator | Later. Needs an anchor fixture verified against an external reference, same discipline as `shared/odds_anchors.json`. |
| 3 | Meta / usage data | Last. The only piece with an external dependency and a ToS question, and the only one that rots if unmaintained. |
| 4 | Shiny bridge | Cheap once 1 exists. |

Nothing in this spec depends on the rename. The two can proceed in parallel.

## Data

### New static data

**Natures — hardcode, do not seed.** All 25, each raising one stat by 10% and lowering
another. They have not changed since Generation 3 and cannot change without a new game.
A table would be a migration, a seeder, and a network round trip in exchange for nothing.
This is a Swift enum in `ShinyTrackerKit` and a Go map, mirroring how
`calc.ShinyCharmAvailable` already handles a small closed set.

**Held items — seed.** Roughly 100 competitively relevant items. Unlike natures this genuinely
changes between generations and needs a name, a sprite and a description, so it is a table
(`items`) and a seeder (`cmd/seed_items`) reading PokeAPI.

Items whose *effects* matter (Choice Band's ×1.5 attack, Life Orb's ×1.3) carry no mechanical
data in this slice. Effects belong to the damage calculator, which is where they can be
tested against a reference. Storing an unused `effect_multiplier` column now is a guess that
sub-project 2 would have to unpick.

### New user data

```sql
CREATE TABLE teams (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    game_id     INTEGER NOT NULL REFERENCES games(id),   -- always 17 in this slice
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE team_members (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    team_id      UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    slot         SMALLINT NOT NULL CHECK (slot BETWEEN 1 AND 6),
    pokemon_id   INTEGER NOT NULL REFERENCES pokemon(id),
    nickname     TEXT,
    nature       TEXT NOT NULL,
    ability_slug TEXT NOT NULL,
    item_slug    TEXT,
    tera_type    TEXT,
    level        SMALLINT NOT NULL DEFAULT 50,
    evs          JSONB NOT NULL,          -- {"hp":252,"atk":0,...}
    ivs          JSONB NOT NULL,
    moves        TEXT[] NOT NULL,         -- move slugs, 0–4
    UNIQUE (team_id, slot)
);
```

`game_id` is stored even though it is always Scarlet/Violet today. Adding it later means a
migration over live rows with no correct default; adding it now costs one column.

EVs and IVs are JSONB rather than twelve integer columns because they are always read and
written as a whole spread, never queried by individual stat — the same reasoning that put
`hunt_parameters` in JSONB.

**The EV cap is enforced in three places on purpose:** a `CHECK`-equivalent validation in the
handler, a guard in the Swift model, and the UI refusing the input. The database cannot
express "sum of JSONB values ≤ 508" cheaply, and a team that violates it is a team that
exports to a paste Showdown will reject — a silent corruption of the one output that matters.

## API

Five routes, following the existing `/api/me/*` convention established when
`/api/user/{id}/games` was collapsed:

| Method | Path | Notes |
|---|---|---|
| `GET` | `/api/me/teams` | List with members, one query plus a join |
| `POST` | `/api/me/teams` | Create; accepts a full team including members |
| `GET` | `/api/me/teams/{id}` | One team |
| `PATCH` | `/api/me/teams/{id}` | Rename, or replace the member set wholesale |
| `DELETE` | `/api/me/teams/{id}` | |

Every handler scopes by `user_id` from the token, never from a path or body parameter. This
is not a style note: RLS is enabled but bypassed by the backend's `postgres` role, so these
`WHERE` clauses are the *only* thing isolating one user's teams from another's.

`PATCH` replaces the whole member set rather than patching individual slots. A team is edited
as a unit, six slots are small, and per-slot patching invents a merge problem that the
encounter-delta work already showed is expensive to get right.

A new `GET /api/items` serves the static item list, public and unauthenticated like
`/api/games` and `/api/methods`.

## iOS architecture

A new `ios/App/Teams/` alongside `Hunt/`, `Dex/` and `Nuzlocke/`, following their shape
exactly:

- `TeamsModel.swift` — `@MainActor @Observable`, owns the list and the load/refresh/appear
  lifecycle, matching `HuntListModel` and `DexModel`
- `TeamsScreen.swift` — list of saved teams
- `TeamEditorScreen.swift` — the six slots
- `MemberSheet.swift` — editing one slot: species, nature, ability, item, moves, spread
- `TeamsPreviewHarness.swift` — `#if DEBUG`, using the shared `PreviewHarness`

Persistence reuses what exists: a `.teams` key on `SnapshotStore` for offline reads, and the
existing `WriteQueue` for writes.

`WriteQueue` already carries two payload shapes — `.count(delta:)` and `.phase(pokemonID:)` —
so a third is a pattern the type was built for, not a redesign. But both existing cases are
small, hunt-scoped, and *coalescable*: ten taps merge into one `+10`. A team write is a whole
six-slot document and merges by last-write-wins instead. That difference is the actual work,
and the plan should treat it as a task rather than an assumption. If it proves larger than it
looks, teams ship read-cached and write-online-only, with offline writes following separately —
a team you cannot edit in a tunnel is a smaller failure than a hunt you cannot count.

Pure logic — the Showdown parser, stat computation, EV validation — lives in
`ShinyTrackerKit`, which has a test target. The view models do not, and that is exactly why
`HuntCountPolicy` was extracted there. Anything worth testing goes in the package.

### Stat computation

The Gen 3+ formula, which has not changed since Ruby/Sapphire:

```
HP    = floor((2 × Base + IV + floor(EV/4)) × Level / 100) + Level + 10
Other = floor((floor((2 × Base + IV + floor(EV/4)) × Level / 100) + 5) × NatureMod)
```

Shedinja's HP is always 1 regardless of the formula. That is the only special case, and it
is the kind of thing a fixture catches and a reviewer does not.

## The Showdown paste format

This is the riskiest part of the slice and the reason it is worth a spec.

The format is human-authored, loosely specified, and everywhere in competitive Pokémon. It is
the interop layer: a team that round-trips is a team that works with Showdown, Pikalytics,
every damage calculator, and every forum post. A team that round-trips *lossily* is worse
than no export at all, because the loss is silent.

```
Garchomp (M) @ Rocky Helmet
Ability: Rough Skin
Level: 50
Tera Type: Steel
EVs: 252 Atk / 4 SpD / 252 Spe
Jolly Nature
IVs: 0 SpA
- Earthquake
- Dragon Claw
- Stealth Rock
- Swords Dance
```

Every line except the first is optional. The first line alone carries four optional elements:
a nickname (`Chomp (Garchomp) @ ...`), a gender, a form (`Urshifu-Rapid-Strike`), and an item.

Known cases the fixture must cover:

- Nickname present, absent, and containing parentheses
- Gender `(M)`, `(F)`, absent
- Hyphenated forms — `Urshifu-Rapid-Strike`, `Ogerpon-Wellspring`, `Tauros-Paldea-Aqua`
- No item
- Missing `EVs:` line entirely (all zero) and partial spreads
- `IVs: 0 Atk` — the omitted stats are 31, not 0. **This is the single most common way a
  naive parser corrupts a set**, and it flips a physical attacker's damage output.
- Nature line present and absent
- Fewer than four moves
- Moves with hyphens (`U-turn`) and spaces (`Swords Dance`)
- Windows line endings, trailing whitespace, blank lines between sets
- More than six sets in one paste

### Testing

`shared/showdown_pastes.json` — a fixture of real pastes paired with their expected parsed
structures, consumed by a Swift test in `ShinyTrackerKit`.

This mirrors `shared/odds_anchors.json` deliberately. That file exists because three
independent odds engines agreeing with each other proved nothing; the fixture is the
reference. Here there is one implementation, so the fixture serves the second purpose: it
pins behaviour against a format defined by someone else's software.

Three properties, asserted per fixture:

1. **Parse** — a paste produces the expected structure
2. **Round-trip** — parse then export reproduces the input, modulo normalised whitespace
3. **Reject** — malformed input returns a typed error naming the offending line, never a
   partially populated team

Round-trip is the property that catches silent loss. Parse-only tests pass happily while
export quietly drops the Tera type.

## Error handling

Following the conventions already in the codebase:

- A failed team load falls back to the `SnapshotStore` snapshot and shows an inline sync
  warning, never an error screen over cached content — the rule `DexModel` and
  `NuzlockeModel` already follow
- A failed write rolls back the optimistic change and surfaces a dismissible banner
- An import failure names the line and leaves any existing team untouched. Import is
  additive: it never overwrites in place, so a bad paste cannot destroy a saved team.
- A session expiry routes through the existing `SessionExpiredError` path

## Deferred, with reasons

| Deferred | Why |
|---|---|
| Damage calculation | Needs its own external reference and fixture. Bolting it on here would make this slice unverifiable. |
| Format legality (Reg H, etc.) | Regulation sets change every few months. This is perishable meta data and belongs with sub-project 3, which will already own a refresh pipeline. |
| Shiny bridge | Owner deferred it. Cheap to add once the picker exists. |
| Games other than SV | No moveset data exists for any other Switch title. Adding one means a seeding job before any builder work. |
| Team sharing | Needs a sharing model, public URLs, and moderation questions. Export to a paste already gives the user a way to share. |

## Related

- `docs/superpowers/specs/2026-08-13-offline-write-queue-design.md` — the `WriteQueue` this extends
- `docs/superpowers/specs/2026-08-12-offline-foundation-design.md` — `SnapshotStore`
- `shared/odds_anchors.json` — the fixture pattern `shared/showdown_pastes.json` copies
