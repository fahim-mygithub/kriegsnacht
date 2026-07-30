extends RefCounted

## Frags and the Monkey Bomb: what the player carries, the cook clock, and the one
## flag the horde reads.
##
## **Neither exists in the ancestor.** `grep -i "grenade\|monkey\|frag"` over
## kriegsnacht.html finds only the China Lake's `proj:'grenade'` kind, so this is
## designed against Black Ops rather than restored, and every number below is the
## port's own except the two that are deliberately borrowed from the launcher
## shell — see FRAG.
##
## **Not a Node**, unlike the five systems in this directory, and the reason is the
## clock. The cook timer is the only state here that ticks, and it has to tick on
## exactly the clock that reads the throw input — the player's `_physics_process` —
## or a grenade cooked for 2.5 s can leave the hand on a frame where the fuse has
## already expired. A second `_process` callback would be a second ordering
## question for no reader's benefit. It owns no transform either: the bodies it
## makes are `projectile.gd` nodes that live under the world.
##
## **The lure is one position on the Game autoload, and that is the whole of the
## Monkey Bomb's AI.** The flow field already re-solves whenever its goal tile moves
## (flow_field.gd:22) and `invalidate()` already exists for the case where it does
## not, so a monkey needs no lure subsystem, no per-zombie state and no new
## pathfinding: it needs somewhere else for the horde to walk.
##
## **It lives on `Game` and not in a static here**, and that is a correction rather
## than a preference. This file first published the lure as its own statics while
## `zombie.gd::_goal_point` read `Game.lure_position` behind an `in` guard — so the
## guard was false, every zombie fell back to the player, and throwing a monkey did
## nothing whatsoever. Both halves were individually reasonable and there was no
## contract either could see. `Game.lure_position` is now the single store; the four
## accessors below are views onto it and hold no state of their own, so there is
## nothing left that can disagree with the thing the AI actually reads. It also gets
## the run-lifetime question right for free: `Game.reset_run()` clears it, where a
## static would have survived `reload_current_scene()` and started the next run with
## the whole horde walking at a monkey in the previous map.

## preload rather than the class name: a freshly added script is not in the class
## registry until the editor rescans, and a headless run has no editor.
const PROJECTILE := preload("res://scripts/entities/projectile.gd")

const FRAG := "frag"
const MONKEY := "monkey"

## Every throwable, in one table, in the shape `projectile.gd::setup` reads.
##
## FRAG — BO1's M67. Two carried and four maximum is canon; the 2.5 s fuse is the
## reference's, and it is what makes cooking worth doing at all.
##
##   `splash_dmg` is the China Lake's 1150 (weapons.gd, and html:2560 feeds the
##   same field), NOT a second blast number invented next to the first one. The
##   radius is larger — 3.0 against 2.6 — because a frag body fragments spherically
##   where a 40 mm shell has a shaped charge and a direction, and the frag has no
##   `dmg` term at all: a grenade that has to hit somebody to be worth anything is
##   a bullet with extra steps. Against the health curve that is a clean kill on
##   anything through round 13 at the centre and through round 5 at the very edge,
##   which is the reference's shape — a round-one panic button that becomes crowd
##   control rather than a delete key.
##
##   `grav` is REAL gravity, not the ancestor's 2.6. That number is a launcher
##   number: html:2559's shell leaves at 16 m/s and travels 24 m before it lands,
##   which is right for a China Lake indoors and absurd for something thrown by
##   hand. At 9.8 the frag lands 9.5 m out, which is a throw.
##
## MONKEY — the Cymbal Monkey. No ancestor and no canon script to read, so the
## numbers are the port's: it is not carried at the start (it is a box weapon in
## BO1), four arrive at once when it is found, and it holds the horde for 6.0 s
## before going off. The blast is bigger than a frag's in both terms because the
## whole design is "everything is standing on top of it when it detonates" — and
## it is deliberately NOT big enough to be a delete key past about round 21, which
## is where the health curve overtakes it.
const SPEC := {
	"frag": {
		"kind": "frag", "start": 2, "max": 4,
		"speed": 11.0, "rise": 2.6, "grav": 9.8,
		"fuse": 2.5, "cook": true,
		"dmg": 0.0, "splash": 3.0, "splash_dmg": 1150.0,
		"contact": false, "bounces": true, "lures": false,
	},
	"monkey": {
		"kind": "monkey", "start": 0, "max": 4,
		"speed": 9.5, "rise": 2.4, "grav": 9.8,
		"fuse": 6.0, "cook": false,
		"dmg": 0.0, "splash": 4.0, "splash_dmg": 3000.0,
		"contact": false, "bounces": true, "lures": true,
	},
}

