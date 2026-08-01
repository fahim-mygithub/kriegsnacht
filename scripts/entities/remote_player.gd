extends Node3D

## Another player's body, as seen from this client.
##
## NOT a `Player`. It is a view and nothing else: it holds no input, no weapon, no
## health and no collider, because the machine that owns this player is simulating
## all of that on the other end of the relay
## (notes/design/2026-07-31-coop-topology-decision.md). Everything here is driven
## from one call — `apply()` — made by scripts/net/session_runtime.gd and by nothing
## else, which is the one-writer rule applied to a node nobody local controls.
##
## THREE THINGS `player.gd::_ready` BUILDS THAT THIS DELIBERATELY DOES NOT:
##
##   * **A `Camera3D`.** `Camera3D` makes itself `current` when it enters the tree,
##     and the last one in wins. Four players in a room would mean four cameras and
##     the local player would be looking out of somebody else's head — a black
##     screen, or worse, a moving one. There is no camera under here at all, so the
##     failure cannot happen rather than being guarded against.
##   * **A viewmodel.** `viewmodel.gd::bind()` parents itself under the camera and
##     builds every weapon mesh in the game. There is no camera to parent to, and a
##     first-person arm rig is by construction not visible from outside the head it
##     belongs to.
##   * **A SHADOW-CASTING torch.** `player.gd:308-333` records that the torch is the
##     one shadow-casting light in the project and why: on `gl_compatibility` each
##     shadowed light re-draws every instance it touches. The co-op decision note
##     lists "four shadow-casting torches" as a deferred cost with no cheap out and
##     settles it — remote avatars get `shadow_enabled = false`. See `_build_torch`
##     for what that costs and what is done about it.
##
## THE BODY IS A BILLBOARD, DRAWN THE WAY THE ENEMIES ARE. `zombie.gd:424-435` is
## the template: an `AnimatedSprite3D` on `BILLBOARD_FIXED_Y`, nearest filter,
## `ALPHA_CUT_DISCARD` at the same 0.35 scissor, shaded so the torches light it, and
## a five-row bearing atlas indexed through `SpriteLib.view_for()` so a teammate
## walking away from you shows you their back. There is no survivor art in
## `assets/sprites/`, so the atlas is GENERATED — see `_sheet()`.

## The one line-of-sight-free thing this file shares with the enemies: the bearing
## table and the animation naming. Using `SpriteLib` rather than a private copy is
## what stops a remote body and a zombie disagreeing about which way "row 2" faces.
## preload rather than the class name is unnecessary here — `SpriteLib` carries a
## `class_name` and has since Milestone 1 — but the const keeps the dependency in
## one place.
const SPRITES := preload("res://scripts/world/sprite_lib.gd")

## Metres. The player's own capsule is 1.7 m tall with its eye at
## `MapData.EYE` = 1.55; 1.80 is the drawn figure including the head above the eye,
## which puts a teammate a hair under the 1.82 m walker — deliberately, so the two
## read as the same scale of creature and a silhouette in the dark is told apart by
## its shape and not by its size.
const HEIGHT := 1.80

## The cell, matching the walker's 48x64 (`SpriteLib.SPEC.zombie`) so a survivor and
## a zombie are cut from the same grid and the same `pixel_size` arithmetic.
const CELL_W := 48
const CELL_H := 64
const WALK_FRAMES := 4

## Authored rate of the generated walk cycle, and the divisor in `anim_scale_for`.
## Same shape as `Zombie.WALK_FPS`, and the same reason: a `speed_scale` means
## nothing without the rate it scales.
const WALK_FPS := 8.0

## Frames of walk cycle per metre travelled — `Zombie.ANIM_FRAMES_PER_METRE`, which
## is the ancestor's own `z.anim += dt*spd*2.6` (kriegsnacht.html:2340). Reused
## rather than re-tuned: a teammate jogging beside a zombie at the same speed should
## take the same number of strides, and two different constants is how that stops
## being true.
const ANIM_FRAMES_PER_METRE := 2.6

## `zombie.gd:301`. One number, used by the sprite's discard and by nothing else
## here — but it has to be the enemies' number, because the two families are lit by
## the same torches and a different scissor reads as a different amount of body.
const ALPHA_SCISSOR := 0.35

