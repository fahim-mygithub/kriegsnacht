extends Node3D

## Dropped power-ups: the pool they are rolled from, the hover-and-blink life of
## one on the floor, and what collecting it does.
##
## Split out of main.gd. A Node3D rather than a plain Node purely so it has a
## place in the 3D tree next to the systems it works with; the sprites themselves
## are Atmosphere's children, because that file owns every prop scale in the game.

const POWER_POOL := ["ammo", "ammo", "insta", "nuke", "points", "points", "carp"]
const POWER_COLOR := {
	"ammo": Color(0.95, 0.82, 0.30), "insta": Color(0.90, 0.20, 0.18),
	"nuke": Color(0.45, 0.80, 0.95), "points": Color(0.55, 0.85, 0.35),
	"carp": Color(0.80, 0.55, 0.25),
}

var world: WorldBuilder
var player: Player
## atmosphere.gd and round_director.gd. Untyped for the same reason main.gd's
## `hud` and `lighting` are: both scripts are attached at runtime, so a typed
## variable cannot see `powerup_sprite()` or `alive()`.
var atmos
var rounds

var _powerups: Array = []


func bind(w: WorldBuilder, p: Player, a: Node3D, r: Node3D) -> void:
	world = w
	player = p
	atmos = a
	rounds = r


func spawn(at: Vector3) -> void:
	var kind: String = Rng.pick(Rng.DROPS, POWER_POOL)
	var node: Sprite3D = atmos.powerup_sprite("pu_" + kind,
		Vector2(at.x, at.z), "Powerup_" + kind)
	# Drops hover and glow so they read across a dark room.
	node.modulate = POWER_COLOR[kind] * 1.6
	node.position.y = 0.7
	_powerups.append({"node": node, "kind": kind, "life": 26.0, "t": 0.0})


## Driven from main.gd rather than from this node's own `_process` — see the note
## on the drive order there. Runs after the mystery box and before the interact
## scan, exactly where main.gd's `_update_powerups` used to sit, because a Nuke
## collected here kills the horde and every one of those deaths rolls DROPS.
func tick(dt: float) -> void:
	var keep := []
	for p in _powerups:
		p.life -= dt
		p.t += dt
		var n: Sprite3D = p.node
		if not is_instance_valid(n):
			continue
		n.position.y = 0.7 + sin(p.t * 3.0) * 0.10
		# Blink out over the last four seconds.
		n.visible = p.life > 4.0 or fmod(p.life, 0.4) > 0.2
		if p.life <= 0.0:
			n.queue_free()
			continue
		if n.global_position.distance_to(player.global_position) < 1.5:
			_collect(p.kind)
			n.queue_free()
			continue
		keep.append(p)
	_powerups = keep


## The drops currently on the floor. Nothing in the game reads this; the debug
## console does.
func live() -> Array:
	return _powerups


func _collect(kind: String) -> void:
	Sfx.play("powerup", -4.0)
	match kind:
		"ammo":
			player.refill_ammo()
			Game.toast.emit("MAX AMMO")
		"insta":
			Game.insta_kill = 30.0
			Game.toast.emit("INSTA-KILL")
		"points":
			Game.dbl_points = 30.0
			Game.toast.emit("DOUBLE POINTS")
		"nuke":
			Game.add_points(Game.PTS_NUKE)
			# One scaled cue rather than up to 24 phase-coherent copies of the
			# same buffer in a single frame, which summed about 21 dB hot.
			Sfx.play("death", -2.0, 0.72)
			# Duplicated because every death erases from the director's own live
			# list while this loop is walking it.
			var horde: Array = rounds.alive().duplicate()
			for z: Zombie in horde:
				if is_instance_valid(z):
					z.take_damage(1e9, 0.0)
			Game.toast.emit("NUKE")
		"carp":
			Game.add_points(Game.PTS_CARPENTER)
			for wi in MapData.WINDOWS.size():
				world.set_window_boards(wi, 6)
			Sfx.play("board", -6.0)
			Game.toast.emit("CARPENTER")
