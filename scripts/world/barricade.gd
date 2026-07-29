extends Node3D

## One window barricade: a masonry frame with a real hole through it, six separate
## planks nailed across that hole, and the state a zombie works against.
##
## **What this replaces.** A window used to be a single full-height quad that
## swapped between seven pre-baked textures (window0..window6) over a single
## full-height collider. The collider never changed with the picture, so a
## barricade stripped to zero boards was still a solid wall — you could not shoot
## through it, you could not see through it, and there was nothing on the far side
## to see. "Working the boards" was a number the round director decremented at the
## instant a zombie spawned, with the zombie already standing inside the room.
##
## **The geometry is read off the ancestor's own barricade texture**
## (kriegsnacht.html:802-831), which is the authority for where masonry ends and
## the opening begins: 6 px jambs, a 4 px head and a 10 px sill on a 64 px cell
## (html:812-813), and six planks at `ys = [8,18,28,38,46,54]` (html:816), each
## 68x9 px, drawn at `translate(s/2, y+4)` with a small alternating tilt. Those
## pixels become metres
## here, so the frame lines up with `window0.png` — the boardless state — exactly.
## That is why the frame can go on sampling that texture while the planks leave it
## and become geometry: the two halves of the drawing were always separable, and
## the six intermediate textures simply stop being used.
##
## **Board order is the ancestor's.** `T.window[boards]` draws planks `0..boards-1`
## (html:817), so the *last* plank — `ys[5]`, the lowest — is the first to come
## off. Six pre-built meshes, one per surviving count, and swapping `mesh` is a
## pointer assignment: no SurfaceTool allocation on a plank tear, and one draw call
## for all six planks rather than six.

#
# This script carries no `class_name`: it is new, and a new script is not in the
# class registry until the editor rescans, which a headless run never does. Both
# references to it are preloads — `world_builder.gd` builds these, `zombie.gd`
# finds them.
#
# And it names `WorldBuilder` nowhere, in either direction, even though the world
# builder is what constructs it and hands it its shading. `world_builder.gd`
# preloads this file, so a type annotation or a `WorldBuilder.SOME_CONST` here
# would close a resolution cycle between the two — and a cyclic *constant* is the
# case GDScript is least reliable about. The cost of avoiding it is one untyped
# member and six integers of winding order copied below; the cost of getting it
# wrong is a parse error, which makes Godot hang rather than report.

## Boards on a full barricade.
const PLANK_COUNT := 6

## Two triangles from four corners, wound a-b-c / a-c-d. The same order and the
## same reason as `world_builder.QUAD_TRIS` — a plain Array literal rather than a
## `PackedInt32Array(...)`, because a Packed constructor is a call and a call is not
## a constant expression. Copied rather than referenced; see the note above.
const QUAD_TRIS := [0, 1, 2, 0, 2, 3]


# --- the registry -------------------------------------------------------------

## Window index -> the node that owns it.
##
## A zombie is handed a window index by the round director and nothing else: it
## holds no reference to the world builder, and a scene path is worth nothing after
## `reload_current_scene()` has rebuilt the level. `WorldBuilder.build()` is the one
## place a set of barricades is ever made, and it clears this first — which is what
## keeps a static from outliving the scene that filled it.
static var _registry := {}


static func reset_registry() -> void:
	_registry.clear()


## The barricade for a window, or null if none was built — which is the case in any
## harness that runs the game logic without a world.
##
## The lookup lands in an `Object` first and is only narrowed after
## `is_instance_valid`. Assigning a *freed* object straight into a `Node3D`-typed
## local is itself an error at runtime — the assignment has to read the instance's
## class to check it — so the obvious `var n: Node3D = _registry.get(wi)` would
## fail on exactly the case the validity test exists to survive.
static func of(wi: int) -> Node3D:
	if not _registry.has(wi):
		return null
	var n: Object = _registry[wi]
	if not is_instance_valid(n):
		return null
	return n as Node3D


# --- the frame, in the ancestor's own texture pixels --------------------------

