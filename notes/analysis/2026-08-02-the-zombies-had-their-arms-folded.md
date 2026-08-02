# The zombies had their arms folded

Reported by the player, against the live build:

> I'm noticing that the zombies have crossed arms. I do like the 2d billboard
> style can we improve on the visual representation?

They did, and the hands crossed **past** each other. Pulling that thread found
three more defects in the same sprite, one of which meant the walk cycle had been
half of what it cost since Milestone 1.

---

## Four defects, one sprite

### 1. The arms were folded, and the ancestor knew they should not be

`kriegsnacht.html:911`:

```js
g.rotate(side*(1.05 - o.reach*0.55) + o.swing*side*0.05);
```

The arm is a rect chain hanging from a shoulder at `x = ±8.5`, rotated **inward**.
In the walk cycle `reach` is `0.25 ± 0.08` (html:980), so the angle is 0.868–0.956
rad — **50 to 55 degrees**. Over the 21 px from shoulder to the centre of the hand
rect that is 16.0–17.2 px of inward travel, landing each hand **7.5–8.7 px past the
centreline, on the far side of the body**.

The ancestor's own comment one line above is `// arms, reaching` (html:899). The
intent was a reach; the numbers delivered a hug.

**This had already been diagnosed once and half-fixed.** `tools/gen/views.js:169-172`
says it almost word for word — *"at 90 degrees the ancestor's reach would still be
drawn across the chest instead of out in front of the body, which is the whole tell
of a zombie"* — and rebuilt rows 1–4 on body-space keypoints. Row 0 was left to
`zombieBody`, because row 0 is the walker's anchor row. So the shipped walker
**hugged itself head-on and reached once it turned**, and head-on is the bearing a
zombie chasing you is nearly always on.

### 2. The six-frame walk cycle was three images

Measured on the committed `assets/sprites/zombie0_walk.png`, byte-identical and not
merely close:

```
frame 0 == frame 3
frame 1 == frame 2
frame 4 == frame 5
distinct frames: 3 of 6
```

Every driver was symmetric about the same two phases — `swing` is `sin(ph)`,
`reach` is `sin(ph)`, `bob` is `|cos(ph)|`, and all three fold about ph = 90° and
270°. Six samples of functions that all fold there can only make three poses. At
8 fps that is an effective 4 fps shamble with the neutral pose showing twice as
often as either extreme, and it cost the full six cells per row in every atlas —
6 × 5 rows × 3 palettes × 3 cycles — to do it.

`lean` was the one driver held constant, which is why it is the one that fixes it:
`cos(ph)` is symmetric about 0° and 180°, not 90° and 270°, so it cannot fold where
the others do.

### 3. The ruined chest was a red-and-white striped necktie

Only visible **because** defect 1 was fixed: the folded arms had been covering the
chest. Three full-width `#C9C3AE` bars evenly spaced down a 7×10 dark-red panel is
a rep tie, and the turned bearings had it worse — the chest is a flat face at
z = +4.5, so its width foreshortens by cos(yaw) while its height does not, and on
row 1 every decal on it is 0.707 as wide and exactly as tall. The wound measured 7
wide by 14 tall there, aspect 2.0; the upper blood run 2.8 by 9, aspect 3.2.

### 4. The ground shadow bobbed with the body

`base` is `62 - o.bob` (html:851) and the shadow ellipse sat at `base+1`, so a
1.6 px bob lifted the contact shadow off the floor with it. The walker floated
rather than trod. A contact shadow is the one thing in a frame that must not move
vertically — it is what tells the eye where the ground is.

### and the horde read as three clones

Not a defect, a gap: the atlas ships three palettes and a round of 24 draws from
them, so eight bodies on screen were pixel-identical to eight others.

---

## The fixes

