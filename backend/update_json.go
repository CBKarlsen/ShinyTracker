//go:build ignore

// Orphaned generator (uses the defunct generation/method_rules model).
// Excluded from `go build ./...`; see FUTUREWORK.md.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"regexp"
	"strings"

	"github.com/casper/shinytracker/internal/database"
	"github.com/joho/godotenv"
)

// Define JSON structures based on existing ones
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

var nameOverrides = map[string]string{
	"Nidoran♀":         "nidoran-f",
	"Nidoran♂":         "nidoran-m",
	"Farfetch'd":       "farfetchd",
	"Mr. Mime":         "mr-mime",
	"Ho-Oh":            "ho-oh",
	"Flabébé":          "flabebe",
	"Great Tusk":       "great-tusk",
	"Scream Tail":      "scream-tail",
	"Brute Bonnet":     "brute-bonnet",
	"Flutter Mane":     "flutter-mane",
	"Slither Wing":     "slither-wing",
	"Sandy Shocks":     "sandy-shocks",
	"Iron Treads":      "iron-treads",
	"Iron Bundle":      "iron-bundle",
	"Iron Hands":       "iron-hands",
	"Iron Jugulis":     "iron-jugulis",
	"Iron Moth":        "iron-moth",
	"Iron Thorns":      "iron-thorns",
	"Iron Valiant":     "iron-valiant",
	"Roaring Moon":     "roaring-moon",
	"Iron Leaves":      "iron-leaves",
	"Walking Wake":     "walking-wake",
	"Gouging Fire":     "gouging-fire",
	"Raging Bolt":      "raging-bolt",
	"Iron Boulder":     "iron-boulder",
	"Iron Crown":       "iron-crown",
}

func normaliseSpecies(csvName string) string {
	if override, ok := nameOverrides[csvName]; ok {
		return override
	}
	n := strings.ToLower(csvName)
	n = strings.ReplaceAll(n, "'", "")
	n = strings.ReplaceAll(n, "\u2019", "")
	n = strings.ReplaceAll(n, ".", "")
	n = strings.ReplaceAll(n, " ", "-")
	return n
}

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

var regionalSuffixes = []string{"-alola", "-galar", "-hisui", "-paldea"}

func resolvePokemonID(csvSpecies string, pokemonIDs map[string]int) (int, bool) {
	dbName := normaliseSpecies(csvSpecies)
	if id, ok := pokemonIDs[dbName]; ok {
		return id, true
	}
	if formName, ok := formSuffixes[dbName]; ok {
		if id, ok := pokemonIDs[formName]; ok {
			return id, true
		}
	}
	for _, suffix := range regionalSuffixes {
		if strings.HasSuffix(dbName, suffix) {
			base := strings.TrimSuffix(dbName, suffix)
			if id, ok := pokemonIDs[base]; ok {
				return id, true
			}
			if formName, ok := formSuffixes[base]; ok {
				if id, ok := pokemonIDs[formName]; ok {
					return id, true
				}
			}
		}
	}
	// special case for paldean tauros
	if csvSpecies == "Tauros" {
		if id, ok := pokemonIDs["tauros-paldea-combat-breed"]; ok {
			return id, true
		}
	}
	return 0, false
}

func parseNames(text string) []string {
	var names []string
	re := regexp.MustCompile(`\(.*?\)`)
	for _, line := range strings.Split(text, "\n") {
		line = re.ReplaceAllString(line, "")
		parts := strings.Split(line, ":")
		for _, name := range strings.Split(parts[0], ",") {
			n := strings.TrimSpace(name)
			if n != "" {
				n = strings.ReplaceAll(n, "Alolan ", "")
				n = strings.ReplaceAll(n, "Paldean ", "")
				if n == "Swadoon" {
					n = "Swadloon"
				}
				names = append(names, n)
			}
		}
	}
	return names
}

func readJSON(file string, v interface{}) {
	b, err := os.ReadFile(file)
	if err != nil {
		log.Fatal(err)
	}
	if err := json.Unmarshal(b, v); err != nil {
		log.Fatal(err)
	}
}

func writeJSON(file string, v interface{}) {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		log.Fatal(err)
	}
	if err := os.WriteFile(file, b, 0644); err != nil {
		log.Fatal(err)
	}
}