## `tex()` bakes every wall texture at `TEXW = 64` (html:577-578), so one texture
## pixel is 1/64 of a tile across and 1/64 of `MapData.WALL_H` up.
const TEX_CELL := 64.0

## `g.fillRect(0,0,6,s)` and `g.fillRect(s-6,0,6,s)` — the two jambs, `#4A4740`
## (html:812); `g.fillRect(0,0,s,4)` — the head; `g.fillRect(0,s-10,s,10)` — the
## sill, both `#3C3933` (html:813). Everything inside those four bands is the
## opening the ancestor filled with night sky and stars (html:807-810), and it is
## exactly the hole cut here.
const JAMB_PX := 6.0
const HEAD_PX := 4.0
const SILL_PX := 10.0

## Texture v runs 1 at the floor and 0 at the ceiling, matching the convention
## `world_builder._quad` established for every other wall in the level.
const APERTURE_U0 := JAMB_PX / TEX_CELL
const APERTURE_U1 := 1.0 - JAMB_PX / TEX_CELL
const APERTURE_TOP := MapData.WALL_H * (1.0 - HEAD_PX / TEX_CELL)
const APERTURE_BOT := MapData.WALL_H * (SILL_PX / TEX_CELL)


# --- the planks ---------------------------------------------------------------

## `const ys=[8,18,28,38,46,54]` (html:816), then `g.translate(s/2, y+4)`
## (html:819) and `g.fillRect(-34,-4.5,68,9)` (html:822). So each plank is centred
## four pixels below its row, is 68 px wide — wider than the 64 px cell, which is
## why a board overlaps the masonry it is nailed to — and 9 px tall.
const PLANK_ROW := [8.0, 18.0, 28.0, 38.0, 46.0, 54.0]
const PLANK_CENTRE_PAD := 4.0
const PLANK_HALF_W_PX := 34.0
const PLANK_HALF_H_PX := 4.5

## `const tilt=(b%2?1:-1)*sr(.07,.02)` (html:818). The sign alternates by plank
## parity, which is the ancestor's; the magnitudes are a deterministic spread
## across its exact 0.02-0.07 rad range, because the specific draws live inside the
## texture generator's seeded PRNG and are not recoverable from the PNG. Invented
## within a sourced interval.
const PLANK_TILT := [-0.02, 0.03, -0.04, 0.05, -0.06, 0.07]

## `const v=sr(26,-12)` feeding `rgb(126+v, 90+v*.7, 48+v*.5)` (html:820-821) — the
## per-plank colour jitter. Same treatment as the tilt: the range is the ancestor's,
## the six values are a deterministic scatter across it.
const PLANK_V := [4.0, -9.0, 18.0, -2.0, 24.0, 9.0]
const PLANK_V_TOP := 26.0
const PLANK_BASE_R := 126.0
const PLANK_BASE_G := 90.0
const PLANK_BASE_B := 48.0

## The plank material's albedo: the ancestor's fill at the *top* of its own jitter
## range, `v = 26`. The top rather than the middle because the per-plank draw then
## rides in the vertex colours as a multiplier at or below 1.0 — vertex colours are
## 8 bit and cannot carry a value over it, the same constraint `zombie.gd` records
## for the eye tints. Read by `world_builder._barricade_plank`.
const PLANK_ALBEDO := Color(
	(PLANK_BASE_R + PLANK_V_TOP) / 255.0,
	(PLANK_BASE_G + PLANK_V_TOP * 0.7) / 255.0,
	(PLANK_BASE_B + PLANK_V_TOP * 0.5) / 255.0)

## Invented: the ancestor's planks were painted into a 64x64 texture and had no
## thickness at all. Five centimetres is a board, and it is what makes the ends
## catch the torch when you stand beside a window instead of reading as a decal.
##
## The slab is centred on the room-side wall plane, so half of it stands proud into
## the room and half sits inside the reveal. Proud, because that is where a board
## nailed over a window is; centred rather than fully proud, because the two
## centimetres behind the plane are what stop the plank ends from hovering in front
## of the jamb masonry they are supposed to be fixed to.
const PLANK_THICK := 0.05

