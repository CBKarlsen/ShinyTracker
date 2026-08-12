package api

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/models"
	"github.com/go-chi/chi/v5"
)

// ─────────────────────────────────────────────────────────────────────────
// Reference: the seeded route timeline
// ─────────────────────────────────────────────────────────────────────────

// loadTimelineForGame loads the full seeded Nuzlocke timeline for one game and
// version, in order, with each location's encounter pool and each boss's squad
// and movesets attached. Pure reference data — never scoped by user.
//
// version is required, not optional: games.id 5 covers Diamond, Pearl AND
// Platinum, whose routes and trainers genuinely differ (Fantina is the third
// gym in Platinum and the fifth in D/P), so a timeline without one would be
// three games' data interleaved by sort_order.
func loadTimelineForGame(ctx context.Context, gameID int, version string) ([]models.NuzlockeTimelineEntry, error) {
	rows, err := database.DB.Query(ctx,
		`SELECT id, slug, kind, name, sort_order, place, boss_title, level_cap
		 FROM nuzlocke_timeline_entries WHERE game_id = $1 AND version = $2
		 ORDER BY sort_order ASC`, gameID, version)
	if err != nil {
		return nil, err
	}
	entries := []models.NuzlockeTimelineEntry{}
	entryIdx := make(map[int]int, 8)
	for rows.Next() {
		var e models.NuzlockeTimelineEntry
		if err := rows.Scan(&e.ID, &e.Slug, &e.Kind, &e.Name, &e.SortOrder, &e.Place, &e.BossTitle, &e.LevelCap); err != nil {
			rows.Close()
			return nil, err
		}
		entryIdx[e.ID] = len(entries)
		entries = append(entries, e)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(entries) == 0 {
		return entries, nil
	}

	poolRows, err := database.DB.Query(ctx,
		`SELECT ep.timeline_entry_id, ep.pokemon_id, p.name, COALESCE(p.sprite_url, '')
		 FROM nuzlocke_encounter_pool ep
		 JOIN pokemon p ON p.id = ep.pokemon_id
		 JOIN nuzlocke_timeline_entries te ON te.id = ep.timeline_entry_id
		 WHERE te.game_id = $1 AND te.version = $2
		 ORDER BY ep.timeline_entry_id, ep.sort_order`, gameID, version)
	if err != nil {
		return nil, err
	}
	defer poolRows.Close()
	for poolRows.Next() {
		var entryID int
		var opt models.NuzlockeEncounterOption
		if err := poolRows.Scan(&entryID, &opt.PokemonID, &opt.PokemonName, &opt.SpriteURL); err != nil {
			poolRows.Close()
			return nil, err
		}
		idx := entryIdx[entryID]
		entries[idx].Encounters = append(entries[idx].Encounters, opt)
	}
	if err := poolRows.Err(); err != nil {
		return nil, err
	}

	squadRows, err := database.DB.Query(ctx,
		`SELECT bp.id, bp.timeline_entry_id, bp.pokemon_id, p.name, COALESCE(p.sprite_url, ''), bp.level, bp.ability
		 FROM nuzlocke_boss_pokemon bp
		 JOIN pokemon p ON p.id = bp.pokemon_id
		 JOIN nuzlocke_timeline_entries te ON te.id = bp.timeline_entry_id
		 WHERE te.game_id = $1 AND te.version = $2
		 ORDER BY bp.timeline_entry_id, bp.sort_order`, gameID, version)
	if err != nil {
		return nil, err
	}
	defer squadRows.Close()
	type squadMember struct {
		bossPokemonID int
		entryID       int
		mon           models.NuzlockeBossMon
	}
	var squadMembers []squadMember
	for squadRows.Next() {
		var sm squadMember
		if err := squadRows.Scan(&sm.bossPokemonID, &sm.entryID, &sm.mon.PokemonID, &sm.mon.PokemonName, &sm.mon.SpriteURL, &sm.mon.Level, &sm.mon.Ability); err != nil {
			squadRows.Close()
			return nil, err
		}
		squadMembers = append(squadMembers, sm)
	}
	if err := squadRows.Err(); err != nil {
		return nil, err
	}

	moveRows, err := database.DB.Query(ctx,
		`SELECT bm.boss_pokemon_id, bm.name, bm.type, bm.power, bm.damage_class
		 FROM nuzlocke_boss_moves bm
		 JOIN nuzlocke_boss_pokemon bp ON bp.id = bm.boss_pokemon_id
		 JOIN nuzlocke_timeline_entries te ON te.id = bp.timeline_entry_id
		 WHERE te.game_id = $1 AND te.version = $2
		 ORDER BY bm.boss_pokemon_id, bm.sort_order`, gameID, version)
	if err != nil {
		return nil, err
	}
	defer moveRows.Close()
	movesByBossPokemon := make(map[int][]models.NuzlockeBossMove, len(squadMembers))
	for moveRows.Next() {
		var bossPokemonID int
		var mv models.NuzlockeBossMove
		if err := moveRows.Scan(&bossPokemonID, &mv.Name, &mv.Type, &mv.Power, &mv.DamageClass); err != nil {
			moveRows.Close()
			return nil, err
		}
		movesByBossPokemon[bossPokemonID] = append(movesByBossPokemon[bossPokemonID], mv)
	}
	if err := moveRows.Err(); err != nil {
		return nil, err
	}

	for _, sm := range squadMembers {
		sm.mon.Moves = movesByBossPokemon[sm.bossPokemonID]
		idx := entryIdx[sm.entryID]
		entries[idx].Squad = append(entries[idx].Squad, sm.mon)
	}

	return entries, nil
}

// GetNuzlockeVersionsHandler lists the versions of one game that have a seeded
// timeline. An empty list means the game cannot be Nuzlocked yet, which is the
// normal case — routes are seeded per version, one at a time.
//
// This is what a "start a run" screen asks first: it answers both "is this game
// seeded" and "which version am I playing" in one request.
func GetNuzlockeVersionsHandler(w http.ResponseWriter, r *http.Request) {
	gameID, err := strconv.Atoi(r.URL.Query().Get("game_id"))
	if err != nil || gameID <= 0 {
		http.Error(w, "game_id is required and must be a positive integer", http.StatusBadRequest)
		return
	}

	rows, err := database.DB.Query(context.Background(),
		`SELECT DISTINCT version FROM nuzlocke_timeline_entries WHERE game_id = $1
		 ORDER BY version`, gameID)
	if err != nil {
		log.Printf("GetNuzlockeVersions error: %v", err)
		http.Error(w, "Failed to fetch versions", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	versions := []string{}
	for rows.Next() {
		var v string
		if err := rows.Scan(&v); err == nil {
			versions = append(versions, v)
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(versions)
}

// GetNuzlockeTimelineHandler returns the seeded reference timeline for one game
// and version. Reference data — not scoped by user.
func GetNuzlockeTimelineHandler(w http.ResponseWriter, r *http.Request) {
	gameIDStr := r.URL.Query().Get("game_id")
	gameID, err := strconv.Atoi(gameIDStr)
	if err != nil || gameID <= 0 {
		http.Error(w, "game_id is required and must be a positive integer", http.StatusBadRequest)
		return
	}
	version := strings.TrimSpace(r.URL.Query().Get("version"))
	if version == "" {
		http.Error(w, "version is required — see GET /api/nuzlocke/versions", http.StatusBadRequest)
		return
	}

	timeline, err := loadTimelineForGame(context.Background(), gameID, version)
	if err != nil {
		log.Printf("GetNuzlockeTimeline error: %v", err)
		http.Error(w, "Failed to fetch timeline", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(timeline)
}

// ─────────────────────────────────────────────────────────────────────────
// User data: runs
// ─────────────────────────────────────────────────────────────────────────

// scanRun scans one row shaped like the SELECT list shared by GetRunsHandler,
// CreateRunHandler and GetRunHandler.
func scanRun(row interface {
	Scan(dest ...any) error
}) (models.NuzlockeRun, error) {
	var run models.NuzlockeRun
	err := row.Scan(&run.ID, &run.UserID, &run.GameID, &run.Version, &run.GameTitle, &run.DupesClause, &run.BattleStyle,
		&run.NicknamesRequired, &run.Status, &run.StartedAt, &run.EndedAt, &run.CreatedAt, &run.UpdatedAt)
	return run, err
}

const runSelectColumns = `r.id, r.user_id, r.game_id, r.version, g.title, r.dupes_clause, r.battle_style, r.nicknames_required, r.status, r.started_at, r.ended_at, r.created_at, r.updated_at`

// GetRunsHandler lists every run owned by the caller.
func GetRunsHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	rows, err := database.DB.Query(context.Background(),
		`SELECT `+runSelectColumns+`
		 FROM nuzlocke_runs r
		 LEFT JOIN games g ON g.id = r.game_id
		 WHERE r.user_id = $1
		 ORDER BY r.created_at DESC`, userID)
	if err != nil {
		log.Printf("GetRuns error: %v", err)
		http.Error(w, "Failed to fetch runs", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	runs := []models.NuzlockeRun{}
	for rows.Next() {
		run, err := scanRun(rows)
		if err != nil {
			continue
		}
		runs = append(runs, run)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(runs)
}

// CreateRunHandler starts a run for the caller: a game plus house rules.
// Rejects a game with no seeded Nuzlocke timeline rather than creating a
// run that can never log anything.
func CreateRunHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")

	var req struct {
		GameID            int    `json:"game_id"`
		Version           string `json:"version"`
		DupesClause       *bool  `json:"dupes_clause"`
		BattleStyle       string `json:"battle_style"`
		NicknamesRequired *bool  `json:"nicknames_required"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.GameID <= 0 {
		http.Error(w, "game_id is required", http.StatusBadRequest)
		return
	}
	req.Version = strings.TrimSpace(req.Version)
	if req.Version == "" {
		http.Error(w, "version is required — see GET /api/nuzlocke/versions", http.StatusBadRequest)
		return
	}
	if req.BattleStyle == "" {
		req.BattleStyle = "set"
	}
	if req.BattleStyle != "set" && req.BattleStyle != "shift" {
		http.Error(w, "battle_style must be 'set' or 'shift'", http.StatusBadRequest)
		return
	}
	dupesClause := true
	if req.DupesClause != nil {
		dupesClause = *req.DupesClause
	}
	nicknamesRequired := true
	if req.NicknamesRequired != nil {
		nicknamesRequired = *req.NicknamesRequired
	}

	ctx := context.Background()

	// Validated against (game, version), not the game alone: Platinum being
	// seeded says nothing about whether Diamond is.
	var hasTimeline bool
	if err := database.DB.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM nuzlocke_timeline_entries WHERE game_id = $1 AND version = $2)`,
		req.GameID, req.Version).Scan(&hasTimeline); err != nil {
		http.Error(w, "Failed to validate game", http.StatusInternalServerError)
		return
	}
	if !hasTimeline {
		http.Error(w, "No Nuzlocke timeline is seeded for this game version", http.StatusBadRequest)
		return
	}

	var runID string
	if err := database.DB.QueryRow(ctx,
		`INSERT INTO nuzlocke_runs (user_id, game_id, version, dupes_clause, battle_style, nicknames_required)
		 VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
		userID, req.GameID, req.Version, dupesClause, req.BattleStyle, nicknamesRequired).Scan(&runID); err != nil {
		log.Printf("CreateRun error: %v", err)
		http.Error(w, "Failed to create run", http.StatusInternalServerError)
		return
	}

	run, err := scanRun(database.DB.QueryRow(ctx,
		`SELECT `+runSelectColumns+` FROM nuzlocke_runs r LEFT JOIN games g ON g.id = r.game_id WHERE r.id = $1`, runID))
	if err != nil {
		log.Printf("CreateRun reload error: %v", err)
		http.Error(w, "Failed to load created run", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(run)
}

// loadOwnedRun loads a run's game_id/dupes_clause/nicknames_required, scoped
// to (id, user_id). Every error — no row, malformed uuid, or a real DB error
// — is reported to the caller as "not found": a request for another user's
// run must not distinguish "doesn't exist" from "not yours".
func loadOwnedRun(ctx context.Context, runID, userID string) (gameID *int, version string, dupesClause, nicknamesRequired bool, err error) {
	err = database.DB.QueryRow(ctx,
		`SELECT game_id, version, dupes_clause, nicknames_required FROM nuzlocke_runs WHERE id = $1 AND user_id = $2`,
		runID, userID).Scan(&gameID, &version, &dupesClause, &nicknamesRequired)
	return
}

// GetRunHandler returns one run with its timeline, logged encounters, and
// boss progress. 404s (not 403) for a run that exists but isn't the
// caller's, so existence is never leaked.
func GetRunHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	runID := chi.URLParam(r, "id")
	ctx := context.Background()

	run, err := scanRun(database.DB.QueryRow(ctx,
		`SELECT `+runSelectColumns+` FROM nuzlocke_runs r LEFT JOIN games g ON g.id = r.game_id WHERE r.id = $1 AND r.user_id = $2`,
		runID, userID))
	if err != nil {
		http.Error(w, "Run not found", http.StatusNotFound)
		return
	}

	detail := models.NuzlockeRunDetail{NuzlockeRun: run, Timeline: []models.NuzlockeTimelineEntry{}, Encounters: []models.NuzlockeEncounterLog{}, BossProgress: []models.NuzlockeBossProgress{}}

	if run.GameID != nil {
		timeline, err := loadTimelineForGame(ctx, *run.GameID, run.Version)
		if err != nil {
			log.Printf("GetRun timeline error: %v", err)
			http.Error(w, "Failed to load timeline", http.StatusInternalServerError)
			return
		}
		detail.Timeline = timeline
	}

	encRows, err := database.DB.Query(ctx,
		`SELECT el.id, el.run_id, COALESCE(te.slug, ''), el.pokemon_id, p.name, el.nickname, el.status, el.nature, el.is_boxed, el.is_dupe, el.created_at, el.updated_at
		 FROM nuzlocke_encounters_logged el
		 LEFT JOIN nuzlocke_timeline_entries te ON te.id = el.timeline_entry_id
		 LEFT JOIN pokemon p ON p.id = el.pokemon_id
		 WHERE el.run_id = $1
		 ORDER BY te.sort_order ASC NULLS LAST`, runID)
	if err != nil {
		log.Printf("GetRun encounters error: %v", err)
		http.Error(w, "Failed to load encounters", http.StatusInternalServerError)
		return
	}
	defer encRows.Close()
	for encRows.Next() {
		var e models.NuzlockeEncounterLog
		if err := encRows.Scan(&e.ID, &e.RunID, &e.LocationSlug, &e.PokemonID, &e.PokemonName, &e.Nickname, &e.Status, &e.Nature, &e.IsBoxed, &e.IsDupe, &e.CreatedAt, &e.UpdatedAt); err != nil {
			encRows.Close()
			log.Printf("GetRun encounters scan error: %v", err)
			http.Error(w, "Failed to load encounters", http.StatusInternalServerError)
			return
		}
		detail.Encounters = append(detail.Encounters, e)
	}
	if err := encRows.Err(); err != nil {
		log.Printf("GetRun encounters error: %v", err)
		http.Error(w, "Failed to load encounters", http.StatusInternalServerError)
		return
	}

	bossRows, err := database.DB.Query(ctx,
		`SELECT te.slug, bp.beaten
		 FROM nuzlocke_boss_progress bp
		 JOIN nuzlocke_timeline_entries te ON te.id = bp.timeline_entry_id
		 WHERE bp.run_id = $1`, runID)
	if err != nil {
		log.Printf("GetRun boss progress error: %v", err)
		http.Error(w, "Failed to load boss progress", http.StatusInternalServerError)
		return
	}
	defer bossRows.Close()
	for bossRows.Next() {
		var bp models.NuzlockeBossProgress
		if err := bossRows.Scan(&bp.BossSlug, &bp.Beaten); err != nil {
			bossRows.Close()
			log.Printf("GetRun boss progress scan error: %v", err)
			http.Error(w, "Failed to load boss progress", http.StatusInternalServerError)
			return
		}
		detail.BossProgress = append(detail.BossProgress, bp)
	}
	if err := bossRows.Err(); err != nil {
		log.Printf("GetRun boss progress error: %v", err)
		http.Error(w, "Failed to load boss progress", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(detail)
}

// UpdateRunHandler updates a run's status. Ending a run archives it
// (ended_at is stamped); runs are never deleted.
func UpdateRunHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	runID := chi.URLParam(r, "id")

	var req struct {
		Status string `json:"status"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if req.Status != "active" && req.Status != "ended" {
		http.Error(w, "status must be 'active' or 'ended'", http.StatusBadRequest)
		return
	}

	ctx := context.Background()
	tag, err := database.DB.Exec(ctx,
		`UPDATE nuzlocke_runs
		 SET status = $1, ended_at = CASE WHEN $1 = 'ended' THEN now() ELSE NULL END, updated_at = now()
		 WHERE id = $2 AND user_id = $3`,
		req.Status, runID, userID)
	if err != nil || tag.RowsAffected() == 0 {
		http.Error(w, "Run not found", http.StatusNotFound)
		return
	}

	// Reload with the game title joined in, same as CreateRunHandler.
	run, err := scanRun(database.DB.QueryRow(ctx,
		`SELECT `+runSelectColumns+` FROM nuzlocke_runs r LEFT JOIN games g ON g.id = r.game_id WHERE r.id = $1`, runID))
	if err != nil {
		log.Printf("UpdateRun reload error: %v", err)
		http.Error(w, "Failed to load updated run", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(run)
}

// ─────────────────────────────────────────────────────────────────────────
// User data: logged encounters
// ─────────────────────────────────────────────────────────────────────────

// needsNickname reports whether a logged encounter is missing a
// caller-required nickname. Only "caught" and "fainted" ever carry a
// Pokemon (and therefore a nickname); "missed"/"ran" never need one.
func needsNickname(nicknamesRequired bool, status string, nickname *string) bool {
	if !nicknamesRequired {
		return false
	}
	if status != "caught" && status != "fainted" {
		return false
	}
	return nickname == nil || strings.TrimSpace(*nickname) == ""
}

// isDupeCatch reports whether logging pokemonID as a fresh catch should be
// flagged a dupe: the run's dupes clause is on, this is a real catch (not a
// miss/faint/run), and that species is already caught elsewhere in the run.
func isDupeCatch(dupesClauseOn bool, status string, pokemonID int, alreadyCaughtElsewhere []int) bool {
	if !dupesClauseOn || status != "caught" {
		return false
	}
	for _, id := range alreadyCaughtElsewhere {
		if id == pokemonID {
			return true
		}
	}
	return false
}

var validEncounterStatuses = map[string]bool{"caught": true, "missed": true, "fainted": true, "ran": true}

// PutRunEncounterHandler logs or updates the encounter at one location for
// one run.
func PutRunEncounterHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	runID := chi.URLParam(r, "id")
	locationSlug := chi.URLParam(r, "locationSlug")
	ctx := context.Background()

	var req struct {
		PokemonID *int    `json:"pokemon_id"`
		Status    string  `json:"status"`
		Nickname  *string `json:"nickname"`
		Nature    *string `json:"nature"`
		IsBoxed   *bool   `json:"is_boxed"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}
	if !validEncounterStatuses[req.Status] {
		http.Error(w, "status must be one of caught, missed, fainted, ran", http.StatusBadRequest)
		return
	}

	gameID, version, dupesClause, nicknamesRequired, err := loadOwnedRun(ctx, runID, userID)
	if err != nil {
		http.Error(w, "Run not found", http.StatusNotFound)
		return
	}
	if gameID == nil {
		http.Error(w, "This run has no game set", http.StatusBadRequest)
		return
	}

	needsPokemon := req.Status == "caught" || req.Status == "fainted"
	if needsPokemon && (req.PokemonID == nil || *req.PokemonID <= 0) {
		http.Error(w, "pokemon_id is required for status caught or fainted", http.StatusBadRequest)
		return
	}
	if !needsPokemon {
		req.PokemonID = nil
	}
	if needsNickname(nicknamesRequired, req.Status, req.Nickname) {
		http.Error(w, "This run requires a nickname for every catch", http.StatusBadRequest)
		return
	}

	var timelineEntryID int
	if err := database.DB.QueryRow(ctx,
		`SELECT id FROM nuzlocke_timeline_entries
		 WHERE game_id = $1 AND version = $2 AND slug = $3 AND kind = 'location'`,
		*gameID, version, locationSlug).Scan(&timelineEntryID); err != nil {
		http.Error(w, "Location not found", http.StatusNotFound)
		return
	}

	if needsPokemon {
		var inPool bool
		if err := database.DB.QueryRow(ctx,
			`SELECT EXISTS(SELECT 1 FROM nuzlocke_encounter_pool WHERE timeline_entry_id = $1 AND pokemon_id = $2)`,
			timelineEntryID, *req.PokemonID).Scan(&inPool); err != nil {
			http.Error(w, "Failed to validate encounter", http.StatusInternalServerError)
			return
		}
		if !inPool {
			http.Error(w, "That Pokemon is not in this location's encounter pool", http.StatusBadRequest)
			return
		}
	}

	isDupe := false
	if req.Status == "caught" {
		rows, err := database.DB.Query(ctx,
			`SELECT pokemon_id FROM nuzlocke_encounters_logged
			 WHERE run_id = $1 AND status = 'caught' AND pokemon_id IS NOT NULL AND timeline_entry_id IS DISTINCT FROM $2`,
			runID, timelineEntryID)
		if err != nil {
			http.Error(w, "Failed to validate encounter", http.StatusInternalServerError)
			return
		}
		var caughtElsewhere []int
		for rows.Next() {
			var id int
			if err := rows.Scan(&id); err == nil {
				caughtElsewhere = append(caughtElsewhere, id)
			}
		}
		rows.Close()
		isDupe = isDupeCatch(dupesClause, req.Status, *req.PokemonID, caughtElsewhere)
	}

	isBoxed := false
	if req.IsBoxed != nil {
		isBoxed = *req.IsBoxed
	}

	var entryLog models.NuzlockeEncounterLog
	err = database.DB.QueryRow(ctx,
		`INSERT INTO nuzlocke_encounters_logged (run_id, timeline_entry_id, pokemon_id, nickname, status, nature, is_boxed, is_dupe)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		 ON CONFLICT (run_id, timeline_entry_id) DO UPDATE SET
		     pokemon_id = EXCLUDED.pokemon_id, nickname = EXCLUDED.nickname, status = EXCLUDED.status,
		     nature = EXCLUDED.nature, is_boxed = EXCLUDED.is_boxed, is_dupe = EXCLUDED.is_dupe, updated_at = now()
		 RETURNING id, run_id, pokemon_id, nickname, status, nature, is_boxed, is_dupe, created_at, updated_at`,
		runID, timelineEntryID, req.PokemonID, req.Nickname, req.Status, req.Nature, isBoxed, isDupe,
	).Scan(&entryLog.ID, &entryLog.RunID, &entryLog.PokemonID, &entryLog.Nickname, &entryLog.Status, &entryLog.Nature, &entryLog.IsBoxed, &entryLog.IsDupe, &entryLog.CreatedAt, &entryLog.UpdatedAt)
	if err != nil {
		log.Printf("PutRunEncounter error: %v", err)
		http.Error(w, "Failed to log encounter", http.StatusInternalServerError)
		return
	}
	entryLog.LocationSlug = locationSlug

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(entryLog)
}

// ─────────────────────────────────────────────────────────────────────────
// User data: party management
// ─────────────────────────────────────────────────────────────────────────

// PatchPartyMemberHandler moves a logged (caught) encounter between alive,
// boxed, and fainted. memberId is the logged encounter's own id — a party
// "member" is a specific catch, not a location.
func PatchPartyMemberHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	runID := chi.URLParam(r, "id")
	memberID := chi.URLParam(r, "memberId")
	ctx := context.Background()

	var req struct {
		Status string `json:"status"` // "alive", "fainted", "boxed"
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	var newStatus string
	var newIsBoxed *bool
	switch req.Status {
	case "alive":
		newStatus, newIsBoxed = "caught", boolPtr(false)
	case "boxed":
		newStatus, newIsBoxed = "caught", boolPtr(true)
	case "fainted":
		newStatus = "fainted" // is_boxed is left as-is, matching the design prototype
	default:
		http.Error(w, "status must be one of alive, fainted, boxed", http.StatusBadRequest)
		return
	}

	// Ownership is verified through the run, then the update itself is
	// additionally scoped by run_id so the write can never touch a row
	// outside that run — same two-step pattern LogPhaseHandler uses.
	if _, _, _, _, err := loadOwnedRun(ctx, runID, userID); err != nil {
		http.Error(w, "Run not found", http.StatusNotFound)
		return
	}

	var query string
	var args []any
	if newIsBoxed != nil {
		query = `UPDATE nuzlocke_encounters_logged SET status = $1, is_boxed = $2, updated_at = now()
		          WHERE id = $3 AND run_id = $4
		          RETURNING id, run_id, COALESCE((SELECT slug FROM nuzlocke_timeline_entries WHERE id = timeline_entry_id), ''), pokemon_id, nickname, status, nature, is_boxed, is_dupe, created_at, updated_at`
		args = []any{newStatus, *newIsBoxed, memberID, runID}
	} else {
		query = `UPDATE nuzlocke_encounters_logged SET status = $1, updated_at = now()
		          WHERE id = $2 AND run_id = $3
		          RETURNING id, run_id, COALESCE((SELECT slug FROM nuzlocke_timeline_entries WHERE id = timeline_entry_id), ''), pokemon_id, nickname, status, nature, is_boxed, is_dupe, created_at, updated_at`
		args = []any{newStatus, memberID, runID}
	}

	var el models.NuzlockeEncounterLog
	err := database.DB.QueryRow(ctx, query, args...).
		Scan(&el.ID, &el.RunID, &el.LocationSlug, &el.PokemonID, &el.Nickname, &el.Status, &el.Nature, &el.IsBoxed, &el.IsDupe, &el.CreatedAt, &el.UpdatedAt)
	if err != nil {
		http.Error(w, "Party member not found", http.StatusNotFound)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(el)
}

func boolPtr(b bool) *bool { return &b }

// ─────────────────────────────────────────────────────────────────────────
// User data: boss progress
// ─────────────────────────────────────────────────────────────────────────

// PutBossProgressHandler sets the beaten flag for one boss in one run.
func PutBossProgressHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	runID := chi.URLParam(r, "id")
	bossSlug := chi.URLParam(r, "bossSlug")
	ctx := context.Background()

	var req struct {
		Beaten bool `json:"beaten"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	gameID, version, _, _, err := loadOwnedRun(ctx, runID, userID)
	if err != nil {
		http.Error(w, "Run not found", http.StatusNotFound)
		return
	}
	if gameID == nil {
		http.Error(w, "This run has no game set", http.StatusBadRequest)
		return
	}

	var timelineEntryID int
	if err := database.DB.QueryRow(ctx,
		`SELECT id FROM nuzlocke_timeline_entries
		 WHERE game_id = $1 AND version = $2 AND slug = $3 AND kind = 'boss'`,
		*gameID, version, bossSlug).Scan(&timelineEntryID); err != nil {
		http.Error(w, "Boss not found", http.StatusNotFound)
		return
	}

	if _, err := database.DB.Exec(ctx,
		`INSERT INTO nuzlocke_boss_progress (run_id, timeline_entry_id, beaten, updated_at)
		 VALUES ($1, $2, $3, now())
		 ON CONFLICT (run_id, timeline_entry_id) DO UPDATE SET beaten = EXCLUDED.beaten, updated_at = now()`,
		runID, timelineEntryID, req.Beaten); err != nil {
		log.Printf("PutBossProgress error: %v", err)
		http.Error(w, "Failed to update boss progress", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(models.NuzlockeBossProgress{BossSlug: bossSlug, Beaten: req.Beaten})
}
