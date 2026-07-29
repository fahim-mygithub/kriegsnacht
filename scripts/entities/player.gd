class_name Player
extends CharacterBody3D

## First-person controller.
##
## Node chain is deliberate, and the rule is **one writer per node**:
##   Player      yaw                — mouse only
##   └ Head      pitch / eye height — mouse writes the rotation, stance the height
##     └ RecoilPivot                — recoil spring and shake only
##       └ Camera3D                 — view bob translation only
## Godot composes parent/child transforms every frame, so "additive" is free.
## Recoil used to be written straight into the camera's own rotation.x, which the
## next mouse-motion event then overwrote — that single shared writer was the
## whole recoil bug, and no amount of better maths would have fixed it.
##
## Mouse capture is the one place the port is strictly better than the original:
## the browser build needed a capture chip, a pointer-lock error path and an
## idle-cursor timer because artifacts run in a sandboxed iframe that can refuse
## pointer lock outright. Here it is one call to Input.set_mouse_mode().

signal health_changed(hp: float, max_hp: float)
signal weapon_changed(gun: Dictionary)
## Fired for every state transition of every gun the player carries, stowed ones
## included, so a viewmodel can drive animation from the machine rather than from a
## pile of inferred floats. `from` and `to` are Weapon.State values. Separate from
## weapon_changed because that signal means "the ammo readout is stale" and is
## already bound to that meaning in hud.gd.
signal weapon_state_changed(gun: Dictionary, from: int, to: int)
signal downed_changed(is_down: bool, time_left: float)
signal died
signal fired(muzzle: Vector3)
## A melee swing actually landed. Separate from the key press because _knife()
## refuses most presses on its cooldown, and a viewmodel driven by the input would
## animate the refused ones too.
signal knifed
signal hit_confirmed(headshot: bool, killed: bool)
## Same event as hit_confirmed, plus the world-space point. Kept separate because
## the HUD only ever needed the two flags and is already bound to that shape; the
## FX layer needs somewhere to put the blood puff.
signal impact(at: Vector3, headshot: bool, killed: bool)
## Where a round stopped on something that was not a zombie, and the surface normal
## it stopped against. Emitted once per pellet. Until this existed a shot that
## missed produced nothing at all — no sound, no mark, no dust — so the only
## feedback the game gave for firing was the feedback for hitting.
signal surface_impact(at: Vector3, normal: Vector3)

## The state machine every gun runs on. preload rather than the class name: a
## freshly added script is not in the class registry until the editor rescans, and a
## headless run has no editor.
const WEAPON := preload("res://scripts/entities/weapon.gd")

const SPEED := 3.15
const SPRINT_MULT := 1.55
const DOWNED_SPEED := 1.15
const RADIUS := 0.24
const EYE := MapData.EYE
const MOUSE_SENS := 0.0022

## The ancestor had no camera to lower, so it sheared the raycaster's horizon down
## 17% of screen height instead (kriegsnacht.html:1748). Converted: 0.17 H is 0.34 of
## a half-screen, and at this camera's 74° vertical FOV a half-screen spans
## tan(37°) = 0.754 world units per metre of depth, so the shear is worth a drop of
## 0.256 m per metre of range — ~1.15 m at the ~4.5 m a zombie gets engaged from.
## EYE - 1.15 = 0.40, which is also literally what the shear stood in for: you are
## on the floor.
const DOWNED_EYE := 0.40
## Fall and stand at ~0.36 s over that 1.15 m. The ancestor's shear was a boolean
## and snapped; a 1.15 m teleport of a real camera reads as a glitch, not a fall.
const DOWNED_EYE_RATE := 3.2

const REGEN_DELAY := 3.4
const REGEN_RATE := 0.34          # fraction of max health per second
const PITCH_LIMIT := deg_to_rad(85)

## Sprint is no longer free and infinite. That, plus zombies that can now block
## the player, is what makes the game losable — a 4.88 m/s sprint against a
## 3.45 m/s ceiling meant nothing could ever catch you.
const SPRINT_DRAIN := 1.0 / 4.2   # full bar lasts ~4.2 s
const SPRINT_RECOVER := 1.0 / 4.0
const SPRINT_FLOOR := 0.15        # must recover this far before sprinting again
const SPRINT_OUT := 0.25          # weapon-raise delay after sprinting

