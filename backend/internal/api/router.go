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
		r.Get("/methods", GetMethodsHandler)
		r.Get("/odds", GetOddsHandler)

		r.Group(func(r chi.Router) {
			r.Use(AuthMiddleware)
			r.Get("/me", MeHandler)

			r.Get("/user/{id}/games", GetUserGamesHandler)
			r.Post("/user/{id}/games/{gameId}", ToggleUserGameHandler)
			r.Delete("/user/{id}/games/{gameId}", RemoveUserGameHandler)

			r.Get("/hunts", GetHuntsHandler)
			r.Post("/hunts", CreateHuntHandler)
			r.Post("/hunts/manual", ManualCatchHandler)
			r.Patch("/hunts/{id}", UpdateHuntHandler)
			r.Post("/hunts/{id}/phases", LogPhaseHandler)
			r.Delete("/hunts/manual/{pokemonId}", RemoveManualCatchHandler)

			r.Get("/hunt-methods", GetHuntMethodsHandler)

			r.Group(func(r chi.Router) {
				r.Use(AdminMiddleware)
				r.Get("/admin/hunt-methods", AdminGetHuntMethods)
				r.Post("/admin/hunt-methods", AdminCreateHuntMethod)
				r.Post("/admin/hunt-methods/import", AdminImportHuntMethods)
				r.Put("/admin/hunt-methods/{id}", AdminUpdateHuntMethod)
				r.Delete("/admin/hunt-methods/{id}", AdminDeleteHuntMethod)

				r.Get("/admin/games", AdminGetGames)
				r.Post("/admin/games", AdminCreateGame)
				r.Put("/admin/games/{id}", AdminUpdateGame)
				r.Delete("/admin/games/{id}", AdminDeleteGame)

				r.Get("/admin/availability", AdminGetAvailability)
				r.Put("/admin/availability", AdminSetAvailability)

				r.Get("/admin/users", AdminGetUsers)
				r.Patch("/admin/users/{id}", AdminPatchUser)
			})
		})
	})

	return r
}
