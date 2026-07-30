'use strict';

/* Builds the 8-direction strips: one PNG per kind/palette/animation, frames left
 * to right as before, VIEWS stacked top to bottom.
 *
 *   row 0 = 0 deg   (facing the camera)      row 3 = 135 deg
 *   row 1 = 45 deg                           row 4 = 180 deg (facing away)
 *   row 2 = 90 deg  (profile, facing +x)
 *
 * 225/270/315 are `flip_h` at runtime; see views.js.
 *
 * THESE ARE NEW FILES, not replacements. `zombie0_walk.png` and its sixteen
 * siblings are left exactly as committed, so `gen.js --all --check` still
 * reproduces the drift table in README.md and the front view of every enemy is
 * still, pixel for pixel, the one the browser build shipped. The atlas lands
 * beside them as `<stem>_dir.png` and scripts/world/sprite_lib.gd prefers it and
 * falls back to the single-view strip when it is absent — which is what makes
 * this package safe to land before the art is regenerated on a given machine.
 *
 * One row of each atlas is not new art either: see ANCHOR in views.js. The
 * walker's row 0 is `zombieBody` called unmodified, and the crawler's and the
 * hound's row 2 is the ancestor's own baked frame mirrored, because both of
 * those are authored in profile facing screen-left and this file's +z is +x. */

const views = require('./views.js');

const SETS = {
	zombie: { w: 48, h: 64, anims: { walk: 6, attack: 2, death: 4 }, palettes: 3 },
	crawler: { w: 48, h: 34, anims: { walk: 4, death: 3 }, palettes: 3 },
	hound: { w: 56, h: 40, anims: { walk: 4, death: 3 }, palettes: 0 },
};


/* The ancestor's own xorshift, re-implemented here rather than reached for:
 * `_seed` is a module-level `let` inside the extraction and is not exported, so
 * there is no way to set it from outside and the ancestor's ember scatter cannot
 * be replayed. Same shape, seeded per frame, so the turned hounds still spark
 * and still spark identically on every machine. */
function xorshift(seed) {
	let s = seed >>> 0;
	return () => {
		s ^= s << 13; s >>>= 0;
		s ^= s >>> 17;
		s ^= s << 5; s >>>= 0;
		return s / 4294967296;
	};
}


/* Horizontal mirror of a baked {w,h,data} frame. */
function mirror(sprite) {
	const out = new Uint32Array(sprite.w * sprite.h);
	for (let y = 0; y < sprite.h; y++) {
		const row = y * sprite.w;
		for (let x = 0; x < sprite.w; x++) out[row + x] = sprite.data[row + (sprite.w - 1 - x)];
	}
	return { w: sprite.w, h: sprite.h, data: out };
}


function blit(dst, dstW, dx, dy, src) {
	for (let y = 0; y < src.h; y++) {
		const to = (dy + y) * dstW + dx;
		dst.set(src.data.subarray(y * src.w, (y + 1) * src.w), to);
	}
}


/* Frame parameter tables, transcribed from the ancestor's own loops so the
 * turned views animate on the same clock as the frame they sit beside:
 * makeZombieSet html:973-999, makeCrawlerSet html:1078-1086, makeHoundSet
 * html:1115-1123. */
function walkerFrameArgs(anim, f, p, ZPAL) {
	const common = { tornArm: p === ZPAL[2], ribs: p !== ZPAL[1] };
	if (anim === 'walk') {
		const ph = f / 6 * Math.PI * 2;
		return Object.assign({
			swing: Math.sin(ph), bob: Math.abs(Math.cos(ph)) * 1.6,
			reach: 0.25 + Math.sin(ph) * 0.08, lean: 1,
		}, common);
	}
	if (anim === 'attack') {
		return Object.assign({
			swing: f ? 0.4 : -0.3, bob: f ? 2.4 : 0, reach: f ? 1 : 0.72, lean: 2.4,
		}, common);
	}
	const t = f / 3;
	return Object.assign({ swing: t * 1.4, bob: 0, reach: 0.1, lean: -3 * t },
		common, { ribs: true, t });
}


function drawWalker(anc, g, W, H, p, anim, f, yaw) {
	const o = walkerFrameArgs(anim, f, p, anc.ZPAL);
	if (anim !== 'death') {
		views.walkerTurned(g, p, o, yaw);
		anc.outlineSprite(g, W, H);
		return;
	}
	const t = o.t;
	g.save();
	g.translate(24, 62); g.rotate(t * 1.32); g.translate(-24, -62 + t * 10);
	g.globalAlpha = 1 - t * 0.15;
	views.walkerTurned(g, p, o, yaw);
	g.restore();
	g.globalAlpha = 1;
	if (t > 0.2) {
		g.fillStyle = `rgba(72,8,10,${(t * 0.55).toFixed(2)})`;
		g.beginPath(); g.ellipse(24, 62, 6 + t * 13, 2 + t * 4.5, 0, 0, Math.PI * 2); g.fill();
	}
	anc.outlineSprite(g, W, H);
}