func main() {
	_ = godotenv.Load()
	if err := database.ConnectDB(); err != nil {
		log.Fatal(err)
	}
	defer database.CloseDB()
	ctx := context.Background()
	pokemonIDs := make(map[string]int)
	rows, _ := database.DB.Query(ctx, "SELECT id, name FROM pokemon")
	for rows.Next() {
		var id int
		var name string
		rows.Scan(&id, &name)
		pokemonIDs[name] = id
	}
	rows.Close()

	// Parse texts
	paldeaText := `Pichu, Pikachu, Raichu
Igglybuff, Jigglypuff, Wigglytuff
Venonat, Venomoth
Diglett, Dugtrio
Meowth, Persian
Psyduck, Golduck
Mankey, Primeape
Growlithe, Arcanine
Slowpoke, Slowbro
Magnemite, Magneton
Grimer, Muk
Shellder, Cloyster
Gastly, Haunter
Drowzee, Hypno
Voltorb, Electrode
Happiny, Chansey, Blissey
Scyther
Paldean Tauros (Combat, Blaze, and Aqua breeds)
Magikarp, Gyarados
Ditto
Eevee, Vaporeon, Jolteon, Flareon, Espeon, Umbreon, Leafeon, Glaceon
Dratini, Dragonair
Mareep, Flaaffy, Ampharos
Azurill, Marill, Azumarill
Bonsly, Sudowoodo
Hoppip, Skiploom, Jumpluff
Sunflora
Paldean Wooper
Murkrow, Honchkrow
Misdreavus, Mismagius
Girafarig
Pineco, Forretress
Dunsparce
Qwilfish
Heracross
Sneasel, Weavile
Teddiursa, Ursaring
Delibird
Houndour, Houndoom
Phanpy, Donphan
Stantler
Larvitar, Pupitar
Wingull, Pelipper
Ralts, Kirlia, Gardevoir, Gallade
Surskit, Masquerain
Shroomish, Breloom
Slakoth, Vigoroth, Slaking
Makuhita, Hariyama
Sableye
Meditite, Medicham
Gulpin, Swalot
Numel, Camerupt
Torkoal
Spoink, Grumpig
Cacnea, Cacturne
Swablu, Altaria
Zangoose, Seviper
Barboach, Whiscash
Shuppet, Banette
Tropius
Snorunt, Glalie, Froslass
Luvdisc
Bagon, Shelgon
Starly, Staravia, Staraptor
Kricketot, Kricketune
Shinx, Luxio, Luxray
Combee, Vespiquen
Pachirisu
Buizel, Floatzel
Shellos, Gastrodon (West and East Sea variants)
Drifloon, Drifblim
Stunky, Skuntank
Bronzor, Bronzong
Gible, Gabite
Riolu, Lucario
Hippopotas, Hippowdon
Croagunk, Toxicroak
Finneon, Lumineon
Snover, Abomasnow
Rotom
Petilil, Lilligant
Basculin: Red and Blue-Striped forms
Sandile, Krokorok
Zorua, Zoroark
Gothita, Gothorita, Gothitelle
Deerling, Sawsbuck (Spring, Summer, Autumn, Winter forms)
Foongus, Amoonguss
Alomomola
Tynamo, Eelektrik
Axew, Fraxure
Cubchoo, Beartic
Cryogonal
Pawniard, Bisharp
Rufflet, Braviary
Deino, Zweilous
Larvesta, Volcarona
Fletchling, Fletchinder, Talonflame
Scatterbug, Spewpa, Vivillon
Litleo, Pyroar
Flabébé, Floette, Florges (Red, Yellow, Orange, Blue, White flowers)
Skiddo, Gogoat
Pancham, Pangoro
Inkay, Malamar
Skrelp, Dragalge
Clauncher, Clawitzer
Hawlucha
Dedenne
Goomy, Sliggoo, Goodra
Klefki
Phantump, Trevenant
Bergmite, Avalugg
Noibat, Noivern
Yungoos, Gumshoos
Crabrawler, Crabominable
Oricorio: Baile, Pom-Pom, Pa'u, Sensu styles
Rockruff, Lycanroc (Midday, Midnight, Dusk forms)
Mudbray, Mudsdale
Fomantis, Lurantis
Salandit, Salazzle
Bounsweet, Steenee, Tsareena
Oranguru, Passimian
Sandygast, Palossand
Komala
Mimikyu
Bruxish
Skwovet, Greedent
Rookidee, Corvisquire, Corviknight
Dottler, Orbeetle
Chewtle, Drednaw
Rolycoly, Carkol, Coalossal
Applin, Flapple, Appletun
Silicobra, Sandaconda
Arrokuda, Barraskewda
Toxel, Toxtricity (Amped and Low Key forms)
Sizzlipede, Centiskorch
Clobbopus, Grapploct
Sinistea: Phony and Antique forms
Hatenna, Hattrem, Hatterene
Impidimp, Morgrem, Grimmsnarl
Milcery, Alcremie
Falinks
Pincurchin
Snom, Frosmoth
Stonjourner, Eiscue
Indeedee
Cufant, Copperajah
Dreepy, Drakloak, Dragapult
Lechonk, Oinkologne
Tarountula, Spidops
Nymble, Lokix
Pawmi, Pawmo, Pawmot
Tandemaus, Maushold
Fidough, Dachsbun
Smoliv, Dolliv, Arboliva
Squawkabilly (Green, Blue, Yellow, White plumes)
Nacli, Naclstack, Garganacl
Charcadet, Armarouge, Ceruledge
Tadbulb, Bellibolt
Wattrel, Kilowattrel
Maschiff, Mabosstiff
Shroodle, Grafaiai
Bramblin, Brambleghast
Toedscool, Toedscruel
Klawf
Capsakid, Scovillain
Rellor, Rabsca
Flittle, Espathra
Tinkatink, Tinkatuff, Tinkaton
Wiglett, Wugtrio
Bombirdier
Finizen, Palafin
Varoom, Revavroom
Cyclizar
Orthworm
Glimmet, Glimmora
Greavard, Houndstone
Flamigo
Cetoddle, Cetitan
Veluza
Dondozo, Tatsugiri (Curly, Droopy, Stretchy forms)
Kingambit
Frigibax, Arctibax, Baxcalibur`

	kitakamiText := `Ekans, Arbok
Alolan Sandshrew, Alolan Sandslash
Clefairy, Clefable
Vulpix, Ninetales (including Alolan Vulpix and Alolan Ninetales)
Oddish, Gloom, Vileplume, Bellossom
Poliwag, Poliwhirl, Poliwrath, Politoed
Bellsprout, Weepinbell, Victreebel
Alolan Geodude, Alolan Graveler, Alolan Golem
Koffing, Weezing
Munchlax, Snorlax
Sentret, Furret
Hoothoot, Noctowl
Spinarak, Ariados
Aipom, Ambipom
Yanma, Yanmega
Gligar, Gliscor
Swinub, Piloswine, Mamoswine
Poochyena, Mightyena
Lotad, Lombre, Ludicolo
Seedot, Nuzleaf, Shiftry
Volbeat, Illumise
Corphish, Crawdaunt
Feebas, Milotic
Chingling, Chimecho
Timburr, Gurdurr, Conkeldurr
Sewaddle, Swadoon, Leavanny
Ducklett, Swanna
Litwick, Lampent, Chandelure
Mienfoo, Mienshao
Vullaby, Mandibuzz
Phantump, Trevenant
Grubbin, Charjabug, Vikavolt
Cutiefly, Ribombee
Cramorant
Morpeko
Dipplin
Poltchageist, Sinistcha (Counterfeit and Artisan forms)`

	terariumText := `Bulbasaur, Ivysaur, Venusaur
Charmander, Charmeleon, Charizard
Squirtle, Wartortle, Blastoise
Chikorita, Bayleef, Meganium
Cyndaquil, Quilava, Typhlosion
Totodile, Croconaw, Feraligatr
Treecko, Grovyle, Sceptile
Torchic, Combusken, Blaziken
Mudkip, Marshtomp, Swampert
Turtwig, Grotle, Torterra
Chimchar, Monferno, Infernape
Piplup, Prinplup, Empoleon
Snivy, Servine, Serperior
Tepig, Pignite, Emboar
Oshawott, Dewott, Samurott
Chespin, Quilladin, Chesnaught
Fennekin, Braixen, Delphox
Froakie, Frogadier, Greninja
Rowlet, Dartrix, Decidueye
Litten, Torracat, Incineroar
Popplio, Brionne, Primarina
Grookey, Thwackey, Rillaboom
Scorbunny, Raboot, Cinderace
Sobble, Drizzile, Inteleon
Alolan Exeggutor
Tyrogue, Hitmonlee, Hitmonchan, Hitmontop
Rhyhorn, Rhydon, Rhyperior
Horsea, Seadra, Kingdra
Elekid, Electabuzz, Electivire
Magby, Magmar, Magmortar
Lapras
Porygon, Porygon2, Porygon-Z
Chinchou, Lanturn
Snubbull, Granbull
Scizor
Skarmory
Smeargle
Plusle, Minun
Trapinch, Vibrava, Flygon
Beldum, Metang, Metagross
Cranidos, Rampardos
Shieldon, Bastiodon
Blitzle, Zebstrika
Drilbur, Excadrill
Cottonee, Whimsicott
Scraggy, Scrafty
Minccino, Cinccino
Solosis, Duosion, Reuniclus
Joltik, Galvantula
Golett, Golurk
Espurr, Meowstic
Pikipek, Trumbeak, Toucannon
Dewpider, Araquanid
Comfey
Minior: Core colors (Red, Orange, Yellow, Green, Blue, Indigo, Violet)
Duraludon, Archaludon
Kleavor`

	paldeaNames := parseNames(paldeaText)
	kitakamiNames := parseNames(kitakamiText)
	terariumNames := parseNames(terariumText)
	// add Eevee manually just in case
	paldeaNames = append(paldeaNames, "Eevee")

	// Update hunt_methods.json
	var methods []HuntMethod
	readJSON("seeds/hunt_methods.json", &methods)
	var newMethods []HuntMethod
	for _, m := range methods {
		if m.MethodName != "Mass Outbreak" {
			newMethods = append(newMethods, m)
		}
	}
	newMethods = append(newMethods, 
		HuntMethod{Generation: 9, MethodName: "Paldea Mass Outbreak", AvgTimeSeconds: 15, BaseRolls: 1, CharmRolls: 2, FormulaType: "outbreak_defeats_sv", IsRecommended: true},
		HuntMethod{Generation: 9, MethodName: "Kitakami Mass Outbreak", AvgTimeSeconds: 15, BaseRolls: 1, CharmRolls: 2, FormulaType: "outbreak_defeats_sv", IsRecommended: true},
		HuntMethod{Generation: 9, MethodName: "Terarium Mass Outbreak", AvgTimeSeconds: 15, BaseRolls: 1, CharmRolls: 2, FormulaType: "outbreak_defeats_sv", IsRecommended: true},
	)
	writeJSON("seeds/hunt_methods.json", newMethods)

	// Update method_rules.json
	var rules []MethodRule
	readJSON("seeds/method_rules.json", &rules)
	var newRules []MethodRule
	for _, r := range rules {
		if r.MethodName != "Mass Outbreak" {
			newRules = append(newRules, r)
		}
	}
	newRules = append(newRules,
		MethodRule{Generation: 9, MethodName: "Paldea Mass Outbreak", Condition: "always_false"},
		MethodRule{Generation: 9, MethodName: "Kitakami Mass Outbreak", Condition: "always_false"},
		MethodRule{Generation: 9, MethodName: "Terarium Mass Outbreak", Condition: "always_false"},
	)
	writeJSON("seeds/method_rules.json", newRules)

	// Update method_exceptions.json
	var exceptions []MethodException
	readJSON("seeds/method_exceptions.json", &exceptions)
	var newExceptions []MethodException
	for _, e := range exceptions {
		if e.MethodName != "Mass Outbreak" {
			newExceptions = append(newExceptions, e)
		}
	}

	appendExceptions := func(names []string, methodName string) {
		for _, n := range names {
			id, ok := resolvePokemonID(n, pokemonIDs)
			if ok {
				newExceptions = append(newExceptions, MethodException{PokemonID: id, Generation: 9, MethodName: methodName, Include: true})
			} else {
				fmt.Printf("Warning: Could not resolve %s\n", n)
			}
		}
	}
	appendExceptions(paldeaNames, "Paldea Mass Outbreak")
	appendExceptions(kitakamiNames, "Kitakami Mass Outbreak")
	appendExceptions(terariumNames, "Terarium Mass Outbreak")
	writeJSON("seeds/method_exceptions.json", newExceptions)
}
