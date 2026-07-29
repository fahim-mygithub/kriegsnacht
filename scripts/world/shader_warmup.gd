class_name ShaderWarmup
extends Node3D

## Forces every shader variant the game uses through one compile before play.
##
## WebGL 2.0 exposes no program-binary API, so Godot compiles the GLES3 program
## cache out entirely on web: every visitor, on every page load, recompiles every
## shader variant from GLSL source, on the main thread, mid-frame. There is no
## cache to warm and no thread to compile on — the only mitigation is the old
## one, which is to put every material in front of a camera for one frame while
## a loading screen is still up.
##
## This is a permanent maintenance job, not a one-off: every new material added
## later must appear here too, or it reintroduces a hitch at the moment it is
## first drawn — which for a muzzle flash is the first trigger pull.

## Far enough in front of the near plane to survive clipping, small enough to
## occupy almost no fill.
const DIST := 0.4
const SIZE := 0.012
const FRAMES := 3

var _frames := FRAMES
var _done := false

signal finished


## `extra` takes materials the world builder does not own — the additive muzzle
## quad, sprite materials, anything created later.
func warm(cam: Camera3D, materials: Array, extra: Array = []) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(SIZE, SIZE)

	var all: Array = []
	all.append_array(materials)
	all.append_array(extra)

	var n := 0
	for m in all:
		if m == null:
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Spread them across the view so none is fully occluded by another;
		# a fragment that never rasterises does not compile the fragment stage.
		mi.position = Vector3((n % 8) * SIZE * 1.4 - SIZE * 5.6,
			(n / 8) * SIZE * 1.4 - SIZE * 2.0, -DIST)
		cam.add_child(mi)
		add_child_ref(mi)
		n += 1

	# The sprite path is a different shader again — billboard, alpha scissor,
	# vertex colour — and is what every zombie in the game draws with.
	var spr := Sprite3D.new()
	spr.texture = load("res://assets/props/pu_ammo.png")
	spr.pixel_size = 0.0006
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.shaded = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.position = Vector3(0, -SIZE * 4.0, -DIST)
	cam.add_child(spr)
	add_child_ref(spr)

	# The chalk plaques are a second sprite variant: alpha-blended rather than
	# scissored, and not billboarded. Both of those are material features compiled
	# into the program under gl_compatibility, so this is a separate first-draw
	# hitch from the sprite above — and it would land the first time the player
	# rounds a corner onto a wall buy.
	var plaque := Sprite3D.new()
	plaque.texture = load("res://assets/props/chalk_mp40.png")
	plaque.pixel_size = 0.0006
	plaque.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	plaque.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	plaque.shaded = true
	plaque.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	plaque.position = Vector3(SIZE * 2.0, -SIZE * 4.0, -DIST)
	cam.add_child(plaque)
	add_child_ref(plaque)


var _spawned: Array[Node] = []


func add_child_ref(n: Node) -> void:
	_spawned.append(n)


func _process(_dt: float) -> void:
	if _done:
		return
	_frames -= 1
	if _frames > 0:
		return
	_done = true
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	finished.emit()
