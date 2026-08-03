extends RefCounted

## The browser build's weapon part lists (kriegsnacht.html:1151), transliterated,
## and the extrusion that turns one into a viewmodel mesh.
##
## `GUNART` is already a 3D-ready specification and nobody noticed: 84 axis-aligned
## rectangles in a 100x60 space, plus 13 circles, **two** rotated rects (mp40
## `:1166`, pm63 `:1169`) and **two** polygons (both the knife's, `:1203`-`:1204`).
## A rect becomes a box, a circle becomes a low-segment cylinder, a polygon becomes
## a prism — and twelve weapons plus the knife come out of one builder with no
## files, no licences and no art pass. Every plan document for this package says
## "one rotated rect and one polygon"; a builder written to that would have
## silently dropped the PM63's stock and the knife's blade highlight. The
## ancestor drew the same table at two scales, 1.9 for the viewmodel (`:1210`) and
## 0.46 for the chalk plaques (`:1251`); this is the same table at a third.
##
## **Everything is built with `SurfaceTool` and vertex colours, exactly as
## `world_builder.gd` builds the level.** That is not a convenience — it is why
## the weapon is stylistically identical to the room it is held in, by
## construction, rather than by anyone matching a palette.
##
## Four things here are NOT the ancestor's and are marked as such at their
## definition: `SLIDE` (which part reciprocates), `SIGHTS` (the only geometry in
## this file the ancestor did not draw), `DEPTH` (how thick each part is), and the
## baked face ramp. The ancestor's viewmodel was a flat 2D drawing, so it had no
## opinion about any of them.
##
## Nothing in this file touches the scene tree, an `Rng` stream, or global state.
## It is a table and a mesh builder; `scripts/entities/viewmodel.gd` is the rig.


# --- the ancestor's tables ---------------------------------------------------

## kriegsnacht.html:1151, verbatim. `['r', x, y, w, h, colour]` is a rect in the
## 100x60 art space with **the muzzle at the left and the stock at the right**
## (the comment at :1150 says so, and `MUZZLE` below agrees with it); `['c', cx,
## cy, r, colour]` a circle; `['rr', x, y, w, h, rot, colour]` a rect rotated
## about its own (x, y); `['p', [x0,y0, x1,y1, ...], colour]` a polygon.
##
## Colours are the ancestor's own hex strings with the `#` dropped, because
## `Color("2a2c2e")` is a constant expression and this table has to be a `const`.
## They are authored sRGB and are converted once, at build time, in `_tint` — see
## there for why that conversion is not optional.
##
## Part *order* is load-bearing in two directions. The ancestor drew them back to
## front with a painter's algorithm, so a later part covers an earlier one; here a
## later part is extruded slightly **thicker** so it stands proud of the one it
## covers (see `LAYER`). And `SLIDE` indexes into this array, so inserting a part
## anywhere but the end silently moves which part reciprocates.
const ART := {
	"m1911": [["r", 30, 22, 26, 7, Color("2a2c2e")], ["r", 26, 20, 32, 4, Color("3e4245")],
		["r", 22, 23, 10, 4, Color("1f2123")], ["r", 52, 26, 7, 16, Color("5a3b1e")],
		["r", 50, 28, 4, 12, Color("3a2512")], ["r", 44, 28, 5, 8, Color("2a2c2e")],
		["r", 26, 20, 30, 1.4, Color("6a7075")]],
	"olympia": [["r", 6, 20, 58, 5, Color("2e3033")], ["r", 6, 25, 58, 5, Color("26282b")],
		["r", 60, 19, 10, 13, Color("4b3218")], ["r", 66, 22, 22, 15, Color("5a3b1e")],
		["r", 66, 22, 22, 3, Color("7a5228")], ["r", 44, 21, 10, 10, Color("3a3d40")],
		["r", 6, 20, 58, 1.2, Color("7a8085")]],
	"m14": [["r", 10, 22, 52, 5, Color("2c2e30")], ["r", 36, 20, 34, 10, Color("5a3b1e")],
		["r", 62, 20, 28, 15, Color("5a3b1e")], ["r", 62, 20, 28, 3, Color("7a5228")],
		["r", 44, 30, 7, 12, Color("42301a")], ["r", 52, 28, 10, 10, Color("26282b")],
		["r", 10, 22, 52, 1.2, Color("6e7479")]],
	"mp40": [["r", 8, 23, 44, 4, Color("26282b")], ["r", 26, 20, 30, 9, Color("2e3033")],
		["r", 50, 27, 6, 15, Color("1f2123")], ["r", 56, 22, 10, 8, Color("2a2c2e")],
		["r", 64, 24, 4, 4, Color("1a1c1e")], ["rr", 68, 26, 20, 3.5, -0.35, Color("3a3d40")],
		["r", 18, 20, 10, 3, Color("3a3d40")], ["r", 8, 23, 44, 1.2, Color("6a7075")]],
	"pm63": [["r", 12, 24, 34, 3.6, Color("2a2c2e")], ["r", 30, 21, 22, 8, Color("33363a")],
		["r", 46, 26, 5, 13, Color("1f2123")], ["rr", 54, 24, 18, 3, -0.45, Color("3a3d40")],
		["r", 26, 29, 5, 11, Color("26282b")], ["r", 12, 24, 34, 1, Color("6a7075")]],
	"ak74u": [["r", 6, 23, 40, 4.4, Color("2c2e30")], ["r", 24, 20, 26, 9, Color("3a2c1c")],
		["r", 44, 27, 6, 14, Color("1f2123")], ["r", 50, 21, 14, 8, Color("33363a")],
		["r", 62, 23, 22, 7, Color("5a3b1e")], ["r", 30, 29, 9, 10, Color("26282b")],
		["r", 6, 23, 40, 1.2, Color("6a7075")], ["r", 18, 19, 8, 3, Color("3a3d40")]],
	"stakeout": [["r", 4, 22, 54, 5, Color("2a2c2e")], ["r", 4, 27, 54, 4, Color("3a2c1c")],
		["r", 20, 27, 16, 5, Color("4a3820")], ["r", 56, 20, 14, 12, Color("4b3218")],
		["r", 68, 21, 20, 13, Color("5a3b1e")], ["r", 68, 21, 20, 3, Color("7a5228")],
		["r", 50, 30, 7, 11, Color("3a2c1c")], ["r", 4, 22, 54, 1.2, Color("7a8085")]],
	"m16": [["r", 4, 23, 46, 4, Color("2a2c2e")], ["r", 26, 19, 26, 10, Color("33363a")],
		["r", 30, 17, 18, 3, Color("26282b")], ["r", 48, 27, 6, 14, Color("1f2123")],
		["r", 54, 21, 12, 9, Color("2e3033")], ["r", 64, 22, 24, 8, Color("33363a")],
		["r", 34, 29, 8, 13, Color("26282b")], ["r", 4, 23, 46, 1, Color("6a7075")]],
	"rpk": [["r", 2, 23, 48, 5, Color("2c2e30")], ["r", 26, 20, 26, 10, Color("3a2c1c")],
		["r", 46, 28, 6, 14, Color("1f2123")], ["r", 52, 21, 14, 9, Color("33363a")],
		["r", 64, 23, 24, 7, Color("5a3b1e")], ["r", 28, 29, 14, 14, Color("33363a")],
		["c", 35, 38, 7, Color("33363a")], ["r", 2, 23, 48, 1.2, Color("6a7075")],
		["r", 10, 20, 14, 3, Color("3a3d40")]],
	"chinalake": [["r", 6, 19, 50, 11, Color("33362e")], ["r", 6, 19, 50, 2, Color("4e5246")],
		["c", 12, 24.5, 6.2, Color("22251f")], ["r", 52, 27, 7, 14, Color("2a2c24")],
		["r", 58, 21, 26, 12, Color("3a3d33")], ["r", 58, 21, 26, 3, Color("4e5246")],
		["r", 26, 30, 18, 5, Color("22251f")]],
	"raygun": [["r", 18, 20, 34, 13, Color("3e4a2e")], ["r", 18, 20, 34, 3, Color("5e7044")],
		["c", 16, 26, 7.5, Color("2e3822")], ["c", 16, 26, 4.6, Color("8fe04a")],
		["c", 16, 26, 2.4, Color("e8ffc0")], ["r", 46, 30, 8, 14, Color("2e3822")],
		["r", 30, 14, 12, 8, Color("5e7044")], ["c", 36, 18, 3.2, Color("8fe04a")],
		["r", 52, 22, 14, 8, Color("3e4a2e")], ["c", 60, 26, 3, Color("8fe04a")]],
	"thundergun": [["r", 20, 18, 38, 16, Color("3a3d42")], ["r", 20, 18, 38, 3, Color("5a5f66")],
		["c", 14, 22, 6.5, Color("22252a")], ["c", 14, 31, 6.5, Color("22252a")],
		["c", 14, 22, 3.6, Color("7adff0")], ["c", 14, 31, 3.6, Color("7adff0")],
		["r", 52, 32, 8, 15, Color("22252a")], ["r", 56, 20, 26, 11, Color("3a3d42")],
		["r", 56, 20, 26, 2.4, Color("5a5f66")], ["c", 34, 26, 4.4, Color("7adff0")],
		["c", 34, 26, 2.2, Color("dff9ff")]],
	"knife": [["p", [10, 30, 44, 22, 50, 26, 44, 31, 10, 33], Color("b9bec4")],
		["p", [10, 30, 44, 22, 46, 25, 12, 31], Color("e2e7ec")],
		["r", 48, 23, 6, 10, Color("2a2c2e")], ["r", 54, 24, 20, 8, Color("3a2c1c")],
		["r", 54, 24, 20, 2, Color("4e3a24")]],
}

