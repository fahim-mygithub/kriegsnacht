'use strict';

/* The 8-direction atlas (SYNTHESIS §4.2).
 *
 * READ tools/gen/README.md FIRST. Everything else in this package replays the
 * ancestor's own drawing code; THIS FILE DOES NOT. `kriegsnacht.html` draws
 * exactly one view of each enemy — `makeZombieSet` at html:973, `makeCrawlerSet`
 * at html:1010, `makeHoundSet` at html:1060 — so a zombie walking away from you
 * still faces you. There is no ancestor code for the other seven bearings and
 * this file must not pretend otherwise: the poses below are new work, drawn
 * against Call of Duty: Zombies rather than ported from anything.
 *
 * WHAT IS STILL THE ANCESTOR'S, and it is most of what you see:
 *   - `ZPAL`, the three corpse palettes (html:844-848).
 *   - `outlineSprite`, the 1px rim every silhouette carries (html:955-971).
 *   - `bake`, the canvas harness (html:571).
 *   - One whole row of every strip. See ANCHOR below.
 *
 * ANCHOR — the row that is not new art.
 *   Walker:  the ancestor draws it FACING THE VIEWER, so its frame is view 0
 *            and is emitted by calling `zombieBody` unmodified.
 *   Crawler: the ancestor draws it IN PROFILE, head to the left (html:1041,
 *            `ellipse(-13, hy, ...)`), so its frame is a 90-degree view.
 *   Hound:   likewise in profile, head at `translate(-16, ...)` (html:1092).
 *   Both of those profiles face screen-LEFT and this file's yaw convention puts
 *   +z (the body's forward) at +screen-x, so the ancestor frame is mirrored into
 *   view 2 rather than dropped. Nothing is redrawn that the ancestor already drew.
 *
 * THE PROJECTION. Every new pose is one body model seen from five bearings, not
 * five hand-drawn poses. Parts live in body space — x to the body's right, z out
 * of its chest, y down the screen exactly as the ancestor's own coordinates run —
 * and are projected with
 *
 *     screen_x = x*cos(yaw) + z*sin(yaw)
 *     depth    = z*cos(yaw) - x*sin(yaw)        (larger = nearer the camera)
 *
 * At yaw 0 that is the identity on x, which is why the walker's view 0 and the
 * turned views share a coordinate system and the head, shoulders and hips land on
 * the same scanlines in all five. `depth` orders the painter's pass, so an arm
 * behind the torso is behind it without a single per-view special case.
 *
 * Views are 0, 45, 90, 135 and 180 degrees. The other three bearings are the
 * horizontal mirror of 45, 90 and 135, applied at runtime by `flip_h` on the
 * Sprite3D — see scripts/entities/zombie.gd. Mirroring costs nothing and a
 * zombie is close enough to bilaterally symmetric that the seam is invisible;
 * the asymmetries the ancestor authored (the torn arm on palette 2, the scalp
 * wound) swap sides with it, which is the price and it is not visible at 48px.
 */

const TAU = Math.PI * 2;

/* 0, 45, 90, 135, 180. Index is the row in the generated strip. */
const VIEWS = [0, Math.PI / 4, Math.PI / 2, 3 * Math.PI / 4, Math.PI];
const VIEW_COUNT = VIEWS.length;

/* Which row each kind's ancestor frame occupies, and whether it has to be
 * mirrored to face this file's +x. Consumed by the builders below and asserted
 * against by scripts/dev/checks/enemies.gd through the generated strip itself. */
const ANCHOR = {
	zombie: { view: 0, mirror: false },
	crawler: { view: 2, mirror: true },
	hound: { view: 2, mirror: true },
};


function proj(yaw) {
	const c = Math.cos(yaw), s = Math.sin(yaw);
	return {
		c, s,
		/* body (x,z) -> screen x */
		x: (bx, bz) => bx * c + bz * s,
		/* body (x,z) -> depth; larger is nearer the camera */
		d: (bx, bz) => bz * c - bx * s,
		/* projected half-width of an axis-aligned box of half extents (hx,hz) */
		box: (hx, hz) => Math.abs(hx * c) + Math.abs(hz * s),
		/* projected half-width of an ellipse of radii (rx,rz) */
		ell: (rx, rz) => Math.hypot(rx * c, rz * s),
		/* is a surface with outward normal (nx,nz) turned toward the camera?
		 * The camera sits along (-s, c) in body space — see `d` above. */
		faces: (nx, nz, bias = 0.06) => (-nx * s + nz * c) > bias,
	};
}


