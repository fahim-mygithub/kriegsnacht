class_name MapData
extends RefCounted

## Static level description, ported 1:1 from kriegsnacht.html section 5.
##
## Coordinate mapping from the web build to Godot:
##   grid (x, y)  ->  Godot (x, 0, y)      1 tile == 1 metre == 1 Godot unit
##   tile centre  ->  (x + 0.5, _, y + 0.5)
## +Y is up, so the browser build's "south" (+y) becomes Godot's +Z.

const MAPW := 42
const MAPH := 34

## Metre scale carried over verbatim — this is what stops rooms reading as
## flat plains, and it is why every other height in the port is in metres.
const WALL_H := 2.8
const EYE := 1.55

# wall texture ids
const TX_CONCRETE := 0
const TX_WOOD := 1
const TX_BRICK := 2
const TX_METAL := 3
const TX_TILE := 4
const TX_DOOR := 5
const TX_DEBRIS := 6
const TX_WINDOW := 7

# floor texture ids
const FL_CARPET := 0
const FL_CEMENT := 1
const FL_COBBLE := 2
const FL_GRATE := 3

# ceiling texture ids
const CE_PLASTER := 0
const CE_NIGHT := 1
const CE_BEAMS := 2
const CE_METAL := 3

const WALL_TEX := ["concrete", "wood", "brick", "metal", "tile", "door", "debris"]
const FLOOR_TEX := ["carpet", "cement", "cobble", "grate"]
const CEIL_TEX := ["plaster", "night", "beams", "metal"]

const ROOMS := [
	{"x0": 3, "y0": 3, "x1": 14, "y1": 13, "w": TX_CONCRETE, "f": FL_CARPET, "c": CE_PLASTER, "name": "Lobby"},
	{"x0": 16, "y0": 7, "x1": 21, "y1": 10, "w": TX_TILE, "f": FL_CEMENT, "c": CE_PLASTER, "name": "Corridor"},
	{"x0": 23, "y0": 3, "x1": 38, "y1": 16, "w": TX_WOOD, "f": FL_CARPET, "c": CE_BEAMS, "name": "Theatre"},
	{"x0": 7, "y0": 15, "x1": 8, "y1": 17, "w": TX_CONCRETE, "f": FL_CEMENT, "c": CE_PLASTER, "name": "Stairwell"},
	{"x0": 3, "y0": 18, "x1": 14, "y1": 29, "w": TX_BRICK, "f": FL_COBBLE, "c": CE_NIGHT, "name": "Alley"},
	{"x0": 16, "y0": 23, "x1": 21, "y1": 24, "w": TX_CONCRETE, "f": FL_CEMENT, "c": CE_PLASTER, "name": "Tunnel"},
	{"x0": 29, "y0": 18, "x1": 30, "y1": 18, "w": TX_METAL, "f": FL_GRATE, "c": CE_METAL, "name": "Landing"},
	{"x0": 23, "y0": 19, "x1": 38, "y1": 31, "w": TX_METAL, "f": FL_GRATE, "c": CE_METAL, "name": "Generator Hall"},
]

## Free openings punched between rooms that already share a purchase.
const OPENINGS := [
	{"x": 22, "y": 8, "f": FL_CEMENT, "c": CE_PLASTER, "w": TX_WOOD},
	{"x": 22, "y": 9, "f": FL_CEMENT, "c": CE_PLASTER, "w": TX_WOOD},
	{"x": 22, "y": 23, "f": FL_CEMENT, "c": CE_METAL, "w": TX_METAL},
	{"x": 22, "y": 24, "f": FL_CEMENT, "c": CE_METAL, "w": TX_METAL},
]

## The canonical door table. `DOORS` below is the live one, because the seeded run
## layer moves the prices; this is the fixture every reset returns to.
const DOORS_FIXED := [
	{"tiles": [[15, 8], [15, 9]], "cost": 750, "label": "Open the theatre doors", "tex": TX_DOOR, "f": FL_CARPET, "c": CE_PLASTER},
	{"tiles": [[7, 14], [8, 14]], "cost": 1000, "label": "Open the stairwell", "tex": TX_DOOR, "f": FL_CEMENT, "c": CE_PLASTER},
	{"tiles": [[29, 17], [30, 17]], "cost": 1250, "label": "Open the generator hall", "tex": TX_DOOR, "f": FL_GRATE, "c": CE_METAL},
	{"tiles": [[15, 23], [15, 24]], "cost": 1250, "label": "Clear the debris", "tex": TX_DEBRIS, "f": FL_CEMENT, "c": CE_PLASTER},
]

## x/y is the wall tile itself; ix/iy is the open tile on the room side.
const WINDOWS := [
	{"x": 2, "y": 6, "ix": 3, "iy": 6}, {"x": 2, "y": 11, "ix": 3, "iy": 11}, {"x": 8, "y": 2, "ix": 8, "iy": 3},
	{"x": 18, "y": 6, "ix": 18, "iy": 7},
	{"x": 39, "y": 6, "ix": 38, "iy": 6}, {"x": 39, "y": 13, "ix": 38, "iy": 13},
	{"x": 27, "y": 2, "ix": 27, "iy": 3}, {"x": 34, "y": 2, "ix": 34, "iy": 3},
	{"x": 2, "y": 21, "ix": 3, "iy": 21}, {"x": 2, "y": 27, "ix": 3, "iy": 27}, {"x": 8, "y": 30, "ix": 8, "iy": 29},
	{"x": 39, "y": 23, "ix": 38, "iy": 23}, {"x": 39, "y": 29, "ix": 38, "iy": 29}, {"x": 30, "y": 32, "ix": 30, "iy": 31},
]

## What a barricade's exterior pocket is floored and roofed with.
##
## The ancestor drew the space beyond every window as night sky: `#080B10` filled
## the cell (html:807), `#0E1420` the opening inside it (html:808), and eighteen
## stars were stippled over that at `rgba(180,190,210, 0.15-0.6)` (html:809-810).
## The night ceiling is the
## same decision one level up, and it is already unshaded (see
## `world_builder._night_sky`) so the torch cannot light it — which is what stops a
## pocket reading as a cupboard with a painted roof. Cobble is the outdoor floor
## the Alley already uses.
const POCKET_FLOOR := FL_COBBLE
const POCKET_CEIL := CE_NIGHT