function drawCrawler(anc, g, W, H, p, anim, f, yaw) {
	if (anim === 'walk') {
		views.crawlerTurned(g, p, { ph: f / 4 * Math.PI * 2, dead: false }, yaw);
		anc.outlineSprite(g, W, H);
		return;
	}
	g.globalAlpha = 1 - f * 0.25;
	views.crawlerTurned(g, p, { ph: 0, dead: true }, yaw);
	g.globalAlpha = 1;
	g.fillStyle = `rgba(72,8,10,${(0.2 + f * 0.2).toFixed(2)})`;
	g.beginPath(); g.ellipse(24, 31, 10 + f * 7, 3 + f * 2, 0, 0, Math.PI * 2); g.fill();
	anc.outlineSprite(g, W, H);
}


function drawHound(anc, g, W, H, anim, f, yaw) {
	if (anim === 'walk') {
		views.houndTurned(g, { ph: f / 4 * Math.PI * 2, dead: false, rnd: xorshift(1234 + f) }, yaw);
		anc.outlineSprite(g, W, H);
		return;
	}
	g.save();
	g.translate(28, 36); g.rotate(f * 0.5); g.translate(-28, -36 + f * 4);
	g.globalAlpha = 1 - f * 0.28;
	views.houndTurned(g, { ph: 0, dead: true, rnd: xorshift(99 + f) }, yaw);
	g.restore();
	g.globalAlpha = 1;
	g.fillStyle = `rgba(240,110,20,${(0.3 - f * 0.08).toFixed(2)})`;
	g.beginPath(); g.ellipse(28, 34, 12 + f * 8, 4 + f * 3, 0, 0, Math.PI * 2); g.fill();
	anc.outlineSprite(g, W, H);
}


/* One kind/palette/animation, all VIEW_COUNT rows. `anc.SPR` is already built by
 * the time this runs (targets.js calls buildSprites first), which is where the
 * anchor row comes from. */
function strip(anc, kind, pal, anim, count) {
	const s = SETS[kind];
	const W = s.w, H = s.h;
	const out = new Uint32Array(W * count * H * views.VIEW_COUNT);
	const anchor = views.ANCHOR[kind];
	const set = s.palettes > 0 ? anc.SPR[kind][pal] : anc.SPR[kind];
	const p = s.palettes > 0 ? anc.ZPAL[pal] : null;

	for (let v = 0; v < views.VIEW_COUNT; v++) {
		const yaw = views.VIEWS[v];
		for (let f = 0; f < count; f++) {
			let frame;
			if (v === anchor.view) {
				// Not redrawn. The ancestor's baked frame, mirrored if its author
				// pointed it the other way.
				frame = anchor.mirror ? mirror(set[anim][f]) : set[anim][f];
			} else {
				frame = anc.bake(W, H, (g) => {
					if (kind === 'zombie') drawWalker(anc, g, W, H, p, anim, f, yaw);
					else if (kind === 'crawler') drawCrawler(anc, g, W, H, p, anim, f, yaw);
					else drawHound(anc, g, W, H, anim, f, yaw);
				});
			}
			blit(out, W * count, f * W, v * H, frame);
		}
	}
	return { w: W * count, h: H * views.VIEW_COUNT, rgba: Buffer.from(out.buffer, out.byteOffset, out.length * 4) };
}


/* Every atlas target, keyed by filename stem. */
function build(anc) {
	const t = new Map();
	for (const kind of Object.keys(SETS)) {
		const s = SETS[kind];
		const pals = s.palettes > 0 ? s.palettes : 1;
		for (let p = 0; p < pals; p++) {
			const prefix = s.palettes > 0 ? `${kind}${p}` : kind;
			for (const [anim, count] of Object.entries(s.anims)) {
				const a = views.ANCHOR[kind];
				t.set(`${prefix}_${anim}_dir`, {
					name: `${prefix}_${anim}_dir`,
					dir: 'assets/sprites',
					note: `views.js, ${views.VIEW_COUNT} rows; row ${a.view} is the ancestor's own frame`
						+ `${a.mirror ? ', mirrored' : ''}`,
					...strip(anc, kind, p, anim, count),
				});
			}
		}
	}
	return t;
}


module.exports = { build, SETS, mirror };