/* A rect painted on a surface at depth `bz`, given in the body's own x. Its
 * width foreshortens by cos(yaw) and its position slides by z*sin(yaw), which is
 * the whole of the projection for a flat decal — the open coat, the eye sockets,
 * the blood. */
function faceRect(g, P, bz, x, y, w, h) {
	const a = P.x(x, bz), b = P.x(x + w, bz);
	const lo = Math.min(a, b), wd = Math.abs(b - a);
	if (wd < 0.35) return;              // edge-on: nothing to draw
	g.fillRect(lo, y, wd, h);
}


/* A limb: a tapered quad between two projected points. Cheaper to read than a
 * rotate/translate stack and it survives the projection without shearing. */
function limb(g, x0, y0, x1, y1, w0, w1) {
	g.beginPath();
	g.moveTo(x0 - w0, y0);
	g.lineTo(x0 + w0, y0);
	g.lineTo(x1 + w1, y1);
	g.lineTo(x1 - w1, y1);
	g.closePath();
	g.fill();
}


/* ---------------------------------------------------------------------------
 * The walker.
 *
 * Vertical layout is the ancestor's, line for line, so that view 0 (its own
 * drawing) and views 1-4 put the head, shoulders, hips and boots on the same
 * scanlines: base = 62 - bob, hips at base-19/20, shoulders base-40, torso top
 * base-42, head centre base-46 (html:850, 866-869, 897, 923).
 * ------------------------------------------------------------------------- */

/* Half depths, in sprite pixels. 1 px is 1.82/64 = 0.02844 m, so the torso's 4.5
 * is a 0.256 m chest front to back against the ancestor's 18 px (0.512 m) across
 * — a real human ratio, and the number that decides how wide a zombie in profile
 * draws. Everything here is measured off that scale rather than eyeballed. */
const Z_TORSO = 4.5;
const Z_HEAD = 5.6;
const Z_LEG = 4.0;

