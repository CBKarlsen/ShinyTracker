// audit_methods reports the health of method_availability by checking the INPUT
// tables that derive it (pokemon_game_encounter, method_games, hunt_methods,
// pokemon_availability) rather than eyeballing the derived rows themselves.
//
// Usage:
//
//	go run ./cmd/audit_methods            # full health report
//	go run ./cmd/audit_methods -pokemon 147   # per-game method breakdown for one Pokemon
//
// A wrong method on a Pokemon is always a symptom of a wrong input row; this tool
// points at the likely culprit instead of making you scan thousands of rows.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"text/tabwriter"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

func main() {
	pokemonID := flag.Int("pokemon", 0, "show the per-game method breakdown for a single Pokemon id")
	flag.Parse()

	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database: ", err)
	}
	defer database.CloseDB()
	ctx := context.Background()

	if *pokemonID != 0 {
		dumpPokemon(ctx, *pokemonID)
		return
	}
	healthReport(ctx)
}

// dumpPokemon is the enriched version of the manual "which methods does this
// Pokemon get, and why" query — it also shows the encounter kind/terrain backing
// each method, so a wrong row is traceable to its source.
func dumpPokemon(ctx context.Context, id int) {
	var name string
	if err := database.DB.QueryRow(ctx, `SELECT name FROM pokemon WHERE id = $1`, id).Scan(&name); err != nil {
		log.Fatalf("no pokemon with id %d: %v", id, err)
	}
	fmt.Printf("== #%d %s ==\n\n", id, name)

	fmt.Println("Methods available (and the encounter row that justifies each):")
	tw := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "game\tgen\tmethod\trequires_kind\trequires_terrain\tbacking encounter")
	rows, err := database.DB.Query(ctx, `
		SELECT g.title, g.generation, hm.method_name, hm.requires_kind,
		       COALESCE(hm.requires_terrain, '(any)') AS req_terrain,
		       COALESCE(pge.kind || '/' || pge.terrain, '** NONE **') AS backing
		FROM method_availability ma
		JOIN hunt_methods hm ON hm.id = ma.method_id
		JOIN games g ON g.id = ma.game_id
		LEFT JOIN pokemon_game_encounter pge
			ON pge.pokemon_id = ma.pokemon_id AND pge.game_id = ma.game_id
			AND pge.kind = hm.requires_kind
			AND (hm.requires_terrain IS NULL OR pge.terrain = hm.requires_terrain)
		WHERE ma.pokemon_id = $1
		ORDER BY g.generation, g.title, hm.method_name`, id)
	if err != nil {
		log.Fatal(err)
	}
	printTable(tw, rows)
	tw.Flush()

	fmt.Println("\nRaw encounter rows for this Pokemon (the source of truth):")
	tw = tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "game\tgen\tkind\tterrain")
	rows, err = database.DB.Query(ctx, `
		SELECT g.title, g.generation, pge.kind, pge.terrain
		FROM pokemon_game_encounter pge
		JOIN games g ON g.id = pge.game_id
		WHERE pge.pokemon_id = $1
		ORDER BY g.generation, g.title, pge.kind, pge.terrain`, id)
	if err != nil {
		log.Fatal(err)
	}
	printTable(tw, rows)
	tw.Flush()
}

