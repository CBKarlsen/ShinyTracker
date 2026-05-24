const fs = require('fs');

async function scrape() {
    try {
        const res = await fetch('https://www.serebii.net/scarletviolet/massoutbreaks.shtml');
        const text = await res.text();
        
        // Serebii usually links pokemon like <a href="/pokedex-sv/pikachu/"><img ...></a>
        // Or lists them in tables.
        // Let's use regex to find pokedex links
        const regex = /\/pokedex-sv\/([^/.]+)\//g;
        let match;
        const pokemon = new Set();
        
        while ((match = regex.exec(text)) !== null) {
            pokemon.add(match[1]);
        }
        
        console.log("Found Pokemon:", pokemon.size);
        fs.writeFileSync('serebii_outbreak.json', JSON.stringify(Array.from(pokemon), null, 2));
    } catch (err) {
        console.error(err);
    }
}
scrape();