function walkerTurned(g, p, o, yaw) {
	const P = proj(yaw);
	const cx = 24, base = 62 - o.bob;
	const hy = base - 46;
	const seesFace = P.c > 0.05;

	g.save();
	g.translate(cx, 0);

	// shadow. Longer front-to-back than side to side, which is why it barely
	// narrows in profile rather than collapsing to the torso's width.
	//
	// Pinned to y=63 and shrinking with the bob, matching the `zombie-shadow`
	// patch in extract.js — `base` is 62-bob, so placing it at base+1 lifted the
	// contact shadow off the floor with the body and the walker floated. 63 is
	// what base+1 evaluated to at bob=0, so an unbobbed frame is unchanged.
	g.fillStyle = 'rgba(0,0,0,.34)';
	g.beginPath();
	g.ellipse(0, 63, P.ell(13 - o.bob * 0.9, 9 - o.bob * 0.6), 3.4 - o.bob * 0.35, 0, 0, TAU);
	g.fill();

	// --- legs. The ancestor swings them in the screen plane (html:859-871),
	// which only reads as a stride head-on; here the foot swings fore and aft in
	// z, so a zombie in profile actually walks.
	const legs = [-1, 1].map((side) => {
		const fz = o.swing * side * 6.5;
		return {
			side,
			hx: P.x(side * 5, 0),
			fx: P.x(side * 5, fz),
			depth: P.d(side * 5, fz * 0.5),
		};
	}).sort((a, b) => a.depth - b.depth);

	const lw = P.box(4, Z_LEG);
	for (const L of legs) {
		g.fillStyle = p.clothD; limb(g, L.hx, base - 20, L.fx, base - 5, lw, lw);
		g.fillStyle = p.cloth; limb(g, L.hx, base - 20, (L.hx + L.fx) * 0.5, base - 11, lw, lw);
		g.fillStyle = 'rgba(0,0,0,.4)'; limb(g, L.fx, base - 7, L.fx, base - 5, lw, lw);
		g.fillStyle = '#1A1712'; g.fillRect(L.fx - lw - 1, base - 5, lw * 2 + 2, 5);
		g.fillStyle = 'rgba(255,255,255,.08)'; g.fillRect(L.fx - lw - 1, base - 5, lw * 2 + 2, 1);
	}

	// Everything above the hips leans, exactly as the ancestor does it
	// (html:865, `g.rotate(o.lean*0.03)` applied after the legs and before the
	// torso). It is what separates the two attack frames from the walk cycle.
	g.save();
	g.rotate(o.lean * 0.03);

	// --- arms. Three body-space keypoints per arm rather than the ancestor's
	// in-plane rotation, because a rotation about the view axis cannot turn: at
	// 90 degrees the ancestor's reach would still be drawn across the chest
	// instead of out in front of the body, which is the whole tell of a zombie.
	//
	// THE IN-PLANE ANGLE IS DERIVED, NOT COPIED. `armAngle` reproduces the
	// ancestor's own arm rotation as patched by `zombie-arms` in extract.js, and
	// the body-space x of each joint is where that rotation puts it at yaw 0 —
	// which IS row 0, the walker's anchor row, drawn by zombieBody itself. Get
	// this wrong and the hands jump sideways the moment a zombie turns 45
	// degrees. It is written as the same expression rather than the same numbers
	// so that the next person to retune the pose only has to find one of them:
	// checks/enemies.gd asserts the two agree at yaw 0.
	//
	// z is the half the ancestor cannot express at all. A flat front view has no
	// way to say "forward", so `reachZ` carries the whole reach into depth: small
	// at a walk, where the arms hang at the hips, and large at a lunge.
	const reachZ = 5 + o.reach * 16;
	const arms = [-1, 1].map((side) => {
		const A = side * (0.10 + o.reach * 0.40) + o.swing * 0.16;
		const sn = Math.sin(A), cs = Math.cos(A);
		// `ly` is distance down the arm from the shoulder, in the ancestor's own
		// local units: 0 shoulder, 10 elbow, 19 the top of the hand rect
		// (html:912-916). Canvas rotate(A) sends local (0,ly) to (-ly*sin A, ly*cos A).
		const ax = (ly) => side * 8.5 - ly * sn;
		const ay = (ly) => base - 40 + ly * cs;
		const sz = side * 1.6;                       // one shoulder slightly ahead
		return {
			side,
			sx: P.x(ax(0), sz), sy: ay(0),
			ex: P.x(ax(10), sz + reachZ * 0.42), ey: ay(10),
			hx: P.x(ax(19), sz + reachZ), hy2: ay(19),
			depth: P.d(ax(10), sz + reachZ * 0.5),
			torn: o.tornArm && side === 1,
		};
	}).sort((a, b) => a.depth - b.depth);

	const torsoDepth = P.d(0, 0);
	const drawArm = (A) => {
		if (A.torn) {
			// severed at the elbow, html:903-909
			g.fillStyle = p.cloth; limb(g, A.sx, A.sy, A.ex, A.ey, 2.6, 2.4);
			g.fillStyle = p.wound; g.fillRect(A.ex - 2.4, A.ey, 4.8, 3);
			g.fillStyle = 'rgba(60,6,8,.7)'; g.fillRect(A.ex - 1.5, A.ey + 3, 3, 4);
			return;
		}
		g.fillStyle = p.cloth; limb(g, A.sx, A.sy, A.ex, A.ey, 2.6, 2.5);
		g.fillStyle = p.skin; limb(g, A.ex, A.ey, A.hx, A.hy2, 2.4, 2.2);
		g.fillStyle = p.dark; limb(g, A.hx, A.hy2 - 3, A.hx, A.hy2, 2.2, 2.2);
		g.fillStyle = p.skin; g.fillRect(A.hx - 3.4, A.hy2, 6.8, 4);
		g.fillStyle = p.dark;
		g.fillRect(A.hx - 3.4, A.hy2 + 3, 1.6, 3);
		g.fillRect(A.hx - 0.8, A.hy2 + 3, 1.6, 3.4);
		g.fillRect(A.hx + 1.8, A.hy2 + 3, 1.6, 3);
	};

	for (const A of arms) if (A.depth < torsoDepth) drawArm(A);

	// --- torso
	const shw = P.box(9, Z_TORSO), hpw = P.box(7, Z_TORSO * 0.78);
	g.fillStyle = p.cloth;
	g.beginPath();
	g.moveTo(-shw, base - 42); g.lineTo(shw, base - 42);
	g.lineTo(hpw, base - 19); g.lineTo(-hpw, base - 19);
	g.closePath(); g.fill();
	g.fillStyle = 'rgba(0,0,0,.35)';
	g.fillRect(-shw, base - 24, shw * 2, 5);

	if (seesFace) {
		// open coat over a ruined chest, html:882-895 as patched by `zombie-ribs`.
		// The geometry has to track that patch: this row and row 0 are the same
		// chest, and the necktie the patch exists to kill was WORSE here, because
		// the lapels foreshorten away at 45 degrees and leave the stripes with
		// nothing framing them.
		g.fillStyle = p.skin; faceRect(g, P, Z_TORSO, -5, base - 40, 10, 17);
		if (o.ribs) {
			g.fillStyle = p.wound; faceRect(g, P, Z_TORSO, -5, base - 36, 10, 8);
			g.fillStyle = '#8E876F';
			for (let i = 0; i < 3; i++) {
				faceRect(g, P, Z_TORSO, i % 2 ? 1.2 : -4.6, base - 35 + i * 2.4, 3.4, 1.2);
			}
		}
		g.fillStyle = p.clothD;
		faceRect(g, P, Z_TORSO, -9, base - 42, 3.5, 23);
		faceRect(g, P, Z_TORSO, 5.5, base - 42, 3.5, 23);
		g.fillStyle = 'rgba(84,10,12,.6)';
		faceRect(g, P, Z_TORSO, -8.2, base - 30, 4.5, 7);
		faceRect(g, P, Z_TORSO, 2.2, base - 27, 4, 5);
	} else {
		// The back of the coat. Nothing here is ported — the ancestor never drew
		// one — so it stays the plainest thing on the sprite. But "plainest" had
		// become "nothing": at 22% black the shoulder blades did not survive the
		// tonemap and rows 3 and 4 rendered as a flat slab with a ball on top, the
		// arms hidden behind the torso and no shoulder line at all. Widened,
		// dropped to sit under the shoulder rather than beside it, and taken to
		// 30% — still the quietest surface here, now a legible one.
		g.fillStyle = p.clothD;
		faceRect(g, P, -Z_TORSO, -1.2, base - 42, 2.4, 23);
		g.fillStyle = 'rgba(0,0,0,.30)';
		faceRect(g, P, -Z_TORSO, -8.4, base - 38, 6.4, 11);
		faceRect(g, P, -Z_TORSO, 2.0, base - 38, 6.4, 11);
		if (o.ribs) {
			// It went all the way through. Gated on `ribs` for the same reason the
			// front is (html:980, `ribs: p!==ZPAL[1]`): palette 1 has no chest wound,
			// so it must not have an exit wound either.
			g.fillStyle = 'rgba(84,10,12,.5)';
			faceRect(g, P, -Z_TORSO, -3.6, base - 33, 7.2, 9);
		}
	}

	for (const A of arms) if (A.depth >= torsoDepth) drawArm(A);

	// --- head
	g.fillStyle = p.skin;
	g.beginPath(); g.ellipse(0, hy, P.ell(7.2, Z_HEAD), 8.4, 0, 0, TAU); g.fill();
	g.fillStyle = p.dark;
	g.beginPath(); g.ellipse(0, hy + 4.5, P.ell(6.4, 5.0), 4.4, 0, 0, TAU); g.fill();
	if (seesFace) {
		g.fillStyle = p.skin;
		g.beginPath(); g.ellipse(P.x(0, 1.2), hy + 3.2, P.ell(5.8, 4.6), 4.2, 0, 0, TAU); g.fill();
	}
	// hair sits on the crown and wraps the back, so it slides with -z
	g.fillStyle = p.hair;
	g.beginPath(); g.ellipse(P.x(-1, -1.4), hy - 4.4, P.ell(6.6, 5.2), 4.2, 0, 0, TAU); g.fill();
	if (!seesFace) {
		g.beginPath(); g.ellipse(P.x(0, -2.2), hy - 0.8, P.ell(6.8, 5.4), 6.4, 0, 0, TAU); g.fill();
	}
	g.fillStyle = p.dark; faceRect(g, P, -1.0, 3.4, hy - 6.6, 3.6, 3.2);
	g.fillStyle = p.wound; faceRect(g, P, -1.0, 3.8, hy - 6.2, 2.8, 2.4);

	// Eyes, per socket. A socket is drawn only when its own outward normal is
	// turned toward the camera, which is what gives the profile exactly one eye
	// and the two rear views none — and none is the point: a zombie with its back
	// to you must not glow at you. scripts/entities/zombie.gd's EYE_VIEW table is
	// the same geometry, so the additive quads land on these pixels.
	for (const side of [-1, 1]) {
		if (!P.faces(side * 0.45, 0.89)) continue;
		const ex = P.x(side * 2.9, 4.6);
		const w = Math.max(1.6, 3.4 * Math.abs(P.c) + 1.2 * Math.abs(P.s));
		g.fillStyle = '#100E0C'; g.fillRect(ex - w * 0.5, hy - 1.6, w, 3);
		g.fillStyle = '#F3E4A8'; g.fillRect(ex - 1.0, hy - 1.0, 2.0, 1.8);
		g.fillStyle = 'rgba(255,236,168,.28)'; g.fillRect(ex - 2.3, hy - 2.4, 4.6, 4.4);
	}
	if (seesFace) {
		const drop = o.reach * 1.4;
		g.fillStyle = '#0D0B0A'; faceRect(g, P, 4.0, -3.2, hy + 3.6 + drop, 6.4, 3.2 + o.reach * 1.6);
		g.fillStyle = '#C9C3AE'; faceRect(g, P, 4.0, -3.0, hy + 3.6 + drop, 6.0, 1.1);
		g.fillStyle = 'rgba(90,10,12,.55)'; faceRect(g, P, 4.0, -2.6, hy + 6.4 + drop, 5.2, 2.4);
	}

	g.restore();      // lean
	g.restore();      // translate to cx
}


