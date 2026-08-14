package api

import (
	"os"
	"strings"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
)

// corsAllowedOrigins reads CORS_ALLOWED_ORIGINS (comma-separated) from env.
// Falls back to http://localhost:5173 for local dev when the var is unset.
// AllowCredentials: true is only safe with explicit origins, never with "*".
func corsAllowedOrigins() []string {
	raw := os.Getenv("CORS_ALLOWED_ORIGINS")
	if raw == "" {
		return []string{"http://localhost:5173"}
	}
	parts := strings.Split(raw, ",")
	origins := make([]string, 0, len(parts))
	for _, p := range parts {
		if o := strings.TrimSpace(p); o != "" {
			origins = append(origins, o)
		}
	}
	if len(origins) == 0 {
		return []string{"http://localhost:5173"}
	}
	return origins
}

func NewRouter() *chi.Mux {
	r := chi.NewRouter()

	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)
	r.Use(cors.Handler(cors.Options{
		AllowedOrigins:   corsAllowedOrigins(),
		AllowedMethods:   []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowedHeaders:   []string{"Accept", "Authorization", "Content-Type", "X-CSRF-Token"},
		ExposedHeaders:   []string{"Link"},
		AllowCredentials: true,
		MaxAge:           300,
	}))

	r.Route("/api", func(r chi.Router) {
		r.Get("/games", GetGamesHandler)
		r.Get("/games/{id}/pokemon", GetGamePokemonHandler)
		r.Get("/games/{id}/pokedex", GetGamePokedexHandler)
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
			r.Delete("/hunts/{id}", DeleteHuntHandler)
			r.Post("/hunts/{id}/phases", LogPhaseHandler)
			r.Delete("/hunts/manual/{pokemonId}", RemoveManualCatchHandler)

			r.Get("/hunt-methods", GetHuntMethodsHandler)

			r.Get("/stats", GetStatsHandler)
			r.Get("/export", ExportHandler)

			r.Get("/dex/status", DexStatusHandler)
			r.Get("/dex/suggestions", DexSuggestionsHandler)
			r.Get("/pokemon/{id}", PokemonDetailHandler)
			r.Get("/pokemon/{id}/route", PokemonRouteHandler)

			r.Get("/runs", GetRunsHandler)
			r.Post("/runs", CreateRunHandler)
			r.Get("/runs/{id}", GetRunHandler)
			r.Patch("/runs/{id}", UpdateRunHandler)
			r.Put("/runs/{id}/encounters/{locationSlug}", PutRunEncounterHandler)
			r.Patch("/runs/{id}/party/{memberId}", PatchPartyMemberHandler)
			r.Put("/runs/{id}/bosses/{bossSlug}", PutBossProgressHandler)
			r.Get("/nuzlocke/timeline", GetNuzlockeTimelineHandler)
			r.Get("/nuzlocke/versions", GetNuzlockeVersionsHandler)

			r.Group(func(r chi.Router) {
				r.Use(AdminMiddleware)
				// hunt_methods are global, derived availability — read-only view
				// plus edit/delete of the global method by id. No create/import.
				// SyncHandler triggers a PokeAPI re-seed in a goroutine;
				// admin-only to prevent unauthenticated abuse.
				r.Post("/sync", SyncHandler)

				r.Get("/admin/hunt-methods", AdminGetHuntMethods)
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
