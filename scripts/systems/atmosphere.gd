extends Node3D

## Everything the level *wears*: the muzzle flash, and every billboard prop the
## browser build drew as a sprite — the machines, the chalk plaques, the perk
## markers, the mystery box's own art.
##
## Split out of main.gd, which was the composition root and this layer both. The
## seam is that a system which needs a prop asks for one here rather than growing
## its own loader: the pixel scales, the billboard policy and the alpha cut are one
## table in one file, so a new prop cannot quietly arrive at a different scale.
##
## A Node3D at the origin under main, so every sprite's `position` is still its
## world position — the arithmetic below is unchanged from when main.gd owned it.

## Props reuse the browser build's own art, exported to assets/props/ by
## replaying its canvas drawing code. They are billboards for the same reason
## the zombies are: the original had no 3D geometry for them either.
const PROP_DIR := "res://assets/props/"
const PROP_PX := 0.025          # metres per source pixel
const POWERUP_PX := 0.018
## 1.7 m of drawn machine over 64 source px — html:2092. The generic PROP_PX
## would render it 1.60 m, which is the perk machines' scale, not this one's.
const PAP_PX := 0.0265625

## Chalk wall-buy plaques, drawn from each weapon's own GUNART parts.
##
## The plaque hangs on the wall face, not at the interact point: html:2035 puts
## both at tile centre + face * 0.52, which is 0.02 m proud of the wall plane —
## enough to clear it without reading as a floating panel. Height and lift are the
## ancestor's, from html:2105 `add(CHALK[b.gun], b.x, b.y, 0.72, 1.30)`: 0.72 m of
## plaque with its bottom edge 1.30 m off the floor, under a 2.8 m ceiling.
const CHALK_PX := 0.018         # 0.72 m over 40 source px
const CHALK_LIFT := 1.30        # floor to the plaque's bottom edge
const CHALK_PROUD := 0.52       # tile centre to the drawing plane

## The weapon hovering out of an open mystery box — the reel while it spins and
## the offer once it lands. Same plaque art as a wall buy, drawn smaller and
## lower: html:2099-2102 is `add(CHALK[...], bs.x, bs.y, 0.62, 1.15, {glow:true})`,
## i.e. 0.62 m of plaque with its bottom edge 1.15 m off the floor.
const BOX_SHOW_PX := 0.0155     # 0.62 m over the same 40 source px
const BOX_SHOW_LIFT := 1.15

## The Pack-a-Punch machine mid-cycle. A multiply on the sprite's albedo, NOT a
## light energy and not an sRGB conversion of one — constraint 7. It reads as the
## machine coming alive without adding a second light to the Generator Hall, which
## already carries the only shadow-casting light in the game.
const PAP_WORK_TINT := Color(1.5, 1.18, 0.7)

const MUZZLE_COLOR := {
	"raygun": Color(0.63, 1.0, 0.35),
	"thundergun": Color(0.59, 0.92, 1.0),
}

var _player: Player
## viewmodel.gd, for flash_anchor(). Untyped for the same reason main.gd's handle
## is: the script is attached at runtime, so the compiler only knows Node3D.
var _viewmodel: Node3D

var _muzzle_light: OmniLight3D
var _muzzle_quad: MeshInstance3D
var _muzzle_mat: StandardMaterial3D
var _muzzle_t := 0.0

var _perk_nodes := {}
var _gen_node: Sprite3D
var _pap_node: Sprite3D
var _box_show: Sprite3D
## What set_box_display() was last asked for, whether or not a plaque existed to
## draw it with. The box's own assertions read this, so a missing texture is
## visible as a gap rather than as silence.
var _box_show_gun := ""


func bind(p: Player, vm: Node3D) -> void:
	_player = p
	_viewmodel = vm
	_setup_muzzle()
	# main.gd used to own this connection, which made it the first listener on
	# `fired`; it is the last one now. Nothing observable moved: neither of the
	# other two listeners draws from an Rng stream (fx.gd is forbidden to, by its
	# own header) and neither writes anything `flash_anchor()` reads — the
	# viewmodel's transform only moves in its own `_process`.
	p.fired.connect(_on_fired)