## kriegsnacht.html:2020, verbatim, and in the same art space as `ART` — the
## drawing code proves it: the flash is placed at `(6 + m[0]*1.9, 26 + m[1]*1.9)`
## (:3146) which is the same `translate(6, 26)` + `scale(1.9)` the parts are drawn
## under (:1214, :1217). So the barrel end is free data, not a guess.
const MUZZLE := {
	"m1911": Vector2(22, 25), "olympia": Vector2(6, 25), "m14": Vector2(10, 24),
	"mp40": Vector2(8, 25), "pm63": Vector2(12, 26), "ak74u": Vector2(6, 25),
	"stakeout": Vector2(4, 24), "m16": Vector2(4, 25), "rpk": Vector2(2, 25),
	"chinalake": Vector2(6, 24), "raygun": Vector2(16, 26), "thundergun": Vector2(14, 26),
	"knife": Vector2(10, 30),
}

## kriegsnacht.html:1224 — where the ancestor drew the gloved hand on each weapon.
##
## This is the *anchor*, and using it rather than a bounding-box centre is the
## single decision that makes thirteen weapons sit in one rig without thirteen
## offsets. Every mesh is built with its grip at the origin, so the pistol and the
## RPK are held in the same place and differ only in how much gun there is either
## side of the hand — which is what actually distinguishes them. It is also the
## physically correct pivot for recoil: a gun rotates about the hand holding it.
const GRIP := {
	"m1911": Vector2(52, 30), "olympia": Vector2(62, 26), "m14": Vector2(48, 32),
	"mp40": Vector2(52, 30), "pm63": Vector2(48, 30), "ak74u": Vector2(47, 31),
	"stakeout": Vector2(53, 32), "m16": Vector2(50, 30), "rpk": Vector2(49, 31),
	"chinalake": Vector2(54, 30), "raygun": Vector2(49, 33), "thundergun": Vector2(54, 34),
	"knife": Vector2(56, 27),
}

## Which parts ride the bolt, by index into that weapon's `ART` entry.
##
## **INVENTED — the ancestor has no weapon animation of any kind.** Its viewmodel
## is one baked canvas per weapon, translated and rotated as a whole (:3138-3142),
## so there is nothing to transliterate here and no number to be faithful to.
##
## The rule applied was: a weapon gets a reciprocating part only when the art
## actually *draws* one. Weapons with no entry still recoil; the whole mesh kicks
## about the grip (see viewmodel.gd).
##
## **FIVE ROWS ARE EMPTY BECAUSE THE PART IS ON THE FAR SIDE, AND THAT SENTENCE
## HAS TO BE HERE OR IT GETS UNDONE.** M14, M16, AK-74u and RPK all cycle
## something on the weapon's far flank — an M14's op rod is *external* and runs
## along the right of the barrel (the comment this replaces said it "runs inside
## the receiver", which is wrong about the mechanism and would have invited
## somebody to draw it), an M16's port cover and deflector are on the right, and
## an AK's and an RPK's charging handle is welded to the bolt carrier and travels
## over the **rear** of the receiver on the right.
##
## `_extrude` sweeps +/-`half` about x = 0 (`:699-700`) and `_prism_corners` does
## the same, so **this builder cannot make a one-sided part.** A charging handle
## added for the far flank is drawn on the near one too, and the near cap is the
## one the player is looking at: the rest pose puts the grip at x +0.038 and yaws
## the weapon 0.2094 rad inward (`viewmodel.gd:171`, `:189`), which resolves the
## model's -X cap toward the lens — I worked the dot product rather than taking
## the art's muzzle-left profile convention on trust, and the conclusion does not
## depend on which flank that convention calls -X, because a symmetric sweep puts
## the part on *both*. So the choice is between no charging handle and a charging
## handle on a side of an AK that has none, and off-reference beats off-budget.
##
## **The AK-74u and the RPK additionally need the gas-tube sentence, because the
## geometry does not settle them and an agent arguing from geometry alone will put
## them back.** Both drew part 7 / part 8 as an 8-14 x 3 strip in `3a3d40` above
## the barrel, forward of the receiver — and the MP40's part 6 is the same idiom in
## the same colour with the same two units of receiver overlap (ak74u part 7
## x18-26 against receiver x24-50; mp40 part 6 x18-28 against x26-56). A predicate
## built from those rects convicts both or acquits both. What separates them is
## what the weapon *is*: an AK-74u and an RPK carry a **gas tube** bolted down in
## exactly that position, and an **MP40 is straight blowback with no gas system at
## all**, so on an MP40 the same strip can only be the cocking handle — which is
## on the MP40's near flank, which is why that row survives and these two do not.
##
## Emptying two rows removes visible motion from the two highest-fire-rate rifles
## in the game and that will read as a regression, so: **their shot-time motion is
## the brass** (`fx.gd`'s `fx_pistol` / `fx_saw`, which land on exactly these four
## weapons) **and their mechanical motion belongs to the reload.**
const SLIDE := {
	# The slide plate, the highlight rib along its top, and — 7 and 8, appended by
	# SIGHTS below — the front post and rear blade, which on a 1911 are milled into
	# the slide and reciprocate with it.
	"m1911": [1, 6, 7, 8],
	"olympia": [],         # break-action: nothing reciprocates
	"m14": [],             # op rod, external, far flank — see above
	"mp40": [6],           # the bolt handle, the 10x3 strip above the barrel
	"pm63": [1],           # the receiver *is* the bolt on a PM63, and it is drawn
	"ak74u": [],           # part 7 is the gas tube, and the handle is on the far flank
	"stakeout": [2],       # the pump fore-end under the barrel
	"m16": [],             # carrier internal; port cover and deflector on the far flank
	"rpk": [],             # part 8 is the gas tube, and the handle is on the far flank
	"chinalake": [6],      # the pump under the launcher tube
	"raygun": [],          # no moving parts drawn
	"thundergun": [],      # likewise
	"knife": [],
}


# --- how the group moves, and how far --------------------------------------------
#
# Three tables and three accessors, and they are HERE rather than in `weapons.gd`
# for one reason each. Travel is a statement about the **art** — how far a part can
# slide before it hits the part behind it — so the collision reasoning has to live
# where the rects are. Mode and hold-open are statements about the **mechanism**,
# which is what `SLIDE` two lines above already is. And `weapons.gd` declares
# itself "ported verbatim from kriegsnacht.html section 4 ... engine-independent
# design data" (`weapons.gd:4-5`); all three of these are invented, and its TABLE is
# read by `balance_sim.gd`, so a cosmetic column there would break the file's stated
# contract and widen the sim's data surface for nothing.

## How far the reciprocating group travels, in art units, per weapon.
##
## **INVENTED, and the method is the durable part rather than the digits.** Each
## floor is one cartridge overall length scaled through that weapon's own drawn
## span — `floor = cartridge OAL / (weapon OAL / drawn span)` — because a breech
## that does not open by at least one cartridge cannot feed. Each ceiling is the
## **free run in the art**: the x-gap between the group's trailing edge and the
## first non-slide part behind it whose y-span and depth range overlap the group's.
## `checks/systems.gd` recomputes that free run from `ART` and asserts the row
## between the two, so neither bound is a pasted number.
##
##   weapon    drawn span   mm/unit   cartridge      floor   free run   here
##   m1911     37 (x22-59)  5.68-5.84 .45 ACP 32.4   5.55    none behind    7
##   mp40      80 (x8-88)   10.41     9x19 29.69     2.85    28 (part 3)    8
##   pm63      59.5         9.80      9x18 25.0      2.55    2  (part 3)    5  (!)
##   stakeout  84 (x4-88)   9.98      2.75in 69.85   7.00    14 (grip)      9
##   chinalake 78.2         11.21     40x46 98.4     8.78    8  (grip)      8  (!)
##
## The three folding-stock weapons are scaled with their **extended** overall
## lengths (MP 40 833 mm, AKS-74U 730, FB PM-63 583; Wikipedia infoboxes) because
## all three are drawn stock-out — mp40 part 5's far corner lands at x 87.99, pm63
## part 3's at x 71.51. Feeding the folded figures moves three of the five floors.
##
## **TWO ROWS ARE DEPARTURES AND BOTH ARE RECORDED HERE RATHER THAN DISCOVERED
## LATER.** The PM-63's 5 is an *interpenetration*: its slide (part 1, x30-52)
## meets the folding-stock strut at x54, so the art affords 2 units and the floor
## is 2.55 — the drawn weapon has no valid stroke at all. 5 is taken because part 3
## sits at half-depth 3.02 art units against part 1's 2.74 and is inflated by
## `3*PROUD` against `1*PROUD`, so the strut **encloses** the slide where they meet
## and hides the overlap on both flanks — the same LAYER/PROUD stacking that exists
## to put a highlight over its plate. The China Lake's 8 is a **cap forced by the
## drawn pistol grip** (part 6 x26-44 meets part 3 at x52): 8 units is 89.7 mm
## against a 98.4 mm grenade, so it stops 0.78 units short of its own floor. Either
## would be wrong even if right without this paragraph.
##
## **Sizing note, measured 2026-08-02 and it overrides the two derivations in
## M6.** The shipped 4-unit stroke moves **9.62 px** on screen (M1911, `spawn`,
## 1280x720), read off three captures with `_slide_offset()` pinned at 0, at
## travel and at 10x travel and solved for the changed-pixel envelope. Model +Z is
## 14.09 degrees off the view axis, so ~97% of the stroke goes into DEPTH and only
## ~24% is lateral: lengthening it buys about **2.4 px per art unit**, which is why
## these rows are sized against the cartridge floor and the free run and NOT tuned
## for legibility. Rotating the travel axis toward the screen plane or lengthening
## the cycle are both cheaper per pixel, and both are out of this stage's scope.
const TRAVEL := {
	"m1911": 7, "mp40": 8, "pm63": 5, "stakeout": 9, "chinalake": 8,
}

