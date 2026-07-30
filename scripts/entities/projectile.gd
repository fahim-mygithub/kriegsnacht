extends Area3D

## One thing in flight that detonates: the Ray Gun's bolt, the China Lake's shell,
## a frag, a Monkey Bomb. The ancestor has the whole system (`updateProjectiles`,
## kriegsnacht.html:2593-2618, and `explode`, :2576-2591) and the port had none of
## it — so `proj`, `splash` and `splash_dmg` sat in the weapon table being read by
## nothing, and the Ray Gun was a 180-damage single-target hitscan against the
## 500-point M14's 185. Nothing errored; the weapon just read as disappointing.
##
## **Not a RigidBody3D, and the integration is manual and SWEPT.**
##
## THE OBVIOUS REASON IS NOT THE REASON, and it was measured rather than argued.
## This file used to claim that a discrete per-frame position test tunnels here —
## that `world_builder.gd:358` makes the level one `ConcavePolygonShape3D` of loose
## triangles, so a wall has no thickness and a point sample "has no chance of
## hitting". **That is false, and the control run says so.** Replacing the sweep
## below with a bare `intersect_point` at the destination passes all 451 assertions
## in `--verify`, the wall tests included. Two facts kill the argument: a solid tile
## is a full 1 x 1 x 2.8 m block, not a plane (`_emit_wall_faces` skips the faces
## between two solid tiles, so the trimesh is a closed shell and Jolt's point query
## resolves inside/outside against it), and the thing that has to be thicker than
## one tick's travel is the WALL, not the projectile. 0.383 m a tick puts about two
## and a half samples inside a 1 m wall. The old note compared the step to the
## body's own 0.30 m, which is not a quantity anything collides with.
##
## The sweep stays, for the three reasons that survive contact with the control:
##
##   - **`_bounce` needs a contact point and a surface normal**, and a point test
##     produces neither. Deleting the sweep does not slow the frag down; it deletes
##     the thrown weapons, which is most of what this file is for.
##   - **A blast has to go off at the wall FACE.** A point test reports "somewhere
##     inside", which is up to 0.38 m past it — and a detonation origin buried in
##     geometry is occluded by that geometry from every `LOS.clear` below, so the
##     splash and the self-damage both silently evaluate to nothing.
##   - **It does not depend on the backend.** Jolt answers point-in-mesh; the engine
##     default GodotPhysics3D does not. project.godot:138-154 exists because that
##     setting has already silently reverted once on this project, and a wall test
##     that stops working on a typo in an unrelated line is not a wall test.
##
## The 1 m margin is also not a margin anybody wrote down: it only holds under
## 60 m/s. `checks/projectiles.gd::_tunnelling` now fires a round fast enough to
## clear a whole tile in one tick and asserts it is still stopped, which is the
## assertion the discrete control actually fails.
##
## A solver would fight the design in any case: the ancestor's grenade arc uses
## `grav 2.6` (html:2559), a quarter of real gravity, because a 40 mm shell that
## drops at 9.8 m/s^2 is unusable in a 2.8 m room.
##
## **Zombies are tested analytically, not through the physics space**, and that is
## also measured rather than stylistic: `scripts/dev/checks/downed.gd` records that
## a body added to the tree inside `Verify.run` is never flushed into the Jolt
## space, so a shape query against it returns empty and every assertion about it
## passes for the wrong reason. A swept segment-versus-body-axis test is exact, is
## the ancestor's own test (`hypot(z.x-nx, z.y-ny) < z.r+0.16`, html:2605) with a
## sweep and a height band added, and can actually be asserted.
##
## The node is an `Area3D` because that is the shape of the thing — a volume in the
## world that hits things and is not simulated — but it is deliberately inert in
## the physics space: no `CollisionShape3D`, `monitoring` off, both masks zero. It
## contributes nothing to the solver, and every contact below is a query this file
## makes itself.

## The one line-of-sight test in the game, shared with the AI's chase decision, the
## Thundergun's wedge and the interaction scan. preload rather than the class name,
## per the convention at the top of los.gd.
const LOS := preload("res://scripts/world/los.gd")

## This script's own path, for the static factory. `new()` cannot be called on a
## script's own class from a static function when the script carries no
## `class_name`, and `load()` on an already-resident resource is a cache lookup
## rather than a disk read — the same workaround, for the same reason, as
## `console.gd:101`.
const SELF_PATH := "res://scripts/entities/projectile.gd"


# --- the ancestor's launch parameters ----------------------------------------

