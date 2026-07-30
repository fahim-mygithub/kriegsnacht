extends RefCounted

## Projectiles, blast falloff, aim-down-sights and the two throwables.
##
## None of it can be checked by playing. A round that tunnels through a wall leaves
## nothing behind — no impact, no sound, no corpse — so it reads as a miss; a blast
## that reaches through geometry reads as a good throw; and "the Ray Gun is worth
## its box roll" is a claim about a number nobody can see. Every one of those
## shipped once already in this project's Thundergun.
##
## **Bounded at both ends, everywhere.** The rule this file inherits from
## `downed.gd`: a check that only ever asserts the refusal passes equally well
## against a subsystem that has stopped working altogether. So the wall tests fire
## the same round at the same range down two of the map's own bearings — one with
## geometry across it and one without — and the ADS tests assert both the narrowed
## value and that the hip value is still what it was.
##
## **It fires at the level's real colliders, not at a wall it builds.** `Verify.run`
## is synchronous and `--verify` reaches it through `call_deferred` from `_ready`,
## so a StaticBody3D added inside it is never flushed into the Jolt space and every
## ray fired at it comes back empty — which looks exactly like a missing occlusion
## test. `downed.gd` measured that; this file takes it as given and uses the
## geometry world_builder already put in the space.
##
## **It must not write the player's save file.** `died` is what main.gd turns into
## `Game.record_run()`, and the only self-damage in the game lives in this
## subsystem — so every listener comes off for the duration and the player's health
## is parked somewhere a 24-point blast cannot reach.

const PROJ := preload("res://scripts/entities/projectile.gd")
const THROWABLES := preload("res://scripts/systems/throwables.gd")
const VIEWMODEL := preload("res://scripts/entities/viewmodel.gd")
const LOS := preload("res://scripts/world/los.gd")

## The tick the whole tunnelling argument is written against. `_physics_process`
## runs at Godot's default 60 Hz; change this and the thing being measured stops
## existing.
const TICK := 1.0 / 60.0

## Ranges the bearing search tries, nearest first, until it finds one that offers
## BOTH a walled and an open heading. Swept rather than fixed for the reason
## downed.gd records: the player spawns in the middle of an open room, so at 3 m
## every bearing is clear and a fixed range finds no wall to be stopped by.
const RANGES: Array[float] = [3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]
const BEARINGS := 64

## A synthetic blast big enough to reach across the wall the search finds. The
## occlusion tests are about the sight line, not about the Ray Gun's 1.7 m — a
## radius that cannot reach the far side would "pass" with the gate deleted.
const TEST_SPLASH_DMG := 900.0

## High enough that a body survives a direct Ray Gun hit and its own splash, so the
## damage can be READ rather than inferred from a corpse. Round 25 is 4367 hp
## against the ~800 one round delivers.
const TOUGH_ROUND := 25

## Speeds at which one physics tick covers at least one whole map tile, so the
## destination sample lands cleanly past the wall and only a swept test can see it.
## A tile is 1 m and the tick is 1/60, so 60 m/s is exactly the boundary and the
## first entry is the first speed at which the cheap version stops being correct by
## accident. Climbing rather than a single value: a failure then names the speed the
## wall test survived to, which is the number this file exists to pin down.
const TILE_HOP: Array[float] = [61.0, 90.0, 140.0, 220.0]


## Staged once for the whole module rather than per section, because the thing
## being protected — the player's `died` listeners, and therefore the real save
## file — is not something a section should be able to forget. Double Tap is
## cleared for the same reason `downed.gd` clears Insta-Kill: every damage figure
## below is measured against the table, and a perk left standing by an earlier
## check would scale one side of the comparison and not the other.
static func run(v: Verify, main: Node3D) -> void:
	var state_was: int = Game.state
	Game.set_state(Game.STATE_PLAY)
	var stage := _stage(main)
	Game.perks.clear()
	Game.insta_kill = 0.0
	Game.dbl_points = 0.0

	_launch_parameters(v)
	_falloff(v)
	_bindings(v)
	_wiring(v, main)
	_tunnelling(v, main)
	_splash_occlusion(v, main)
	_self_damage(v, main)
	_ray_gun_earns_its_slot(v, main)
	_light_pool(v, main)
	_ads(v, main)
	_throwables(v, main)

	_clear_projectiles(main)
	_unstage(main, stage)
	Game.set_state(state_was)


# --- the ancestor's numbers ----------------------------------------------------

## Pinned with their lines, because these are the whole of what "ported" means for
## this subsystem and every one of them is a value a later retune could quietly
## round off.
static func _launch_parameters(v: Verify) -> void:
	v.check("the ray leaves at 23 m/s with no arc, the shell at 16 with one",
		v.near(PROJ.RAY_SPEED, 23.0) and v.near(PROJ.GRENADE_SPEED, 16.0)
			and v.near(PROJ.GRENADE_RISE, 1.1) and v.near(PROJ.GRENADE_GRAV, 2.6),
		"ray=%.1f shell=%.1f rise=%.2f grav=%.2f" % [PROJ.RAY_SPEED,
			PROJ.GRENADE_SPEED, PROJ.GRENADE_RISE, PROJ.GRENADE_GRAV])
	v.check("the body is 0.30 m and the fuse 3 s, html:2561",
		v.near(PROJ.BODY, 0.30) and v.near(PROJ.RADIUS, 0.15)
			and v.near(PROJ.LIFE, 3.0))
	# html:2556 is an absolute 1.42 in a world with no camera. 1.55 - 1.42 = 0.13 is
	# the same statement expressed against an eye that can now look up and down, and
	# it only stays the same statement while EYE is 1.55.
	v.check("the muzzle sits 0.35 m ahead of the eye and 0.13 m below it",
		v.near(PROJ.SPAWN_AHEAD, 0.35)
			and v.near(Player.EYE - PROJ.SPAWN_DROP, 1.42, 0.0001),
		"ahead=%.2f eye-drop=%.3f" % [PROJ.SPAWN_AHEAD, Player.EYE - PROJ.SPAWN_DROP])
	# The dead data the whole item is about. Stated here so that a table edit which
	# zeroes either one fails next to the code that reads it rather than nowhere.
	var ray := Weapons.spec("raygun")
	var lake := Weapons.spec("chinalake")
	v.check("the two projectile weapons still declare the payload this reads",
		String(ray.proj) == "ray" and v.near(ray.splash, 1.7) and v.near(ray.splash_dmg, 620.0)
			and String(lake.proj) == "grenade" and v.near(lake.splash, 2.6)
			and v.near(lake.splash_dmg, 1150.0),
		"ray %s/%.1f/%.0f lake %s/%.1f/%.0f" % [ray.proj, ray.splash, ray.splash_dmg,
			lake.proj, lake.splash, lake.splash_dmg])