## What the single global constant this table replaces was worth (`SLIDE_TRAVEL`
## 0.0042 m at `UNIT`). Kept as the fallback so a weapon given a `SLIDE` row and no
## `TRAVEL` row animates the way the rig shipped rather than sitting dead, which is
## the same bargain `part_half` makes for a missing `DEPTH` row — and, as there,
## `checks/systems.gd` asserts that no row is missing, so it is a safety net and
## not a supported state.
const TRAVEL_DEFAULT := 4

## Which way the cycle runs. `CLOSED` is the default and is the only one the rig
## shipped with.
##
##   CLOSED  rest at battery; the shot throws the group back and a spring returns
##           it. The M1911, and what every row used to be.
##   OPEN    rest with the group held BACK by the sear; the trigger releases it
##           FORWARD, it fires, and blowback returns it. The cycle is the time
##           mirror of CLOSED, and getting it backwards means the rig plays the
##           only visible mechanism on the weapon in reverse.
##   PUMP    hand-worked, and it does not move at the instant of the shot at all —
##           it strokes BETWEEN shots, symmetrically, because nothing is throwing
##           it. See viewmodel.gd's PUMP_DELAY.
const CLOSED := 0
const OPEN := 1
const PUMP := 2

## **Provenance, per row.** The MP40 fires from an open bolt: rest is bolt-back,
## the trigger sends it forward. The PM-63 is the same and one step further — it
## fires while the slide is still travelling forward (advanced primer ignition),
## and the slide *is* the reciprocating mass. The Stakeout is an Ithaca 37 and the
## China Lake a pump-action launcher; on both the fore-end is stroked after the
## shot, not with it. (The pre-1975 Model 37 slam-fires, which would put the stroke
## *before* the shot — BO1 overrides that with a rechamber state entered after the
## fire animation, and the reference wins.)
const MODE := {
	"mp40": OPEN, "pm63": OPEN, "stakeout": PUMP, "chinalake": PUMP,
}

## Which weapons hold the group open on an empty magazine.
##
## **Two of seven, and the rig used to do it for all seven.** An M1911 has a slide
## stop. The PM-63 has a cited one — Wikipedia's `FB PM-63 RAK`: "after the last
## cartridge has been fired from the magazine, the slide is locked open on the
## slide catch" — though under `OPEN` its locked pose and its ready pose are the
## same pose, so it is here because it is true and not because it shows. An AK and
## an RPK have no last-round hold-open at all and their bolts run forward; an MP40
## has no hold-open device of any kind; and a pump gun's fore-end rests forward,
## which is a pose no shotgun holds.
##
## A plain `Array` literal, the shape `ONE_HANDED` uses at `:571`, because
## `PackedStringArray([...])` is a *call* and a const that is not a constant
## expression is a hard parse error in this project.
const BOLT_HOLD := ["m1911", "pm63"]


## How far this weapon's group travels, in **metres**. The single accessor both
## `viewmodel.gd:_slide_offset()` and `viewmodel.gd:_measure()` read, and that is
## the whole point of it: `_measure()` used to hardcode the global constant as its
## second sweep endpoint, and a per-weapon table that did not land there too would
## have voided the no-clip guarantee while every assertion stayed green.
static func slide_travel(key: String) -> float:
	var units: float = float(TRAVEL.get(key, TRAVEL_DEFAULT))
	return units * UNIT


## `CLOSED` / `OPEN` / `PUMP`. See `MODE`.
static func slide_mode(key: String) -> int:
	var m: int = int(MODE.get(key, CLOSED))
	return m


## Whether the group is held back on an empty magazine. See `BOLT_HOLD`.
static func bolt_holds(key: String) -> bool:
	return BOLT_HOLD.has(key)


## The free run behind this weapon's group, in art units: how far it can go before
## it meets the first part that is actually in its way.
##
## **Derived from `ART`, never pasted**, and that is the correction that gives it a
## reason to exist. The figure in circulation was measured to the `GRIP` anchor,
## which is a hand position and not a part, and it was wrong on all three weapons
## it covered (Stakeout 16.92 against 14, China Lake 9.76 against 8, PM-63 -4.04
## against 2). A part is only in the way if it is not itself in the group, does not
## already overlap the group at rest, overlaps it in y, overlaps it in **depth**
## (the `+ i*LAYER` ramp means a part far enough out in x passes in front of or
## behind rather than into), and lies behind it — behind being art +x, which
## `_to_local` maps to model +z, which is the direction the group travels.
##
## `INF` when nothing is behind the group at all, which is the M1911: its slide
## band (art y 20-24) is clear all the way to the back of the drawing.
static func slide_free_run(key: String) -> float:
	var parts: Array = _parts(key)
	var slide: Array = SLIDE.get(key, [])
	if slide.is_empty():
		return 0.0
	# The group's own extent, unioned over its parts, and its depth band.
	var g_x0 := INF
	var g_x1 := -INF
	var g_y0 := INF
	var g_y1 := -INF
	var g_d0 := INF
	var g_d1 := -INF
	for i in parts.size():
		if not slide.has(i):
			continue
		var box := _part_box(parts[i], float(i) * PROUD)
		g_x0 = minf(g_x0, box.position.x)
		g_x1 = maxf(g_x1, box.end.x)
		g_y0 = minf(g_y0, box.position.y)
		g_y1 = maxf(g_y1, box.end.y)
		var half := part_half(key, i) / UNIT
		g_d0 = minf(g_d0, -half)
		g_d1 = maxf(g_d1, half)
	var run := INF
	for i in parts.size():
		if slide.has(i):
			continue
		var box := _part_box(parts[i], float(i) * PROUD)
		var half := part_half(key, i) / UNIT
		# No y overlap, no depth overlap, or already overlapping in x at rest: not
		# something this group can be driven into.
		if box.end.y <= g_y0 or box.position.y >= g_y1:
			continue
		if half <= g_d0 or -half >= g_d1:
			continue
		if box.position.x < g_x1:
			continue
		run = minf(run, box.position.x - g_x1)
	return run


## One part's axis-aligned art-space box, already grown by `proud`. Shares
## `_part_poly` with the builder so a rotated rect and a circle are bounded by the
## polygon that is actually extruded rather than by their nominal rect.
static func _part_box(part: Array, proud: float) -> Rect2:
	var poly := _part_poly(part, proud)
	var r := Rect2(poly[0], Vector2.ZERO)
	for p: Vector2 in poly:
		r = r.expand(p)
	return r