## Height of the tear cue. `spawnParticles(w.x+0.5, w.y+0.5, 1.2, 6, SPLINT)`
## (html:2277) — the ancestor threw its splinters from the centre of the window
## tile at 1.2 m, so that is where the sound comes from too.
const BOARD_CUE_HEIGHT := 1.2


# --- workers ------------------------------------------------------------------

## How many zombies a barricade is *shaped* for. Two abreast is what a one-metre
## opening holds, and it is the figure the gap analysis's per-window pacing item
## carries. Nothing here refuses a third — the round director's window pick is what
## spreads the horde (see the wiring note in this package's report) — but a third
## shares a standing slot rather than getting one of its own.
const MAX_WORKERS := 2

## Lateral gap between the two standing slots, along the wall. The pocket is one
## metre square and a zombie capsule is 0.52 m across, so this is most of the room
## there is: enough that two bodies read as two, not enough to put either of them
## in the masonry.
const SLOT_SPREAD := 0.44


# --- the vault ----------------------------------------------------------------

## Apex of the traversal, measured at the body origin — the zombie's feet. The sill
## is 0.4375 m, so this clears it by about 18 cm, which is a clamber rather than a
## hop.
##
## Invented. The ancestor did not traverse at all: it set `z.x = w.ix+0.5;
## z.y = w.iy+0.5` and changed state in the same statement (html:2272).
const VAULT_LIFT := 0.62

## How far the apex control point reaches along the direction of travel. Larger
## flattens the top of the arc; this is set so the curve is still climbing as it
## crosses the wall plane.
const VAULT_HANDLE := 0.35


# --- state --------------------------------------------------------------------

var wi := -1
var map: MapData
## Boards remaining, 0-6. `map.window_boards[wi]` is the copy the round director,
## the HUD prompt and the Carpenter power-up all read, and `set_boards` is the only
## thing that writes either — so they cannot drift apart.
var boards := PLANK_COUNT

## The world builder, untyped for the reason in the header. Four things are asked
## of it and every result is annotated at the call site, because a call on an
## untyped base comes back Variant: `_material`, `_room_at`, `_shade_at` and
## `_fill_at`.
var _wb
var _centre := Vector3.ZERO       # centre of the window tile, at floor level
var _inward := Vector3.ZERO       # unit, window tile -> the room
var _uaxis := Vector3.ZERO        # unit, along the wall face, for the room side
var _stand := Vector3.ZERO        # centre of the exterior standing area
var _base := 1.0                  # per-tile shade jitter, Z-face darkening folded in
var _room_in := -1                # the room the barricade opens into, or -1
var _room_out := -1               # the pocket's room, which is always -1

var _planks: MeshInstance3D
var _plank_meshes: Array[ArrayMesh] = []
var _plank_shapes: Array[CollisionShape3D] = []

## Live workers per standing slot. A count rather than a flag because nothing stops
## a third zombie arriving; the slot it shares is then the least crowded one.
var _slot_count := PackedInt32Array()

var _vault: Curve3D
var _vault_len := 0.0


# --- build --------------------------------------------------------------------

