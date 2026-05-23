package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

type HuntMethod struct {
	Generation     int    `json:"generation"`
	MethodName     string `json:"method_name"`
	AvgTimeSeconds int    `json:"avg_time_seconds"`
	BaseRolls      int    `json:"base_rolls"`
	CharmRolls     int    `json:"charm_rolls"`
	FormulaType    string `json:"formula_type"`
	IsRecommended  bool   `json:"is_recommended"`
}

type MethodRule struct {
	Generation int    `json:"generation"`
	MethodName string `json:"method_name"`
	Condition  string `json:"condition"`
}

type MethodException struct {
	PokemonID  int    `json:"pokemon_id"`
	Generation int    `json:"generation"`
	MethodName string `json:"method_name"`
	Include    bool   `json:"include"`
}

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	ctx := context.Background()

	file, err := os.Open("FullDexMethods.csv")
	if err != nil {
		log.Fatal("Failed to open FullDexMethods.csv: ", err)
	}
	defer file.Close()

	log.Println("Wiping old method data...")
	// We need to cascade delete, which will also delete user_hunts using these methods.
	_, err = database.DB.Exec(ctx, `TRUNCATE TABLE hunt_methods, method_rules, method_exceptions, method_availability CASCADE`)
	if err != nil {
		log.Fatal("Failed to truncate tables: ", err)
	}

	log.Println("Seeding hunt_methods...")
	seedMethods(ctx)

	log.Println("Seeding method_rules...")
	seedRules(ctx)

	log.Println("Seeding method_exceptions...")
	seedExceptions(ctx)

	log.Println("Computing method_availability...")
	computeAvailability(ctx)
	
	log.Println("Seeding complete.")
}

func seedMethods(ctx context.Context) {
	data, err := os.ReadFile("seeds/hunt_methods.json")
	if err != nil {
		log.Fatal("Failed to read hunt_methods.json: ", err)
	}
	var methods []HuntMethod
	if err := json.Unmarshal(data, &methods); err != nil {
		log.Fatal("JSON parse error: ", err)
	}

	for _, m := range methods {
		_, err := database.DB.Exec(ctx,
			`INSERT INTO hunt_methods (generation, method_name, avg_time_seconds, base_rolls, charm_rolls, formula_type, is_recommended)
			 VALUES ($1, $2, $3, $4, $5, $6, $7)`,
			m.Generation, m.MethodName, m.AvgTimeSeconds, m.BaseRolls, m.CharmRolls, m.FormulaType, m.IsRecommended,
		)
		if err != nil {
			log.Fatalf("Failed to insert method %s in gen %d: %v", m.MethodName, m.Generation, err)
		}
	}
}

func seedRules(ctx context.Context) {
	data, err := os.ReadFile("seeds/method_rules.json")
	if err != nil {
		log.Fatal("Failed to read method_rules.json: ", err)
	}
	var rules []MethodRule
	if err := json.Unmarshal(data, &rules); err != nil {
		log.Fatal("JSON parse error: ", err)
	}

	for _, r := range rules {
		var methodID int
		err := database.DB.QueryRow(ctx, "SELECT id FROM hunt_methods WHERE generation = $1 AND method_name = $2", r.Generation, r.MethodName).Scan(&methodID)
		if err != nil {
			log.Fatalf("Failed to find method %s in gen %d for rule: %v", r.MethodName, r.Generation, err)
		}

		_, err = database.DB.Exec(ctx,
			`INSERT INTO method_rules (method_id, generation, condition) VALUES ($1, $2, $3)`,
			methodID, r.Generation, r.Condition,
		)
		if err != nil {
			log.Fatalf("Failed to insert rule %s: %v", r.Condition, err)
		}
	}
}

func seedExceptions(ctx context.Context) {
	data, err := os.ReadFile("seeds/method_exceptions.json")
	if err != nil {
		log.Fatal("Failed to read method_exceptions.json: ", err)
	}
	var exceptions []MethodException
	if err := json.Unmarshal(data, &exceptions); err != nil {
		log.Fatal("JSON parse error: ", err)
	}

	for _, e := range exceptions {
		var methodID int
		err := database.DB.QueryRow(ctx, "SELECT id FROM hunt_methods WHERE generation = $1 AND method_name = $2", e.Generation, e.MethodName).Scan(&methodID)
		if err != nil {
			log.Fatalf("Failed to find method %s in gen %d for exception: %v", e.MethodName, e.Generation, err)
		}

		_, err = database.DB.Exec(ctx,
			`INSERT INTO method_exceptions (pokemon_id, method_id, generation, include) VALUES ($1, $2, $3, $4)`,
			e.PokemonID, methodID, e.Generation, e.Include,
		)
		if err != nil {
			log.Fatalf("Failed to insert exception for pokemon %d: %v", e.PokemonID, err)
		}
	}
}

func computeAvailability(ctx context.Context) {
	// First, apply all rules that evaluate to true
	_, err := database.DB.Exec(ctx, `
		INSERT INTO method_availability (pokemon_id, method_id, generation)
		SELECT p.id, r.method_id, r.generation
		FROM pokemon p
		JOIN method_rules r ON 
			(r.condition = 'always_true') OR
			(r.condition = 'is_breedable' AND p.can_breed = true)
		ON CONFLICT DO NOTHING
	`)
	if err != nil {
		log.Fatal("Failed to insert rule-based availability: ", err)
	}

	// Apply positive exceptions
	_, err = database.DB.Exec(ctx, `
		INSERT INTO method_availability (pokemon_id, method_id, generation)
		SELECT pokemon_id, method_id, generation FROM method_exceptions WHERE include = true
		ON CONFLICT DO NOTHING
	`)
	if err != nil {
		log.Fatal("Failed to insert positive exceptions: ", err)
	}

	// Apply negative exceptions
	_, err = database.DB.Exec(ctx, `
		DELETE FROM method_availability ma
		USING method_exceptions me
		WHERE ma.pokemon_id = me.pokemon_id AND ma.method_id = me.method_id AND ma.generation = me.generation AND me.include = false
	`)
	if err != nil {
		log.Fatal("Failed to apply negative exceptions: ", err)
	}
	
	var count int
	database.DB.QueryRow(ctx, "SELECT COUNT(*) FROM method_availability").Scan(&count)
	fmt.Printf("Inserted %d availability records.\n", count)
}