## Iron sights, appended to each weapon's part list at build time.
##
## **INVENTED, and kept OUT of `ART` on purpose — that separation is the whole
## design of this constant.** `ART` claims to be `kriegsnacht.html:1151` verbatim
## and `tools/gen/targets.js:150-162` bakes the chalk wall plaques from a *second*
## copy of that table (`tools/gen/ancestor.generated.js:634`, itself extracted from
## the ancestor). Nothing asserts the two agree — M5 F8 — so a part added to `ART`
## would silently stop the plaque on the wall from being a drawing of the weapon
## behind it. A part added *here* cannot: `ART` is still the ancestor's, byte for
## byte, and the chalk is still a faithful sketch of it. The sights are ours, they
## are only on the viewmodel, and the plaque not showing a 1.8-unit post on a
## 40-pixel chalk drawing is the correct outcome rather than a desync.
##
## **Why they exist: M5 F5.** At full sights `ADS_CENTRE`, `ADS_YAW` and
## `ADS_LEVEL` are all 1.0, so the camera sits in the caps' own plane, both caps go
## edge-on, and the only faces left are the +Z rear edges of a stack of flat
## plates. There was no rear sight, no front post, and no vocabulary in the art
## space for one — "anything that improves the ADS read has to add geometry along
## +Z", and this is that geometry. A tall near blade with a small far post beyond
## it is the sight picture, and it is the one thing this pipeline *can* build:
##
## **the notch cannot be modelled and it is worth saying why.** A rear notch is a
## gap across the shooter's horizontal axis, which is model X — the extrusion axis,
## about which every prism this builder emits is symmetric. Two rects with a gap
## between them (M5 R10's own suggestion) reads as an aperture only if the gap runs
## along a *drawn* axis; here it would be a gap in height, which is a different
## sight. So the read is carried by depth ordering — near blade, far post — and not
## by an aperture.
##
## Appended and never inserted, which is what makes them safe: `SLIDE` indexes
## `ART` by position (F2), so an inserted part would move which part reciprocates,
## every later part's `DEPTH` row and every later part's `PROUD` inflation. An
## appended one moves nothing. The M1911's two ride the slide — that is where a
## 1911's sights are — which is why `SLIDE["m1911"]` names 7 and 8.
##
## Every post and blade sits **above** the top edge of everything under it, so no
## depth assignment can hide one behind the part it is mounted on. That is checked
## by eye against the table above and it is why they are all `D_THIN`.
##
## The shotguns get a bead and no rear blade, because that is what an Olympia and a
## Stakeout have. The Ray Gun, the Thundergun and the knife get nothing.
const SIGHTS := {
	# slide top is y 20, so the post and blade start above it; both in SLIDE.
	"m1911": [["r", 28, 17.6, 1.8, 2.4, Color("1a1c1e")],
		["r", 54.5, 16.6, 2.2, 3.4, Color("1a1c1e")]],
	"olympia": [["r", 8, 17.0, 1.6, 2.5, Color("1a1c1e")]],
	"m14": [["r", 12, 19.5, 1.8, 2.5, Color("1a1c1e")],
		["r", 56, 17.0, 2.2, 3.0, Color("1a1c1e")]],
	"mp40": [["r", 10, 20.5, 1.6, 2.5, Color("1a1c1e")],
		["r", 50, 17.6, 2.0, 2.4, Color("1a1c1e")]],
	"pm63": [["r", 13.5, 21.5, 1.5, 2.5, Color("1a1c1e")],
		["r", 46, 18.4, 1.8, 2.6, Color("1a1c1e")]],
	"ak74u": [["r", 8, 19.0, 1.8, 4.0, Color("1a1c1e")],
		["r", 52, 17.0, 2.0, 4.0, Color("1a1c1e")]],
	# The Stakeout's receiver (part 3) tops out at art y 20, higher than its
	# barrel, so a bead level with the barrel would not be the top of the weapon
	# and `sight_height()` would go on reading the receiver.
	"stakeout": [["r", 6, 18.0, 1.6, 4.0, Color("1a1c1e")]],
	# The front tower is the M16's whole silhouette cue and it is 4.5 units tall;
	# the rear blade sits on the carry handle (part 2, y 17), not on the receiver.
	"m16": [["r", 6, 18.5, 2.2, 4.5, Color("1a1c1e")],
		["r", 46, 15.6, 2.0, 2.0, Color("1a1c1e")]],
	"rpk": [["r", 5, 19.5, 2.0, 3.5, Color("1a1c1e")],
		["r", 54, 18.0, 2.0, 3.0, Color("1a1c1e")]],
	# A ladder sight, which is what a China Lake carries and is the tallest here.
	"chinalake": [["r", 9, 16.0, 1.8, 3.0, Color("1a1c1e")],
		["r", 50, 15.0, 2.0, 4.0, Color("1a1c1e")]],
}


## `ART` plus `SIGHTS`, which is what every walk in this file iterates.
##
## One function rather than two loops in each of `_build` and `_corners`, because
## those two already have to agree part-for-part and index-for-index (see
## `_corners`) and a second place to get the concatenation wrong is a second place
## for the clip measurement to measure a mesh that is not on screen.
static func _parts(key: String) -> Array:
	var base: Array = ART.get(key, [])
	var extra: Array = SIGHTS.get(key, [])
	if extra.is_empty():
		return base
	return base + extra


# --- how big, and how thick --------------------------------------------------

## Metres per art unit.
##
## Chosen against **two** constraints at once, and it is the number every other
## dimension in the rig is derived from.
##
## 1. The no-clip budget. `viewmodel.gd`'s `REST_POS` puts the grip 0.116 m from
##    the lens; the longest reach from any grip is the Olympia's 56 units of
##    barrel, and the deepest is the M14's 42 units of stock. At 0.00105 the worst
##    mesh corner across every weapon and every pose lands 0.201 m from the lens,
##    the nearest 0.0575 m along it (clear of the camera's 0.05 m near plane), and
##    the projection-widened radius that actually decides occlusion — see
##    `viewmodel.max_screen_radius()`, which is the number that matters and not
##    the first one — at 0.232 m against `Player.RADIUS`'s 0.24. All three are
##    re-derived from `body_corners()` / `slide_corners()` below, which is what
##    makes them assertions rather than claims.
## 2. Apparent size. Through the narrowed viewmodel projection the weapons come
##    out at 16% (Olympia) to 27% (Thundergun) of screen height at the grip. The
##    ancestor's drawn viewmodel occupied 21.8% — its art region is 47.5% of a
##    120 px canvas scaled to 46% of screen height (:3114) — so this lands on the
##    ancestor's own framing without having been fitted to it.
const UNIT := 0.00105

## Half the extrusion depth of the *first* part, in art units, and how much
## thicker each subsequent part is.
##
## **Both invented; the ancestor's art is two-dimensional.** `LAYER` is not
## decoration: the ancestor drew these parts back to front, so the Ray Gun's three
## concentric lens circles and every highlight rib are drawn *over* the part
## underneath. Extruded at one depth their **caps** would be exactly coplanar and
## z-fight. Giving part *i* a half-depth of `BASE_HALF + i*LAYER` turns the
## painter's algorithm into geometry along the extrusion axis, and the depth buffer
## resolves it for free. The widest weapon has eleven parts, so the deepest is
## 4.14 units — a gun about 8 units thick against a receiver 10 units tall, which
## is roughly a real weapon's proportion.
##
## It fixes the caps and **only** the caps. See `PROUD` for the half it misses.
##
## **`BASE_HALF` is no longer the depth of a part; it is the unit `DEPTH`'s
## multipliers are quoted in.** See `DEPTH` for why draw order stopped being the
## answer, and note that the `+ i*LAYER` term below survived that change unaltered
## — it is the z-fight fix and two parts given the same authored multiplier are
## still separated by it.
const BASE_HALF := 2.6
const LAYER := 0.14

## The depth tiers, in multiples of `BASE_HALF`. Quantised to six values on
## purpose: a part's depth is a statement about what the part IS, and six tiers is
## as much vocabulary as thirteen weapons of drawn side-profile can carry.
##
##   D_THIN  1.30 art units — a barrel, a strut, a folding stock, a sight post
##   D_BODY  2.34 — a receiver, a magazine, a pistol grip
##   D_FAT   2.86 — a buttstock, a wooden handguard, a pump
##   D_BULK  3.25 — a launcher tube, a Ray Gun body, a Thundergun shell
##
## Four rungs and not more. A fifth was drafted for hairline ribs and thrown away
## when it turned out to hide them — see below.
const D_THIN := 0.50
const D_BODY := 0.90
const D_FAT := 1.10
const D_BULK := 1.25

