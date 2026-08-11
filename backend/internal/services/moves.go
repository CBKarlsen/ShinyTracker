package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/casper/shinytracker/internal/database"
	"github.com/jackc/pgx/v5"
)

// This file backs cmd/seed_moves. It is deliberately independent of
// pokeapi.go's SyncPokemonData/processPokemon (cmd/sync's crawler): the two
// commands have different lifecycles and no reason to share request-shaped
// state, so keeping them decoupled keeps a change to one from risking the
// other's merge.

// ---------------------------------------------------------------------------
// PokeAPI response shapes
// ---------------------------------------------------------------------------

// pokeAPINamedList is the shape of PokeAPI's list endpoints (/move, /ability),
// which additionally report `count` -- used to fetch the whole list in one
// page instead of guessing a limit.
type pokeAPINamedList struct {
	Count   int `json:"count"`
	Results []struct {
		Name string `json:"name"`
		URL  string `json:"url"`
	} `json:"results"`
}

// pokeAPILangText is PokeAPI's repeated "text in every language" shape, used
// for both localized names and effect entries.
type pokeAPILangText struct {
	Name     string `json:"name"`
	Language struct {
		Name string `json:"name"`
	} `json:"language"`
}

type pokeAPIEffectEntry struct {
	ShortEffect string `json:"short_effect"`
	Language    struct {
		Name string `json:"name"`
	} `json:"language"`
}

// pokeAPIMoveDetail is the subset of /move/{id} needed for the `moves` table.
type pokeAPIMoveDetail struct {
	Name     string `json:"name"`
	Power    *int   `json:"power"`
	Accuracy *int   `json:"accuracy"`
	PP       int    `json:"pp"`
	Type     struct {
		Name string `json:"name"`
	} `json:"type"`
	DamageClass struct {
		Name string `json:"name"`
	} `json:"damage_class"`
	Names         []pokeAPILangText    `json:"names"`
	EffectEntries []pokeAPIEffectEntry `json:"effect_entries"`
}

// pokeAPIAbilityDetail is the subset of /ability/{id} needed for the
// `abilities` table.
type pokeAPIAbilityDetail struct {
	Name          string               `json:"name"`
	Names         []pokeAPILangText    `json:"names"`
	EffectEntries []pokeAPIEffectEntry `json:"effect_entries"`
}

type pokeAPIStatEntry struct {
	BaseStat int `json:"base_stat"`
	Stat     struct {
		Name string `json:"name"`
	} `json:"stat"`
}

type pokeAPIAbilitySlot struct {
	Ability struct {
		Name string `json:"name"`
		URL  string `json:"url"`
	} `json:"ability"`
	IsHidden bool `json:"is_hidden"`
	Slot     int  `json:"slot"`
}

type pokeAPIMoveVGDetail struct {
	LevelLearnedAt  int `json:"level_learned_at"`
	MoveLearnMethod struct {
		Name string `json:"name"`
	} `json:"move_learn_method"`
	VersionGroup struct {
		Name string `json:"name"`
	} `json:"version_group"`
}

type pokeAPIMoveEntry struct {
	Move struct {
		Name string `json:"name"`
		URL  string `json:"url"`
	} `json:"move"`
	VersionGroupDetails []pokeAPIMoveVGDetail `json:"version_group_details"`
}

// pokeAPISpeciesMoveset is the subset of /pokemon/{id} needed for base
// stats, ability slots, and per-version-group learnsets. Deliberately not
// reused/merged with pokeapi.go's PokeAPIPokemonResponse -- see the package
// comment above.
type pokeAPISpeciesMoveset struct {
	Stats     []pokeAPIStatEntry   `json:"stats"`
	Abilities []pokeAPIAbilitySlot `json:"abilities"`
	Moves     []pokeAPIMoveEntry   `json:"moves"`
}

// ---------------------------------------------------------------------------
// Pure parsing (unit tested in moves_test.go)
// ---------------------------------------------------------------------------

