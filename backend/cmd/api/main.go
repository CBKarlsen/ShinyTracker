package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/casper/shinytracker/internal/api"
	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

// validateRequiredEnv fails fast on missing config instead of booting healthy
// and then 401ing (or worse) every request. Single pass, called once here,
// so a typo'd var is a startup crash, not a silent runtime surprise.
func validateRequiredEnv() {
	if os.Getenv("DATABASE_URL") == "" {
		log.Fatal("DATABASE_URL env var is required but not set")
	}
	if _, err := api.SupabaseURLFromEnv(); err != nil {
		log.Fatalf("startup config error: %v", err)
	}
}

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("No .env file found, relying on environment variables")
	}

	validateRequiredEnv()

	if err := database.ConnectDB(); err != nil {
		log.Fatalf("Database connection failed: %v", err)
	}

	r := api.NewRouter()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Timeouts are set explicitly: the bare http.ListenAndServe used before this
	// had none, so a slow/stalled client could hold a connection (and its goroutine)
	// open indefinitely. Values are generous for a JSON API, not tuned for streaming.
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           r,
		ReadTimeout:       15 * time.Second,
		ReadHeaderTimeout: 5 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    1 << 20, // 1MB
	}

	// Railway sends SIGTERM on redeploy. Without graceful shutdown, in-flight
	// requests (e.g. a write mid-transaction) are dropped when the process dies.
	go func() {
		log.Printf("Server starting on port %s", port)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	<-stop
	log.Println("Shutdown signal received, draining connections...")

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		log.Printf("Graceful shutdown failed: %v", err)
	}

	database.CloseDB()
	log.Println("Shutdown complete")
}