## `base_shade` is the window tile's own brightness jitter with the wall's Z-facing
## darkening already folded in. Computed by the caller rather than here, because
## `Z_FACE_SHADE` and the reason for it live in `world_builder.gd` and reading a
## constant back out of it would be the cyclic reference the header rules out.
func build(p_wi: int, p_map: MapData, wb, base_shade: float) -> void:
	wi = p_wi
	map = p_map
	_wb = wb
	_base = base_shade
	_registry[wi] = self

	var w: Dictionary = MapData.WINDOWS[wi]
	var tx: int = w.x
	var ty: int = w.y
	var iw: int = w.ix
	var ih: int = w.iy

	_centre = Vector3(float(tx) + 0.5, 0.0, float(ty) + 0.5)
	_inward = Vector3(float(iw - tx), 0.0, float(ih - ty))
	# The face's own left-to-right axis. Derived rather than picked: winding here
	# has to match every other quad in the level, where the right-hand-rule normal
	# points *away* from the side the surface faces. `u x UP == -normal` is that
	# convention solved for u, and it reproduces `world_builder.WALL_DIRS`'s a/b
	# endpoints exactly for all four directions.
	_uaxis = Vector3(-_inward.z, 0.0, _inward.x)

	var stand := map.window_stand_pos(wi)
	_stand = Vector3(stand.x, 0.0, stand.y)

	_slot_count.resize(MAX_WORKERS)

	# A wall belongs to the room it faces, exactly as `_emit_wall_faces` decides it,
	# so each side of the frame takes its own side's lamp for the static fill. The
	# pocket belongs to no room and gets the no-lamp floor value, which is correct:
	# there is no light out there.
	var room_in: int = _wb._room_at(iw, ih)
	var pocket := map.window_pocket(wi)
	var room_out: int = _wb._room_at(pocket.x, pocket.y)
	_room_in = room_in
	_room_out = room_out

	_build_frame()
	_build_planks()
	_build_vault(iw, ih)
	set_boards(map.window_boards[wi])


## The masonry: four border quads on each face, plus the four surfaces of the hole
## itself. The reveal exists because the wall is a metre thick and the hole now goes
## all the way through it — without those four quads you see the opening's edges as
## zero-thickness slivers from any angle off the perpendicular.
func _build_frame() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	_frame_face(st, _inward, _room_in)
	_frame_face(st, -_inward, _room_out)
	_reveal(st, _room_in)

	var mi := MeshInstance3D.new()
	mi.name = "Frame"
	mi.mesh = st.commit()
	# window0 is the boardless state of the very texture the frame's UVs are cut
	# from, so the surround lands pixel for pixel where the ancestor drew it. The
	# aperture region of that image is simply never sampled now — it is a hole.
	var frame_mat: StandardMaterial3D = _wb._material("window0")
	mi.material_override = frame_mat
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "FrameBody"
	# Layer 1 is the world layer the hitscan and both character bodies test against,
	# so the masonry stops rounds and stops feet exactly as the old full-height quad
	# did — and the aperture, which is simply absent from this list, does not.
	body.collision_layer = 1
	# Four solid boxes rather than a triangle shell of the same faces. A box is a
	# volume, so a body pressed into the sill cannot end up inside the wall the way
	# it can with a one-sided soup, and the sill is 0.44 m of vertical face with no
	# step-up behind it — which is what keeps the player out of a stripped window.
	body.add_child(_frame_box(0.0, 1.0, 0.0, APERTURE_BOT))                     # sill
	body.add_child(_frame_box(0.0, 1.0, APERTURE_TOP, MapData.WALL_H))          # head
	body.add_child(_frame_box(0.0, APERTURE_U0, APERTURE_BOT, APERTURE_TOP))    # jamb
	body.add_child(_frame_box(APERTURE_U1, 1.0, APERTURE_BOT, APERTURE_TOP))    # jamb
	add_child(body)


## One face of the surround: head, sill and two jambs, each taking its own rect of
## window0.png rather than repeating the whole image.
func _frame_face(st: SurfaceTool, face: Vector3, room: int) -> void:
	var u_ax := Vector3(-face.z, 0.0, face.x)
	var plane := _centre + face * 0.5
	_face_rect(st, plane, u_ax, face, room, 0.0, 1.0, APERTURE_TOP, MapData.WALL_H)
	_face_rect(st, plane, u_ax, face, room, 0.0, 1.0, 0.0, APERTURE_BOT)
	_face_rect(st, plane, u_ax, face, room, 0.0, APERTURE_U0, APERTURE_BOT, APERTURE_TOP)
	_face_rect(st, plane, u_ax, face, room, APERTURE_U1, 1.0, APERTURE_BOT, APERTURE_TOP)