## How many arrive when the box hands over a Monkey Bomb. BO1 gives the full set.
const MONKEY_PICKUP := 4


# --- the lure ------------------------------------------------------------------

## Live only while a monkey is in the air or on the floor playing. Cleared on the
## frame of the blast rather than when the node is freed, because the node outlives
## its own detonation by FLASH_TIME to hold the blast light.
##
## `Vector3.INF` is "no lure" — game_state.gd:116 owns that convention, and the `in`
## guard is what lets this file load and run on a tree where the property has not
## landed yet, exactly as `zombie.gd:795` does on the reading side.
static func lure_active() -> bool:
	if not ("lure_position" in Game):
		return false
	var at: Vector3 = Game.lure_position
	return is_finite(at.x) and is_finite(at.z)


static func lure_position() -> Vector3:
	if not lure_active():
		return Vector3.ZERO
	var at: Vector3 = Game.lure_position
	return at


## The one writer of `Game.lure_position` in the project. Both edges go through it,
## so "set" and "clear" cannot drift apart, and `_kick_flow` fires on the change
## rather than on the call: `_set_lure` runs every tick a monkey is in the air and
## the flow field must not be invalidated sixty times a second.
static func _publish(at: Vector3) -> void:
	if not ("lure_position" in Game):
		return
	Game.lure_position = at


## Where the flow field should solve to. **This is the AI's whole contract with the
## Monkey Bomb**, and it is one function rather than a flag plus a position on
## purpose: two reads on two frames can disagree, and a horde half-pathing to a
## monkey that has already gone off is exactly the kind of thing nobody would find.
static func flow_goal(fallback: Vector2) -> Vector2:
	if not lure_active():
		return fallback
	var at := lure_position()
	return Vector2(at.x, at.z)


## The same answer for a zombie's own direct-chase decision, which works in 3D and
## has to be given the monkey's real height or a body standing on it walks at the
## floor. Falls back to whatever the caller was going to chase — the player.
static func chase_goal(fallback: Vector3) -> Vector3:
	return lure_position() if lure_active() else fallback


# --- one player's pouch --------------------------------------------------------

var counts := {}

var _player: Player
## The live monkey, so the lure can follow it without the projectile having to know
## this file exists. One at a time: a second throw replaces the first as the lure,
## which is also what BO1 does with two monkeys down.
var _monkey: Area3D
## Which throwable is being cooked, and for how long it has been. Empty when the
## hand is free.
var _cooking := ""
var _cook_t := 0.0


func _init(p: Player) -> void:
	_player = p
	# A fresh pouch means no monkey of this player's is live, by construction — this
	# runs from `Player._ready`, so it is once per scene load. `Game.reset_run()`
	# clears the same property, but the two are not ordered against each other and a
	# lure left standing for even one physics tick is a horde solving to a point in
	# the map that was just torn down.
	_publish(Vector3.INF)
	for key: String in SPEC:
		var row: Dictionary = SPEC[key]
		var start: int = row.start
		counts[key] = start


func count(key: String) -> int:
	var n: int = counts.get(key, 0)
	return n


## The cook clock as a fraction of the fuse, 0 when nothing is cooking. For a HUD:
## this is the one piece of state a player cannot see any other way, and holding a
## frag past 1.0 kills them.
func cook_fraction() -> float:
	if _cooking.is_empty():
		return 0.0
	var row: Dictionary = SPEC[_cooking]
	var fuse: float = row.fuse
	return clampf(_cook_t / maxf(fuse, 0.001), 0.0, 1.0)


func give(key: String, n: int) -> void:
	if not SPEC.has(key):
		return
	var row: Dictionary = SPEC[key]
	var cap: int = row.max
	counts[key] = mini(cap, count(key) + n)


## The trigger going down. A cookable throwable starts its fuse in the hand; a
## Monkey Bomb leaves immediately, because cooking a lure makes no sense — the
## whole value of it is the six seconds it spends on the floor.
func press(key: String) -> void:
	if not SPEC.has(key) or count(key) <= 0:
		return
	if not _cooking.is_empty():
		return
	if _player == null or not is_instance_valid(_player) or _player.is_downed:
		return
	var row: Dictionary = SPEC[key]
	var cook: bool = row.cook
	if not cook:
		_throw(key, float(row.fuse))
		return
	_cooking = key
	_cook_t = 0.0
	# The pin, so a cook that is never released still reads as an action the player
	# took. sfx.gd bakes no pull cue; `reload_out` is the shortest metallic click
	# already resident (0.06 s of noise at 240 Hz) and it is what the reload uses
	# for the magazine leaving the well.
	Sfx.play("reload_out", -14.0)