## How long a trigger pull is remembered when the weapon cannot answer it yet.
## Unchanged from Milestone 1, where it fixed the discarded semi-auto click: it is
## comfortably longer than the fastest interval in the table (the PM63's 0.06 s) and
## well under a deliberate double-tap, so no click is eaten and none is doubled.
const FIRE_BUFFER := 0.18

## Per-attacker grace window. One global cooldown capped the entire horde at a
## single zombie's damage output, which is why a pile of six was survivable.
const HURT_IGNORE := 0.4

## Damped oscillator, tuned in the browser build and carried across verbatim.
const KICK_SPRING := 46.0
const KICK_DAMP := 11.0

const BOB_POS := 9.4
const BOB_ROLL := 13.0
const BOB_SLOW := 2.2

var hp := 100.0
var guns: Array[Dictionary] = []
var slot := 0
var has_bowie := false
var is_downed := false
var downed_time := 0.0

var _head: Node3D
var _recoil_pivot: Node3D
var _cam: Camera3D
var _torch: SpotLight3D
var _regen_wait := 0.0
var _fire_held := false
var _fire_buffer := 0.0
var _knife_cooldown := 0.0

var _kick := 0.0
var _kick_v := 0.0
var _shake := 0.0
var _bob_phase := 0.0
var _moving := false

var _stamina := 1.0
var _sprinting := false

## attacker instance id -> seconds until that attacker may hurt us again
var _hurt_gate := {}

var world: Node3D


func _ready() -> void:
	# PROCESS_MODE_ALWAYS, on this node only. The resume click has to reach
	# `_unhandled_input`, and Godot gates input propagation on `can_process()`
	# exactly as it gates `_process` — a pausable player never sees the one event
	# that can leave the pause, because pointer lock needs transient activation and
	# so the answer has to come from inside the event. `_physics_process` below
	# early-returns on the state instead, which it has to do anyway for the title
	# screen, where the tree is deliberately not paused.
	process_mode = Node.PROCESS_MODE_ALWAYS

	collision_layer = 2
	# Walls and enemies. Zombies could previously be walked through, so no
	# amount of horde pressure could ever corner the player.
	collision_mask = 1 | 4
	floor_max_angle = deg_to_rad(70)

	var caps := CapsuleShape3D.new()
	caps.radius = RADIUS
	caps.height = 1.7
	var cs := CollisionShape3D.new()
	cs.shape = caps
	cs.position.y = 0.85
	add_child(cs)

	_head = Node3D.new()
	_head.name = "Head"
	_head.position.y = EYE
	# ...and everything below the player is pausable again. `process_mode` is
	# inherited, so ALWAYS on the player alone would hand it to the whole camera
	# chain and to the viewmodel hanging off the end of it — which would go on
	# swaying, bobbing and decaying its recoil spring behind the pause overlay.
	# Nothing under here needs to run while paused; only the input does.
	_head.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_head)

	_recoil_pivot = Node3D.new()
	_recoil_pivot.name = "RecoilPivot"
	_head.add_child(_recoil_pivot)

	_cam = Camera3D.new()
	_cam.fov = 74.0
	_cam.near = 0.05
	_cam.far = 60.0
	_recoil_pivot.add_child(_cam)

	# Stands in for the browser build's per-pixel flashlight falloff LUT.
	_torch = SpotLight3D.new()
	# The one shadow-casting light in the game. On this renderer each shadowed
	# light re-draws every instance it touches, and a spot needs one shadow pass
	# where an omni in cubemap mode would need six — so the torch is the only
	# affordable candidate. Shadowed lights also blend in sRGB rather than
	# linear, which reads brighter, hence the energy coming down from 3.2.
	# 3.4 -> 3.1 holds the near field where it was. 3.1*d^-1.25 = 3.4*d^-1.40 at
	# d = 1.85 m, so the wall you are pressed against does not get brighter and
	# everything past arm's reach gets a little more reach. The mandate's "retune
	# the energy downward for sRGB shadow blending" was already spent in Milestone
	# 1 — 3.4 was chosen with shadows already on — so this is a second, smaller
	# move for a different reason, not a repeat of that one.
	_torch.light_energy = 3.1
	_torch.light_color = Color(1.0, 0.94, 0.82)
	_torch.spot_range = 18.0
	# Step 4 of the lighting pass (see scripts/world/lighting.gd). 38 -> 34 degrees
	# is the mandate: a tighter cone is more torch and less floodlight, and Godot's
	# spot does not renormalise for angle, so narrowing removes light from the
	# periphery without brightening the centre.
	_torch.spot_angle = 34.0
	# 1.4 -> 1.25 buys some of that back as *reach* rather than as width. The
	# distance term is d^-attenuation, so a lower exponent lifts the far field:
	# about +24% at 8 m. That matters because ambient just fell to 0.15 and the
	# lamps to 0.80, and the torch is the only light the player steers.
	_torch.spot_attenuation = 1.25
	_torch.shadow_enabled = true
	_torch.shadow_bias = 0.04
	_cam.add_child(_torch)

	guns = [Weapons.make_gun("m1911", false)]
	hp = Game.max_health()
	health_changed.emit(hp, Game.max_health())
	weapon_changed.emit(current_gun())