## A sub-rect of a wall face. `u` runs 0-1 along the face and doubles as the
## texture's own horizontal coordinate, which is what makes the masonry line up:
## the whole-face convention every other wall uses is u 0 at endpoint a and u 1 at
## endpoint b, so a sub-rect of the geometry is the same sub-rect of the image.
func _face_rect(st: SurfaceTool, plane: Vector3, u_ax: Vector3, n: Vector3,
		room: int, u0: float, u1: float, y0: float, y1: float) -> void:
	var lo := plane + u_ax * (u0 - 0.5)
	var hi := plane + u_ax * (u1 - 0.5)
	var p := PackedVector3Array([
		lo + Vector3(0.0, y0, 0.0), hi + Vector3(0.0, y0, 0.0),
		hi + Vector3(0.0, y1, 0.0), lo + Vector3(0.0, y1, 0.0)])
	var v0 := 1.0 - y0 / MapData.WALL_H
	var v1 := 1.0 - y1 / MapData.WALL_H
	var uv := PackedVector2Array([
		Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
	_emit(st, p, uv, n, room)


## The four inside surfaces of the hole, spanning the tile's full one-metre depth.
## All four sample the jamb strip, which is the flat `#4A4740` the ancestor used for
## cut stone — so the reveal reads as the same masonry seen edge on.
func _reveal(st: SurfaceTool, room: int) -> void:
	var jamb_v0 := 1.0 - APERTURE_BOT / MapData.WALL_H
	var jamb_v1 := 1.0 - APERTURE_TOP / MapData.WALL_H

	# Sill top, facing up. Ordered so the right-hand-rule normal comes out pointing
	# down, which is this project's convention for a surface that faces up.
	var s0 := _hole_point(APERTURE_U0, APERTURE_BOT, 0.5)
	var s1 := _hole_point(APERTURE_U1, APERTURE_BOT, 0.5)
	var s2 := _hole_point(APERTURE_U1, APERTURE_BOT, -0.5)
	var s3 := _hole_point(APERTURE_U0, APERTURE_BOT, -0.5)
	_emit(st, PackedVector3Array([s0, s1, s2, s3]), PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(APERTURE_U0, 1.0),
		Vector2(APERTURE_U0, jamb_v0), Vector2(0.0, jamb_v0)]),
		Vector3.UP, room)

	# Head underside, facing down — the same four corners in the opposite order.
	var h0 := _hole_point(APERTURE_U0, APERTURE_TOP, -0.5)
	var h1 := _hole_point(APERTURE_U1, APERTURE_TOP, -0.5)
	var h2 := _hole_point(APERTURE_U1, APERTURE_TOP, 0.5)
	var h3 := _hole_point(APERTURE_U0, APERTURE_TOP, 0.5)
	_emit(st, PackedVector3Array([h0, h1, h2, h3]), PackedVector2Array([
		Vector2(0.0, jamb_v1), Vector2(APERTURE_U0, jamb_v1),
		Vector2(APERTURE_U0, 0.0), Vector2(0.0, 0.0)]),
		Vector3.DOWN, room)

	# The two jamb returns. `din x UP` is `_uaxis`, so the winding that faces one of
	# them into the hole is the depth order reversed for the other.
	_reveal_side(st, room, APERTURE_U0, 0.5, -0.5, _uaxis, jamb_v0, jamb_v1)
	_reveal_side(st, room, APERTURE_U1, -0.5, 0.5, -_uaxis, jamb_v0, jamb_v1)


func _reveal_side(st: SurfaceTool, room: int, u: float, s0: float, s1: float,
		n: Vector3, v0: float, v1: float) -> void:
	var p := PackedVector3Array([
		_hole_point(u, APERTURE_BOT, s0), _hole_point(u, APERTURE_BOT, s1),
		_hole_point(u, APERTURE_TOP, s1), _hole_point(u, APERTURE_TOP, s0)])
	var uv := PackedVector2Array([
		Vector2(0.0, v0), Vector2(APERTURE_U0, v0),
		Vector2(APERTURE_U0, v1), Vector2(0.0, v1)])
	_emit(st, p, uv, n, room)


## A point inside the window tile: `u` across the face, `y` up, `s` from -0.5 at the
## exterior face to +0.5 at the room face.
func _hole_point(u: float, y: float, s: float) -> Vector3:
	return _centre + _uaxis * (u - 0.5) + Vector3(0.0, y, 0.0) + _inward * s


