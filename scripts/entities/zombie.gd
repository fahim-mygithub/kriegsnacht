class_name Zombie
extends CharacterBody3D

## One undead. Nodes are built in code rather than from a .tscn so the whole
## entity — collider, billboard, hitbox split — lives in one readable place.

signal died(z: Zombie, was_headshot: bool, by_melee: bool)

## `ENTERING` was declared here from the first commit and assigned by nothing; it
## is the vault now, which is exactly what the name always meant. `TEARING_BOARDS`
## is appended rather than inserted because `player.gd`, `verify.gd` and this file
## all compare against `State.DYING` by value, and renumbering the four that
## already exist would move that comparison without moving any of them.
enum State { ENTERING, CHASING, ATTACKING, DYING, TEARING_BOARDS }

## preload rather than the class name: `barricade.gd` is new, so it is not in the
## class registry until the editor rescans and a headless run has no editor. Only
## the static `of()` is used from here — a zombie is handed a window index by the
## round director and finds its barricade from that alone.
const BARRICADE := preload("res://scripts/world/barricade.gd")

const SEPARATION_RADIUS := 0.62
const SEPARATION_FORCE := 2.4

## The separation sum used to be unbounded: each neighbour contributes up to 1.0,
## summed over every neighbour, multiplied by 2.4, then added to a *unit-length*
## steering vector. With four or more crowded neighbours the push outweighed the
## steering five to ten times over, so a dense pack behaved like a repulsion gas
## and could drift away from the player and into walls. Clamped before scaling.
const SEPARATION_LIMIT := 0.6

## Line of sight beats the flow field, but only nearby. Unbounded it fired 24
## full-length raycasts per tick and funnelled the entire horde onto one point
## across a 16x14 room. Near-goal only, which is what the technique is for.
const LOS_RANGE := 9.0

const GROAN_MIN := 3.5
const GROAN_MAX := 9.0
const GROAN_RANGE := 20.0

## Working the boards. `boardT: rnd(1.2,0.3)` at spawn (html:2212), then
## `z.boardT = z.type==='hound' ? 0.42 : rnd(1.5,0.9)` after each plank
## (html:2274). `rnd(a,b)` is `b + random()*(a-b)` (html:377), so both of those are
## ranges written with the larger number first.
##
## Note the interval is **0.9-1.5 s**, not the 0.9-1.4 the milestone plan quotes,
## and the hound's flat 0.42 s is not in the plan at all — a dog is through a
## barricade in two and a half seconds against a walker's seven, which is most of
## what makes a dog round feel like a different game.
const BOARD_FIRST_MIN := 0.3
const BOARD_FIRST_MAX := 1.2
const BOARD_MIN := 0.9
const BOARD_MAX := 1.5
const BOARD_HOUND := 0.42

## `z.atkAnim = 0.3` on every plank (html:2278) — the swing that pulls it off. The
## walk cycle resumes underneath it, which is what stops a zombie at a window
## reading as an idle prop between boards.
const BOARD_SWING := 0.3

## The tear cue, positioned. `Audio2.board(...)` (html:501-503, called at :2276) is
## the ancestor's own sound for this and the port has never played it: `main.gd`
## plays the same baked `board` buffer, but on the *rebuild* and on Carpenter,
## where the ancestor used a different sound entirely (`repair()`, :504). So the
## "baked and never played" note in the gap analysis is stale — the buffer is
## played — but this, the event it was written for, is genuinely new.
const BOARD_VOLUME := -7.0

## The traversal, once the last plank is off. The ancestor did not have one:
## `if(w.boards<=0){ z.state='chase'; z.x=w.ix+0.5; z.y=w.iy+0.5; }` (html:2271) is
## a teleport in a single statement. 1.2 s is the plan's figure and it is invented
## there too — but the hitbox stays live for every frame of it, which is the part
## that matters: a zombie that cannot be shot while it climbs in is a free entry,
## and free entry is the opposite of what a barricade is for.
const VAULT_TIME := 1.2

## Eye geometry, in the sprite's own pixels, read off the ancestor's draw calls
## so the quads land on the pixels the art already lights up: a `#F3E4A8` core
## inside a soft halo on every walker and crawler frame (kriegsnacht.html:939,
## 1043) and `#FF7A18` burning eyes on the hound (:1104). They are dark in the
## port only because the billboard is `shaded = true` and the map is dark.
##
## `y` is the row from the top of the cell, averaged over the vertical bob the
## ancestor applied per frame; `sep` the gap between the two eye centres; `x` how
## far the pair sits from the cell's horizontal centre — zero for a walker, well
## left for a crawler dragging its head and for the hound, which is drawn in
## profile; `glow` the footprint of one eye, taken from the halo rect where the
## ancestor drew one. Everything is converted through `SpriteLib.pixel_size(kind)`,
## so the eyes move with the body if `SpriteLib.HEIGHT` ever changes.
##
## `glow` rather than `size` because dot-access on a `Dictionary` is a key
## lookup and `size` is also a `Dictionary` method — not worth finding out which
## one wins on a build that hangs rather than reports a parse error.
const EYE_PX := {
	"zombie": {"y": 14.9, "sep": 5.9, "x": 0.0, "glow": 4.6},
	"crawler": {"y": 15.4, "sep": 4.6, "x": -13.2, "glow": 4.1},
	"hound": {"y": 10.6, "sep": 4.4, "x": -18.3, "glow": 6.0},
}

