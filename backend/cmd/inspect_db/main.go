package main

import (
	"context"
	"fmt"
	"log"
	"strings"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal(err)
	}
	defer database.CloseDB()

	// Check what's in DB for pokemon that were skipped
	bases := []string{
		"thundurus", "keldeo", "meloetta", "pyroar", "meowstic",
		"aegislash", "pumpkaboo", "gourgeist", "zygarde", "oricorio",
		"lycanroc", "wishiwashi", "minior", "mimikyu", "toxtricity",
		"eiscue", "indeedee", "morpeko", "basculegion", "enamorus",
		"oinkologne", "maushold", "squawkabilly", "dudunsparce",
		"palafin", "tatsugiri",
	}

	fmt.Println("=== Form-name Pokemon (base name not found) ===")
	for _, base := range bases {
		rows, _ := database.DB.Query(context.Background(),
			"SELECT id, name FROM pokemon WHERE name LIKE $1 ORDER BY id",
			base+"%")
		found := false
		for rows.Next() {
			var id int
			var name string
			rows.Scan(&id, &name)
			fmt.Printf("  id=%-4d name=%s\n", id, name)
			found = true
		}
		rows.Close()
		if !found {
			fmt.Printf("  ❌ NO MATCH for %q\n", base)
		}
	}

	// Check regional forms
	regionals := []string{"rattata", "raichu", "sandshrew", "vulpix", "diglett",
		"meowth", "geodude", "grimer", "growlithe", "voltorb", "wooper", "tauros"}
	fmt.Println("\n=== Regional form base Pokemon ===")
	for _, base := range regionals {
		rows, _ := database.DB.Query(context.Background(),
			"SELECT id, name FROM pokemon WHERE name LIKE $1 ORDER BY id",
			base+"%")
		for rows.Next() {
			var id int
			var name string
			rows.Scan(&id, &name)
			// Only show if name has a suffix
			if strings.Contains(name, "-") || name == base {
				fmt.Printf("  id=%-4d name=%s\n", id, name)
			}
		}
		rows.Close()
	}
}
