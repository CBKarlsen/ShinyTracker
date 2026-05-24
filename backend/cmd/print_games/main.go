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
		log.Println("No .env file found")
	}
	if err := database.ConnectDB(); err != nil {
		log.Fatal(err)
	}
	defer database.CloseDB()
	rows, err := database.DB.Query(context.Background(), "SELECT id, title, generation FROM games")
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var id, gen int
		var title string
		rows.Scan(&id, &title, &gen)
		fmt.Printf("%d: %s (Gen %d)\n", id, title, gen)
	}
}