## Per-part depth multipliers, one row per weapon, one entry per part of
## `_parts(key)` — `ART` first, then `SIGHTS`.
##
## **INVENTED, and it replaces a defect.** Depth used to be `BASE_HALF + i*LAYER`
## and nothing else, i.e. **draw order**, which the ancestor chose for a painter's
## algorithm and which has no opinion about thickness at all. M5 F1 worked the
## consequence on the M1911: the receiver got 5.20 units of thickness, the barrel
## 5.76 — 1.44x its own drawn height — and a 30x1.4 highlight rib got 6.72, **4.8x
## its own height and the thickest thing on the gun**. Ten of thirteen weapons had
## a hairline strip as their deepest part. Flan's Mod's `ModelColt` (grip 5 deep,
## barrel 2) and OpenSpades both give each part its own depth and both put the
## massive parts deepest; a real M1911 slide is ~23 mm across against a 34 mm grip.
##
## **The ratios are Flan's; the absolute scale is ours, and it is bounded rather
## than chosen.** M5 F7 puts the screen-radius cost of a depth change somewhere
## between 5.9% and 50% of an 8.1 mm margin — two derivations that disagree by up
## to 8x — and the measurement that would settle it was never run. So this table
## never exceeds the deepest half-depth that already shipped (4.00 units, the
## Thundergun's part 10 under the old expression) and mostly sits well under it.
## A table that only ever moves x inward cannot be the thing that spends a margin
## nobody has measured. When that measurement exists, this ceiling is the constant
## to revisit — not the ratios.
##
## **Where M5 R2's own wording is wrong, and it matters.** R2 says "receivers and
## magazines thick; ribs, sights and highlight strips thin". Author a highlight rib
## thin and **it disappears**: the ancestor drew it *over* the plate it lies on, so
## in 3D its caps end up 2 units *inside* that plate's caps and the depth buffer
## does exactly what it is supposed to. A painted highlight has to be proud of
## everything it is painted on. The rule used here is therefore: a part's tier is
## what the part is made of, and **a surface feature takes the tier of the thickest
## part it overlaps**, with `+ i*LAYER` — which is monotone in draw order, which is
## the order the ancestor painted in — supplying the proudness. That is `LAYER`
## doing the job it was written for, against a host instead of against everything.
##
## Two invariants over this table, both asserted in `checks/frame.gd` rather than
## left as a comment, because F7's first draft named a different mechanism for the
## first one and an implementer who checked *that* would have shipped a broken
## table:
##
##  1. No part of a weapon may land on `HAND_HALF` (5.0) or `HAND_HALF + LAYER`
##     (5.14). The gloves are pinned at those two and do **not** ride the ramp, so
##     a gun part on either z-fights its caps against a glove.
##  2. No two parts of one weapon may land on the same half-depth, or their caps
##     are coplanar again and `LAYER` has been undone by hand.
const DEPTH := {
	# receiver, slide, barrel, grip panel, backstrap, trigger guard, slide rib,
	# front post, rear blade. The backstrap is thinner than the wooden panel over
	# it, so the strip of it that shows forward of the panel reads as frame.
	"m1911": [D_BODY, D_BODY, D_THIN, D_FAT, D_BODY, D_THIN, D_BODY, D_THIN, D_THIN],
	# two stacked barrels, breech, stock, stock rib, barrel band, top rib, bead.
	"olympia": [D_BODY, D_BODY, D_FAT, D_FAT, D_FAT, D_BODY, D_BODY, D_THIN],
	# barrel, handguard, buttstock, stock rib, pistol grip, magazine, barrel rib,
	# front post, rear blade.
	"m14": [D_BODY, D_FAT, D_FAT, D_FAT, D_BODY, D_BODY, D_BODY, D_THIN, D_THIN],
	# barrel, receiver tube, magazine, trigger housing, stock hinge, folding stock,
	# bolt handle, barrel rib, front post, rear blade.
	"mp40": [D_BODY, D_FAT, D_BODY, D_BODY, D_THIN, D_THIN, D_THIN, D_BODY,
		D_THIN, D_THIN],
	# barrel, slide, magazine, folding stock, foregrip, barrel rib. The rib takes
	# D_FAT because it runs across the slide, not only across the barrel.
	"pm63": [D_BODY, D_FAT, D_BODY, D_THIN, D_THIN, D_FAT, D_THIN, D_THIN],
	# barrel, handguard, magazine, dust cover, stock, foregrip, barrel rib,
	# charging handle, front post, rear blade.
	"ak74u": [D_BODY, D_FAT, D_BODY, D_FAT, D_FAT, D_BODY, D_FAT, D_THIN,
		D_THIN, D_THIN],
	# barrel, magazine tube, pump, receiver, stock, stock rib, grip, barrel rib,
	# bead.
	"stakeout": [D_BODY, D_BODY, D_FAT, D_FAT, D_FAT, D_FAT, D_BODY, D_BODY, D_THIN],
	# barrel, upper receiver, carry handle, magazine, lower receiver, stock, grip,
	# barrel rib, front tower, rear blade.
	"m16": [D_BODY, D_FAT, D_THIN, D_BODY, D_FAT, D_FAT, D_BODY, D_FAT,
		D_THIN, D_THIN],
	# barrel, handguard, magazine, receiver, stock, drum housing, drum, barrel rib,
	# charging handle, front post, rear blade. The drum is the fattest gun part on
	# the roster, which is the one thing an RPK's silhouette is for.
	"rpk": [D_BODY, D_FAT, D_BODY, D_FAT, D_FAT, D_FAT, D_FAT, D_FAT, D_THIN,
		D_THIN, D_THIN],
	# launcher tube, tube rib, muzzle ring, grip, stock, stock rib, pump, front
	# post, ladder sight.
	"chinalake": [D_BULK, D_BULK, D_BULK, D_FAT, D_FAT, D_FAT, D_FAT, D_THIN, D_THIN],
	# body, body rib, lens housing, lens mid, lens core, grip, scope block, scope
	# emitter, rear block, rear emitter. The three concentric lens circles MUST
	# step outward in that order or the inner ones are inside the outer ones.
	"raygun": [D_BULK, D_BULK, D_BULK, D_BULK, D_BULK, D_BODY, D_FAT, D_FAT,
		D_BODY, D_BODY],
	# shell, shell rib, two emitter housings, two emitter cores, grip, stock,
	# stock rib, mid ring, mid core.
	"thundergun": [D_BULK, D_BULK, D_BULK, D_BULK, D_BULK, D_BULK, D_BODY, D_FAT,
		D_FAT, D_BODY, D_BODY],
	# blade, blade highlight, bolster, handle, handle rib. The blade at 2.60 units
	# thick against a 6.56-unit handle is the change this whole table exists for:
	# it used to be 5.20 against 6.04, i.e. a blade five sixths as thick as the
	# grip it folds out of.
	"knife": [D_THIN, D_THIN, D_BODY, D_FAT, D_FAT],
}

## And how much each subsequent part is grown *sideways*, in art units.
##
## **This one is not decoration either, and leaving it out is a visible bug.** Two
## parts whose rects share an edge **line** — which is exactly what a highlight
## strip drawn along the top edge of the plate underneath it is — still produce two
## *side* quads lying in the same plane, overlapping, at identical depth, however
## much `LAYER` separates their caps. There are 95 such pairs across the thirteen
## weapons and every one of the thirteen has at least two, so without this the top
## edge of every gun in the game is a z-fight between the plate and its own
## highlight: on the M1911 that is a 30-unit by 5-unit band, roughly 180 by 11
## pixels of speckle at the rest pose, in the middle of the screen, always.
##
## Growing part *i* outward by `i * PROUD` (see `_inflate`) puts the later part's
## side faces strictly proud of the earlier one's, which is what `LAYER` already
## does for the caps. 0.04 units is 42 micrometres, and at the 0.12 m this mesh
## sits at that is about 2400 levels of a 24-bit depth buffer — three orders of
## magnitude more than the interpolation error it has to beat. The cost is that the
## outermost part of an eleven-part weapon grows 0.4 units — under half a percent
## of that weapon's length, and worst on the one small high-index part in the
## table, the Thundergun's 2.2-unit hot core, which goes to 2.62 and so from about
## 13 screen pixels across to 15. Everything else moves by well under a pixel.
##
## Set it to 0.0 and `_inflate` returns the polygon untouched, which is the way to
## look at the bug rather than take my word for it.
const PROUD := 0.04

## Segments in a circle. Ten, because the largest circle in the table is the RPK's
## 7-unit drum at 7.4 mm across on screen and nobody will count its facets, and
## because every segment is two triangles in a build with no texture budget to
## spend on silhouettes.
const CIRCLE_SEGS := 10


# --- Pack-a-Punch ------------------------------------------------------------

## `makeViewmodel(art, 'rgba(96,64,200,.42)')` (:3432) composites this over the
## drawn weapon with `source-atop` (:1218-1222), which is exactly
## `base*(1-a) + tint*a` on the pixels the gun already covers — so in 3D it is a
## per-vertex lerp and costs no second material, no second shader and no texture.
const PAP_TINT := Color(96.0 / 255.0, 64.0 / 255.0, 200.0 / 255.0)
const PAP_ALPHA := 0.42


# --- the baked face ramp -----------------------------------------------------