## THE FOUR, IN THE REFERENCE'S OWN ORDER. Black Ops' Kino der Toten crew is
## Dempsey, Nikolai, Takeo, Richtofen, and the thing that tells them apart across a
## dark room is the colour of the coat. This is that, reduced to one tint per
## player slot: olive drab, a red-brown greatcoat, dark indigo, and Richtofen's pale
## lab coat. Authored in DISPLAY space (constraint 6) because these bytes go into an
## albedo texture, which the renderer decodes with the sRGB EOTF exactly as it does
## for the zombie PNGs on disk — converting here would decode them twice.
const CREW := [
	Color8(94, 99, 64),
	Color8(122, 62, 49),
	Color8(57, 67, 106),
	Color8(151, 151, 143),
]

## Everything that is not the coat. Display space, for the reason above.
const SKIN := Color8(214, 168, 132)
const SKIN_DARK := Color8(158, 116, 88)
const HAIR := Color8(58, 54, 48)
const EYE_DARK := Color8(28, 24, 22)
const TROUSER := Color8(84, 79, 69)
## The far leg. A stride seen from the side crosses, and two rectangles of one
## colour that cross are one rectangle — the near/far split is what makes the walk
## legible at the bearing where it moves most.
const TROUSER_DARK := Color8(50, 47, 41)
const BOOT := Color8(38, 34, 30)
const GUN := Color8(50, 48, 45)
const GUN_HL := Color8(101, 96, 89)
const PACK := Color8(63, 55, 44)
## `outlineSprite()` stamped a 1 px dark rim on every enemy cell so a silhouette
## reads against a dark wall (see sprite_lib.gd's header). A survivor drawn without
## one would be the only body in the game that dissolves into the background.
const OUTLINE := Color8(15, 13, 11)

## The torch, and the whole of the departure from `player.gd`'s.
##
## `shadow_enabled = false` is settled by the design note, so an unshadowed spot is
## what there is. Two consequences, and both are bought off here rather than left
## for someone to find:
##
##  1. **It reads dimmer at the same energy.** `player.gd:310-321` records that a
##     shadowed light blends in sRGB rather than linear, "which reads brighter,
##     hence the energy coming down from 3.2" — 3.4 to 3.1. Unshadowed, the same
##     3.1 would read lower than the local torch. Matching would mean going back up.
##  2. **It leaks through walls.** With no shadow map there is nothing to occlude
##     the cone, so a teammate two rooms away paints light on your side of a wall.
##     That is not a tuning problem, it is what the flag means.
##
## (2) beats (1), so this goes DOWN rather than up: a shorter, dimmer, tighter cone
## bounds how far the leak can reach and how bright it can be when it gets there,
## at the cost of a teammate's beam being visibly weaker than your own. That is a
## decision and not a measurement — there is no co-op frame-gate scenario to measure
## it against yet, and this file says so rather than implying a number was taken.
const TORCH_ENERGY := 2.4
const TORCH_RANGE := 11.0
const TORCH_ANGLE := 30.0
const TORCH_ATTEN := 1.25

## How far above the head the name floats. Above `HEIGHT` so it never sits inside
## the body it labels.
const TAG_HEIGHT := 2.06

## The name tag is drawn THROUGH geometry, deliberately. It is the one thing here
## that is not a simulation of a body: a teammate you cannot find is a teammate you
## cannot cover, and BO1 shows the other three players' names through the level for
## exactly that reason. The body itself is depth-tested normally.
const TAG_PIXEL := 0.0045
const TAG_FONT := 64

## Sunk this far into the floor while downed, which with the walk cycle stopped is
## the whole of the downed pose. There is no crawl art and inventing one belongs to
## whichever package lands co-op revives; a body at ankle height with a red tag is
## unambiguous and costs nothing.
const DOWN_SINK := 1.16

var _sprite: AnimatedSprite3D
var _tag: Label3D
var _head: Node3D
var _torch: SpotLight3D

var _tint := 0
var _view := 0
var _flip := false
var _facing := Vector2(0.0, 1.0)
var _downed := false

## Where the beam is being asked to point, and how fast it gets there.
##
## Pitch is the one field that is NOT interpolated on the buffer:
## `replication.gd::sample_at` returns position, yaw and speed, and pitch is held
## at whatever the newest `me` carried. At 12 Hz a held value is a beam that jumps
## in eleven-degree steps every 83 ms, which on the brightest moving thing in a
## dark room is the most visible artefact the avatar has. So it is eased locally
## instead — this is a smoother on a display value, not interpolation of
## authoritative state, and it is deliberately in the view rather than in the
## replication layer for that reason.
##
## The rate is a per-second exponential: at 14 the beam covers 90% of a step in
## 165 ms, which is under two sends and above the frequency a head actually moves.
const PITCH_RATE := 14.0
var _pitch_target := 0.0