## One persistent light and one persistent quad, toggled by a timer. Allocating
## a flash per shot would mean fifteen node allocations a second at 880 RPM.
func _setup_muzzle() -> void:
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.84, 0.51)
	_muzzle_light.light_energy = 4.0
	_muzzle_light.omni_range = 2.6
	# Shadowless keeps it free: OMNI_LIGHT_COUNT is a uniform, not a shader
	# define, so toggling this cannot trigger a mid-fight shader recompile.
	_muzzle_light.shadow_enabled = false
	_muzzle_light.visible = false
	add_child(_muzzle_light)

	_muzzle_mat = StandardMaterial3D.new()
	_muzzle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_muzzle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_muzzle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_muzzle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_muzzle_mat.albedo_color = Color(1.0, 0.86, 0.55)
	_muzzle_mat.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	_muzzle_quad = MeshInstance3D.new()
	_muzzle_quad.mesh = quad
	_muzzle_quad.material_override = _muzzle_mat
	_muzzle_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle_quad.visible = false
	add_child(_muzzle_quad)


func _on_fired(at: Vector3) -> void:
	var key: String = _player.current_gun().key
	var col: Color = MUZZLE_COLOR.get(key, Color(1.0, 0.84, 0.51))
	# The weapon is drawn through a narrowed projection (viewmodel.gd), so a flash
	# placed on the same ray as the barrel does NOT land on the barrel on screen —
	# the viewmodel's screen offset is the world's scaled by
	# tan(74/2)/tan(55/2) = 1.4476. And a 0.34 m quad at the barrel's actual 0.18 m
	# would subtend more than the whole frame. flash_anchor() is the point that
	# satisfies both: same screen position, survivable distance.
	var flash_at: Vector3 = _viewmodel.flash_anchor(
		at.distance_to(_player.camera().global_position))
	_muzzle_light.light_color = col
	_muzzle_light.omni_range = 5.7 if key == "thundergun" else 2.6
	_muzzle_light.global_position = flash_at
	_muzzle_light.visible = true
	_muzzle_mat.albedo_color = col
	_muzzle_quad.global_position = flash_at
	_muzzle_quad.rotation.z = Rng.randf(Rng.VISUAL) * TAU
	_muzzle_quad.visible = true
	_muzzle_t = 0.05


## The flash is the only thing in this file with a clock, and it is the reason
## this node processes at all. Pausable like the rest of the world: a 50 ms flash
## frozen behind the pause overlay is the same frozen frame everything else is.
func _process(dt: float) -> void:
	if _muzzle_t <= 0.0:
		return
	_muzzle_t -= dt
	if _muzzle_t <= 0.0:
		_muzzle_light.visible = false
		_muzzle_quad.visible = false


## The one material this file owns, for the warm-up pass. Same shape as
## fx.materials(), lighting.materials() and world.materials(), so main.gd can hand
## the pass every material in the game without knowing where any of them came from.
func materials() -> Array:
	return [_muzzle_mat]


# --- props -------------------------------------------------------------------

func _sprite(tex: String, px: float, pos: Vector2, sprite_name: String) -> Sprite3D:
	var s := Sprite3D.new()
	s.name = sprite_name
	s.texture = load(PROP_DIR + tex + ".png")
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.alpha_scissor_threshold = 0.35
	# Sprite origin is its centre, so lift it half its own height off the floor.
	s.position = Vector3(pos.x, s.texture.get_height() * px * 0.5, pos.y)
	add_child(s)
	return s


## A floor-standing machine at the shared prop scale — the mystery box.
func prop_sprite(tex: String, pos: Vector2, sprite_name: String) -> Sprite3D:
	return _sprite(tex, PROP_PX, pos, sprite_name)


## A dropped power-up. Its own scale, and the only prop that is a full billboard:
## drops hover and glow so they read across a dark room.
func powerup_sprite(tex: String, pos: Vector2, sprite_name: String) -> Sprite3D:
	var s := _sprite(tex, POWERUP_PX, pos, sprite_name)
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return s


func spawn_chalk(gun: String, tile: Array, face: Array) -> void:
	var s := Sprite3D.new()
	s.name = "Chalk_" + gun
	s.texture = load(PROP_DIR + "chalk_" + gun + ".png")
	s.pixel_size = CHALK_PX
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = true
	# Not a billboard: it is painted on a specific wall, and turning to face the
	# player would break the illusion the moment you walked past it.
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# The plaque's own ground is rgba(12,14,11,.74) across all 52x40 px
	# (html:1247), so every pixel clears a 0.35 scissor and ALPHA_CUT_DISCARD would
	# render it as an opaque slab. Blend it, so the wall reads through at 26% the
	# way the raycaster composited it.
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	var px: float = float(tile[0]) + 0.5 + float(face[0]) * CHALK_PROUD
	var pz: float = float(tile[1]) + 0.5 + float(face[1]) * CHALK_PROUD
	s.position = Vector3(px, CHALK_LIFT + s.texture.get_height() * CHALK_PX * 0.5, pz)
	# A Sprite3D's quad normal is local +Z, and rotating by this angle sends +Z to
	# (face[0], 0, face[1]) — out of the wall, into the room.
	s.rotation.y = atan2(float(face[0]), float(face[1]))
	add_child(s)