func camera() -> Camera3D:
	return _cam


func current_gun() -> Dictionary:
	return guns[slot] if slot < guns.size() else guns[0]


func stamina() -> float:
	return _stamina


# --- input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		_head.rotation.x = clampf(_head.rotation.x - event.relative.y * MOUSE_SENS,
			-PITCH_LIMIT, PITCH_LIMIT)

	if event.is_action_pressed("toggle_capture"):
		set_capture(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)

	# A release is honoured in every state, and it has to be, because both guards
	# below return early: letting go of the trigger while the game was not running
	# was swallowed outright and left the latch armed. Hold an automatic, pause,
	# release, then resume with L — which recovers the pointer, and the HUD reads a
	# recovered pointer as the resume — and the gun fired on its own until the
	# button had been cycled again. The resume-click path clears the latch too, but
	# it is only one of the two ways back into play.
	if event.is_action_released("fire"):
		_fire_held = false

	# Resume is a click, and it has to be answered from inside the event, because
	# pointer lock needs transient activation: a re-capture asked for from _process
	# is the documented prohibited pattern and can never work in a browser. Escape
	# cannot do it either — the HTML spec excludes Escape from the events that grant
	# activation, which is why "press Escape to resume" was unfixable rather than
	# merely broken. The HUD owns the other half of the contract: losing the pointer
	# lock is what pauses. Nothing here pauses.
	if Game.state == Game.STATE_PAUSE:
		var click := event as InputEventMouseButton
		# Wheel ticks arrive as InputEventMouseButton too, and a wheel event grants
		# no activation, so a scroll would set the state to play against a pointer
		# that never re-locked — and the HUD would pause again a frame later.
		if click != null and click.pressed and click.button_index <= MOUSE_BUTTON_MIDDLE:
			set_capture(true)
			Game.set_state(Game.STATE_PLAY)
			# The resume click must not also be a trigger pull, so drop it here and
			# return before the fire block below — the state is play again by now,
			# so the guard underneath would let it straight through. Clearing the
			# latch matters too: an automatic held down at the moment the window
			# lost focus would otherwise fire the instant the state flipped back.
			_fire_held = false
			_fire_buffer = 0.0
			get_viewport().set_input_as_handled()
		return

	if Game.state != Game.STATE_PLAY:
		return

	if event.is_action_pressed("fire"):
		# In play a loose pointer means one of three things, and firing is right in
		# all three: the browser has not granted the lock start_game() asked for yet;
		# it refused outright, which a sandboxed iframe does and which the capture
		# chip at the top of this file exists to survive; or nothing is driving a
		# real mouse at all (headless, or the MCP input service). Consuming the click
		# instead would mean those players — and every automated run — can never fire
		# once, and the view has not moved either, so the crosshair is still exactly
		# where they aimed. Only the *resume* click above is not a trigger pull, and
		# only because it was aimed at an overlay.
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			set_capture(true)
		_fire_held = true
		# Buffer the click rather than consuming it immediately. A press landing
		# during the fire cooldown used to be discarded outright, so clicking
		# faster than the weapon's rate silently ate inputs.
		_fire_buffer = FIRE_BUFFER

	if event.is_action_pressed("reload"):
		_start_reload()
	if event.is_action_pressed("knife"):
		_knife()
	if event.is_action_pressed("swap_weapon") and guns.size() > 1:
		_swap_weapon()