/* ---------------------------------------------------------------------------
 * The crawler. The ancestor's is a profile (html:1043-1077), so its own frame is
 * view 2 mirrored; the other four are new. Body space here has the crawler
 * pointing along +z, which is what makes view 0 the one the port never had — a
 * crawler coming straight at you, head-on and low.
 * ------------------------------------------------------------------------- */

function crawlerTurned(g, p, o, yaw) {
	const P = proj(yaw);
	const base = 31;
	const seesFace = P.c > 0.05;

	g.save();
	g.translate(24, 0);

	g.fillStyle = 'rgba(0,0,0,.32)';
	g.beginPath(); g.ellipse(0, base + 1, P.ell(7, 15), 3, 0, 0, TAU); g.fill();

	// dragging entrails, behind the torso in z
	g.fillStyle = p.wound;
	g.beginPath(); g.ellipse(P.x(0, -8), base - 3, P.ell(4, 8), 3.4, 0, 0, TAU); g.fill();
	g.fillStyle = 'rgba(60,6,10,.75)';
	g.beginPath(); g.ellipse(P.x(0, -9), base - 1, P.ell(3, 9), 2, 0, 0, TAU); g.fill();

	// torso, flat to the ground and pointing along +z
	const tw = P.box(7, 11);
	g.fillStyle = p.cloth;
	g.beginPath(); g.ellipse(P.x(0, -1), base - 8, tw, 5.6, 0, 0, TAU); g.fill();
	g.fillStyle = p.clothD; g.fillRect(-tw, base - 6, tw * 2, 3);
	if (seesFace) {
		g.fillStyle = p.skin; faceRect(g, P, 6, -4, base - 12, 8, 7);
		g.fillStyle = p.wound; faceRect(g, P, 6, -4, base - 9, 8, 4);
	}

	// clawing arms, out to the sides and forward
	const arms = [-1, 1].map((side) => {
		// `dead` pulls both arms in and down, which is the ancestor's own
		// `+ (dead?0.9:0)` on the arm rotation at html:1068.
		const sw = Math.sin(o.ph + (side < 0 ? Math.PI : 0)) - (o.dead ? 0.9 : 0);
		const hz = 9 + sw * 3.5;
		return {
			side, sw,
			sx: P.x(side * 6, 2), sy: base - 11,
			hx: P.x(side * 8.5, hz), hy2: base - 3 + Math.max(0, -sw) * 1.5,
			depth: P.d(side * 7, hz * 0.6),
		};
	}).sort((a, b) => a.depth - b.depth);
	for (const A of arms) {
		g.fillStyle = p.cloth; limb(g, A.sx, A.sy, (A.sx + A.hx) * 0.5, (A.sy + A.hy2) * 0.5, 2.4, 2.3);
		g.fillStyle = p.skin; limb(g, (A.sx + A.hx) * 0.5, (A.sy + A.hy2) * 0.5, A.hx, A.hy2, 2.3, 2.2);
		g.fillStyle = p.dark; g.fillRect(A.hx - 3, A.hy2, 6, 3);
	}

	// head, dragged out in front
	const hx = P.x(0, 13), hy = base - 16;
	g.fillStyle = p.skin;
	g.beginPath(); g.ellipse(hx, hy, P.ell(6.4, 5.4), 6, 0, 0, TAU); g.fill();
	g.fillStyle = p.hair;
	g.beginPath(); g.ellipse(P.x(0, 11.5), hy - 3, P.ell(6, 5), 3.4, 0, 0, TAU); g.fill();
	for (const side of [-1, 1]) {
		if (!P.faces(side * 0.5, 0.87)) continue;
		const ex = P.x(side * 2.3, 17.2);
		const w = Math.max(1.5, 3.0 * Math.abs(P.c) + 1.1 * Math.abs(P.s));
		g.fillStyle = '#100E0C'; g.fillRect(ex - w * 0.5, hy - 1, w, 2.6);
		g.fillStyle = '#F3E4A8'; g.fillRect(ex - 0.9, hy - 0.4, 1.8, 1.6);
	}
	if (seesFace) {
		g.fillStyle = '#0D0B0A'; faceRect(g, P, 16, -3, hy + 3, 6, 2.4);
	}

	g.restore();
}


