class_name Zombie
extends CharacterBody3D

## One undead. Nodes are built in code rather than from a .tscn so the whole
## entity — collider, billboard, hitbox split — lives in one readable place.

signal died(z: Zombie, was_headshot: bool, by_melee: bool)

enum State { ENTERING, CHASING, ATTACKING, DYING }

const SEPARATION_RADIUS := 0.62
const SEPARATION_FORCE := 2.4

var kind := "zombie"          # zombie | crawler | hound
var pal := 0
var hp := 150.0
var max_hp := 150.0
var speed := 1.2
var melee_damage := 34.0
var melee_cadence := 1.05
var melee_reach := 1.15
var state: int = State.CHASING

var _sprite: AnimatedSprite3D
var _collider: CollisionShape3D
var _attack_timer := 0.0
var _death_timer := 0.0
var _last_headshot := false
var _last_melee := false
var _window_id := -1
var _height := 1.82

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
	var base_speed := Game.zombie_speed(p_round)
	match kind:
		"hound":
			hp = base_hp * 0.62
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
			speed = base_speed
	# Each zombie is a little off the round's nominal pace.
	speed *= randf_range(0.86, 1.14)
	max_hp = hp


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1        # walls only; zombies pass through each other
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
	_sprite.alpha_scissor_threshold = 0.35
	# Sprite origin is its centre, so lift it half a body to stand on the floor.
	_sprite.position.y = _height * 0.5
	_sprite.play("walk")
	add_child(_sprite)

	# Slight per-zombie speed variation on the animation too.
	_sprite.speed_scale = randf_range(0.85, 1.2)


## Records which barricade this one climbed through, then goes straight to
## chasing — the boards are torn off at spawn time by the round manager.
func set_entering(window_id: int) -> void:
	_window_id = window_id
	state = State.CHASING


func _physics_process(dt: float) -> void:
	if Game.state != Game.STATE_PLAY:
		return

	if state == State.DYING:
		_death_timer -= dt
		if _death_timer <= 0.0:
			queue_free()
		return

	if target == null:
		return

	var here := Vector2(global_position.x, global_position.z)
	var goal := Vector2(target.global_position.x, target.global_position.z)
	var to_target := goal - here
	var dist := to_target.length()

	if dist <= melee_reach:
		state = State.ATTACKING
		if _sprite.animation != "attack":
			_sprite.play("attack")
		_attack_timer -= dt
		if _attack_timer <= 0.0:
			_attack_timer = melee_cadence
			if target.has_method("take_damage"):
				target.take_damage(melee_damage)
			Sfx.play("melee", -8.0)
		velocity = Vector3.ZERO
		move_and_slide()
		return

	if state == State.ATTACKING:
		state = State.CHASING
	if _sprite.animation != "walk":
		_sprite.play("walk")

	# Direct line of sight beats the flow field — it stops a horde in an open
	# room from filing along tile centres like a conga line.
	var dir: Vector2
	if _has_los(here, goal):
		dir = to_target.normalized()
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
	return push


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
	if hp <= 0.0:
		_die()
		return true
	Sfx.play("headshot" if headshot else "hit", -10.0)
	return false


func _die() -> void:
	state = State.DYING
	collision_layer = 0
	collision_mask = 0
	_sprite.play("death")
	var frames: int = SpriteLib.SPEC[kind].death
	_death_timer = float(frames) / 9.0 + 0.9
	Sfx.play("death", -12.0)
	died.emit(self, _last_headshot, _last_melee)


## Where a hitscan should aim to be "centre mass", used by the melee test.
func centre() -> Vector3:
	return global_position + Vector3(0, _height * 0.5, 0)