## The viewmodel is drawn unshaded (see viewmodel.gd for why the torch cannot be
## allowed near it), so its only form comes from these five numbers, folded into
## the vertex colours at build time. Nothing is computed at runtime.
##
## **THIS REPLACES A CLAMPED DIRECTIONAL DOT PRODUCT, and the replacement is a fix
## rather than a retune.** What shipped was
## `f = FILL + KEY * max(n . normalize(-0.55, 0.70, 0.45), 0)` with FILL 0.86 and
## KEY 0.30. Three things were wrong with it and only the third is arguable:
##
##  1. **The clamp pinned three distinct orientations to one value.** Bottom -Y,
##     away cap +X and muzzle-facing -Z all scored a negative dot and all came out
##     at exactly 0.860. A per-part depth table (`DEPTH`) exists to create steps
##     along those very faces; a shading model that cannot tell them apart hands
##     back a flat picture from a stepped mesh.
##  2. **The model could not reach its own target.** Measured 2026-08-02 on the
##     shipped constants: the attainable dots are 0.551380 on the visible cap,
##     0.701757 on the top and 0.451129 on the stock end, so as FILL goes to zero
##     the ramp tops out at **1.556:1** top-to-end and **1.273:1** top-to-cap — and
##     only at FILL = 0, where every away-facing face is pure black. M5 R1 asks for
##     "materially more than 7.5%" against a 2:1 lineage; widening FILL and KEY is
##     arithmetically incapable of it. Three variants were rendered at 1280x720 and
##     measured over the hip silhouette before this was accepted.
##  3. Minecraft's `FaceBakery.getShade` — UP 1.0, N/S 0.8, E/W 0.6, DOWN 0.5 —
##     and every blocky-FPS lineage that copies it use a per-axis face ramp, and
##     M5's own style contract (rule 3) says a per-axis ramp is **more** voxel-like
##     than a directional key light, not less. So this is not a compromise made for
##     the arithmetic.
##
## **The mapping, and the one deliberate departure from the lineage.** Minecraft's
## two horizontal pairs are equal within themselves so that no visible face is ever
## the dark one under an arbitrary yaw. This weapon is not under an arbitrary yaw:
## the shading is baked in **model** space and the rig turns the gun by twelve
## degrees and never more, so which faces are seen is known at authoring time. The
## +/-X caps take Minecraft's brighter horizontal (0.8) because they are the faces
## that fill the screen; +Z, the stock end, keeps its shipped value outright; and
## -Z, the muzzle-facing side of every step `DEPTH` has just created, is given its
## own darker value instead of being tied to +Z. That last one is the departure and
## the reason for it is that a step is only a step if its two faces differ.
##
## **The scale is anchored, not chosen.** `SHADE_CAP` is the value the visible cap
## has under the shipped constants to four decimals (0.86 + 0.30*0.551380), and
## `SHADE_REAR` likewise (0.86 + 0.30*0.451129). Those two carry almost all of the
## weapon's screen area, so the ramp is a **redistribution** of the bracket and not
## a brightening of it — measured over the hip silhouette, an axis ramp that did
## not anchor them dropped the median from 40.6 to 31.1 code, which is a regression
## dressed as a contrast improvement. Top over bottom is Minecraft's 2:1 exactly.
const SHADE_TOP := 1.28         # +Y
const SHADE_CAP := 1.0254       # +/-X, the extrusion caps
const SHADE_REAR := 0.9953      # +Z, toward the viewer
const SHADE_FRONT := 0.78       # -Z, toward the muzzle
const SHADE_UNDER := 0.64       # -Y

## The shade of one flat face, and the only place a vertex colour is scaled.
##
## **The blend rule is the half of M5 R1 the first draft did not have, and without
## it the ramp is undefined on a third of the table.** An axis ramp is defined on
## six normals; `_extrude` emits one normal per side quad, and the 13 circles at
## `CIRCLE_SEGS` 10 and the two rotated rects (mp40 -0.35 rad, pm63 -0.45 rad) hand
## it normals that are on no axis at all — and the Ray Gun's five circles and the
## Thundergun's six are precisely the parts this exists to give form to.
##
## The value stays flat per face (style contract rule 3: no interpolation across a
## face) and only the *lookup* is blended, weighted by how much of the normal
## points down each of the six signed axes. On an axis-aligned face exactly one
## weight is non-zero and this reduces to that axis's constant; off-axis it walks
## between neighbours in 36-degree steps with no discontinuity.
##
## R1 writes the weight as `|n . axis|` over six axes. That is wrong as written and
## it is worth saying why rather than quietly fixing it: with an absolute value the
## +X and -X axes receive the *same* weight, so every signed pair collapses to its
## own average and the ramp becomes unsigned — top equals bottom, which is the one
## distinction the whole recommendation is about. `max(n . axis, 0)` is the same
## rule with the sign kept, and its six weights still sum to |x| + |y| + |z|.
static func face_shade(n: Vector3) -> float:
	var w := absf(n.x) + absf(n.y) + absf(n.z)
	if w <= 0.0:
		# Unreachable from `_extrude`, which normalises every normal it emits.
		# Returning the cap value rather than dividing by zero keeps a degenerate
		# face merely wrong instead of NaN, which would propagate into the whole
		# vertex colour and then into the frame.
		return SHADE_CAP
	var f := maxf(n.x, 0.0) * SHADE_CAP + maxf(-n.x, 0.0) * SHADE_CAP
	f += maxf(n.y, 0.0) * SHADE_TOP + maxf(-n.y, 0.0) * SHADE_UNDER
	f += maxf(n.z, 0.0) * SHADE_REAR + maxf(-n.z, 0.0) * SHADE_FRONT
	return f / w


# --- the hands ---------------------------------------------------------------

## `makeViewmodel` draws two gloved hands over every weapon (html:1223-1238), and
## they are not in `ART` — they are drawn from the `grips` table, which is `GRIP`
## above. Without them the weapon floats, which is the single most obvious way a
## viewmodel reads as wrong.
##
## Four rounded rects in the ancestor, four boxes here; the corner radius is the
## one thing that does not survive, and at this size it is two pixels. Positions
## and sizes are its canvas figures divided by the 1.9 it drew the parts at, so
## they land in the same art space as everything else: the main glove is
## `roundRect(gx*1.9-6, gy*1.9+2, 30, 26)` and the cuff over it
## `roundRect(gx*1.9-4, gy*1.9+4, 26, 10)`.
const HAND_MAIN := Color("2e2b26")
const HAND_CUFF := Color("3a362f")
const HAND_POS := Vector2(-3.158, 1.053)
const HAND_SIZE := Vector2(15.789, 13.684)
const CUFF_POS := Vector2(-2.105, 2.105)
const CUFF_SIZE := Vector2(13.684, 5.263)

## The support hand, further up the weapon: `roundRect(gx*1.9-58, gy*1.9-2, 28, 22)`
## with `roundRect(gx*1.9-56, gy*1.9, 24, 9)` over it.
const SUPPORT_POS := Vector2(-30.526, -1.053)
const SUPPORT_SIZE := Vector2(14.737, 11.579)
const SUPPORT_CUFF_POS := Vector2(-29.474, 0.0)
const SUPPORT_CUFF_SIZE := Vector2(12.632, 4.737)

## The ancestor's own exclusion list, verbatim (:1233): a pistol, a knife and a
## Ray Gun are held in one hand.
const ONE_HANDED := ["m1911", "knife", "raygun"]

## A hand is thicker than the gun it is wrapped around — five art units either
## side against the widest part's 4.14. Invented, because the ancestor's hands are
## as flat as everything else it drew.
const HAND_HALF := 5.0


# --- public ------------------------------------------------------------------

static func keys() -> Array:
	return ART.keys()


## Where the barrel ends, in the mesh's own space, so a `Marker3D` can be parked
## on it. Falls back to the ancestor's own default (`MUZZLE[art] || [10,25]`,
## :3145) rather than failing, because a missing row should cost a misplaced
## flash and not a crash mid-round.
static func muzzle_local(key: String) -> Vector3:
	var m: Vector2 = MUZZLE.get(key, Vector2(10, 25))
	return _to_local(m, _grip(key))


## Everything that is not the reciprocating group.
static func build_body(key: String, pap: bool) -> ArrayMesh:
	return _build(key, pap, false)


## The reciprocating group alone, or null when the weapon has none. Null is the
## contract, not an error: over half the table has no drawn bolt (see `SLIDE`).
static func build_slide(key: String, pap: bool) -> ArrayMesh:
	return _build(key, pap, true)


## Every extruded corner of the body, in the same mesh space `build_body` emits,
## for the clip measurement in `viewmodel.gd`.
##
## Read from the table rather than back off the committed `ArrayMesh`, for two
## reasons. `surface_get_arrays()` is a round trip through the rendering server
## and `--verify` runs against the dummy driver, where a silently empty result
## would make the assertion pass by measuring nothing — the one failure mode a
## safety assertion may not have. And an `AABB` is not a substitute: on a barrel
## this long it pairs the muzzle's z with the grip's y and overstates the reach by
## five millimetres.
##
## It shares `_parts`, `_part_poly`, `_inflate`, `_hands`, `_grip`, `_to_local` and
## — since the depth table landed — the same `part_half()` **call** with the
## builder, so the only step it does not run is the triangulation, and
## triangulation cannot move a vertex. That is what keeps this honest about the
## mesh that shipped rather than being a second copy of its arithmetic, and
## `checks/frame.gd` reads the committed `ArrayMesh` back and compares the two
## rather than taking the sharing on trust.
static func body_corners(key: String) -> PackedVector3Array:
	return _corners(key, false)


## The same for the reciprocating group. Empty when the weapon has none; the
## caller adds `SLIDE_TRAVEL` itself, because how far it travels is the rig's.
static func slide_corners(key: String) -> PackedVector3Array:
	return _corners(key, true)


## Cache for `sight_height`, keyed by weapon. Nothing invalidates it because
## nothing here is mutable: `ART`, `GRIP`, `SLIDE`, `UNIT`, `PROUD` are all
## constants, so a weapon's top edge is fixed at load.
static var _sight_cache: Dictionary = {}