func healthReport(ctx context.Context) {
	fmt.Println("================ METHOD AVAILABILITY HEALTH REPORT ================")

	fmt.Println("\n--- Scale ---")
	scale := map[string]string{
		"pokemon":                "SELECT COUNT(*) FROM pokemon",
		"games":                  "SELECT COUNT(*) FROM games",
		"hunt_methods":           "SELECT COUNT(*) FROM hunt_methods",
		"pokemon_availability":   "SELECT COUNT(*) FROM pokemon_availability",
		"pokemon_game_encounter": "SELECT COUNT(*) FROM pokemon_game_encounter",
		"method_availability":    "SELECT COUNT(*) FROM method_availability",
		"method_exceptions":      "SELECT COUNT(*) FROM method_exceptions",
	}
	tw := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	for _, k := range []string{"pokemon", "games", "hunt_methods", "pokemon_availability", "pokemon_game_encounter", "method_availability", "method_exceptions"} {
		fmt.Fprintf(tw, "%s\t%d\n", k, count(ctx, scale[k]))
	}
	tw.Flush()

	// A. Legally available but zero huntable methods. Many are evolution-only
	// (you hunt the pre-evolution), but large per-game counts flag whole games
	// with missing wild-encounter data (PokeAPI gap for Gen 1/2/5).
	fmt.Printf("\n--- A. Available but NO method (total %d) — likely missing wild data ---\n",
		count(ctx, `SELECT COUNT(*) FROM pokemon_availability pa WHERE NOT EXISTS (
			SELECT 1 FROM method_availability ma WHERE ma.pokemon_id=pa.pokemon_id AND ma.game_id=pa.game_id)`))
	tw = tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "game\tgen\tmissing\tof_available\twild_rows_in_game")
	printTable(tw, query(ctx, `
		SELECT g.title, g.generation,
		  COUNT(*) FILTER (WHERE NOT EXISTS (
			SELECT 1 FROM method_availability ma WHERE ma.pokemon_id=pa.pokemon_id AND ma.game_id=pa.game_id)) AS missing,
		  COUNT(*) AS of_available,
		  (SELECT COUNT(*) FROM pokemon_game_encounter pge WHERE pge.game_id=g.id AND pge.kind='wild') AS wild_rows
		FROM pokemon_availability pa JOIN games g ON g.id=pa.game_id
		GROUP BY g.id, g.title, g.generation ORDER BY missing DESC`))
	tw.Flush()

	// B. Huntable but not legally available — contradictory by definition.
	// Causes: encounter rows mislabeled (e.g. fossils marked 'wild') or holes
	// in pokemon_availability. Small and worth fixing one by one.
	fmt.Printf("\n--- B. Huntable but NOT legally available (total %d pairs) — REAL inconsistencies ---\n",
		count(ctx, `SELECT COUNT(DISTINCT (ma.pokemon_id, ma.game_id)) FROM method_availability ma
			WHERE NOT EXISTS (SELECT 1 FROM pokemon_availability pa WHERE pa.pokemon_id=ma.pokemon_id AND pa.game_id=ma.game_id)`))
	tw = tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "game\tid\tname\tbacking_kinds")
	printTable(tw, query(ctx, `
		SELECT g.title, ma.pokemon_id, p.name, string_agg(DISTINCT pge.kind, ',') AS kinds
		FROM method_availability ma
		JOIN games g ON g.id=ma.game_id JOIN pokemon p ON p.id=ma.pokemon_id
		LEFT JOIN pokemon_game_encounter pge ON pge.pokemon_id=ma.pokemon_id AND pge.game_id=ma.game_id
		WHERE NOT EXISTS (SELECT 1 FROM pokemon_availability pa WHERE pa.pokemon_id=ma.pokemon_id AND pa.game_id=ma.game_id)
		GROUP BY g.title, ma.pokemon_id, p.name ORDER BY g.title, ma.pokemon_id`))
	tw.Flush()

	// C. Orphaned availability rows: derived methods with no backing encounter.
	// This should always be 0 — the seed asserts it as an invariant.
	orphans := count(ctx, `
		SELECT COUNT(*) FROM method_availability ma
		JOIN hunt_methods hm ON hm.id=ma.method_id
		LEFT JOIN pokemon_game_encounter pge ON pge.pokemon_id=ma.pokemon_id AND pge.game_id=ma.game_id
			AND pge.kind=hm.requires_kind AND (hm.requires_terrain IS NULL OR pge.terrain=hm.requires_terrain)
		WHERE pge.pokemon_id IS NULL`)
	fmt.Printf("\n--- C. Orphan availability rows (must be 0): %d ---\n", orphans)

	// D. Encounter-kind/terrain distribution — sanity on the riskiest input.
	fmt.Println("\n--- D. pokemon_game_encounter by kind/terrain ---")
	tw = tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "kind\tterrain\trows")
	printTable(tw, query(ctx, `SELECT kind, terrain, COUNT(*) FROM pokemon_game_encounter GROUP BY kind, terrain ORDER BY kind, terrain`))
	tw.Flush()

	fmt.Println("\nTip: drill into any Pokemon with  go run ./cmd/audit_methods -pokemon <id>")
}

func count(ctx context.Context, q string) int {
	var n int
	if err := database.DB.QueryRow(ctx, q).Scan(&n); err != nil {
		log.Fatalf("query failed: %v\n%s", err, q)
	}
	return n
}

func query(ctx context.Context, q string) pgxRows {
	rows, err := database.DB.Query(ctx, q)
	if err != nil {
		log.Fatalf("query failed: %v\n%s", err, q)
	}
	return rows
}

// pgxRows is the minimal surface we use, so we don't import pgx directly here.
type pgxRows interface {
	Next() bool
	Values() ([]any, error)
	Close()
}

func printTable(tw *tabwriter.Writer, rows pgxRows) {
	defer rows.Close()
	for rows.Next() {
		vals, _ := rows.Values()
		for i, v := range vals {
			if i > 0 {
				fmt.Fprint(tw, "\t")
			}
			fmt.Fprintf(tw, "%v", v)
		}
		fmt.Fprintln(tw)
	}
}