## `tint` is the player's slot in `Net.players()` order, which is host-first and
## then stable by presence key (session.gd:166-180) — so everyone in the room
## assigns the same coat to the same person without a byte on the wire.
func setup(display_name: String, tint: int) -> void:
	_tint = posmod(tint, CREW.size())

	_sprite = AnimatedSprite3D.new()
	_sprite.name = "Body"
	_sprite.sprite_frames = frames_for(_tint)
	_sprite.pixel_size = HEIGHT / float(CELL_H)
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.shaded = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = ALPHA_SCISSOR
	# Sprite origin is its centre, so lift it half a body to stand on the floor —
	# zombie.gd:432-433, same line, same reason.
	_sprite.position.y = HEIGHT * 0.5
	_sprite.play(SPRITES.anim_name("walk", 0))
	add_child(_sprite)

	_tag = Label3D.new()
	_tag.name = "Tag"
	_tag.text = display_name
	_tag.font_size = TAG_FONT
	_tag.pixel_size = TAG_PIXEL
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	# DISCARD rather than a blended cut: a transparent surface with the depth test
	# off has nothing to sort against, and a discard makes the question moot.
	_tag.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	_tag.outline_size = 10
	_tag.outline_modulate = Color(0.02, 0.02, 0.03, 1.0)
	_tag.modulate = CREW[_tint]
	_tag.position.y = TAG_HEIGHT
	add_child(_tag)

	# Pitch lives on its own node for the same reason it does on the player: the
	# body's yaw is this node's and the beam's elevation is the head's, and one
	# writer each. Nothing here rotates the sprite — `BILLBOARD_FIXED_Y` overrides
	# the node's own basis, which is why the bearing has to come from `view_for`.
	_head = Node3D.new()
	_head.name = "Head"
	_head.position.y = MapData.EYE
	add_child(_head)
	_build_torch()


func _build_torch() -> void:
	_torch = SpotLight3D.new()
	_torch.name = "Torch"
	# THE LINE THIS FILE EXISTS TO GET RIGHT. See TORCH_ENERGY.
	_torch.shadow_enabled = false
	_torch.light_energy = TORCH_ENERGY
	_torch.light_color = Color(1.0, 0.94, 0.82)
	_torch.spot_range = TORCH_RANGE
	_torch.spot_angle = TORCH_ANGLE
	_torch.spot_attenuation = TORCH_ATTEN
	_head.add_child(_torch)


## The one entry point. Position and orientation are already interpolated by
## session_runtime.gd — this applies them and derives everything else, which is the
## split the design note asks for: derived state "is a pure function of what is
## already on the wire and must never be sent".
##
## `speed` is metres per second of horizontal movement, and it drives the cycle
## rate through the enemies' own frames-per-metre constant rather than through a
## boolean, so a sprinting teammate's legs move at sprint rate.
func apply(pos: Vector3, yaw: float, pitch: float, speed: float, downed: bool) -> void:
	global_position = pos + Vector3(0.0, -DOWN_SINK if downed else 0.0, 0.0)
	rotation.y = yaw
	_pitch_target = pitch
	# The heading the atlas row is picked from. `-Z` is forward for the player
	# (`player.gd::_hitscan` aims down `-basis.z`), and in the XZ plane a yaw of
	# zero therefore points at -Z.
	_facing = Vector2(-sin(yaw), -cos(yaw))
	if downed != _downed:
		_downed = downed
		if _tag != null:
			# The one piece of state the tag carries besides the name. Red is the
			# HUD's own downed colour language and needs no legend.
			_tag.modulate = Color(0.92, 0.24, 0.20) if downed else CREW[_tint]
	if _sprite != null:
		_sprite.speed_scale = 0.0 if downed else anim_scale_for(speed)
	_update_view()


## Metres per second to a multiplier on the strip's authored rate. Deliberately the
## same expression as `Zombie.anim_scale_for` (zombie.gd:487-488) — static and
## public for the same reason, so the relationship can be asserted without standing
## an avatar up in a scene tree.
static func anim_scale_for(spd: float) -> float:
	return maxf(0.0, spd * ANIM_FRAMES_PER_METRE / WALK_FPS)


