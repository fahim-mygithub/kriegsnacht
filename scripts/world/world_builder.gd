class_name WorldBuilder
extends Node3D

## Turns the 42x34 grid into real 3D geometry.
##
## This is the part of the browser build that does NOT port: the software
## raycaster is gone entirely. What survives is the data it was reading — the
## same grid, the same per-tile texture assignment, the same metre scale.
##
## One surface is built per texture so the whole level is a handful of draw
## calls. Per-tile brightness jitter is baked into vertex colours, reproducing
## the `tileShade` table that stopped a 64px texture reading as wallpaper — and
## since Milestone 2 those same vertex colours also carry a static light bake:
## ambient occlusion from the surrounding tiles plus a fill term from the room's
## own lamp. See `_shade_at`. It costs nothing at runtime because it is bytes
## that were already in the vertex stream.

const TEX_DIR := "res://assets/textures/"

## preload rather than the class name: `lighting.gd` carries no `class_name`, and
## a freshly added script is not in the class registry until the editor rescans.
## Only `lamp_position` is used from it, and only at build time.
const LIGHTING := preload("res://scripts/world/lighting.gd")

## Same reason, and the same rule: `barricade.gd` is new, so it is reached by path
## and never by class name. One node per window, built below, and the only thing
## that ever writes a barricade's board count.
const BARRICADE := preload("res://scripts/world/barricade.gd")

var map: MapData
var _materials := {}
var _door_nodes := {}
var _barricades := {}
## The eight lamp positions, resolved once. `_fill_at` runs per vertex — about
## ten thousand times — and re-deriving a room rectangle inside that loop is the
## kind of cost that turns a build-time bake into a visible load stall.
var _lamp_pos: Array[Vector3] = []


func build(m: MapData) -> void:
	map = m
	# A `static` outlives `reload_current_scene()`, and a death reloads the scene —
	# so the registry has to be emptied by whatever fills it, here, rather than
	# trusted to be empty.
	BARRICADE.reset_registry()
	for r in MapData.ROOMS.size():
		_lamp_pos.append(LIGHTING.lamp_position(r))
	_build_static()
	_build_doors()
	_build_windows()
	# window1..window6 are no longer drawn by anything: the planks in those six
	# images are separate meshes now, so a barricade at any board count is
	# `window0` — the masonry surround and the opening — with `n` real boards in
	# front of it. The six PNGs stay in `assets/textures/` because they are what
	# `tools/gen/` produces from the ancestor's own drawing code, and deleting a
	# generator output to reflect a renderer decision would be the wrong direction.
	_material("window0")
	_material("plank")


## All materials the level owns, for the shader warm-up pass.
func materials() -> Array:
	return _materials.values()