## `x:P.x+P.dirX*0.35 ... z:1.42` (html:2556). The ancestor's world has no camera,
## so 1.42 is an absolute height; here it is expressed as a drop below the eye,
## because the eye is `MapData.EYE` = 1.55 (html:1683) and 1.55 - 1.42 = 0.13. That
## 13 cm is what stops the round leaving your forehead.
const SPAWN_AHEAD := 0.35
const SPAWN_DROP := 0.13

## `h:0.30` (html:2561) is the body's full size — it is passed straight to the
## sprite draw as a height (html:2109). Half of it is the radius the sweep uses.
const BODY := 0.30
const RADIUS := BODY * 0.5

## `life:3` (html:2561).
const LIFE := 3.0

## `spd: d.proj==='ray'?23:16`, `vz: ...?0:1.1`, `grav: ...?0:2.6` (html:2558-2559).
const RAY_SPEED := 23.0
const GRENADE_SPEED := 16.0
const GRENADE_RISE := 1.1
const GRENADE_GRAV := 2.6

## `dmg*(1 - d/radius*0.55)` (html:2587). **The edge of the blast still does 45%**,
## and that is not a rounding of "zero at the edge" — it is what makes a China Lake
## round worth carrying against a horde that is never conveniently stacked.
const FALLOFF := 0.55

## `if(pd<radius*0.75 && !P.downed) hurtPlayer(Math.round(24*(1-pd/(radius*0.75))))`
## (html:2590). The only self-damage in the game, and the whole reason the China
## Lake is not a panic button.
const SELF_FRACTION := 0.75
const SELF_DAMAGE := 24.0

## `G.shake=Math.max(G.shake,0.55)` (html:2578).
const BLAST_SHAKE := 0.55

## Static world geometry only, exactly as `LOS.MASK_WORLD`. Enemies are on 4 and
## are handled by the analytic sweep; the player is on 2 and a round must not
## detonate on the person who fired it.
const MASK_WORLD := 1

## Restitution and tangential loss for a body that bounces rather than detonating
## on contact — the thrown pair. Invented: the ancestor has no thrown weapon at
## all. A frag that does not bounce is a frag that cannot be banked round a corner,
## which is most of what a grenade is for in the reference.
const BOUNCE := 0.32
const BOUNCE_FRICTION := 0.6
## Under this, on a surface facing mostly up, the body is at rest. Without a rest
## state gravity re-collides it with the floor every tick and it jitters.
const REST_SPEED := 0.55


# --- the travelling light ------------------------------------------------------

## **This is the point of the Ray Gun.** A 180-damage bolt is a slow bullet; a bolt
## that lights the corridor it is crossing is a wonder weapon. It is an
## `OmniLight3D` and not a Decal or a volumetric because both of those are dead at
## runtime under `gl_compatibility`, and the trail is a billboard rather than a
## particle trail for the same reason.
##
## The colour is the one `atmosphere.gd:50` already uses for the Ray Gun's muzzle
## flash, which is the ancestor's own `rgba(150,240,80)` bolt (html:3420) rounded
## to the same hue. Not converted through `srgb_to_linear`: `light_color` is a
## light, not an albedo, and constraint 7 is explicit that a canvas number must not
## become a light energy — so only the hue carries across and the energy below is
## chosen against this renderer's other lights, not against the browser's.
##
## The energy and the reach are the pair that was TUNED ON A RENDERED FRAME rather
## than derived, and the two are not independent: the same wash comes from a bright
## short light or a dim long one, and only one of them stops looking like a lamp.
## 2.4 at 5.0 m — chosen off the lamp constants (LAMP_ENERGY_OFF 2.0,
## LAMP_ENERGY_ON 3.0, lighting.gd:145/:109) on the theory that a bolt should sit
## between an unpowered and a powered lamp — filled the corridor evenly end to end
## and read as somebody switching a light on. 1.6 at 4.5 falls off inside the room,
## so there is a lit pool travelling with the round and darkness past it, which is
## the thing that makes it read as a moving source at all.
##
## Keep these two together if either is retuned, and look at a `--shot` rather than
## at the numbers: the arithmetic against the lamps is what produced the wrong
## answer the first time.
const RAY_LIGHT_COLOR := Color(0.63, 1.0, 0.35)
const RAY_LIGHT_ENERGY := 1.6
const RAY_LIGHT_RANGE := 4.5