## Two triangles, wound a-b-c / a-c-d, taking the same static light bake every other
## surface in the level takes — per-tile jitter, ambient occlusion from the
## surrounding solid tiles, and the room lamp's fill. Reusing `world_builder`'s own
## `_shade_at` rather than re-deriving it is deliberate: two copies of that formula
## in two files look equally plausible and disagree in the dark.
func _emit(st: SurfaceTool, p: PackedVector3Array, uv: PackedVector2Array,
		n: Vector3, room: int) -> void:
	for k: int in QUAD_TRIS:
		st.set_normal(n)
		var s: float = _wb._shade_at(p[k], _base, room, true, MapData.WALL_H)
		st.set_color(Color(s, s, s))
		st.set_uv(uv[k])
		st.add_vertex(p[k])


## One solid block of masonry, sized in the window's own frame: `u` along the wall,
## `y` up, and the full tile depth through it.
func _frame_box(u0: float, u1: float, y0: float, y1: float) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = _uaxis.abs() * (u1 - u0) + Vector3(0.0, y1 - y0, 0.0) + _inward.abs()
	var cs := CollisionShape3D.new()
	cs.shape = box
	cs.position = _centre + _uaxis * ((u0 + u1) * 0.5 - 0.5) \
		+ Vector3(0.0, (y0 + y1) * 0.5, 0.0)
	return cs


# --- planks -------------------------------------------------------------------

## Six meshes, one per surviving board count, and six collision shapes toggled
## individually. Pre-built because the alternative is a `SurfaceTool.commit()` per
## plank torn — an allocation inside a per-zombie timer — and because one mesh swap
## keeps all six planks in a single draw call.
func _build_planks() -> void:
	for k in PLANK_COUNT:
		# A fresh tool per mesh rather than committing a growing one. `commit()` is
		# documented to return a mesh, not to say what it leaves behind, and 294
		# small boxes across the whole level is load-time work nobody will measure —
		# guessing at that contract to save it would be the wrong trade.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in k + 1:
			_plank_box(st, i)
		_plank_meshes.append(st.commit())

	_planks = MeshInstance3D.new()
	_planks.name = "Planks"
	_planks.mesh = _plank_meshes[PLANK_COUNT - 1]
	var plank_mat: StandardMaterial3D = _wb._material("plank")
	_planks.material_override = plank_mat
	_planks.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(_planks)

	var body := StaticBody3D.new()
	body.name = "PlankBody"
	body.collision_layer = 1
	for i in PLANK_COUNT:
		var cs := _plank_shape(i)
		body.add_child(cs)
		_plank_shapes.append(cs)
	add_child(body)


## Local axes of plank `i`: along the board, across it, and through it. The tilt is
## a rotation about the wall's own normal, which is the only axis the ancestor's
## `g.rotate(tilt)` could have meant — it was rotating the 2D canvas the wall face
## is drawn on.
##
## **This basis is LEFT-handed and the winding below depends on it.** `_uaxis` is
## `_inward` turned so that `_uaxis x UP == -_inward` — that is the same identity
## that makes `_uaxis` reproduce `world_builder.WALL_DIRS`'s a/b endpoints, and it
## is why `x cross y == -z` here. `_plank_box` passes each face the two tangents
## whose cross product then comes out *opposite* the face normal, which is this
## project's winding convention. Flip either the basis or the tangent order and
## every board turns inside out — invisible under `CULL_BACK`, with no error.
## `_plank_shape` is the one place that must not inherit the handedness; see there.
func _plank_basis(i: int) -> Basis:
	var tilt: float = PLANK_TILT[i]
	var rot := Basis(_inward, tilt)
	return Basis(rot * _uaxis, rot * Vector3.UP, _inward)


func _plank_centre(i: int) -> Vector3:
	var row: float = PLANK_ROW[i]
	var y := MapData.WALL_H * (1.0 - (row + PLANK_CENTRE_PAD) / TEX_CELL)
	# On the room-side wall plane, so the slab straddles it.
	return _centre + _inward * 0.5 + Vector3(0.0, y, 0.0)