## One tint per palette. The three ZPAL bodies (html:844-848) are meant to read
## as three different corpses and the groan pitch already splits on `pal`, so the
## eyes split too — but only inside the authored amber band, because franchise
## undead eyes are warm and a cold-eyed zombie reads as a different game.
## Palette 0 is the ancestor's `#F3E4A8` unchanged; 1 is pushed warm to sit with
## its brown cloth, 2 paler and faintly green to sit with its blue-grey skin.
const EYE_TINT := [
	Color(0.953, 0.894, 0.659),
	Color(1.000, 0.816, 0.502),
	Color(0.886, 0.941, 0.753),
]

## `#FF7A18`, verbatim (html:1104). A hellhound is on fire and must not share an
## eye colour with a walker.
const EYE_TINT_HOUND := Color(1.000, 0.478, 0.094)

## Vertex colours are 8-bit and cannot carry a value over 1.0, so the overdrive
## that pushes the pixel past `env.glow_hdr_threshold` — 0.92, set at main.gd:149
## against an RGBA8 LDR colour buffer — has to live here, in the one shared
## albedo, rather than in the per-palette hue.
const EYE_GAIN := 1.15

## Pushed toward the camera so the additive quad is never coplanar with the
## billboard it sits on and loses the depth test to it. Depth resolution at 20 m
## is under a millimetre, so this is two orders of margin, and 2 cm of parallax
## on a 1.3 m sprite is invisible.
const EYE_FORWARD := 0.02

## One number, used twice, and the two uses have to agree or the rim outlines
## something the sprite does not draw: the sprite discards below this, and the
## rim shader calls an edge "the outermost texel the sprite still draws".
const ALPHA_SCISSOR := 0.35

var kind := "zombie"          # zombie | crawler | hound
var pal := 0
var hp := 150.0
var max_hp := 150.0
var speed := 1.2
var melee_damage := 60.0
var melee_cadence := 1.05
var melee_reach := 1.15
var state: int = State.CHASING

var _sprite: AnimatedSprite3D
var _eyes: MeshInstance3D
var _collider: CollisionShape3D
var _attack_timer := 0.0
var _death_timer := 0.0
var _last_headshot := false
var _last_melee := false
var _height := 1.82
var _hit_flash := 0.0
var _groan_timer := 0.0
## Each zombie aims at a slightly different point around the player. Ten lines,
## and most of the difference between a horde and a conga line.
var _goal_offset := Vector2.ZERO
var _offset_timer := 0.0

## The barricade this one is working, and which of its standing slots it took.
## Untyped on purpose: `barricade.gd` carries no `class_name`, so a `Node3D`-typed
## local could not see `take_board()` — the same reason `main.gd` leaves `lighting`
## and `hud` untyped. Cleared the moment the vault finishes, so a chasing zombie
## holds no reference to a window.
var _barricade
var _slot := -1
var _board_timer := 0.0
var _swing_t := 0.0
var _vault_t := 0.0
var _vault_from := Vector3.ZERO

var flow: FlowField
var target: Node3D
var neighbours: Array = []


static func create(p_kind: String, p_pal: int, p_round: int, insta: bool) -> Zombie:
	var z := Zombie.new()
	z.kind = p_kind
	z.pal = p_pal
	z._configure(p_round, insta)
	return z


func _configure(p_round: int, _insta: bool) -> void:
	_height = SpriteLib.HEIGHT[kind]
	var base_hp := Game.zombie_hp(p_round)
	# Discrete movement class rather than one continuous curve. Escalation past
	# round 16 now comes from the class mixture shifting, not from a speed value
	# that saturated and never moved again.
	var base_speed := Game.roll_speed_class(p_round)
	match kind:
		"hound":
			hp = base_hp * 0.62
			# Hounds are deliberately left alone: they already outrun the player.
			speed = base_speed * 1.55
			melee_damage = 36.0
			melee_cadence = 0.85
			melee_reach = 1.15
		"crawler":
			hp = base_hp * 0.8
			speed = base_speed * 0.62
			melee_reach = 1.05
		_:
			hp = base_hp
			# A23: `spd * (G.round>=14 && z.type==='z' ? 1.06 : 1)`
			# (kriegsnacht.html:2334). One 6% step at round 14, and only for
			# regular zombies — the ancestor's `type==='z'` excludes hounds and
			# crawlers, both of which already have their own multiplier above.
			# Deliberately not folded into roll_speed_class(), which feeds all
			# three kinds and is asserted against SPEED_SPRINT by value.
			speed = base_speed * Game.late_speed_scale(p_round)
	# A little off the class's nominal pace, but not so much that the three
	# classes stop reading as three distinct threats.
	speed *= Rng.randf_range(Rng.AI, 0.92, 1.08)
	max_hp = hp
	# Phase the attack clock per zombie. A single shared cooldown meant a pile of
	# six dealt exactly one zombie's damage.
	_attack_timer = Rng.randf_range(Rng.AI, 0.0, 0.6)


