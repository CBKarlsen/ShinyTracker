package api

import (
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
)

func NewRouter() *chi.Mux {
	r := chi.NewRouter()

	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   []string{"http://localhost:5173", "*"},
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	r.Route("/api", func(r chi.Router) {
		r.Post("/auth/register", RegisterHandler)
		r.Post("/auth/login", LoginHandler)
		r.Post("/sync", SyncHandler)
		r.Get("/games", GetGamesHandler)
		r.Get("/pokemon", GetPokemonHandler)

		r.Group(func(r chi.Router) {
			r.Use(AuthMiddleware)
			r.Get("/user/{id}/games", GetUserGamesHandler)
			r.Post("/user/{id}/games/{gameId}", ToggleUserGameHandler)
			
			r.Get("/hunts", GetHuntsHandler)
			r.Post("/hunts", CreateHuntHandler)
			r.Patch("/hunts/{id}", UpdateHuntHandler)

			r.Get("/recommend/{pokemonId}", GetRecommendationsHandler)
		})
	})

	return r
}
