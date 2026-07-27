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

const DOORS := [
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

const WALLBUYS := [
	{"gun": "olympia", "tile": [15, 5], "face": [-1, 0], "cost": 500},
	{"gun": "m14", "tile": [12, 14], "face": [0, -1], "cost": 500},
	{"gun": "mp40", "tile": [22, 11], "face": [1, 0], "cost": 1000},
	{"gun": "stakeout", "tile": [39, 10], "face": [-1, 0], "cost": 1200},
	{"gun": "pm63", "tile": [15, 20], "face": [-1, 0], "cost": 1000},
	{"gun": "ak74u", "tile": [2, 24], "face": [1, 0], "cost": 1400},
	{"gun": "m16", "tile": [22, 26], "face": [1, 0], "cost": 1200},
]

const BOWIE := {"tile": [22, 5], "face": [1, 0], "cost": 3000}

const PERKSPOTS := [
	{"k": "revive", "x": 4.5, "y": 12.5},
	{"k": "dtap", "x": 37.5, "y": 4.5},
	{"k": "speed", "x": 4.5, "y": 19.5},
	{"k": "jug", "x": 24.5, "y": 20.5},
]

const BOXSPOTS := [Vector2(31.5, 12.5), Vector2(10.5, 25.5), Vector2(31.5, 26.5), Vector2(11.5, 11.5)]
const GENSPOT := Vector2(38.4, 30.5)
const PAPSPOT := Vector2(36.5, 22.5)
const SPAWN_TILE := Vector2i(8, 8)

# --- runtime grids -----------------------------------------------------------

var solid := PackedByteArray()
var wtex := PackedByteArray()
var ftex := PackedByteArray()
var ctex := PackedByteArray()
var door_at := PackedInt32Array()
var win_at := PackedInt32Array()
var reach := PackedByteArray()
## Fixed per-tile brightness jitter so a 64px texture stops reading as wallpaper.
var tile_shade := PackedFloat32Array()

## Mutable per-window state: boards remaining.
var window_boards := PackedInt32Array()
var door_open := PackedByteArray()


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
	for wi in WINDOWS.size():
		var w: Dictionary = WINDOWS[wi]
		var i := ix(w.x, w.y)
		solid[i] = 1
		wtex[i] = TX_WINDOW
		win_at[i] = wi

	compute_reach()


func _carve(x: int, y: int, f: int, c: int) -> void:
	var i := ix(x, y)
	solid[i] = 0
	ftex[i] = f
	ctex[i] = c


## Where a zombie stands to work a window's boards. In the browser build this
## had to sit on the *room* side of the wall plane or the depth buffer swallowed
## the sprite. In real 3D that is no longer a constraint, but keeping it means
## the attackers line up with the opening exactly as they did before.
func window_stand_pos(wi: int) -> Vector2:
	var w: Dictionary = WINDOWS[wi]
	return Vector2(
		w.ix + 0.5 + (w.x - w.ix) * 0.33,
		w.iy + 0.5 + (w.y - w.iy) * 0.33
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
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + d.x
			var ny := y + d.y
			if nx < 0 or ny < 0 or nx >= MAPW or ny >= MAPH:
				continue
			var ni := ix(nx, ny)
			if reach[ni] == 1:
				continue
			# Windows count as reachable edges — that is how zombies get in.
			if solid[ni] == 1 and win_at[ni] < 0:
				continue
			reach[ni] = 1
			if solid[ni] == 0:
				q.append(ni)


func open_door(di: int) -> void:
	if door_open[di] == 1:
		return
	door_open[di] = 1
	for t in DOORS[di].tiles:
		var i := ix(t[0], t[1])
		solid[i] = 0
	compute_reach()


func is_blocked(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= MAPW or y >= MAPH:
		return true
	return solid[ix(x, y)] == 1


func live_windows() -> Array[int]:
	var out: Array[int] = []
	for wi in WINDOWS.size():
		var w: Dictionary = WINDOWS[wi]
		if reach[ix(w.ix, w.iy)] == 1:
			out.append(wi)
	return out