static func set_capture(on: bool) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE)


# --- movement ----------------------------------------------------------------

func _physics_process(dt: float) -> void:
	# Not redundant with `get_tree().paused`, and this node is the one place in the
	# game where it is not: the player processes while paused so the resume click
	# can land, and the title screen does not pause the tree at all — the warm-up
	# pass runs there. Both are states in which nothing below may move.
	if Game.state != Game.STATE_PLAY:
		return

	_knife_cooldown = maxf(0.0, _knife_cooldown - dt)
	_fire_buffer = maxf(0.0, _fire_buffer - dt)
	_tick_hurt_gate(dt)

	if is_downed:
		downed_time -= dt
		downed_changed.emit(true, downed_time)
		if downed_time <= 0.0:
			died.emit()
			return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	# Strafe rides the camera's own right vector. Deriving it from the basis
	# instead of hand-rolling a perpendicular is what keeps A/D from inverting —
	# that exact bug bit the browser build.
	var dir := (transform.basis.x * input.x + transform.basis.z * input.y)
	dir.y = 0.0
	dir = dir.normalized()
	_moving = dir.length_squared() > 0.001

	var spd := DOWNED_SPEED if is_downed else SPEED
	_update_sprint(dt, _moving and not is_downed)
	if _sprinting:
		spd *= SPRINT_MULT

	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	velocity.y = 0.0
	move_and_slide()

	# Health regen, unchanged from the browser build's curve.
	if not is_downed:
		_regen_wait += dt
		if _regen_wait >= REGEN_DELAY and hp < Game.max_health():
			hp = minf(Game.max_health(), hp + Game.max_health() * REGEN_RATE * dt)
			health_changed.emit(hp, Game.max_health())

	_update_view(dt, spd)
	_update_fire(dt)


func _update_sprint(dt: float, wants_move: bool) -> void:
	var held := Input.is_action_pressed("sprint") and wants_move
	if held and _stamina > 0.0 and (_sprinting or _stamina > SPRINT_FLOOR):
		if not _sprinting:
			_sprinting = true
		_stamina = maxf(0.0, _stamina - SPRINT_DRAIN * dt)
		if _stamina <= 0.0:
			_stop_sprint()
	else:
		if _sprinting:
			_stop_sprint()
		_stamina = minf(1.0, _stamina + SPRINT_RECOVER * dt)


func _stop_sprint() -> void:
	if not _sprinting:
		return
	_sprinting = false
	# The raise is a weapon state rather than a bare float on the player, so a
	# viewmodel can animate it and so it arbitrates against the reload and the draw
	# instead of quietly overlapping them.
	var gun := current_gun()
	var was: int = gun.state
	WEAPON.begin_sprint_out(gun, SPRINT_OUT)
	_weapon_state(gun, was)


## Recoil spring, downed eye height, view bob and shake. Every one of these writes
## a transform component nobody else writes — Head's height is not Head's pitch —
## so none of them can be clobbered by mouse look.
func _update_view(dt: float, spd: float) -> void:
	# Properly integrated damped oscillator — the ancestor's model, and a better
	# feel than the two-lerp approximation most Godot FPS templates use.
	_kick_v += (-_kick * KICK_SPRING - _kick_v * KICK_DAMP) * dt
	_kick += _kick_v * dt
	_shake = maxf(0.0, _shake - dt * 2.2)

	# The downed drop rides Head's *position*, which is the only place in the chain
	# it can go: everything below Head sits inside the pitch rotation, so a drop
	# applied there would stop pointing down the moment you looked up, and the two
	# nodes under it are already owned by recoil and by the bob. Head's rotation
	# stays the mouse's alone; nothing but this line writes its height.
	var eye := DOWNED_EYE if is_downed else EYE
	_head.position.y = move_toward(_head.position.y, eye, DOWNED_EYE_RATE * dt)

	if _moving:
		_bob_phase += dt * spd

	# X and Y ride different functions — that asymmetry is what reads as a
	# figure-eight rather than a pendulum.
	var amp := 0.0 if not _moving else (0.020 * spd / SPEED)
	var bob_x := sin(_bob_phase * BOB_POS) * amp
	var bob_y := absf(cos(_bob_phase * BOB_POS * 0.5)) * amp * 0.8
	_cam.position = Vector3(bob_x, bob_y, 0.0)

	# Shake reads as roll rather than translation, so it does not fight the bob.
	var roll := sin(_bob_phase * BOB_ROLL) * amp * 0.35 + _shake * 0.05
	var slow := sin(_bob_phase * BOB_SLOW) * amp * 0.5
	_recoil_pivot.rotation = Vector3(_kick + slow, 0.0, roll)