## Picks the atlas row from where the body is pointing and where the camera is, and
## re-issues the cycle when it changes. `zombie.gd:567-580` with the phase-keeping
## removed: `AnimatedSprite3D.play()` on the animation that is already playing is a
## no-op, so the only path that reaches `play()` here is a genuine bearing change,
## and re-seating the phase across one is worth a line only when it happens four
## times a second on a body circling you. A teammate turns as often as a zombie
## does, so the phase IS kept — see the two lines below.
func _update_view() -> void:
	if not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	var to_cam := Vector2(cp.x - global_position.x, cp.z - global_position.z)
	var pick := SPRITES.view_for(_facing, to_cam)
	var flip := pick.y == 1
	if pick.x == _view and flip == _flip:
		return
	_view = pick.x
	_flip = flip
	var full := SPRITES.anim_name("walk", _view)
	var was_frame := _sprite.frame
	var was_progress := _sprite.frame_progress
	_sprite.play(full)
	var n := _sprite.sprite_frames.get_frame_count(full)
	if n > 0:
		_sprite.set_frame_and_progress(mini(was_frame, n - 1), was_progress)
	_sprite.flip_h = _flip


## Every frame, because the row depends on the camera as much as on the body — a
## teammate standing still still has to turn to face you as you walk round them.
func _process(dt: float) -> void:
	if _head != null:
		# Frame-rate independent: `1 - exp(-k*dt)` is the same curve at 30 fps and
		# at 144, where a bare `lerp(a, b, k*dt)` is not.
		_head.rotation.x = lerpf(_head.rotation.x, _pitch_target,
			1.0 - exp(-PITCH_RATE * dt))
	_update_view()


# --- the generated atlas -----------------------------------------------------
#
# There is no survivor art in assets/sprites/ and adding an art pipeline is not
# this package's job, so the sheet is drawn here, once, into an ImageTexture. That
# is the same bargain `Zombie._eye_texture()` takes for the eye ramp: a texture
# generated at startup costs one upload and nothing after, where a shader costs a
# main-thread GLSL compile the first time it is drawn on the web target.
#
# It is generated LAZILY, on the first avatar of a run, so a single-player session
# never pays for a pixel of it.
#
# The layout mirrors `<stem>_dir.png`: WALK_FRAMES cells across, VIEW_COUNT rows
# down, one row per bearing, cut with the same AtlasTexture regions
# `SpriteLib._add_set` uses. Rows 1-3 are mirrored by `view_for` to cover the other
# three bearings, exactly as the enemies' rows are.

static var _frames_cache := {}


## The SpriteFrames for one coat, built once and shared by every avatar wearing it.
## Public and static so the assertion suite can measure the sheet — the frame gate
## has no co-op scenario, so the only thing that can check this art without a human
## is a test that reads the pixels.
static func frames_for(tint: int) -> SpriteFrames:
	var t := posmod(tint, CREW.size())
	if _frames_cache.has(t):
		var cached: SpriteFrames = _frames_cache[t]
		return cached
	var sheet := sheet_for(t)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for v in SPRITES.VIEW_COUNT:
		var n := SPRITES.anim_name("walk", v)
		sf.add_animation(n)
		sf.set_animation_speed(n, WALK_FPS)
		sf.set_animation_loop(n, true)
		for i in WALK_FRAMES:
			var at := AtlasTexture.new()
			at.atlas = sheet
			at.region = Rect2(i * CELL_W, v * CELL_H, CELL_W, CELL_H)
			at.filter_clip = true
			sf.add_frame(n, at)
	_frames_cache[t] = sf
	return sf


static var _sheet_cache := {}


static func sheet_for(tint: int) -> ImageTexture:
	var t := posmod(tint, CREW.size())
	if _sheet_cache.has(t):
		var cached: ImageTexture = _sheet_cache[t]
		return cached
	var tex := ImageTexture.create_from_image(sheet_image(t))
	_sheet_cache[t] = tex
	return tex


