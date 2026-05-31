// migrate_supabase_auth — applies 008_add_profiles.sql and
// 009_drop_users_fks.sql against the DATABASE_URL from .env.
// Run once; idempotent (safe to re-run).
package main

import (
	"context"
	"log"
	"os"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(".env"); err != nil {
		log.Println("No .env file found, relying on environment")
	}
	if err := database.ConnectDB(); err != nil {
		log.Fatal(err)
	}
	defer database.CloseDB()

	migrations := []string{
		"migrations/008_add_profiles.sql",
		"migrations/009_drop_users_fks.sql",
	}

	for _, path := range migrations {
		sql, err := os.ReadFile(path)
		if err != nil {
			log.Fatalf("read %s: %v", path, err)
		}
		if _, err := database.DB.Exec(context.Background(), string(sql)); err != nil {
			log.Fatalf("apply %s: %v", path, err)
		}
		log.Printf("applied %s", path)
	}
	log.Println("migrations done")
}