## Same split as DOORS: the gun-to-plaque assignment is what the run layer shuffles,
## so the table with the answers in it is the fixture and `WALLBUYS` is the live one.
## A slot is `tile` + `face`; a weapon is `gun` + `cost`, and the price travels with
## the weapon rather than with the wall — an M14 is 500 wherever it hangs.
const WALLBUYS_FIXED := [
	{"gun": "olympia", "tile": [15, 5], "face": [-1, 0], "cost": 500},
	{"gun": "m14", "tile": [12, 14], "face": [0, -1], "cost": 500},
	{"gun": "mp40", "tile": [22, 11], "face": [1, 0], "cost": 1000},
	{"gun": "stakeout", "tile": [39, 10], "face": [-1, 0], "cost": 1200},
	{"gun": "pm63", "tile": [15, 20], "face": [-1, 0], "cost": 1000},
	{"gun": "ak74u", "tile": [2, 24], "face": [1, 0], "cost": 1400},
	{"gun": "m16", "tile": [22, 26], "face": [1, 0], "cost": 1200},
]

const BOWIE := {"tile": [22, 5], "face": [1, 0], "cost": 3000}

## Six machines against a PERK_CAP of four, and the gap is the point: before the
## last two rows the map offered exactly four, so "four at once" described the
## inventory rather than limiting it. Both new spots are deep — Stamin-Up in the
## far corner of the Generator Hall, Mule Kick in the south-west of the Theatre —
## so neither is on the round-one side of a door and the 4000 is not a decision
## anybody makes early.
const PERKSPOTS_FIXED := [
	{"k": "revive", "x": 4.5, "y": 12.5},
	{"k": "dtap", "x": 37.5, "y": 4.5},
	{"k": "speed", "x": 4.5, "y": 19.5},
	{"k": "jug", "x": 24.5, "y": 20.5},
	{"k": "stamin", "x": 24.5, "y": 29.5},
	{"k": "mule", "x": 24.5, "y": 15.5},
]

const BOXSPOTS_FIXED := [Vector2(31.5, 12.5), Vector2(10.5, 25.5), Vector2(31.5, 26.5), Vector2(11.5, 11.5)]
const GENSPOT := Vector2(38.4, 30.5)
const PAPSPOT := Vector2(36.5, 22.5)
const SPAWN_TILE := Vector2i(8, 8)

## THE LIVE LAYOUT TABLES, and the reason four of them are `static var` rather than
## `const`.
##
## Eight files read `MapData.WALLBUYS` / `PERKSPOTS` / `BOXSPOTS` / `DOORS` through
## the class, and a GDScript `const` Array is read-only at runtime — so a seeded
## layout either mutates these in place or every one of those eight call sites has
## to be rewritten to ask an instance. A static var is the smaller change and it
## keeps the reads honest: there is exactly one live layout at a time and everything
## sees the same one.
##
## They are rebuilt from the `_FIXED` fixtures by `reset_layout()`, which
## `roll_layout()` calls first — so a static that survives `reload_current_scene()`
## can never accumulate two rolls.
static var DOORS: Array = []
static var WALLBUYS: Array = []
static var PERKSPOTS: Array = []
static var BOXSPOTS: Array = []


## Runs once, when the script is first loaded, so the tables are never empty —
## `interaction_system.build()` and `checks/curves.gd` both read them before
## anything has had a chance to roll a layout.
static func _static_init() -> void:
	reset_layout()

# --- interior geometry -------------------------------------------------------

## The height the shared line-of-sight test runs at: `los.clear_flat`'s own default
## (los.gd:47), which is what `zombie._has_los` uses, and the height
## `interaction_system._sees` aims its occlusion ray at (INTERACT_LOS_Y).
##
## Every prop below is sized against this one number, and in opposite directions,
## which is the whole design of this section:
##
##  - A prop that BLOCKS A TILE must stand taller than it. `zombie._physics_process`
##    overrides the flow field with a straight line whenever `_has_los` is clear
##    inside 9 m — so a waist-high crate that stops a body but not a sight line is a
##    thing the horde walks into and grinds against forever. Above this height the
##    crate occludes, the override drops out, and the field steers around it.
##  - A MACHINE must stand shorter than it, because its interact point is its own
##    centre. `_sees` stops the ray LOS_SLACK short of that point, and the ray runs
##    from the camera (1.55 m) downward to 1.2 m — so it clears anything under
##    1.2 m at every range and angle, and a machine taller than that would occlude
##    itself and be unbuyable. That is the bug `DOOR_LOS_SLACK` exists for, and this
##    is the way to not have it a second time.
const LOS_HEIGHT := 1.2
const PROP_BLOCK_H := 1.35
const MACHINE_H := 1.05

## The perk machines, Pack-a-Punch and the generator, as physics. Half-extents on
## the XZ plane, from the art each one is drawn with at its own pixel scale
## (atmosphere.gd): 44 px x 0.025 = 1.10 m of perk machine, 52 px x 0.0265625 =
## 1.38 m of Pack-a-Punch, 40 px x 0.025 = 1.00 m of generator. Set a little inside
## the drawn width so the collider never sticks out of the picture, and square
## because the sprite is BILLBOARD_FIXED_Y and has no fixed depth to match.
const MACHINE_HALF_PERK := 0.50
const MACHINE_HALF_PAP := 0.62
const MACHINE_HALF_GEN := 0.45
## And the mystery box, 56 px x 0.025 = 1.40 m of crate. The only one of the five
## whose collider has to move, because the only one whose position is run state.
const MACHINE_HALF_BOX := 0.62