func add_shake(amount: float) -> void:
	_shake = minf(1.6, _shake + amount)


## Every transition runs through Weapon; this is the one place the resulting signal
## goes out, so a listener cannot miss one that some other path happened to make.
func _weapon_state(gun: Dictionary, was: int) -> void:
	var now: int = gun.state
	if now != was:
		weapon_state_changed.emit(gun, was, now)


func _update_fire(dt: float) -> void:
	var cur := slot if slot < guns.size() else 0
	var gun: Dictionary = guns[cur]
	# Automatics fire while held; everything else needs a fresh press, but a
	# press that arrives mid-cooldown stays buffered instead of being dropped.
	var want := _fire_held if gun.def.auto else _fire_buffer > 0.0

	# Every gun the player is carrying advances, not just the one in hand. The
	# ancestor ticked `P.guns[P.slot]` alone (html:2966), so a stowed weapon froze
	# mid-reload — indefinitely — and resumed exactly where it stopped when you
	# switched back. Nothing cleared it either, so the freeze was the whole of its
	# behaviour rather than a deliberate cancel.
	#
	# A stowed gun can no longer *be* mid-reload: holstering cancels it, per Call of
	# Duty (see Weapon.stow_cancels). What ticking every gun buys now is the
	# remainder of it — the fire-rate cooldown a weapon was carrying when it went
	# away, which should keep running while it is on your back rather than waiting
	# to be observed.
	for i in guns.size():
		var g: Dictionary = guns[i]
		var was: int = g.state
		var mag_was: int = g.mag
		# Only the weapon actually being asked for rounds keeps its sub-tick
		# remainder — see Weapon.tick.
		WEAPON.tick(g, dt, i == cur and want and WEAPON.can_fire(g))
		_weapon_state(g, was)
		if int(g.mag) != mag_was:
			# Nothing inside a tick can *spend* ammunition, so a magazine that grew
			# is a reload landing — one magazine, or one shell of a shotgun's tube,
			# which is why the click comes from here rather than from a completion
			# callback that would fire once for six shells.
			Sfx.play("reload_in", -12.0)
			# Always the gun in hand: hud.gd puts this argument straight into the
			# main ammo readout, and a stowed weapon belongs on the [Q] line.
			weapon_changed.emit(current_gun())

	if not want:
		return
	# Firing brings the weapon up out of a sprint rather than doing nothing; the
	# shot itself waits for SPRINT_OUT below.
	if _sprinting:
		_stop_sprint()
		return
	if not WEAPON.can_fire(gun):
		var state: int = gun.state
		if state == WEAPON.State.SPRINT_OUT or state == WEAPON.State.SWAPPING:
			# The intent has to outlive the transient. SPRINT_OUT is 0.25 s against a
			# 0.18 s buffer, so a semi-auto shot asked for at the end of a sprint was
			# dropped outright — the queue expired before the weapon came back up,
			# and the same held for a shot asked for during a swap.
			var left: float = gun.state_t
			_fire_buffer = maxf(_fire_buffer, left + FIRE_BUFFER)
		return
	# A shotgun's shell reload is interrupted by the trigger, and the shells already
	# in the tube stay there. That asymmetry is most of the reason to load shell by
	# shell at all, and it is the one thing a state machine expresses that four
	# independent floats could not.
	if gun.state == WEAPON.State.RELOAD_SHELL:
		var was_reloading: int = gun.state
		WEAPON.settle(gun)
		_weapon_state(gun, was_reloading)
		weapon_changed.emit(gun)

	# Bounded rather than single, because one shot per tick silently caps any weapon
	# whose interval is under 1/60 s at 60 rpm. Nothing in the table is that fast, so
	# this runs once today; it is a bound against a future weapon or a lowered tick
	# rate, not a feature.
	var shots := 0
	while shots < WEAPON.MAX_SHOTS_PER_TICK:
		var still_want := _fire_held if gun.def.auto else _fire_buffer > 0.0
		if not still_want or float(gun.next_shot) > 0.0:
			break
		if int(gun.mag) <= 0:
			Sfx.play("empty", -14.0)
			# The lockout is what stops that click repeating sixty times a second
			# while an automatic is held down. It touches the cooldown only, so the
			# state transition below is _start_reload's alone to emit.
			WEAPON.dry_fire(gun)
			# html:2516 — the ancestor only reaches for a reload when there is
			# something to reload with, and with an empty reserve the click is the
			# whole answer.
			_start_reload(false)
			break
		_fire_buffer = 0.0
		_shoot(gun)
		shots += 1