## The trigger coming up. Whatever is left of the fuse goes with the grenade, which
## is the entire point of cooking one.
func release(key: String) -> void:
	if _cooking != key:
		return
	var row: Dictionary = SPEC[key]
	var fuse: float = row.fuse
	_throw(key, maxf(0.05, fuse - _cook_t))
	_cooking = ""
	_cook_t = 0.0


## Driven from `Player._physics_process`, which is also what reads the throw input —
## see the header for why this does not own a clock of its own.
func tick(dt: float) -> void:
	if not _cooking.is_empty():
		_cook_t += dt
		var row: Dictionary = SPEC[_cooking]
		var fuse: float = row.fuse
		if _cook_t >= fuse:
			# COOKED OFF IN THE HAND. The reference's own punishment, and it is what
			# makes the cook a decision rather than free damage: `_throw` with a
			# fuse of nothing detonates at the player's feet, and the self-damage in
			# projectile.gd does the rest.
			var key := _cooking
			_cooking = ""
			_cook_t = 0.0
			_throw(key, 0.0)

	# The lure follows the monkey while it flies and while it sits, and ends on the
	# frame it detonates rather than when the node is finally freed.
	if _monkey != null and is_instance_valid(_monkey) and not _monkey.dead():
		_set_lure(_monkey.global_position)
	elif lure_active():
		_monkey = null
		_clear_lure()


func _throw(key: String, fuse: float) -> void:
	if count(key) <= 0:
		return
	counts[key] = count(key) - 1
	var row: Dictionary = SPEC[key]
	var host := _host()
	if host == null:
		return
	var cam := _player.camera()
	var aim := -cam.global_transform.basis.z
	var speed: float = row.speed
	var rise: float = row.rise
	# Along the crosshair plus a lift, so a throw at a wall two metres away drops in
	# front of the player rather than sailing over the room. `rise` is added on top
	# of the aim rather than folded into it because the aim already carries the
	# camera's pitch and a player looking up should get both.
	var vel := aim * speed + Vector3.UP * rise
	var from := cam.global_position + aim * PROJECTILE.SPAWN_AHEAD \
		- Vector3(0.0, PROJECTILE.SPAWN_DROP, 0.0)

	var cfg := {
		"kind": key,
		"grav": row.grav,
		"dmg": row.dmg,
		"splash": row.splash,
		"splash_dmg": row.splash_dmg,
		"fuse": fuse,
		"contact": row.contact,
		"bounces": row.bounces,
		"lures": row.lures,
	}
	var pr: Area3D = PROJECTILE.launch(_player, host, cfg, from, vel)
	var lures: bool = row.lures
	if lures:
		_monkey = pr
		_set_lure(pr.global_position)
	Sfx.play("reload_in", -12.0)


## Where a thrown body lives: the composition root, never the player, or every
## grenade in the air would ride the thrower's own movement. `Player.world` is main
## and is set by main.gd immediately after the player is added; `get_parent()` is
## the same node by a different route and covers a harness that never set it.
func _host() -> Node3D:
	if _player == null or not is_instance_valid(_player):
		return null
	if _player.world != null and is_instance_valid(_player.world):
		return _player.world
	return _player.get_parent() as Node3D


func _set_lure(at: Vector3) -> void:
	var was := lure_active()
	_publish(at)
	if not was:
		_kick_flow()


func _clear_lure() -> void:
	if not lure_active():
		return
	_publish(Vector3.INF)
	_kick_flow()


## The flow field early-returns whenever its goal is still in the same tile
## (flow_field.gd:22), so a lure that begins or ends on the tile the player is
## already standing on would leave the whole horde steering on a graph solved for
## the wrong goal. `invalidate()` exists for exactly this and is one BFS.
##
## Reached through `Object.get` rather than by name: `Player.world` is typed
## `Node3D`, main.gd's `flow` is not part of that type, and a typed member access
## is resolved at parse time — so naming it directly would make a renamed field a
## build that never finishes rather than a feature that quietly stops working.
func _kick_flow() -> void:
	var host := _host()
	if host == null:
		return
	var f: FlowField = host.get("flow")
	if f != null:
		f.invalidate()