// englishName returns the "en"-tagged entry from a PokeAPI `names` list,
// falling back to the slug if no english entry is present (defensive; every
// real PokeAPI response has one).
func englishName(names []pokeAPILangText, fallback string) string {
	for _, n := range names {
		if n.Language.Name == "en" {
			return n.Name
		}
	}
	return fallback
}

// englishEffect returns the "en"-tagged short_effect from a PokeAPI
// `effect_entries` list, or "" if none is present (some obscure entries lack
// english text entirely).
func englishEffect(entries []pokeAPIEffectEntry) string {
	for _, e := range entries {
		if e.Language.Name == "en" {
			return e.ShortEffect
		}
	}
	return ""
}

// BaseStats is the six base stats parsed from a /pokemon/{id} payload.
type BaseStats struct {
	HP             int
	Attack         int
	Defense        int
	SpecialAttack  int
	SpecialDefense int
	Speed          int
}

// parseBaseStats extracts the six base stats keyed by PokeAPI stat name
// rather than assumed array position (PokeAPI documents, but does not
// guarantee, a fixed order). ok is false if any of the six is missing, so a
// short/malformed payload can never silently write partial/zeroed stats.
func parseBaseStats(stats []pokeAPIStatEntry) (BaseStats, bool) {
	var b BaseStats
	seen := make(map[string]bool, 6)
	for _, s := range stats {
		switch s.Stat.Name {
		case "hp":
			b.HP = s.BaseStat
		case "attack":
			b.Attack = s.BaseStat
		case "defense":
			b.Defense = s.BaseStat
		case "special-attack":
			b.SpecialAttack = s.BaseStat
		case "special-defense":
			b.SpecialDefense = s.BaseStat
		case "speed":
			b.Speed = s.BaseStat
		default:
			continue
		}
		seen[s.Stat.Name] = true
	}
	return b, len(seen) == 6
}

// AbilitySlotRef is one parsed ability slot, ready to resolve against the
// abilities reference table by Slug.
type AbilitySlotRef struct {
	Slug     string
	Slot     int
	IsHidden bool
}

// parseAbilitySlots extracts the ability slots from a /pokemon/{id} payload.
// PokeAPI's ability name IS the slug the `abilities` table is keyed on, so no
// further normalization is needed.
func parseAbilitySlots(abilities []pokeAPIAbilitySlot) []AbilitySlotRef {
	out := make([]AbilitySlotRef, 0, len(abilities))
	for _, a := range abilities {
		out = append(out, AbilitySlotRef{Slug: a.Ability.Name, Slot: a.Slot, IsHidden: a.IsHidden})
	}
	return out
}

// movesetVersionGroups maps a PokeAPI version_group slug we seed to the
// games.title row it belongs to. Only Platinum and Scarlet/Violet are seeded
// so far, per spec -- adding another game later is additive: add an entry
// here and re-run cmd/seed_moves, no schema change required.
var movesetVersionGroups = map[string]string{
	"platinum":       "Diamond/Pearl/Platinum",
	"scarlet-violet": "Scarlet/Violet",
}

// normalizeLearnMethod maps PokeAPI's move-learn-method vocabulary onto ours
// (level-up/tm/egg/tutor). PokeAPI's "machine" bucket covers both TMs and
// TRs/HMs, which we call "tm". Anything else (Stadium-era curiosities,
// Colosseum/XD purification, form-change, zygarde-cube, ...) is not one of
// our four categories and is reported not-ok so the caller skips it.
func normalizeLearnMethod(pokeAPIMethod string) (string, bool) {
	switch pokeAPIMethod {
	case "level-up":
		return "level-up", true
	case "machine":
		return "tm", true
	case "egg":
		return "egg", true
	case "tutor":
		return "tutor", true
	default:
		return "", false
	}
}

// MoveLearnEntry is one (move, game, method[, level]) row, ready to resolve
// against the moves/games tables and insert into pokemon_moves.
type MoveLearnEntry struct {
	MoveSlug  string
	GameTitle string
	Method    string
	Level     *int // non-nil only when Method == "level-up" and the level is known
}