## `spawnParticles(x,y,1.0,26,{r:255,g:170,b:60,...})` (html:2580) is the ancestor's
## detonation colour. Held for 0.14 s, which is nearly three times the muzzle
## flash's 0.05 s (atmosphere.gd:136) because a blast is not a flash-in-the-pan.
const FLASH_COLOR := Color(1.0, 0.667, 0.235)
const FLASH_ENERGY := 7.0
const FLASH_TIME := 0.14

## Pooled, and the pool is small on purpose. The Ray Gun fires 320 rpm — 5.3 rounds
## a second — and a bolt crosses this map's longest room in about half a second, so
## two or three are in the air at once in the worst case. The renderer's per-object
## light cap is 8 and the level already spawns 8 room lamps plus a muzzle flash
## (world_builder.gd:295-302 records that the headroom is exactly zero on a surface
## that sees them all), so a fourth bolt flies unlit rather than silently evicting a
## room lamp from a wall.
##
## Slots are handed out round-robin, so the light always follows the NEWEST round —
## which is the one nearest the player and the one being aimed.
const LIGHT_POOL := 3


# --- the visible body ----------------------------------------------------------

## `add(pr.spr, pr.x, pr.y, pr.h, pr.z, {glow:true})` (html:2109): both projectiles
## are drawn additively, at `pr.h` = 0.30 m.
##
## The material is `Zombie.eye_material()`, and reusing it is deliberate rather than
## lazy. It is a shared, unshaded, additive, billboarded material with a radial
## alpha ramp baked into a `GradientTexture2D` — which is *exactly* what
## `SPR.projRay` is (three concentric circles, html:3419-3423). Taking it costs zero
## new materials, zero new shader variants on a platform that recompiles every
## variant on every page load, and it is already reachable from the warm-up pass, so
## the first Ray Gun round of a run does not buy a mid-fight GLSL compile. Its name
## is about the first thing that needed it, not about what it is.
##
## Per-kind colour therefore rides the vertex stream, which is the only per-instance
## channel that material leaves open — `INSTANCE_CUSTOM` does nothing on a plain
## MeshInstance3D under Compatibility.
const QUAD_SIZE := BODY

## Display-space, converted the same way `Zombie._eye_mesh` converts its own
## (zombie.gd:734): the material does not flag its vertex colours as sRGB, so a hex
## authored against a canvas has to be linearised here or the hue is wrong on the
## one material both of them share. Alpha is carried through untouched — the
## material is `blend_add`, so alpha is the contribution and the grenade's dull
## shell is dimmer than the ray's core rather than a different colour.
##
##   ray      `#B4F268`, the middle of the ancestor's three circles (html:3421).
##   grenade  `rgba(255,170,60,.5)`, the only lit part of `SPR.projNade`
##            (html:3427) — the shell itself is `#3A4030` and does not glow.
##   frag     the same burning tail, a little dimmer: it is a smaller charge.
##   monkey   no ancestor at all. Warm red so it cannot be mistaken for a frag at a
##            glance, which matters because one of them is a lure you walk away from
##            and the other is a bomb you throw at something.
const TINT := {
	"ray": Color(0.706, 0.949, 0.408, 1.0),
	"grenade": Color(1.0, 0.667, 0.235, 0.5),
	"frag": Color(1.0, 0.667, 0.235, 0.45),
	"monkey": Color(1.0, 0.42, 0.30, 0.8),
}


# --- shared state ------------------------------------------------------------

## kind -> ArrayMesh. Four at most, for the life of the process.
static var _meshes := {}

## The light pool, its per-slot owner (an instance id, 0 for free) and the
## round-robin cursor. Statics survive `reload_current_scene()`, so the nodes are
## revalidated before use — see `_ensure_lights`.
static var _lights: Array[OmniLight3D] = []
static var _light_owner: Array[int] = []
static var _light_next := 0


# --- one round ---------------------------------------------------------------

var kind := "ray"
var vel := Vector3.ZERO
var grav := 0.0
## Damage to the body actually struck. Zero for the thrown pair: a frag that has to
## hit somebody to be worth anything is a bullet with extra steps.
var dmg := 0.0
var splash := 0.0
var splash_dmg := 0.0
var fuse := LIFE
## The ancestor's rule for both of its projectiles: `blocked() || z<0.12 || life<=0`
## (html:2600) and any body inside `z.r+0.16` (html:2605). A thrown body sets this
## false and rides its fuse instead, which is what makes it bankable off a wall.
var contact_detonates := true
var bounces := false
## Whether the horde should walk toward this instead of toward the player while it
## is alive. Read by `throwables.gd`, which owns the flag the AI reads — nothing
## here knows the AI exists.
var lures := false

