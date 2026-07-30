'use strict';

/* The manifest: every PNG this project's art pipeline can produce, and where
 * in assets/ it belongs.
 *
 * Names match the committed filenames exactly, because half the point of the
 * package is being able to ask "does olympia's plaque still come out the same"
 * and get an answer. The animation strips are laid out the way
 * scripts/world/sprite_lib.gd reads them: one row, frames left to right, cell
 * size from SPEC there. */

const extract = require('./extract.js');
const atlas = require('./atlas.js');

/* Cell counts per strip, asserted rather than assumed. sprite_lib.gd's SPEC
 * hard-codes these and slices AtlasTexture regions off them, so a frame count
 * that drifts here shows up in-game as a blank or duplicated animation frame
 * rather than as an error. */
const STRIPS = [
	{ set: 'zombie', anims: { walk: 6, attack: 2, death: 4 }, palettes: 3 },
	{ set: 'crawler', anims: { walk: 4, death: 3 }, palettes: 3 },
	{ set: 'hound', anims: { walk: 4, death: 3 }, palettes: 0 },
];


/* The ancestor's bake() returns {w,h,data} where data is a Uint32Array aliased
 * onto an ImageData buffer — which on little-endian hardware is already the
 * byte order a PNG scanline wants, so this is a view, not a conversion. */
function bytes(sprite) {
	return Buffer.from(sprite.data.buffer, sprite.data.byteOffset, sprite.data.length * 4);
}


/* Lays frames out left to right into one strip, which is the only layout
 * sprite_lib.gd knows how to read. */
function strip(frames, expected, label) {
	if (frames.length !== expected) {
		throw new Error(`targets: ${label} has ${frames.length} frames, sprite_lib.gd expects ${expected}`);
	}
	const h = frames[0].h, cw = frames[0].w;
	const w = cw * frames.length;
	const out = Buffer.alloc(w * h * 4);
	frames.forEach((f, i) => {
		if (f.w !== cw || f.h !== h) throw new Error(`targets: ${label} frame ${i} is ${f.w}x${f.h}, expected ${cw}x${h}`);
		const src = bytes(f);
		for (let y = 0; y < h; y++) {
			src.copy(out, (y * w + i * cw) * 4, y * cw * 4, (y + 1) * cw * 4);
		}
	});
	return { w, h, rgba: out };
}


function single(sprite) {
	return { w: sprite.w, h: sprite.h, rgba: bytes(sprite) };
}


/* Runs the ancestor's own boot sequence and returns every target keyed by
 * filename stem. buildTextures() then buildSprites() is the order boot() uses
 * at html:3416-3417; both reseed _seed themselves (html:602, html:1440), so the
 * output does not depend on which subset you ask for. */
/* Perks the ancestor never had, drawn by the machine the ancestor DOES have.
 *
 * `makePerkMachine(k)` (html:1271-1307) reads nothing but `PERKDEF[k]` — two
 * colours and a letter — so a cabinet for a new perk is a data row rather than
 * new drawing code, and injecting the row before `buildSprites()` puts it through
 * the ancestor's own brush, palette and 5x7 letter. That is the difference
 * between extending the pipeline and forging provenance: the ART is the
 * ancestor's, the ROW is the port's, and the note on each target says so.
 *
 * These must agree with scripts/data/weapons.gd's PERKDEF or the cabinet in the
 * Generator Hall is a different colour from the badge on the HUD. */
const PORT_PERKS = {
	stamin: { name: 'Stamin-Up', cost: 2000, col: '#D8C33C', col2: '#6B5F12', letter: 'U', blurb: 'run further, walk quicker' },
	mule: { name: 'Mule Kick', cost: 4000, col: '#A2571F', col2: '#4A2409', letter: 'M', blurb: 'carry a third weapon' },
};