func _ready() -> void:
	collision_layer = 4
	# Walls and the player. Zombies still pass through each other — the boid
	# separation handles spacing far more cheaply than 24 mutually-colliding
	# capsules would, and that cost is unmeasured on this physics backend.
	collision_mask = 1 | 2
	floor_max_angle = deg_to_rad(70)

	var caps := CapsuleShape3D.new()
	caps.radius = 0.26 if kind != "hound" else 0.30
	caps.height = maxf(_height, caps.radius * 2.0 + 0.05)
	_collider = CollisionShape3D.new()
	_collider.shape = caps
	_collider.position.y = caps.height * 0.5
	add_child(_collider)

	_sprite = AnimatedSprite3D.new()
	_sprite.sprite_frames = SpriteLib.frames_for(kind, pal)
	_sprite.pixel_size = SpriteLib.pixel_size(kind)
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_sprite.shaded = true
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_sprite.alpha_scissor_threshold = ALPHA_SCISSOR
	# Sprite origin is its centre, so lift it half a body to stand on the floor.
	_sprite.position.y = _height * 0.5
	_play("walk")
	add_child(_sprite)

	# The one thing that says "Call of Duty Zombies" from across a dark room.
	# It cannot be a second Sprite3D — `SpriteBase3D` exposes no blend mode, so
	# there is no way to make one additive. This is the same construction the
	# muzzle flash uses at main.gd:181-196, which is the working reference in
	# this project for an additive billboard on this renderer.
	_eyes = MeshInstance3D.new()
	_eyes.mesh = _eye_mesh(kind, pal)
	_eyes.material_override = eye_material()
	_eyes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_eyes.position.y = _eye_height()
	# Billboarding is a vertex-shader rotation, so the mesh AABB never turns with
	# the geometry. Without a margin the hound's pair — which sits over half a
	# body-length off its own origin, because its head is drawn in profile — gets
	# culled early and blinks out at the edge of the screen.
	#
	# Twice the span, not once. The margin grows the AABB the mesh already has,
	# and the crawler's and the hound's sit wholly on one side of the origin
	# (x from -0.58 to -0.32 on a hound), so one span leaves the opposite side of
	# the swept circle short by however far the box is off-centre. Two covers any
	# offset, because that distance can never exceed the span itself.
	_eyes.extra_cull_margin = _eye_span() * 2.0
	add_child(_eyes)

	# Slight per-zombie variation on the animation. Cosmetic, so it draws from
	# the visual stream and cannot perturb anything the run depends on.
	_sprite.speed_scale = Rng.randf_range(Rng.VISUAL, 0.85, 1.2)
	_groan_timer = Rng.randf_range(Rng.VISUAL, 1.0, GROAN_MAX)
	_reroll_offset()


## Every animation change goes through here, because the rim overlay and the
## animation cannot move independently: the rim reads the silhouette out of the
## strip the current animation is cut from, and walk, attack and death are three
## separate PNGs. A bare `_sprite.play()` anywhere would leave a zombie outlined
## by the pose it was in a moment ago.
func _play(anim: String) -> void:
	_sprite.play(anim)
	_sprite.material_overlay = rim_material(kind, pal, anim)


func _reroll_offset() -> void:
	var a := Rng.randf(Rng.AI) * TAU
	_goal_offset = Vector2.from_angle(a) * Rng.randf_range(Rng.AI, 0.0, 1.2)
	_offset_timer = Rng.randf_range(Rng.AI, 3.0, 5.0)


## Puts this one outside the barricade it was assigned, with the boards still on.
##
## The round director used to decrement the board count on the frame a zombie
## spawned and drop the body on the *room* side of the wall — so "working the
## boards" was a number that ticked, the barricade never had anything standing at
## it, and a spawn could land inside the player's melee reach. All of that is
## replaced here: the zombie arrives in the exterior pocket, and the only ways in
## are through six planks it has to pull off itself or through a window somebody
## already stripped.
func set_entering(window_id: int) -> void:
	# `_window_id` used to be recorded here and read by nothing at all. The
	# barricade node is the identity now, and it is cleared the moment the vault
	# lands — a chasing zombie has no window.
	_barricade = BARRICADE.of(window_id)
	if _barricade == null:
		# No barricade node for this window, which is what any harness that runs the
		# game logic without building a world sees. Land on the room tile and chase,
		# which is what this function did before the barricade existed — stranding
		# the body in an unreachable pocket instead would be a silent stall.
		var w: Dictionary = MapData.WINDOWS[window_id]
		global_position = Vector3(float(w.ix) + 0.5, 0.0, float(w.iy) + 0.5)
		state = State.CHASING
		return

	_slot = _barricade.claim()
	var stand: Vector3 = _barricade.stand_point(_slot)
	global_position = stand
	var left: int = _barricade.boards
	if left <= 0:
		# A window somebody already stripped is a door. The ancestor made the same
		# check at the top of its window state (html:2271), so a zombie sent to a
		# boardless barricade went straight through on its first tick.
		_begin_vault()
		return
	state = State.TEARING_BOARDS
	_board_timer = Rng.randf_range(Rng.AI, BOARD_FIRST_MIN, BOARD_FIRST_MAX)