func _plank_half() -> Vector3:
	return Vector3(
		PLANK_HALF_W_PX / TEX_CELL,
		MapData.WALL_H * PLANK_HALF_H_PX / TEX_CELL,
		PLANK_THICK * 0.5)


## One board as six quads. Flat-shaded across the whole board rather than per
## vertex: a plank is 0.39 m tall, and the wall bake's only gradient over that span
## is the floor crease, which no board is long enough to show.
##
## The nail heads and the dark bottom stripe the ancestor painted into each plank
## (html:823-826) do not survive, because a board is geometry now and there is no
## 64 px tile of "plank" to sample. That is the trade the aperture is worth: two
## pixels of highlight against a barricade you can actually shoot through.
func _plank_box(st: SurfaceTool, i: int) -> void:
	var b := _plank_basis(i)
	var c := _plank_centre(i)
	var h := _plank_half()
	var ux := b.x * h.x
	var uy := b.y * h.y
	var uz := b.z * h.z

	# `v` is the ancestor's per-plank colour draw, folded into the vertex stream as
	# a multiplier against PLANK_ALBEDO — which is that same expression at the top
	# of its range, so this is always at or below 1.0.
	var v: float = PLANK_V[i]
	var s := _base * (PLANK_BASE_R + v) / (PLANK_BASE_R + PLANK_V_TOP)
	# The room's own lamp fill. A plank hangs in the opening rather than on a tile
	# face, so there is no meaningful occlusion term for it — only the distance
	# falloff every other surface in that room takes.
	var fill: float = _wb._fill_at(c, _room_in)
	s *= fill
	var col := Color(s, s, s)

	# Six faces, each given the two tangents whose cross product comes out opposite
	# the face's own normal — the winding convention the whole level is built on —
	# and its own centre, which is the board's centre pushed out by that half extent.
	_plank_face(st, col, c + uz, ux, uy, b.z)
	_plank_face(st, col, c - uz, uy, ux, -b.z)
	_plank_face(st, col, c + ux, uy, uz, b.x)
	_plank_face(st, col, c - ux, uz, uy, -b.x)
	_plank_face(st, col, c + uy, uz, ux, b.y)
	_plank_face(st, col, c - uy, ux, uz, -b.y)


func _plank_face(st: SurfaceTool, col: Color, o: Vector3, t1: Vector3, t2: Vector3,
		n: Vector3) -> void:
	var p := PackedVector3Array([o - t1 - t2, o + t1 - t2, o + t1 + t2, o - t1 + t2])
	var uv := PackedVector2Array([
		Vector2(0.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.0), Vector2(0.0, 0.0)])
	for k: int in QUAD_TRIS:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv(uv[k])
		st.add_vertex(p[k])


func _plank_shape(i: int) -> CollisionShape3D:
	var box := BoxShape3D.new()
	var h := _plank_half()
	box.size = h * 2.0
	var cs := CollisionShape3D.new()
	cs.shape = box
	# The third column is negated on the way in, and only here.
	#
	# `_plank_basis` is left-handed by construction (see its note) — determinant
	# -1, which `Basis.get_scale()` reports as a scale of (-1,-1,-1). This project
	# runs Jolt (`project.godot`, `3d/physics_engine="Jolt Physics"`), and Jolt
	# rejects a mirrored shape transform outright: it cannot decompose one, so it
	# logs and falls back, and the fallback orientation is not the one the mesh was
	# built with. The symptom would be 84 errors at load and planks whose colliders
	# do not sit where the boards are drawn — a barricade you can see and shoot
	# through in different places.
	#
	# A box is symmetric about its own centre, so negating one axis describes the
	# identical volume with determinant +1. The mesh keeps the left-handed basis
	# because its winding is derived from it.
	var b := _plank_basis(i)
	cs.transform = Transform3D(Basis(b.x, b.y, -b.z), _plank_centre(i))
	return cs