func _material(tex_name: String) -> StandardMaterial3D:
	if _materials.has(tex_name):
		return _materials[tex_name]
	var mat := StandardMaterial3D.new()
	var path := TEX_DIR + tex_name + ".png"
	if ResourceLoader.exists(path):
		var t: Texture2D = load(path)
		mat.albedo_texture = t
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Every quad below is wound consistently (checked face by face: the
	# right-hand-rule normal points away from the side the surface faces, which
	# is front-facing under Godot's clockwise convention), so culling can stay
	# on. Leaving it disabled was rasterising all static geometry twice, which
	# on a fill-rate-bound WebGL2 target is the cheapest frame time in the file.
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	_night_sky(mat, tex_name)
	_metal_power(mat, tex_name)
	_barricade_plank(mat, tex_name)
	_materials[tex_name] = mat
	return mat


## The barricade planks are the one surface in the level with no texture behind
## them: a board is geometry now rather than pixels in `window6.png`, and there is
## no 64x64 tile of "plank" to sample. `ResourceLoader.exists` finds no
## `plank.png`, so `albedo_texture` stays null — which under gl_compatibility binds
## the engine's default white, the *same* shader as every textured wall and
## therefore not one extra variant to compile on a platform with no program cache.
## The hue has to arrive as the material's own albedo instead.
##
## `albedo_color` and not a vertex colour, because vertex colours are 8 bit and
## clamp at 1.0 while this uniform does not — see `barricade.PLANK_ALBEDO`, which
## is the ancestor's own plank fill at the top of its jitter range so that the
## per-plank variation can ride in the vertex stream underneath it.
func _barricade_plank(mat: StandardMaterial3D, tex_name: String) -> void:
	if tex_name != "plank":
		return
	var c: Color = BARRICADE.PLANK_ALBEDO
	mat.albedo_color = c


## The ancestor gave night ceilings their own light curve — flatter and hard
## capped at 150/256, `min(150, (0.26 + 0.34/(1+d*d*0.2))*256)` (1701), selected
## per tile at 1868 — so walking toward the Alley never brightened the sky. In
## Godot that whole statement is one flag: unshaded means the torch, the eight
## room lamps and the muzzle flash cannot reach the ceiling at all. Without it
## the Alley reads as an indoor room with a painted roof, because the torch
## visibly lights the stars.
func _night_sky(mat: StandardMaterial3D, tex_name: String) -> void:
	if tex_name != "night":
		return
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Unshaded leaves the per-tile shade jitter in the vertex colours with
	# nothing to hide it: it would read as a chequerboard of one-metre squares
	# across the sky. The ancestor never applied `tileShade` to a ceiling either
	# — its ceiling caster took the raw LUT value (1868).
	mat.vertex_color_use_as_albedo = false
	# 150/256 = 0.586 is the cap the curve never exceeded, so the stars land at
	# the same brightness they did in the ancestor. The blue is the `+9` the
	# night branch added where every other ceiling got `+5`; that was an additive
	# floor, and unshaded discards EMISSION, so it survives here only as a bias
	# in the multiplier. The curve's distance falloff (0.586 near to 0.26 far) is
	# left to the depth fog, which is already enabled and does the same job.
	mat.albedo_color = Color(0.586, 0.586, 0.66)


## `if(G.power && wid===TX_METAL) lit = min(400, lit + 26)` (1801). Additive, so
## metal the lamps barely reach lifts too — that is what makes the Generator Hall
## announce itself from the corridor once the power is on.
##
## Emission is the only additive channel a StandardMaterial3D has, and the
## feature flag is what selects the shader variant, so it is armed here at zero
## energy and left that way: there is no shader cache on the web, so enabling it
## at the moment the generator is thrown would compile mid-fight. Only the
## uniform moves. See set_power_on().
func _metal_power(mat: StandardMaterial3D, tex_name: String) -> void:
	if tex_name != "metal":
		return
	mat.emission_enabled = true
	# Roughly metal.png's own average, so the added light is the colour of the
	# plate rather than a white wash. The ancestor's `+26` scaled the texel, which
	# a flat emission colour can only approximate.
	mat.emission = Color(0.30, 0.30, 0.29)
	mat.emission_energy_multiplier = 0.0


## Two triangles from four corners, wound a-b-c / a-c-d.
##
## A plain Array literal, not PackedInt32Array([...]): a Packed constructor is a
## call, and a call is not a constant expression, so the Packed form is a parse
## error rather than a slower constant. The loop below types its own variable,
## which is what the Packed form was reaching for.
const QUAD_TRIS := [0, 1, 2, 0, 2, 3]


## One shade per corner rather than one per face — the whole of the light bake
## lives in those four numbers. `v_bot`/`v_top` exist because a wall is now split
## into three vertical bands and each band has to take its own slice of the
## texture rather than repeating the whole of it three times.
##
## Everything indexed here is a Packed array so the element type survives the
## subscript; an untyped `Array` would hand back Variants and the build would
## fail on the unsafe argument.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		sa: float, sb: float, sc: float, sd: float, v_bot := 1.0, v_top := 0.0) -> void:
	var col := PackedColorArray([
		Color(sa, sa, sa), Color(sb, sb, sb), Color(sc, sc, sc), Color(sd, sd, sd)])
	var uv := PackedVector2Array([
		Vector2(0.0, v_bot), Vector2(1.0, v_bot), Vector2(1.0, v_top), Vector2(0.0, v_top)])
	var v := PackedVector3Array([a, b, c, d])
	# Typed, because QUAD_TRIS is an untyped Array and an untyped index into a
	# Packed array is an unsafe subscript, which this project builds as an error.
	for k: int in QUAD_TRIS:
		st.set_normal(n)
		st.set_color(col[k])
		st.set_uv(uv[k])
		st.add_vertex(v[k])


# --- the static light bake ---------------------------------------------------

## How much a fully enclosed corner loses, and how much a wall loses where it
## meets the floor or the ceiling.
##
## Both invented. Nothing in the ancestor computed occlusion, because a raycaster
## that lights every texel from the camera has no geometry to occlude with — its
## only spatial light term is distance from the player. They are set so that the
## darkest vertex the level can produce (an enclosed corner, at the floor line,
## on a Z-facing wall, out of every lamp's reach: 0.58 x 0.70 x 0.727 x 0.60,
## times the tile jitter) lands near a fifth of the texel rather than at black —
## because this is albedo, not light, so a vertex at zero is a vertex the torch
## can never reach either.
const AO_CORNER := 0.42
const AO_CREASE := 0.30

## The height of the wall-to-floor and wall-to-ceiling shadow band, and therefore
## where the two extra vertex rows sit. Half a metre against a 2.8 m ceiling:
## wide enough to read as a gradient at this grid resolution, narrow enough not
## to read as a painted stripe. Invented.
const AO_BAND := 0.5

## What a surface gets with no lamp anywhere near it, as a fraction of what a
## surface directly under one gets. The curve is `1/(1 + d*d*0.05)`, which is the
## ancestor's own light falloff (`litLUT`, html:1698) — the shape it used for
## every lit surface in the game, borrowed here for the one light it never had.
const FILL_FLOOR := 0.76
const FILL_K := 0.05

## The four tiles meeting a grid corner, as offsets from it. Array literal rather
## than PackedInt32Array for the same reason as QUAD_TRIS above.
const CORNER_OFF := [-1, 0]


## The static bake, evaluated once per vertex at build time and multiplied into
## the vertex colour the materials already read as albedo. Zero runtime cost.
##
## Three terms: `base`, which is the per-tile jitter with `Z_FACE_SHADE` already
## folded in by the caller; an occlusion term from the solid tiles around the
## vertex; and a fill term from the room's own lamp. `Z_FACE_SHADE` composes
## rather than being replaced — it is a *facing* cue and this is a *position*
## cue, and a corridor needs both to read as a corridor.
func _shade_at(p: Vector3, base: float, room: int, wall: bool, H: float) -> float:
	return base * _ao_at(p, wall, H) * _fill_at(p, room)


func _ao_at(p: Vector3, wall: bool, H: float) -> float:
	var n := _corner_solids(int(roundf(p.x)), int(roundf(p.z)))
	var h: float
	if wall:
		# One of the four tiles meeting this corner is the wall's own and is
		# solid by definition, so it carries no information; and the tile across
		# the face is open, which is why the face exists at all. Two can occlude.
		h = 1.0 - AO_CORNER * (float(n - 1) / 2.0)
	else:
		# A floor or ceiling vertex sits on open ground, so at most three of the
		# four tiles around it can be solid.
		h = 1.0 - AO_CORNER * (float(n) / 3.0)

	# The crease is a wall term only. A floor is at the floor everywhere, so the
	# same test there would darken every floor in the level by a constant, which
	# is a change of exposure rather than a shadow.
	var v := 1.0
	if wall:
		var crease := maxf(1.0 - p.y / AO_BAND, 1.0 - (H - p.y) / AO_BAND)
		v = 1.0 - AO_CREASE * clampf(crease, 0.0, 1.0)
	return clampf(h, 0.0, 1.0) * v


## Solid tiles among the four that meet at grid corner (gx, gz). Off-map counts
## as solid: the border ring already is, and treating it as open would draw a
## bright seam right around the level.
func _corner_solids(gx: int, gz: int) -> int:
	var n := 0
	for oz: int in CORNER_OFF:
		for ox: int in CORNER_OFF:
			var tx := gx + ox
			var tz := gz + oz
			if tx < 0 or tz < 0 or tx >= MapData.MAPW or tz >= MapData.MAPH:
				n += 1
			elif map.solid[MapData.ix(tx, tz)] == 1:
				n += 1
	return n


## Corridors, doorways and openings belong to no room and get the floor value —
## which is also what a room's far corner converges to, so a doorway has no step
## in it. Distance is 3D, so the ceiling immediately around a lamp bakes bright
## and the floor four metres away does not.
func _fill_at(p: Vector3, room: int) -> float:
	if room < 0:
		return FILL_FLOOR
	var d2 := p.distance_squared_to(_lamp_pos[room])
	return FILL_FLOOR + (1.0 - FILL_FLOOR) / (1.0 + d2 * FILL_K)


## Which room a tile belongs to, or -1 for corridors, doorways and openings that
## sit outside every room rectangle.
func _room_at(x: int, y: int) -> int:
	for r in MapData.ROOMS.size():
		var rm: Dictionary = MapData.ROOMS[r]
		if x >= rm.x0 and x <= rm.x1 and y >= rm.y0 and y <= rm.y1:
			return r
	return -1


func _build_static() -> void:
	# Keyed "<room>|<texture>" rather than just "<texture>". Previously every
	# surface spanned the whole 42x34 grid, so each one intersected the AABB of
	# every lamp in the level — light pairing gates on AABB intersection first,
	# which meant every fragment on the map looped over all 8 omnis. It also left
	# zero headroom: the cap is 8 lights per instance and the level spawns
	# exactly 8, so a ninth (a muzzle flash, a perk glow) would silently evict a
	# room lamp with no warning. Per-room instances see 1-3 lights instead.
	var wall_st := {}
	var floor_st := {}
	var ceil_st := {}
	var collide := PackedVector3Array()

	var H := MapData.WALL_H

	for y in MapData.MAPH:
		for x in MapData.MAPW:
			var i := MapData.ix(x, y)
			var shade: float = map.tile_shade[i]

			if map.solid[i] == 1:
				# Door and window tiles get their own removable/updatable nodes.
				if map.door_at[i] >= 0 or map.win_at[i] >= 0:
					continue
				_emit_wall_faces(wall_st, x, y, shade, collide, H)
			else:
				var room := _room_at(x, y)
				var f0 := Vector3(x, 0, y)
				var f1 := Vector3(x + 1, 0, y)
				var f2 := Vector3(x + 1, 0, y + 1)
				var f3 := Vector3(x, 0, y + 1)
				var fkey := "%d|%s" % [room, MapData.FLOOR_TEX[map.ftex[i]]]
				if not floor_st.has(fkey):
					floor_st[fkey] = _new_st()
				_quad(floor_st[fkey], f0, f1, f2, f3, Vector3.UP,
					_shade_at(f0, shade, room, false, H),
					_shade_at(f1, shade, room, false, H),
					_shade_at(f2, shade, room, false, H),
					_shade_at(f3, shade, room, false, H))
				collide.append_array([f0, f1, f2, f0, f2, f3])

				var c0 := Vector3(x, H, y + 1)
				var c1 := Vector3(x + 1, H, y + 1)
				var c2 := Vector3(x + 1, H, y)
				var c3 := Vector3(x, H, y)
				var ckey := "%d|%s" % [room, MapData.CEIL_TEX[map.ctex[i]]]
				if not ceil_st.has(ckey):
					ceil_st[ckey] = _new_st()
				_quad(ceil_st[ckey], c0, c1, c2, c3, Vector3.DOWN,
					_shade_at(c0, shade, room, false, H),
					_shade_at(c1, shade, room, false, H),
					_shade_at(c2, shade, room, false, H),
					_shade_at(c3, shade, room, false, H))

				_emit_edge_walls(wall_st, x, y, shade, collide, H)

	_commit(wall_st, "Walls")
	_commit(floor_st, "Floors")
	_commit(ceil_st, "Ceilings")

	var body := StaticBody3D.new()
	body.name = "WorldCollision"
	body.collision_layer = 1
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collide)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