/* ---------------------------------------------------------------------------
 * The hellhound. Ancestor frame at html:1090-1128, again a profile, again view 2
 * mirrored. Head-on is the view that matters and the one the port never had: a
 * dog charging you currently shows you its flank, which is both wrong and
 * (§4.2, the collider reconciliation) 1.37 m of billboard around a 0.60 m body.
 * ------------------------------------------------------------------------- */

function houndTurned(g, o, yaw) {
	const P = proj(yaw);
	const base = 36;
	const bob = Math.abs(Math.sin(o.ph)) * 2;
	const seesFace = P.c > 0.05;

	g.save();
	g.translate(28, 0);

	g.fillStyle = 'rgba(0,0,0,.34)';
	g.beginPath(); g.ellipse(0, base + 1, P.ell(6.5, 16), 3.2, 0, 0, TAU); g.fill();

	// legs: front pair at +z, rear pair at -z, swinging fore and aft
	const legs = [];
	for (let i = 0; i < 4; i++) {
		const front = i < 2, side = (i % 2) ? 1 : -1;
		const bz = front ? 10 : -10;
		const sw = Math.sin(o.ph + (front ? 0 : Math.PI) + side * 0.5) * 3.2;
		legs.push({
			tx: P.x(side * 4.5, bz), fx: P.x(side * 4.5, bz + sw),
			depth: P.d(side * 4.5, bz), front,
		});
	}
	legs.sort((a, b) => a.depth - b.depth);
	for (const L of legs) {
		g.fillStyle = '#1B1512'; limb(g, L.tx, base - 13 - bob, L.fx, base - 3, 2.4, 2.2);
		g.fillStyle = '#0E0B09'; g.fillRect(L.fx - 3, base - 3, 6, 3);
	}

	// tail, behind
	g.save(); g.translate(P.x(0, -15), base - 21 - bob);
	g.rotate(-0.5 + Math.sin(o.ph) * 0.25);
	g.fillStyle = '#1B1512'; g.fillRect(0, -2, Math.max(3, P.box(1, 13)), 3.6);
	g.restore();

	// body
	g.save(); g.translate(0, -bob);
	g.fillStyle = '#241C18';
	g.beginPath(); g.ellipse(0, base - 19, P.ell(7, 16), 7.5, 0, 0, TAU); g.fill();
	g.fillStyle = '#150F0D';
	g.beginPath(); g.ellipse(0, base - 15, P.ell(6.4, 15), 5, 0, 0, TAU); g.fill();
	// charred hide, glowing cracks — the ancestor's own rgba(226,96,20,.5)
	g.fillStyle = 'rgba(226,96,20,.5)';
	for (let i = 0; i < 7; i++) {
		const bz = -13 + i * 4.3;
		g.fillRect(P.x((i % 2 ? 2.5 : -2.5), bz) - 1.2, base - 22 + (i % 2) * 3, 2.4, 1.4);
	}

	// neck. The ancestor needs none — in profile the head ellipse overlaps the
	// body ellipse — but from 45 degrees the head projects inward and upward and
	// reads as a floating lantern without one.
	g.fillStyle = '#1B1512';
	limb(g, P.x(0, 9), base - 21, P.x(0, 15), base - 23, 4.5, 4.0);

	// head, out in front
	g.save(); g.translate(P.x(0, 16), base - 23);
	g.fillStyle = '#241C18';
	g.beginPath(); g.ellipse(0, 0, P.ell(6.2, 8), 6.4, 0, 0, TAU); g.fill();
	if (seesFace) {
		g.fillStyle = '#1B1512'; faceRect(g, P, 8, -4, -1, 8, 5.4);
		g.fillStyle = '#0A0806'; faceRect(g, P, 8, -4, 2.6, 8, 1.6);
		g.fillStyle = '#D8D2C0';
		for (let i = 0; i < 4; i++) faceRect(g, P, 8, -3.4 + i * 2.1, 2.2, 1.1, 2.2);
	}
	// ears
	g.fillStyle = '#241C18';
	for (const side of [-1, 1]) {
		const ex = P.x(side * 3.4, -1);
		g.beginPath(); g.moveTo(ex - 2.4, -4.6); g.lineTo(ex + side * 0.6, -10.4);
		g.lineTo(ex + 2.4, -4); g.closePath(); g.fill();
	}
	// burning eyes, #FF7A18 verbatim (html:1104). The ancestor's halo is a 7.6x6.6
	// rect and it works there because the head is drawn in profile and the halo
	// falls inside the skull; projected onto a three-quarter view it hangs off the
	// silhouette and the head reads as a lantern, so it is sized to the pair here.
	for (const side of [-1, 1]) {
		if (!P.faces(side * 0.5, 0.87)) continue;
		const ex = P.x(side * 2.4, 5.4);
		g.fillStyle = 'rgba(255,140,30,.30)'; g.fillRect(ex - 2.4, -3.6, 4.8, 5.0);
		g.fillStyle = '#FF7A18'; g.fillRect(ex - 1.5, -2.5, 3, 2.7);
	}
	g.restore();      // head
	g.restore();      // body bob

	// embers trailing off it, html:1110-1112. `sr()` is not reachable from here
	// (see atlas.js), so this draws through the caller's own seeded generator and
	// scatters over the body's projected footprint rather than a fixed x range.
	g.fillStyle = 'rgba(255,140,40,.5)';
	for (let i = 0; i < 5; i++) {
		const bz = (o.rnd() - 0.5) * 30;
		g.fillRect(P.x((o.rnd() - 0.5) * 8, bz) | 0, (base - 26 + o.rnd() * 14) | 0, 1, 1);
	}

	g.restore();
}


module.exports = { VIEWS, VIEW_COUNT, ANCHOR, proj, walkerTurned, crawlerTurned, houndTurned };