## One plank at a time, and nothing else: no steering, no attack test, no
## `move_and_slide`. **This is the asymmetry the whole barricade exists for — a
## zombie here is fully shootable and completely harmless**, and rounds one to five
## are the seconds that buys you.
func _tick_boards(dt: float) -> void:
	if _swing_t > 0.0:
		_swing_t -= dt
		if _swing_t <= 0.0 and _sprite.animation != "walk":
			_play("walk")

	if _barricade == null or not is_instance_valid(_barricade):
		# The level was torn down under a live zombie (a scene reload does exactly
		# this). Fall back to chasing rather than standing outside forever.
		#
		# Released on the way out even though the release can no longer reach the
		# map — `_release_window` needs a live barricade to decrement
		# `window_workers`, and there is none — so that "every exit from
		# TEARING_BOARDS gives the slot back" holds without an exception a reader
		# has to find. What it does do here is clear `_slot`, which is what stops a
		# later `_die()` from asking a dead node for anything.
		_release_window()
		state = State.CHASING
		return

	var left: int = _barricade.boards
	if left <= 0:
		_begin_vault()
		return

	_board_timer -= dt
	if _board_timer > 0.0:
		return
	if kind == "hound":
		# Flat, and no draw at all — the ancestor's ternary short-circuits the same
		# way, so a dog round consumes a different number of AI draws than a walker
		# round does and always has.
		_board_timer = BOARD_HOUND
	else:
		# Gameplay, not cosmetic: how fast a barricade comes apart decides when the
		# round arrives on you, so this draw belongs to the AI stream.
		_board_timer = Rng.randf_range(Rng.AI, BOARD_MIN, BOARD_MAX)
	_barricade.take_board()
	var at: Vector3 = _barricade.cue_point()
	Sfx.play_at("board", at, BOARD_VOLUME)
	_swing_t = BOARD_SWING
	if _sprite.animation != "attack":
		_play("attack")


## Hands the standing slot back and starts the climb.
func _begin_vault() -> void:
	_release_window()
	state = State.ENTERING
	_vault_t = 0.0
	_vault_from = global_position
	_swing_t = 0.0
	if _sprite.animation != "walk":
		_play("walk")


## The climb. Position is written straight rather than driven through
## `move_and_slide`, which is what lets a body cross a tile the flow field and the
## player both still see as solid — and it is also why the collision mask is left
## exactly as configured. Zeroing the layer for the traversal, which is the obvious
## way to pass through a wall, would take the zombie out of the hitscan's mask as
## well and hand the player a target it cannot shoot.
func _tick_vault(dt: float) -> void:
	if _barricade == null or not is_instance_valid(_barricade):
		state = State.CHASING
		return
	_vault_t = minf(1.0, _vault_t + dt / VAULT_TIME)
	var on_curve: Vector3 = _barricade.vault_sample(_vault_t)
	var start: Vector3 = _barricade.vault_start()
	# Blended off this body's own starting point rather than snapped to the curve's.
	# One curve serves a window and two zombies work it from two slightly different
	# spots, so the second one would otherwise jump sideways on its first frame.
	global_position = on_curve + (_vault_from - start) * (1.0 - _vault_t)
	velocity = Vector3.ZERO
	if _vault_t >= 1.0:
		state = State.CHASING
		_barricade = null


## Idempotent, because both of its callers can fire for the same zombie: it dies at
## the window, or it starts the climb. A slot released twice would let a barricade
## believe it is emptier than it is and stack the next arrivals on one spot.
func _release_window() -> void:
	if _slot >= 0 and _barricade != null and is_instance_valid(_barricade):
		_barricade.release(_slot)
	_slot = -1


func _physics_process(dt: float) -> void:
	if Game.state != Game.STATE_PLAY:
		return

	if state == State.DYING:
		_death_timer -= dt
		if _death_timer <= 0.0:
			queue_free()
		return

	_tick_flash(dt)

	if target == null:
		return

	_tick_groan(dt)

	# Above the steering and below the vocalisation, which is the ancestor's own
	# ordering (html:2260-2282): a zombie at a window still groans, and that is
	# what tells you a barricade you cannot see is being worked.
	if state == State.TEARING_BOARDS:
		_tick_boards(dt)
		return
	if state == State.ENTERING:
		_tick_vault(dt)
		return

	_offset_timer -= dt
	if _offset_timer <= 0.0:
		_reroll_offset()

	var here := Vector2(global_position.x, global_position.z)
	var goal := Vector2(target.global_position.x, target.global_position.z)
	var to_target := goal - here
	var dist := to_target.length()

	if dist <= melee_reach:
		state = State.ATTACKING
		if _sprite.animation != "attack":
			_play("attack")
		_attack_timer -= dt
		if _attack_timer <= 0.0:
			_attack_timer = melee_cadence
			if target.has_method("take_damage"):
				# Identify the attacker so the player can apply a per-attacker
				# grace window instead of one global cooldown for the whole horde.
				target.take_damage(melee_damage, get_instance_id())
			Sfx.play_at("melee", centre(), -8.0)
		velocity = Vector3.ZERO
		move_and_slide()
		return

	if state == State.ATTACKING:
		state = State.CHASING
	if _sprite.animation != "walk":
		_play("walk")

	# Direct line of sight beats the flow field near the goal — it stops a horde
	# in an open room from filing along tile centres like a conga line.
	var aim := goal + _goal_offset
	var dir: Vector2
	if dist < LOS_RANGE and _has_los(here, goal):
		dir = (aim - here).normalized()
	else:
		dir = flow.direction_at(here) if flow else Vector2.ZERO
		if dir == Vector2.ZERO:
			dir = to_target.normalized()

	dir += _separation(here) * SEPARATION_FORCE
	dir = dir.normalized()

	velocity.x = dir.x * speed
	velocity.z = dir.y * speed
	velocity.y = 0.0
	move_and_slide()