## Who fired it. Needed for the payout path, the self-damage and the shake; null is
## tolerated so a headless harness can detonate one without a player.
var player: Player

var _quad: MeshInstance3D
var _slot := -1
var _flash_t := 0.0
var _dead := false
var _resting := false


## The one way a round comes into existence. `host` is where the node lives — main,
## not the player, or every round in the air would ride the player's own movement.
static func launch(p: Player, host: Node3D, cfg: Dictionary, from: Vector3,
		velocity: Vector3) -> Area3D:
	var script: GDScript = load(SELF_PATH)
	var pr: Area3D = script.new()
	pr.name = "Proj_%s" % String(cfg.get("kind", "ray"))
	# Configured before it enters the tree, because `_ready` builds the billboard
	# out of `kind` and a mesh swapped a frame later is a frame of the wrong colour.
	pr.setup(p, cfg, velocity)
	# `force_readable_name`, and it earns its cost. Without it Godot resolves the
	# second live round's name collision by mangling it to `@Area3D@597`, so every
	# round after the first is unfindable in a debugger, in a remote scene tree and
	# in any harness that identifies one by name — which is exactly how this was
	# found. One string operation per shot against a node instantiation is nothing.
	host.add_child(pr, true)
	pr.global_position = from
	# `_ready` claims the light before this line runs, so without it the first tick
	# of every Ray Gun round is lit from the world origin. It is one frame, it is a
	# whole room away, and it is exactly the kind of thing a rendered frame catches
	# and an assertion does not — this one was found in a `--shot`.
	pr.sync_light()
	return pr


## Every field a round carries, in one call, so there is no half-built state a
## `_ready` could observe.
func setup(p: Player, cfg: Dictionary, velocity: Vector3) -> void:
	player = p
	kind = String(cfg.get("kind", "ray"))
	vel = velocity
	# Annotated rather than inferred, all of them: `Dictionary.get` returns Variant
	# and inference through it is a hard parse error, not a warning.
	var g: float = cfg.get("grav", 0.0)
	grav = g
	var d: float = cfg.get("dmg", 0.0)
	dmg = d
	var sr: float = cfg.get("splash", 0.0)
	splash = sr
	var sd: float = cfg.get("splash_dmg", 0.0)
	splash_dmg = sd
	var f: float = cfg.get("fuse", LIFE)
	fuse = f
	var cd: bool = cfg.get("contact", true)
	contact_detonates = cd
	var bo: bool = cfg.get("bounces", false)
	bounces = bo
	var lu: bool = cfg.get("lures", false)
	lures = lu


func _ready() -> void:
	# Inert in the space. The Area3D is the node type, not the detector — see the
	# header. Leaving it monitoring would put an area and a broadphase entry in the
	# space for every round fired, for a callback nothing reads.
	monitoring = false
	monitorable = false
	collision_layer = 0
	collision_mask = 0

	_quad = MeshInstance3D.new()
	_quad.name = "Glow"
	_quad.mesh = _glow_mesh(kind)
	_quad.material_override = Zombie.eye_material()
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Billboarding is a vertex-shader rotation, so the AABB never turns with the
	# geometry. The quad is centred on its own origin, so one full span covers the
	# swept circle — the same argument lighting.gd makes for its lamp fixtures, and
	# unlike the zombie eyes, which sit off theirs and need two.
	_quad.extra_cull_margin = QUAD_SIZE
	add_child(_quad)

	if kind == "ray":
		_claim_light()


## Puts the travelling light where the body is. Public because `launch()` has to
## call it once the node has been positioned — see there.
func sync_light() -> void:
	_move_light()


## True once it has gone off. Read by `throwables.gd` to end the lure on the frame
## of the blast rather than 0.14 s later, when the node is finally freed.
func dead() -> bool:
	return _dead


func _exit_tree() -> void:
	_release_light()


func _physics_process(dt: float) -> void:
	# Not redundant with the tree pause: STATE_TITLE deliberately does not pause
	# (game_state.gd:241) and the warm-up pass runs there. Nothing may move in it.
	if Game.state != Game.STATE_PLAY:
		return

	if _dead:
		_tick_flash(dt)
		return

	fuse -= dt
	_step(dt)
	if _dead:
		return
	# Unconditional, and after the step: a body at rest, a body that bounced and a
	# body that flew all have to drag their light with them, and putting the call in
	# only the paths that happen to move left a resting frag lighting the origin.
	_move_light()
	if fuse <= 0.0:
		# `pr.life<=0` is one of the ancestor's three detonation conditions
		# (html:2600) and it applies to the thrown pair as their whole timer.
		_explode(global_position)