func _new_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


const WALL_DIRS := [
	{"d": Vector2i(1, 0), "n": Vector3(1, 0, 0)},
	{"d": Vector2i(-1, 0), "n": Vector3(-1, 0, 0)},
	{"d": Vector2i(0, 1), "n": Vector3(0, 0, 1)},
	{"d": Vector2i(0, -1), "n": Vector3(0, 0, -1)},
]

## Faces along Z are darkened, exactly as the raycaster did: `if(side===1) lit =
## (lit*186)>>8` (html:1799), where `side===1` is the DDA having stepped in map y
## (html:1773) and map y is world z here. With no shadows on this renderer it is
## the whole reason
## adjacent walls read as separate planes instead of meeting at one flat
## luminance — three characters of arithmetic for most of the depth cue.
const Z_FACE_SHADE := 186.0 / 256.0


## Geometry for the faces of one solid tile that border open space. `sink` is
## either a SurfaceTool (doors, windows — one mesh each) or a Dictionary keyed
## "<room>|<texture>" for the static world.
func _emit_wall_faces(sink, x: int, y: int, shade: float,
		collide: PackedVector3Array, H: float) -> void:
	# Where the two extra vertex rows sit. Hoisted out of the face loop because it
	# depends only on H, and this runs a couple of thousand times at load.
	var bands := PackedFloat32Array([0.0, AO_BAND, H - AO_BAND, H])
	for e in WALL_DIRS:
		# Lifted into typed locals rather than used as `e.d`/`e.n` in place: a
		# const Array hands its elements back as Variant, and handing a Variant to
		# `_quad`'s `n: Vector3` is an unsafe call argument the compiler is right
		# to object to. One annotation here fixes every use below.
		var dir: Vector2i = e.d
		var nrm: Vector3 = e.n
		var nx := x + dir.x
		var ny := y + dir.y
		if nx < 0 or ny < 0 or nx >= MapData.MAPW or ny >= MapData.MAPH:
			continue
		if map.solid[MapData.ix(nx, ny)] == 1:
			continue
		var a: Vector3
		var b: Vector3
		if dir == Vector2i(1, 0):
			a = Vector3(x + 1, 0, y); b = Vector3(x + 1, 0, y + 1)
		elif dir == Vector2i(-1, 0):
			a = Vector3(x, 0, y + 1); b = Vector3(x, 0, y)
		elif dir == Vector2i(0, 1):
			a = Vector3(x + 1, 0, y + 1); b = Vector3(x, 0, y + 1)
		else:
			a = Vector3(x, 0, y); b = Vector3(x + 1, 0, y)
		var c := b + Vector3(0, H, 0)
		var d := a + Vector3(0, H, 0)
		var face_shade := shade
		if dir.x == 0:
			face_shade *= Z_FACE_SHADE

		# A wall belongs to the room it faces, so both sides of a shared wall land
		# in their own room's batch — and take that room's lamp for the static fill.
		var room := _room_at(nx, ny)

		var st: SurfaceTool
		if sink is SurfaceTool:
			st = sink
		else:
			var key := "%d|%s" % [room, MapData.WALL_TEX[map.wtex[MapData.ix(x, y)]]]
			if not sink.has(key):
				sink[key] = _new_st()
			st = sink[key]

		# Three vertical bands rather than one quad. A per-vertex bake whose only
		# vertices are at the floor and the ceiling can express no gradient between
		# them — the whole face would carry a single crease value — so the dark
		# skirting where a wall meets the floor, which is the most recognisable
		# thing a baked light gives you, needs the two extra rows in order to exist
		# at all. Six triangles a face instead of two, on a level with a few hundred
		# exposed faces: invisible against a 65536-element budget, and not one extra
		# draw call, because the bands land in the surface the face was already in.
		for bi in 3:
			var y0: float = bands[bi]
			var y1: float = bands[bi + 1]
			var pa := a + Vector3(0.0, y0, 0.0)
			var pb := b + Vector3(0.0, y0, 0.0)
			var pc := b + Vector3(0.0, y1, 0.0)
			var pd := a + Vector3(0.0, y1, 0.0)
			# v runs 1 at the floor to 0 at the ceiling, so each band takes the slice
			# of the texture it actually covers instead of repeating the whole of it.
			_quad(st, pa, pb, pc, pd, nrm,
				_shade_at(pa, face_shade, room, true, H),
				_shade_at(pb, face_shade, room, true, H),
				_shade_at(pc, face_shade, room, true, H),
				_shade_at(pd, face_shade, room, true, H),
				1.0 - y0 / H, 1.0 - y1 / H)

		# Collision stays one full-height quad: the extra rows are a lighting
		# subdivision and a triangle soup gains nothing from them.
		collide.append_array([a, b, c, a, c, d])


