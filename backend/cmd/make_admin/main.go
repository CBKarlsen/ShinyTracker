package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load(".env")
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		log.Fatal("DATABASE_URL must be set")
	}

	conn, err := pgx.Connect(context.Background(), dbURL)
	if err != nil {
		log.Fatalf("Unable to connect to database: %v\n", err)
	}
	defer conn.Close(context.Background())

	res, err := conn.Exec(context.Background(), "UPDATE users SET is_admin = true WHERE username = 'pw_suite'")
	if err != nil {
		log.Fatalf("Failed to execute query: %v\n", err)
	}

	fmt.Printf("Successfully updated user: %v rows affected\n", res.RowsAffected())
}
