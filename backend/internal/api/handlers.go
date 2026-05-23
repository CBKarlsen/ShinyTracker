package api

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"

	"github.com/casper/shinytracker/internal/calc"
	"github.com/casper/shinytracker/internal/database"
	"github.com/casper/shinytracker/internal/models"
	"github.com/casper/shinytracker/internal/services"
	"github.com/go-chi/chi/v5"
)

type RegisterRequest struct {
	Username string `json:"username"`
	Email    string `json:"email"`
	Password string `json:"password"`
}

type LoginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func RegisterHandler(w http.ResponseWriter, r *http.Request) {
	var req RegisterRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	hashedPassword, err := HashPassword(req.Password)
	if err != nil {
		http.Error(w, "Failed to hash password", http.StatusInternalServerError)
		return
	}

	var user models.User
	err = database.DB.QueryRow(context.Background(),
		"INSERT INTO users (username, email, password_hash) VALUES ($1, $2, $3) RETURNING id, username, email, created_at",
		req.Username, req.Email, hashedPassword).Scan(&user.ID, &user.Username, &user.Email, &user.CreatedAt)

	if err != nil {
		http.Error(w, "Username or email already exists", http.StatusConflict)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

func LoginHandler(w http.ResponseWriter, r *http.Request) {
	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	var user models.User
	var storedHash string
	err := database.DB.QueryRow(context.Background(),
		"SELECT id, username, email, password_hash, created_at FROM users WHERE email = $1",
		req.Email).Scan(&user.ID, &user.Username, &user.Email, &storedHash, &user.CreatedAt)

	if err != nil || !CheckPasswordHash(req.Password, storedHash) {
		http.Error(w, "Invalid credentials", http.StatusUnauthorized)
		return
	}

	token, err := GenerateJWT(user.ID)
	if err != nil {
		http.Error(w, "Failed to generate token", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"token": token,
		"user":  user,
	})
}

func GetUserGamesHandler(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	authUserID := r.Header.Get("X-User-ID")

	if userID != authUserID {
		http.Error(w, "Unauthorized access to user games", http.StatusForbidden)
		return
	}

	rows, err := database.DB.Query(context.Background(),
		"SELECT game_id, has_shiny_charm FROM user_games WHERE user_id = $1", userID)
	if err != nil {
		http.Error(w, "Failed to fetch user games", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var userGames []models.UserGame
	for rows.Next() {
		var ug models.UserGame
		ug.UserID = userID
		if err := rows.Scan(&ug.GameID, &ug.HasShinyCharm); err != nil {
			continue
		}
		userGames = append(userGames, ug)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(userGames)
}

func ToggleUserGameHandler(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	gameID := chi.URLParam(r, "gameId")
	authUserID := r.Header.Get("X-User-ID")

	if userID != authUserID {
		http.Error(w, "Unauthorized access", http.StatusForbidden)
		return
	}

	var req struct {
		HasShinyCharm bool `json:"has_shiny_charm"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Invalid request body", http.StatusBadRequest)
		return
	}

	_, err := database.DB.Exec(context.Background(),
		`INSERT INTO user_games (user_id, game_id, has_shiny_charm) 
		 VALUES ($1, $2, $3) 
		 ON CONFLICT (user_id, game_id) 
		 DO UPDATE SET has_shiny_charm = EXCLUDED.has_shiny_charm`,
		userID, gameID, req.HasShinyCharm)

	if err != nil {
		http.Error(w, "Failed to update user game", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "success"})
}

func RemoveUserGameHandler(w http.ResponseWriter, r *http.Request) {
	userID := chi.URLParam(r, "id")
	gameID := chi.URLParam(r, "gameId")
	authUserID := r.Header.Get("X-User-ID")

	if userID != authUserID {
		http.Error(w, "Unauthorized access", http.StatusForbidden)
		return
	}

	_, err := database.DB.Exec(context.Background(),
		"DELETE FROM user_games WHERE user_id = $1 AND game_id = $2",
		userID, gameID)
	if err != nil {
		http.Error(w, "Failed to remove user game", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(map[string]string{"message": "success"})
}

func MeHandler(w http.ResponseWriter, r *http.Request) {
	userID := r.Header.Get("X-User-ID")
	var user models.User
	err := database.DB.QueryRow(context.Background(),
		"SELECT id, username, email, is_admin, created_at FROM users WHERE id = $1", userID).
		Scan(&user.ID, &user.Username, &user.Email, &user.IsAdmin, &user.CreatedAt)
	if err != nil {
		http.Error(w, "User not found", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(user)
}

func SyncHandler(w http.ResponseWriter, r *http.Request) {
	go services.SyncPokemonData()
	w.WriteHeader(http.StatusAccepted)
	json.NewEncoder(w).Encode(map[string]string{"message": "Sync started in background"})
}

func GetGamesHandler(w http.ResponseWriter, r *http.Request) {
	rows, err := database.DB.Query(context.Background(), "SELECT id, title, generation, base_odds FROM games ORDER BY id ASC")
	if err != nil {
		http.Error(w, "Failed to fetch games", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var games []models.Game
	for rows.Next() {
		var g models.Game
		if err := rows.Scan(&g.ID, &g.Title, &g.Generation, &g.BaseOdds); err == nil {
			games = append(games, g)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(games)
}

func GetPokemonHandler(w http.ResponseWriter, r *http.Request) {
	search := r.URL.Query().Get("q")
	query := "SELECT id, name, sprite_url, types FROM pokemon"
	args := []interface{}{}
	
	limit := r.URL.Query().Get("limit")
	
	if search != "" {
		query += " WHERE name ILIKE $1"
		args = append(args, "%"+search+"%")
	}
	query += " ORDER BY id ASC"
	
	if limit != "all" {
		query += " LIMIT 50"
	}

	rows, err := database.DB.Query(context.Background(), query, args...)
	if err != nil {
		http.Error(w, "Failed to fetch pokemon", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var pokemon []models.Pokemon
	for rows.Next() {
		var p models.Pokemon
		if err := rows.Scan(&p.ID, &p.Name, &p.SpriteURL, &p.Types); err == nil {
			pokemon = append(pokemon, p)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(pokemon)
}

type HuntMethodDetail struct {
	ID             int    `json:"id"`
	PokemonID      int    `json:"pokemon_id"`
	GameID         int    `json:"game_id"`
	GameTitle      string `json:"game_title"`
	MethodName     string `json:"method_name"`
	AvgTimeSeconds int    `json:"avg_time_seconds"`
	BaseRolls      int    `json:"base_rolls"`
	CharmRolls     int    `json:"charm_rolls"`
	IsRecommended  bool   `json:"is_recommended"`
	FormulaType    string `json:"formula_type"`
}

type MethodDetail struct {
	ID             int    `json:"id"`
	GameID         int    `json:"game_id"`
	GameTitle      string `json:"game_title"`
	MethodName     string `json:"method_name"`
	BaseRolls      int    `json:"base_rolls"`
	CharmRolls     int    `json:"charm_rolls"`
	AvgTimeSeconds int    `json:"avg_time_seconds"`
	IsRecommended  bool   `json:"is_recommended"`
	FormulaType    string `json:"formula_type"`
}

type OddsResponse struct {
	Fraction           string  `json:"fraction"`
	Percentage         string  `json:"percentage"`
	ExpectedEncounters int     `json:"expected_encounters"`
	ETAHours           float64 `json:"eta_hours"`
}

func GetMethodsHandler(w http.ResponseWriter, r *http.Request) {
	gameIDStr := r.URL.Query().Get("game_id")
	gameID := 0
	if gameIDStr != "" {
		var err error
		gameID, err = strconv.Atoi(gameIDStr)
		if err != nil {
			http.Error(w, "game_id must be an integer", http.StatusBadRequest)
			return
		}
	}

	rows, err := database.DB.Query(context.Background(), `
		SELECT DISTINCT ON (g.id, hm.method_name)
			hm.id, g.id as game_id, g.title, hm.method_name,
			hm.base_rolls, hm.charm_rolls, hm.avg_time_seconds, hm.is_recommended, hm.formula_type
		FROM hunt_methods hm
		JOIN games g ON g.generation = hm.generation
		WHERE ($1 = 0 OR g.id = $1)
		ORDER BY g.id ASC, hm.method_name ASC
	`, gameID)
	if err != nil {
		fmt.Println("GetMethodsHandler error:", err)
		http.Error(w, "Failed to fetch methods", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var methods []MethodDetail
	for rows.Next() {
		var m MethodDetail
		if err := rows.Scan(&m.ID, &m.GameID, &m.GameTitle, &m.MethodName,
			&m.BaseRolls, &m.CharmRolls, &m.AvgTimeSeconds, &m.IsRecommended, &m.FormulaType); err == nil {
			methods = append(methods, m)
		}
	}
	if methods == nil {
		methods = []MethodDetail{}
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(methods)
}

func GetOddsHandler(w http.ResponseWriter, r *http.Request) {
	huntMethodIDStr := r.URL.Query().Get("hunt_method_id")
	if huntMethodIDStr == "" {
		http.Error(w, "hunt_method_id is required", http.StatusBadRequest)
		return
	}
	huntMethodID, err := strconv.Atoi(huntMethodIDStr)
	if err != nil {
		http.Error(w, "hunt_method_id must be an integer", http.StatusBadRequest)
		return
	}
	shinyCharm := r.URL.Query().Get("shiny_charm") == "true"

	var baseRolls, charmRolls, avgTimeSeconds, baseOdds int
	err = database.DB.QueryRow(context.Background(), `
		SELECT e.base_rolls, e.charm_rolls, e.avg_time_seconds, g.base_odds
		FROM hunt_methods e
		JOIN games g ON e.game_id = g.id
		WHERE e.id = $1
	`, huntMethodID).Scan(&baseRolls, &charmRolls, &avgTimeSeconds, &baseOdds)
	if err != nil {
		http.Error(w, "Hunt method not found", http.StatusNotFound)
		return
	}

	totalRolls := baseRolls
	if shinyCharm {
		totalRolls += charmRolls
	}
	if totalRolls <= 0 {
		totalRolls = 1
	}

	expectedEncounters := baseOdds / totalRolls
	etaHours := calc.CalculateEstimatedTimeHours(calc.OddsConfig{
		BaseOdds:       baseOdds,
		BaseRolls:      baseRolls,
		CharmRolls:     charmRolls,
		HasShinyCharm:  shinyCharm,
		AvgTimeSeconds: avgTimeSeconds,
	})

	resp := OddsResponse{
		Fraction:           fmt.Sprintf("1/%d", expectedEncounters),
		Percentage:         fmt.Sprintf("%.4f%%", float64(totalRolls)/float64(baseOdds)*100),
		ExpectedEncounters: expectedEncounters,
		ETAHours:           float64(int(etaHours*10+0.5)) / 10,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

func GetHuntMethodsHandler(w http.ResponseWriter, r *http.Request) {
	pokemonIDStr := r.URL.Query().Get("pokemon_id")
	if pokemonIDStr == "" {
		http.Error(w, "pokemon_id is required", http.StatusBadRequest)
		return
	}
	pokemonID, err := strconv.Atoi(pokemonIDStr)
	if err != nil {
		http.Error(w, "pokemon_id must be an integer", http.StatusBadRequest)
		return
	}

	userID := r.Header.Get("X-User-ID")
	if userID == "" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	// Fetch methods from our new rules-based availability table
	rows, err := database.DB.Query(context.Background(), `
		SELECT hm.id, ma.pokemon_id, g.id as game_id, g.title, hm.method_name, hm.avg_time_seconds, hm.base_rolls, hm.charm_rolls, hm.is_recommended, hm.formula_type
		FROM method_availability ma
		JOIN hunt_methods hm ON ma.method_id = hm.id
		JOIN games g ON g.generation = hm.generation
		JOIN user_games ug ON g.id = ug.game_id
		WHERE ma.pokemon_id = $1 AND ug.user_id = $2
		ORDER BY g.generation ASC, g.id ASC
	`, pokemonID, userID)
	if err != nil {
		http.Error(w, "Failed to fetch hunt methods", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var methods []HuntMethodDetail
	for rows.Next() {
		var m HuntMethodDetail
		if err := rows.Scan(
			&m.ID, &m.PokemonID, &m.GameID, &m.GameTitle,
			&m.MethodName, &m.AvgTimeSeconds, &m.BaseRolls, &m.CharmRolls, &m.IsRecommended, &m.FormulaType,
		); err != nil {
			continue
		}
		methods = append(methods, m)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(methods)
}