# --- integration ---------------------------------------------------------------

## One swept step. Gravity, then the segment, then whichever of the wall and the
## horde the segment reaches first.
func _step(dt: float) -> void:
	if _resting:
		return
	vel.y -= grav * dt
	var from := global_position
	var step := vel * dt
	var span := step.length()
	if span < 1e-6:
		return
	var dir := step / span
	# The nose, not the centre. Extending the segment by the body's own radius is
	# what makes a 0.30 m shell stop against a wall rather than half inside it, and
	# it is the sweep equivalent of the ancestor's `z.r+0.16` margin (html:2605).
	var reach := span + RADIUS

	var wall_d := reach + 1.0
	var wall_at := from
	var wall_n := Vector3.UP
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * reach)
	q.collision_mask = MASK_WORLD
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		# Everything out of the hit dictionary is Variant, so annotate rather than
		# infer — the same rule `player._hitscan` follows.
		var hp: Vector3 = hit.position
		var hn: Vector3 = hit.normal
		wall_d = from.distance_to(hp)
		wall_at = hp
		wall_n = hn

	var body_d := reach + 1.0
	var body: Zombie = null
	var found := _sweep_bodies(from, dir, reach)
	if not found.is_empty():
		var fd: float = found[0]
		var fz: Zombie = found[1]
		body_d = fd
		body = fz

	if body != null and body_d <= wall_d:
		# `zombieDamage(z, pr.dmg, false)` then `explode(z.x, z.y, ...)`
		# (html:2606-2612). The direct damage is a body shot by construction: the aim
		# point is `centre()`, which is `_height*0.5` and under every kind's
		# `head_threshold()` — the same argument `_cone_blast` makes, and the
		# ancestor passes `false` for headshot outright.
		# NOT pulled back the way the wall case below is: `bx=z.x, by=z.y`
		# (html:2607) centres the blast on the body it struck, and there is no
		# surface here for the origin to be occluded by.
		var at := from + dir * body_d
		if dmg > 0.0:
			_hurt(body, dmg, false)
		_explode(at)
		return

	if wall_d <= reach:
		if contact_detonates:
			# Pulled back by the body's radius, and this is load-bearing rather than
			# cosmetic: the shell detonates at its own centre, not at the contact
			# point, and a blast origin sitting exactly ON a wall face would be
			# occluded from everything by the wall it just hit — including the
			# player, so the only self-damage in the game would never once land.
			_explode(wall_at - dir * RADIUS)
			return
		_bounce(wall_at - dir * RADIUS, wall_n)
		return

	global_position = from + step


## Reflect, lose energy, and come to rest on something flat. Invented — the
## ancestor has no bouncing body — but the rest test is not optional: gravity
## re-collides a stationary shell with the floor on every tick, and without a rest
## state it buzzes there until its fuse runs out.
func _bounce(at: Vector3, n: Vector3) -> void:
	global_position = at
	var into := n * vel.dot(n)
	var along := vel - into
	vel = along * BOUNCE_FRICTION - into * BOUNCE
	if vel.length() < REST_SPEED and n.y > 0.7:
		_resting = true
		vel = Vector3.ZERO


## Swept segment against every live body, returning `[distance, zombie]` for the
## nearest one the segment actually touches, or empty.
##
## The horizontal part is the ancestor's own test — `hypot(z.x-nx, z.y-ny) < z.r+0.16`
## (html:2605) — with the point replaced by the segment, so a round travelling
## 0.38 m a tick can no longer straddle a body. The vertical part has no ancestor,
## because the ancestor's projectile had a height and its zombies did not: a bolt
## fired at the ceiling should miss the thing standing under it.
func _sweep_bodies(from: Vector3, dir: Vector3, reach: float) -> Array:
	var best_d := reach + 1.0
	var best: Zombie = null
	for node in get_tree().get_nodes_in_group("zombies"):
		var z := node as Zombie
		if z == null or not is_instance_valid(z) or z.state == Zombie.State.DYING:
			continue
		var foot := z.global_position
		var height: float = z.centre().y * 2.0
		# Closest approach along the step, solved in the horizontal plane because
		# that is the plane the ancestor's test lives in and because a body is a
		# vertical axis: the horizontal offset is what decides a hit and the height
		# only decides whether the round was at body level when it got there.
		var flat := Vector2(dir.x, dir.z)
		var flat2 := flat.length_squared()
		var d := 0.0
		if flat2 > 1e-10:
			var rel := Vector2(foot.x - from.x, foot.z - from.z)
			d = clampf(rel.dot(flat) / flat2, 0.0, reach)
		elif absf(dir.y) > 1e-6:
			# Straight up or down — a grenade at the top of its arc. The horizontal
			# offset is constant over the whole step, so the only thing left to
			# choose is the height, and the body's middle is the best candidate.
			d = clampf((foot.y + height * 0.5 - from.y) / dir.y, 0.0, reach)
		var at := from + dir * d
		if Vector2(at.x - foot.x, at.z - foot.z).length() > _body_radius(z) + RADIUS:
			continue
		if at.y < foot.y - RADIUS or at.y > foot.y + height + RADIUS:
			continue
		if d < best_d:
			best_d = d
			best = z
	if best == null:
		return []
	return [best_d, best]