## Interior geometry, as tile-aligned rectangles. `x0..x1`, `y0..y1` inclusive.
##
## NO ANCESTOR. `buildMap` (html:1571-1606) carves the room rectangles and then writes
## nothing else into `solid` but walls, doors and windows, and `blocked` (html:1625) is
## `solid[IX(x,y)]===1` and nothing more — so every room in the browser build is an
## empty box and there is no prop layer to port. This table and `prop_solid` are a
## deliberate departure designed against the reference, where a room without a pivot
## is a room you cannot train in: circling an empty rectangle means using the walls,
## which puts the horde between you and the middle of the room every lap. Kino's
## foyer, stage and dressing rooms are all built round something you can loop.
##
## `h` decides the class outright: at or above PROP_BLOCK_H the tiles are stamped
## into `prop_solid` and the flow field routes around them; below it a prop is cost
## only. There is nothing below it in this table, and the validator's
## "props are taller than the sight line" invariant is what keeps it that way.
##
## NOTHING SITS EXACTLY ONE TILE FROM A WALL, and this is not an aesthetic
## preference — it is the rule the validator's `prop-pinch` invariant enforces, and
## four of the placements below were moved because of it. A crate with a one-tile
## gap behind it makes that gap one-abreast, which by R5's own arithmetic is a
## guaranteed conga line in a place the level designer never chose to put one. The
## corner of a room is free (a prop against two walls creates nothing), and so is the
## middle; it is the near miss that costs.
##
## NOTHING IS PLACED IN THE CORRIDOR, THE TUNNEL, THE STAIRWELL OR THE LANDING.
## All four are two tiles wide, and R5's own throughput arithmetic
## (`agents_abreast(W) = floor((W - 0.52)/0.62) + 1`) says two tiles is three
## abreast and one tile is a guaranteed conga line — so a single crate in any of
## them converts a portal into a queue. The rooms are where a train wants pivots
## and the corridors are where it wants width.
const PROPS := [
	# Lobby. Three columns and a counter: the spawn room is where a player learns
	# to train, so it is the one room with a loop you can run without a door.
	{"x0": 6, "y0": 6, "x1": 6, "y1": 6, "h": WALL_H, "tex": "concrete", "inset": 0.15},
	{"x0": 6, "y0": 10, "x1": 6, "y1": 10, "h": WALL_H, "tex": "concrete", "inset": 0.15},
	{"x0": 11, "y0": 6, "x1": 11, "y1": 6, "h": WALL_H, "tex": "concrete", "inset": 0.15},
	{"x0": 3, "y0": 3, "x1": 4, "y1": 3, "h": PROP_BLOCK_H, "tex": "wood", "inset": 0.06},
	{"x0": 10, "y0": 9, "x1": 12, "y1": 9, "h": PROP_BLOCK_H, "tex": "wood", "inset": 0.06},
	# Theatre. A stage against the north wall and four columns off the seating.
	{"x0": 29, "y0": 3, "x1": 33, "y1": 4, "h": PROP_BLOCK_H, "tex": "wood", "inset": 0.02},
	{"x0": 26, "y0": 8, "x1": 26, "y1": 8, "h": WALL_H, "tex": "wood", "inset": 0.15},
	{"x0": 26, "y0": 13, "x1": 26, "y1": 13, "h": WALL_H, "tex": "wood", "inset": 0.15},
	{"x0": 35, "y0": 8, "x1": 35, "y1": 8, "h": WALL_H, "tex": "wood", "inset": 0.15},
	{"x0": 35, "y0": 13, "x1": 35, "y1": 13, "h": WALL_H, "tex": "wood", "inset": 0.15},
	{"x0": 27, "y0": 11, "x1": 28, "y1": 11, "h": PROP_BLOCK_H, "tex": "wood", "inset": 0.06},
	# Alley. Crates and one buttress off the brick.
	{"x0": 6, "y0": 22, "x1": 7, "y1": 22, "h": PROP_BLOCK_H, "tex": "wood", "inset": 0.06},
	{"x0": 11, "y0": 21, "x1": 11, "y1": 21, "h": PROP_BLOCK_H, "tex": "wood", "inset": 0.06},
	{"x0": 11, "y0": 26, "x1": 11, "y1": 26, "h": WALL_H, "tex": "brick", "inset": 0.15},
	{"x0": 5, "y0": 26, "x1": 5, "y1": 27, "h": PROP_BLOCK_H, "tex": "wood", "inset": 0.06},
	# Generator Hall. Plant, not furniture.
	{"x0": 26, "y0": 22, "x1": 27, "y1": 23, "h": PROP_BLOCK_H, "tex": "metal", "inset": 0.04},
	{"x0": 33, "y0": 21, "x1": 33, "y1": 21, "h": WALL_H, "tex": "metal", "inset": 0.15},
	{"x0": 33, "y0": 25, "x1": 33, "y1": 25, "h": WALL_H, "tex": "metal", "inset": 0.15},
	{"x0": 26, "y0": 28, "x1": 26, "y1": 28, "h": WALL_H, "tex": "metal", "inset": 0.15},
	{"x0": 34, "y0": 29, "x1": 36, "y1": 29, "h": PROP_BLOCK_H, "tex": "metal", "inset": 0.04},
]


## The cost field, as bytes.
##
## R5 §4.5 item 4: an 8-bit cost field with a wall-adjacency blur is the published
## fix for corner bunching — a uniform BFS treats a tile scraping masonry exactly
## like the middle of a corridor, which is what makes a pack file along one side.
##
## COST_BASE is 8 rather than 1 so that the blur has somewhere to live: a wall-hugging
## tile at 12 is 1.5x the cost of an open one, which biases a route to the middle of
## a three-wide corridor without ever refusing a two-wide one. COST_WALL is the
## impassable sentinel and is never a distance a solver should add.
##
## NOTHING READS THIS FIELD YET. `flow_field.solve()` is still an unweighted BFS over
## `is_blocked()`, so today the array is built, kept in step with the blocking grid
## (the validator's `cost-agrees` invariant is what keeps it honest) and consumed by
## nobody. Turning it on is a single edit to `flow_field.gd`, which is not this
## package's file; until that lands, every number in this section is inert and the
## assertions that read it say so.
const COST_BASE := 8
const COST_WALL := 255
const COST_NEAR_WALL := 4
const COST_DIAG_WALL := 2
## `machine_at`'s value for the mystery box. Outside the range of
## `machine_positions()` because the box is not in it: the eight fixed machines are
## stamped once by `build()` and the box is moved by `set_box_block()`, and the
## validator has to be able to tell "the level put this here" from "this run did".
const MACHINE_BOX := 1000

# --- runtime grids -----------------------------------------------------------

var solid := PackedByteArray()
var wtex := PackedByteArray()
var ftex := PackedByteArray()
var ctex := PackedByteArray()
var door_at := PackedInt32Array()
var win_at := PackedInt32Array()
## Tile -> the window whose exterior pocket it is, or -1. The pockets are open
## floor that the player must never be able to stand on, which is the whole reason
## this grid exists separately from `solid`.
var pocket_at := PackedInt32Array()
var reach := PackedByteArray()
## Fixed per-tile brightness jitter so a 64px texture stops reading as wallpaper.
var tile_shade := PackedFloat32Array()