## The whole sheet as an Image. Split out of `sheet_for` so it can be written to a
## PNG and looked at, which is the only visual check this package has: the frame
## gate photographs a single-player run and there is nothing in it that can put a
## second player in the room.
static func sheet_image(tint: int) -> Image:
	var img := Image.create_empty(CELL_W * WALK_FRAMES, CELL_H * SPRITES.VIEW_COUNT,
		false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for v in SPRITES.VIEW_COUNT:
		for f in WALK_FRAMES:
			_draw_cell(img, f * CELL_W, v * CELL_H, v, f, posmod(tint, CREW.size()))
	_outline(img)
	return img


## One 48x64 cell: a survivor stood on the bottom edge, seen from bearing `view`,
## on frame `frame` of the walk.
##
## The figure is a stack of rectangles, which is what the ancestor's own sprites
## are — `makeZombieSet` is a run of `fillRect` calls (kriegsnacht.html:973 on) —
## so this matches the drawing idiom rather than only the file format. What changes
## with the bearing is deliberately small: the shoulder width, whether there is a
## face, whether there is a pack, and where the weapon is. A figure that is
## re-drawn from scratch per bearing is a figure whose five rows do not look like
## the same person.
static func _draw_cell(img: Image, ox: int, oy: int, view: int, frame: int,
		tint: int) -> void:
	var coat: Color = CREW[tint]
	var coat_dark := Color(coat.r * 0.62, coat.g * 0.62, coat.b * 0.62, 1.0)
	var c := CELL_W / 2                       # cell centre, in cell pixels
	# Shoulders narrow into profile and open out again at the back. Row 2 is the
	# side view and is the narrowest thing a body can be — but never narrower than
	# the head, or the figure reads as a lollipop.
	var half: int = [7, 6, 5, 6, 7][view]
	var faces_us := view <= 1
	var backs_us := view >= 3

	# --- legs, and the whole of the walk ------------------------------------
	#
	# Contact, pass, contact, pass. TWO quantities decide where a leg is, and
	# conflating them is what the first version of this got wrong:
	#
	#   `lateral` — how far apart the legs are ACROSS the body. Head-on that is the
	#      whole of what you see of a pair of legs, and it does not change as the
	#      figure walks. Drawing it as part of the stride merged the two legs into
	#      one column on three frames of four and split them on the fourth, which
	#      read as a body growing a second leg every half second.
	#   `throw * spread` — how far one leg is FORWARD of the other. That is almost
	#      the whole of a stride and almost none of it is visible head-on, so
	#      `spread` is zero on rows 0 and 4 and full in profile.
	#
	# The far leg goes down first and in the darker tone, so the profile frames
	# where the two cross still read as two legs.
	var throw: int = [1, 0, -1, 0][frame]
	var lateral: int = [3, 3, 0, 3, 3][view]
	var spread: int = [0, 1, 4, 1, 0][view]
	var leg_w := 4
	var lift := 3 if throw == 0 else 0
	# Which leg is raised on a passing frame alternates, or the gait limps.
	var raise_near := frame == 1
	var near_x := c + lateral - leg_w / 2 + throw * spread
	var far_x := c - lateral - leg_w / 2 - throw * spread
	var far_h := 23 - (lift if not raise_near else 0)
	var near_h := 23 - (lift if raise_near else 0)
	# Head-on there is no near and no far, so the depth tone would read as a
	# shadow on one leg rather than as depth.
	var far_col := TROUSER_DARK if spread > 0 else TROUSER
	_rect(img, ox + far_x, oy + 40, leg_w, far_h, far_col)
	_rect(img, ox + far_x, oy + 40 + far_h - 5, leg_w + 1, 5, BOOT)
	_rect(img, ox + near_x, oy + 40, leg_w, near_h, TROUSER)
	_rect(img, ox + near_x, oy + 40 + near_h - 5, leg_w + 1, 5, BOOT)

	# --- torso --------------------------------------------------------------
	_rect(img, ox + c - half, oy + 13, half * 2, 23, coat)
	# A darker band down one side gives the coat a light direction that survives
	# being 14 px wide. Mirrored with the row by `flip_h`, which is correct: the
	# shading turns with the body.
	_rect(img, ox + c + half - 3, oy + 13, 3, 23, coat_dark)
	# Belt.
	_rect(img, ox + c - half, oy + 34, half * 2, 3, coat_dark)
	# Hips, under the coat.
	_rect(img, ox + c - half + 2, oy + 37, half * 2 - 4, 4, TROUSER)

	# --- pack ---------------------------------------------------------------
	# Only from behind, and drawn OVER the coat rather than under it — a pack is
	# worn on the back, and the first version of this put it beneath the torso
	# rectangle where it was covered completely and therefore did nothing. It is
	# the thing that says "this one is not looking at you" on a silhouette that has
	# no face left to lose.
	if backs_us:
		_rect(img, ox + c - half + 2, oy + 16, half * 2 - 4, 15, PACK)
		_rect(img, ox + c - half + 2, oy + 22, half * 2 - 4, 2, coat_dark)
		_rect(img, ox + c - 1, oy + 16, 2, 15, coat_dark)

	# --- arms ---------------------------------------------------------------
	# Counter-swung against the legs, which is what stops the figure reading as a
	# mannequin being slid along the floor.
	var swing := throw * 2
	_rect(img, ox + c - half - 2, oy + 15 - swing, 3, 15, coat_dark)
	_rect(img, ox + c + half - 1, oy + 15 + swing, 3, 15, coat)

	# --- head ---------------------------------------------------------------
	_rect(img, ox + c - 4, oy + 3, 8, 9, HAIR)
	if faces_us:
		_rect(img, ox + c - 3, oy + 6, 6, 5, SKIN)
		_rect(img, ox + c - 3, oy + 10, 6, 1, SKIN_DARK)
		# Two eyes head-on, one in three-quarter. A survivor's eyes are DARK — the
		# enemies' are the additive amber quads in zombie.gd, and the single
		# clearest read at distance is that this one's are not lit.
		_px(img, ox + c - 2, oy + 8, EYE_DARK)
		if view == 0:
			_px(img, ox + c + 1, oy + 8, EYE_DARK)
	# Neck.
	_rect(img, ox + c - 2, oy + 12, 4, 2, SKIN_DARK)

	# --- the weapon ---------------------------------------------------------
	# Carried across the chest head-on and swung forward as the body turns, which
	# is the pose a first-person game's own viewmodel is in and therefore the pose
	# a teammate is telling you they are in.
	#
	# IT HAS TO BREAK THE SILHOUETTE, AND IT MUST NOT BE SYMMETRIC. The first
	# version drew the head-on bar 13 px wide inside a 14 px torso, so at the
	# bearing a teammate spends most of their time at the weapon was a slightly
	# darker stripe on a coat. Widening it to 19 px fixed that and broke something
	# worse: a bar centred on the chest and overhanging both shoulders reads as a
	# shelf, not as a rifle. It is offset to the weapon side on every row now, so
	# the overhang is on ONE side and the shape has a muzzle.
	#
	# Nothing at all from behind. The rifle is in front of the body there, and a
	# bar drawn across the back on top of the pack was the busiest thing in the
	# sheet while depicting the one object you cannot see from that angle.
	var gx: int = [-1, 0, 1, 0, 0][view]
	var gw: int = [11, 13, 15, 0, 0][view]
	var gy: int = [26, 25, 23, 0, 0][view]
	if gw > 0:
		_rect(img, ox + c + gx, oy + gy, gw, 3, GUN)
		_rect(img, ox + c + gx, oy + gy, gw, 1, GUN_HL)
		if faces_us:
			# The grip, so the weapon reads as held rather than as a stripe.
			_rect(img, ox + c + gx + 2, oy + gy + 3, 2, 4, GUN)


static func _rect(img: Image, x: int, y: int, w: int, h: int, col: Color) -> void:
	for j in h:
		for i in w:
			_px(img, x + i, y + j, col)


static func _px(img: Image, x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	img.set_pixel(x, y, col)


## The 1 px dark rim, stamped over the whole sheet at the end.
##
## `outlineSprite()` is the ancestor's and every enemy strip carries one
## (sprite_lib.gd:6-9); without it a body lit only by a torch cone loses its edge
## against a wall lit by the same cone. Run as a separate pass over the finished
## sheet rather than per shape, because an outline drawn per rectangle outlines the
## seams between them as well.
##
## Cells are outlined INDEPENDENTLY of each other — a pixel at a cell boundary does
## not see its neighbour across the seam — because the sheet is sliced back into
## 48x64 regions and a rim bled across a seam would appear as a stray line down the
## edge of the next frame.
static func _outline(img: Image) -> void:
	var src := img.duplicate()
	for y in img.get_height():
		for x in img.get_width():
			if src.get_pixel(x, y).a > 0.0:
				continue
			var cx := x % CELL_W
			var cy := y % CELL_H
			var touched := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := cx + d.x
				var ny := cy + d.y
				if nx < 0 or ny < 0 or nx >= CELL_W or ny >= CELL_H:
					continue
				if src.get_pixel(x + d.x, y + d.y).a > 0.0:
					touched = true
					break
			if touched:
				img.set_pixel(x, y, OUTLINE)