## The wall at the edge of the grid, seen from the open tile inside it.
##
## `_emit_wall_faces` runs from the *solid* side of every boundary, so where the
## neighbour is off the map there is no tile to run it from and the world simply
## ends: no quad, no collider, and a view straight out into nothing. Until the
## exterior pockets existed no open tile touched the border, so this cost nothing
## and was never needed. It is needed now, because the pocket behind the window at
## (30,32) sits in the last row of the grid.
##
## The face is on the tile's `dir` edge but faces back into it, which is the
## geometry `_emit_wall_faces` emits for `-dir` translated one tile along `dir` —
## wound, like every quad in this file, so the right-hand-rule normal points away
## from the side the surface faces.
func _emit_edge_walls(sink: Dictionary, x: int, y: int, shade: float,
		collide: PackedVector3Array, H: float) -> void:
	var bands := PackedFloat32Array([0.0, AO_BAND, H - AO_BAND, H])
	for e in WALL_DIRS:
		var dir: Vector2i = e.d
		var nx := x + dir.x
		var ny := y + dir.y
		if nx >= 0 and ny >= 0 and nx < MapData.MAPW and ny < MapData.MAPH:
			continue
		var nrm := Vector3(-dir.x, 0, -dir.y)
		var a: Vector3
		var b: Vector3
		if dir == Vector2i(1, 0):
			a = Vector3(x + 1, 0, y + 1); b = Vector3(x + 1, 0, y)
		elif dir == Vector2i(-1, 0):
			a = Vector3(x, 0, y); b = Vector3(x, 0, y + 1)
		elif dir == Vector2i(0, 1):
			a = Vector3(x, 0, y + 1); b = Vector3(x + 1, 0, y + 1)
		else:
			a = Vector3(x + 1, 0, y); b = Vector3(x, 0, y)
		var face_shade := shade
		if dir.x == 0:
			face_shade *= Z_FACE_SHADE

		# The tile is its own room here — this face belongs to the open space it
		# closes off, not to a solid tile on the far side, because there is none.
		var room := _room_at(x, y)
		var key := "%d|%s" % [room, MapData.WALL_TEX[map.wtex[MapData.ix(x, y)]]]
		if not sink.has(key):
			sink[key] = _new_st()
		var st: SurfaceTool = sink[key]

		for bi in 3:
			var y0: float = bands[bi]
			var y1: float = bands[bi + 1]
			var pa := a + Vector3(0.0, y0, 0.0)
			var pb := b + Vector3(0.0, y0, 0.0)
			var pc := b + Vector3(0.0, y1, 0.0)
			var pd := a + Vector3(0.0, y1, 0.0)
			_quad(st, pa, pb, pc, pd, nrm,
				_shade_at(pa, face_shade, room, true, H),
				_shade_at(pb, face_shade, room, true, H),
				_shade_at(pc, face_shade, room, true, H),
				_shade_at(pd, face_shade, room, true, H),
				1.0 - y0 / H, 1.0 - y1 / H)

		# One full-height quad, exactly as `_emit_wall_faces` does: the three bands
		# above are a lighting subdivision and a triangle soup gains nothing from them.
		var c := b + Vector3(0, H, 0)
		var d := a + Vector3(0, H, 0)
		collide.append_array([a, b, c, a, c, d])


