package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"unicode/utf8"

	"github.com/casper/shinytracker/internal/database"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

// scarletVioletGameID is the only game this slice supports. Scarlet/Violet is the
// only Switch title with moveset data seeded, and it is where current VGC is played.
const scarletVioletGameID = 17

// validStats is the closed set of EV/IV keys, matching Stat.rawValue in ShinyTrackerKit.
var validStats = map[string]bool{
	"hp": true, "atk": true, "def": true, "spa": true, "spd": true, "spe": true,
}

// evSpreadValid enforces the game's own caps: 508 total, 252 per stat.
//
// Also enforced in the Swift model and the UI. Triplication is deliberate: the
// database cannot express "sum of JSONB values <= 508" cheaply, and a set that breaks
// the cap exports to a paste Showdown rejects — a silent corruption of the one output
// that has to interoperate.
func evSpreadValid(evs map[string]int) bool {
	total := 0
	for stat, value := range evs {
		if !validStats[stat] || value < 0 || value > 252 {
			return false
		}
		total += value
	}
	return total <= 508
}

func ivSpreadValid(ivs map[string]int) bool {
	for stat, value := range ivs {
		if !validStats[stat] || value < 0 || value > 31 {
			return false
		}
	}
	return true
}

// validNatures is the closed set of the game's 25 natures, lowercase to match
// Nature.rawValue in ios/ShinyTrackerKit/Sources/ShinyTrackerKit/Nature.swift
// exactly -- that enum is Codable with no custom encoder, so it puts its
// rawValue on the wire as-is. Nature is stored as free TEXT (no FK, no CHECK),
// so this is the only thing standing between the column and arbitrary user
// text. Keep in sync with Nature.swift by hand; there is no shared source.
var validNatures = map[string]bool{
	"hardy": true, "lonely": true, "brave": true, "adamant": true, "naughty": true,
	"bold": true, "docile": true, "relaxed": true, "impish": true, "lax": true,
	"timid": true, "hasty": true, "serious": true, "jolly": true, "naive": true,
	"modest": true, "mild": true, "quiet": true, "bashful": true, "rash": true,
	"calm": true, "gentle": true, "sassy": true, "careful": true, "quirky": true,
}

// validTeraTypes is the closed set of legal Tera Types. Same reasoning as
// validNatures: tera_type is free TEXT with no FK.
//
// 19 entries, not 18: Stellar was added in The Indigo Disk and is legal and
// competitively current (Terapagos has it natively; Tera Shards can grant it
// to anything). It is not one of the 18 elemental types on the type chart --
// do not "clean this up" back down to 18.
var validTeraTypes = map[string]bool{
	"Normal": true, "Fire": true, "Water": true, "Electric": true, "Grass": true,
	"Ice": true, "Fighting": true, "Poison": true, "Ground": true, "Flying": true,
	"Psychic": true, "Bug": true, "Rock": true, "Ghost": true, "Dragon": true,
	"Dark": true, "Steel": true, "Fairy": true, "Stellar": true,
}

// maxAbilitySlugLength and maxMoveSlugLength bound the two other free-text
// columns team_members writes with no FK behind them (ability_slug, moves).
// PokeAPI slugs run well under this; it exists to stop an oversized payload,
// not to fit real data tightly.
const maxAbilitySlugLength = 50
const maxMoveSlugLength = 50

func slugTooLong(s string, max int) bool {
	return utf8.RuneCountInString(s) > max
}

type TeamMemberPayload struct {
	Slot        int            `json:"slot"`
	PokemonID   int            `json:"pokemon_id"`
	Nickname    *string        `json:"nickname"`
	Nature      string         `json:"nature"`
	AbilitySlug string         `json:"ability_slug"`
	ItemSlug    *string        `json:"item_slug"`
	TeraType    *string        `json:"tera_type"`
	Level       int            `json:"level"`
	EVs         map[string]int `json:"evs"`
	IVs         map[string]int `json:"ivs"`
	Moves       []string       `json:"moves"`
}

type TeamPayload struct {
	ID      string              `json:"id"`
	Name    string              `json:"name"`
	GameID  int                 `json:"game_id"`
	Members []TeamMemberPayload `json:"members"`
}

const maxTeamNameLength = 100