// parseMoveset flattens one species' /pokemon/{id} `moves` array into learn
// entries, restricted to movesetVersionGroups. PokeAPI repeats a
// (move, version_group) pair once per distinct learn method (e.g. a move
// learnable both by level-up and by tutor in the same game), so both survive
// here; exact duplicates (e.g. the same level-up entry listed twice) are left
// for the caller to dedupe against the pokemon_moves natural key.
func parseMoveset(moves []pokeAPIMoveEntry) []MoveLearnEntry {
	var out []MoveLearnEntry
	for _, m := range moves {
		for _, vgd := range m.VersionGroupDetails {
			gameTitle, ok := movesetVersionGroups[vgd.VersionGroup.Name]
			if !ok {
				continue
			}
			method, ok := normalizeLearnMethod(vgd.MoveLearnMethod.Name)
			if !ok {
				continue
			}
			entry := MoveLearnEntry{MoveSlug: m.Move.Name, GameTitle: gameTitle, Method: method}
			if method == "level-up" && vgd.LevelLearnedAt > 0 {
				lvl := vgd.LevelLearnedAt
				entry.Level = &lvl
			}
			out = append(out, entry)
		}
	}
	return out
}

// ---------------------------------------------------------------------------
// Seeding (I/O)
// ---------------------------------------------------------------------------

// movesWorkers bounds concurrency against PokeAPI, matching the pace of the
// other crawlers in this package (pokeapi.go, locations.go): a handful of
// workers with a short per-request sleep is enough to finish in minutes
// without hammering a free public API.
const movesWorkers = 5

// SeedMoveReference upserts the `moves` table from PokeAPI's full move list
// (~937 entries as of Gen 9), keyed by slug so re-runs never duplicate rows.
// Returns the slug -> id map for phase 3 (pokemon_moves) and a count of rows
// touched.
func SeedMoveReference(ctx context.Context) (map[string]int, int, error) {
	log.Println("Seeding moves reference table...")
	names, err := fetchAllNames("move")
	if err != nil {
		return nil, 0, fmt.Errorf("failed to list moves: %w", err)
	}

	ids := make(map[string]int, len(names))
	var mu sync.Mutex
	var touched int
	var firstErr error

	jobs := make(chan string, len(names))
	for _, n := range names {
		jobs <- n
	}
	close(jobs)

	var wg sync.WaitGroup
	for i := 0; i < movesWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for name := range jobs {
				time.Sleep(100 * time.Millisecond)
				id, err := seedOneMove(ctx, name)
				mu.Lock()
				if err != nil {
					log.Printf("Failed to seed move %q: %v", name, err)
					if firstErr == nil {
						firstErr = err
					}
				} else {
					ids[name] = id
					touched++
				}
				mu.Unlock()
			}
		}()
	}
	wg.Wait()

	log.Printf("Moves reference table: %d/%d upserted.", touched, len(names))
	if firstErr != nil {
		return ids, touched, fmt.Errorf("one or more moves failed to seed (see logs); re-run cmd/seed_moves to retry: %w", firstErr)
	}
	return ids, touched, nil
}

func seedOneMove(ctx context.Context, name string) (int, error) {
	resp, err := httpClient.Get(fmt.Sprintf("https://pokeapi.co/api/v2/move/%s", name))
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("unexpected status %d", resp.StatusCode)
	}
	var d pokeAPIMoveDetail
	if err := json.NewDecoder(resp.Body).Decode(&d); err != nil {
		return 0, fmt.Errorf("decode: %w", err)
	}

	var id int
	err = database.DB.QueryRow(ctx, `
		INSERT INTO moves (slug, name, type, damage_class, power, accuracy, pp, effect)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (slug) DO UPDATE SET
			name = EXCLUDED.name, type = EXCLUDED.type, damage_class = EXCLUDED.damage_class,
			power = EXCLUDED.power, accuracy = EXCLUDED.accuracy, pp = EXCLUDED.pp, effect = EXCLUDED.effect
		RETURNING id
	`, d.Name, englishName(d.Names, d.Name), d.Type.Name, d.DamageClass.Name, d.Power, d.Accuracy, d.PP, englishEffect(d.EffectEntries)).Scan(&id)
	return id, err
}