## `dmg*(1 - d/radius*0.55)` (html:2587). **THE EDGE OF THE BLAST DOES 45%, NOT
## ZERO**, and that is not a detail: it is the difference between a weapon that
## needs the horde stacked on one tile and one worth carrying. Asserted as
## arithmetic rather than by firing, so the number is pinned even on a build where
## nothing can be spawned.
static func _falloff(v: Verify) -> void:
	var edge := 1.0 - 1.0 * PROJ.FALLOFF
	var mid := 1.0 - 0.5 * PROJ.FALLOFF
	v.check("blast falloff is 100% at the centre and 45% at the edge, not 0%",
		v.near(1.0 - 0.0 * PROJ.FALLOFF, 1.0) and v.near(edge, 0.45)
			and v.near(mid, 0.725),
		"centre=1.000 mid=%.3f edge=%.3f" % [mid, edge])
	v.check("self-damage is 24 inside three quarters of the radius, html:2590",
		v.near(PROJ.SELF_DAMAGE, 24.0) and v.near(PROJ.SELF_FRACTION, 0.75))


# --- the keys ------------------------------------------------------------------

## This package added three input actions, and project.godot belongs to no package,
## so they were bound by a different hand than the one that named them.
##
## **Both halves matter and only one of them is obvious.** A MISSING action is loud —
## `player._bind_action` pushes a named warning at boot and the feature is merely
## dead. A DUPLICATE binding is silent and worse: Godot dispatches one key press to
## every action that claims it, so `throw_tactical` on Q — which is `swap_weapon` —
## swapped the weapon and threw a Monkey Bomb on the same press. The lure then
## dragged the horde onto a fixed point, so it read as "the round went strange",
## which is not a sentence anybody debugs by looking at a keymap.
##
## Swept over the whole InputMap rather than over this package's three, because the
## next package to add an action has the same problem and no reason to look here.
## `ui_*` is excluded: those are the engine's own and they are SUPPOSED to double up
## with game keys (`pause` and `ui_cancel` are both Escape, by design).
static func _bindings(v: Verify) -> void:
	var wanted: Array[String] = ["ads", "throw_frag", "throw_tactical"]
	var missing := ""
	for a: String in wanted:
		if not InputMap.has_action(a):
			missing += a + " "
	v.check("the three actions ADS and the throwables poll are bound",
		missing.is_empty(), "unbound: %s — see project.godot [input]" % missing)
	if not missing.is_empty():
		return

	# One entry per physical thing a player can press, mapped to the actions that
	# claim it. Physical keycodes rather than keycodes, because that is what the
	# bindings use and a layout-independent binding is the point of them.
	var claimed := {}
	for a: StringName in InputMap.get_actions():
		var name := String(a)
		if name.begins_with("ui_"):
			continue
		for ev: InputEvent in InputMap.action_get_events(a):
			var key := ""
			var k := ev as InputEventKey
			var m := ev as InputEventMouseButton
			if k != null:
				key = "key:%d" % k.physical_keycode
			elif m != null:
				key = "mouse:%d" % m.button_index
			else:
				continue
			if not claimed.has(key):
				claimed[key] = []
			var who: Array = claimed[key]
			who.append(name)

	var clashes := ""
	for key: String in claimed:
		var who: Array = claimed[key]
		if who.size() > 1:
			clashes += "%s -> %s  " % [key, who]
	v.check("no two input actions claim the same key, so one press is one action",
		clashes.is_empty(), clashes)


# --- the branch that was dead --------------------------------------------------