func _shoot(gun: Dictionary) -> void:
	var def: Dictionary = gun.def
	var was: int = gun.state
	WEAPON.consume_shot(gun, Game.rpm_scale())
	_weapon_state(gun, was)
	# Into the spring, not into the camera. The old code added straight to
	# _cam.rotation.x with nothing to pull it back, so a 100-round RPK magazine
	# walked the view up about 30 degrees and left it there.
	_kick_v -= def.kick * 0.55
	add_shake(def.kick * 0.06)
	Sfx.play_shot(gun.key + ("_p" if gun.pap else ""), def.freq, def.thump, def.body)
	fired.emit(_cam.global_position - _cam.global_transform.basis.z * 0.35)

	if def.cone > 0.0:
		_cone_blast(def)
	else:
		for i in int(def.pellets):
			_hitscan(def)

	weapon_changed.emit(gun)
	if int(gun.mag) <= 0:
		# Not a manual request, so a dead reserve leaves the weapon bolt-locked in
		# silence here rather than clicking at you the instant it runs dry. The
		# trigger's own dry-fire path is where that click belongs.
		_start_reload(false)


## Accuracy degrades while moving and while downed, as it did in the ancestor.
func _spread_rad(def: Dictionary) -> float:
	var s: float = def.spread
	if _moving:
		s *= 1.5
	if is_downed:
		s *= 1.4
	return deg_to_rad(s) * 0.5


func _hitscan(def: Dictionary) -> void:
	var space := get_world_3d().direct_space_state
	var origin := _cam.global_position
	var basis := _cam.global_transform.basis
	var aim := -basis.z

	# Sample the cone in polar coordinates. Rotating by two independent axis
	# angles — which is what this did before — samples a *square*, so the spread
	# was about 1.41x wider on the diagonals than along the axes.
	var spread := _spread_rad(def)
	if spread > 0.0:
		var a := Rng.randf(Rng.VISUAL) * TAU
		var r := sqrt(Rng.randf(Rng.VISUAL)) * spread
		aim = aim.rotated(basis.x, sin(a) * r).rotated(basis.y, cos(a) * r)

	var pierce: int = int(def.get("pierce", 1))
	var exclude: Array[RID] = [get_rid()]
	var dmg: float = def.dmg * Game.damage_scale()

	for p in pierce:
		var q := PhysicsRayQueryParameters3D.create(origin, origin + aim * def.range)
		q.collision_mask = 1 | 4        # world and enemies
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return
		var body = hit.collider
		if body is Zombie:
			# Everything out of the hit dictionary is Variant, so annotate the point
			# rather than inferring it.
			var at: Vector3 = hit.position
			_apply_hit(body, dmg, at)
			exclude.append(body.get_rid())
		else:
			# World geometry stops the round — and says so. Every pellet reports
			# separately, because a shotgun's six marks spread across a wall are the
			# only thing on screen that shows the spread cone is real.
			var wall_at: Vector3 = hit.position
			var wall_n: Vector3 = hit.normal
			surface_impact.emit(wall_at, wall_n)
			return


