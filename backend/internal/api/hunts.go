package api

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"time"
	"unicode/utf8"

	"github.com/casper/shinytracker/internal/calc"
	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/models"
	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5/pgconn"
)

// maxNicknameLength bounds the user_hunts.nickname free-text field at the
// write boundary, same reasoning as custom_method_name (also unbounded TEXT
// in the DB): plain user input, no server-side use beyond display.
//
// Counted in runes, not bytes: this is a character limit shown to a user, and
// len() would silently cut a Japanese or emoji nickname off at a third of it.
const maxNicknameLength = 100

// nicknameTooLong reports whether a supplied nickname exceeds the cap. An absent
// nickname is never too long -- omitting the field is how a caller says "leave it".
func nicknameTooLong(nickname *string) bool {
	return nickname != nil && utf8.RuneCountInString(*nickname) > maxNicknameLength
}

// loadPhasesForHunts fetches all phases for the given hunt IDs and groups them by hunt ID.
func loadPhasesForHunts(ctx context.Context, huntIDs []string) (map[string][]models.HuntPhase, error) {
	result := make(map[string][]models.HuntPhase)
	if len(huntIDs) == 0 {
		return result, nil
	}

	rows, err := database.DB.Query(ctx,
		`SELECT hp.id, hp.hunt_id, hp.pokemon_id, p.name, COALESCE(p.sprite_url, ''), COALESCE(p.shiny_sprite_url, ''), hp.encounter_count_at_phase, hp.created_at
		 FROM hunt_phases hp
		 JOIN pokemon p ON hp.pokemon_id = p.id
		 WHERE hp.hunt_id = ANY($1::uuid[])
		 ORDER BY hp.hunt_id, hp.created_at ASC`, huntIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var ph models.HuntPhase
		if err := rows.Scan(&ph.ID, &ph.HuntID, &ph.PokemonID, &ph.PokemonName, &ph.SpriteURL, &ph.ShinySpriteURL, &ph.EncounterCountAtPhase, &ph.CreatedAt); err != nil {
			continue
		}
		result[ph.HuntID] = append(result[ph.HuntID], ph)
	}
	return result, rows.Err()
}

// loadHuntsForUser fetches every hunt (with join details and phases) owned by
// one user. Shared by GetHuntsHandler and ExportHandler so the export can't
// drift from what the hunts list actually returns.
// huntDetailQuery is the SELECT/FROM/JOIN shared by every read of a hunt with its
// joined method, game and shiny-charm state. Callers append their own WHERE (and
// ORDER BY). Keeping the column list in one place is the point: the hunts list and
// the single-hunt reload after a phase log must decode to an identical shape, and
// when these were two copy-pasted queries they were free to drift apart silently.
const huntDetailQuery = `
	SELECT h.id, h.user_id, h.pokemon_id, h.game_id, h.hunt_method_id, h.encounter_count, h.phase_count, h.status, h.acquisition_type, h.hunt_parameters, h.created_at, h.updated_at,
	       p.name AS pokemon_name, COALESCE(p.sprite_url, '') AS sprite_url, COALESCE(p.shiny_sprite_url, '') AS shiny_sprite_url, e.method_name, h.custom_method_name, g.title AS game_title,
	       h.total_time_seconds, e.base_rolls, e.charm_rolls, e.avg_time_seconds, g.base_odds, ug.has_shiny_charm,
	       COALESCE(e.formula_type, 'static') AS formula_type, h.nickname
	  FROM user_hunts h
	  JOIN pokemon p ON h.pokemon_id = p.id
	  LEFT JOIN hunt_methods e ON h.hunt_method_id = e.id
	  LEFT JOIN games g ON h.game_id = g.id
	  LEFT JOIN user_games ug ON ug.game_id = g.id AND ug.user_id = h.user_id`

// rowScanner is satisfied by both pgx.Rows and pgx.Row, so scanHuntDetail works for
// the list query and the single-row reload alike.
type rowScanner interface {
	Scan(dest ...any) error
}