// validateMembers checks everything the database cannot. Returns a user-facing message
// on failure, empty on success.
func validateMembers(members []TeamMemberPayload) string {
	if len(members) > 6 {
		return "a team holds at most six Pokemon"
	}
	slots := map[int]bool{}
	for _, m := range members {
		if m.Slot < 1 || m.Slot > 6 {
			return "slot must be between 1 and 6"
		}
		if slots[m.Slot] {
			return "two members share a slot"
		}
		slots[m.Slot] = true
		if m.PokemonID <= 0 {
			return "pokemon_id is required"
		}
		if nicknameTooLong(m.Nickname) {
			return "nickname is too long"
		}
		if !validNatures[m.Nature] {
			return "nature must be a real nature"
		}
		if slugTooLong(m.AbilitySlug, maxAbilitySlugLength) {
			return "ability_slug is too long"
		}
		if m.TeraType != nil && !validTeraTypes[*m.TeraType] {
			return "tera_type must be a real type"
		}
		if len(m.Moves) > 4 {
			return "a Pokemon knows at most four moves"
		}
		for _, mv := range m.Moves {
			if slugTooLong(mv, maxMoveSlugLength) {
				return "a move name is too long"
			}
		}
		if m.Level < 1 || m.Level > 100 {
			return "level must be between 1 and 100"
		}
		if !evSpreadValid(m.EVs) {
			return "EVs exceed the 508 total or 252 per-stat cap"
		}
		if !ivSpreadValid(m.IVs) {
			return "IVs must be between 0 and 31"
		}
	}
	return ""
}

func GetTeamsHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	teams, err := loadTeams(context.Background(), userID, "")
	if err != nil {
		http.Error(w, "Failed to load teams", http.StatusInternalServerError)
		return
	}
	writeJSON(w, teams)
}

func GetTeamHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	teams, err := loadTeams(context.Background(), userID, chi.URLParam(r, "id"))
	if err != nil {
		http.Error(w, "Failed to load team", http.StatusInternalServerError)
		return
	}
	if len(teams) == 0 {
		http.Error(w, "Team not found", http.StatusNotFound)
		return
	}
	writeJSON(w, teams[0])
}

