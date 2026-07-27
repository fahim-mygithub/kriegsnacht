class_name Player
extends CharacterBody3D

## First-person controller.
##
## Mouse capture is the one place the port is strictly better than the original:
## the browser build needed a capture chip, a pointer-lock error path and an
## idle-cursor timer because artifacts run in a sandboxed iframe that can refuse
## pointer lock outright. Here it is one call to Input.set_mouse_mode().

signal health_changed(hp: float, max_hp: float)
signal weapon_changed(gun: Dictionary)
signal downed_changed(is_down: bool, time_left: float)
signal died

const SPEED := 3.15
const SPRINT_MULT := 1.55
const DOWNED_SPEED := 1.15
const RADIUS := 0.24
const EYE := MapData.EYE
const MOUSE_SENS := 0.0022
const REGEN_DELAY := 3.4
const REGEN_RATE := 0.34          # fraction of max health per second
const PITCH_LIMIT := deg_to_rad(85)

var hp := 100.0
var guns: Array[Dictionary] = []
var slot := 0
var has_bowie := false
var is_downed := false
var downed_time := 0.0
var self_revive_used := false

var _cam: Camera3D
var _torch: SpotLight3D
var _hurt_cooldown := 0.0
var _regen_wait := 0.0
var _fire_held := false
var _fire_queued := false
var _knife_cooldown := 0.0
var _recoil := 0.0

var world: Node3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(70)

	var caps := CapsuleShape3D.new()
	caps.radius = RADIUS
	caps.height = 1.7
	var cs := CollisionShape3D.new()
	cs.shape = caps
	cs.position.y = 0.85
	add_child(cs)

	_cam = Camera3D.new()
	_cam.position.y = EYE
	_cam.fov = 74.0
	_cam.near = 0.05
	_cam.far = 60.0
	add_child(_cam)

	# Stands in for the browser build's per-pixel flashlight falloff LUT.
	_torch = SpotLight3D.new()
	_torch.light_energy = 3.2
	_torch.light_color = Color(1.0, 0.94, 0.82)
	_torch.spot_range = 18.0
	_torch.spot_angle = 42.0
	_torch.spot_attenuation = 1.4
	_torch.shadow_enabled = false
	_cam.add_child(_torch)

	guns = [Weapons.make_gun("m1911", false)]
	hp = Game.max_health()
	health_changed.emit(hp, Game.max_health())
	weapon_changed.emit(current_gun())


func camera() -> Camera3D:
	return _cam


func current_gun() -> Dictionary:
	return guns[slot] if slot < guns.size() else guns[0]


# --- input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		_cam.rotation.x = clampf(_cam.rotation.x - event.relative.y * MOUSE_SENS, -PITCH_LIMIT, PITCH_LIMIT)

	if event.is_action_pressed("toggle_capture"):
		set_capture(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)

	if Game.state != Game.STATE_PLAY:
		return

	if event.is_action_pressed("fire"):
		_fire_held = true
		_fire_queued = true
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			set_capture(true)
	elif event.is_action_released("fire"):
		_fire_held = false

	if event.is_action_pressed("reload"):
		_start_reload()
	if event.is_action_pressed("knife"):
		_knife()
	if event.is_action_pressed("swap_weapon") and guns.size() > 1:
		slot = (slot + 1) % guns.size()
		weapon_changed.emit(current_gun())


static func set_capture(on: bool) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE)


# --- movement ----------------------------------------------------------------

func _physics_process(dt: float) -> void:
	if Game.state != Game.STATE_PLAY:
		return

	_hurt_cooldown = maxf(0.0, _hurt_cooldown - dt)
	_knife_cooldown = maxf(0.0, _knife_cooldown - dt)
	_recoil = maxf(0.0, _recoil - dt * 4.0)

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

	var spd := DOWNED_SPEED if is_downed else SPEED
	if not is_downed and Input.is_action_pressed("sprint"):
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

	_update_fire(dt)


func _update_fire(dt: float) -> void:
	var gun := current_gun()
	if gun.reloading > 0.0:
		gun.reloading -= dt
		if gun.reloading <= 0.0:
			_finish_reload(gun)
		return
	gun.next_shot = maxf(0.0, gun.next_shot - dt)

	# Automatics fire while held; everything else needs a fresh press.
	var want := _fire_held if gun.def.auto else _fire_queued
	_fire_queued = false
	if not want:
		return
	if gun.next_shot > 0.0:
		return
	if gun.mag <= 0:
		Sfx.play("empty", -14.0)
		_start_reload()
		return

	_shoot(gun)