// scanHuntDetail decodes one row of huntDetailQuery. The order here mirrors that
// query's column list exactly — change one and you must change the other.
func scanHuntDetail(row rowScanner, h *models.UserHuntDetail) error {
	return row.Scan(
		&h.ID, &h.UserID, &h.PokemonID, &h.GameID, &h.HuntMethodID, &h.EncounterCount, &h.PhaseCount, &h.Status, &h.AcquisitionType, &h.HuntParameters, &h.CreatedAt, &h.UpdatedAt,
		&h.PokemonName, &h.SpriteURL, &h.ShinySpriteURL, &h.MethodName, &h.CustomMethodName, &h.GameTitle,
		&h.TotalTimeSeconds, &h.BaseRolls, &h.CharmRolls, &h.AvgTimeSeconds, &h.BaseOdds, &h.HasShinyCharm, &h.FormulaType, &h.Nickname,
	)
}

func loadHuntsForUser(ctx context.Context, userID string) ([]models.UserHuntDetail, error) {
	rows, err := database.DB.Query(ctx,
		huntDetailQuery+`
		 WHERE h.user_id = $1
		 ORDER BY h.created_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	hunts := []models.UserHuntDetail{}
	huntIDs := []string{}
	for rows.Next() {
		var h models.UserHuntDetail
		if err := scanHuntDetail(rows, &h); err != nil {
			continue
		}
		h.Phases = []models.HuntPhase{}
		hunts = append(hunts, h)
		huntIDs = append(huntIDs, h.ID)
	}

	phasesByHunt, err := loadPhasesForHunts(ctx, huntIDs)
	if err == nil {
		for i, h := range hunts {
			if phases, ok := phasesByHunt[h.ID]; ok {
				hunts[i].Phases = phases
			}
		}
	}

	return hunts, rows.Err()
}

func GetHuntsHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	hunts, err := loadHuntsForUser(context.Background(), userID)
	if err != nil {
		log.Printf("GetHunts error: %v", err)
		http.Error(w, "Failed to fetch hunts", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunts)
}

// DeleteHuntHandler deletes a hunt owned by the calling user. Scoped by
// user_id as well as id so one user cannot delete another's hunt.
func DeleteHuntHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	huntID := chi.URLParam(r, "id")

	tag, err := database.DB.Exec(context.Background(),
		`DELETE FROM user_hunts WHERE id = $1 AND user_id = $2`, huntID, userID)
	if err != nil {
		// A malformed id is client error, not server error: Postgres rejects it
		// with 22P02 (invalid_text_representation) before matching any row.
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "22P02" {
			http.Error(w, "Hunt not found", http.StatusNotFound)
			return
		}
		http.Error(w, "Failed to delete hunt", http.StatusInternalServerError)
		return
	}
	if tag.RowsAffected() == 0 {
		http.Error(w, "Hunt not found", http.StatusNotFound)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Hunt deleted successfully"})
}

func CreateHuntHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	var req struct {
		HuntMethodID     int             `json:"hunt_method_id"`
		PokemonID        int             `json:"pokemon_id"`
		GameID           int             `json:"game_id"`
		MethodName       string          `json:"method_name"`
		CustomMethodName string          `json:"custom_method_name"`
		HuntParameters   json.RawMessage `json:"hunt_parameters"`
		Nickname         *string         `json:"nickname"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	hasCurated := req.HuntMethodID > 0
	hasSynthetic := req.HuntMethodID < 0
	hasCustom := req.CustomMethodName != ""

	if (hasCurated && hasCustom) || (hasCurated && hasSynthetic) || (hasCustom && hasSynthetic) {
		http.Error(w, "Provide hunt_method_id or custom_method_name, not both", http.StatusBadRequest)
		return
	}
	if nicknameTooLong(req.Nickname) {
		http.Error(w, "nickname is too long", http.StatusBadRequest)
		return
	}

	var pokemonID int
	var gameID *int
	var huntMethodID *int
	var customMethodName *string
	var huntParameters json.RawMessage

	if len(req.HuntParameters) > 0 {
		huntParameters = req.HuntParameters
	} else {
		huntParameters = json.RawMessage(`{}`)
	}

	if hasCustom {
		if req.PokemonID == 0 {
			http.Error(w, "pokemon_id required for custom hunt methods", http.StatusBadRequest)
			return
		}
		pokemonID = req.PokemonID
		huntMethodID = nil
		gameID = nil
		customMethodName = &req.CustomMethodName
	} else if hasSynthetic {
		// No longer synthetic logic since rules handle it, but fallback just in case
		http.Error(w, "Synthetic methods should no longer be passed as negative IDs", http.StatusBadRequest)
		return
	} else if hasCurated {
		// Validating pokemonID and GameID are provided
		if req.PokemonID == 0 || req.GameID == 0 {
			http.Error(w, "pokemon_id and game_id required", http.StatusBadRequest)
			return
		}
		pokemonID = req.PokemonID
		gameID = &req.GameID
		huntMethodID = &req.HuntMethodID
		customMethodName = nil
	} else {
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	var hunt models.UserHunt
	err := database.DB.QueryRow(context.Background(),
		`INSERT INTO user_hunts (user_id, pokemon_id, game_id, hunt_method_id, custom_method_name, acquisition_type, hunt_parameters, nickname)
		 VALUES ($1, $2, $3, $4, $5, 'HUNTED', $6, NULLIF($7, ''))
		 RETURNING id, user_id, pokemon_id, game_id, hunt_method_id, encounter_count, phase_count, status, acquisition_type, hunt_parameters, created_at, updated_at, nickname`,
		userID, pokemonID, gameID, huntMethodID, customMethodName, huntParameters, req.Nickname).
		Scan(&hunt.ID, &hunt.UserID, &hunt.PokemonID, &hunt.GameID, &hunt.HuntMethodID, &hunt.EncounterCount, &hunt.PhaseCount, &hunt.Status, &hunt.AcquisitionType, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt, &hunt.Nickname)

	if err != nil {
		log.Printf("CreateHunt error: %v", err)
		http.Error(w, "Failed to create hunt", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunt)
}

func UpdateHuntHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	huntID := chi.URLParam(r, "id")

	var req struct {
		EncounterCount int             `json:"encounter_count"`
		Status         string          `json:"status"`
		HuntParameters json.RawMessage `json:"hunt_parameters"`
		// Pointer so "absent" (pre-D1 web frontend, keep deriving server-side)
		// is distinguishable from "zero". See calc.DecideTotalTime.
		TotalTimeSeconds *int `json:"total_time_seconds"`
		// Pointer so an omitted nickname leaves the stored value untouched,
		// same optional-field convention as HuntParameters below. JSON null
		// decodes to nil too and so also means "leave it alone"; sending ""
		// is the way to clear one, which the UPDATE folds back to NULL so the
		// column never holds an empty string.
		Nickname *string `json:"nickname"`
		// The "−" control's explicit permission to lower the count. Absent means
		// no: a sync or a replayed offline burst can only ever raise it. See
		// calc.DecideEncounterCount.
		AllowDecrease bool `json:"allow_decrease"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	// Validate client-supplied fields before they reach the UPDATE. status drives
	// the hunt lifecycle (and the active|completed filters across the app), so an
	// arbitrary value would corrupt state; a negative encounter_count would break
	// odds/ETA math. The DB columns have no CHECK constraints, so guard here.
	if req.Status != "active" && req.Status != "completed" {
		http.Error(w, "status must be 'active' or 'completed'", http.StatusBadRequest)
		return
	}
	if req.EncounterCount < 0 {
		http.Error(w, "encounter_count must be >= 0", http.StatusBadRequest)
		return
	}
	if nicknameTooLong(req.Nickname) {
		http.Error(w, "nickname is too long", http.StatusBadRequest)
		return
	}

	var prevUpdatedAt time.Time
	var currentTotalTime int
	var clientOwnsTime bool
	var huntParameters json.RawMessage
	var storedCount int
	err := database.DB.QueryRow(context.Background(),
		`SELECT updated_at, total_time_seconds, client_owns_time, hunt_parameters, encounter_count FROM user_hunts WHERE id = $1 AND user_id = $2`,
		huntID, userID).Scan(&prevUpdatedAt, &currentTotalTime, &clientOwnsTime, &huntParameters, &storedCount)
	if err != nil {
		http.Error(w, "Hunt not found", http.StatusNotFound)
		return
	}

	// D1 (docs/handoff/DECISIONS.md): total_time_seconds is client-authoritative
	// once a client starts sending it — see calc.DecideTotalTime for the full
	// derive/store/latch decision.
	newTotalTime, newClientOwnsTime, err := calc.DecideTotalTime(currentTotalTime, clientOwnsTime, req.TotalTimeSeconds, time.Since(prevUpdatedAt))
	if err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	newEncounterCount := calc.DecideEncounterCount(storedCount, req.EncounterCount, req.AllowDecrease)
	if req.TotalTimeSeconds != nil && *req.TotalTimeSeconds < currentTotalTime {
		log.Printf("UpdateHunt: clamping total_time_seconds for hunt %s (submitted %d < stored %d), keeping stored", huntID, *req.TotalTimeSeconds, currentTotalTime)
	}

	if len(req.HuntParameters) > 0 {
		huntParameters = req.HuntParameters
	}

	var hunt models.UserHunt
	err = database.DB.QueryRow(context.Background(),
		`UPDATE user_hunts
		 SET encounter_count = $1, status = $2, updated_at = CURRENT_TIMESTAMP, total_time_seconds = $3, client_owns_time = $4, hunt_parameters = $5, nickname = NULLIF(COALESCE($6, nickname), '')
		 WHERE id = $7 AND user_id = $8
		 RETURNING id, user_id, pokemon_id, hunt_method_id, encounter_count, phase_count, status, acquisition_type, hunt_parameters, created_at, updated_at, nickname`,
		newEncounterCount, req.Status, newTotalTime, newClientOwnsTime, huntParameters, req.Nickname, huntID, userID).
		Scan(&hunt.ID, &hunt.UserID, &hunt.PokemonID, &hunt.HuntMethodID, &hunt.EncounterCount, &hunt.PhaseCount, &hunt.Status, &hunt.AcquisitionType, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt, &hunt.Nickname)

	if err != nil {
		http.Error(w, "Failed to update hunt", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunt)
}

func LogPhaseHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	huntID := chi.URLParam(r, "id")

	var req struct {
		PokemonID int `json:"pokemon_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.PokemonID == 0 {
		http.Error(w, "pokemon_id required", http.StatusBadRequest)
		return
	}

	// Verify hunt ownership, active status, and capture current encounter count.
	// parentGameID is nullable (custom-method hunts have no game).
	var currentCount int
	var huntStatus string
	var parentGameID *int
	err := database.DB.QueryRow(context.Background(),
		`SELECT encounter_count, status, game_id FROM user_hunts WHERE id = $1 AND user_id = $2`,
		huntID, userID).Scan(&currentCount, &huntStatus, &parentGameID)
	if err != nil {
		http.Error(w, "Hunt not found", http.StatusNotFound)
		return
	}
	if huntStatus != "active" {
		http.Error(w, "Cannot log phase on a completed hunt", http.StatusBadRequest)
		return
	}

	tx, err := database.DB.Begin(context.Background())
	if err != nil {
		http.Error(w, "Failed to start transaction", http.StatusInternalServerError)
		return
	}
	defer tx.Rollback(context.Background())

	// Insert phase record.
	if _, err := tx.Exec(context.Background(),
		`INSERT INTO hunt_phases (hunt_id, pokemon_id, encounter_count_at_phase) VALUES ($1, $2, $3)`,
		huntID, req.PokemonID, currentCount); err != nil {
		http.Error(w, "Failed to log phase", http.StatusInternalServerError)
		return
	}

	// Reset encounter count, increment phase count. Re-assert user_id inside the
	// transaction (not just the pre-tx ownership SELECT) so the write can never
	// touch a row the caller doesn't own — the API layer is the only isolation
	// (the backend connects with a BYPASSRLS role).
	if _, err := tx.Exec(context.Background(),
		`UPDATE user_hunts SET encounter_count = 0, phase_count = phase_count + 1, updated_at = CURRENT_TIMESTAMP WHERE id = $1 AND user_id = $2`,
		huntID, userID); err != nil {
		http.Error(w, "Failed to update hunt", http.StatusInternalServerError)
		return
	}

	// Add phase pokemon to collection as its own completed entry. It carries the
	// parent hunt's game, encounter_count 0 (a phase appeared once, mid-hunt), and
	// the PHASE acquisition type so it is distinguishable from a deliberate hunt.
	if _, err := tx.Exec(context.Background(),
		`INSERT INTO user_hunts (user_id, pokemon_id, game_id, hunt_method_id, acquisition_type, encounter_count, status, hunt_parameters)
		 VALUES ($1, $2, $3, NULL, 'PHASE', 0, 'completed', '{}')`,
		userID, req.PokemonID, parentGameID); err != nil {
		http.Error(w, "Failed to add phase pokemon to collection", http.StatusInternalServerError)
		return
	}

	if err := tx.Commit(context.Background()); err != nil {
		http.Error(w, "Failed to commit transaction", http.StatusInternalServerError)
		return
	}

	// Load full hunt detail with phases for response. Same query and scan as the
	// hunts list — see huntDetailQuery — so the two can never return different shapes.
	var hunt models.UserHuntDetail
	row := database.DB.QueryRow(context.Background(),
		huntDetailQuery+`
		 WHERE h.id = $1 AND h.user_id = $2`,
		huntID, userID)
	if err := scanHuntDetail(row, &hunt); err != nil {
		log.Printf("LogPhase load err: %v", err)
		http.Error(w, "Failed to load updated hunt", http.StatusInternalServerError)
		return
	}

	phasesByHunt, _ := loadPhasesForHunts(context.Background(), []string{huntID})
	if phases, ok := phasesByHunt[huntID]; ok {
		hunt.Phases = phases
	} else {
		hunt.Phases = []models.HuntPhase{}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunt)
}

func ManualCatchHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	var req struct {
		PokemonID int `json:"pokemon_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	var hunt models.UserHunt
	err := database.DB.QueryRow(context.Background(),
		`INSERT INTO user_hunts (user_id, pokemon_id, hunt_method_id, acquisition_type, encounter_count, status, hunt_parameters)
		 VALUES ($1, $2, NULL, 'MANUAL_OVERRIDE', 1, 'completed', '{"manual": true}')
		 RETURNING id, user_id, pokemon_id, hunt_method_id, encounter_count, phase_count, status, acquisition_type, hunt_parameters, created_at, updated_at`,
		userID, req.PokemonID).
		Scan(&hunt.ID, &hunt.UserID, &hunt.PokemonID, &hunt.HuntMethodID, &hunt.EncounterCount, &hunt.PhaseCount, &hunt.Status, &hunt.AcquisitionType, &hunt.HuntParameters, &hunt.CreatedAt, &hunt.UpdatedAt)

	if err != nil {
		http.Error(w, "Failed to create manual catch", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(hunt)
}

func RemoveManualCatchHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	pokemonID := chi.URLParam(r, "pokemonId")

	_, err := database.DB.Exec(context.Background(),
		`DELETE FROM user_hunts
		 WHERE user_id = $1 AND status = 'completed' AND pokemon_id = $2 AND acquisition_type = 'MANUAL_OVERRIDE'`,
		userID, pokemonID)

	if err != nil {
		http.Error(w, "Failed to remove catch", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "Catch removed successfully"})
}

// GameStatBreakdown is one game's slice of a user's stats. GameID/GameTitle
// are nullable because custom-method hunts have no game.
type GameStatBreakdown struct {
	GameID          *int    `json:"game_id"`
	GameTitle       *string `json:"game_title"`
	HuntCount       int     `json:"hunt_count"`
	TotalEncounters int     `json:"total_encounters"`
}

// MethodStatBreakdown is one method's slice of a user's stats. MethodID is
// nullable for custom-method hunts; MethodName falls back to the custom name.
type MethodStatBreakdown struct {
	MethodID        *int   `json:"method_id"`
	MethodName      string `json:"method_name"`
	HuntCount       int    `json:"hunt_count"`
	TotalEncounters int    `json:"total_encounters"`
}

type UserStatsResponse struct {
	TotalHunts       int                   `json:"total_hunts"`
	CompletedHunts   int                   `json:"completed_hunts"`
	ActiveHunts      int                   `json:"active_hunts"`
	TotalEncounters  int                   `json:"total_encounters"`
	TotalPhases      int                   `json:"total_phases"`
	TotalTimeSeconds int                   `json:"total_time_seconds"`
	ByGame           []GameStatBreakdown   `json:"by_game"`
	ByMethod         []MethodStatBreakdown `json:"by_method"`
}

// GetStatsHandler returns aggregate stats for the calling user, computed
// server-side as SQL group-bys over user_hunts.
func GetStatsHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	ctx := context.Background()

	resp := UserStatsResponse{ByGame: []GameStatBreakdown{}, ByMethod: []MethodStatBreakdown{}}
	err := database.DB.QueryRow(ctx,
		`SELECT COUNT(*), COUNT(*) FILTER (WHERE status = 'completed'), COUNT(*) FILTER (WHERE status = 'active'),
		        COALESCE(SUM(encounter_count), 0), COALESCE(SUM(phase_count), 0), COALESCE(SUM(total_time_seconds), 0)
		 FROM user_hunts WHERE user_id = $1`, userID).
		Scan(&resp.TotalHunts, &resp.CompletedHunts, &resp.ActiveHunts, &resp.TotalEncounters, &resp.TotalPhases, &resp.TotalTimeSeconds)
	if err != nil {
		http.Error(w, "Failed to compute stats", http.StatusInternalServerError)
		return
	}

	gameRows, err := database.DB.Query(ctx,
		`SELECT h.game_id, g.title, COUNT(*), COALESCE(SUM(h.encounter_count), 0)
		 FROM user_hunts h
		 LEFT JOIN games g ON g.id = h.game_id
		 WHERE h.user_id = $1
		 GROUP BY h.game_id, g.title
		 ORDER BY COUNT(*) DESC`, userID)
	if err != nil {
		http.Error(w, "Failed to compute game stats", http.StatusInternalServerError)
		return
	}
	defer gameRows.Close()
	for gameRows.Next() {
		var gs GameStatBreakdown
		if err := gameRows.Scan(&gs.GameID, &gs.GameTitle, &gs.HuntCount, &gs.TotalEncounters); err != nil {
			continue
		}
		resp.ByGame = append(resp.ByGame, gs)
	}
	if err := gameRows.Err(); err != nil {
		http.Error(w, "Failed to compute game stats", http.StatusInternalServerError)
		return
	}

	methodRows, err := database.DB.Query(ctx,
		`SELECT h.hunt_method_id, COALESCE(hm.method_name, h.custom_method_name, 'Unknown'), COUNT(*), COALESCE(SUM(h.encounter_count), 0)
		 FROM user_hunts h
		 LEFT JOIN hunt_methods hm ON hm.id = h.hunt_method_id
		 WHERE h.user_id = $1
		 GROUP BY h.hunt_method_id, hm.method_name, h.custom_method_name
		 ORDER BY COUNT(*) DESC`, userID)
	if err != nil {
		http.Error(w, "Failed to compute method stats", http.StatusInternalServerError)
		return
	}
	defer methodRows.Close()
	for methodRows.Next() {
		var ms MethodStatBreakdown
		if err := methodRows.Scan(&ms.MethodID, &ms.MethodName, &ms.HuntCount, &ms.TotalEncounters); err != nil {
			continue
		}
		resp.ByMethod = append(resp.ByMethod, ms)
	}
	if err := methodRows.Err(); err != nil {
		http.Error(w, "Failed to compute method stats", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// UserExport is everything a user owns, for the GDPR-style data export.
type UserExport struct {
	Profile   any                     `json:"profile"`
	UserGames []models.UserGame       `json:"user_games"`
	Hunts     []models.UserHuntDetail `json:"hunts"`
}

// ExportHandler returns the calling user's profile, user_games, and hunts
// (with phases) as one JSON blob. Never touches other users' rows or global
// reference tables.
func ExportHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	ctx := context.Background()

	var profile struct {
		ID        string    `json:"id"`
		Username  string    `json:"username"`
		IsAdmin   bool      `json:"is_admin"`
		CreatedAt time.Time `json:"created_at"`
	}
	if err := database.DB.QueryRow(ctx,
		`SELECT id, username, is_admin, created_at FROM profiles WHERE id = $1`, userID).
		Scan(&profile.ID, &profile.Username, &profile.IsAdmin, &profile.CreatedAt); err != nil {
		http.Error(w, "Failed to load profile", http.StatusInternalServerError)
		return
	}

	gameRows, err := database.DB.Query(ctx,
		"SELECT game_id, has_shiny_charm FROM user_games WHERE user_id = $1", userID)
	if err != nil {
		http.Error(w, "Failed to load user games", http.StatusInternalServerError)
		return
	}
	defer gameRows.Close()
	userGames := []models.UserGame{}
	for gameRows.Next() {
		var ug models.UserGame
		ug.UserID = userID
		if err := gameRows.Scan(&ug.GameID, &ug.HasShinyCharm); err != nil {
			continue
		}
		userGames = append(userGames, ug)
	}
	// An export that silently drops rows is worse than one that fails loudly.
	if err := gameRows.Err(); err != nil {
		http.Error(w, "Failed to load user games", http.StatusInternalServerError)
		return
	}

	hunts, err := loadHuntsForUser(ctx, userID)
	if err != nil {
		http.Error(w, "Failed to load hunts", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(UserExport{Profile: profile, UserGames: userGames, Hunts: hunts})
}