## Brief bright tint on damage, plus a standing warm tint while Insta-Kill is up
## so the power-up is visible on the horde rather than only in a HUD toast.
func _tick_flash(dt: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = maxf(0.0, _hit_flash - dt * 11.0)
	var c := Color(1.0, 1.0, 1.0)
	if Game.insta_kill > 0.0:
		c = c.lerp(Color(1.6, 0.55, 0.42), 0.35)
	if _hit_flash > 0.0:
		c = c.lerp(Color(2.4, 2.1, 1.9), _hit_flash)
	_sprite.modulate = c


## Idle vocalisation, positioned in the world. This is the channel that answers
## "what is behind me" — the one question a billboard can never answer, because
## the thing behind you is not on screen.
func _tick_groan(dt: float) -> void:
	_groan_timer -= dt
	if _groan_timer > 0.0:
		return
	_groan_timer = Rng.randf_range(Rng.VISUAL, GROAN_MIN, GROAN_MAX)
	if target.global_position.distance_to(global_position) > GROAN_RANGE:
		return
	if kind == "hound":
		Sfx.play_at("bark", centre(), -10.0,
			Rng.randf_range(Rng.VISUAL, 0.94, 1.08), GROAN_RANGE)
	else:
		Sfx.play_at("groan%d" % pal, centre(), -12.0,
			Rng.randf_range(Rng.VISUAL, 0.92, 1.10), GROAN_RANGE)


## Boid-style push so bodies spread out instead of stacking on one tile.
func _separation(here: Vector2) -> Vector2:
	var push := Vector2.ZERO
	for other in neighbours:
		if other == self or not is_instance_valid(other):
			continue
		var o := Vector2(other.global_position.x, other.global_position.z)
		var d := here - o
		var l := d.length()
		if l > 0.001 and l < SEPARATION_RADIUS:
			push += d / l * (1.0 - l / SEPARATION_RADIUS)
	return push.limit_length(SEPARATION_LIMIT)


func _has_los(from: Vector2, to: Vector2) -> bool:
	var space := get_world_3d().direct_space_state
	var a := Vector3(from.x, 1.2, from.y)
	var b := Vector3(to.x, 1.2, to.y)
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collision_mask = 1
	return space.intersect_ray(q).is_empty()


## Real 3D headshots. The browser build could only test whether screen-centre
## fell inside the top band of the billboard; here the hit point's height is
## compared against the actual head region of the body.
func head_threshold() -> float:
	return _height * (0.70 if kind == "zombie" else 0.58)


func take_damage(amount: float, hit_y: float, by_melee := false) -> bool:
	if state == State.DYING:
		return false
	var headshot := hit_y >= head_threshold()
	if Game.insta_kill > 0.0:
		amount = 1e9
	if headshot:
		amount *= 1.5
	hp -= amount
	_last_headshot = headshot
	_last_melee = by_melee
	_hit_flash = 1.0
	# Play the impact before the kill check. The killing shot used to be the one
	# event in the game with no impact sound at all — a headshot kill was silent
	# apart from the death rattle.
	Sfx.play_at("headshot" if headshot else "hit", centre(), -10.0)
	if hp <= 0.0:
		_die()
		return true
	return false


func _die() -> void:
	# Before the state changes, because the release is keyed on holding a slot and
	# a corpse holding one would keep a standing place at a window occupied for the
	# rest of the run.
	_release_window()
	state = State.DYING
	collision_layer = 0
	collision_mask = 0
	# The rim follows the animation and deliberately survives the death: a corpse
	# still needs a silhouette while it falls, and the death strip is a different
	# PNG from the walk strip — outlining one with the other's alpha would trace a
	# figure that is no longer there.
	_play("death")
	_sprite.modulate = Color(1.0, 1.0, 1.0)
	# The death animation runs for a second or so before queue_free, and a corpse
	# with two lights still burning in its skull is a bug, not a flourish.
	_eyes.visible = false
	var frames: int = SpriteLib.SPEC[kind].death
	_death_timer = float(frames) / 9.0 + 0.9
	Sfx.play_at("death", centre(), -12.0)
	died.emit(self, _last_headshot, _last_melee)


## Where a hitscan should aim to be "centre mass", used by the melee test.
func centre() -> Vector3:
	return global_position + Vector3(0, _height * 0.5, 0)


# --- glowing eyes ------------------------------------------------------------

## Shared by every zombie alive. A `StandardMaterial3D` per zombie would be 24
## uniform sets and, on a platform with no shader program cache, 24 chances to
## compile the same program again in the middle of a fight.
static var _eye_mat: StandardMaterial3D

## Seven small meshes at most — three walker palettes, three crawler, one hound —
## also shared. The per-palette colour rides in the vertex stream because that is
## the only per-instance channel this renderer leaves open: `INSTANCE_CUSTOM`
## does nothing on a plain `MeshInstance3D` under Compatibility, and an
## `instance uniform` would mean a new shader, which is the one thing the web
## target charges most for.
static var _eye_meshes := {}


## The warm-up pass needs this by name. `main.gd::_ready` hands `shader_warmup.gd`
## an `extra` array of materials the world builder does not own, and any material
## missing from that list buys a mid-frame GLSL compile the first time it is
## drawn — here, the first time a zombie walks into view. Referenced by function
## rather than line number because the call site moves and a stale line sends the
## next reader to the wrong statement.
static func eye_material() -> StandardMaterial3D:
	if _eye_mat != null:
		return _eye_mat

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(EYE_GAIN, EYE_GAIN, EYE_GAIN)
	m.albedo_texture = _eye_texture()
	# Explicit, so the sampler never asks for a mip level this texture does not
	# carry, and so the variant is pinned rather than inherited from a default.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.disable_receive_shadows = true
	# Depth fog is a lerp toward the fog colour in the fragment shader and it runs
	# on unshaded transparents like any other surface — which on an additive quad
	# is wrong twice over. It adds a disc of fog grey on top of a wall the same
	# fog already greyed, and it drags the eye colour down with distance: at 10 m,
	# with fog_density 0.030 (main.gd:151), the core falls to ~0.89 and stops
	# clearing the 0.92 bleed threshold — so the glow dies at exactly the range
	# this whole effect exists for. Light is not dimmed by the air in front of it.
	# This is the flag the engine documents for the case.
	m.disable_fog = true
	# The quad is planar and always turned to face the camera, so only one of its
	# two triangles can ever be front-facing whichever way it is wound. Disabling
	# the cull rasterises nothing extra and takes winding off the list of things
	# that can silently blank the effect on a build nobody can step through.
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_eye_mat = m

	# Build the meshes here too. This is called from the warm-up pass, which runs
	# behind the title screen, so the first zombie of the run draws a vertex
	# buffer that is already resident instead of uploading one mid-round.
	for k in EYE_PX.keys():
		var eye_kind: String = k
		for p in EYE_TINT.size():
			_eye_mesh(eye_kind, p)
	return _eye_mat


## A baked gradient, not a shader. WebGL2 exposes no program-binary API, so every
## new `Shader` is a main-thread GLSL compile the first time it is drawn; a
## texture generated once at startup costs one upload and nothing after.
##
## The ramp is the ancestor's two nested rects — a solid core inside a halo at
## alpha 0.28 (html:940) — smoothed out, because a hard-edged square reads as a
## square once it is additive and blooming instead of four pixels of a 48x64
## sprite. The core lands at 40% of the radius, which on the 4.6 px walker
## footprint is the 2 px core the ancestor actually drew.
##
## White, with the whole falloff in alpha: nothing here then depends on whether
## an RGBA8 texture is decoded as sRGB, because the hue comes from the mesh.
static func _eye_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.40, 0.52, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.85),
		Color(1.0, 1.0, 1.0, 0.28),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