## Keys arriving as "<room>|<texture>" are split back out; anything else is used
## as both the node name and the texture name.
func _commit(dict: Dictionary, group_name: String) -> void:
	var root := Node3D.new()
	root.name = group_name
	add_child(root)
	for key in dict:
		var k := str(key)
		var tname := k
		var label := k
		if "|" in k:
			var parts := k.split("|")
			tname = parts[1]
			label = "R%s_%s" % [parts[0], parts[1]]
		var st: SurfaceTool = dict[key]
		var mesh := st.commit()
		var mi := MeshInstance3D.new()
		mi.name = label
		mi.mesh = mesh
		mi.material_override = _material(tname)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(mi)


## Doors are their own bodies so a purchase can simply delete them.
func _build_doors() -> void:
	var root := Node3D.new()
	root.name = "Doors"
	add_child(root)
	for di in MapData.DOORS.size():
		var holder := Node3D.new()
		holder.name = "Door%d" % di
		root.add_child(holder)
		var st := _new_st()
		var collide := PackedVector3Array()
		for t in MapData.DOORS[di].tiles:
			var i := MapData.ix(t[0], t[1])
			_emit_wall_faces(st, t[0], t[1], map.tile_shade[i], collide, MapData.WALL_H)
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _material(MapData.WALL_TEX[MapData.DOORS[di].tex])
		holder.add_child(mi)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(collide)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		holder.add_child(body)
		_door_nodes[di] = holder