## The Thundergun's instant cone — no projectile, everything in the wedge dies.
func _cone_blast(def: Dictionary) -> void:
	var fwd := -_cam.global_transform.basis.z
	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or z.state == Zombie.State.DYING:
			continue
		var to = z.centre() - _cam.global_position
		if to.length() > def.range:
			continue
		if fwd.dot(to.normalized()) < 1.0 - def.cone:
			continue
		# The cone has no ray and therefore no hit point, so aim the one _apply_hit
		# needs at the head: same world-space height the wedge always used, which
		# keeps its headshot payout exactly as it was. A centimetre *inside* the
		# head, not exactly on the threshold, because _apply_hit recovers the local
		# height as `at.y - z.global_position.y` and (y + t) - y is only exactly t
		# while the body's y is exactly zero — the same reason _knife aims a
		# centimetre under the threshold rather than at it.
		var at: Vector3 = z.global_position + Vector3(0.0, z.head_threshold() + 0.01, 0.0)
		_apply_hit(z, 1e9, at)


## `at` is the world-space point the shot landed on. The height decides the
## headshot; the other two components exist only so the puff can be put where the
## round actually went in rather than at the zombie's origin.
func _apply_hit(z: Zombie, dmg: float, at: Vector3) -> void:
	var local_y := at.y - z.global_position.y
	var headshot := local_y >= z.head_threshold()
	var killed := z.take_damage(dmg, local_y)
	if not killed:
		Game.add_points(Game.PTS_HIT)
	hit_confirmed.emit(headshot, killed)
	impact.emit(at, headshot, killed)


func _knife() -> void:
	if _knife_cooldown > 0.0:
		return
	_knife_cooldown = 0.55
	knifed.emit()
	Sfx.play("melee", -6.0)
	var fwd := -_cam.global_transform.basis.z
	var reach := 2.1 if has_bowie else 1.5
	var dmg := 1000.0 if has_bowie else 150.0
	# Pick the nearest valid target rather than whichever happened to sit first
	# in the group's arbitrary ordering.
	var best: Zombie = null
	var best_d := 1e9
	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or z.state == Zombie.State.DYING:
			continue
		var to = z.centre() - _cam.global_position
		# z comes back untyped from the group lookup, so annotate explicitly.
		var d: float = to.length()
		if d > reach or d >= best_d:
			continue
		if fwd.dot(to.normalized()) < 0.6:
			continue
		best = z
		best_d = d
	if best == null:
		return
	var killed := best.take_damage(dmg, best.head_threshold() - 0.01, true)
	hit_confirmed.emit(false, killed)
	# The knife deliberately cannot headshot — it damages one notch under the
	# threshold — so centre mass is where the blade landed.
	impact.emit(best.centre(), false, killed)


## `manual` is a deliberate press of the reload key, as opposed to the automatic
## attempt made when a magazine runs dry. Only a deliberate press earns the refusal
## cue: the automatic one fires on the same tick as the shot that emptied the gun,
## and a click there would arrive on top of the shot rather than as an answer to
## anything the player did.
func _start_reload(manual := true) -> void:
	var gun := current_gun()
	var was: int = gun.state
	if WEAPON.begin_reload(gun, Game.reload_scale()):
		Sfx.play("reload_out", -12.0)
		_weapon_state(gun, was)
		weapon_changed.emit(gun)
	elif manual and int(gun.res) <= 0 and int(gun.mag) < int(gun.def.mag):
		# The bolt-lock. This used to fail completely silently — the reload refused,
		# no state changed, and the player got no cue at all that the weapon was dead
		# rather than merely busy with something.
		Sfx.play("empty", -16.0)


