// One-off script: extracts NUZ_TIMELINE out of the owner's design prototype
// (docs/design/hunt-prototype.dc.html) and writes backend/seeds/nuzlocke_platinum.json.
//
//   node scripts/extract_nuzlocke_seed.js ../docs/design/hunt-prototype.dc.html
// Run this instead of hand-transcribing the prototype's data so the seed can
// never silently drift from the source of truth.
//
//   node extract_nuzlocke_seed.js ../docs/design/hunt-prototype.dc.html
//
// The prototype's NUZ_TIMELINE is a JS array literal, not JSON (unquoted
// keys, single quotes), so this evaluates the literal slice of source in a
// sandboxed vm context and re-emits it as clean JSON shaped for
// cmd/seed_nuzlocke.
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const srcPath = process.argv[2];
if (!srcPath) {
    console.error('usage: node extract_nuzlocke_seed.js <path-to-hunt-prototype.dc.html>');
    process.exit(1);
}
const html = fs.readFileSync(srcPath, 'utf8');

// Pulls out the RHS expression of `const NAME = <expr>;` by walking bracket/
// brace/paren depth and string state to the statement-terminating `;` at
// depth 0 — a plain indexOf(';') would stop at the first `;` inside a nested
// object, which NUZ_TIMELINE has plenty of.
function extractConst(name) {
    const startMarker = `const ${name} = `;
    const start = html.indexOf(startMarker);
    if (start === -1) throw new Error(`${name} not found in ${srcPath}`);
    const exprStart = start + startMarker.length;
    let depth = 0, i = exprStart, inStr = null;
    for (; i < html.length; i++) {
        const c = html[i];
        if (inStr) {
            if (c === '\\') { i++; continue; }
            if (c === inStr) inStr = null;
            continue;
        }
        if (c === "'" || c === '"' || c === '`') { inStr = c; continue; }
        if (c === '[' || c === '{' || c === '(') depth++;
        else if (c === ']' || c === '}' || c === ')') depth--;
        else if (c === ';' && depth === 0) break;
    }
    return html.slice(exprStart, i);
}

const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(`NUZ_TIMELINE = ${extractConst('NUZ_TIMELINE')};`, sandbox);

// Reshape prototype's {k, kind:'loc'|'boss', ...} rows into the schema shape
// cmd/seed_nuzlocke expects: explicit sort_order (the prototype relies on
// array order only) and pokemon_id/type/power field names matching the DB
// columns instead of the prototype's terse id/n/t/p.
const entries = sandbox.NUZ_TIMELINE.map((e, i) => {
    const sortOrder = i + 1;
    if (e.kind === 'loc') {
        return { slug: e.k, kind: 'location', sort_order: sortOrder, name: e.name, encounters: e.enc };
    }
    if (e.kind === 'boss') {
        const squad = (e.squad || []).map((sq, j) => ({
            pokemon_id: sq.id,
            level: sq.lv,
            ability: sq.ability,
            sort_order: j + 1,
            moves: sq.moves.map((mv, k) => ({ name: mv.n, type: mv.t, power: mv.p || 0, sort_order: k + 1 })),
        }));
        return {
            slug: e.k, kind: 'boss', sort_order: sortOrder, name: e.name,
            boss_title: e.boss, place: e.place, level_cap: e.cap, squad,
        };
    }
    throw new Error(`unknown timeline entry kind ${e.kind} for ${e.k}`);
});

const out = { game: 'Diamond/Pearl/Platinum', entries };
// Resolved against backend/, not this script's directory, so the script stays
// relocatable — it lives in backend/scripts/ but writes to backend/seeds/.
const outPath = path.join(__dirname, '..', 'seeds', 'nuzlocke_platinum.json');
fs.writeFileSync(outPath, JSON.stringify(out, null, 2) + '\n');

const locs = entries.filter(e => e.kind === 'location').length;
const bosses = entries.filter(e => e.kind === 'boss').length;
console.log(`Wrote ${outPath}: ${locs} locations, ${bosses} bosses, ` +
    `${entries.reduce((n, e) => n + (e.squad || []).length, 0)} squad members, ` +
    `${entries.reduce((n, e) => n + (e.encounters || []).length, 0)} encounter-pool rows.`);