## One mesh per kind-and-palette, cached forever. Hounds ignore `pal` for the
## same reason `SpriteLib.frames_for` does: `SPEC.hound.pal` is 0, so there is
## only one hound body and there should only be one pair of hound eyes.
static func _eye_mesh(p_kind: String, p_pal: int) -> ArrayMesh:
	var key: String = p_kind if p_kind == "hound" else "%s%d" % [p_kind, p_pal]
	if _eye_meshes.has(key):
		var cached: ArrayMesh = _eye_meshes[key]
		return cached

	var geo: Dictionary = EYE_PX[p_kind]
	var row_sep: float = geo.sep
	var row_x: float = geo.x
	var row_glow: float = geo.glow
	var px := SpriteLib.pixel_size(p_kind)
	var half := row_sep * 0.5 * px
	var off := row_x * px
	var s := row_glow * 0.5 * px

	var tint: Color = EYE_TINT_HOUND if p_kind == "hound" else EYE_TINT[p_pal]
	# The material does not flag its vertex colours as sRGB, so convert here
	# instead of handing the renderer an sRGB hue it will read as linear.
	var col := tint.srgb_to_linear()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_eye_quad(st, col, off - half, s)
	_eye_quad(st, col, off + half, s)
	var mesh := st.commit()
	_eye_meshes[key] = mesh
	return mesh


## Two triangles centred on `ox`, in the billboard's local space: +X is camera
## right, +Y camera up, +Z toward the viewer. Both eyes live in one mesh so a
## zombie costs one draw call for the pair rather than two.
static func _eye_quad(st: SurfaceTool, col: Color, ox: float, s: float) -> void:
	var bl := Vector3(ox - s, -s, EYE_FORWARD)
	var br := Vector3(ox + s, -s, EYE_FORWARD)
	var tr := Vector3(ox + s, s, EYE_FORWARD)
	var tl := Vector3(ox - s, s, EYE_FORWARD)
	_eye_vertex(st, col, bl, Vector2(0.0, 1.0))
	_eye_vertex(st, col, br, Vector2(1.0, 1.0))
	_eye_vertex(st, col, tr, Vector2(1.0, 0.0))
	_eye_vertex(st, col, bl, Vector2(0.0, 1.0))
	_eye_vertex(st, col, tr, Vector2(1.0, 0.0))
	_eye_vertex(st, col, tl, Vector2(0.0, 0.0))