func _shoot(gun: Dictionary) -> void:
	var def: Dictionary = gun.def
	gun.mag -= 1
	gun.next_shot = 60.0 / (def.rpm * Game.rpm_scale())
	_recoil = minf(1.0, _recoil + def.kick * 0.06)
	_cam.rotation.x = clampf(_cam.rotation.x + def.kick * 0.0035, -PITCH_LIMIT, PITCH_LIMIT)
	Sfx.play_shot(gun.key + ("_p" if gun.pap else ""), def.freq, def.thump, def.body)

	if def.cone > 0.0:
		_cone_blast(def)
	else:
		for i in int(def.pellets):
			_hitscan(def)

	weapon_changed.emit(gun)
	if gun.mag <= 0:
		_start_reload()


func _hitscan(def: Dictionary) -> void:
	var space := get_world_3d().direct_space_state
	var origin := _cam.global_position
	var spread := deg_to_rad(def.spread) * 0.5
	var aim := -_cam.global_transform.basis.z
	aim = aim.rotated(_cam.global_transform.basis.x, randf_range(-spread, spread))
	aim = aim.rotated(_cam.global_transform.basis.y, randf_range(-spread, spread))

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
			_apply_hit(body, dmg, hit.position.y)
			exclude.append(body.get_rid())
		else:
			return   # world geometry stops the round


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
		# _apply_hit wants a world-space Y, so lift the local head height.
		_apply_hit(z, 1e9, z.global_position.y + z.head_threshold())


func _apply_hit(z: Zombie, dmg: float, hit_y: float) -> void:
	var local_y := hit_y - z.global_position.y
	var killed := z.take_damage(dmg, local_y)
	if not killed:
		Game.add_points(Game.PTS_HIT)


func _knife() -> void:
	if _knife_cooldown > 0.0:
		return
	_knife_cooldown = 0.55
	Sfx.play("melee", -6.0)
	var fwd := -_cam.global_transform.basis.z
	var reach := 2.1 if has_bowie else 1.5
	var dmg := 1000.0 if has_bowie else 150.0
	for z in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(z) or z.state == Zombie.State.DYING:
			continue
		var to = z.centre() - _cam.global_position
		if to.length() > reach:
			continue
		if fwd.dot(to.normalized()) < 0.6:
			continue
		z.take_damage(dmg, z.head_threshold() - 0.01, true)
		return


func _start_reload() -> void:
	var gun := current_gun()
	if gun.reloading > 0.0 or gun.mag >= gun.def.mag or gun.res <= 0:
		return
	gun.reloading = gun.def.reload * Game.reload_scale()
	Sfx.play("reload_out", -12.0)


func _finish_reload(gun: Dictionary) -> void:
	var want: int = int(gun.def.mag) - gun.mag
	var take: int = mini(want, gun.res)
	gun.mag += take
	gun.res -= take
	gun.reloading = 0.0
	Sfx.play("reload_in", -12.0)
	weapon_changed.emit(gun)


# --- damage ------------------------------------------------------------------

func take_damage(amount: float) -> void:
	if is_downed or _hurt_cooldown > 0.0:
		return
	_hurt_cooldown = 0.35
	_regen_wait = 0.0
	hp -= amount
	Sfx.play("hurt", -8.0)
	if hp <= 0.0:
		hp = 0.0
		_go_down()
	health_changed.emit(hp, Game.max_health())


func _go_down() -> void:
	if Game.has_perk("revive") and not self_revive_used:
		self_revive_used = true
		is_downed = true
		downed_time = Game.DOWNED_TIME
		downed_changed.emit(true, downed_time)
	else:
		died.emit()


func revive() -> void:
	is_downed = false
	hp = Game.max_health()
	downed_changed.emit(false, 0.0)
	health_changed.emit(hp, Game.max_health())


func give_gun(key: String, pap := false) -> void:
	for i in guns.size():
		if guns[i].key == key:
			guns[i] = Weapons.make_gun(key, pap or guns[i].pap)
			slot = i
			weapon_changed.emit(current_gun())
			return
	if guns.size() < 2:
		guns.append(Weapons.make_gun(key, pap))
		slot = guns.size() - 1
	else:
		guns[slot] = Weapons.make_gun(key, pap)
	weapon_changed.emit(current_gun())


func refill_ammo() -> void:
	for g in guns:
		g.res = g.def.res
		g.mag = g.def.mag
	weapon_changed.emit(current_gun())


func grid_pos() -> Vector2:
	return Vector2(global_position.x, global_position.z)
