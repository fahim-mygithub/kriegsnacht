'use strict';

/* CLI.
 *
 *   node tools/gen/gen.js --list                 what can be generated, and what already exists
 *   node tools/gen/gen.js chalk_mp40 pap_on      write those PNGs to their home in assets/
 *   node tools/gen/gen.js --all                  write everything that is missing
 *   node tools/gen/gen.js --all --check          write nothing; diff against what is committed
 *   node tools/gen/gen.js --all --out <dir>      write everything somewhere harmless
 *
 * Existing files are never overwritten without --force. The committed art was
 * rasterised by Chrome and this rasterises with standalone Skia; R7 §A2
 * measured the residual at a mean 2.7/255 over the pixels that move at all, so
 * a regeneration is a *near*-identical image, and clobbering seventeen sprite
 * strips with near-identical ones is a diff nobody can review. */

const fs = require('fs');
const path = require('path');
const png = require('./png.js');
const targets = require('./targets.js');

const ROOT = path.resolve(__dirname, '..', '..');


function parseArgs(argv) {
	const opts = { names: [], all: false, list: false, check: false, force: false, out: null };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === '--all') opts.all = true;
		else if (a === '--list') opts.list = true;
		else if (a === '--check') opts.check = true;
		else if (a === '--force') opts.force = true;
		else if (a === '--out') opts.out = argv[++i];
		else if (a.startsWith('-')) throw new Error(`gen: unknown option ${a}`);
		else opts.names.push(a);
	}
	// --check always compares against assets/. Accepting --out alongside it
	// would silently ignore one of the two.
	if (opts.check && opts.out) throw new Error('gen: --check compares against assets/ and cannot take --out');
	return opts;
}


function destination(t, out) {
	return out ? path.join(path.resolve(out), `${t.name}.png`) : path.join(ROOT, t.dir, `${t.name}.png`);
}


/* Decodes what is on disk and compares pixels, not file bytes. Every committed
 * asset carries Chromium's IDAT chunking, so byte equality is a property of the
 * encoder that wrote them and would report "different" for an identical image. */
function compare(t, file) {
	if (!fs.existsSync(file)) return { state: 'new' };
	const onDisk = fs.readFileSync(file);
	const mine = png.encode(t.w, t.h, t.rgba);
	const sameBytes = onDisk.equals(mine);

	let old;
	try {
		old = png.decode(onDisk);
	} catch (e) {
		return { state: 'undecodable', why: e.message, sameBytes };
	}
	if (old.w !== t.w || old.h !== t.h) {
		return { state: 'resized', was: `${old.w}x${old.h}`, now: `${t.w}x${t.h}`, sameBytes };
	}

	// Compare premultiplied, which is what a compositor actually reads.
	// Straight RGBA lies at low alpha: both rasterisers store premultiplied
	// internally and unpremultiply on the way out, so an alpha-3 pixel comes
	// back as (255,255,85) here and (170,170,0) in the committed file — a
	// "delta of 255" on a pixel that is 1% opaque and identical on screen.
	const pm = (v, a) => Math.round(v * a / 255);
	let differing = 0, sumDelta = 0, maxDelta = 0, invisible = 0;
	for (let i = 0; i < t.rgba.length; i += 4) {
		const an = t.rgba[i + 3], ao = old.rgba[i + 3];
		let d = Math.abs(an - ao);
		for (let c = 0; c < 3; c++) d = Math.max(d, Math.abs(pm(t.rgba[i + c], an) - pm(old.rgba[i + c], ao)));
		if (d === 0) {
			for (let c = 0; c < 4; c++) if (t.rgba[i + c] !== old.rgba[i + c]) { invisible++; break; }
			continue;
		}
		differing++;
		sumDelta += d;
		if (d > maxDelta) maxDelta = d;
	}
	const pixels = t.w * t.h;
	return {
		state: differing === 0 ? 'identical' : 'differs',
		sameBytes, pixels, differing, maxDelta, invisible,
		meanDelta: differing ? sumDelta / differing : 0,
	};
}


function describe(r) {
	switch (r.state) {
		case 'new': return 'NEW            (nothing committed at this path)';
		case 'identical': return `pixel-identical${r.sameBytes ? ', byte-identical too' : ' (file bytes differ: encoder, not image)'}`
			+ (r.invisible ? `  [${r.invisible} px differ only below the compositor]` : '');
		case 'resized': return `SIZE CHANGED   ${r.was} -> ${r.now}`;
		case 'undecodable': return `UNREADABLE     ${r.why}`;
		default:
			return `differs        ${r.differing}/${r.pixels} px (${(100 * r.differing / r.pixels).toFixed(2)}%)`
				+ `  meanDelta ${r.meanDelta.toFixed(2)}  maxDelta ${r.maxDelta}`
				+ (r.invisible ? `  [+${r.invisible} px differ only below the compositor]` : '');
	}
}


function main(argv) {
	const opts = parseArgs(argv);
	const { targets: all, meta } = targets.build();

	if (opts.list) {
		console.log(`${all.size} targets  (ancestor sha256 ${meta.sha.slice(0, 12)})\n`);
		let dir = null;
		for (const t of all.values()) {
			if (t.dir !== dir) { dir = t.dir; console.log(`${dir}/`); }
			const exists = fs.existsSync(destination(t, null));
			console.log(`  ${exists ? ' ' : '+'} ${t.name.padEnd(18)} ${(t.w + 'x' + t.h).padEnd(9)} ${t.note}`);
		}
		console.log('\n  + = not committed yet');
		return 0;
	}

	let wanted;
	if (opts.all) {
		wanted = [...all.values()];
	} else if (opts.names.length) {
		wanted = opts.names.map((n) => {
			const t = all.get(n);
			if (!t) throw new Error(`gen: no target named '${n}' — run --list`);
			return t;
		});
	} else {
		console.error('gen: name at least one target, or pass --all or --list');
		return 2;
	}

	if (opts.out && !opts.check) fs.mkdirSync(path.resolve(opts.out), { recursive: true });

	let wrote = 0, skipped = 0, drifted = 0;
	for (const t of wanted) {
		if (opts.check) {
			const r = compare(t, path.join(ROOT, t.dir, `${t.name}.png`));
			if (r.state === 'differs' || r.state === 'resized') drifted++;
			console.log(`${t.name.padEnd(18)} ${(t.w + 'x' + t.h).padEnd(9)} ${describe(r)}`);
			continue;
		}

		const file = destination(t, opts.out);
		// Repo-relative when it is in the repo; absolute when --out sent it elsewhere,
		// because "../../../AppData/Local/Temp/..." helps nobody.
		const inside = path.relative(ROOT, file).replace(/\\/g, '/');
		const rel = inside.startsWith('..') ? file.replace(/\\/g, '/') : inside;

		if (fs.existsSync(file) && !opts.force) {
			console.log(`${t.name.padEnd(18)} skipped   ${rel} exists (--force to replace)`);
			skipped++;
			continue;
		}
		fs.writeFileSync(file, png.encode(t.w, t.h, t.rgba));
		console.log(`${t.name.padEnd(18)} ${(t.w + 'x' + t.h).padEnd(9)} -> ${rel}`);
		wrote++;
	}

	if (opts.check) console.log(`\n${wanted.length} compared, ${drifted} differ from what is committed`);
	else console.log(`\n${wrote} written, ${skipped} skipped`);
	return 0;
}


if (require.main === module) {
	try {
		process.exit(main(process.argv.slice(2)));
	} catch (e) {
		console.error(e.message);
		process.exit(1);
	}
}

module.exports = { main, compare };