## The collider's radius, read off the body rather than assumed, so the projectile
## and `player._hitscan` agree about how wide a zombie is. Falls back to the walker
## figure for a body that was never added to a tree — `balance_sim.gd` builds
## exactly those, and `_ready` is what makes the collider.
static func _body_radius(z: Zombie) -> float:
	var cs: CollisionShape3D = z._collider
	if cs == null:
		return 0.26
	var caps := cs.shape as CapsuleShape3D
	return caps.radius if caps != null else 0.26


# --- detonation ----------------------------------------------------------------

## `explode(x,y,radius,dmg)` (html:2576-2591), and the three things it does that the
## port must not lose: falloff that leaves 45% at the edge, a line-of-sight gate per
## target, and self-damage.
##
## The node is not freed here. It stops, hides, and holds the blast light for
## FLASH_TIME before freeing itself — which is the cheapest way to let a pooled
## light outlive the round that claimed it without a second piece of machinery to
## own the decay.
func _explode(at: Vector3) -> void:
	if _dead:
		return
	_dead = true
	vel = Vector3.ZERO
	global_position = at
	if _quad != null and is_instance_valid(_quad):
		_quad.visible = false

	if splash > 0.0 and splash_dmg > 0.0:
		_splash(at)
	_self_damage(at)

	# No `explode` cue is baked — sfx.gd's prebake list (`_prebake`, sfx.gd:204) has
	# no entry for one, and an unbaked id synthesises a generic thud on the main
	# thread the first time it is asked for, mid-fight. `death` is the longest and
	# lowest noise burst already resident (0.42 s, 8.0 decay, a 90 Hz body); at 0.55
	# pitch it is 0.76 s of 50 Hz, which is a blast. A dedicated bake belongs to
	# whoever owns sfx.gd next — the same trade `player._go_down` records.
	#
	# **AFTER the splash, and that ordering is load-bearing.** Every body damaged
	# above plays its own `hit` through `zombie.take_damage` — see `_hurt` for why
	# this port cannot yet suppress them the way html:2587 does. There are 14
	# positional voices (sfx.gd:22) and `_free_player_3d` evicts the one with the
	# LARGEST playback position, so among voices all started on this same frame it
	# evicts the OLDEST — which, played first, was the blast itself. A Monkey Bomb
	# landing in a crowd was therefore silent, drowned by the pings of the bodies it
	# was killing. Played last it is the newest voice and nothing that frame can take
	# it.
	Sfx.play_at("death", at, -1.0, 0.55)
	_flash()


func _splash(at: Vector3) -> void:
	var world3d := get_world_3d()
	for node in get_tree().get_nodes_in_group("zombies"):
		var z := node as Zombie
		if z == null or not is_instance_valid(z) or z.state == Zombie.State.DYING:
			continue
		var d := _axis_distance(at, z.global_position, z.centre().y * 2.0)
		if d > splash:
			continue
		# html:2586. Without it a blast reaches through geometry, which is the exact
		# failure `_cone_blast` shipped twice — and `los.gd:24` already cites this
		# line as the reason a body in the blast does not shield the one behind it.
		if not LOS.clear(world3d, at, z.centre()):
			continue
		_hurt(z, splash_dmg * (1.0 - d / splash * FALLOFF), true)


