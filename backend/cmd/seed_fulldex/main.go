package main

import (
	"context"
	"encoding/csv"
	"fmt"
	"log"
	"os"
	"strings"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

// ── CSV Game → DB Game mapping ───────────────────────────────────────────────
// The CSV uses single-version names; the DB stores combined titles.
var gameTitleMap = map[string]string{
	// Gen 2
	"Pokémon Crystal": "Gold/Silver/Crystal",
	// Gen 3
	"Ruby":    "Ruby/Sapphire/Emerald",
	"Emerald": "Ruby/Sapphire/Emerald",
	// Gen 4
	"Diamond":                   "Diamond/Pearl/Platinum",
	"Pearl":                     "Diamond/Pearl/Platinum",
	"Pokémon Brilliant Diamond": "Brilliant Diamond/Shining Pearl",
	// Gen 6
	"X":          "X/Y",
	"Y":          "X/Y",
	"Omega Ruby": "Omega Ruby/Alpha Sapphire",
	// Gen 7
	"Sun":        "Sun/Moon",
	"Ultra Sun":  "Ultra Sun/Ultra Moon",
	"Ultra Moon": "Ultra Sun/Ultra Moon",
	// Gen 8
	"Pokémon Sword":   "Sword/Shield",
	"Legends: Arceus": "Legends: Arceus",
	"Pokémon GO":      "", // no DB entry for GO — handled specially
	// Gen 9
	"Scarlet": "Scarlet/Violet",
}

// ── CSV Species → DB name normalisation ──────────────────────────────────────
// The DB stores PokeAPI-style names: lowercase, hyphens, no unicode symbols.
// We build a hard-coded override table for the tricky ones and fall back to a
// simple lowercase + space→hyphen rule for everything else.
var nameOverrides = map[string]string{
	"Nidoran♀":         "nidoran-f",
	"Nidoran♂":         "nidoran-m",
	"Farfetch'd":       "farfetchd",
	"Farfetch'd-Galar": "farfetchd", // regional form → base id
	"Mr. Mime":         "mr-mime",
	"Mr. Mime-Galar":   "mr-mime", // regional form → base id
	"Mr. Rime":         "mr-rime",
	"Mime Jr.":         "mime-jr",
	"Ho-Oh":            "ho-oh",
	"Flabébé":          "flabebe",
	"Type: Null":       "type-null",
	"Tapu Koko":        "tapu-koko",
	"Tapu Lele":        "tapu-lele",
	"Tapu Bulu":        "tapu-bulu",
	"Tapu Fini":        "tapu-fini",
	"Sirfetch'd":       "sirfetchd",
	"Jangmo-o":         "jangmo-o",
	"Hakamo-o":         "hakamo-o",
	"Kommo-o":          "kommo-o",
	"Wo-Chien":         "wo-chien",
	"Chien-Pao":        "chien-pao",
	"Ting-Lu":          "ting-lu",
	"Chi-Yu":           "chi-yu",
	// Paradox Pokémon (space → hyphen)
	"Great Tusk":   "great-tusk",
	"Scream Tail":  "scream-tail",
	"Brute Bonnet": "brute-bonnet",
	"Flutter Mane": "flutter-mane",
	"Slither Wing": "slither-wing",
	"Sandy Shocks": "sandy-shocks",
	"Iron Treads":  "iron-treads",
	"Iron Bundle":  "iron-bundle",
	"Iron Hands":   "iron-hands",
	"Iron Jugulis": "iron-jugulis",
	"Iron Moth":    "iron-moth",
	"Iron Thorns":  "iron-thorns",
	"Iron Valiant": "iron-valiant",
	"Roaring Moon": "roaring-moon",
	"Iron Leaves":  "iron-leaves",
	"Walking Wake": "walking-wake",
	"Gouging Fire": "gouging-fire",
	"Raging Bolt":  "raging-bolt",
	"Iron Boulder": "iron-boulder",
	"Iron Crown":   "iron-crown",
}

func normaliseSpecies(csvName string) string {
	if override, ok := nameOverrides[csvName]; ok {
		return override
	}
	// Default: lowercase, replace spaces with hyphens, drop apostrophes/periods
	n := strings.ToLower(csvName)
	n = strings.ReplaceAll(n, "'", "")
	n = strings.ReplaceAll(n, "\u2019", "")
	n = strings.ReplaceAll(n, ".", "")
	n = strings.ReplaceAll(n, " ", "-")
	return n
}

// PokeAPI stores some Pokémon under a default-form suffix.
// CSV says "Thundurus" but the DB has "thundurus-incarnate".
var formSuffixes = map[string]string{
	"thundurus":    "thundurus-incarnate",
	"tornadus":     "tornadus-incarnate",
	"landorus":     "landorus-incarnate",
	"enamorus":     "enamorus-incarnate",
	"keldeo":       "keldeo-ordinary",
	"meloetta":     "meloetta-aria",
	"pyroar":       "pyroar-male",
	"meowstic":     "meowstic-male",
	"aegislash":    "aegislash-shield",
	"pumpkaboo":    "pumpkaboo-average",
	"gourgeist":    "gourgeist-average",
	"zygarde":      "zygarde-50",
	"oricorio":     "oricorio-baile",
	"lycanroc":     "lycanroc-midday",
	"wishiwashi":   "wishiwashi-solo",
	"minior":       "minior-red-meteor",
	"mimikyu":      "mimikyu-disguised",
	"toxtricity":   "toxtricity-amped",
	"eiscue":       "eiscue-ice",
	"indeedee":     "indeedee-male",
	"morpeko":      "morpeko-full-belly",
	"basculegion":  "basculegion-male",
	"oinkologne":   "oinkologne-male",
	"maushold":     "maushold-family-of-four",
	"squawkabilly": "squawkabilly-green-plumage",
	"dudunsparce":  "dudunsparce-two-segment",
	"palafin":      "palafin-zero",
	"tatsugiri":    "tatsugiri-curly",
}

// Regional suffixes that should be stripped to fall back to the base species.
var regionalSuffixes = []string{"-alola", "-galar", "-hisui", "-paldea"}

// resolvePokemonID tries multiple strategies to find the DB id for a CSV species.
func resolvePokemonID(csvSpecies string, pokemonIDs map[string]int) (int, bool) {
	dbName := normaliseSpecies(csvSpecies)

	// 1. Direct match
	if id, ok := pokemonIDs[dbName]; ok {
		return id, true
	}

	// 2. PokeAPI default-form suffix (e.g. thundurus → thundurus-incarnate)
	if formName, ok := formSuffixes[dbName]; ok {
		if id, ok := pokemonIDs[formName]; ok {
			return id, true
		}
	}

	// 3. Strip regional suffix and map to base species
	for _, suffix := range regionalSuffixes {
		if strings.HasSuffix(dbName, suffix) {
			base := strings.TrimSuffix(dbName, suffix)
			if id, ok := pokemonIDs[base]; ok {
				return id, true
			}
			// Base might also need a form suffix
			if formName, ok := formSuffixes[base]; ok {
				if id, ok := pokemonIDs[formName]; ok {
					return id, true
				}
			}
		}
	}

	return 0, false
}

// ── Method derivation ────────────────────────────────────────────────────────
// Returns (method_name, base_rolls, charm_rolls, avg_time_seconds, formula_type).
// The actual hunt method is encoded across Location + Environment columns.
type MethodInfo struct {
	Name        string
	BaseRolls   int
	CharmRolls  int
	AvgTime     int
	FormulaType string
}

func deriveMethod(location, environment string, generation int) MethodInfo {
	loc := strings.ToLower(strings.TrimSpace(location))
	env := strings.ToLower(strings.TrimSpace(environment))

	// ── Starter Pokémon (soft-reset the starter selection) ──
	if strings.Contains(loc, "starter") || strings.Contains(loc, "evolve") {
		return MethodInfo{"Soft Reset", 1, 3, 40, "static"}
	}

	// ── Breeding / Masuda ──
	if env == "masuda method" || strings.Contains(loc, "day care") || strings.Contains(loc, "nursery") || strings.Contains(loc, "picnic") {
		return MethodInfo{"Masuda Method", 6, 8, 45, "static"}
	}

	// ── SV Outbreaks ──
	if env == "sv outbreak" || (strings.Contains(loc, "mass outbreak") && !strings.Contains(env, "massive")) {
		return MethodInfo{"Mass Outbreak", 3, 5, 15, "outbreak_defeats_sv"}
	}

	// ── PLA Massive Mass Outbreaks ──
	if strings.Contains(env, "massive mass outbreak") {
		return MethodInfo{"Massive Mass Outbreak", 12, 25, 20, "static"}
	}

	// ── PokéRadar chains ──
	if strings.Contains(env, "pokeradar") || strings.Contains(env, "poke radar") {
		return MethodInfo{"PokéRadar", 1, 0, 60, "radar_chain_gen4"}
	}

	// ── Dynamax Adventures / Max Raid ──
	if env == "max raid battle" {
		return MethodInfo{"Max Raid Battle", 14, 41, 900, "static"}
	}

	// ── Horde Encounters ──
	if env == "horde" {
		return MethodInfo{"Horde Encounter", 5, 7, 10, "static"}
	}

	// ── SOS Battles (includes "Weather SOS Battle") ──
	if strings.Contains(env, "sos") {
		return MethodInfo{"SOS Battle", 13, 15, 30, "static"}
	}

	// ── Fossil reviving ──
	if strings.Contains(env, "fossil") || strings.Contains(env, "combine fossils") {
		return MethodInfo{"Fossil Soft Reset", 1, 3, 40, "static"}
	}

	// ── Pokédex Completion Gift (Deposit full Dex) ──
	if strings.Contains(env, "deposit full") {
		return MethodInfo{"Pokédex Completion Gift", 1, 1, 0, "static"}
	}

	// ── Gift / interact / event ──
	if env == "interact" || env == "event" {
		return MethodInfo{"Soft Reset", 1, 3, 40, "static"}
	}

	// ── Pokémon GO specifics ──
	if env == "daily adventure incense" || env == "mystery box" {
		return MethodInfo{"Pokémon GO Transfer", 1, 1, 60, "static"}
	}

	// ── Requires legendary combo (e.g. Landorus needs Tornadus+Thundurus) ──
	if strings.Contains(env, "requires") {
		return MethodInfo{"Soft Reset", 1, 3, 40, "static"}
	}

	// ── Roaming encounters ──
	if strings.Contains(env, "roaming") {
		return MethodInfo{"Roaming Soft Reset", 1, 3, 120, "static"}
	}

	// ── Chain Fishing ──
	if strings.Contains(env, "rod") || env == "fish" {
		if generation == 6 {
			return MethodInfo{"Chain Fishing", 1, 2, 15, "chain_fishing_gen6"}
		}
		return MethodInfo{"Random Encounter", 1, 3, 20, "static"}
	}

	// ── Surfing ──
	if env == "surf" {
		return MethodInfo{"Random Encounter", 1, 3, 20, "static"}
	}

	// ── Wimpod special case ──
	if env == "wimpod" {
		return MethodInfo{"Random Encounter", 1, 3, 20, "static"}
	}

	// ── Generic wild encounters (walk, grass, cave, underground, etc.) ──
	if env == "grass" || env == "rock" || env == "cave; underground" ||
		env == "underground" || env == "grass; underground" || env == "lake; swamp" ||
		strings.Contains(env, "walking") {
		return MethodInfo{"Random Encounter", 1, 3, 20, "static"}
	}

	// ── Fallback ──
	return MethodInfo{"Random Encounter", 1, 3, 20, "static"}
}

type gameInfo struct {
	ID         int
	Generation int
}

func main() {
	_ = godotenv.Load()

	if err := database.ConnectDB(); err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	defer database.CloseDB()

	ctx := context.Background()

	// ── Step 1: Truncate existing hunt methods ──────────────────────────────
	log.Println("Truncating hunt_methods table...")
	if _, err := database.DB.Exec(ctx, "TRUNCATE TABLE hunt_methods CASCADE"); err != nil {
		log.Fatal("Failed to truncate hunt_methods:", err)
	}
	log.Println("  ✓ hunt_methods table cleared")

	// ── Step 2: Load Pokémon name → ID map ──────────────────────────────────
	pokemonIDs := make(map[string]int)
	rows, err := database.DB.Query(ctx, "SELECT id, name FROM pokemon")
	if err != nil {
		log.Fatal("Failed to fetch pokemon:", err)
	}
	for rows.Next() {
		var id int
		var name string
		if err := rows.Scan(&id, &name); err == nil {
			pokemonIDs[name] = id
		}
	}
	rows.Close()
	log.Printf("  ✓ loaded %d pokémon from DB", len(pokemonIDs))

	// ── Step 3: Load Game title → ID map ────────────────────────────────────
	gameMap := make(map[string]gameInfo)
	rows2, err := database.DB.Query(ctx, "SELECT id, title, generation FROM games")
	if err != nil {
		log.Fatal("Failed to fetch games:", err)
	}
	for rows2.Next() {
		var id int
		var title string
		var gen int
		if err := rows2.Scan(&id, &title, &gen); err == nil {
			gameMap[title] = gameInfo{ID: id, Generation: gen}
		}
	}
	rows2.Close()
	log.Printf("  ✓ loaded %d games from DB", len(gameMap))

	// For "Any" game rows (Masuda Method), pick Scarlet/Violet as a sensible default
	anyGame, anyGameOK := gameMap["Scarlet/Violet"]

	// ── Step 4: Parse CSV ───────────────────────────────────────────────────
	file, err := os.Open("FullDexMethods.csv")
	if err != nil {
		log.Fatalf("Failed to open CSV: %v", err)
	}
	defer file.Close()

	records, err := csv.NewReader(file).ReadAll()
	if err != nil {
		log.Fatal("Failed to parse CSV:", err)
	}
	log.Printf("  ✓ read %d CSV rows (including header)", len(records))

	// ── Step 5: Insert hunt methods ─────────────────────────────────────────
	var inserted, skipped, locked, noID, noGame int

	for i, row := range records {
		if i == 0 || len(row) < 5 {
			continue // skip header
		}

		species := strings.TrimSpace(row[0])
		targetAs := strings.TrimSpace(row[1])
		csvGame := strings.TrimSpace(row[2])
		location := strings.TrimSpace(row[3])
		environment := strings.TrimSpace(row[4])

		// ── Shiny-locked check ──
		// Rows with "None" in Game or Location are shiny-locked.
		// Also skip rows where Game or Location is completely blank.
		if csvGame == "" || location == "" || csvGame == "None" || location == "None" {
			locked++
			continue
		}

		// ── Resolve Pokémon ID ──
		// First try the Species column directly.
		// If not found, fall back to the Target As column so the encounter
		// is still linked to a valid Pokémon the user can search for.
		pokemonID, ok := resolvePokemonID(species, pokemonIDs)
		if !ok && targetAs != "" && targetAs != species {
			pokemonID, ok = resolvePokemonID(targetAs, pokemonIDs)
		}
		if !ok {
			log.Printf("SKIP  no DB match for species=%q target_as=%q (normalised=%q)",
				species, targetAs, normaliseSpecies(species))
			noID++
			continue
		}

		// ── Resolve Game ID ──
		var targetGame gameInfo
		if csvGame == "Any" {
			if !anyGameOK {
				noGame++
				continue
			}
			targetGame = anyGame
		} else if csvGame == "Pokémon GO" {
			// Skip Pokémon GO rows — no corresponding DB game
			skipped++
			continue
		} else {
			dbTitle, exists := gameTitleMap[csvGame]
			if !exists || dbTitle == "" {
				log.Printf("SKIP  unmapped CSV game=%q for species=%q", csvGame, species)
				noGame++
				continue
			}
			ginfo, gok := gameMap[dbTitle]
			if !gok {
				log.Printf("SKIP  game %q not in DB for species=%q", dbTitle, species)
				noGame++
				continue
			}
			targetGame = ginfo
		}

		// ── Derive method ──
		method := deriveMethod(location, environment, targetGame.Generation)

		// ── Insert (skip duplicates) ──
		tag, err := database.DB.Exec(ctx,
			`INSERT INTO hunt_methods (pokemon_id, game_id, method_name, avg_time_seconds, base_rolls, charm_rolls, formula_type)
			 SELECT $1, $2, $3, $4, $5, $6, $7
			 WHERE NOT EXISTS (
				 SELECT 1 FROM hunt_methods
				 WHERE pokemon_id = $1 AND game_id = $2 AND method_name = $3
			 )`,
			pokemonID, targetGame.ID, method.Name, method.AvgTime, method.BaseRolls, method.CharmRolls, method.FormulaType,
		)
		if err != nil {
			log.Printf("FAIL  pokemon_id=%d game_id=%d method=%q: %v", pokemonID, targetGame.ID, method.Name, err)
			continue
		}

		if tag.RowsAffected() > 0 {
			inserted++
		} else {
			skipped++ // duplicate (same pokemon + game + method)
		}
	}

	fmt.Println()
	fmt.Println("════════════════════════════════════════════════════")
	fmt.Println("  FullDex Method Seeder — Complete")
	fmt.Println("════════════════════════════════════════════════════")
	fmt.Printf("  ✅ Inserted:      %d\n", inserted)
	fmt.Printf("  ⏭  Skipped/Dupes: %d\n", skipped)
	fmt.Printf("  🔒 Shiny-locked:  %d\n", locked)
	fmt.Printf("  ❓ No Pokémon ID: %d\n", noID)
	fmt.Printf("  🎮 No Game Match: %d\n", noGame)
	fmt.Println("════════════════════════════════════════════════════")
}