func open_door(di: int) -> void:
	map.open_door(di)
	if _door_nodes.has(di):
		_door_nodes[di].queue_free()
		_door_nodes.erase(di)
	# The tiles are now open floor — patch in the floor and ceiling quads.
	var st_f := {}
	var st_c := {}
	var H := MapData.WALL_H
	for t in MapData.DOORS[di].tiles:
		var i := MapData.ix(t[0], t[1])
		var shade: float = map.tile_shade[i]
		var fname: String = MapData.FLOOR_TEX[map.ftex[i]]
		var cname: String = MapData.CEIL_TEX[map.ctex[i]]
		if not st_f.has(fname): st_f[fname] = _new_st()
		if not st_c.has(cname): st_c[cname] = _new_st()
		# A door tile sits between rooms and belongs to neither, so the bake gives
		# it the no-lamp floor value — which is what the tiles either side of it
		# converge to as well, so the patch does not read as a seam.
		var room := _room_at(t[0], t[1])
		var f0 := Vector3(t[0], 0, t[1])
		var f1 := Vector3(t[0] + 1, 0, t[1])
		var f2 := Vector3(t[0] + 1, 0, t[1] + 1)
		var f3 := Vector3(t[0], 0, t[1] + 1)
		_quad(st_f[fname], f0, f1, f2, f3, Vector3.UP,
			_shade_at(f0, shade, room, false, H),
			_shade_at(f1, shade, room, false, H),
			_shade_at(f2, shade, room, false, H),
			_shade_at(f3, shade, room, false, H))
		var c0 := Vector3(t[0], H, t[1] + 1)
		var c1 := Vector3(t[0] + 1, H, t[1] + 1)
		var c2 := Vector3(t[0] + 1, H, t[1])
		var c3 := Vector3(t[0], H, t[1])
		_quad(st_c[cname], c0, c1, c2, c3, Vector3.DOWN,
			_shade_at(c0, shade, room, false, H),
			_shade_at(c1, shade, room, false, H),
			_shade_at(c2, shade, room, false, H),
			_shade_at(c3, shade, room, false, H))
	_commit(st_f, "DoorFloor%d" % di)
	_commit(st_c, "DoorCeil%d" % di)