// SeedAbilityReference upserts the `abilities` table from PokeAPI's full
// ability list (~373 entries), keyed by slug. Returns the slug -> id map for
// phase 3 (pokemon_abilities) and a count of rows touched.
func SeedAbilityReference(ctx context.Context) (map[string]int, int, error) {
	log.Println("Seeding abilities reference table...")
	names, err := fetchAllNames("ability")
	if err != nil {
		return nil, 0, fmt.Errorf("failed to list abilities: %w", err)
	}

	ids := make(map[string]int, len(names))
	var mu sync.Mutex
	var touched int
	var firstErr error

	jobs := make(chan string, len(names))
	for _, n := range names {
		jobs <- n
	}
	close(jobs)

	var wg sync.WaitGroup
	for i := 0; i < movesWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for name := range jobs {
				time.Sleep(100 * time.Millisecond)
				id, err := seedOneAbility(ctx, name)
				mu.Lock()
				if err != nil {
					log.Printf("Failed to seed ability %q: %v", name, err)
					if firstErr == nil {
						firstErr = err
					}
				} else {
					ids[name] = id
					touched++
				}
				mu.Unlock()
			}
		}()
	}
	wg.Wait()

	log.Printf("Abilities reference table: %d/%d upserted.", touched, len(names))
	if firstErr != nil {
		return ids, touched, fmt.Errorf("one or more abilities failed to seed (see logs); re-run cmd/seed_moves to retry: %w", firstErr)
	}
	return ids, touched, nil
}

func seedOneAbility(ctx context.Context, name string) (int, error) {
	resp, err := httpClient.Get(fmt.Sprintf("https://pokeapi.co/api/v2/ability/%s", name))
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("unexpected status %d", resp.StatusCode)
	}
	var d pokeAPIAbilityDetail
	if err := json.NewDecoder(resp.Body).Decode(&d); err != nil {
		return 0, fmt.Errorf("decode: %w", err)
	}

	var id int
	err = database.DB.QueryRow(ctx, `
		INSERT INTO abilities (slug, name, effect)
		VALUES ($1, $2, $3)
		ON CONFLICT (slug) DO UPDATE SET name = EXCLUDED.name, effect = EXCLUDED.effect
		RETURNING id
	`, d.Name, englishName(d.Names, d.Name), englishEffect(d.EffectEntries)).Scan(&id)
	return id, err
}

// SeedSpeciesStatsAndMoves populates pokemon.{hp,attack,...}, pokemon_abilities,
// and pokemon_moves (Platinum + Scarlet/Violet only) for every Pokemon that
// does not yet have stats recorded.
//
// Resumability: pokemon.hp IS NULL is the on-disk checkpoint. A species is
// only picked up here if hp is still unset, and hp is the LAST column written
// inside that species' transaction (see seedOneSpeciesMoveset) -- so a
// species is either fully written (stats + abilities + both games' movesets)
// or, if anything failed partway, left exactly as it was and picked up again
// on the next run. There is no separate checkpoint file to go stale.
func SeedSpeciesStatsAndMoves(ctx context.Context, moveIDs, abilityIDs map[string]int) (int, error) {
	gameIDs, err := loadTargetGameIDs(ctx)
	if err != nil {
		return 0, err
	}

	rows, err := database.DB.Query(ctx, "SELECT id FROM pokemon WHERE hp IS NULL ORDER BY id")
	if err != nil {
		return 0, fmt.Errorf("failed to list pending pokemon: %w", err)
	}
	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err == nil {
			ids = append(ids, id)
		}
	}
	rows.Close()

	total, err := countPokemon(ctx)
	if err != nil {
		return 0, err
	}
	log.Printf("Species stats/abilities/moveset: %d of %d pokemon already done, %d remaining.", total-len(ids), total, len(ids))

	jobs := make(chan int, len(ids))
	for _, id := range ids {
		jobs <- id
	}
	close(jobs)

	var done int64
	var mu sync.Mutex
	var firstErr error

	var wg sync.WaitGroup
	for i := 0; i < movesWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for id := range jobs {
				time.Sleep(100 * time.Millisecond)
				if err := seedOneSpeciesMoveset(ctx, id, moveIDs, abilityIDs, gameIDs); err != nil {
					log.Printf("Failed to seed species #%d: %v (will retry on next run)", id, err)
					mu.Lock()
					if firstErr == nil {
						firstErr = err
					}
					mu.Unlock()
					continue
				}
				mu.Lock()
				done++
				mu.Unlock()
			}
		}()
	}
	wg.Wait()

	log.Printf("Species stats/abilities/moveset: %d/%d newly seeded this run.", done, len(ids))
	if firstErr != nil {
		return int(done), fmt.Errorf("one or more species failed to seed (see logs); re-run cmd/seed_moves to retry only the incomplete ones: %w", firstErr)
	}
	return int(done), nil
}