## Tiles a blocking prop stands on, and which entry of PROPS put it there.
##
## Kept out of `solid` rather than folded into it, because the two are read for
## different questions and only one of them is about masonry: `world_builder`
## walks `solid` to decide where a wall FACE goes, and a crate that entered that
## grid would have the room's wall texture emitted around it and its own floor quad
## deleted. `is_blocked()` is where the two meet, which is the one place — pathing
## and body movement — that genuinely cannot tell them apart.
##
## THE MACHINES ARE IN HERE TOO, and that is the fix for the one thing this grid
## exists to prevent. A perk machine, Pack-a-Punch, the generator and the mystery box
## all got a real `BoxShape3D` on collision layer 1 in T3.4, and every one of them is
## a metre of solid body-blocking geometry. `MACHINE_H` has to stay UNDER
## `LOS_HEIGHT` or a machine occludes its own interact point and can never be bought
## — so the shared sight line runs straight over the top of one and
## `zombie._physics_process` keeps its straight-line override on. Left out of this
## grid as well, a machine was solid to `move_and_slide` and invisible to both the
## flow field and `_has_los`: the exact "stops a body but not a sight line" case the
## PROP_BLOCK_H rule was written to forbid, built eight times over.
##
## The ancestor could not have this bug and it is worth saying why: `hasLOS`
## (html:2166) and `computeFlow` (html:2152) are both grid walks over the same
## `blocked()`, so the ray and the path there could not disagree. In 3D the ray is a
## physics cast and the path is a grid walk, and this array is what keeps them
## describing the same building.
var prop_solid := PackedByteArray()
var prop_at := PackedInt32Array()
## Which machine fills a tile, indexing `machine_positions()`, or -1.
##
## A second marker rather than a second blocking grid, so `is_blocked`,
## `compute_reach` and the cost blur stay one test rather than two. It exists because
## the validator has to tell the two apart: a prop standing on an interact point is a
## typo, and a machine standing on its own interact point is what a machine IS.
var machine_at := PackedInt32Array()

## Per-tile traversal cost, 0..255, COST_WALL meaning impassable. See the constants.
var cost := PackedByteArray()

## The tile the mystery box's collider is standing on, or (-1, -1) before the first
## `set_box_block()`. Run state rather than level data, which is why it is here and
## not in `_stamp_machines()`.
var box_tile := Vector2i(-1, -1)

## Mutable per-window state: boards remaining, and how many zombies are working
## the window right now.
##
## Both are run state on the map for the same reason: they are read from three
## unrelated places — the round director when it picks a spawn window, the
## interaction prompt when it decides whether to offer a rebuild, and the barricade
## itself — and a value copied into any one of those goes stale the first time one
## of the others moves it. `barricade.gd` is the only writer of either.
var window_boards := PackedInt32Array()
var window_workers := PackedInt32Array()
var door_open := PackedByteArray()


## The two neighbourhoods, hoisted out of the loops that walk them. The blur runs
## 1428 x 8 times per rebuild and the flood fill 1428 x 4, and a literal inside
## either is a fresh Array allocation on every iteration.
const NEIGHBOURS4 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const NEIGHBOURS8 := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]


static func ix(x: int, y: int) -> int:
	return y * MAPW + x


func build() -> void:
	var n := MAPW * MAPH
	solid.resize(n); solid.fill(1)
	wtex.resize(n); wtex.fill(TX_CONCRETE)
	ftex.resize(n); ftex.fill(0)
	ctex.resize(n); ctex.fill(0)
	door_at.resize(n); door_at.fill(-1)
	win_at.resize(n); win_at.fill(-1)
	pocket_at.resize(n); pocket_at.fill(-1)
	prop_solid.resize(n); prop_solid.fill(0)
	prop_at.resize(n); prop_at.fill(-1)
	machine_at.resize(n); machine_at.fill(-1)
	cost.resize(n); cost.fill(COST_BASE)
	reach.resize(n)
	tile_shade.resize(n)

	for i in n:
		# Same hash as the web build. There it was clamped to a Uint8Array and
		# had to stay under 256; here it is just a 0.83..1.0 multiplier.
		# Masked to 32 bits so it matches the browser build's `>>> 0`.
		var h := ((i * 2654435761) ^ (i << 7)) & 0xFFFFFFFF
		tile_shade[i] = (212.0 + float(h % 44)) / 256.0

	for r in ROOMS:
		for y in range(r.y0, r.y1 + 1):
			for x in range(r.x0, r.x1 + 1):
				_carve(x, y, r.f, r.c)
	for o in OPENINGS:
		_carve(o.x, o.y, o.f, o.c)

	# Give each wall tile the texture of whichever room it faces.
	for r in ROOMS:
		for y in range(r.y0 - 1, r.y1 + 2):
			for x in range(r.x0 - 1, r.x1 + 2):
				if x < 0 or y < 0 or x >= MAPW or y >= MAPH:
					continue
				if solid[ix(x, y)] == 1:
					wtex[ix(x, y)] = r.w
	for o in OPENINGS:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var i := ix(o.x + d.x, o.y + d.y)
			if solid[i] == 1:
				wtex[i] = o.w

	door_open.resize(DOORS.size()); door_open.fill(0)
	for di in DOORS.size():
		for t in DOORS[di].tiles:
			var i := ix(t[0], t[1])
			solid[i] = 1
			wtex[i] = DOORS[di].tex
			door_at[i] = di
			ftex[i] = DOORS[di].f
			ctex[i] = DOORS[di].c

	window_boards.resize(WINDOWS.size()); window_boards.fill(6)
	window_workers.resize(WINDOWS.size()); window_workers.fill(0)
	for wi in WINDOWS.size():
		var w: Dictionary = WINDOWS[wi]
		var i := ix(w.x, w.y)
		solid[i] = 1
		wtex[i] = TX_WINDOW
		win_at[i] = wi
		# Nothing renders a solid tile's floor texture, but `fx.gd` decides which
		# debris a round throws by quantising the hit point to the grid and reading
		# these arrays — and a barricade now has a real aperture with a real stone
		# sill a bullet can land on top of. Without this the sill sprayed carpet,
		# which is only what `ftex.fill(0)` happened to leave there.
		ftex[i] = POCKET_FLOOR

	# Carved last, and deliberately after the room wall-texture pass: a pocket sits
	# outside every room's rectangle, so the tiles around it keep the default
	# concrete — which is also the closest thing in the wall set to the `#4A4740`
	# masonry the ancestor drew around every window opening (html:812).
	for wi in WINDOWS.size():
		var p := window_pocket(wi)
		if p.x < 0 or p.y < 0 or p.x >= MAPW or p.y >= MAPH:
			continue
		_carve(p.x, p.y, POCKET_FLOOR, POCKET_CEIL)
		pocket_at[ix(p.x, p.y)] = wi

	_stamp_props()
	_stamp_machines()
	rebuild_cost()
	compute_reach()


## Blocking props into `prop_solid`. A prop on a tile that is already masonry is a
## typo, not a decision, so it is left out of the grid entirely and the validator's
## "every prop stands on open floor" invariant is what says so out loud — silently
## stamping it would make a prop inside a wall indistinguishable from a wall.
func _stamp_props() -> void:
	for pi in PROPS.size():
		var p: Dictionary = PROPS[pi]
		if float(p.h) < PROP_BLOCK_H:
			continue
		for y in range(int(p.y0), int(p.y1) + 1):
			for x in range(int(p.x0), int(p.x1) + 1):
				if x < 0 or y < 0 or x >= MAPW or y >= MAPH:
					continue
				var i := ix(x, y)
				if solid[i] == 1:
					continue
				prop_solid[i] = 1
				prop_at[i] = pi