## Swapping is no longer instantaneous and free. The ancestor flipped the slot at
## once and then refused the trigger for 0.42 s while the new weapon rose into frame
## (kriegsnacht.html:3293, gated at :2510, drawn at :3136) — and refused a second
## swap for the same window, which is what the guard below restores.
func _swap_weapon() -> void:
	var going := current_gun()
	if going.state == WEAPON.State.SWAPPING:
		return
	# Holstering cancels whatever the outgoing weapon was doing. Without this a
	# swap is a free reload: start a 4.6 s RPK, switch to the M1911, fight, and
	# come back to a full magazine you never paid for.
	var was: int = going.state
	WEAPON.stow_cancels(going)
	_weapon_state(going, was)
	slot = (slot + 1) % guns.size()
	_raise_current(WEAPON.SWAP_TIME)


## Brings whatever is now in hand up. Kept separate from the swap because a weapon
## handed over by a wall buy, the box or Pack-a-Punch is drawn from nothing rather
## than swapped to, and the ancestor timed that at 0.45 s (html:2667).
func _raise_current(duration: float) -> void:
	var gun := current_gun()
	var was: int = gun.state
	WEAPON.begin_swap(gun, duration)
	_weapon_state(gun, was)
	weapon_changed.emit(gun)


# --- damage ------------------------------------------------------------------

func _tick_hurt_gate(dt: float) -> void:
	if _hurt_gate.is_empty():
		return
	for id in _hurt_gate.keys():
		var t: float = _hurt_gate[id] - dt
		if t <= 0.0:
			_hurt_gate.erase(id)
		else:
			_hurt_gate[id] = t


## `from` identifies the attacker so each one carries its own cooldown. With a
## single global timer the whole horde shared one zombie's damage output, which
## is why standing in a pile of six was survivable.
func take_damage(amount: float, from := 0) -> void:
	if is_downed:
		return
	if from != 0 and _hurt_gate.has(from):
		return
	if from != 0:
		_hurt_gate[from] = HURT_IGNORE
	_regen_wait = 0.0
	hp -= amount
	Sfx.play("hurt", -8.0)
	add_shake(0.5)
	if hp <= 0.0:
		hp = 0.0
		_go_down()
	health_changed.emit(hp, Game.max_health())


func _go_down() -> void:
	if Game.revives_left > 0:
		Game.revives_left -= 1
		is_downed = true
		downed_time = Game.DOWNED_TIME
		downed_changed.emit(true, downed_time)
	else:
		died.emit()


## Solo Quick Revive: the bleedout is survived on its own once, rather than the
## perk simply delaying the same death. This was defined and called by nothing.
func revive() -> void:
	is_downed = false
	downed_time = 0.0
	hp = Game.max_health()
	_regen_wait = 0.0
	downed_changed.emit(false, 0.0)
	health_changed.emit(hp, Game.max_health())


func give_gun(key: String, pap := false) -> void:
	for i in guns.size():
		var held: Dictionary = guns[i]
		if held.key == key:
			guns[i] = Weapons.make_gun(key, pap or held.pap)
			slot = i
			_raise_current(WEAPON.DRAW_TIME)
			return
	if guns.size() < 2:
		guns.append(Weapons.make_gun(key, pap))
		slot = guns.size() - 1
	else:
		guns[slot] = Weapons.make_gun(key, pap)
	_raise_current(WEAPON.DRAW_TIME)


## Refills only the weapon named, so a wall buy stops silently topping up a
## Pack-a-Punched Ray Gun you happen to also be carrying.
func refill_gun(key: String) -> bool:
	for i in guns.size():
		var g: Dictionary = guns[i]
		if g.key == key:
			if int(g.res) >= int(g.def.res):
				return false
			g.res = int(g.def.res)
			_ammo_arrived(g)
			weapon_changed.emit(current_gun())
			return true
	return false


func refill_ammo() -> void:
	for i in guns.size():
		var g: Dictionary = guns[i]
		g.res = int(g.def.res)
		g.mag = int(g.def.mag)
		_ammo_arrived(g)
	weapon_changed.emit(current_gun())


## A bolt-locked weapon has to come off the lock the moment ammunition arrives, and
## the transition has to be announced or a viewmodel stays on the empty pose. Any
## other state is left exactly as it was, because a live reload settled here would
## be cancelled by its own Max Ammo.
func _ammo_arrived(gun: Dictionary) -> void:
	var was: int = gun.state
	WEAPON.on_ammo_added(gun)
	_weapon_state(gun, was)


func grid_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)