## How far the weapon's own sighting surface — the top of it — sits above the
## grip, in metres. `viewmodel.gd` drops the whole rig by this at the sights so
## that what lands on the view axis is the top of the gun rather than the hand
## holding it; see `ADS_SIGHT_CLEAR` there for why that is what a hard scope is.
##
## **DERIVED FROM THE SAME CORNER WALK THE MESH IS BUILT FROM, and that is the
## whole reason it is a function and not a table.** Thirteen hand-read top edges
## would be a second copy of the art, and it would go stale the first time a part
## moved by a unit — silently, because a sight height that is wrong by two units
## looks like a weapon that is merely posed a little high.
##
## **`slide_corners` is not optional.** `body_corners` excludes whatever `SLIDE`
## names, and on the M1911 the topmost part IS the slide plate (`SLIDE` index 1, a
## rect at art y 20 against a grip at 30). Walking the body alone reads 8.00 art
## units against the real 10.24 and puts the flagship weapon's sight line 2.24
## units — about 13 px at the sighted pose in a 720 px frame — through the
## crosshair. The AK74u (12.28 against 11.04) and the RPK (11.32 against 11.04)
## are the other two the term catches.
##
## Measured across the table, this runs from 5.05 art units on the knife to 19.24
## on the Ray Gun — a spread of nearly four to one, which is why the rig cannot
## use one constant and get anything but the middle of the table right.
##
## Cached: the rig reads it through the pose, and `_corners()` walks and inflates
## every part of every shape. That is a load-time cost, not a per-frame one.
static func sight_height(key: String) -> float:
	if _sight_cache.has(key):
		var hit: float = _sight_cache[key]
		return hit
	# Zero rather than -INF for a key with no art, so a missing row costs an
	# unsighted weapon and not a NaN in the camera's transform — the same call the
	# `muzzle_local` fallback makes. It is also the right floor for real art: a
	# weapon whose every corner is below its own grip is not a weapon.
	var top := 0.0
	var body := body_corners(key)
	for p: Vector3 in body:
		top = maxf(top, p.y)
	var slide := slide_corners(key)
	for p: Vector3 in slide:
		top = maxf(top, p.y)
	_sight_cache[key] = top
	return top


# --- internals ---------------------------------------------------------------

static func _grip(key: String) -> Vector2:
	var g: Vector2 = GRIP.get(key, Vector2(50, 30))
	return g


## Art space to mesh space. The gun points **forward** — art +x runs muzzle to
## stock, so it maps to world +z, which is *toward* the viewer — and art +y is
## canvas-down, so it maps to world -y. The extrusion is left to right, on x.
##
## One consequence is worth stating because a later reader will otherwise
## rediscover it the hard way: under this mapping a canvas `rotate(t)` is exactly
## a rotation of `t` about world **+X**, so the ancestor's viewmodel tilt (:1216)
## and its reload roll (:3126) carry across as pitch, in radians, unchanged.
static func _to_local(p: Vector2, g: Vector2) -> Vector3:
	return Vector3(0.0, -(p.y - g.y) * UNIT, (p.x - g.x) * UNIT)


## Half the extrusion depth of part `i` of `key`, in metres.
##
## **The single source both `_build` and `_corners` read, and that is the entire
## point of it being a function.** M5 R2 names the trap in as many words: author
## per-part depth at one of the two call sites and the clip measurement measures a
## mesh that is not on screen. Two call sites reading one expression cannot drift;
## two call sites *copying* one expression have, historically, on this file.
##
## Falls back to 1.0 for a weapon with no `DEPTH` row, which is exactly the old
## behaviour — the same choice `muzzle_local` and `sight_height` make, for the same
## reason: a missing row should cost a badly proportioned gun and not a crash
## mid-round. `checks/frame.gd` asserts that no row is missing, so the fallback is
## a safety net rather than a supported state.
static func part_half(key: String, i: int) -> float:
	var mults: Array = DEPTH.get(key, [])
	var d := 1.0
	if i < mults.size():
		d = float(mults[i])
	# The `+ i*LAYER` tiebreak survived the move to authored depth and had to:
	# it is the coplanar-cap z-fight fix (see LAYER), and two parts given the same
	# multiplier — a highlight rib and the plate it is painted on, which is most of
	# this table — would reinstate that bug without it.
	return (BASE_HALF * d + float(i) * LAYER) * UNIT


static func _build(key: String, pap: bool, want_slide: bool) -> ArrayMesh:
	if not ART.has(key):
		return null
	var parts: Array = _parts(key)
	var slide: Array = SLIDE.get(key, [])
	var g := _grip(key)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0
	for i in parts.size():
		if slide.has(i) != want_slide:
			continue
		var part: Array = parts[i]
		# What the part is made of, plus the draw-order tiebreak — see DEPTH.
		var half := part_half(key, i)
		var col := _tint(part[part.size() - 1], pap)
		_extrude(st, _part_poly(part, float(i) * PROUD), g, half, col)
		emitted += 1
	if not want_slide:
		# Last, exactly as the ancestor draws them — after the parts and, note,
		# after the Pack-a-Punch composite, so the gun is tinted and the gloves are
		# not. `_tint(.., false)` is that ordering, not an oversight.
		for row: Array in _hands(key, g):
			var poly: PackedVector2Array = row[0]
			var half: float = row[1]
			var raw: Color = row[2]
			_extrude(st, poly, g, half * UNIT, _tint(raw, false))
		emitted += 1
	if emitted == 0:
		return null
	return st.commit()


## Same walk as `_build`, keeping only the vertex positions. Every number it
## reaches for is the one the builder used.
static func _corners(key: String, want_slide: bool) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not ART.has(key):
		return out
	var parts: Array = _parts(key)
	var slide: Array = SLIDE.get(key, [])
	var g := _grip(key)
	for i in parts.size():
		if slide.has(i) != want_slide:
			continue
		var part: Array = parts[i]
		# THE SAME ACCESSOR THE BUILDER CALLS. Not the same expression — the same
		# call. See `part_half`.
		var half := part_half(key, i)
		out.append_array(_prism_corners(_part_poly(part, float(i) * PROUD), g, half))
	if not want_slide:
		for row: Array in _hands(key, g):
			var poly: PackedVector2Array = row[0]
			var half: float = row[1]
			out.append_array(_prism_corners(poly, g, half * UNIT))
	return out