function build() {
	const { anc, meta } = extract.load();
	for (const [k, d] of Object.entries(PORT_PERKS)) {
		if (!anc.PERKDEF[k]) anc.PERKDEF[k] = d;
	}
	anc.buildTextures();
	anc.buildSprites();

	const t = new Map();
	const add = (name, dir, img, note) => t.set(name, { name, dir, note, ...img });

	// ---- textures: 7 wall + 4 floor + 4 ceiling, then the barricade ladder ----
	for (const k of ['concrete', 'wood', 'brick', 'metal', 'tile', 'door', 'debris',
		'carpet', 'cement', 'cobble', 'grate', 'plaster', 'night', 'beams']) {
		// tex() drops the wrapper and returns the raw buffer, so rebuild the header.
		add(k, 'assets/textures', { w: 64, h: 64, rgba: Buffer.from(anc.T[k].buffer, anc.T[k].byteOffset, anc.T[k].length * 4) },
			'html:601-835 buildTextures');
	}
	anc.T.window.forEach((win, boards) => {
		add(`window${boards}`, 'assets/textures',
			{ w: 64, h: 64, rgba: Buffer.from(win.buffer, win.byteOffset, win.length * 4) },
			`html:803-831, ${boards} plank${boards === 1 ? '' : 's'} standing`);
	});

	// ---- enemy strips ----
	for (const s of STRIPS) {
		const pals = s.palettes > 0 ? s.palettes : 1;
		for (let p = 0; p < pals; p++) {
			const set = s.palettes > 0 ? anc.SPR[s.set][p] : anc.SPR[s.set];
			const prefix = s.palettes > 0 ? `${s.set}${p}` : s.set;
			for (const [anim, count] of Object.entries(s.anims)) {
				add(`${prefix}_${anim}`, 'assets/sprites',
					strip(set[anim], count, `${prefix}_${anim}`),
					`html:973-1129 make${s.set[0].toUpperCase()}${s.set.slice(1)}Set`);
			}
		}
	}

	// ---- the 8-direction atlas ----
	// Added beside the single-view strips above rather than replacing them: the
	// committed art stays byte-for-byte what it was, `--check` keeps reproducing
	// the drift table in README.md, and sprite_lib.gd falls back to the
	// single-view strip on any machine where these have not been generated yet.
	for (const [name, a] of atlas.build(anc)) add(name, a.dir, a, a.note);

	// ---- props that already ship ----
	for (const k of Object.keys(anc.PERKDEF)) {
		const note = PORT_PERKS[k]
			? 'html:1271-1307 makePerkMachine, port-authored PERKDEF row (see PORT_PERKS)'
			: 'html:1271-1307 makePerkMachine';
		add(`perk_${k}_off`, 'assets/props', single(anc.SPR.perk[k].off), note);
		add(`perk_${k}_on`, 'assets/props', single(anc.SPR.perk[k].on), note);
	}
	for (const k of ['closed', 'open', 'teddy']) {
		add(`box_${k}`, 'assets/props', single(anc.SPR.box[k]), 'html:1310-1365 makeBox');
	}
	add('gen_off', 'assets/props', single(anc.SPR.gen.off), 'html:1368-1393 makeGenerator');
	add('gen_on', 'assets/props', single(anc.SPR.gen.on), 'html:1368-1393 makeGenerator');
	for (const k of Object.keys(anc.POWERDEF)) {
		add(`pu_${k}`, 'assets/props', single(anc.SPR.power[k]), 'html:1403-1435 makePowerup');
	}

	// ---- props the original export pass never reached ----
	// Pack-a-Punch first, matching boot()'s order at html:3418. Nothing here
	// draws through sr(), so the order is documentation rather than a
	// constraint — but the cheapest way to keep that true is to not deviate.
	const pap = anc.makePaP();
	add('pap_off', 'assets/props', single(pap.off), 'html:1986-2012 makePaP, unpowered');
	add('pap_on', 'assets/props', single(pap.on), 'html:1986-2012 makePaP, powered');

	// One chalk plaque per wall buy, drawn from that weapon's own GUNART parts
	// with its real price — html:3435.
	for (const b of anc.WALLBUYS) {
		const w = anc.WEAPONS[b.gun];
		add(`chalk_${b.gun}`, 'assets/props',
			single(anc.makeChalk(w.art, w.name, b.cost)),
			`html:1244-1262 makeChalk('${w.art}','${w.name}',${b.cost})`);
	}
	// The Bowie knife is bought off a wall like the guns but lives outside
	// WALLBUYS in both the ancestor and scripts/data/map_data.gd — html:3438.
	add('chalk_bowie', 'assets/props',
		single(anc.makeChalk('knife', 'Bowie Knife', anc.BOWIE.cost)),
		`html:1244-1262 makeChalk('knife','Bowie Knife',${anc.BOWIE.cost})`);

	return { targets: t, meta };
}


module.exports = { build, STRIPS };