static func _eye_vertex(st: SurfaceTool, col: Color, p: Vector3, uv: Vector2) -> void:
	st.set_normal(Vector3(0.0, 0.0, 1.0))
	st.set_color(col)
	st.set_uv(uv)
	st.add_vertex(p)


## Height of the eye row off the floor. `SpriteLib.pixel_size()` is
## `HEIGHT[kind]` over the cell height, so this is the body's own geometry rather
## than a tuned number: 1.40 m on a 1.82 m walker, inside the head region
## `head_threshold()` opens at 1.27 m, and 0.34 m on a crawler — which drags its
## head along the floor, and would have had its eyes hovering somewhere over its
## back if the walker's fraction had simply been reused. The crawler's row sits a
## couple of centimetres under its own `head_threshold()`; that threshold is a
## hit-registration band, not a measurement of where the art put the skull.
func _eye_height() -> float:
	var geo: Dictionary = EYE_PX[kind]
	var row: float = geo.y
	return _height - row * SpriteLib.pixel_size(kind)


## Distance from the node origin to the furthest eye vertex, which is how far the
## billboard can swing the geometry outside the mesh's own AABB.
func _eye_span() -> float:
	var geo: Dictionary = EYE_PX[kind]
	var row_x: float = geo.x
	var row_sep: float = geo.sep
	var row_glow: float = geo.glow
	return (absf(row_x) + row_sep * 0.5 + row_glow * 0.5) * SpriteLib.pixel_size(kind)


# --- alpha-edge rim ----------------------------------------------------------

## The colour the ancestor already used for light that is not a lamp: the stars
## it stipples into the night ceiling, `rgba(190,200,220)` (html:781), which is
## also within ten parts of the ones behind every window barricade (html:809).
## Cold, because everything else lighting this map is sodium.
const RIM_TINT := Color(190.0 / 255.0, 200.0 / 255.0, 220.0 / 255.0)

## Deliberately under the environment's `glow_hdr_threshold` (set in
## `main.gd::_setup_environment`, currently 0.92) rather than over it. The eyes
## are meant to bloom — they are two dots. A whole silhouette pushed past the
## bleed threshold smears the zombie into a lamp, and the point of the effect is
## the edge, not a halo. 0.62 x the brightest channel is 0.535, so the rim reads
## as a cold edge on an unlit wall and never blooms on its own. Invented; this is
## the knob if it does not read on the target.
const RIM_ENERGY := 0.62

## Same 2 cm and the same reason as EYE_FORWARD: the overlay is a second draw of
## the *same* quad, so without an offset it is exactly coplanar with the sprite
## and loses the depth test to it on every fragment.
const RIM_FORWARD := 0.02

## A billboard cannot be rim-lit by fresnel. `NORMAL` is constant across a flat
## quad, so `dot(NORMAL, VIEW)` is constant, so every fresnel shader ever written
## for this produces a uniform tint over the whole sprite rather than an edge.
## The silhouette lives in the texture's alpha channel, so the edge has to be
## found by sampling neighbouring texels — four taps, thresholded at exactly the
## sprite's own alpha scissor so the rim traces the figure and not the quad.
##
## What it lights is already there. `outlineSprite()` (html:955-969) stamps a 1px
## ring of `rgba(6,6,5,205)` on the *transparent* side of every silhouette, and
## 205/255 clears the 0.35 scissor — so that ring is drawn, it is simply black. A
## black rim reads against a light background, which is what a flat-lit raycaster
## had and this map does not. The four-tap inner edge selects that exact ring, so
## this does not add an outline: it turns the one the art already carries from
## dark to cold.
##
## `INV_VIEW_MATRIX` rather than `MAIN_CAM_INV_VIEW_MATRIX`, which is what
## Godot's own generated billboard code uses. The two differ only during shadow
## and reflection passes, and an additively-blended surface enters neither; the
## trade is deliberate, because M-BILLBOARD records that whether the newer
## built-in even compiles under gl_compatibility is unverified, and a shader that
## fails to compile is a magenta zombie in a build nobody here can step through.
##
## The horizontal taps are clamped inside the current frame's own column of the
## strip. Frames are packed edge to edge, so an unclamped tap at a frame boundary
## samples the *next pose's* alpha and stamps a rim down the middle of nothing.
const RIM_CODE := """shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

uniform sampler2D rim_tex : filter_nearest, repeat_disable;
uniform vec3 rim_color : source_color = vec3(0.745, 0.784, 0.863);
uniform float rim_energy = 0.62;
uniform float cut = 0.35;
uniform float cols = 1.0;
uniform vec2 texel = vec2(1.0);
uniform float push_z = 0.02;

void vertex() {
	// BILLBOARD_FIXED_Y, reproduced: material_overlay is a second draw of the
	// same surface with a different material, and the billboard lives in the
	// material, so the sprite's own orientation is not inherited here.
	mat4 face = mat4(
		vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0),
		vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0),
		MODEL_MATRIX[3]);
	mat4 keep_scale = mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * face * keep_scale;
	// Local +Z is toward the viewer under that basis, so this is the same
	// coplanarity fix the eye quads bake into their vertices.
	VERTEX.z += push_z;
}

void fragment() {
	float hx = texel.x * 0.5;
	float hy = texel.y * 0.5;
	float fw = 1.0 / cols;
	float f0 = floor(UV.x * cols) * fw;
	float lo = f0 + hx;
	float hi = f0 + fw - hx;
	float xl = clamp(UV.x - texel.x, lo, hi);
	float xr = clamp(UV.x + texel.x, lo, hi);
	float yl = clamp(UV.y - texel.y, hy, 1.0 - hy);
	float yr = clamp(UV.y + texel.y, hy, 1.0 - hy);
	float a = step(cut, texture(rim_tex, UV).a);
	float l = step(cut, texture(rim_tex, vec2(xl, UV.y)).a);
	float r = step(cut, texture(rim_tex, vec2(xr, UV.y)).a);
	float u = step(cut, texture(rim_tex, vec2(UV.x, yl)).a);
	float d = step(cut, texture(rim_tex, vec2(UV.x, yr)).a);
	// Drawn, and with a transparent 4-neighbour: the outermost texel of the
	// figure, which is exactly the ring outlineSprite() stamped.
	float edge = a * (1.0 - min(min(l, r), min(u, d)));
	if (edge < 0.5) {
		discard;
	}
	ALBEDO = rim_color * rim_energy;
	// blend_add is SRC_ALPHA, ONE, so the contribution is ALBEDO * ALPHA and
	// the edge test above has already decided this fragment is on the rim.
	ALPHA = 1.0;
}
"""

