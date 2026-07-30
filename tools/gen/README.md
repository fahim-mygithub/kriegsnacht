# `tools/gen` — the art pipeline, committed

Every PNG in `assets/` was drawn by `kriegsnacht.html`'s own Canvas 2D code. That
code was replayed once, by hand, and the harness that did it was never committed —
so for the whole of Milestone 1 no sprite in this project could be regenerated,
fixed or extended, and nobody could say exactly which lines produced which file.
This package is that harness, written down.

It does not transliterate anything. It reads `kriegsnacht.html` at run time,
slices five ranges out of it, applies six recorded substitutions, and runs the
result under Node with [`@napi-rs/canvas`](https://github.com/Brooooooklyn/canvas)
— which is Skia, the same rasteriser Chrome draws with.

## Running it

```
cd tools/gen && npm install          # ~37 MB of prebuilt Skia; no compiler needed
node tools/gen/gen.js --list         # every target, and which are not committed yet
node tools/gen/gen.js chalk_mp40     # write one PNG to its home in assets/
node tools/gen/gen.js --all          # write everything missing
node tools/gen/gen.js --all --check  # write nothing; diff against what is committed
node tools/gen/extract.js --report   # the provenance dump: ranges, patches, hashes
```

`gen.js` **never overwrites a committed file** without `--force`. That is not
politeness: a regeneration is *near*-identical rather than identical (see
[Drift](#drift-against-the-committed-art)), and replacing seventeen sprite strips
with near-identical ones produces a diff nobody can review.

Do not hand-write `.import` files for new PNGs. Godot writes those, and this
project needs settings (`detect_3d/compress_to=0`) that are applied centrally.

## What is extracted

Resolved by anchor, not by hard-coded line number, and verified on
**2026-07-27** against `kriegsnacht.html` at
`sha256 0d48059a4a5efe5b7bc785f47c51791fa08d691d6e57019fde79912341af7e0d`
(139 769 bytes, 3 477 lines). `extract.js --report` reprints this at any time.

| Range | Lines | Opening symbol | Closing symbol | Why |
|---|---|---|---|---|
| `utils` | **374-392** | `const TAU` | `const sr` | `TAU`, `clamp`/`lerp`, the `RGB`/`RGBA` packers, and the xorshift PRNG (`_seed`, `srnd`, `sr`) every texture draws through. |
| `art` | **564-1448** | `function makeCanvas` | end of `buildSprites` | Sections 2 and 3 entire: `bake`/`grain`/`splotch`, all 21 textures, `ZPAL`, `zombieBody`, `outlineSprite`, the walker/crawler/hound sets, `GUNART`, `drawParts`, `makeViewmodel`, `makeChalk`, `makePerkMachine`, `makeBox`, `makeGenerator`, `makePowerup`, `buildSprites`. |
| `weapons` | **1452-1471** | `const W_` | end of `WEAPONS` | Plaque labels and the `art` key each plaque draws. Pure data. |
| `wallbuys` | **1550-1559** | `const WALLBUYS` | `const BOWIE` | Which plaques exist and what each costs. |
| `pap` | **1986-2012** | `function makePaP` | its closing brace | The Pack-a-Punch machine. |

**961 lines total.**

### Corrections to the plan

SYNTHESIS §6 (Milestone 2) says to extract *"374-392 + 564-1450"*.

- **374-392 is exact.** 374 is `const TAU`, 392 is `const sr`. 393 is blank and
  **394 is `const reduceMotion = window.matchMedia(...)`**, which throws in Node —
  so the upper bound matters and is correct.
- **564-1450 overshoots by two lines and, much more importantly, misses
  `makePaP` entirely.** `buildSprites` closes at 1448; 1449-1451 are the
  section-4 comment. And `makePaP` is at **1986-2012**, in section 8, seven
  hundred lines below everything else — *this is why `assets/props/` had no
  Pack-a-Punch machine*. The gap was never an art decision; it was an off-by-a-
  section-boundary in a range that nobody wrote down. R7 §A1's own table says
  "`makePerkMachine` / `makeBox` / `makeGenerator` / `makePowerup` / `makePaP` |
  1271–2011", collapsing a 700-line gap into one row, which is how it slipped past.
- The plan also lists `makeChalk` at 1244-1262. **That is exact.**

### What is deliberately *not* extracted

- `makeViewmodel` (html:1210-1241) is inside the `art` range and runs fine, but
  emits 200x120 2D gun art for a software raycaster. The Godot viewmodel is a
  real mesh (SYNTHESIS §4.1), so nothing consumes it. It is not in `EXPORTS`;
  add the name there when something needs it.
- `dataToCanvas` (html:2013-2019) exists to hand a `bake()` buffer back to a
  canvas for `drawImage`. `png.js` writes the buffer straight out instead.
- ~~The 8-direction atlas (SYNTHESIS §4.2)~~ — **built, 2026-07-29**, and not by
  threading `yaw` into `zombieBody` after all. See
  [The 8-direction atlas](#the-8-direction-atlas) below.

## The 8-direction atlas

`views.js` and `atlas.js` are the one part of this package that **is not the
ancestor's drawing code**, and they say so at the top of both files. The ancestor
draws exactly one view of each enemy — `makeZombieSet` (html:973), `makeCrawlerSet`
(html:1043), `makeHoundSet` (html:1090) — so a zombie walking away from you still
faced you. There is no ancestor code for the other seven bearings.

Output goes to **new files**, `<stem>_dir.png`, one per kind/palette/cycle:
frames left to right as before, five bearings stacked top to bottom (0, 45, 90,
135, 180 degrees; the other three are `flip_h` at runtime).
`scripts/world/sprite_lib.gd` prefers them and falls back to the single-view strip
when one is absent.

**The seventeen committed strips are untouched.** That is deliberate and it is
why the [drift table](#drift-against-the-committed-art) below is still valid.

### What is still the ancestor's

| | |
|---|---|
| `ZPAL` | the three corpse palettes, html:844-848 |
| `outlineSprite` | the 1px rim every silhouette carries, html:955-969 |
| `bake` | the canvas harness, html:571 |
| frame parameter tables | the swing/bob/reach/lean per frame, transcribed from the ancestor's own loops (html:975-999, 1078-1086, 1115-1123) |
| **one whole row of every strip** | see below |

Three names were added to `EXPORTS` in `extract.js` for this — `bake`,
`outlineSprite`, `ZPAL` — which is why `EXPECTED_SHA` moved on 2026-07-29. The 961
extracted lines are byte-identical; the hash covers the assembled module, and the
module's last line is the exports list.

### The anchor row

One row of each atlas is not new art at all:

| kind | row | why |
|---|---|---|
| walker | **0** (facing you) | the ancestor draws it front-on, so `zombieBody` is called unmodified |
| crawler | **2** (profile) | the ancestor draws it in profile, head to the left (html:1071) |
| hound | **2** (profile) | likewise, head at `translate(-16,...)` (html:1114) |

Both profiles face screen-**left** and this package's yaw convention puts the
body's forward at screen-right, so the crawler's and the hound's frames are
*mirrored* into row 2 rather than redrawn. Nothing the ancestor already drew is
drawn again.

`scripts/dev/checks/enemies.gd` asserts this against the shipped PNGs — not by
byte equality, which would fail on a correct build for the reasons in
[Drift](#drift-against-the-committed-art), but by requiring the anchor row to be
several times closer to the committed frame than any other row is.

### The projection

Every new pose is one body model seen from five bearings, not five hand-drawn
poses. Parts live in body space — x to the body's right, z out of its chest, y
down the screen exactly as the ancestor's coordinates run — and project with

```
screen_x = x*cos(yaw) + z*sin(yaw)
depth    = z*cos(yaw) - x*sin(yaw)        // larger = nearer the camera
```

At yaw 0 that is the identity on x, which is why the walker's turned views put
the head, shoulders, hips and boots on the same scanlines its anchor row does.
`depth` orders the painter's pass, so an arm behind a torso is behind it with no
per-view special case, and a surface is drawn only when its own outward normal
faces the camera — which is what gives a profile one eye and the two rear
bearings none.

**A zombie with its back to you does not glow at you.** That is the single most
visible thing the atlas buys and it is asserted in `enemies.gd` rather than left
to a screenshot.

### What is invented, and admitted

- The back of the walker's coat. The ancestor never drew one, so it is a seam and
  a shoulder-blade shadow and nothing more.
- The hound's neck. In profile the head ellipse overlaps the body and none is
  needed; from 45 degrees the head reads as a floating lantern without one.
- The hound's ember scatter uses a local xorshift rather than the ancestor's
  `sr()`, because `_seed` is a module-level `let` inside the extraction and is not
  reachable from outside it. Same shape, seeded per frame, deterministic.
- The eye halo on a turned hound is smaller than the ancestor's 7.6x6.6 rect,
  which only works because that rect falls inside a profile skull.

## The six patches

Every text run in the ancestor is drawn through a CSS font stack, and **every one
of them is machine-dependent**:

- `ui-monospace, monospace` — `ui-monospace` is a CSS *system-font keyword*. It
  has no fixed face by definition and does not exist in Node at all.
- `Haettenschweiler, "Arial Narrow", Impact, sans-serif` — resolves to
  Haettenschweiler on most Windows installs, Impact on macOS, and DejaVu Sans on
  a Linux CI runner.

R7 §A5 flagged the first stack. **The second has the same defect and reaches ten
of the eighteen committed props** — the eight perk machines, `box_closed` and
`pu_points` — which the research did not record. A generator whose output depends
on which machine ran it is not a generator, so all six sites are rewritten to draw
from `font5x7.js`.

| id | html | change |
|---|---|---|
| `chalk-label` | 1256-1257 | weapon name → 3x5 face at `px:6`, `maxWidth: W-4` |
| `chalk-cost` | 1259-1260 | price → 5x7 face, bold, `px:10`, `maxWidth: W-4` |
| `perk-letter` | 1283-1288 | J/S/D/Q → 5x7 at `px:30`; **`bold` dropped** |
| `box-question` | 1326-1327 | `?` → 5x7, bold, `px:20` |
| `powerup-x2` | 1426-1427 | `X2` → 5x7, bold, `px:14` |
| `pap-label` | 1998-1999 | `PAP` → 5x7, bold, `px:9` |

Each `from` string must match **exactly once** or extraction fails. The
ancestor's `g.textAlign=` / `g.textBaseline=` lines are left in place and stay
load-bearing: `font5x7.text()` reads them off the context exactly as `fillText`
did, and draws through `fillRect`, so `globalAlpha` keeps working too.

`bold` is dropped only on `perk-letter`, and only because at scale 3 the
double-stamp is a 6 px stroke on a 15 px glyph, which closes the counters of D, Q
and O into blobs. Haettenschweiler is an ultra-condensed heavy face where `bold`
was close to a no-op anyway.

## The font

`font5x7.js` holds two faces as editable ASCII art:

- **`large`, 5x7** — the one the plan asked for. Serves `bold 9px` and up.
- **`small`, 3x5** — the one 6 px run, the chalk plaque's weapon name.

The second face is not a flourish. A 5x7 glyph at its smallest is 6 px of advance
against a 6 px monospace font's ~3.6 px, so `"BOWIE KNIFE"` wants **65 px of a
52 px plaque** in the large face and fits in **43** in the small one. The first
render of this package clipped it to `OWIE KNIF`; `maxWidth` now makes that a
thrown error instead of a shipped sprite.

Scale is derived, not chosen:

```
scale = max(1, round(cssPx * 0.7 / faceHeight))
```

`0.7` is the cap-height/em ratio of the faces the ancestor names (Arial's cap
height is 716/1000 em; Impact's is within a percent). It lands `9px`, `10px` and
`14px` on scale 1, `20px` on 2, and `30px` on 3 — and 3 × 7 = **21 px is exactly
the cap height of the perk machine's `bold 30px`**.

Tracking is 1 glyph-pixel. That one is invented: a CSS advance width is a
property of the resolved face, not of the call site, so there is no ancestor
number to copy.

Both faces cover the same character set — the full uppercase alphabet, the
digits, and the punctuation `WEAPONS`, `PAP_NAMES` and the plaques can produce
(`- . , ' & : / ! ? + ( )`). The module asserts at load that the two key sets are
identical, because a label that renders in one face and blanks in the other is a
bug that would only surface after someone renamed a weapon. An unknown character
throws rather than drawing nothing.

## Drift against the committed art

`node tools/gen/gen.js --all --check` compares **premultiplied** pixels against
what is in `assets/`. Not file bytes: every committed PNG carries Chromium's IDAT
chunking, which is a property of the encoder that wrote it. And not straight
RGBA: both rasterisers store premultiplied and unpremultiply on the way out, so
an alpha-3 pixel reads `(255,255,85)` here and `(170,170,0)` in the committed
file — a "delta of 255" on a pixel that is 1% opaque and identical on screen.

Measured 2026-07-27, all 56 committed files:

| group | files | worst mean delta | worst max delta | cause |
|---|---|---|---|---|
| textures | 21 | 2.10 | 7 | `grain()` alpha rounding, Skia-in-Blink vs standalone |
| enemies | 17 | 2.64 | 205 | `outlineSprite` rim pixels flipping |
| generator | 2 | 2.86 | 186 | same rim |
| perk machines | 8 | 11.44 | 154 | **the font patch** |
| box | 3 | 27.88 | 150 | **the font patch** (`box_closed` only; open/teddy max 3) |
| power-ups | 5 | 12.83 | 91 | **the font patch** (`pu_points` only; the rest max 4) |

Two distinct stories, and they should not be confused:

1. **Rasteriser noise** — textures, enemies, generator, `box_open`, `box_teddy`,
   `pu_ammo/insta/nuke/carp`. Nothing here is a decision; it is Skia-standalone
   antialiasing against Skia-inside-Blink. `outlineSprite`'s hard threshold
   (`alpha > 18`, neighbour `alpha > 80`, html:965-967) turns a ±1 alpha wobble
   into a rim pixel that is fully present or fully absent — hence max deltas of
   exactly **205**, the alpha of the rim colour `rgba(6,6,5,205)`. R7 §A2
   measured `zombie0_walk` at 3 860 differing pixels (20.94%); this package
   reproduces **3 860 / 20.94%**, which is a useful independent check that the
   pipeline is the same one the research executed.
2. **The font patch** — the eight perk machines, `box_closed`, `pu_points`. These
   are the ten files whose glyphs changed shape on purpose. Regenerating them is
   a real, visible art change and needs a human to look at a frame before it is
   adopted. **None of them has been overwritten.**

## Layout

| file | what |
|---|---|
| `extract.js` | ranges, patches, `EXPECTED_SHA`, assembles + loads the bundle |
| `shim.js` | the two-line `document` shim, plus the `FONT` binding the patches need |
| `font5x7.js` | the two bitmap faces and `text()` |
| `png.js` | 8-bit RGBA encoder and decoder, no dependency |
| `targets.js` | the manifest: name → destination, size, provenance note |
| `views.js` | **not ancestor code** — the five turned poses per body |
| `atlas.js` | stitches those plus the anchor row into `<stem>_dir.png` |
| `gen.js` | the CLI |
| `ancestor.generated.js` | written every run, gitignored — **read this when something breaks** |

`EXPECTED_SHA` in `extract.js` pins the assembled extraction. If
`kriegsnacht.html`, an anchor or a patch moves, every command fails with both
hashes and a pointer to `--report`. Read the diff, then paste the new hash in.
That guard is the only thing standing between a silent ancestor edit and a
silently different sprite.

## Adding a target

1. Make sure the drawing function is inside an extracted range and named in
   `EXPORTS` in `extract.js`.
2. Add an `add(...)` line to `build()` in `targets.js` with its destination
   directory and an `html:` citation.
3. `node tools/gen/gen.js --list` to confirm, then generate it.

## Determinism

Same commit, same `@napi-rs/canvas` version (pinned exactly in `package.json` —
a Skia bump changes pixels), same output on any machine. The fonts are the repo's
own, the PRNG is the ancestor's seeded xorshift, and `png.js` writes filter-0
scanlines through `zlib` at a fixed level.

What is *not* guaranteed is byte-equality with the committed art, which came out
of Blink. R7 §A4 costed a Playwright capture as the only byte-identical route and
concluded it is not worth a 150 MB browser download and an async harness to chase
a mean delta of 2 / 255. That conclusion still holds.