## That `def.proj` reaches a projectile at all. Everything else in this file could
## pass with `_shoot` still falling through to `_hitscan` for the Ray Gun, which is
## precisely the state the port shipped in.
static func _wiring(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var guns_was: Array[Dictionary] = p.guns.duplicate()
	var slot_was := p.slot
	var before := _count_projectiles(main)

	p.guns = [Weapons.make_gun("raygun", false)]
	p.slot = 0
	p._shoot(p.guns[0])
	var made := _count_projectiles(main) - before
	v.check("firing the Ray Gun puts a projectile in the world",
		made == 1, "spawned %d" % made)

	# ...and a hitscan weapon still does not, or the branch is inverted.
	p.guns = [Weapons.make_gun("m14", false)]
	p.slot = 0
	var mid := _count_projectiles(main)
	p._shoot(p.guns[0])
	v.check("firing the M14 does not", _count_projectiles(main) == mid,
		"spawned %d" % (_count_projectiles(main) - mid))

	_clear_projectiles(main)
	p.guns = guns_was
	p.slot = slot_was


# --- the tunnelling case -------------------------------------------------------

## **THE REASON THE INTEGRATION IS SWEPT**, at the real speed and the real tick.
##
## **The version of this that shipped first did not test what it said it tested,
## and the control run is on the record.** It asserted that a ray at 23 m/s is
## stopped by a wall, and justified the sweep by claiming the level is a zero-
## thickness face soup in which a discrete point sample can never land inside
## anything. Replacing `_step`'s swept ray with a bare `intersect_point` at the
## destination passes that assertion, and every other one in the suite — 451/0.
## Deleting the wall test outright is what finally failed it. So the old pair
## discriminated "a wall test" from "no wall test", which nobody was going to get
## wrong, and said nothing at all about sweeping.
##
## The arithmetic was measured against the wrong quantity. What has to be thicker
## than one tick of travel is the WALL, and a solid tile here is a full 1 x 1 x
## 2.8 m block — `_emit_wall_faces` skips the faces between two solid tiles, so the
## trimesh is a closed shell and Jolt resolves inside/outside against it. 0.383 m a
## tick puts about two and a half samples inside a 1 m wall. Comparing the step to
## the projectile's own 0.30 m body compares it to a number nothing collides with.
##
## So the speed sweep below is the assertion that has teeth: a round that clears a
## whole tile between two ticks is the case a discrete test cannot see, the 1 m
## margin only holds under 60 m/s, and that ceiling is written down nowhere else.
## Nothing in the game is that fast today, which is exactly why it needs an
## assertion rather than a reader's attention.
##
## Both ends everywhere: the walled bearing proves the round is stopped, and the
## open bearing proves the same round at the same speed still travels past that
## range — without which a projectile that simply died on its first tick would pass.
static func _tunnelling(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var cam := p.camera()
	var yaw_was := p.rotation.y
	var found := _bearings(main, p)

	v.check("a ray moves further in one tick than its own body is wide",
		PROJ.RAY_SPEED * TICK > PROJ.BODY,
		"%.3f m per tick against a %.2f m body" % [PROJ.RAY_SPEED * TICK, PROJ.BODY])
	v.check("the map offers a walled and an open bearing to fire along",
		not found.is_empty(), "none of %s worked from %s" % [RANGES, cam.global_position])
	if found.is_empty():
		return
	var dist: float = found[0]
	var walled: float = found[1]
	var open: float = found[2]

	p.rotation.y = walled
	var blocked := _fly(main, p, _cfg("ray", 1.7, 620.0), 60)
	var stopped: Vector3 = blocked[0]
	var died: bool = blocked[1]
	var near_side := LOS.clear(main.get_world_3d(), cam.global_position, stopped)
	var travel := cam.global_position.distance_to(stopped)

	p.rotation.y = open
	var clear_run := _fly(main, p, _cfg("ray", 1.7, 620.0), 60)
	var far: Vector3 = clear_run[0]
	var reached := cam.global_position.distance_to(far)

	v.check("a full-speed ray is stopped by a wall and never reaches the far side",
		died and near_side and travel < dist + 0.6,
		"stopped after %.2f m (wall at ~%.1f m), detonated=%s, still in sight=%s" % [
			travel, dist, died, near_side])
	# Against the walled run rather than against the range, because the range is
	# only where the sight line was tested — the wall itself can be anywhere short
	# of it, so "further than dist" would be an assumption. "Further than the round
	# that was stopped" is a measurement.
	v.check("...and the same round down an open bearing travels considerably further",
		reached > travel + 0.5 and reached > dist - 0.3,
		"open %.2f m against walled %.2f m, sight line clear to %.1f m" % [
			reached, travel, dist])

	# THE ONE A DISCRETE TEST FAILS. Everything above passes against an
	# `intersect_point` at the destination — measured, see the docstring. This does
	# not: at TILE_HOP m/s the round clears a whole 1 m tile between two samples, so
	# the only thing that can stop it is a test that looks at the SEGMENT.
	#
	# Swept up from the real speed rather than jumping straight to the top, so a
	# failure reports the speed at which the wall stopped working rather than only
	# that it did. The margin is a real quantity: it is the speed ceiling under which
	# the cheap version happens to be correct on this map, and nothing else records
	# what it is.
	var leaked := ""
	var last_ok := 0.0
	p.rotation.y = walled
	for speed: float in TILE_HOP:
		var cfg := _cfg("ray", 1.7, 620.0)
		# 12 ticks is 2.4 tiles at the slowest of these and 20 at the fastest, which
		# is past the wall in every case and short of the far side of the map.
		var fast := _fly_at(main, p, cfg, speed, 12)
		var where: Vector3 = fast[0]
		var boom: bool = fast[1]
		var got := cam.global_position.distance_to(where)
		if boom and got < dist + 1.2 and LOS.clear(main.get_world_3d(),
				cam.global_position, where):
			last_ok = speed
			continue
		leaked += "%.0f m/s reached %.2f m (detonated=%s)  " % [speed, got, boom]
	v.check("a round that clears a whole wall tile in one tick is still stopped by it",
		leaked.is_empty(),
		"wall at ~%.1f m; last speed that held was %.0f m/s; %s" % [
			dist, last_ok, leaked])

	p.rotation.y = yaw_was
	_clear_projectiles(main)


# --- the blast does not cross geometry -----------------------------------------

## html:2586, `if(!hasLOS(x,y,z.x,z.y)) continue;`. `los.gd:24` already cites this
## line for the rule that a body in the blast does not shield the one behind it —
## the converse, that a *wall* does, is what this asserts.
##
## Both ends again, at one range, so the pair differs by geometry and by nothing
## else: a walled bearing at 8 m against an open one at 3 m would also differ in
## distance and "it survived" would have two candidate explanations.
static func _splash_occlusion(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var cam := p.camera()
	var yaw_was := p.rotation.y
	var found := _bearings(main, p)
	if found.is_empty():
		v.check("the map offers a bearing pair to test blast occlusion along", false,
			"no walled/open pair from %s" % cam.global_position)
		return
	var dist: float = found[0]
	var walled: float = found[1]
	var open: float = found[2]
	# Comfortably past the wall, so a survivor survived the sight line rather than
	# the radius.
	var cfg := _cfg("grenade", dist + 2.0, TEST_SPLASH_DMG)

	p.rotation.y = walled
	var behind := _target(main, p, dist)
	var hp_behind := behind.hp
	_detonate(main, p, cfg, cam.global_position)
	var shielded := behind.hp
	_drop(behind)

	p.rotation.y = open
	var exposed := _target(main, p, dist)
	var hp_open := exposed.hp
	_detonate(main, p, cfg, cam.global_position)
	var hurt := exposed.hp
	_drop(exposed)

	v.check("splash is stopped by a wall and lands along an open bearing at the same range",
		v.near(shielded, hp_behind, 0.01) and hurt < hp_open - 1.0,
		"at %.1f m — walled: %.0f of %.0f hp / open: %.0f of %.0f hp" % [
			dist, shielded, hp_behind, hurt, hp_open])

	p.rotation.y = yaw_was
	_clear_projectiles(main)


# --- the only self-damage in the game ------------------------------------------

## `if(pd<radius*0.75 && !P.downed) hurtPlayer(...)` (html:2590). It is what stops
## the China Lake being a panic button, and it is exactly the kind of rule that
## survives review and is then wired to nothing.
static func _self_damage(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var here := p.global_position
	var cfg := _cfg("grenade", 2.6, 1150.0)
	var lim: float = 2.6 * PROJ.SELF_FRACTION

	# At your own feet: the full 24, less whatever rounding does to it.
	p.hp = 1000.0
	_detonate(main, p, cfg, here + Vector3(0.0, 0.8, 0.0))
	var point_blank := 1000.0 - p.hp

	# Just inside the ring, where the falloff has nearly finished: a positive but
	# small number, which is what proves the scaling rather than the branch.
	p.hp = 1000.0
	_detonate(main, p, cfg, here + Vector3(lim * 0.9, 0.8, 0.0))
	var edge := 1000.0 - p.hp

	# ...and outside it, where nothing at all may land. `radius*0.75` is a smaller
	# circle than the splash, so a blast can hurt a zombie standing where the player
	# would take nothing — which is the whole design of the number.
	p.hp = 1000.0
	_detonate(main, p, cfg, here + Vector3(2.5, 0.8, 0.0))
	var outside := 1000.0 - p.hp

	v.check("a blast at your feet costs the full 24 and one at the ring's edge costs almost nothing",
		v.near(point_blank, PROJ.SELF_DAMAGE, 0.51) and edge > 0.0
			and edge < PROJ.SELF_DAMAGE * 0.25,
		"feet=%.1f edge=%.1f (limit %.2f m)" % [point_blank, edge, lim])
	v.check("...and one outside three quarters of the radius costs nothing at all",
		v.near(outside, 0.0, 0.001), "took %.1f" % outside)

	_clear_projectiles(main)


# --- the weapon this whole item is about ---------------------------------------

## With `proj` unimplemented the Ray Gun was a 180-damage single-target hitscan
## against the 500-point M14's 185 — strictly worse, for a Mystery Box roll. Both
## halves of the fix are measured here: what one round does to the body it hits,
## and what it does to the four standing round it.
static func _ray_gun_earns_its_slot(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var cam := p.camera()
	var yaw_was := p.rotation.y
	var found := _bearings(main, p)
	if found.is_empty():
		v.check("the map offers an open bearing to fire the Ray Gun down", false, "")
		return
	var dist: float = found[0]
	var open: float = found[2]
	p.rotation.y = open

	var m14: float = float(Weapons.spec("m14").dmg) * Game.damage_scale()
	var spec := Weapons.spec("raygun")

	# One tough body, hit directly. It has to survive the round for the damage to be
	# readable at all — a corpse only says "more than its health".
	var solo := _target(main, p, minf(dist, 4.0), TOUGH_ROUND)
	var solo_before := solo.hp
	_fly(main, p, _cfg("ray", float(spec.splash), float(spec.splash_dmg)), 60)
	var solo_dealt := solo_before - solo.hp
	_drop(solo)
	_clear_projectiles(main)

	v.check("a direct Ray Gun hit delivers its impact AND its splash, not just its impact",
		solo_dealt > float(spec.dmg) * 1.5 and solo_dealt > m14 * 4.0,
		"dealt %.0f — impact alone is %.0f, one M14 round is %.0f" % [
			solo_dealt, float(spec.dmg), m14])

	# ...and the case the weapon is actually for. Four bodies inside the 1.7 m
	# blast, which is a tight but entirely ordinary knot of a horde.
	var group: Array[Zombie] = []
	var before := 0.0
	var centre := cam.global_position + _flat_forward(cam) * minf(dist, 4.0)
	var ring: Array[Vector2] = [Vector2(0.45, 0.0), Vector2(-0.45, 0.0),
		Vector2(0.0, 0.45), Vector2(0.0, -0.45)]
	for off: Vector2 in ring:
		var z := Zombie.create("zombie", 0, TOUGH_ROUND, false)
		main.add_child(z)
		z.add_to_group("zombies")
		z.global_position = Vector3(centre.x + off.x, 0.0, centre.z + off.y)
		before += z.hp
		group.append(z)
	_detonate(main, p, _cfg("ray", float(spec.splash), float(spec.splash_dmg)), centre)
	var after := 0.0
	for z: Zombie in group:
		after += z.hp
	var total := before - after
	for z: Zombie in group:
		_drop(z)

	v.check("one Ray Gun round out-damages one M14 round on a group by an order of magnitude",
		total > m14 * 8.0,
		"%.0f across four bodies against the M14's %.0f" % [total, m14])
	# The number that makes it true, stated separately: without the edge doing 45%
	# the outer pair would contribute nothing and the ratio would halve.
	v.check("...and every body in the blast took damage, not just the nearest",
		_all_hurt(group), "some bodies in the radius took nothing")

	p.rotation.y = yaw_was
	_clear_projectiles(main)


# --- the travelling light ------------------------------------------------------

## Pooled, and bounded. Five rounds in the air must not be five new lights: the
## renderer's per-object cap is 8 and the level already spawns 8 room lamps plus a
## muzzle flash, so an unbounded pool silently evicts a room lamp from a wall.
static func _light_pool(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var before := _count_lights(main)
	var made: Array[Area3D] = []
	for i in 5:
		made.append(_spawn(main, p, _cfg("ray", 1.7, 620.0),
			p.camera().global_position, Vector3(0.0, 0.0, 0.0)))
	var lights := _count_lights(main)
	v.check("five rounds in the air share a fixed pool of travelling lights",
		lights - before <= PROJ.LIGHT_POOL and PROJ.LIGHT_POOL > 0,
		"pool grew by %d, cap is %d" % [lights - before, PROJ.LIGHT_POOL])
	# The Ray Gun's identity, asserted as a fact about the node rather than about a
	# rendered frame: without a light this is a slow bullet.
	# Every round asks; only LIGHT_POOL of them can be answered at once, and the
	# round-robin means the answer goes to the NEWEST — which is the one nearest the
	# player and the one being aimed. Counted off the lights rather than off the
	# rounds, because a round whose slot has been taken from it still remembers the
	# index until the next time it looks.
	var asked := 0
	for pr: Area3D in made:
		if int(pr.get("_slot")) >= 0:
			asked += 1
	var on := 0
	for l: OmniLight3D in PROJ._lights:
		if is_instance_valid(l) and l.visible:
			on += 1
	v.check("every ray asks for a travelling light and exactly the pool is lit",
		asked == made.size() and on == PROJ.LIGHT_POOL,
		"%d of %d rounds claimed a slot, %d lights on, pool is %d" % [
			asked, made.size(), on, PROJ.LIGHT_POOL])
	# Shadowless: OMNI_LIGHT_COUNT is a uniform rather than a define, so a shadowed
	# one would also be a mid-fight shader recompile on a platform with no cache.
	var shadowed := ""
	for l: OmniLight3D in PROJ._lights:
		if is_instance_valid(l) and l.shadow_enabled:
			shadowed += l.name + " "
	v.check("no travelling light casts a shadow", shadowed.is_empty(), shadowed)
	_clear_projectiles(main)


# --- aim down sights -----------------------------------------------------------

## The four effects, and the one-writer rule the brief puts hardest on this item.
static func _ads(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var cam := p.camera()
	var vm: Node3D = main.viewmodel
	var ads_was: float = p._ads
	var head := p._head

	p._ads = 0.0
	p._apply_fov()
	var hip_fov := cam.fov
	var hip_spread := p._spread_rad(Weapons.spec("m14"))
	var pitch_was := head.rotation.x
	var pivot_was: Vector3 = p._recoil_pivot.position
	# **Forced WHILE THE CAMERA IS STILL AT THE HIP, and read again later rather than
	# measured later.** `viewmodel._measure()` caches on first call and bakes in
	# `tan(_cam.fov/2)/tan(VIEWMODEL_FOV/2)` as it goes (viewmodel.gd:829), so the
	# first caller in the whole suite decides the ratio every later caller sees. This
	# section narrows the camera by a third; if it were ever to run before
	# `verify.gd::_viewmodel`, M-VMCLIP — another package's no-clip SAFETY assertion —
	# would be silently measured at the sighted ratio, come out ~30% small and pass
	# against a weapon that clips. Today the order saves us. Order is not a guarantee.
	# Annotated, not inferred: `vm` is declared `Node3D`, so every call on it comes
	# back Variant and inference through one is a hard parse error.
	var widest: float = vm.max_screen_radius()

	p._ads = 1.0
	p._apply_fov()
	var aim_fov := cam.fov
	var aim_spread := p._spread_rad(Weapons.spec("m14"))

	v.check("the sights narrow the field of view and the hip value is unchanged",
		v.near(aim_fov, hip_fov * Player.ADS_FOV_MULT, 0.001) and aim_fov < hip_fov,
		"hip=%.2f sighted=%.2f" % [hip_fov, aim_fov])
	v.check("the sights tighten the cone without closing it",
		aim_spread < hip_spread and aim_spread > 0.0
			and v.near(aim_spread, hip_spread * Player.ADS_SPREAD, 0.0001),
		"hip=%.5f rad sighted=%.5f rad" % [hip_spread, aim_spread])
	v.check("the sights cost movement speed, and not all of it",
		Player.ADS_MOVE < 1.0 and Player.ADS_MOVE > 0.25,
		"%.2f" % Player.ADS_MOVE)

	# ONE WRITER PER NODE. Aiming is a field of view and a weapon pose; it is not a
	# rotation of the view, and the crosshair must not move. Head belongs to the
	# mouse, RecoilPivot to the spring, Camera3D's position to the bob.
	v.check("ADS writes the camera's field of view and nothing else in the chain",
		v.near(head.rotation.x, pitch_was) and p._recoil_pivot.position == pivot_was
			and v.near(head.position.y, head.position.y)
			and v.near(cam.position.x, 0.0, 0.001),
		"pitch %.5f->%.5f pivot %s cam.x %.5f" % [pitch_was, head.rotation.x,
			p._recoil_pivot.position, cam.position.x])

	# THE INTERACTION viewmodel.gd WARNS ABOUT. That file draws the weapon through a
	# fixed 55 degree projection whatever the camera does, so the gun is drawn
	# `tan(cam/2)/tan(vm/2)` wider than the world. Narrowing the camera drives that
	# ratio toward 1 — the sighted weapon is composited through the same lens as the
	# world, which is why the barrel lines up at the sights and does not at the hip.
	var hip_ratio := tan(0.5 * deg_to_rad(hip_fov)) \
		/ tan(0.5 * deg_to_rad(VIEWMODEL.VIEWMODEL_FOV))
	var aim_ratio := tan(0.5 * deg_to_rad(aim_fov)) \
		/ tan(0.5 * deg_to_rad(VIEWMODEL.VIEWMODEL_FOV))
	v.check("at the sights the weapon is drawn through the same lens as the world",
		absf(aim_ratio - 1.0) < 0.05 and hip_ratio > 1.3,
		"hip ratio %.4f, sighted ratio %.4f" % [hip_ratio, aim_ratio])
	# ...and therefore M-VMCLIP can only get safer. `max_screen_radius()` scales with
	# that ratio, so a narrower camera cannot invalidate the no-clip guarantee — the
	# cached measurement stays an upper bound.
	v.check("narrowing the camera cannot break the viewmodel's no-clip guarantee",
		aim_ratio < hip_ratio and widest < Player.RADIUS,
		"widest %.4f at the hip ratio against %.3f" % [widest, Player.RADIUS])

	p._ads = ads_was
	p._apply_fov()


# --- grenades and the Monkey Bomb ----------------------------------------------

static func _throwables(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var th = p.throwables()
	if th == null:
		v.check("the player carries a throwables pouch", false, "null")
		return

	var frag_was: int = th.count(THROWABLES.FRAG)
	var monkey_was: int = th.count(THROWABLES.MONKEY)
	th.counts[THROWABLES.FRAG] = 2
	th.counts[THROWABLES.MONKEY] = 0
	p.hp = 1000.0

	v.check("the player starts with two frags and no Monkey Bomb, and neither exceeds four",
		int(THROWABLES.SPEC[THROWABLES.FRAG].start) == 2
			and int(THROWABLES.SPEC[THROWABLES.MONKEY].start) == 0
			and int(THROWABLES.SPEC[THROWABLES.FRAG].max) == 4
			and int(THROWABLES.SPEC[THROWABLES.MONKEY].max) == 4)

	# A throw spends one, and an empty pouch spends nothing — which is the half that
	# would otherwise let a player throw a grenade they do not have.
	th.press(THROWABLES.FRAG)
	th.release(THROWABLES.FRAG)
	# `th` is untyped (the accessor declares no return type), so every value it
	# hands back is a Variant and inference through one is a hard parse error.
	var after_one: int = th.count(THROWABLES.FRAG)
	th.counts[THROWABLES.FRAG] = 0
	var made := _count_projectiles(main)
	th.press(THROWABLES.FRAG)
	th.release(THROWABLES.FRAG)
	v.check("throwing a frag spends one and an empty pouch throws nothing",
		after_one == 1 and _count_projectiles(main) == made,
		"after one throw: %d" % after_one)

	# COOKED OFF IN THE HAND. The reference's punishment for holding one too long,
	# and the only thing that makes the cook a decision instead of free damage.
	th.counts[THROWABLES.FRAG] = 1
	p.hp = 1000.0
	th.press(THROWABLES.FRAG)
	var fuse: float = THROWABLES.SPEC[THROWABLES.FRAG].fuse
	# Half a second short of the fuse, then past it — a single sample after the end
	# would pass equally well against a grenade that went off on the first tick.
	for i in int((fuse - 0.5) * 60.0):
		th.tick(TICK)
	var still_held: bool = th.cook_fraction() > 0.0 and v.near(p.hp, 1000.0, 0.001)
	for i in 40:
		th.tick(TICK)
		# The cook-off leaves the hand as an ordinary projectile with nothing left on
		# its fuse, and a projectile only detonates inside its own physics step —
		# which nothing is driving while Verify.run is on the stack.
		_step_projectiles(main, 1)
	var went_off: bool = th.count(THROWABLES.FRAG) == 0 and p.hp < 1000.0
	v.check("a frag cooked past its fuse is still in hand at 2.0 s and has gone off by 3.2 s",
		still_held and went_off,
		"at 2.0 s: cooking=%.2f hp=%.0f / after: left=%d hp=%.0f" % [
			th.cook_fraction(), 1000.0 if still_held else p.hp,
			th.count(THROWABLES.FRAG), p.hp])
	_clear_projectiles(main)

	# THE MONKEY BOMB'S WHOLE AI CONTRACT: a position and a flag. Nothing else about
	# it is a system, which is the reason it fits in this package at all.
	v.check("no lure is live before one is thrown", not THROWABLES.lure_active())
	th.counts[THROWABLES.MONKEY] = 1
	p.hp = 1000.0
	th.press(THROWABLES.MONKEY)
	th.tick(TICK)
	var live := THROWABLES.lure_active()
	var at := THROWABLES.lure_position()
	var near_player := at.distance_to(p.global_position) < 3.0
	# The contract the AI actually calls, rather than the two fields behind it.
	var fallback := Vector2(999.0, 999.0)
	var goal := THROWABLES.flow_goal(fallback)
	v.check("a thrown Monkey Bomb becomes the horde's goal instead of the player",
		live and near_player and goal != fallback
			and v.near(goal.x, at.x, 0.001) and v.near(goal.y, at.z, 0.001),
		"active=%s at=%s goal=%s" % [live, at, goal])

	# ...AND A REAL ZOMBIE ACTUALLY WALKS AT IT. Everything above this line is
	# throwables.gd's own getter agreeing with throwables.gd's own setter, and that is
	# exactly the shape of assertion that let the whole throwable ship inert: the AI
	# reads `Game.lure_position` (zombie.gd:794) and this file was publishing to a
	# private static nothing else could see, so `"lure_position" in Game` was false,
	# every zombie fell back to the player and throwing a monkey did nothing at all.
	# A getter cannot detect that; a body can.
	#
	# Flown out first, so the monkey and the player are metres apart and "it is
	# steering at the monkey" is distinguishable from "it is steering at the player
	# and the monkey happens to be in his pocket".
	var monkey: Area3D = th._monkey
	for i in 24:
		if monkey == null or not is_instance_valid(monkey) or monkey.dead():
			break
		monkey._physics_process(TICK)
		th.tick(TICK)
	var flown := THROWABLES.lure_position()
	var walker := Zombie.create("zombie", 0, 1, false)
	main.add_child(walker)
	walker.target = p
	walker.global_position = p.global_position - Vector3(0.0, 0.0, 6.0)
	var lured := walker._goal_point()
	var to_lure := lured.distance_to(Vector2(flown.x, flown.z))
	var from_player := lured.distance_to(
		Vector2(p.global_position.x, p.global_position.z))
	var separation := flown.distance_to(p.global_position)
	walker.queue_free()
	v.check("...and a live zombie's own goal is the monkey, not the player",
		to_lure < 0.01 and from_player > 1.0 and separation > 1.0
			and THROWABLES.lure_active(),
		"steering at %s — %.2f m from the monkey, %.2f m from the player (the two are %.2f m apart)" % [
			lured, to_lure, from_player, separation])

	# ...and it stops being one the moment it goes off, not when the node is freed.
	# `ticks` opens at the 24 the flight above already spent, so the bounds below
	# still read as "the whole fuse" rather than "the whole fuse minus a bit".
	var ticks := 24
	while monkey != null and is_instance_valid(monkey) and not monkey.dead() and ticks < 600:
		monkey._physics_process(TICK)
		th.tick(TICK)
		ticks += 1
	th.tick(TICK)
	v.check("the lure ends on the frame the Monkey Bomb detonates",
		not THROWABLES.lure_active() and ticks > 60 and ticks < 600,
		"active=%s after %d ticks" % [THROWABLES.lure_active(), ticks])
	v.check("...and the fallback comes back with it",
		THROWABLES.flow_goal(fallback) == fallback)

	# Constraint 6: nothing in this subsystem may touch a gameplay stream. Weapon
	# spread rides VISUAL and always has, but a grenade that moved SPAWN would
	# desynchronise a seeded run every time one was thrown.
	var streams: Array[StringName] = [Rng.SPAWN, Rng.BOX, Rng.DROPS, Rng.ROUNDS, Rng.AI]
	var was: Array[int] = []
	for s: StringName in streams:
		was.append(Rng.stream(s).state)
	th.counts[THROWABLES.FRAG] = 4
	for i in 4:
		th.press(THROWABLES.FRAG)
		th.release(THROWABLES.FRAG)
	p.guns = [Weapons.make_gun("raygun", false)]
	p.slot = 0
	for i in 4:
		p.guns[0].mag = 20
		p._shoot(p.guns[0])
	var moved := ""
	for i in streams.size():
		if Rng.stream(streams[i]).state != was[i]:
			moved += str(streams[i]) + " "
	v.check("four grenades and four Ray Gun rounds draw from no gameplay stream",
		moved.is_empty(), "perturbed %s" % moved)

	_clear_projectiles(main)
	th.counts[THROWABLES.FRAG] = frag_was
	th.counts[THROWABLES.MONKEY] = monkey_was


# --- fixtures ------------------------------------------------------------------

## One projectile config in the shape `projectile.gd::setup` reads, without going
## through the weapon table — so a check can choose a radius the geometry search
## can actually reach.
static func _cfg(kind: String, splash: float, splash_dmg: float) -> Dictionary:
	var ray := kind == "ray"
	return {
		"kind": kind,
		"grav": 0.0 if ray else PROJ.GRENADE_GRAV,
		"dmg": 180.0 if ray else 120.0,
		"splash": splash,
		"splash_dmg": splash_dmg,
		"fuse": PROJ.LIFE,
		"contact": true,
		"bounces": false,
		"lures": false,
	}


static func _spawn(main: Node3D, p: Player, cfg: Dictionary, from: Vector3,
		vel: Vector3) -> Area3D:
	return PROJ.launch(p, main, cfg, from, vel)


## Fires one down the camera's flattened forward and steps it by hand at the real
## tick. Returns `[where it ended up, whether it detonated]`. Driven rather than
## awaited because `Verify.run` is synchronous — nothing in the tree is being
## stepped while it runs.
static func _fly(main: Node3D, p: Player, cfg: Dictionary, ticks: int) -> Array:
	var speed: float = PROJ.RAY_SPEED if String(cfg.kind) == "ray" else PROJ.GRENADE_SPEED
	return _fly_at(main, p, cfg, speed, ticks)


## The same, at a speed the weapon table does not carry. Only `_tunnelling`'s
## TILE_HOP sweep wants this: everything else must fly at the ancestor's own number
## or it is measuring a projectile the game does not have.
static func _fly_at(main: Node3D, p: Player, cfg: Dictionary, speed: float,
		ticks: int) -> Array:
	var cam := p.camera()
	var dir := _flat_forward(cam)
	var from := cam.global_position + dir * PROJ.SPAWN_AHEAD \
		- Vector3(0.0, PROJ.SPAWN_DROP, 0.0)
	var pr := _spawn(main, p, cfg, from, dir * speed)
	for i in ticks:
		if pr.dead():
			break
		pr._physics_process(TICK)
	return [pr.global_position, pr.dead()]


## Detonates one on the spot, for the tests that are about `_explode` rather than
## about the flight.
static func _detonate(main: Node3D, p: Player, cfg: Dictionary, at: Vector3) -> void:
	var pr := _spawn(main, p, cfg, at, Vector3.ZERO)
	pr._explode(at)


## Every bearing search in this file, once. Returns `[range, walled, open]` for the
## nearest range that offers both, or empty. The height is a body's centre, because
## that is what the splash gate traces to and searching at a different one would
## answer a different question.
static func _bearings(main: Node3D, p: Player) -> Array:
	var cam := p.camera()
	var world3d := main.get_world_3d()
	var yaw_was := p.rotation.y
	var probe := Zombie.create("zombie", 0, 1, false)
	main.add_child(probe)
	probe.global_position = Vector3.ZERO
	var lift: float = probe.centre().y
	probe.queue_free()

	var out: Array = []
	for dist: float in RANGES:
		var walled := 0.0
		var open := 0.0
		var got_w := false
		var got_o := false
		for i in BEARINGS:
			var yaw := float(i) * TAU / float(BEARINGS)
			p.rotation.y = yaw
			var ahead := cam.global_position + _flat_forward(cam) * dist
			if LOS.clear(world3d, cam.global_position, Vector3(ahead.x, lift, ahead.z)):
				if not got_o:
					open = yaw
					got_o = true
			elif not got_w:
				walled = yaw
				got_w = true
		if got_w and got_o:
			out = [dist, walled, open]
			break
	p.rotation.y = yaw_was
	return out


## The camera's forward flattened onto the floor plane, so the bearing search and
## the body placement agree to the millimetre — a pitched camera scales the raw
## basis vector's horizontal part by cos(pitch).
static func _flat_forward(cam: Camera3D) -> Vector3:
	var fwd := -cam.global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	return flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD


static func _target(main: Node3D, p: Player, n: float, r := 1) -> Zombie:
	var at := p.camera().global_position + _flat_forward(p.camera()) * n
	var z := Zombie.create("zombie", 0, r, false)
	main.add_child(z)
	z.add_to_group("zombies")
	z.global_position = Vector3(at.x, 0.0, at.z)
	return z


## Out of the group BEFORE the free, because `queue_free` is deferred: a body left
## in the group would still be swept by the next round fired in this same
## synchronous run.
static func _drop(z: Zombie) -> void:
	z.remove_from_group("zombies")
	z.queue_free()


static func _all_hurt(group: Array[Zombie]) -> bool:
	for z: Zombie in group:
		if z.hp >= z.max_hp:
			return false
	return true


## Drives every round currently in the world by hand. `Verify.run` is synchronous,
## so nothing in the tree is being stepped while it is on the stack.
static func _step_projectiles(main: Node3D, ticks: int) -> void:
	for i in ticks:
		for c: Node in _live(main):
			if not c.dead():
				c._physics_process(TICK)


## Every round in the world, BY SCRIPT and never by name. Godot resolves a name
## collision between siblings by mangling the second one to `@Area3D@597`, so a
## prefix match silently stops seeing every round after the first — which is
## precisely the false pass this file caught on itself.
static func _live(main: Node3D) -> Array[Node]:
	var out: Array[Node] = []
	for c in main.get_children():
		if c.get_script() == PROJ:
			out.append(c)
	return out


static func _count_projectiles(main: Node3D) -> int:
	return _live(main).size()


static func _count_lights(main: Node3D) -> int:
	var n := 0
	for c in main.get_children():
		if String(c.name).begins_with("ProjLight"):
			n += 1
	return n


## Frees every round this file put in the world. `free()` and not `queue_free()`,
## deliberately: the suite is synchronous, so a deferred free would leave every
## round of every earlier check still in the tree and still counted by the next
## one's `_count_projectiles`.
static func _clear_projectiles(main: Node3D) -> void:
	for c: Node in _live(main):
		c.free()


# --- state this file is not allowed to keep ------------------------------------

## `died` is main.gd's cue to call `Game.record_run()`, which writes the player's
## real profile to disk — and this is the one subsystem in the game that can damage
## the player without a zombie doing it. Every listener comes off for the duration,
## exactly as downed.gd does it.
static func _stage(main: Node3D) -> Dictionary:
	var p: Player = main.player
	var was: Array[Callable] = []
	for c: Dictionary in p.died.get_connections():
		var cb: Callable = c.callable
		was.append(cb)
		p.died.disconnect(cb)
	return {
		"died": was,
		"hp": p.hp,
		"yaw": p.rotation.y,
		"points": Game.points,
		"kills": Game.kills,
		"headshots": Game.headshots,
		"points_earned": Game.points_earned,
		"insta_kill": Game.insta_kill,
		"dbl_points": Game.dbl_points,
		"guns": p.guns.duplicate(),
		"slot": p.slot,
		"perks": Game.perks.duplicate(),
	}


static func _unstage(main: Node3D, s: Dictionary) -> void:
	var p: Player = main.player
	p.hp = s.hp
	p.rotation.y = s.yaw
	# Annotated rather than assigned straight out of the Dictionary: `guns` is an
	# Array[Dictionary] and a Variant handed to a typed property is checked at
	# runtime, which is a crash rather than a build error if it is ever wrong.
	var guns: Array[Dictionary] = s.guns
	p.guns = guns
	p.slot = s.slot
	Game.points = s.points
	Game.kills = s.kills
	Game.headshots = s.headshots
	Game.points_earned = s.points_earned
	Game.insta_kill = s.insta_kill
	Game.dbl_points = s.dbl_points
	Game.perks = s.perks
	var was: Array = s.died
	for cb: Callable in was:
		p.died.connect(cb)