## One `Shader` for every zombie in the game, and therefore one GLSL compile.
## This is the same bargain `eye_material()` makes and it matters more here: a
## ShaderMaterial per zombie would still be one program, but a *Shader* per
## zombie would be 24 compiles of identical source on a platform with no program
## cache, in the middle of a fight.
static var _rim_shader: Shader

## One ShaderMaterial per sprite strip — seventeen at most, and fewer, because
## crawlers and hounds cut their attack out of the walk strip. Keyed by the
## strip's own resource path, which is what makes that sharing fall out rather
## than have to be special-cased.
static var _rim_mats := {}


static func rim_shader() -> Shader:
	if _rim_shader != null:
		return _rim_shader
	var sh := Shader.new()
	sh.code = RIM_CODE
	_rim_shader = sh
	return sh


## The rim material for one animation of one body. Null when the strip is
## missing, which `SpriteLib._add_strip` already treats as a warning rather than
## a failure — a zombie with no art should still walk around, not crash the round.
static func rim_material(p_kind: String, p_pal: int, p_anim: String) -> ShaderMaterial:
	var frames := SpriteLib.frames_for(p_kind, p_pal)
	if frames.get_frame_count(p_anim) == 0:
		return null
	# The frames are AtlasTexture windows onto one strip, and Sprite3D bakes the
	# window into the quad's UVs — so handing the shader the whole strip and
	# reading UV straight off the mesh lands on exactly the texel the sprite
	# sampled, with no per-frame uniform to keep in step.
	var at := frames.get_frame_texture(p_anim, 0) as AtlasTexture
	if at == null or at.atlas == null:
		return null
	var strip := at.atlas
	var key := strip.resource_path
	if _rim_mats.has(key):
		var cached: ShaderMaterial = _rim_mats[key]
		return cached

	var spec: Dictionary = SpriteLib.SPEC[p_kind]
	var cell: float = spec.w
	var w := float(strip.get_width())
	var h := float(strip.get_height())

	var m := ShaderMaterial.new()
	m.shader = rim_shader()
	m.set_shader_parameter("rim_tex", strip)
	m.set_shader_parameter("rim_color", RIM_TINT)
	m.set_shader_parameter("rim_energy", RIM_ENERGY)
	m.set_shader_parameter("cut", ALPHA_SCISSOR)
	# Frames per strip, taken from the image rather than from the animation:
	# `SPEC.crawler` has no attack entry, so its attack animation holds two
	# frames of a strip that is four frames wide, and clamping to the animation's
	# count would put the frame boundary in the wrong place on every tap.
	m.set_shader_parameter("cols", w / cell)
	m.set_shader_parameter("texel", Vector2(1.0 / w, 1.0 / h))
	m.set_shader_parameter("push_z", RIM_FORWARD)
	_rim_mats[key] = m
	return m


## Every rim material, built up front, for the warm-up pass — and, as a side
## effect, every sprite strip loaded and resident before the first spawn instead
## of on it. `frames_for` caches, so this costs one decode of each of the
## seventeen PNGs at load rather than one mid-round.
static func rim_materials() -> Array:
	var out: Array = []
	for k: String in SpriteLib.SPEC.keys():
		var spec: Dictionary = SpriteLib.SPEC[k]
		var pals: int = spec.pal
		# `SPEC.hound.pal` is 0 and `frames_for` ignores `pal` for it, exactly as
		# the eye meshes do, so one hound is one hound.
		for p in maxi(1, pals):
			for anim: String in ["walk", "attack", "death"]:
				var m := rim_material(k, p, anim)
				if m != null and not out.has(m):
					out.append(m)
	return out