## `pd<radius*0.75` for `24*(1-pd/(radius*0.75))` (html:2590).
##
## **Line-of-sight gated, which the ancestor's is not.** The reference traces
## grenade damage to the player and the ancestor simply does not; a blast that
## reaches you through the wall you stepped behind is the one place its cheap
## version is visibly wrong, and every zombie in the same blast is already gated.
## The trace runs to the camera because that is where the player is looking from and
## it is the origin `_cone_blast` and the interaction scan both already use.
func _self_damage(at: Vector3) -> void:
	if player == null or not is_instance_valid(player) or splash <= 0.0:
		return
	var lim := splash * SELF_FRACTION
	if lim <= 0.0:
		return
	# The player capsule is 1.7 m tall and stands on the floor (player.gd:207).
	var pd := _axis_distance(at, player.global_position, 1.7)
	# Distance-scaled, where html:2578's `G.shake` is flat. A China Lake round put
	# down a 20 m corridor shaking the camera as hard as one at your feet is a cue
	# that tells the player something untrue about where the blast was.
	var felt := clampf(1.0 - pd / maxf(splash * 3.0, 0.001), 0.0, 1.0)
	if felt > 0.0:
		player.add_shake(BLAST_SHAKE * felt)
	if pd >= lim or player.is_downed:
		return
	if not LOS.clear(get_world_3d(), at, player.camera().global_position):
		return
	# `Math.round`, and it matters: the ancestor deals whole points here.
	player.take_damage(roundf(SELF_DAMAGE * (1.0 - pd / lim)))


## One damaged body, through the player's own payout path where there is a player —
## `_apply_hit` is what pays PTS_HIT, raises `hit_confirmed` for the HUD and
## `impact` for the blood puff, and a blast that skipped it would be the one damage
## source in the game with no feedback.
##
## `centre()` is the aim point in both cases, so a blast can never be scored as a
## headshot: it is `_height*0.5`, under every kind's `head_threshold()` (0.58 on a
## crawler and a hound, 0.70 on a walker). html:2587 and html:2606 both pass
## `false` for `head` outright, and BO1 pays a falling scale for a blast kill rather
## than 100 a body.
## **UNPORTED, AND IT IS A REAL DEPARTURE, NOT A SIMPLIFICATION.** The ancestor's
## sixth argument is `silent`, and the splash loop is the only caller that passes it
## true (`zombieDamage(z, dmg*(1-...), false, x, y, true)`, html:2587, against
## html:2606's direct hit which does not). It suppresses `Audio2.hit` and nothing
## else — the points, the drop roll and the death rattle all still land, which is
## why routing through `_apply_hit` is otherwise correct.
##
## The port has no way to pass it: the cue lives in `zombie.take_damage`
## (zombie.gd:897) and this package does not own that file. So one blast plays one
## `hit` per body IN THE SAME FRAME. Four bodies inside the Ray Gun's 1.7 m is the
## ordinary case and merely loud; the Monkey Bomb's 4.0 m against a 24-body cap is
## two dozen copies of one 0.09 s sample starting on the same sample index, which
## sums coherently — it is a click at roughly +20 dB over the single cue, on top of
## a detonation already playing at -1 dB. The ancestor's flag exists precisely
## because its author hit this.
##
## The fix is two lines in a file this package does not own and is in the report:
## `take_damage(..., silent := false)` and gating :897 on it. Until then `by_splash`
## is threaded but unread, deliberately — the argument is the record of what is
## missing, and deleting it would delete the only trace.
func _hurt(z: Zombie, amount: float, by_splash: bool) -> void:
	var _silent_unported := by_splash
	# The blast direction is from the detonation point outward, which is why the
	# origin has to be passed rather than recomputed at the far end: `_explode` moves
	# this node to `at` before calling, so `global_position` IS the blast centre.
	var cause: int = Zombie.Cause.BLAST if by_splash else Zombie.Cause.BULLET
	var dir := (z.centre() - global_position).normalized()
	if player != null and is_instance_valid(player):
		player._apply_hit(z, amount, z.centre(), cause, dir)
		return
	# Cause.BLAST was UNREACHABLE in the shipped game until this line: the splash
	# passed neither argument, so a Ray Gun or China Lake kill fell through to
	# `_die`'s away-from-the-player fallback and got SHOVE_BULLET (0.55) where it
	# should get SHOVE_BLAST (2.4). The enum value existed and nothing could ever
	# produce it except a Nuke.
	z.take_damage(amount, z.centre().y - z.global_position.y, false,
		cause, dir)


## Distance from a point to a body's vertical axis segment — its feet to the top of
## its head. Reduces to the ancestor's flat `hypot` whenever the blast is at body
## height, and stops a shell that went off on the floor from measuring an extra
## 0.91 m of nothing to every target's chest.
static func _axis_distance(from: Vector3, foot: Vector3, height: float) -> float:
	var y := clampf(from.y, foot.y, foot.y + maxf(height, 0.01))
	return from.distance_to(Vector3(foot.x, y, foot.z))