Four **recorded art patches** in `tools/gen/extract.js`, which until now held six
patches all of which were forced (a CSS font stack that resolves differently per
machine). These four are the first *deliberate departures* in the art path, and the
array's header comment now separates the two families, because they are not the same
kind of change and a reader should not have to guess which is which.

| id | what |
|---|---|
| `zombie-arms` | reach OPENS the arms instead of unfolding a hug; the swing loses its `side` and becomes contralateral |
| `zombie-walk-phase` | `lean: 1 + Math.cos(ph)`, giving six distinct poses from the same six cells |
| `zombie-ribs` | the whole chest reshaped — see below |
| `zombie-shadow` | the shadow pinned to y=63 and shrinking with the bob |

`views.js` moves with them, because rows 1–4 are the same body: the rib geometry is
mirrored, and **the arm angle is now derived from the same expression rather than
copied as numbers**, so row 0 and row 1 cannot disagree about where a hand is. A
seam there is what a player sees the moment a zombie turns.

`zombie.gd` gains `_tint`, a per-body multiplicative shade on `Rng.VISUAL`. All
three writers of `_sprite.modulate` carry it — the frame-by-frame flash, the
collapse, and the corpse fade — because any one of them that did not would revert
the body to the flat palette on its next frame.

### Two things the fixes were shaped by

**The arm swing is capped by the ancestor's hit radius.** `HIT_RADIUS` is pinned at
0.30 m (`r: isDog?0.30:0.30`, html:2214) and `checks/enemies.gd` asserts both that
the capsule is that number and that it covers 95% of the head-on silhouette. Arms
that swing wider than the capsule are arms a player can see and cannot shoot. The
first cut used 0.22 and dropped head-on coverage to 94.76%, which **failed that
floor on the first full run**. Swept rather than guessed:

| k | coverage | | k | coverage |
|---|---|---|---|---|
| 0.22 | 94.76% under | | 0.13 | 95.26% |
| 0.19 | 94.98% under | | 0.10 | 95.37% |
| 0.16 | **95.15% OK** | | 0.00 | 95.37% |

0.10 and 0.00 read the same because below about 0.10 the hand no longer reaches past
the shoulders and the swing stops deciding the width at all. The usable range is
0 to 0.16 and 0.16 is the top of it — still ±7.9° against the ancestor's ±2.5°, and
contralateral where the ancestor's was symmetric.

**The necktie was killed by asymmetry, not by aspect ratio.** Every individual
rectangle was already wider than tall and it *still* read as a tie, because the
wound and the two blood runs formed a symmetric column narrowing to a point. The
blood came off the centreline entirely — one down the left lapel, one low on the
right — and that is what fixed it. Recorded because the obvious diagnosis (fix the
proportions) was tried first and was not enough.

---

## The finding that nearly sank the whole thing

**Godot did not reimport the regenerated PNGs, and without an assertion that reads
through the loader the entire art change would have shipped as a no-op.**

`--verify` loads `.godot/imported/*.ctex`, not `assets/sprites/*.png`. After
`gen.js --force` rewrote all eighteen sprites, the recorded `source_md5` in
`zombie0_walk_dir.png-*.md5` was `11cf76cf…` against an actual `58f1618f…` — and
the suite happily loaded the old texture. The new check reported `3 distinct of 6`
while the PNG on disk plainly had six, which is what exposed it.

`--headless --path . --import` is the fix. It starts the editor, so it is exactly
the operation CLAUDE.md warns rewrites `project.godot` and strips its comments — it
was run behind a hash guard every time and `project.godot` came back identical
(same md5, 42 comments, `rendering_method.web` intact) on both runs.

This is the second time on this project that "assert through the real path" was the
difference between a check and a decoration, and the first time it caught a defect
in the *build pipeline* rather than in the code under test.

---

## The assertions, and their controls

Twelve, in `checks/enemies.gd`. `ASSERTION_FLOOR` 680 → 692, raised additively.

Eight controls, each required to fail the check named for it:

