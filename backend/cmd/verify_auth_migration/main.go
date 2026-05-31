// verify_auth_migration — prints schema evidence after the Supabase Auth swap.
// Checks: profiles table exists, users table gone, user_hunts/user_games FKs dropped.
package main

import (
	"context"
	"fmt"
	"log"

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

	ctx := context.Background()

	// 1. profiles table columns
	fmt.Println("=== profiles columns ===")
	rows, err := database.DB.Query(ctx, `
		SELECT column_name, data_type, is_nullable
		FROM information_schema.columns
		WHERE table_schema = 'public' AND table_name = 'profiles'
		ORDER BY ordinal_position`)
	if err != nil {
		log.Fatal(err)
	}
	for rows.Next() {
		var col, dt, nullable string
		rows.Scan(&col, &dt, &nullable)
		fmt.Printf("  %-20s %-20s nullable=%s\n", col, dt, nullable)
	}
	rows.Close()

	// 2. users table — should NOT exist
	fmt.Println("\n=== users table (should be empty result) ===")
	rows2, err := database.DB.Query(ctx, `
		SELECT table_name FROM information_schema.tables
		WHERE table_schema = 'public' AND table_name = 'users'`)
	if err != nil {
		log.Fatal(err)
	}
	found := false
	for rows2.Next() {
		found = true
		fmt.Println("  FOUND (unexpected!)")
	}
	rows2.Close()
	if !found {
		fmt.Println("  (not present — correct)")
	}

	// 3. FK constraints on user_hunts and user_games pointing at users
	fmt.Println("\n=== FK constraints referencing users (should be empty) ===")
	rows3, err := database.DB.Query(ctx, `
		SELECT tc.table_name, tc.constraint_name, ccu.table_name AS foreign_table
		FROM information_schema.table_constraints tc
		JOIN information_schema.referential_constraints rc ON rc.constraint_name = tc.constraint_name
		JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = rc.unique_constraint_name
		WHERE tc.constraint_type = 'FOREIGN KEY'
		  AND tc.table_schema = 'public'
		  AND ccu.table_name = 'users'`)
	if err != nil {
		log.Fatal(err)
	}
	foundFK := false
	for rows3.Next() {
		foundFK = true
		var tbl, con, ftbl string
		rows3.Scan(&tbl, &con, &ftbl)
		fmt.Printf("  FOUND FK: %s.%s → %s\n", tbl, con, ftbl)
	}
	rows3.Close()
	if !foundFK {
		fmt.Println("  (none — correct)")
	}

	// 4. Remaining FK constraints on user_hunts and user_games
	fmt.Println("\n=== FK constraints on user_hunts / user_games ===")
	rows4, err := database.DB.Query(ctx, `
		SELECT tc.table_name, tc.constraint_name, kcu.column_name, ccu.table_name AS ref_table
		FROM information_schema.table_constraints tc
		JOIN information_schema.key_column_usage kcu ON kcu.constraint_name = tc.constraint_name
		JOIN information_schema.referential_constraints rc ON rc.constraint_name = tc.constraint_name
		JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = rc.unique_constraint_name
		WHERE tc.constraint_type = 'FOREIGN KEY'
		  AND tc.table_schema = 'public'
		  AND tc.table_name IN ('user_hunts', 'user_games')
		ORDER BY tc.table_name, tc.constraint_name`)
	if err != nil {
		log.Fatal(err)
	}
	for rows4.Next() {
		var tbl, con, col, ref string
		rows4.Scan(&tbl, &con, &col, &ref)
		fmt.Printf("  %s.%s (%s) → %s\n", tbl, con, col, ref)
	}
	rows4.Close()
}