# --- the pooled lights ---------------------------------------------------------

func _claim_light() -> void:
	_ensure_lights()
	if _lights.is_empty():
		return
	_slot = _light_next
	_light_next = (_light_next + 1) % _lights.size()
	_light_owner[_slot] = get_instance_id()
	var l := _lights[_slot]
	l.light_color = RAY_LIGHT_COLOR
	l.light_energy = RAY_LIGHT_ENERGY
	l.omni_range = RAY_LIGHT_RANGE
	l.global_position = global_position
	l.visible = true


## Built once under whatever node the rounds live in, and revalidated rather than
## trusted: these are statics, so they outlive `reload_current_scene()` exactly as
## `quality_governor._kept_step` does — but unlike an int, a freed Node left in a
## static is a crash waiting for the next round fired.
func _ensure_lights() -> void:
	var host := get_parent()
	if host == null:
		return
	if _lights.size() == LIGHT_POOL and is_instance_valid(_lights[0]) \
			and _lights[0].is_inside_tree():
		return
	_lights.clear()
	_light_owner.clear()
	for i in LIGHT_POOL:
		var l := OmniLight3D.new()
		l.name = "ProjLight%d" % i
		# Shadowless, for the reason atmosphere.gd:93 gives about the muzzle flash:
		# OMNI_LIGHT_COUNT is a uniform rather than a shader define, so toggling one
		# of these cannot trigger a mid-fight shader recompile. A shadowed one would
		# also re-draw every instance it touches, six times, for a moving light.
		l.shadow_enabled = false
		l.visible = false
		host.add_child(l)
		_lights.append(l)
		_light_owner.append(0)
	_light_next = 0


## The light this round still owns, or null if a later round took the slot.
func _own_light() -> OmniLight3D:
	if _slot < 0 or _slot >= _lights.size():
		return null
	if not is_instance_valid(_lights[_slot]):
		_slot = -1
		return null
	if _light_owner[_slot] != get_instance_id():
		_slot = -1
		return null
	return _lights[_slot]


func _move_light() -> void:
	var l := _own_light()
	if l != null:
		l.global_position = global_position


func _release_light() -> void:
	var l := _own_light()
	if l == null:
		return
	l.visible = false
	_light_owner[_slot] = 0
	_slot = -1


## The blast. Takes a slot if this round never had one — a China Lake shell flies
## dark and only its detonation is a light.
func _flash() -> void:
	_flash_t = FLASH_TIME
	if _own_light() == null:
		_claim_light()
	var l := _own_light()
	if l == null:
		return
	l.light_color = FLASH_COLOR
	l.omni_range = maxf(splash, 1.0) * 2.0
	l.light_energy = FLASH_ENERGY
	l.global_position = global_position
	l.visible = true


func _tick_flash(dt: float) -> void:
	_flash_t -= dt
	var l := _own_light()
	if l != null:
		l.light_energy = FLASH_ENERGY * maxf(0.0, _flash_t / FLASH_TIME)
	if _flash_t <= 0.0:
		_release_light()
		queue_free()


# --- the billboard -------------------------------------------------------------

static func _glow_mesh(k: String) -> ArrayMesh:
	if _meshes.has(k):
		var cached: ArrayMesh = _meshes[k]
		return cached
	var tint: Color = TINT.get(k, TINT["ray"])
	var col := tint.srgb_to_linear()
	col.a = tint.a
	var s := QUAD_SIZE * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Local +X is camera right and +Y camera up under the shared material's
	# billboard, exactly as `Zombie._eye_quad` assumes.
	_vertex(st, col, Vector3(-s, -s, 0.0), Vector2(0.0, 1.0))
	_vertex(st, col, Vector3(s, -s, 0.0), Vector2(1.0, 1.0))
	_vertex(st, col, Vector3(s, s, 0.0), Vector2(1.0, 0.0))
	_vertex(st, col, Vector3(-s, -s, 0.0), Vector2(0.0, 1.0))
	_vertex(st, col, Vector3(s, s, 0.0), Vector2(1.0, 0.0))
	_vertex(st, col, Vector3(-s, s, 0.0), Vector2(0.0, 0.0))
	var mesh := st.commit()
	_meshes[k] = mesh
	return mesh


static func _vertex(st: SurfaceTool, col: Color, p: Vector3, uv: Vector2) -> void:
	st.set_normal(Vector3(0.0, 0.0, 1.0))
	st.set_color(col)
	st.set_uv(uv)
	st.add_vertex(p)