## The one tile each machine's collider actually fills.
##
## ONE TILE, not the collider's whole footprint, and the difference matters for two
## of the eight. A perk machine is `MACHINE_HALF_PERK` = 0.50, so its box is exactly
## the tile it stands on and there is nothing to round. Pack-a-Punch at 0.62 and the
## generator at 0.45-off-centre spill 0.12 m and 0.05 m into a neighbour, and a body
## is 0.52 m wide: 0.88 m of a metre is still a tile you walk through. Blocking the
## neighbours would wall off open floor that a zombie can plainly cross.
##
## The centre tile is the same `int(m.x), int(m.y)` the cost bump has always used, so
## the two cannot describe different machines.
func _stamp_machines() -> void:
	var pts := machine_positions()
	for mi in pts.size():
		var m: Vector2 = pts[mi]
		var x := int(m.x)
		var y := int(m.y)
		if x < 0 or y < 0 or x >= MAPW or y >= MAPH:
			continue
		var i := ix(x, y)
		# A machine inside masonry is an authoring error, not a decision, and it is
		# left out here so the validator's `machine-in-wall` can say so out loud
		# rather than being hidden behind a tile that was already solid.
		if solid[i] == 1:
			continue
		prop_solid[i] = 1
		machine_at[i] = mi


## Moves the mystery box's tile in the grid, so the field routes around the crate a
## body cannot walk through.
##
## The ninth machine and the only one that moves, which is why it is a method rather
## than part of `_stamp_machines()`: a block baked in at build time would be left
## behind at a spot the teddy bear had already moved the box away from.
## `world_builder.set_box_collider()` is the one caller and it calls this from the
## same place it moves the `BoxShape3D`, so the grid and the shape cannot be at
## different spots.
##
## `compute_reach()` is deliberately NOT called, and the licence for that is one
## specific assertion: `map_validator._check_state`'s `box-choke`, which proves no box
## spot is a cut vertex — every spot, EVERY DOOR STATE. The state qualifier is the
## whole of it and it was not true when this comment was first written: the check ran
## only with every door bought, which is the state with the most routes and therefore
## the fewest cut vertices, while the box relocates mid-run in whatever state the run
## is actually in. Given the invariant, blocking a spot can never take a tile away
## from the fill, and re-flooding 1428 tiles on a frame the teddy bear is already
## relocating the box on would be paying for an answer that cannot have changed.
func set_box_block(pos: Vector2) -> void:
	var nt := Vector2i(int(pos.x), int(pos.y))
	if nt == box_tile:
		return
	if box_tile.x >= 0:
		var oi := ix(box_tile.x, box_tile.y)
		if machine_at[oi] == MACHINE_BOX:
			prop_solid[oi] = 0
			machine_at[oi] = -1
			_patch_cost_around(box_tile.x, box_tile.y)
	box_tile = nt
	if nt.x < 0 or nt.y < 0 or nt.x >= MAPW or nt.y >= MAPH:
		return
	var i := ix(nt.x, nt.y)
	if solid[i] == 1 or prop_solid[i] == 1:
		return
	prop_solid[i] = 1
	machine_at[i] = MACHINE_BOX
	_patch_cost_around(nt.x, nt.y)


## One tile's blocked-ness changed, so the blur has moved for it and its eight
## neighbours and for nothing else. Same 3x3 patch `open_door` uses, and for the same
## reason: this runs on a live frame.
func _patch_cost_around(x: int, y: int) -> void:
	for dy: int in [-1, 0, 1]:
		for dx: int in [-1, 0, 1]:
			var nx := x + dx
			var ny := y + dy
			if nx < 0 or ny < 0 or nx >= MAPW or ny >= MAPH:
				continue
			_cost_tile(nx, ny)


func _carve(x: int, y: int, f: int, c: int) -> void:
	var i := ix(x, y)
	solid[i] = 0
	ftex[i] = f
	ctex[i] = c


## The exterior pocket behind a barricade: the window tile mirrored through itself,
## one step further from the room.
##
## Zombies have to have somewhere to *be* while they work the boards, and a
## barricade you can shoot through has to have something behind it other than the
## inside of a wall. The pocket is standable and it is never reachable by the
## player: the window tile stays solid, so `move_and_slide` and the flow field both
## treat a stripped barricade as a wall, and only the barricade's own vault path
## crosses it.
func window_pocket(wi: int) -> Vector2i:
	var w: Dictionary = WINDOWS[wi]
	return Vector2i(2 * int(w.x) - int(w.ix), 2 * int(w.y) - int(w.iy))


## Where a zombie stands to work a window's boards — now outside, in the pocket.
##
## In the browser build this had to sit on the *room* side of the wall plane or the
## depth buffer swallowed the sprite (html:1600-1603), so a zombie "at a window"
## was already standing in the room and the boards were a number ticking down
## beside it. In real 3D that constraint is gone and there is somewhere outside to
## stand, so the attacker is where the fiction always said it was. The 0.33 bias
## toward the wall is the ancestor's own, kept so the body still reads as pressed
## up against the barricade rather than loitering in the middle of the pocket.
func window_stand_pos(wi: int) -> Vector2:
	var w: Dictionary = WINDOWS[wi]
	var p := window_pocket(wi)
	return Vector2(
		p.x + 0.5 + (int(w.x) - p.x) * 0.33,
		p.y + 0.5 + (int(w.y) - p.y) * 0.33
	)


## Flood fill from the player's start so we know which windows are live.
## Doors are solid until bought, so this naturally re-opens areas on purchase.
func compute_reach() -> void:
	reach.fill(0)
	var start := ix(SPAWN_TILE.x, SPAWN_TILE.y)
	var q: Array[int] = [start]
	reach[start] = 1
	var head := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		var x := i % MAPW
		var y := i / MAPW
		for d: Vector2i in NEIGHBOURS4:
			var nx := x + d.x
			var ny := y + d.y
			if nx < 0 or ny < 0 or nx >= MAPW or ny >= MAPH:
				continue
			var ni := ix(nx, ny)
			if reach[ni] == 1:
				continue
			# A blocking prop is a wall to everything that walks, and `reach` is what
			# decides which windows are live and which box spots exist — so a crate
			# that sealed a corridor and left this fill walking through it would put
			# spawns on the far side of somewhere nothing can get to.
			if prop_solid[ni] == 1:
				continue
			# The exterior pockets are open tiles the player must never reach, and
			# `live_windows()` and every door purchase are decided by this fill. The
			# fill already stops at a barricade — a window tile is marked reachable
			# but never enqueued, because it is solid — so on today's fourteen
			# windows this line changes nothing. It is here because that is an
			# accident of where the windows happen to sit: one moved to a tile whose
			# pocket touches open ground would silently turn the outside of the
			# building into somewhere the player can walk to, with no symptom but a
			# door that has stopped gating anything.
			if pocket_at[ni] >= 0:
				continue
			# Windows count as reachable edges — that is how zombies get in.
			if solid[ni] == 1 and win_at[ni] < 0:
				continue
			reach[ni] = 1
			if solid[ni] == 0:
				q.append(ni)