## Every barricade is its own node now — a masonry frame with a real hole through
## it and six separate plank meshes, all of which lives in `barricade.gd`.
##
## What was here before was one full-height quad over one full-height collider,
## swapping between seven pre-baked textures. The collider never moved with the
## picture, so a barricade stripped to zero boards was still a wall: you could not
## shoot through it, and there was nothing on the far side to shoot at.
func _build_windows() -> void:
	var root := Node3D.new()
	root.name = "Windows"
	add_child(root)
	for wi in MapData.WINDOWS.size():
		var w: Dictionary = MapData.WINDOWS[wi]
		var shade: float = map.tile_shade[MapData.ix(w.x, w.y)]
		# A barricade's two faces are the window tile's own exposed faces, so they
		# take the same Z-facing darkening every other wall face along z takes. The
		# opening's normal runs from the window tile to the room tile, so a window
		# whose two tiles share an x is a face along z. Applied here rather than in
		# `barricade.gd`, which deliberately names nothing in this file — see the
		# note at the top of it.
		if int(w.ix) == int(w.x):
			shade *= Z_FACE_SHADE
		var b := BARRICADE.new()
		b.name = "Window%d" % wi
		root.add_child(b)
		b.build(wi, map, self, shade)
		_barricades[wi] = b


## The one way anything outside `barricade.gd` changes a board count: the round
## director's between-round regrowth, the player's hold-F rebuild and the Carpenter
## power-up all come through here, and a zombie's own tear goes straight to the
## barricade. `map.window_boards` is written on the far side of this call, so the
## count the HUD prompt reads can never disagree with the planks on screen.
##
## `b` is deliberately untyped: `barricade.gd` carries no `class_name`, so a
## `Node3D`-typed local could not see `set_boards()` — the same reason `main.gd`
## leaves `lighting` and `hud` untyped.
func set_window_boards(wi: int, boards: int) -> void:
	if not _barricades.has(wi):
		# No node for this window (nothing builds one outside `build()`), so keep the
		# data grid consistent anyway rather than silently dropping the write.
		map.window_boards[wi] = clampi(boards, 0, BARRICADE.PLANK_COUNT)
		return
	var b = _barricades[wi]
	b.set_boards(boards)


## The ancestor's `+26` on its own 0-256 light scale.
const METAL_POWER_EMISSION := 26.0 / 256.0


## Hangs off the same event as the perk machines lighting up and the lamps coming
## to full.
##
## The metal ceilings of the Landing and the Generator Hall share this material —
## `MapData.WALL_TEX[3]` and `CEIL_TEX[3]` are both "metal" and `_material()` is
## keyed by texture name — so they brighten with the walls. The ancestor lifted
## walls only, but both surfaces are in the room the generator is in.
func set_power_on() -> void:
	var m: StandardMaterial3D = _materials.get("metal")
	if m != null:
		m.emission_energy_multiplier = METAL_POWER_EMISSION
