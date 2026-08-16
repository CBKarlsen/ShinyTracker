package database

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

var DB *pgxpool.Pool

// ConnectDB initializes the database connection pool using the DATABASE_URL environment variable
func ConnectDB() error {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		return fmt.Errorf("DATABASE_URL environment variable is not set")
	}

	config, err := pgxpool.ParseConfig(dbURL)
	if err != nil {
		return fmt.Errorf("failed to parse database config: %w", err)
	}
	config.MaxConns = 10
	// Supabase pauses/restores regularly; a restore can leave pooled connections
	// half-dead (they error with EMAXCONNSESSION or similar instead of closing
	// cleanly). Recycling and periodically health-checking connections means the
	// pool self-heals within ~30s instead of serving errors until every conn is
	// naturally replaced.
	config.MaxConnLifetime = 10 * time.Minute
	config.HealthCheckPeriod = 30 * time.Second

	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}

	// Supabase pause/restore can take the DB down for a stretch of the Railway
	// deploy window; retry with backoff instead of crash-looping the container
	// on the first failed ping.
	const maxAttempts = 5
	backoff := 1 * time.Second
	for attempt := 1; attempt <= maxAttempts; attempt++ {
		err = pool.Ping(context.Background())
		if err == nil {
			break
		}
		if attempt == maxAttempts {
			return fmt.Errorf("failed to ping database after %d attempts: %w", maxAttempts, err)
		}
		log.Printf("database ping failed (attempt %d/%d): %v; retrying in %s", attempt, maxAttempts, err, backoff)
		time.Sleep(backoff)
		backoff *= 2
	}

	log.Println("Successfully connected to the database")
	DB = pool
	return nil
}

// CloseDB closes the database connection pool
func CloseDB() {
	if DB != nil {
		DB.Close()
	}
}
