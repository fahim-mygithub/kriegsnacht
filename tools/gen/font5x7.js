'use strict';

/* Bitmap fonts, defined here so the generator draws identical text on every
 * machine.
 *
 * kriegsnacht.html draws its five text runs through CSS font stacks —
 * `ui-monospace, monospace` (html:1256, 1259, 1998) and
 * `Haettenschweiler, "Arial Narrow", Impact, sans-serif` (html:1283, 1326,
 * 1426). `ui-monospace` is a CSS system keyword with no fixed face at all, and
 * the Haettenschweiler stack resolves to a different one of its three fallbacks
 * on Windows, macOS and a CI runner. R7 §A5 flagged the first stack; the second
 * has the same defect and reaches ten of the eighteen committed props. A
 * generator whose output depends on which machine ran it is not a generator, so
 * every one of those sites draws from these tables instead. The patch list
 * lives in extract.js.
 *
 * There are two faces, because the ancestor uses two text sizes and one bitmap
 * face cannot serve both. `large` is the 5x7 the plan asked for and covers
 * everything from `bold 9px` up. `small` is a 3x5 for the one 6px run: a 5x7
 * glyph is already 67% wider than a 6px monospace advance, so "BOWIE KNIFE"
 * needs 65 px of a 52 px plaque in the large face and 43 px in the small one.
 * Using the large face there would either clip the label or force the plaque
 * layout to be redesigned around a font, which is the tail wagging the dog.
 *
 * Glyphs are ASCII art on purpose: this is a committed asset that people will
 * need to read and edit in a diff, and a few lines of '#' and '.' per character
 * is the only encoding that survives that. */

/* Coverage is the full uppercase alphabet, the digits and the punctuation the
 * weapon table can produce — not just today's plaques. The WALLBUYS labels
 * (OLYMPIA / M14 / MP40 / STAKEOUT / PM63 / AK-74U / M16 / BOWIE KNIFE) need
 * '-' and space, the box pool adds CHINA LAKE and RAY GUN, and PAP_NAMES adds
 * '&' (Mustang & Sally) and an apostrophe (Porter's X2 Ray Gun). Renaming a
 * weapon must not silently blank a plaque. */