| control | verdict |
|---|---|
| `walk-phase reverted to lean:1` (regenerate + reimport) | fails all 3 palette checks; attack and death stay green |
| `flash-ignores-tint` | fails *sixteen bodies … are sixteen shades* |
| `tint-out-of-range` | fails *no body strays outside the declared tint range* |
| `collapse-clears-tint` | fails *the tint survives the collapse* |
| `corpse-never-fades` | fails *a corpse still fades* |
| `corpse-fades-grey` | fails *…and fades as the body it was* |
| `tint-on-gameplay-stream` | fails *the tint moves when only the cosmetic stream moves* |
| `gameplay-on-cosmetic-stream` | fails *…and the body itself does not* (+1 collateral) |

The last two are a matched pair and so are the two corpse-fade ones: each sabotage
of the fade breaks exactly one of them, which is what makes either worth having.

The RNG check is deliberately **differential rather than nominal**. It does not ask
which stream the code names; it rewinds the five gameplay streams to a snapshot,
moves only VISUAL, and requires two bodies to differ in colour and agree in speed.
Move the tint draw to `Rng.AI` and the first half fails, because both bodies then
replay the same rewound AI sequence and come out the same shade.

## What is NOT asserted, and why

**The arm pose — the thing the player actually reported.** Three metrics were tried
against the before and after art and none discriminates:

| metric | bug | fixed | |
|---|---|---|---|
| widest skin span below the chest | 21 px | 16–18 px | real, but the **wrong way round** from the obvious prediction, and a 3 px gap |
| scanlines with two separated skin runs | 7–8 | 9–11 | overlapping |
| skin on the centreline | 4–5 | 4–9 | **higher after the fix** — the same package widened the bare chest, and chest is skin |
| wound-fill aspect (w/h) | 1.20 | 1.50 | both above 1; the bug's wound was mostly hidden behind the folded arms |

A fifth — bounding box of all red-dominant pixels — reported 2.11 for row 0 against
2.14 for row 1 while the two looked nothing alike, because it bounds three stacked
decals rather than the shape that was wrong.

No cheap pixel statistic separates "arms at the hips" from "arms across the chest"
on this sprite. A check that cannot separate them is decoration of exactly the kind
`enemies.gd` exists to avoid, so none of them shipped and the file's header records
all four numbers. What guards the pose instead is the generator: `EXPECTED_SHA` pins
the whole patched extraction and every patch must match its anchor exactly once, so
dropping or editing `zombie-arms` fails `node tools/gen/extract.js --report` loudly.
The visual half is `--shot` and the frames gate.

## What was not done

**Per-zombie scale jitter**, which was in the brief. It is not safe here.
`head_threshold()` is `_height * 0.70` (zombie.gd:898) and `_height` also drives the
capsule and the eye position, so scaling the sprite alone desynchronises the visible
head from the band that scores a headshot — a cosmetic change producing an aiming
bug. Scaling `_height` instead moves the hitbox and the headshot band, which is
gameplay, and BO1 has no height variation to appeal to. Width-only scale would dodge
both, but `SpriteBase3D` billboarding normalises the basis and discards non-uniform
node scale, so it is not reachable without a custom shader.

The tint carries the variety on its own. The horde in `ref/horde.png` is six visibly
different bodies where it was six clones.

## What is uncertain

- **One build run failed 692/1 and the failing check was not captured.** Three runs
  since — two standalone `--verify` and one full `build.ps1` — were 693/0. It
  matches the load-dependent sweep-budget flake recorded on 2026-08-01, which also
  appeared under concurrent load, but that is inference and not evidence.
- **The web build has not been played by hand.** The frames gate is a desktop
  windowed pass; nothing here was verified in a browser beyond the page loading.
- The tint is rolled per client, so in co-op the same zombie is a slightly different
  shade on each screen. Cosmetic and consistent with how the spawn frame phase
  already behaves, but it is a divergence and it is not asserted either way.