# --- the cost field ----------------------------------------------------------

## Base cost plus the wall-adjacency blur. Rebuilt outright rather than patched,
## because it is 1428 bytes and the only things that move it — a door purchase and a
## `--verify` sweep — are not frame events.
##
## The blur is one pass over the eight neighbours rather than a separable kernel:
## at this radius the two are the same arithmetic and the separable form needs a
## second buffer.
##
## THERE IS NO LONGER A MACHINE TERM HERE, and its removal is the point. A machine
## used to be `COST_MACHINE` dearer and still passable, which was a fiction: the
## `BoxShape3D` on layer 1 stops a body dead, so a solver that paid forty extra and
## then walked into it was steering by a map that does not exist. Machines are in
## `prop_solid` now and `_cost_tile` gives them `COST_WALL` like anything else that
## cannot be walked through.
func rebuild_cost() -> void:
	for y in MAPH:
		for x in MAPW:
			_cost_tile(x, y)


## One tile's base cost and blur.
##
## Written with index arithmetic rather than `for d in NEIGHBOURS8`, and the reason
## is measured: iterating a const Array of Vector2i unboxes a Variant eleven
## thousand times per rebuild, and the validator runs a rebuild eighteen times per
## door-state sweep and again for every seed. This is the inner loop of the whole
## map layer.
func _cost_tile(x: int, y: int) -> void:
	var i := ix(x, y)
	if solid[i] == 1 or prop_solid[i] == 1:
		cost[i] = COST_WALL
		return
	var c := COST_BASE
	var x0 := x > 0
	var x1 := x < MAPW - 1
	var y0 := y > 0
	var y1 := y < MAPH - 1
	# Off the grid counts as solid: the border ring already is, and a tile on the
	# edge of the map is against a wall whether or not there is an array element for
	# it.
	# Written out rather than routed through a helper: a call per neighbour is eleven
	# thousand GDScript calls per rebuild, and this is the inner loop of the map layer.
	c += COST_NEAR_WALL if (not x0 or solid[i - 1] == 1 or prop_solid[i - 1] == 1) else 0
	c += COST_NEAR_WALL if (not x1 or solid[i + 1] == 1 or prop_solid[i + 1] == 1) else 0
	c += COST_NEAR_WALL if (not y0 or solid[i - MAPW] == 1 or prop_solid[i - MAPW] == 1) else 0
	c += COST_NEAR_WALL if (not y1 or solid[i + MAPW] == 1 or prop_solid[i + MAPW] == 1) else 0
	var d0 := i - MAPW - 1
	var d1 := i - MAPW + 1
	var d2 := i + MAPW - 1
	var d3 := i + MAPW + 1
	c += COST_DIAG_WALL if (not x0 or not y0 or solid[d0] == 1 or prop_solid[d0] == 1) else 0
	c += COST_DIAG_WALL if (not x1 or not y0 or solid[d1] == 1 or prop_solid[d1] == 1) else 0
	c += COST_DIAG_WALL if (not x0 or not y1 or solid[d2] == 1 or prop_solid[d2] == 1) else 0
	c += COST_DIAG_WALL if (not x1 or not y1 or solid[d3] == 1 or prop_solid[d3] == 1) else 0
	cost[i] = mini(c, COST_WALL - 1)


## A map in the same state as this one, sharing nothing with it.
##
## Exists for the validator, which needs one map per door-open state and would
## otherwise pay `build()` sixteen times for sixteen grids that differ in eight
## tiles. Every field below is a Packed array, so this is a memcpy each and the
## whole clone is cheaper than one pass of the cost blur.
##
## `window_boards` and `window_workers` come too, even though nothing that clones a
## map cares about barricade state today: a copy that silently omits a field is the
## kind of thing that is correct until the first caller that needs it.
func clone() -> MapData:
	var m := MapData.new()
	m.solid = solid.duplicate()
	m.wtex = wtex.duplicate()
	m.ftex = ftex.duplicate()
	m.ctex = ctex.duplicate()
	m.door_at = door_at.duplicate()
	m.win_at = win_at.duplicate()
	m.pocket_at = pocket_at.duplicate()
	m.prop_solid = prop_solid.duplicate()
	m.prop_at = prop_at.duplicate()
	m.machine_at = machine_at.duplicate()
	m.box_tile = box_tile
	m.cost = cost.duplicate()
	m.reach = reach.duplicate()
	m.tile_shade = tile_shade.duplicate()
	m.window_boards = window_boards.duplicate()
	m.window_workers = window_workers.duplicate()
	m.door_open = door_open.duplicate()
	return m


## Every floor-standing machine that has a collider, as a world position. The perk
## machines move with the run layout, so this is derived rather than tabled.
##
## The mystery box is NOT here: it relocates on a teddy bear, and a block baked in at
## build time would be left behind at a spot the box has left — a wall in the field
## with nothing standing in it. It rides `set_box_block()` from the node that knows
## where it is.
func machine_positions() -> Array[Vector2]:
	var out: Array[Vector2] = [GENSPOT, PAPSPOT]
	for ps: Dictionary in PERKSPOTS:
		out.append(Vector2(ps.x, ps.y))
	return out


func open_door(di: int) -> void:
	if door_open[di] == 1:
		return
	door_open[di] = 1
	for t in DOORS[di].tiles:
		var i := ix(t[0], t[1])
		solid[i] = 0
	# The blur reads the eight tiles around each one, so a door that stops being a
	# wall changes the cost of everything within one tile of it — including the two
	# doorway tiles themselves, which were COST_WALL a moment ago and would otherwise
	# stay impassable to any solver reading this field.
	#
	# LOCAL, not a full rebuild. Only the 3x3 around each door tile can have moved,
	# and a purchase happens mid-round on a platform where the whole frame is the
	# budget — eighteen tiles instead of fourteen hundred. It is also what makes the
	# validator's sixteen-state sweep affordable, and therefore what makes checking
	# every seed affordable.
	for t in DOORS[di].tiles:
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var nx: int = int(t[0]) + dx
				var ny: int = int(t[1]) + dy
				if nx < 0 or ny < 0 or nx >= MAPW or ny >= MAPH:
					continue
				_cost_tile(nx, ny)
	compute_reach()


