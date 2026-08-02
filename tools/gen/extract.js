'use strict';

/* Slices the drawing code out of kriegsnacht.html and makes it runnable.
 *
 * kriegsnacht.html is the authority on every pixel in assets/, and it is
 * already committed — so the honest generator is one that reads it at run time
 * rather than one that keeps a copy that can drift. Nothing here is a
 * transliteration: the ancestor's own text is concatenated, ten recorded
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
 * hash moved with it. */
/* Moved a second time, on 2026-08-02, from
 *   62289369199d6d4aaa30171e516eda8e5465ca83fb79633dd649281fe8b2a4a8
 * and this time the art really did change: the four `zombie-*` patches landed.
 * kriegsnacht.html is still byte-for-byte the file the README pinned on
 * 2026-07-27 — `--report` prints `sha256(file) 0d48059a...` above this line and
 * that has not moved. If it ever does, assume the ancestor did and stop. */
const EXPECTED_SHA = '7a8550505720e46ac2e54a09be54e56db0ef90829e1bcbccd2d828f601076d29';

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

/* `from` must occur exactly once in the concatenated extraction. There are two
 * families here and they are not the same kind of change:
 *
 *   FONT patches (six, ids `chalk-*` / `perk-letter` / `box-question` /
 *   `powerup-x2` / `pap-label`) are FORCED. Every text run in the ancestor is
 *   drawn through a CSS font stack that resolves differently per machine, or not
 *   at all in Node. A generator whose output depends on which computer ran it is
 *   not a generator. These change no intent.
 *
 *   ART patches (four, ids `zombie-*`) are DELIBERATE DEPARTURES. The ancestor
 *   runs fine without them and produces exactly what it always produced; we
 *   think what it produced is wrong, and the reference — Black Ops 1 Zombies —
 *   is what says so. Each carries its evidence in `why`. Per CLAUDE.md a
 *   departure that is not recorded as deliberate is wrong even when it is right,
 *   so the whole justification lives here rather than in a commit message.
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

	/* ---- the art patches. Read the family note above the array first. ---- */

	{
		id: 'zombie-arms',
		at: 'html:911',
		why: "THE WALKER HAD ITS ARMS FOLDED ACROSS ITS CHEST. The arm is a rect chain "
			+ "hanging from a shoulder at x=+-8.5 and then rotated INWARD by "
			+ "1.05 - reach*0.55 radians. In the walk cycle reach is 0.25+-0.08 "
			+ "(html:980), so that angle is 0.868-0.956 rad — 50 to 55 degrees. Over the "
			+ "21 px from shoulder to the centre of the hand rect that is 16.0-17.2 px of "
			+ "inward travel, which lands each hand 7.5-8.7 px past the centreline, on the "
			+ "far side of the body. The hands do not fold, they cross. A player reported "
			+ "it on the live build and it is the pose you see most, because a zombie "
			+ "walking at you is drawn on the atlas anchor row and that row is this "
			+ "function unmodified.\n"
			+ "\n"
			+ "THE ANCESTOR AGREES IT IS WRONG. Its own comment one line above the block "
			+ "is `// arms, reaching` (html:899). tools/gen/views.js:169-172 reached the "
			+ "same verdict independently while building the turned bearings — \"at 90 "
			+ "degrees the ancestor's reach would still be drawn across the chest instead "
			+ "of out in front of the body, which is the whole tell of a zombie\" — and "
			+ "fixed rows 1-4 with body-space keypoints, leaving row 0 to this line. So "
			+ "the shipped walker hugged itself head-on and reached once it turned.\n"
			+ "\n"
			+ "The fix inverts the coupling: reach now OPENS the arms rather than "
			+ "unfolding a hug. 0.10 + reach*0.40 is pinned to the ancestor at the lunge — "
			+ "at reach 1.0 both formulas give exactly 0.50 rad, so the attack's second "
			+ "frame is unchanged to the pixel and the hands still converge in front of "
			+ "the chest, which is how a flat front view says `reaching at you`. At the "
			+ "walk's reach it gives 0.168-0.232 rad (10-13 deg), putting each hand at "
			+ "x=+3.7 to +5.0 — beside its own hip, the torso being 7 px half-wide there.\n"
			+ "\n"
			+ "The swing term also loses its `side`. Multiplied by side it moved both arms "
			+ "inward and outward TOGETHER, which is a breath rather than a stride, and at "
			+ "0.05 rad it was 2.5 degrees of it. Unmultiplied it is contralateral: one arm "
			+ "forward while the other trails.\n"
			+ "\n"
			+ "0.16 IS THE LARGEST STRIDE THAT FITS INSIDE THE ANCESTOR'S HIT RADIUS, and "
			+ "that is a hard ceiling rather than taste. HIT_RADIUS is pinned at 0.30 m — "
			+ "`r: isDog?0.30:0.30`, html:2214 — and scripts/dev/checks/enemies.gd asserts "
			+ "both that the capsule IS that number and that it covers 95% of the head-on "
			+ "silhouette. Arms that swing wider than the capsule are arms a player can see "
			+ "and cannot shoot. The first cut of this patch used 0.22 and took head-on "
			+ "coverage to 94.76%, which failed that floor; the value here was swept "
			+ "against it rather than guessed:\n"
			+ "      k=0.22  94.76%   under          k=0.13  95.26%\n"
			+ "      k=0.19  94.98%   under          k=0.10  95.37%\n"
			+ "      k=0.16  95.15%   OK             k=0.00  95.37%\n"
			+ "0.10 and 0.00 read the same because below about 0.10 the hand no longer "
			+ "reaches past the shoulders and the swing stops being what decides the width "
			+ "at all — so the whole usable range is 0 to 0.16 and this is the top of it. "
			+ "Still +-7.9 degrees at the walk's swing of +-0.866, against the ancestor's "
			+ "+-2.5, and contralateral where the ancestor's was symmetric.",
		from: "    g.rotate(side*(1.05 - o.reach*0.55) + o.swing*side*0.05);",
		to: "    g.rotate(side*(0.10 + o.reach*0.40) + o.swing*0.16);",
	},
	{
		id: 'zombie-walk-phase',
		at: 'html:978-980',
		why: "THE SIX-FRAME WALK CYCLE WAS THREE IMAGES. Measured on the committed "
			+ "assets/sprites/zombie0_walk.png, byte-identical and not merely close:\n"
			+ "  frame 0 == frame 3,  frame 1 == frame 2,  frame 4 == frame 5\n"
			+ "  distinct frames: 3 of 6\n"
			+ "Every driver passed to zombieBody was symmetric about the same two phases: "
			+ "swing is sin(ph) and reach is sin(ph), both symmetric about ph=90 and 270 "
			+ "degrees, and bob is |cos(ph)|, symmetric about the same pair. Sampling six "
			+ "phases of functions that all fold there can only produce three poses. At "
			+ "8 fps (SpriteLib._add_set) that is an effective 4 fps shamble, with the "
			+ "neutral pose showing twice as often as either extreme — and it cost the "
			+ "full six cells per row in every atlas to do it.\n"
			+ "\n"
			+ "`lean` was the one driver held constant, so it is the one that fixes this: "
			+ "cos(ph) is symmetric about 0 and 180 degrees, NOT about 90 and 270, so it "
			+ "cannot fold where the others do. The six (swing, lean) pairs become "
			+ "(0,2.0) (.87,1.5) (.87,0.5) (0,0.0) (-.87,0.5) (-.87,1.5) — all distinct, "
			+ "six poses out of the same six cells and the same file size.\n"
			+ "\n"
			+ "It also buys the thing the walk most visibly lacked: lean rotates "
			+ "everything above the hips by lean*0.03 rad (html:876), so the torso now "
			+ "rocks 3.4 degrees peak to peak and the head travels about 2.6 px. The "
			+ "amplitude is chosen so the peak of 2.0 stays UNDER the attack frames' 2.4 "
			+ "(html:986): views.js:163-165 records that the lean is what separates the "
			+ "lunge from the walk, and a walk that out-leaned the lunge would erase that.",
		from:
			"      const ph = f/6*TAU;\n" +
			"      zombieBody(g,p,{swing:Math.sin(ph), bob:Math.abs(Math.cos(ph))*1.6,\n" +
			"                      reach:0.25+Math.sin(ph)*0.08, lean:1, tornArm:p===ZPAL[2], ribs:p!==ZPAL[1]});",
		to:
			"      const ph = f/6*TAU;\n" +
			"      zombieBody(g,p,{swing:Math.sin(ph), bob:Math.abs(Math.cos(ph))*1.6,\n" +
			"                      reach:0.25+Math.sin(ph)*0.08, lean:1+Math.cos(ph), tornArm:p===ZPAL[2], ribs:p!==ZPAL[1]});",
	},
	{
		id: 'zombie-shadow',
		at: 'html:857-858',
		why: "THE GROUND SHADOW BOBBED WITH THE BODY, so the walker floated instead of "
			+ "treading. `base` is 62 - o.bob (html:851) and the shadow ellipse is placed "
			+ "at base+1, so a 1.6 px bob lifted the contact shadow 1.6 px off the floor "
			+ "with it. A contact shadow is the one thing in the frame that must NOT move "
			+ "vertically — it is what tells the eye where the ground is.\n"
			+ "\n"
			+ "Pinned to 63, which is what base+1 evaluates to at bob=0, so every frame "
			+ "the ancestor drew without a bob is unchanged to the pixel and only the "
			+ "raised frames differ. The radii shrink with the bob because that is the "
			+ "other half of what a real contact shadow does when its caster lifts, and "
			+ "it keeps the frames distinguishable now that the ellipse cannot move.",
		from:
			"  // shadow\n" +
			"  g.fillStyle='rgba(0,0,0,.34)';\n" +
			"  g.beginPath(); g.ellipse(0, base+1, 13, 3.4, 0,0,TAU); g.fill();",
		to:
			"  // shadow — pinned to the floor, see the `zombie-shadow` patch\n" +
			"  g.fillStyle='rgba(0,0,0,.34)';\n" +
			"  g.beginPath(); g.ellipse(0, 63, 13-o.bob*0.9, 3.4-o.bob*0.35, 0,0,TAU); g.fill();",
	},
	{
		id: 'zombie-ribs',
		at: 'html:885-897',
		why: "THE RUINED CHEST READS AS A RED-AND-WHITE STRIPED NECKTIE, and this patch "
			+ "only exists because `zombie-arms` exposed it. The folded arms were covering "
			+ "the chest on the front view; unfold them and what is underneath has to hold "
			+ "up on its own. It does not. Three full-width #C9C3AE bars evenly spaced "
			+ "down a 7-wide, 10-tall dark-red panel is a rep tie.\n"
			+ "\n"
			+ "EVERY CHEST DECAL IS SIZED FOR THE 45-DEGREE VIEW, NOT THE FRONT, because "
			+ "that is where the shape fails. The chest is a flat face at z=+4.5 and its "
			+ "width foreshortens by cos(yaw) while its height does not, so on row 1 of "
			+ "every atlas each decal gets 0.707 as wide and stays exactly as tall. "
			+ "Measured on the ancestor's own numbers at that bearing: the wound 7 px wide "
			+ "by 14 tall, aspect 2.0, and the upper blood run 4 px foreshortened to 2.8 "
			+ "against 9 tall, aspect 3.2. Those are tie proportions and no colour change "
			+ "fixes a proportion. The widths cannot be helped — 10 px of an 18 px chest "
			+ "really does project to 7.1 at 45 degrees — so everything else moves.\n"
			+ "\n"
			+ "  - exposed skin widens from 7 to 10 px, filling the gap between the coat "
			+ "lapels at +-5.5 (html:894) instead of leaving a 2 px strip of cloth down "
			+ "each side. An open coat, not a neckline.\n"
			+ "  - the wound goes from 7x10 to 10x8, the full width of that opening: wider "
			+ "than tall head-on, and 7.1x8 even at 45 degrees.\n"
			+ "  - the bone bars go from three full-width rungs to three 3.4 px ones "
			+ "alternating left and right, in #8E876F rather than #C9C3AE — about 70% of "
			+ "the brightness. Rib ENDS from a broken cage read as anatomy; a ladder of "
			+ "even full-width rungs reads as a pattern, and pattern is what the eye was "
			+ "calling a tie. 3.4 is chosen so that even foreshortened to 2.4 they never "
			+ "span the band and turn back into rungs.\n"
			+ "  - THE BLOOD RUNS COME OFF THE CENTRELINE ENTIRELY, from (-2,-30,4x9) and "
			+ "(-4,-26,3x5) to (-8.2,-30,4.5x7) and (2.2,-27,4x5) — one down the left "
			+ "lapel, one low on the right. This was the last thing to fall and the "
			+ "hardest to see: with the runs stacked under the wound and narrowing, the "
			+ "chest was a symmetric column tapering to a point, which is a tie no matter "
			+ "how good the individual rectangles are. Each rect's aspect was already "
			+ "fixed at that stage and it still read as a tie. Asymmetry is what killed it.\n"
			+ "\n"
			+ "A NOTE ON MEASURING THIS. The obvious metric — bounding box of the "
			+ "red-dominant pixels — cannot see the defect: it reported aspect 2.11 for "
			+ "row 0 against 2.14 for row 1, near-identical, while the two looked nothing "
			+ "alike, because it bounds three stacked decals and not the shape that was "
			+ "wrong. It was checked before it was trusted, per CLAUDE.md, found not to "
			+ "discriminate, and this patch was shaped by opening the PNGs instead.\n"
			+ "\n"
			+ "The coat lapels (html:893-894) are inside the patched range and deliberately "
			+ "unchanged — they are what the widened skin is measured against.\n"
			+ "\n"
			+ "Palette 1 draws no ribs at all (`ribs: p!==ZPAL[1]`, html:980) so for that "
			+ "corpse this is only the wider bare chest, which is the same improvement.",
		from:
			"  // open coat showing a ruined chest\n" +
			"  g.fillStyle=p.skin;\n" +
			"  g.fillRect(-3.5, base-40, 7, 17);\n" +
			"  if(o.ribs){\n" +
			"    g.fillStyle=p.wound; g.fillRect(-3.5, base-36, 7, 10);\n" +
			"    g.fillStyle='#C9C3AE';\n" +
			"    for(let i=0;i<3;i++) g.fillRect(-3, base-35+i*3, 6, 1.4);\n" +
			"  }\n" +
			"  g.fillStyle=p.clothD;\n" +
			"  g.fillRect(-9, base-42, 3.5, 23); g.fillRect(5.5, base-42, 3.5, 23);\n" +
			"  // blood down the front\n" +
			"  g.fillStyle='rgba(84,10,12,.6)';\n" +
			"  g.fillRect(-2, base-30, 4, 9); g.fillRect(-4, base-26, 3, 5);",
		to:
			"  // open coat showing a ruined chest — see the `zombie-ribs` patch\n" +
			"  g.fillStyle=p.skin;\n" +
			"  g.fillRect(-5, base-40, 10, 17);\n" +
			"  if(o.ribs){\n" +
			"    g.fillStyle=p.wound; g.fillRect(-5, base-36, 10, 8);\n" +
			"    g.fillStyle='#8E876F';\n" +
			"    for(let i=0;i<3;i++) g.fillRect(i%2 ? 1.2 : -4.6, base-35+i*2.4, 3.4, 1.2);\n" +
			"  }\n" +
			"  g.fillStyle=p.clothD;\n" +
			"  g.fillRect(-9, base-42, 3.5, 23); g.fillRect(5.5, base-42, 3.5, 23);\n" +
			"  // blood down the front\n" +
			"  g.fillStyle='rgba(84,10,12,.6)';\n" +
			"  g.fillRect(-8.2, base-30, 4.5, 7); g.fillRect(2.2, base-27, 4, 5);",
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
