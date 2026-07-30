'use strict';

/* Slices the drawing code out of kriegsnacht.html and makes it runnable.
 *
 * kriegsnacht.html is the authority on every pixel in assets/, and it is
 * already committed — so the honest generator is one that reads it at run time
 * rather than one that keeps a copy that can drift. Nothing here is a
 * transliteration: the ancestor's own text is concatenated, six recorded
 * substitutions are applied, and the result is written to a build file that you
 * can open and read.
 *
 * Ranges are located by anchor rather than by hard-coded line number, because
 * the numbers in notes/ have been wrong before. The numbers below are what the
 * anchors resolved to on the date in README.md, and the last line of every
 * range is asserted against its expected text, so a shifted or gutted range is
 * a loud failure rather than silently different art. */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ANCESTOR = path.resolve(__dirname, '..', '..', 'kriegsnacht.html');
const BUNDLE = path.join(__dirname, 'ancestor.generated.js');

/* SHA-256 of the patched, concatenated extraction. It pins the whole pipeline:
 * change the ancestor, the anchors or the patches and this stops matching, and
 * you are told to look before you regenerate art. Print the current value with
 *   node tools/gen/extract.js --report
 * and paste it here once you have read the diff. */
/* Moved once, on 2026-07-29, from
 *   58d4cea3fa5e9a44118d6310ee7c4a1d1b9668499c673a156a4d411f28234af4
 * and NOT because anything in kriegsnacht.html, the anchors or the patches
 * changed — the 961 extracted lines are byte-identical, which `--report` still
 * prints. The hash covers the whole assembled module, and the module's last line
 * is `module.exports = { ... EXPORTS }`; the 8-direction atlas needs `bake`,
 * `outlineSprite` and `ZPAL` reachable, so EXPORTS grew by three names and the
 * hash moved with it. If it ever moves again, assume the ancestor did. */
const EXPECTED_SHA = '62289369199d6d4aaa30171e516eda8e5465ca83fb79633dd649281fe8b2a4a8';

/* Each range runs from the first line matching `start` up to, but not
 * including, the first line at or after it matching `stop`. `stop` is a regex,
 * or a predicate when one regex cannot say it — the art block contains three
 * section dividers of its own, so its stop has to name the one it means.
 * Trailing blank lines are dropped, and `last` is asserted against the final
 * kept line. */
