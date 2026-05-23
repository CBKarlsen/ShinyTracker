import csv
import re

paldea_text = """Pichu, Pikachu, Raichu
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
Frigibax, Arctibax, Baxcalibur"""

kitakami_text = """Ekans, Arbok
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
Poltchageist, Sinistcha (Counterfeit and Artisan forms)"""

terarium_text = """Bulbasaur, Ivysaur, Venusaur
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
Kleavor"""

def parse_names(text):
    names = set()
    for line in text.split('\n'):
        # remove parentheses and text after colons
        line = re.sub(r'\(.*?\)', '', line)
        parts = line.split(':')
        line = parts[0]
        for name in line.split(','):
            n = name.strip()
            if n:
                if 'Alolan ' in n:
                    n = n.replace('Alolan ', '')
                if 'Paldean ' in n:
                    n = n.replace('Paldean ', '')
                if ' forms' in n or ' breeds' in n or ' styles' in n:
                    pass
                if n == 'Swadoon': # typo in prompt
                    n = 'Swadloon'
                names.add(n)
    return names

paldea = parse_names(paldea_text)
kitakami = parse_names(kitakami_text)
terarium = parse_names(terarium_text)

# Also check for Eevee & Evolutions
paldea.add('Eevee')

rows = []
with open('/Users/casper/Fritidsprosjekt/ShinyTracker/backend/FullDexMethods.csv', 'r') as f:
    reader = csv.reader(f)
    for row in reader:
        if len(row) > 4:
            species = row[0]
            game = row[2]
            loc = row[3]
            env = row[4]
            if game == 'Scarlet' and loc == 'Mass Outbreaks' and env == 'SV Outbreak':
                if species in paldea:
                    row[3] = 'Paldea: Mass Outbreaks'
                elif species in kitakami:
                    row[3] = 'Kitakami: Mass Outbreaks'
                elif species in terarium:
                    row[3] = 'Terarium: Mass Outbreaks'
        rows.append(row)

with open('/Users/casper/Fritidsprosjekt/ShinyTracker/backend/FullDexMethods.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(rows)

print(f"Paldea targets: {len(paldea)}")
print(f"Kitakami targets: {len(kitakami)}")
print(f"Terarium targets: {len(terarium)}")

