package main

import (
	"context"
	"fmt"
	"log"
	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load(".env")
	if err := database.ConnectDB(); err != nil {
		log.Fatal(err)
	}
	defer database.CloseDB()

	rows, err := database.DB.Query(context.Background(), `
		SELECT hm.method_name 
		FROM method_availability ma
		JOIN hunt_methods hm ON ma.method_id = hm.id
		WHERE ma.pokemon_id = 4 AND ma.generation = 9
	`)
	if err != nil {
		log.Fatal(err)
	}
	for rows.Next() {
		var name string
		rows.Scan(&name)
		fmt.Println("Available:", name)
	}
	rows.Close()
}