// loadTeams returns the caller's teams with members attached. A blank teamID means all.
// Scoped by user_id in the WHERE clause, never by a path parameter.
func loadTeams(ctx context.Context, userID, teamID string) ([]TeamPayload, error) {
	query := `SELECT id, name, game_id FROM teams WHERE user_id = $1`
	args := []any{userID}
	if teamID != "" {
		query += ` AND id = $2`
		args = append(args, teamID)
	}
	query += ` ORDER BY updated_at DESC`

	rows, err := database.DB.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	teams := []TeamPayload{}
	ids := []string{}
	for rows.Next() {
		var t TeamPayload
		if err := rows.Scan(&t.ID, &t.Name, &t.GameID); err != nil {
			return nil, err
		}
		t.Members = []TeamMemberPayload{}
		teams = append(teams, t)
		ids = append(ids, t.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(teams) == 0 {
		return teams, nil
	}

	memberRows, err := database.DB.Query(ctx,
		`SELECT team_id, slot, pokemon_id, nickname, nature, ability_slug, item_slug,
		        tera_type, level, evs, ivs, moves
		   FROM team_members WHERE team_id = ANY($1::uuid[]) ORDER BY team_id, slot`, ids)
	if err != nil {
		return nil, err
	}
	defer memberRows.Close()

	byTeam := map[string][]TeamMemberPayload{}
	for memberRows.Next() {
		var teamID string
		var m TeamMemberPayload
		if err := memberRows.Scan(&teamID, &m.Slot, &m.PokemonID, &m.Nickname, &m.Nature,
			&m.AbilitySlug, &m.ItemSlug, &m.TeraType, &m.Level, &m.EVs, &m.IVs, &m.Moves); err != nil {
			return nil, err
		}
		byTeam[teamID] = append(byTeam[teamID], m)
	}
	if err := memberRows.Err(); err != nil {
		return nil, err
	}
	for i := range teams {
		if members, ok := byTeam[teams[i].ID]; ok {
			teams[i].Members = members
		}
	}
	return teams, nil
}

func CreateTeamHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	var req TeamPayload
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.Name == "" || len([]rune(req.Name)) > maxTeamNameLength {
		http.Error(w, "name is required and must be 100 characters or fewer", http.StatusBadRequest)
		return
	}
	if msg := validateMembers(req.Members); msg != "" {
		http.Error(w, msg, http.StatusBadRequest)
		return
	}

	tx, err := database.DB.Begin(context.Background())
	if err != nil {
		http.Error(w, "Failed to start transaction", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(context.Background())

	var teamID string
	if err := tx.QueryRow(context.Background(),
		`INSERT INTO teams (user_id, name, game_id) VALUES ($1, $2, $3) RETURNING id`,
		userID, req.Name, scarletVioletGameID).Scan(&teamID); err != nil {
		http.Error(w, "Failed to create team", http.StatusInternalServerError)
		return
	}
	if err := insertMembers(context.Background(), tx, teamID, req.Members); err != nil {
		http.Error(w, "Failed to save team members", http.StatusInternalServerError)
		return
	}
	if err := tx.Commit(context.Background()); err != nil {
		http.Error(w, "Failed to commit transaction", http.StatusInternalServerError)
		return
	}

	teams, err := loadTeams(context.Background(), userID, teamID)
	if err != nil || len(teams) == 0 {
		http.Error(w, "Failed to reload team", http.StatusInternalServerError)
		return
	}
	writeJSON(w, teams[0])
}

func UpdateTeamHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	teamID := chi.URLParam(r, "id")

	// Members is a pointer to a slice, not a plain slice: "key absent" (leave the
	// roster alone) and "key present but []" (clear it) have to be distinguishable
	// on the wire, and a nil slice and an empty slice decode identically otherwise.
	var req struct {
		Name    *string              `json:"name"`
		Members *[]TeamMemberPayload `json:"members"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.Name != nil && (*req.Name == "" || len([]rune(*req.Name)) > maxTeamNameLength) {
		http.Error(w, "name must be 1 to 100 characters", http.StatusBadRequest)
		return
	}
	if req.Members != nil {
		if msg := validateMembers(*req.Members); msg != "" {
			http.Error(w, msg, http.StatusBadRequest)
			return
		}
	}

	tx, err := database.DB.Begin(context.Background())
	if err != nil {
		http.Error(w, "Failed to start transaction", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(context.Background())

	// Ownership and existence in one statement, scoped by user_id.
	var found string
	err = tx.QueryRow(context.Background(),
		`UPDATE teams SET name = COALESCE($1, name), updated_at = now()
		  WHERE id = $2 AND user_id = $3 RETURNING id`,
		req.Name, teamID, userID).Scan(&found)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			http.Error(w, "Team not found", http.StatusNotFound)
			return
		}
		http.Error(w, "Failed to update team", http.StatusInternalServerError)
		return
	}

	// Members are replaced wholesale, but only when the caller sent a members key at
	// all. An absent members field means "leave the roster alone" (e.g. a bare rename);
	// only an explicit "members": [...] — including "[]" to clear it — touches rows.
	// A team is edited as a unit, six slots are small, and per-slot patching invents
	// the merge problem the encounter-delta work already showed is expensive to get right.
	if req.Members != nil {
		if _, err := tx.Exec(context.Background(),
			`DELETE FROM team_members WHERE team_id = $1`, teamID); err != nil {
			http.Error(w, "Failed to replace members", http.StatusInternalServerError)
			return
		}
		if err := insertMembers(context.Background(), tx, teamID, *req.Members); err != nil {
			http.Error(w, "Failed to save team members", http.StatusInternalServerError)
			return
		}
	}
	if err := tx.Commit(context.Background()); err != nil {
		http.Error(w, "Failed to commit transaction", http.StatusInternalServerError)
		return
	}

	teams, err := loadTeams(context.Background(), userID, teamID)
	if err != nil || len(teams) == 0 {
		http.Error(w, "Failed to reload team", http.StatusInternalServerError)
		return
	}
	writeJSON(w, teams[0])
}

func insertMembers(ctx context.Context, tx pgx.Tx, teamID string, members []TeamMemberPayload) error {
	for _, m := range members {
		evs := m.EVs
		if evs == nil {
			evs = map[string]int{}
		}
		ivs := m.IVs
		if ivs == nil {
			ivs = map[string]int{}
		}
		moves := m.Moves
		if moves == nil {
			moves = []string{}
		}
		if _, err := tx.Exec(ctx,
			`INSERT INTO team_members
			   (team_id, slot, pokemon_id, nickname, nature, ability_slug, item_slug,
			    tera_type, level, evs, ivs, moves)
			 VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
			teamID, m.Slot, m.PokemonID, m.Nickname, m.Nature, m.AbilitySlug,
			m.ItemSlug, m.TeraType, m.Level, evs, ivs, moves); err != nil {
			return err
		}
	}
	return nil
}

func DeleteTeamHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	tag, err := database.DB.Exec(context.Background(),
		`DELETE FROM teams WHERE id = $1 AND user_id = $2`, chi.URLParam(r, "id"), userID)
	if err != nil {
		http.Error(w, "Failed to delete team", http.StatusInternalServerError)
		return
	}
	if tag.RowsAffected() == 0 {
		http.Error(w, "Team not found", http.StatusNotFound)
		return
	}
	writeJSON(w, map[string]string{"message": "Team deleted successfully"})
}

// GetItemsHandler serves the static held-item list. Public and unauthenticated, like
// /api/games and /api/methods.
func GetItemsHandler(w http.ResponseWriter, r *http.Request) {
	rows, err := database.DB.Query(context.Background(),
		`SELECT slug, name, COALESCE(sprite_url,''), COALESCE(description,'')
		   FROM items ORDER BY name`)
	if err != nil {
		http.Error(w, "Failed to load items", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type item struct {
		Slug        string `json:"slug"`
		Name        string `json:"name"`
		SpriteURL   string `json:"sprite_url"`
		Description string `json:"description"`
	}
	items := []item{}
	for rows.Next() {
		var i item
		if err := rows.Scan(&i.Slug, &i.Name, &i.SpriteURL, &i.Description); err != nil {
			continue
		}
		items = append(items, i)
	}
	writeJSON(w, items)
}