// loadTargetGameIDs resolves movesetVersionGroups' game titles against the
// games table. Fails loudly if a title is missing rather than silently
// seeding fewer games than intended.
func loadTargetGameIDs(ctx context.Context) (map[string]int, error) {
	out := make(map[string]int, len(movesetVersionGroups))
	for _, title := range movesetVersionGroups {
		var id int
		if err := database.DB.QueryRow(ctx, "SELECT id FROM games WHERE title = $1", title).Scan(&id); err != nil {
			return nil, fmt.Errorf("game %q not found (has cmd/seed run?): %w", title, err)
		}
		out[title] = id
	}
	return out, nil
}

func countPokemon(ctx context.Context) (int, error) {
	var n int
	err := database.DB.QueryRow(ctx, "SELECT COUNT(*) FROM pokemon").Scan(&n)
	return n, err
}

// seedOneSpeciesMoveset fetches one species' full PokeAPI payload and writes
// stats + ability slots + moveset (Platinum/Scarlet-Violet) inside a single
// transaction, so a mid-species failure can never leave stats set but
// abilities/moveset missing (or vice versa) -- see the SeedSpeciesStatsAndMoves
// doc comment for how that makes the whole seeder resumable.
func seedOneSpeciesMoveset(ctx context.Context, pokemonID int, moveIDs, abilityIDs, gameIDs map[string]int) error {
	resp, err := httpClient.Get(fmt.Sprintf("https://pokeapi.co/api/v2/pokemon/%d", pokemonID))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status %d", resp.StatusCode)
	}
	var sm pokeAPISpeciesMoveset
	if err := json.NewDecoder(resp.Body).Decode(&sm); err != nil {
		return fmt.Errorf("decode: %w", err)
	}

	stats, ok := parseBaseStats(sm.Stats)
	if !ok {
		return fmt.Errorf("incomplete stats payload")
	}
	abilitySlots := parseAbilitySlots(sm.Abilities)
	learn := parseMoveset(sm.Moves)

	tx, err := database.DB.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx) // no-op once Commit succeeds

	for _, a := range abilitySlots {
		abilityID, ok := abilityIDs[a.Slug]
		if !ok {
			log.Printf("warn: pokemon #%d references unknown ability %q; skipping slot", pokemonID, a.Slug)
			continue
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO pokemon_abilities (pokemon_id, ability_id, slot, is_hidden)
			VALUES ($1, $2, $3, $4)
			ON CONFLICT (pokemon_id, slot) DO UPDATE SET ability_id = EXCLUDED.ability_id, is_hidden = EXCLUDED.is_hidden
		`, pokemonID, abilityID, a.Slot, a.IsHidden); err != nil {
			return fmt.Errorf("upsert ability slot %d: %w", a.Slot, err)
		}
	}

	// Delete-then-insert scoped to only the games this seeder owns, so a retry
	// after a partial CopyFrom failure can never collide with rows the
	// previous attempt already wrote (CopyFrom has no ON CONFLICT clause).
	targetGameIDs := make([]int, 0, len(gameIDs))
	for _, gid := range gameIDs {
		targetGameIDs = append(targetGameIDs, gid)
	}
	if _, err := tx.Exec(ctx,
		`DELETE FROM pokemon_moves WHERE pokemon_id = $1 AND game_id = ANY($2)`,
		pokemonID, targetGameIDs); err != nil {
		return fmt.Errorf("clear moveset: %w", err)
	}

	type dedupeKey struct {
		moveID, gameID int
		method         string
		level          int
	}
	seen := make(map[dedupeKey]bool, len(learn))
	var copyRows [][]any
	for _, e := range learn {
		moveID, ok := moveIDs[e.MoveSlug]
		if !ok {
			log.Printf("warn: pokemon #%d references unknown move %q; skipping", pokemonID, e.MoveSlug)
			continue
		}
		gameID, ok := gameIDs[e.GameTitle]
		if !ok {
			continue
		}
		var level int
		if e.Level != nil {
			level = *e.Level
		}
		k := dedupeKey{moveID, gameID, e.Method, level}
		if seen[k] {
			continue
		}
		seen[k] = true
		var levelArg any
		if e.Level != nil {
			levelArg = *e.Level
		}
		copyRows = append(copyRows, []any{pokemonID, moveID, gameID, e.Method, levelArg})
	}
	if len(copyRows) > 0 {
		if _, err := tx.CopyFrom(ctx,
			pgx.Identifier{"pokemon_moves"},
			[]string{"pokemon_id", "move_id", "game_id", "method", "level"},
			pgx.CopyFromRows(copyRows),
		); err != nil {
			return fmt.Errorf("insert moveset: %w", err)
		}
	}

	// hp is written LAST and is the resumability checkpoint (see
	// SeedSpeciesStatsAndMoves): if the transaction fails to commit, hp stays
	// NULL and this species is retried from scratch on the next run.
	if _, err := tx.Exec(ctx, `
		UPDATE pokemon SET hp = $2, attack = $3, defense = $4, special_attack = $5, special_defense = $6, speed = $7
		WHERE id = $1
	`, pokemonID, stats.HP, stats.Attack, stats.Defense, stats.SpecialAttack, stats.SpecialDefense, stats.Speed); err != nil {
		return fmt.Errorf("update stats: %w", err)
	}

	return tx.Commit(ctx)
}

// fetchAllNames fetches the complete name list for a PokeAPI resource kind
// (e.g. "move", "ability"). It first probes for `count` with limit=1, then
// re-requests with that exact count so the whole list comes back in one
// page -- both kinds are a few hundred to ~1000 entries, comfortably one
// request, without hardcoding a limit that could go stale as PokeAPI grows.
func fetchAllNames(kind string) ([]string, error) {
	probe, err := fetchNamedList(fmt.Sprintf("https://pokeapi.co/api/v2/%s?limit=1", kind))
	if err != nil {
		return nil, err
	}
	if probe.Count == 0 {
		return nil, nil
	}
	full, err := fetchNamedList(fmt.Sprintf("https://pokeapi.co/api/v2/%s?limit=%d", kind, probe.Count))
	if err != nil {
		return nil, err
	}
	names := make([]string, 0, len(full.Results))
	for _, r := range full.Results {
		names = append(names, r.Name)
	}
	return names, nil
}

func fetchNamedList(url string) (*pokeAPINamedList, error) {
	resp, err := httpClient.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("unexpected status %d for %s", resp.StatusCode, url)
	}
	var list pokeAPINamedList
	if err := json.NewDecoder(resp.Body).Decode(&list); err != nil {
		return nil, fmt.Errorf("decode %s: %w", url, err)
	}
	return &list, nil
}