func spawn_perk_marker(ps: Dictionary) -> void:
	_perk_nodes[ps.k] = _sprite("perk_%s_off" % ps.k, PROP_PX,
		Vector2(ps.x, ps.y), "Perk_" + ps.k)


func spawn_generator() -> void:
	_gen_node = _sprite("gen_off", PROP_PX, MapData.GENSPOT, "Generator")


## The machine had no art at all until Milestone 2, and the reason turns out to be
## an extraction bug rather than an art decision: makePaP is at html:1986-2012,
## seven hundred lines outside the range the original export pass replayed.
func spawn_pap() -> void:
	_pap_node = _sprite("pap_off", PAP_PX, MapData.PAPSPOT, "PackAPunch")


## The reel, and the weapon the box holds out at the end of it.
##
## One persistent sprite whose texture is swapped, for the same reason the muzzle
## flash is one persistent light: a spin swaps the displayed weapon up to fifteen
## times in 2.9 s (html:2823), and a node per swap is fifteen allocations for one
## animation. Pass an empty key to put it away.
func set_box_display(gun: String, pos: Vector2) -> void:
	_box_show_gun = gun
	if gun.is_empty():
		if _box_show != null and is_instance_valid(_box_show):
			_box_show.visible = false
		return
	# tools/gen emits a plaque per WALL BUY and one for the Bowie (targets.js:119-131);
	# the ancestor also emits one per BOX_POOL entry it has not already covered
	# (html:3436). Until that gap is closed, four of the eleven box weapons have no
	# plaque — and `load()` on a missing path is an error spew *per swap*, fifteen
	# times a spin, rather than one blank frame.
	var path := PROP_DIR + "chalk_" + gun + ".png"
	if not ResourceLoader.exists(path):
		if _box_show != null and is_instance_valid(_box_show):
			_box_show.visible = false
		return
	if _box_show == null or not is_instance_valid(_box_show):
		_box_show = Sprite3D.new()
		_box_show.name = "BoxDisplay"
		_box_show.pixel_size = BOX_SHOW_PX
		_box_show.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_box_show.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		# Unshaded, unlike every other prop here. It hovers in the air out of the
		# lid with no surface to catch the torch, and the ancestor draws it with
		# `{glow:true}`. Unshaded is what reproduces "readable across a dark room"
		# without pushing an albedo past 1.0 and calling it emission — constraint 7.
		_box_show.shaded = false
		_box_show.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		add_child(_box_show)
	_box_show.texture = load(path)
	_box_show.position = Vector3(pos.x,
		BOX_SHOW_LIFT + _box_show.texture.get_height() * BOX_SHOW_PX * 0.5, pos.y)
	_box_show.visible = true


## The Pack-a-Punch mid-cycle, 0 at rest and 1 working.
##
## `light_perks()` owns this node's TEXTURE and this owns its MODULATE, so the
## power ceremony and the machine's own clock are never two writers of one value.
func pap_glow(amount: float) -> void:
	if _pap_node == null or not is_instance_valid(_pap_node):
		return
	_pap_node.modulate = Color.WHITE.lerp(PAP_WORK_TINT, clampf(amount, 0.0, 1.0))


## The machines only light up once the generator is thrown.
func light_perks() -> void:
	for k in _perk_nodes:
		var s: Sprite3D = _perk_nodes[k]
		if is_instance_valid(s):
			s.texture = load(PROP_DIR + "perk_%s_on.png" % k)
	if _gen_node and is_instance_valid(_gen_node):
		_gen_node.texture = load(PROP_DIR + "gen_on.png")
	# The machine is gated on power in the ancestor too — html:2092 tests G.power.
	if _pap_node and is_instance_valid(_pap_node):
		_pap_node.texture = load(PROP_DIR + "pap_on.png")