## The eight-or-more corners of one extruded part, in the same order and from the
## same `_to_local` the builder's own `_extrude` uses.
##
## Returns rather than filling a parameter, deliberately. Whether a
## `PackedVector3Array` handed to a function is the caller's array or a copy of it
## is a question this file should not have to be right about — and being wrong
## about it would leave `_corners` empty, which would make the clip assertion pass
## by measuring nothing at all.
static func _prism_corners(poly: PackedVector2Array, g: Vector2,
		half: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in poly.size():
		var p := _to_local(poly[i], g)
		out.append(Vector3(half, p.y, p.z))
		out.append(Vector3(-half, p.y, p.z))
	return out


## The gloved hands, as `[polygon, half-depth in art units, colour]` rows.
##
## One list rather than four calls, because the builder and `_corners` both walk
## it and a hand that existed in only one of them would make the clip assertion a
## measurement of a different weapon than the one on screen. Positions and sizes
## are the ancestor's canvas figures over the 1.9 it drew the parts at (see
## `HAND_POS`), and the exclusion list at `:1233` is `ONE_HANDED`.
##
## They are deliberately *not* inflated by `PROUD`: the cuff sits strictly inside
## the glove in the y-z plane and 0.14 units proud of it in x, and neither shares
## an edge line with any part in `ART`, so there is no coplanar pair here to break.
static func _hands(key: String, g: Vector2) -> Array:
	var out: Array = [
		[_hand_rect(g, HAND_POS, HAND_SIZE), HAND_HALF, HAND_MAIN],
		[_hand_rect(g, CUFF_POS, CUFF_SIZE), HAND_HALF + LAYER, HAND_CUFF]]
	if ONE_HANDED.has(key):
		return out
	out.append([_hand_rect(g, SUPPORT_POS, SUPPORT_SIZE), HAND_HALF, HAND_MAIN])
	out.append([_hand_rect(g, SUPPORT_CUFF_POS, SUPPORT_CUFF_SIZE),
		HAND_HALF + LAYER, HAND_CUFF])
	return out


## One box, positioned relative to the grip rather than in absolute art space,
## because that is how the ancestor positions them and it is why they fit thirteen
## different weapons without thirteen offsets.
static func _hand_rect(g: Vector2, at: Vector2, size: Vector2) -> PackedVector2Array:
	var p := g + at
	return PackedVector2Array([p, p + Vector2(size.x, 0.0), p + size,
		p + Vector2(0.0, size.y)])


## One part's outline in art space, already grown by `proud`.
##
## The ancestor reads a part's colour as `pt[pt.length-1]` (:1133) precisely
## because the four shapes carry it at four different indices; the geometry is at
## fixed indices per shape, which is what this switch is.
static func _part_poly(part: Array, proud: float) -> PackedVector2Array:
	var kind: String = part[0]
	var poly := PackedVector2Array()
	# Every local below carries its shape's prefix rather than the obvious short
	# name. Match branches have their own scope, but four branches declaring four
	# `x`es is a parse error away from a Godot that hangs rather than reports, and
	# nothing here is worth that.
	match kind:
		"r":
			var bx: float = part[1]
			var by: float = part[2]
			var bw: float = part[3]
			var bh: float = part[4]
			poly = PackedVector2Array([Vector2(bx, by), Vector2(bx + bw, by),
				Vector2(bx + bw, by + bh), Vector2(bx, by + bh)])
		"rr":
			# `translate(x,y); rotate(rot); fillRect(0,0,w,h)` (:1143-1144) — the
			# rect is laid out from the origin *after* the turn, so (x, y) is the
			# pivot and also one corner.
			var rx: float = part[1]
			var ry: float = part[2]
			var rw: float = part[3]
			var rh: float = part[4]
			var rot: float = part[5]
			var rc := cos(rot)
			var rs := sin(rot)
			for corner: Vector2 in [Vector2(0, 0), Vector2(rw, 0), Vector2(rw, rh),
					Vector2(0, rh)]:
				poly.append(Vector2(rx + corner.x * rc - corner.y * rs,
					ry + corner.x * rs + corner.y * rc))
		"c":
			var cx: float = part[1]
			var cy: float = part[2]
			var cr: float = part[3]
			for seg in CIRCLE_SEGS:
				var a := TAU * float(seg) / float(CIRCLE_SEGS)
				poly.append(Vector2(cx + cos(a) * cr, cy + sin(a) * cr))
		"p":
			var pv: Array = part[1]
			# A flat [x0,y0, x1,y1, ...] list, walked in pairs exactly as
			# `moveTo`/`lineTo` walk it at :1137-1139. Both polygons in the table are
			# convex, which is what lets the caps be a triangle fan — and what lets
			# `_inflate` use a mitre.
			var pi := 0
			while pi + 1 < pv.size():
				poly.append(Vector2(float(pv[pi]), float(pv[pi + 1])))
				pi += 2
	return _inflate(poly, proud)


## Pushes every edge of a convex polygon `proud` art units outward along its own
## normal. See `PROUD` for why this exists at all.
##
## The mitre is the standard one — a corner between edge normals `na` and `nb`
## moves along `(na + nb) / (1 + na.nb)`, which is exactly far enough that *both*
## edges end up `proud` out — and it is right for all four shapes: a rect corner
## (perpendicular normals) moves `proud` on each axis, and a ten-segment circle
## grows its circumradius by `proud / cos(18 degrees)`.
static func _inflate(poly: PackedVector2Array, proud: float) -> PackedVector2Array:
	var n := poly.size()
	if n < 3 or proud <= 0.0:
		return poly
	# Winding decides which side "outward" is, and it is *measured* rather than
	# assumed: a rect in this table is authored one way round and the knife's
	# polygons the other, and getting it backwards shrinks a part into itself
	# instead of growing it — which would be a silent art bug, not a crash.
	var area := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	var sgn := 1.0 if area > 0.0 else -1.0
	var norms := PackedVector2Array()
	for i in n:
		var e := poly[(i + 1) % n] - poly[i]
		if e.length_squared() < 1e-12:
			# A doubled point makes the normal undefined. Nothing in the table has
			# one; leaving the polygon alone is the harmless answer if one appears.
			return poly
		norms.append(Vector2(e.y, -e.x).normalized() * sgn)
	var out := PackedVector2Array()
	for i in n:
		var na := norms[(i + n - 1) % n]
		var nb := norms[i]
		var d := na.dot(nb)
		if d <= -0.99:
			# A spike, where the mitre would run away to infinity. Unreachable from
			# this table; capped rather than left to produce a NaN.
			out.append(poly[i] + nb * proud)
		else:
			out.append(poly[i] + (na + nb) * (proud / (1.0 + d)))
	return out


## Passed through as authored, with the Pack-a-Punch composite applied first
## because the ancestor applied it to the drawn image and that image was sRGB.
##
## THIS USED TO CALL srgb_to_linear(), on reasoning that is correct for a *lit*
## material and wrong for this one, and the frame settled it: the whole weapon came
## out near-black except the slide highlight. The argument for converting was that
## Godot renders in linear and encodes on the way out — true — but it stops one
## step short. This surface is `unshaded`, so its albedo is written straight into a
## buffer that FILMIC then tonemaps, and FILMIC crushes exactly the bottom of the
## range these gunmetal greys live in. Decoding sRGB and then handing the result to
## a tone curve applies two darkening transfer functions to a value that the
## ancestor wrote to the framebuffer with none at all.
##
## Passing the hex through unconverted very nearly cancels: the sRGB encode on the
## way out is the inverse of the decode being skipped, leaving only FILMIC's mild
## S-curve between the authored colour and the pixel. Verified in a rendered frame
## at 960x540 — slide, frame, trigger guard and grip panel all read as themselves.
##
## This is the same mistake, in the same direction, that the lighting pass made
## with the ancestor's 0.145 ambient floor. A number authored in display space is
## not a number in linear space, and on this project that has now cost two frames.
##
## One consequence worth knowing, **restated 2026-08-02 because the two accounts
## this file used to carry contradicted each other** (M5 F4 caught it): the version
## of this paragraph above the ramp constants computed the knife blade in LINEAR
## (0.839, "does not bloom") and this one computed it in DISPLAY (0.925, "does"),
## and only one of them can be right. The pipeline settles it: `_tint` passes the
## hex through unconverted, the surface is unshaded, so what reaches the glow
## filter is the display value times the face shade. **Display is the space to
## compute this in.**
##
## So, against `lighting.gd:215`'s GLOW_THRESHOLD of 0.92, on the brightest channel
## as Godot's filter thresholds it:
##
##   knife blade #E2E7EC (blue .925)   caps 0.948, top 1.000* -> blooms
##                                     ends 0.921 / 0.722, under 0.592 -> does not
##   Ray Gun core #E8FFC0 (green 1.0)  caps 1.000*, top 1.000*, rear 0.995 -> blooms
##                                     muzzle side 0.780, under 0.640 -> does not
##   Thundergun emitters #7ADFF0/#DFF9FF  the same shape
##
## `*` is a **truncation, not a product**: `SurfaceTool` stores vertex colours as
## RGBA8, so a channel driven past 1.0 by `SHADE_TOP` is clipped rather than
## carried. The ramp's headroom above 1.0 is therefore only spendable on art below
## `1/SHADE_TOP` = 0.781 on that channel — every gunmetal and every wood in the
## table, and none of the four emissive colours, which were already at the ceiling
## under the old bracket for the same reason. Found by the vertex-colour readback
## in `checks/frame.gd` failing on the Ray Gun's mid ring, not by reasoning.
##
## **M5 F36 is right and the old text here was wrong**: an emissive part does NOT
## clear the threshold on every face and never did — `FILL` alone was 0.860 against
## 0.92, so the three clamped faces missed it. The set of (colour, face) pairs that
## bloom is **unchanged** by the move to the face ramp on every face the camera can
## reach; that is checked in `checks/frame.gd` rather than asserted here, and it is
## a constraint on `SHADE_TOP` and `SHADE_CAP` rather than a happy accident.
static func _tint(raw: Variant, pap: bool) -> Color:
	var c: Color = raw
	if pap:
		c = c.lerp(PAP_TINT, PAP_ALPHA)
	return c


## One convex polygon in art space, extruded along x into a prism: two caps and
## one quad per edge.
##
## The winding of every face is *checked* rather than derived (see `_tri`), which
## is why this handles rects, rotated rects, circles and polygons through one path
## without four separate corner orders to get right.
static func _extrude(st: SurfaceTool, poly: PackedVector2Array, g: Vector2,
		half: float, col: Color) -> void:
	var n := poly.size()
	if n < 3:
		return

	var front := PackedVector3Array()
	var back := PackedVector3Array()
	var mid := Vector3.ZERO
	for i in n:
		var p := _to_local(poly[i], g)
		front.append(Vector3(half, p.y, p.z))
		back.append(Vector3(-half, p.y, p.z))
		mid += p
	mid /= float(n)

	for i in range(1, n - 1):
		_tri(st, front[0], front[i], front[i + 1], Vector3.RIGHT, col)
		_tri(st, back[0], back[i], back[i + 1], Vector3.LEFT, col)

	for i in n:
		var j := (i + 1) % n
		var e := front[j] - front[i]
		if e.length_squared() < 1e-12:
			continue
		# Perpendicular to the edge and to the extrusion axis, then turned outward
		# by testing it against the polygon's own centre — which is what makes a
		# clockwise and an anticlockwise source polygon both come out right.
		var nrm := e.cross(Vector3.RIGHT).normalized()
		var edge_mid := (front[i] + front[j]) * 0.5
		if nrm.dot(edge_mid - mid) < 0.0:
			nrm = -nrm
		_tri(st, front[i], front[j], back[j], nrm, col)
		_tri(st, front[i], back[j], back[i], nrm, col)


## One triangle, wound to face `n`.
##
## `world_builder._quad` establishes the convention this level renders under: the
## right-hand-rule normal of a front-facing triangle points **away** from the side
## the surface faces (check it on its floor quad — the winding gives -Y for a
## surface whose normal is +Y). Rather than hand-derive six box faces plus two cap
## orientations against that, the order is measured and swapped when it is wrong.
## Free: it runs at build time, thirteen times.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
		col: Color) -> void:
	var p1 := b
	var p2 := c
	if (b - a).cross(c - a).dot(n) > 0.0:
		p1 = c
		p2 = b
	var f := face_shade(n)
	var lit := Color(col.r * f, col.g * f, col.b * f, 1.0)
	for v: Vector3 in [a, p1, p2]:
		st.set_normal(n)
		st.set_color(lit)
		st.add_vertex(v)