const LARGE = {
	w: 5, h: 7, glyphs: {
		' ': ['.....', '.....', '.....', '.....', '.....', '.....', '.....'],
		'A': ['.###.', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
		'B': ['####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'],
		'C': ['.###.', '#...#', '#....', '#....', '#....', '#...#', '.###.'],
		'D': ['####.', '#...#', '#...#', '#...#', '#...#', '#...#', '####.'],
		'E': ['#####', '#....', '#....', '####.', '#....', '#....', '#####'],
		'F': ['#####', '#....', '#....', '####.', '#....', '#....', '#....'],
		'G': ['.###.', '#...#', '#....', '#.###', '#...#', '#...#', '.###.'],
		'H': ['#...#', '#...#', '#...#', '#####', '#...#', '#...#', '#...#'],
		'I': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '#####'],
		'J': ['..###', '....#', '....#', '....#', '#...#', '#...#', '.###.'],
		'K': ['#...#', '#..#.', '#.#..', '##...', '#.#..', '#..#.', '#...#'],
		'L': ['#....', '#....', '#....', '#....', '#....', '#....', '#####'],
		'M': ['#...#', '##.##', '#.#.#', '#.#.#', '#...#', '#...#', '#...#'],
		'N': ['#...#', '#...#', '##..#', '#.#.#', '#..##', '#...#', '#...#'],
		'O': ['.###.', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
		'P': ['####.', '#...#', '#...#', '####.', '#....', '#....', '#....'],
		'Q': ['.###.', '#...#', '#...#', '#...#', '#.#.#', '#..#.', '.##.#'],
		'R': ['####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'],
		'S': ['.####', '#....', '#....', '.###.', '....#', '....#', '####.'],
		'T': ['#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'],
		'U': ['#...#', '#...#', '#...#', '#...#', '#...#', '#...#', '.###.'],
		'V': ['#...#', '#...#', '#...#', '#...#', '#...#', '.#.#.', '..#..'],
		'W': ['#...#', '#...#', '#...#', '#.#.#', '#.#.#', '##.##', '#...#'],
		'X': ['#...#', '#...#', '.#.#.', '..#..', '.#.#.', '#...#', '#...#'],
		'Y': ['#...#', '#...#', '.#.#.', '..#..', '..#..', '..#..', '..#..'],
		'Z': ['#####', '....#', '...#.', '..#..', '.#...', '#....', '#####'],
		'0': ['.###.', '#...#', '#..##', '#.#.#', '##..#', '#...#', '.###.'],
		'1': ['..#..', '.##..', '..#..', '..#..', '..#..', '..#..', '.###.'],
		'2': ['.###.', '#...#', '....#', '...#.', '..#..', '.#...', '#####'],
		'3': ['#####', '...#.', '..#..', '...#.', '....#', '#...#', '.###.'],
		'4': ['...#.', '..##.', '.#.#.', '#..#.', '#####', '...#.', '...#.'],
		'5': ['#####', '#....', '####.', '....#', '....#', '#...#', '.###.'],
		'6': ['..##.', '.#...', '#....', '####.', '#...#', '#...#', '.###.'],
		'7': ['#####', '....#', '...#.', '..#..', '.#...', '.#...', '.#...'],
		'8': ['.###.', '#...#', '#...#', '.###.', '#...#', '#...#', '.###.'],
		'9': ['.###.', '#...#', '#...#', '.####', '....#', '...#.', '.##..'],
		'-': ['.....', '.....', '.....', '#####', '.....', '.....', '.....'],
		'.': ['.....', '.....', '.....', '.....', '.....', '.##..', '.##..'],
		',': ['.....', '.....', '.....', '.....', '.##..', '.##..', '.#...'],
		"'": ['..#..', '..#..', '.#...', '.....', '.....', '.....', '.....'],
		'&': ['.##..', '#..#.', '#.#..', '.#...', '#.#.#', '#..#.', '.##.#'],
		':': ['.....', '.##..', '.##..', '.....', '.##..', '.##..', '.....'],
		'/': ['....#', '....#', '...#.', '..#..', '.#...', '#....', '#....'],
		'!': ['..#..', '..#..', '..#..', '..#..', '..#..', '.....', '..#..'],
		'?': ['.###.', '#...#', '....#', '...#.', '..#..', '.....', '..#..'],
		'+': ['.....', '..#..', '..#..', '#####', '..#..', '..#..', '.....'],
		'(': ['...#.', '..#..', '.#...', '.#...', '.#...', '..#..', '...#.'],
		')': ['.#...', '..#..', '...#.', '...#.', '...#.', '..#..', '.#...'],
	},
};

const SMALL = {
	w: 3, h: 5, glyphs: {
		' ': ['...', '...', '...', '...', '...'],
		'A': ['.#.', '#.#', '###', '#.#', '#.#'],
		'B': ['##.', '#.#', '##.', '#.#', '##.'],
		'C': ['.##', '#..', '#..', '#..', '.##'],
		'D': ['##.', '#.#', '#.#', '#.#', '##.'],
		'E': ['###', '#..', '##.', '#..', '###'],
		'F': ['###', '#..', '##.', '#..', '#..'],
		'G': ['.##', '#..', '#.#', '#.#', '.##'],
		'H': ['#.#', '#.#', '###', '#.#', '#.#'],
		'I': ['###', '.#.', '.#.', '.#.', '###'],
		'J': ['..#', '..#', '..#', '#.#', '.#.'],
		'K': ['#.#', '#.#', '##.', '#.#', '#.#'],
		'L': ['#..', '#..', '#..', '#..', '###'],
		// M keeps its middle row open and N fills it, because with both rows solid
		// "MP40" read as "NP40" at 3px.
		'M': ['#.#', '###', '#.#', '#.#', '#.#'],
		'N': ['#.#', '##.', '###', '.##', '#.#'],
		'O': ['.#.', '#.#', '#.#', '#.#', '.#.'],
		'P': ['##.', '#.#', '##.', '#..', '#..'],
		'Q': ['.#.', '#.#', '#.#', '###', '.##'],
		'R': ['##.', '#.#', '##.', '#.#', '#.#'],
		'S': ['.##', '#..', '.#.', '..#', '##.'],
		'T': ['###', '.#.', '.#.', '.#.', '.#.'],
		// U takes the flat bottom and V the point; sharing a bottom row made
		// "AK-74U" read as "AK-74V".
		'U': ['#.#', '#.#', '#.#', '#.#', '###'],
		'V': ['#.#', '#.#', '#.#', '.#.', '.#.'],
		'W': ['#.#', '#.#', '###', '###', '#.#'],
		'X': ['#.#', '#.#', '.#.', '#.#', '#.#'],
		'Y': ['#.#', '#.#', '.#.', '.#.', '.#.'],
		'Z': ['###', '..#', '.#.', '#..', '###'],
		'0': ['###', '#.#', '#.#', '#.#', '###'],
		'1': ['.#.', '##.', '.#.', '.#.', '###'],
		'2': ['##.', '..#', '.#.', '#..', '###'],
		'3': ['##.', '..#', '.#.', '..#', '##.'],
		'4': ['#.#', '#.#', '###', '..#', '..#'],
		'5': ['###', '#..', '##.', '..#', '##.'],
		'6': ['.#.', '#..', '###', '#.#', '.#.'],
		'7': ['###', '..#', '.#.', '.#.', '.#.'],
		'8': ['.#.', '#.#', '.#.', '#.#', '.#.'],
		'9': ['.#.', '#.#', '###', '..#', '.#.'],
		'-': ['...', '...', '###', '...', '...'],
		'.': ['...', '...', '...', '...', '.#.'],
		',': ['...', '...', '...', '.#.', '#..'],
		"'": ['.#.', '.#.', '...', '...', '...'],
		'&': ['.#.', '#.#', '.#.', '#.#', '.##'],
		':': ['...', '.#.', '...', '.#.', '...'],
		'/': ['..#', '..#', '.#.', '#..', '#..'],
		'!': ['.#.', '.#.', '.#.', '...', '.#.'],
		'?': ['##.', '..#', '.#.', '...', '.#.'],
		'+': ['...', '.#.', '###', '.#.', '...'],
		'(': ['..#', '.#.', '.#.', '.#.', '..#'],
		')': ['#..', '.#.', '.#.', '.#.', '#..'],
	},
};

const FACES = { large: LARGE, small: SMALL };

/* A label that renders in one face and blanks in the other is the exact class
 * of bug the plaques would show only after someone renamed a weapon, so the two
 * key sets are held identical at load. */
{
	const a = Object.keys(LARGE.glyphs).sort().join('');
	const b = Object.keys(SMALL.glyphs).sort().join('');
	if (a !== b) throw new Error('font5x7: the large and small faces cover different characters');
	for (const [face, f] of Object.entries(FACES)) {
		for (const [ch, rows] of Object.entries(f.glyphs)) {
			if (rows.length !== f.h || rows.some((r) => r.length !== f.w)) {
				throw new Error(`font5x7: ${face} glyph ${JSON.stringify(ch)} is not ${f.w}x${f.h}`);
			}
		}
	}
}

/* Bold is a second stamp one glyph-pixel to the right, which is how every
 * bitmap font has faked weight since the 1980s. It widens the cell by one
 * column, so advance has to account for it. */
const BOLD_DX = 1;

/* Gap between cells, in glyph-pixels. Invented: there is no ancestor number to
 * copy, because a CSS advance width is a property of the resolved face and not
 * of the call site. One is the smallest value that keeps adjacent glyphs apart. */
const TRACKING = 1;

/* Arial's cap height is 716/1000 em and Impact's is within a percent of it, so
 * a CSS `Npx` run draws capitals about 0.7*N tall. Deriving the integer scale
 * from that keeps every ancestor font size meaningful instead of replacing it
 * with a hand-picked multiplier: in the large face 9px, 10px and 14px land on
 * 1, 20px on 2 and 30px on 3 — and 3*7 = 21 px is exactly the cap height of the
 * perk machine's `bold 30px`. In the small face 6px lands on 1, for 5 px
 * against a 4.2 px cap. */
const CAP_RATIO = 0.7;


function faceOf(name) {
	const f = FACES[name || 'large'];
	if (!f) throw new Error(`font5x7: no face '${name}' (have ${Object.keys(FACES).join(', ')})`);
	return f;
}


function scaleFor(px, faceName) {
	return Math.max(1, Math.round(px * CAP_RATIO / faceOf(faceName).h));
}


/* Canvas ships 'start'/'end' as well as the physical names, and defaults to
 * 'start'. The generator only ever draws left to right, so both collapse. */
function normaliseAlign(a) {
	if (a === 'center') return 'center';
	if (a === 'right' || a === 'end') return 'right';
	return 'left';
}


/* Total advance width in destination pixels, so callers can centre and so the
 * fit check has something to test. */
function width(str, opts = {}) {
	if (str.length === 0) return 0;
	const f = faceOf(opts.face);
	const scale = opts.scale || scaleFor(opts.px || 10, opts.face);
	const cell = f.w + (opts.bold ? BOLD_DX : 0);
	return (str.length * (cell + TRACKING) - TRACKING) * scale;
}


/* Draws `str` with the same positional contract as ctx.fillText, so the patched
 * call sites keep the ancestor's literal coordinates:
 *   - alignment and baseline are read off the context, which is why the
 *     ancestor's own `g.textAlign=`/`g.textBaseline=` lines survive the patch
 *     and still mean what they meant,
 *   - the colour comes from ctx.fillStyle and the fade from ctx.globalAlpha,
 *     because this draws through fillRect,
 *   - nothing on the context is disturbed.
 *
 * `maxWidth` is fillText's own fourth argument, and it throws rather than
 * squeezing. Canvas silently condenses; a generator should not, because the
 * failure mode it hides is a plaque whose label runs off the edge — which is
 * exactly what the 5x7 face did to "BOWIE KNIFE" before the small face existed.
 *
 * A bitmap capital is a pixel or two off the CSS cap height it stands in for,
 * so text sits very slightly lower than the browser drew it. That is the whole
 * visual cost of determinism and it is not worth inventing per-site offsets
 * to hide. */
function text(ctx, str, x, y, opts = {}) {
	const f = faceOf(opts.face);
	const bold = !!opts.bold;
	const scale = opts.scale || scaleFor(opts.px || 10, opts.face);
	const align = normaliseAlign(opts.align || ctx.textAlign);
	const baseline = opts.baseline || ctx.textBaseline || 'alphabetic';

	const w = width(str, { scale, bold, face: opts.face });
	if (opts.maxWidth !== undefined && w > opts.maxWidth) {
		throw new Error(`font5x7: ${JSON.stringify(str)} is ${w}px wide in the ${opts.face || 'large'} face `
			+ `but only ${opts.maxWidth}px are available. Shorten the label, or drop to the `
			+ "'small' face if this is still on 'large'. The small face at scale 1 is the "
			+ 'narrowest this module goes: 4px per character.');
	}

	let left = x;
	if (align === 'center') left = x - w / 2;
	else if (align === 'right') left = x - w;

	let top = y - f.h * scale;
	if (baseline === 'middle') top = y - f.h * scale / 2;
	else if (baseline === 'top') top = y;

	// Snap to the destination pixel grid; a half-pixel origin would reintroduce
	// exactly the antialiasing this font exists to remove.
	left = Math.round(left);
	top = Math.round(top);

	const advance = (f.w + (bold ? BOLD_DX : 0) + TRACKING) * scale;
	for (let i = 0; i < str.length; i++) {
		const ch = str[i];
		const rows = f.glyphs[ch];
		if (!rows) {
			throw new Error(
				`font5x7: no glyph for ${JSON.stringify(ch)} (in ${JSON.stringify(str)}). `
				+ 'Add it to both faces in tools/gen/font5x7.js.');
		}
		const gx = left + i * advance;
		for (let row = 0; row < f.h; row++) {
			for (let col = 0; col < f.w; col++) {
				if (rows[row][col] !== '#') continue;
				ctx.fillRect(gx + col * scale, top + row * scale, scale, scale);
				if (bold) ctx.fillRect(gx + (col + BOLD_DX) * scale, top + row * scale, scale, scale);
			}
		}
	}
}


module.exports = { text, width, scaleFor, FACES, TRACKING, CAP_RATIO };