func is_blocked(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= MAPW or y >= MAPH:
		return true
	var i := ix(x, y)
	return solid[i] == 1 or prop_solid[i] == 1


func live_windows() -> Array[int]:
	var out: Array[int] = []
	for wi in WINDOWS.size():
		var w: Dictionary = WINDOWS[wi]
		if reach[ix(w.ix, w.iy)] == 1:
			out.append(wi)
	return out


# --- the seeded run layer ----------------------------------------------------

## WHAT A SEED IS ALLOWED TO MOVE, and what it is not.
##
## The reference has fixed maps: Kino's Juggernog is in the same room every game,
## and learning where it is IS the progression. A roguelike layer that moved the
## walls would be a different game. What moves here is only what a player could
## have found somewhere else on some other map — which perk is in which alcove,
## which weapon is chalked on which wall, which crate the box is under, and what a
## door costs. The geometry, the windows, the spawn and the room shapes are fixed,
## which is also why a rolled layout needs no geometry rebuild: `world_builder`
## reads none of these tables.
##
## THE ROLL TAKES AN RNG RATHER THAN REACHING FOR ONE. Constraint 6 makes Rng the
## single authority and the layout is a gameplay draw, so the caller passes
## `Rng.stream(Rng.ROUNDS)` — the run-structure stream, the same one the dog-round
## cadence and the barricade regrowth come out of. Taking it as a parameter is what
## lets `checks/mapgen.gd` sweep hundreds of seeds without either duplicating the
## seeding convention or teaching this file about the autoload.

## A run must be able to buy A gun before it can buy a door. Both starting-room
## slots holding 1200-point weapons is a run that opens with nothing but the M1911
## against round three, and at a 7-slot full permutation it comes up about half the
## time — this is the rejection test, and `roll_layout` reports whether it ever had
## to give up.
const EARLY_GUN_MAX := 600

## How far a door's price may move, and the quantum it lands on. The SUM is held at
## the canonical 4250 (see `_roll_door_costs`) — a run where every door is cheap is
## not a variant, it is an easier game, and the interesting question a seed can ask
## is which direction you open the map in, not how much map you get.
const DOOR_COST_SPREAD := 0.35
const DOOR_COST_STEP := 50
const DOOR_COST_MIN := 300

## Chebyshev radius, in tiles, that a mystery-box spot may wander inside its own
## room. Confined to the room on purpose: `mystery_box.spot_door_depth()` classifies
## each spot by how many purchases deep it is and refuses to start a run behind more
## than one, and a spot that drifted through a doorway would silently change class.
const BOX_JITTER := 3

## Attempts before the roll gives up and ships the canonical layout. 64 against a
## test a uniform permutation passes about half the time makes an unseeded fallback
## effectively impossible; it exists so that a future constraint which is
## accidentally unsatisfiable produces a playable map and a failed assertion rather
## than an infinite loop at boot.
const LAYOUT_TRIES := 64

## Cached, layout-invariant facts about the fixed geometry: which wall-buy slots are
## reachable before any door is bought, and which tiles each box spot may move to.
## Both are functions of the rooms, doors, windows and props — none of which a seed
## touches — so they are derived once from a scratch build and then reused for every
## seed of a sweep.
static var _slot_open := PackedByteArray()
static var _box_moves: Array = []


static func reset_layout() -> void:
	DOORS = _deep(DOORS_FIXED)
	WALLBUYS = _deep(WALLBUYS_FIXED)
	PERKSPOTS = _deep(PERKSPOTS_FIXED)
	BOXSPOTS = BOXSPOTS_FIXED.duplicate()


## `duplicate(true)` on the const itself hands back a deep copy whose nested Arrays
## are still the read-only ones the compiler made — a wall buy's `tile` would be
## immutable inside a mutable row. Rebuilt key by key instead.
static func _deep(src: Array) -> Array:
	var out: Array = []
	for row: Dictionary in src:
		var d := {}
		for k: String in row.keys():
			var v: Variant = row[k]
			if typeof(v) == TYPE_ARRAY:
				var a: Array = v
				d[k] = a.duplicate(true)
			else:
				d[k] = v
		out.append(d)
	return out


## Rolls one run's layout. Returns false if every attempt was rejected and the
## canonical layout was shipped instead, which is a thing the assertions look at.
static func roll_layout(rng: RandomNumberGenerator) -> bool:
	reset_layout()
	_derive_layout_cache()

	# Perks first, and unconditionally: any permutation of the six machines over the
	# six alcoves is playable, because a perk you cannot reach yet is a perk you save
	# up for. Juggernog behind two doors is the hardest arrangement and it is also the
	# most interesting one, so it is deliberately not rejected. Measured over the 48
	# swept seeds it lands 0 purchases deep 11 times, 1 deep 20 and 2 deep 17 —
	# `checks/mapgen.gd` prints that histogram and asserts only that it contains no
	# unreachable spot.
	var keys: Array = []
	for ps: Dictionary in PERKSPOTS:
		keys.append(ps.k)
	_shuffle(rng, keys)
	for i in PERKSPOTS.size():
		PERKSPOTS[i].k = keys[i]

	var accepted := false
	for _try in LAYOUT_TRIES:
		var guns: Array = []
		for wb: Dictionary in WALLBUYS_FIXED:
			guns.append({"gun": wb.gun, "cost": wb.cost})
		_shuffle(rng, guns)
		if not _early_gun_affordable(guns):
			continue
		for i in WALLBUYS.size():
			var g: Dictionary = guns[i]
			WALLBUYS[i].gun = g.gun
			WALLBUYS[i].cost = g.cost
		accepted = true
		break

	_roll_box_spots(rng)
	_roll_door_costs(rng)
	return accepted


## At least one weapon the player can walk to on foot, at a price round one can
## reach. `_slot_open` is the every-door-shut reachability of each slot's interact
## tile, which is the same point `interaction_system` puts its row at.
static func _early_gun_affordable(guns: Array) -> bool:
	for i in guns.size():
		if i >= _slot_open.size() or _slot_open[i] == 0:
			continue
		var g: Dictionary = guns[i]
		if int(g.cost) <= EARLY_GUN_MAX:
			return true
	return false


## Each door's price moves independently and then the whole table is rescaled back
## onto the canonical total, so a seed changes the ORDER you can afford to open the
## map in without changing how much map a given number of points buys. The residual
## from rounding each price to DOOR_COST_STEP is put on the most expensive door,
## which is where 50 points is the smallest relative lie.
static func _roll_door_costs(rng: RandomNumberGenerator) -> void:
	var n := DOORS_FIXED.size()
	if n == 0:
		return
	var base_total := 0
	var raw: Array[float] = []
	var raw_total := 0.0
	for d: Dictionary in DOORS_FIXED:
		base_total += int(d.cost)
		var f := 1.0 + rng.randf_range(-DOOR_COST_SPREAD, DOOR_COST_SPREAD)
		var r := float(d.cost) * f
		raw.append(r)
		raw_total += r
	var scale := float(base_total) / raw_total
	var total := 0
	var dearest := 0
	for i in n:
		var c := int(roundf(raw[i] * scale / float(DOOR_COST_STEP))) * DOOR_COST_STEP
		DOORS[i].cost = maxi(c, DOOR_COST_MIN)
		total += int(DOORS[i].cost)
		if int(DOORS[i].cost) > int(DOORS[dearest].cost):
			dearest = i
	DOORS[dearest].cost = maxi(int(DOORS[dearest].cost) + base_total - total, DOOR_COST_MIN)


static func _roll_box_spots(rng: RandomNumberGenerator) -> void:
	for i in BOXSPOTS.size():
		if i >= _box_moves.size():
			continue
		var moves: Array = _box_moves[i]
		if moves.is_empty():
			continue
		BOXSPOTS[i] = moves[rng.randi() % moves.size()]


## Fisher-Yates, drawing from the caller's stream. `randi() % (i + 1)` rather than
## `randi_range`, so the stream advances exactly once per swap however the engine
## implements the range form.
static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := int(rng.randi() % (i + 1))
		var t: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## The layout-invariant cache. Built from scratch maps with the canonical tables in
## place, which `roll_layout` guarantees by calling `reset_layout()` first.
static func _derive_layout_cache() -> void:
	if not _slot_open.is_empty():
		return
	var shut := MapData.new()
	shut.build()
	_slot_open.resize(WALLBUYS_FIXED.size())
	for i in WALLBUYS_FIXED.size():
		var wb: Dictionary = WALLBUYS_FIXED[i]
		var p := wallbuy_point(wb)
		_slot_open[i] = 1 if shut.reach[ix(int(p.x), int(p.y))] == 1 else 0

	var open_map := MapData.new()
	open_map.build()
	for di in DOORS_FIXED.size():
		open_map.open_door(di)
	_box_moves.clear()
	for i in BOXSPOTS_FIXED.size():
		_box_moves.append(_moves_for_spot(open_map, i))


## Where a wall buy's plaque is bought from: the tile in front of the wall, the same
## point `interaction_system` builds its row at (tile centre + face * 0.6).
static func wallbuy_point(wb: Dictionary) -> Vector2:
	var tile: Array = wb.tile
	var face: Array = wb.face
	return Vector2(float(tile[0]) + 0.5 + float(face[0]) * 0.6,
		float(tile[1]) + 0.5 + float(face[1]) * 0.6)


## Every tile a given box spot may be jittered onto: open, unstamped, reachable with
## the map fully bought, inside the same room, and clear of everything else that
## already stands somewhere. The canonical tile is in the list, so a jitter can
## legitimately roll "stay where you are".
static func _moves_for_spot(m: MapData, si: int) -> Array:
	var home: Vector2 = BOXSPOTS_FIXED[si]
	var room := _room_of(int(home.x), int(home.y))
	var out: Array = []
	for dy in range(-BOX_JITTER, BOX_JITTER + 1):
		for dx in range(-BOX_JITTER, BOX_JITTER + 1):
			var x := int(home.x) + dx
			var y := int(home.y) + dy
			if x < 0 or y < 0 or x >= MAPW or y >= MAPH:
				continue
			if _room_of(x, y) != room:
				continue
			var i := ix(x, y)
			if m.solid[i] == 1 or m.prop_solid[i] == 1 or m.reach[i] == 0:
				continue
			if _occupied(x, y, si):
				continue
			out.append(Vector2(x + 0.5, y + 0.5))
	if out.is_empty():
		out.append(home)
	return out


## Which room rectangle a tile sits in, or -1. Static twin of
## `world_builder._room_at`, which is an instance method on a node this file cannot
## see; the duplication is four lines and the alternative is a dependency from the
## data layer to the renderer.
static func _room_of(x: int, y: int) -> int:
	for r in ROOMS.size():
		var rm: Dictionary = ROOMS[r]
		if x >= rm.x0 and x <= rm.x1 and y >= rm.y0 and y <= rm.y1:
			return r
	return -1


## True if something other than box spot `si` already needs this tile or the ring
## around it. The ring is what stops a box being shoved up against a perk machine
## whose collider then swallows the approach to it.
static func _occupied(x: int, y: int, si: int) -> bool:
	if x == SPAWN_TILE.x and y == SPAWN_TILE.y:
		return true
	var here := Vector2(x + 0.5, y + 0.5)
	var claims: Array[Vector2] = [GENSPOT, PAPSPOT]
	for ps: Dictionary in PERKSPOTS_FIXED:
		claims.append(Vector2(ps.x, ps.y))
	for wb: Dictionary in WALLBUYS_FIXED:
		claims.append(wallbuy_point(wb))
	claims.append(Vector2(float(BOWIE.tile[0]) + 0.5 + float(BOWIE.face[0]) * 0.6,
		float(BOWIE.tile[1]) + 0.5 + float(BOWIE.face[1]) * 0.6))
	for w: Dictionary in WINDOWS:
		claims.append(Vector2(float(w.ix) + 0.5, float(w.iy) + 0.5))
	for di in DOORS_FIXED.size():
		var tiles: Array = DOORS_FIXED[di].tiles
		for t: Array in tiles:
			claims.append(Vector2(float(t[0]) + 0.5, float(t[1]) + 0.5))
	for i in BOXSPOTS_FIXED.size():
		if i != si:
			claims.append(BOXSPOTS_FIXED[i])
	for c: Vector2 in claims:
		if absf(c.x - here.x) <= 1.0 and absf(c.y - here.y) <= 1.0:
			return true
	return false


## A one-line fingerprint of the live layout, for the debug console and for a sweep
## that has to say which seed it was looking at.
static func layout_signature() -> String:
	var guns: Array[String] = []
	for wb: Dictionary in WALLBUYS:
		guns.append(String(wb.gun))
	var perks: Array[String] = []
	for ps: Dictionary in PERKSPOTS:
		perks.append(String(ps.k))
	var costs: Array[String] = []
	for d: Dictionary in DOORS:
		costs.append(str(int(d.cost)))
	return "guns=%s perks=%s doors=%s box=%s" % [
		"/".join(guns), "/".join(perks), "/".join(costs), str(BOXSPOTS)]