# --- board state --------------------------------------------------------------

## The single writer for a barricade's board count, in every direction: a zombie
## tearing one off, the player's hold-F rebuild, the Carpenter power-up and the
## between-round regrowth all arrive here.
func set_boards(n: int) -> void:
	boards = clampi(n, 0, PLANK_COUNT)
	map.window_boards[wi] = boards
	if _planks != null:
		_planks.visible = boards > 0
		if boards > 0:
			_planks.mesh = _plank_meshes[boards - 1]
	for i in _plank_shapes.size():
		# Set directly rather than deferred. A tear happens inside a zombie's
		# `_physics_process`, and the one frame a deferred write would cost is a
		# frame in which a board you can see is gone but still stops a bullet.
		_plank_shapes[i].disabled = i >= boards


## Tear one plank off, if there is one. Guarded rather than asserted: two zombies
## working the same window can both reach zero on the same physics tick, and the
## second one asking for a seventh board is normal, not a bug.
func take_board() -> void:
	if boards <= 0:
		return
	set_boards(boards - 1)


# --- workers ------------------------------------------------------------------

## Take a standing slot outside this window. Always succeeds: refusing here would
## leave the round director holding a zombie with nowhere to put it, and the honest
## answer to a third arrival is that it crowds in rather than that it vanishes.
func claim() -> int:
	var best := 0
	for i in MAX_WORKERS:
		if _slot_count[i] < _slot_count[best]:
			best = i
	_slot_count[best] += 1
	map.window_workers[wi] += 1
	return best


func release(slot: int) -> void:
	if slot >= 0 and slot < MAX_WORKERS:
		_slot_count[slot] = maxi(0, _slot_count[slot] - 1)
	map.window_workers[wi] = maxi(0, map.window_workers[wi] - 1)


## Where a worker in `slot` stands, spread along the wall so two bodies at one
## window read as two.
func stand_point(slot: int) -> Vector3:
	var s := clampi(slot, 0, MAX_WORKERS - 1)
	var off := (float(s) - float(MAX_WORKERS - 1) * 0.5) * SLOT_SPREAD
	return _stand + _uaxis * off


## Centre of the window tile at splinter height — where the tear cue is heard from.
func cue_point() -> Vector3:
	return Vector3(_centre.x, BOARD_CUE_HEIGHT, _centre.z)


# --- the vault ----------------------------------------------------------------

## The traversal path: outside, up over the sill, down onto the room tile.
##
## A `Curve3D` sampled by hand rather than a `Tween` driving one. Pause in this
## project is a game state that every `_physics_process` early-returns on, not
## `get_tree().paused` — a Tween runs off the scene tree and would keep hauling a
## zombie through a window while the pause screen was up.
func _build_vault(iw: int, ih: int) -> void:
	var from := stand_point(0)
	var to := Vector3(float(iw) + 0.5, 0.0, float(ih) + 0.5)
	var dir := to - from
	dir.y = 0.0
	dir = dir.normalized()
	_vault = Curve3D.new()
	_vault.add_point(from)
	_vault.add_point(Vector3(_centre.x, VAULT_LIFT, _centre.z),
		-dir * VAULT_HANDLE, dir * VAULT_HANDLE)
	_vault.add_point(to)
	# Forced at build time. `sample_baked` bakes lazily, so the first zombie through
	# any window would otherwise pay for the bake mid-round.
	_vault_len = _vault.get_baked_length()


## Position along the traversal, `t` from 0 to 1.
func vault_sample(t: float) -> Vector3:
	return _vault.sample_baked(clampf(t, 0.0, 1.0) * _vault_len)


## Where the curve starts, so a zombie standing in the other slot can blend off its
## own position instead of snapping to this one.
##
## `get_point_position(0)` rather than `sample_baked(0.0)`: this is read once per
## vaulting body per physics tick, and the baked form is a binary search over the
## baked point array for a value that is a stored field. Same answer — the first
## baked point *is* the first control point — at no cost.
func vault_start() -> Vector3:
	return _vault.get_point_position(0)