const RANGES = [
	{
		id: 'utils',
		why: 'TAU, clamp/lerp, the RGB packers and the seeded PRNG the art draws through. '
			+ 'Stops before `const reduceMotion`, which calls window.matchMedia and would throw in Node.',
		start: /^const TAU = Math\.PI \* 2;$/,
		stop: /^const reduceMotion\b/,
		last: 'const sr = (a=1,b=0) => b + srnd()*(a-b);',
	},
	{
		id: 'art',
		why: 'Sections 2 and 3 entire: makeCanvas/bake/grain/splotch, every wall, floor, '
			+ 'ceiling and barricade texture, the three zombie palettes and zombieBody, '
			+ 'outlineSprite, the walker/crawler/hound sets, GUNART and drawParts, '
			+ 'makeViewmodel, makeChalk, the perk machines, the box, the generator, the '
			+ 'power-ups, and buildSprites.',
		start: /^function makeCanvas\(w,h\)\{$/,
		stop: (lines, i) => /^\/\* -{20,}$/.test(lines[i]) && /^\s+4\. Weapons$/.test(lines[i + 1] || ''),
		stopDesc: 'the section-4 "Weapons" divider',
		last: '}',
	},
	{
		id: 'weapons',
		why: 'The WEAPONS table, for the plaque labels and the `art` key each plaque draws. '
			+ 'Pure data, no DOM. Cross-checks against scripts/data/weapons.gd.',
		start: /^const W_ = \(o\)=>Object\.assign\(\{$/,
		stop: /^\/\* Pack-a-Punch turns any of them/,
		last: '};',
	},
	{
		id: 'wallbuys',
		why: 'WALLBUYS and BOWIE, for which plaques exist and what each one costs. '
			+ 'Cross-checks against scripts/data/map_data.gd.',
		start: /^const WALLBUYS = \[$/,
		stop: /^const PERKSPOTS = \[$/,
		last: "const BOWIE = {tile:[22,5], face:[1,0], cost:3000};",
	},
	{
		id: 'pap',
		why: 'makePaP. It sits in section 8, seven hundred lines below the rest of the art, '
			+ 'which is why the original export pass — working from the "section 2 and 3" '
			+ 'range — never reached it and assets/props/ has no Pack-a-Punch machine.',
		start: /^function makePaP\(\)\{$/,
		stop: /^function dataToCanvas\(sp\)\{$/,
		last: '}',
	},
];

/* Every one of these replaces a CSS-font text run with the repo's own 5x7
 * bitmap font. `from` must occur exactly once in the concatenated extraction.
 *
 * The ancestor's textAlign/textBaseline lines are deliberately left in place —
 * font5x7.text() reads them off the context exactly as fillText did, so they
 * are still load-bearing and the patched code still says what it means. */
const PATCHES = [
	{
		id: 'chalk-label',
		at: 'html:1256-1257',
		why: "`ui-monospace` is a CSS system keyword with no fixed face; it resolves "
			+ "differently on Windows, macOS and a CI runner, and not at all in Node. "
			+ "Drawn in the 3x5 face because 'BOWIE KNIFE' needs 65px of a 52px plaque "
			+ "in the 5x7 one; maxWidth is the plaque inside its 1px border, so a longer "
			+ "label fails loudly instead of running off the edge.",
		from:
			"    g.font='6px ui-monospace, monospace';\n" +
			"    g.fillText(label.toUpperCase(), W/2, H-14);",
		to: "    FONT.text(g, label.toUpperCase(), W/2, H-14, {px:6, face:'small', maxWidth:W-4});",
	},
	{
		id: 'chalk-cost',
		at: 'html:1259-1260',
		why: 'Same font stack as chalk-label. Stays in the 5x7 face: the price is the '
			+ 'one thing on the plaque meant to be read from across a room, and four '
			+ 'digits of it fit inside 52px with room to spare.',
		from:
			"    g.font='bold 10px ui-monospace, monospace';\n" +
			"    g.fillText(String(cost), W/2, H-4);",
		to: "    FONT.text(g, String(cost), W/2, H-4, {px:10, bold:true, maxWidth:W-4});",
	},
	{
		id: 'perk-letter',
		at: 'html:1283-1288',
		why: 'The Haettenschweiler / "Arial Narrow" / Impact stack picks a different one of '
			+ 'its three fallbacks per platform. Two fillText calls share the one font '
			+ 'assignment, so both move together. `bold` is dropped even though the '
			+ 'ancestor asks for it: at scale 3 the double-stamp is a 6px stroke on a '
			+ '15px glyph, which closes the counters of D, Q and O into blobs — and '
			+ 'Haettenschweiler is an ultra-condensed heavy face where `bold` was close '
			+ 'to a no-op anyway.',
		from:
			"    g.font='bold 30px Haettenschweiler, \"Arial Narrow\", Impact, sans-serif';\n" +
			"    g.textAlign='center'; g.textBaseline='middle';\n" +
			"    g.fillText(d.letter, 22, 32);\n" +
			"    if(lit){\n" +
			"      g.fillStyle='rgba(255,255,255,.30)';\n" +
			"      g.fillText(d.letter, 22, 31);",
		to:
			"    g.textAlign='center'; g.textBaseline='middle';\n" +
			"    FONT.text(g, d.letter, 22, 32, {px:30});\n" +
			"    if(lit){\n" +
			"      g.fillStyle='rgba(255,255,255,.30)';\n" +
			"      FONT.text(g, d.letter, 22, 31, {px:30});",
	},
	{
		id: 'box-question',
		at: 'html:1326-1327',
		why: 'Same stack as perk-letter. globalAlpha .85 still applies — font5x7 draws '
			+ 'through fillRect, which honours it exactly as fillText did.',
		from:
			"    g.fillStyle='#D8D2C0'; g.font='bold 20px Haettenschweiler, \"Arial Narrow\", Impact, sans-serif';\n" +
			"    g.textAlign='center'; g.globalAlpha=.85; g.fillText('?',28,36); g.globalAlpha=1;",
		to:
			"    g.fillStyle='#D8D2C0';\n" +
			"    g.textAlign='center'; g.globalAlpha=.85; FONT.text(g,'?',28,36,{px:20, bold:true}); g.globalAlpha=1;",
	},
	{
		id: 'powerup-x2',
		at: 'html:1426-1427',
		why: 'Same stack as perk-letter. This is the Double Points pickup.',
		from:
			"      g.font='bold 14px Haettenschweiler, \"Arial Narrow\", Impact, sans-serif';\n" +
			"      g.textAlign='center'; g.fillText('X2',14,19);",
		to: "      g.textAlign='center'; FONT.text(g,'X2',14,19,{px:14, bold:true});",
	},
	{
		id: 'pap-label',
		at: 'html:1998-1999',
		why: 'Same `ui-monospace` keyword as the chalk plaques.',
		from:
			"      g.fillStyle='#8FD0FF'; g.font='bold 9px ui-monospace, monospace';\n" +
			"      g.textAlign='center'; g.fillText('PAP',26,33);",
		to:
			"      g.fillStyle='#8FD0FF';\n" +
			"      g.textAlign='center'; FONT.text(g,'PAP',26,33,{px:9, bold:true});",
	},
];

/* Everything targets.js is allowed to reach. Named explicitly so that a
 * rename inside the ancestor fails here rather than three files later as
 * `undefined is not a function`. */
const EXPORTS = [
	'buildTextures', 'T',       // every wall/floor/ceiling/barricade tile
	'buildSprites', 'SPR',      // zombies, crawlers, hounds, machines, power-ups
	'makeChalk', 'makePaP',     // called from boot(), never from buildSprites()
	'PERKDEF', 'POWERDEF',      // the keys the prop filenames are built from
	'WEAPONS', 'WALLBUYS', 'BOWIE',
	// The 8-direction atlas (atlas.js / views.js). `bake` is the canvas harness,
	// `outlineSprite` the 1px rim every silhouette in the game carries, and
	// `ZPAL` the three corpse palettes — all three are the ancestor's and the
	// turned views must draw through them rather than carry a second copy.
	'bake', 'outlineSprite', 'ZPAL',
];


function sliceRange(lines, r) {
	const from = lines.findIndex((l) => r.start.test(l));
	if (from < 0) throw new Error(`extract: range '${r.id}' start anchor ${r.start} not found in kriegsnacht.html`);
	const stops = typeof r.stop === 'function' ? r.stop : (ls, i) => r.stop.test(ls[i]);
	const stopDesc = r.stopDesc || String(r.stop);
	let to = from + 1;
	while (to < lines.length && !stops(lines, to)) to++;
	if (to >= lines.length) throw new Error(`extract: range '${r.id}' stop anchor ${stopDesc} not found after line ${from + 1}`);
	while (to > from + 1 && lines[to - 1].trim() === '') to--;
	const text = lines.slice(from, to);
	const lastLine = text[text.length - 1];
	if (lastLine !== r.last) {
		throw new Error(`extract: range '${r.id}' ends at html:${to} with ${JSON.stringify(lastLine)}, `
			+ `expected ${JSON.stringify(r.last)}. The ancestor moved; re-read it before regenerating art.`);
	}
	return { id: r.id, why: r.why, first: from + 1, last: to, lines: text };
}


/* Reads the ancestor, resolves every range, applies every patch and returns
 * the assembled module source with its provenance. Does not touch disk. */
function assemble() {
	const lines = fs.readFileSync(ANCESTOR, 'utf8').split(/\r?\n/);
	const ranges = RANGES.map((r) => sliceRange(lines, r));

	let body = ranges
		.map((r) => `/* ===== kriegsnacht.html:${r.first}-${r.last} (${r.id}) ===== */\n${r.lines.join('\n')}`)
		.join('\n\n');

	const applied = [];
	for (const p of PATCHES) {
		const hits = body.split(p.from).length - 1;
		if (hits !== 1) {
			throw new Error(`extract: patch '${p.id}' (${p.at}) matched ${hits} times, expected exactly 1. `
				+ 'The ancestor changed under it; re-read that line before regenerating art.');
		}
		body = body.replace(p.from, p.to);
		applied.push(p.id);
	}

	const shim = fs.readFileSync(path.join(__dirname, 'shim.js'), 'utf8');
	const source =
		'/* GENERATED by tools/gen/extract.js — do not edit, do not commit.\n'
		+ ' * Ancestor drawing code sliced out of kriegsnacht.html verbatim, plus the\n'
		+ ' * shim and the recorded font patches. Read it when something looks wrong. */\n'
		+ "'use strict';\n\n"
		+ shim + '\n\n'
		+ body + '\n\n'
		+ `module.exports = { ${EXPORTS.join(', ')} };\n`;

	const sha = crypto.createHash('sha256').update(source).digest('hex');
	return { source, ranges, applied, sha };
}


/* Writes the bundle and requires it. `allowDrift` is for --report, which has to
 * be able to run when the hash is exactly what you are trying to find out. */
function load(allowDrift = false) {
	const a = assemble();
	if (!allowDrift && a.sha !== EXPECTED_SHA) {
		throw new Error(
			'extract: the assembled ancestor code no longer hashes to EXPECTED_SHA.\n'
			+ `  expected ${EXPECTED_SHA}\n`
			+ `  actual   ${a.sha}\n`
			+ 'Something moved in kriegsnacht.html, the anchors or the patches. Run\n'
			+ '  node tools/gen/extract.js --report\n'
			+ 'to see the new ranges, read the diff, then update EXPECTED_SHA in extract.js.');
	}
	fs.writeFileSync(BUNDLE, a.source);
	delete require.cache[require.resolve(BUNDLE)];
	return { anc: require(BUNDLE), meta: a };
}


function report() {
	const a = assemble();
	const lines = fs.readFileSync(ANCESTOR, 'utf8').split(/\r?\n/).length;
	console.log(`kriegsnacht.html — ${fs.statSync(ANCESTOR).size} bytes, ${lines} lines`);
	console.log(`sha256(file)     ${crypto.createHash('sha256').update(fs.readFileSync(ANCESTOR)).digest('hex')}`);
	console.log('');
	console.log('extracted ranges (resolved by anchor, not hard-coded):');
	let total = 0;
	for (const r of a.ranges) {
		total += r.lines.length;
		console.log(`  ${String(r.first).padStart(4)}-${String(r.last).padEnd(4)}  ${String(r.lines.length).padStart(4)} lines  ${r.id}`);
	}
	console.log(`  ${' '.repeat(9)}  ${String(total).padStart(4)} lines  total`);
	console.log('');
	console.log(`patches applied: ${a.applied.join(', ')}`);
	console.log('');
	console.log(`sha256(assembled) ${a.sha}`);
	console.log(a.sha === EXPECTED_SHA ? 'matches EXPECTED_SHA' : '*** DOES NOT match EXPECTED_SHA — read the diff before regenerating art ***');
}


module.exports = { load, assemble, report, RANGES, PATCHES, ANCESTOR, BUNDLE, EXPECTED_SHA };

if (require.main === module) {
	if (process.argv.includes('--report')) report();
	else { load(); console.log(`wrote ${BUNDLE}`); }
}
