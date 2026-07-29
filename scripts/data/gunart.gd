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
## Three things here are NOT the ancestor's and are marked as such at their
## definition: `SLIDE` (which part reciprocates), the extrusion depth, and the
## baked key light. The ancestor's viewmodel was a flat 2D drawing, so it had no
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
## actually *draws* one. That is why more than half of these are empty — an M14's
## op-rod and an M16's charging handle are not in the picture, and moving a barrel
## or a carry handle instead would be worse than moving nothing. Weapons with no
## entry still recoil; the whole mesh kicks about the grip (see viewmodel.gd).
const SLIDE := {
	"m1911": [1, 6],       # the slide plate and the highlight rib along its top
	"olympia": [],         # break-action: nothing reciprocates
	"m14": [],             # the op-rod runs inside the receiver and is not drawn
	"mp40": [6],           # the bolt handle, the 10x3 strip above the barrel
	"pm63": [1],           # the receiver *is* the bolt on a PM63, and it is drawn
	"ak74u": [7],          # the charging-handle strip above the gas tube
	"stakeout": [2],       # the pump fore-end under the barrel
	"m16": [],             # part 2 is the carry handle, which does not move
	"rpk": [8],            # the charging-handle strip above the gas tube
	"chinalake": [6],      # the pump under the launcher tube
	"raygun": [],          # no moving parts drawn
	"thundergun": [],      # likewise
	"knife": [],
}


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
const BASE_HALF := 2.6
const LAYER := 0.14

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


# --- the baked key light -----------------------------------------------------

## The viewmodel is drawn unshaded (see viewmodel.gd for why the torch cannot be
## allowed near it), so its only form comes from these two numbers, folded into
## the vertex colours at build time. Nothing is computed at runtime.
##
## **Invented, but the ancestor was doing the same thing by hand:** almost every
## entry in `ART` ends with a 1-1.4 unit highlight strip along its top edge — a
## painted specular. This adds the rest of that idea to the faces the strips do
## not cover, at an amplitude small enough that the authored colours still read as
## themselves.
##
## The bracket matters and is not free choice. `lighting.gd` glows anything whose
## **brightest channel** passes 0.92 linear (Godot's glow filter thresholds on
## `max(r, g, b)`, not on luminance), and `FILL + KEY` = 1.16 is *not* the ceiling
## that reaches: no face can score `n.dot(KEY_DIR)` = 1, because every face this
## builder emits is either a cap on +/-X or a side facet in the y-z plane. The real
## ceilings are 1.025 on a cap and 1.110 on a side facet.
##
## Against those: the knife's blade (#E2E7EC, blue 0.839 linear) lands at 0.860 on
## its caps — the faces you actually see — so a knife does not bloom, and the Ray
## Gun's lens core (#E8FFC0, green 1.0) and the Thundergun's emitters (#DFF9FF)
## clear 0.92 on every face, so the parts that are supposed to be emitting are the
## parts that do. Raise `FILL + KEY*0.5514` — the cap ceiling — by seven percent and
## the blade's caps join them; that is the whole margin.
const FILL := 0.86
const KEY := 0.30

## Model space, and deliberately so: the shading then stays put as the weapon
## moves, which is what makes it read as painted-on rather than as a lamp. Aimed
## from above, from the camera's side of the gun (the rig sits to the right of the
## lens, so the visible face is model -X) and slightly from behind.
const KEY_DIR := Vector3(-0.55, 0.70, 0.45)


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
## It shares `_part_poly`, `_inflate`, `_hands`, `_grip`, `_to_local` and the same
## `BASE_HALF + i*LAYER` walk with the builder, so the only step it does not run is
## the triangulation — and triangulation cannot move a vertex. That is what keeps
## this honest about the mesh that shipped rather than being a second copy of its
## arithmetic.
static func body_corners(key: String) -> PackedVector3Array:
	return _corners(key, false)


## The same for the reciprocating group. Empty when the weapon has none; the
## caller adds `SLIDE_TRAVEL` itself, because how far it travels is the rig's.
static func slide_corners(key: String) -> PackedVector3Array:
	return _corners(key, true)


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


static func _build(key: String, pap: bool, want_slide: bool) -> ArrayMesh:
	if not ART.has(key):
		return null
	var parts: Array = ART[key]
	var slide: Array = SLIDE.get(key, [])
	var g := _grip(key)
	var kd := KEY_DIR.normalized()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted := 0
	for i in parts.size():
		if slide.has(i) != want_slide:
			continue
		var part: Array = parts[i]
		# Later parts stand proud of earlier ones — see LAYER and PROUD.
		var half := (BASE_HALF + float(i) * LAYER) * UNIT
		var col := _tint(part[part.size() - 1], pap)
		_extrude(st, _part_poly(part, float(i) * PROUD), g, half, col, kd)
		emitted += 1
	if not want_slide:
		# Last, exactly as the ancestor draws them — after the parts and, note,
		# after the Pack-a-Punch composite, so the gun is tinted and the gloves are
		# not. `_tint(.., false)` is that ordering, not an oversight.
		for row: Array in _hands(key, g):
			var poly: PackedVector2Array = row[0]
			var half: float = row[1]
			var raw: Color = row[2]
			_extrude(st, poly, g, half * UNIT, _tint(raw, false), kd)
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
	var parts: Array = ART[key]
	var slide: Array = SLIDE.get(key, [])
	var g := _grip(key)
	for i in parts.size():
		if slide.has(i) != want_slide:
			continue
		var part: Array = parts[i]
		var half := (BASE_HALF + float(i) * LAYER) * UNIT
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
## One consequence worth knowing: the brightest art in the table is the knife blade
## at #E2E7EC, whose blue channel is 0.925 undecoded, against lighting.gd's
## GLOW_THRESHOLD of 0.92. Its widest facets sit below that; only the thin side
## facets clear it, and by half a percent. A blade catching a highlight is the
## right look for it, so this is left alone — but it is the reason a future
## brightening of this table needs a look at the glow threshold too.
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
		half: float, col: Color, kd: Vector3) -> void:
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
		_tri(st, front[0], front[i], front[i + 1], Vector3.RIGHT, col, kd)
		_tri(st, back[0], back[i], back[i + 1], Vector3.LEFT, col, kd)

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
		_tri(st, front[i], front[j], back[j], nrm, col, kd)
		_tri(st, front[i], back[j], back[i], nrm, col, kd)


## One triangle, wound to face `n`.
##
## `world_builder._quad` establishes the convention this level renders under: the
## right-hand-rule normal of a front-facing triangle points **away** from the side
## the surface faces (check it on its floor quad — the winding gives -Y for a
## surface whose normal is +Y). Rather than hand-derive six box faces plus two cap
## orientations against that, the order is measured and swapped when it is wrong.
## Free: it runs at build time, thirteen times.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3,
		col: Color, kd: Vector3) -> void:
	var p1 := b
	var p2 := c
	if (b - a).cross(c - a).dot(n) > 0.0:
		p1 = c
		p2 = b
	var f := FILL + KEY * maxf(n.dot(kd), 0.0)
	var lit := Color(col.r * f, col.g * f, col.b * f, 1.0)
	for v: Vector3 in [a, p1, p2]:
		st.set_normal(n)
		st.set_color(lit)
		st.add_vertex(v)
