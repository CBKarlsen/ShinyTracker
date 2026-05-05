package api

import (
	"context"
	"encoding/json"
	"net/http"

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

type EncounterDetail struct {
	ID             int    `json:"id"`
	PokemonID      int    `json:"pokemon_id"`
	GameID         int    `json:"game_id"`
	GameTitle      string `json:"game_title"`
	MethodName     string `json:"method_name"`
	AvgTimeSeconds int    `json:"avg_time_seconds"`
	BaseRolls      int    `json:"base_rolls"`
	CharmRolls     int    `json:"charm_rolls"`
}

func GetEncountersHandler(w http.ResponseWriter, r *http.Request) {
	pokemonID := r.URL.Query().Get("pokemon_id")
	if pokemonID == "" {
		http.Error(w, "pokemon_id is required", http.StatusBadRequest)
		return
	}

	query := `
		SELECT e.id, e.pokemon_id, e.game_id, g.title, e.method_name, e.avg_time_seconds, e.base_rolls, e.charm_rolls
		FROM encounters e
		JOIN games g ON e.game_id = g.id
		WHERE e.pokemon_id = $1
		ORDER BY g.generation ASC, g.id ASC
	`

	rows, err := database.DB.Query(context.Background(), query, pokemonID)
	if err != nil {
		http.Error(w, "Failed to fetch encounters", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	var encounters []EncounterDetail
	for rows.Next() {
		var enc EncounterDetail
		if err := rows.Scan(
			&enc.ID, &enc.PokemonID, &enc.GameID, &enc.GameTitle,
			&enc.MethodName, &enc.AvgTimeSeconds, &enc.BaseRolls, &enc.CharmRolls); err != nil {
			continue
		}
		encounters = append(encounters, enc)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(encounters)
}
