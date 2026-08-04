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
const GUNART := preload("res://scripts/data/gunart.gd")
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
	_bullet_patterns(v, main)
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

	# **PINNED, because the cone is state now and this section is not the first to
	# fire a round.** `_spread_rad` lerps from the weapon's floor to its ceiling by
	# `p._bloom`, and at a saturated bloom BOTH sides of the comparison below sit on
	# the ceiling — which is the same value hip and sighted, by design (M5 F17: the
	# sighted cone is `lerp(adsSpread, max, bloom)`, same ceiling, different floor).
	# This check went red for exactly that reason when the bloom landed, and the
	# check was right: it is about the FLOOR.
	var bloom_was: float = p._bloom
	p._bloom = 0.0
	p._ads = 0.0
	p._apply_fov()
	var hip_fov := cam.fov
	var hip_spread := p._spread_rad(Weapons.spec("m14"))
	var pitch_was := head.rotation.x
	var pivot_was: Vector3 = p._recoil_pivot.position
	# **Forced WHILE THE CAMERA IS STILL AT THE HIP, and read again later rather than
	# measured later.** `viewmodel._measure()` caches on first call and bakes in
	# `tan(_cam.fov/2)/tan(VIEWMODEL_FOV/2)` as it goes (viewmodel.gd:1268), so the
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
	# Still `hip * ADS_SPREAD`, and it is no longer a run-time multiply: `ADS_SPREAD`
	# is the constant that GENERATED `Weapons.BLOOM`'s `spread_ads` column, and this
	# is that column arriving back through the real function. `_bullet_patterns`
	# asserts the same relation over all twelve rows of the table; this one asserts
	# that the rig actually reads the column.
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

	_ads_sight_line(v, main)
	_ads_flash(v, main)

	p._ads = ads_was
	p._bloom = bloom_was
	p._apply_fov()



# --- the sighted pose is a SIGHT LINE, not a raised weapon ----------------------

## **THE DEFECT THESE EXIST FOR.** `ADS_CENTRE` brings the GRIP onto the view axis,
## and a weapon's sights are not at its grip — they are on top of it. Shipped that
## way, the M1911's whole sight line sat 66 px ABOVE the crosshair in a 720 px frame
## and the player was aiming at their own glove. 537 assertions were green: every one
## of them was about the field of view, the cone, the movement penalty or the clip
## budget, and not one of them asked where the weapon ENDED UP.
##
## Driven through the whole real chain — `give_gun` -> `weapon_changed` ->
## `viewmodel._show()` latching the sight height -> `_apply()` writing
## `WeaponMesh.transform` — and read back off that node. Nothing here re-evaluates
## `_mesh_pose`; if it did, it would agree with any pose the rig happened to produce.
static func _ads_sight_line(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var vm: Node3D = main.viewmodel
	var guns_was: Array[Dictionary] = p.guns.duplicate()
	var slot_was: int = p.slot
	var ads_was: float = p._ads

	# One art unit of clear air under the top plane. OUR DECISION — the ancestor has
	# no ADS — swept over 0..3 units and read off captures; viewmodel.gd's
	# ADS_SIGHT_CLEAR carries the table and what each value looked like.
	#
	# **THIS EXPECTATION IS DERIVED FROM THE CONSTANT UNDER TEST, so read what the
	# check below is actually named.** `_mesh_pose` drops the rig by
	# `sight + ADS_SIGHT_CLEAR * UNIT` and the top plane is `sight` above the grip,
	# so the two cancel and `top_ads == -ADS_SIGHT_CLEAR * UNIT` is an algebraic
	# identity in that constant: it is blind to its VALUE and sees only whether the
	# rig honours it, per weapon, through the real chain. MEASURED 2026-07-31 by
	# sweeping ADS_SIGHT_CLEAR over 0, 1, 2 and 3 and running the whole suite at
	# each — `=== 560 passed, 0 failed ===` all four times.
	#
	# So the VALUE is pinned by two things and by nothing else: the `...and that is
	# BELOW the view axis` check below, which bounds it without naming it, and the
	# frame gate's geometric relation `the sight line sits below the crosshair`,
	# whose band [1.005, 1.030]
	# measured 1.00000 / 1.01389 / 1.02500 / 1.03889 across that same sweep and so
	# rejects 0 and 3 exactly as the two halves are meant to agree.
	var want: float = -VIEWMODEL.ADS_SIGHT_CLEAR * GUNART.UNIT
	var bad_ads := ""
	var bad_hip := ""
	var bad_clear := ""
	# The sweep's own two rejected rows, restated as a bound. 0 units is "the
	# crosshair's ticks merge into the top edge" and is the DIRECTION the defect
	# shipped in; 3 units is "the weapon has detached from the aim point and reads
	# as held low" (viewmodel.gd's ADS_SIGHT_CLEAR table). Strictly outside both, so
	# a rig posed at either fails here as well as at the gate.
	#
	# 2.5 AND NOT 3.0, and that is a measurement rather than a rounding of taste.
	# The two sides of `-3.0 * UNIT` are computed by different routes — this one
	# directly, the pose by accumulating `sight + CLEAR * UNIT` and subtracting the
	# corner back off — so at CLEAR = 3.0 exactly they disagree in the last bit:
	# CONTROLLED 2026-07-31, six of the thirteen weapons compared 1 ULP INSIDE the
	# bound and only seven tripped it. The check still failed, but on an accident.
	# 2.5 is the midpoint of the last admitted row and the first rejected one, so
	# both are decided by art units rather than by float error.
	var clear_hi: float = -2.5 * GUNART.UNIT
	for key: String in GUNART.keys():
		_pose_weapon(vm, p, key, 1.0)
		var top_ads := _mesh_top(vm, key)
		if absf(top_ads - want) > 1.0e-5:
			bad_ads += "%s %+.5f " % [key, top_ads]
		# UNDER the axis, and not far under it. Independent of ADS_SIGHT_CLEAR's
		# value, which is the point: this is the one statement in the suite that the
		# sweep above could not satisfy at every setting.
		if top_ads >= 0.0 or top_ads <= clear_hi:
			bad_clear += "%s %+.3f units " % [key, top_ads / GUNART.UNIT]
		# BOUNDED AT THE OTHER END, and tightly, because the obvious version of this is
		# useless. "At the hip the weapon is lower than the axis" passes against a rig
		# that has dropped its `ads` factor and applies the sight drop ALWAYS — the
		# weapon is lower still, so the bound is happier. That was run as a control and
		# it discriminated nothing. With every other channel at rest the hip pose has
		# to be EXACTLY `REST_POS`, which is the only statement that catches it.
		_pose_weapon(vm, p, key, 0.0)
		var rest: Vector3 = vm._mesh.transform.origin
		if not rest.is_equal_approx(VIEWMODEL.REST_POS):
			bad_hip += "%s %v " % [key, rest]
	# An empty corner set cannot make this pass: the expected value is an EQUALITY and
	# the accumulator starts at -1e9, which is not it.
	v.check("at the sights every weapon's top plane lands where ADS_SIGHT_CLEAR says",
		bad_ads.is_empty(), "want %+.5f m, off: %s" % [want, bad_ads])
	v.check("...and that is BELOW the view axis on every weapon, and not detached from it",
		bad_clear.is_empty(),
		"wanted 0 > top > %.1f art units, off: %s" % [clear_hi / GUNART.UNIT, bad_clear])
	v.check("...and at the hip every weapon is back on the rest pose exactly",
		bad_hip.is_empty(), "REST_POS is %v, off: %s" % [VIEWMODEL.REST_POS, bad_hip])

	# THE CANT. Half of a hard scope is that the barrel runs LEVEL to the view axis
	# rather than 7.4 degrees under it; without this the top plane is a ramp and only
	# one point of it is at the clearance the check above measures.
	_pose_weapon(vm, p, "m1911", 1.0)
	var pitch_ads := _mesh_pitch(vm)
	_pose_weapon(vm, p, "m1911", 0.0)
	var pitch_hip := _mesh_pitch(vm)
	v.check("the sights level the weapon's cant and the hip pose keeps it",
		absf(pitch_ads) < 1.0e-5 and v.near(pitch_hip, VIEWMODEL.REST_PITCH, 1.0e-5),
		"sighted %.5f rad, hip %.5f rad against REST_PITCH %.5f" % [
			pitch_ads, pitch_hip, VIEWMODEL.REST_PITCH])

	# THE SLIDE TERM, which is the one way to derive this and get it quietly wrong.
	# `body_corners` excludes whatever `SLIDE` names, and on the M1911 `SLIDE` is
	# [1, 6] — part 1 being the slide plate, a rect at art y 20, against the topmost
	# part left in the body at art y 22. So the term is worth at least 2 art units by
	# inspection of the table (gunart.gd:50-53, :147), and measures 2.24 with the
	# PROUD inflation. Two art units is 13 px at the sighted pose.
	var body_only := -1.0e9
	var m_body: PackedVector3Array = GUNART.body_corners("m1911")
	for c: Vector3 in m_body:
		body_only = maxf(body_only, c.y)
	var m_sight: float = GUNART.sight_height("m1911")
	v.check("the M1911's sight height comes off its slide and not just its body",
		m_sight - body_only > 2.0 * GUNART.UNIT,
		"sight %.5f m, body alone %.5f m, difference %.2f art units" % [
			m_sight, body_only, (m_sight - body_only) / GUNART.UNIT])

	# ...and that it is PER WEAPON. The Ray Gun's scope block sits at art y 14 against
	# a grip at 33 (19 units) and the knife's blade at art y 22 against a grip at 27
	# (5 units), so the true ratio is 3.8. A `sight_height` that collapsed to one
	# constant — the failure this whole approach exists to avoid — lands at 1.0.
	var rg: float = GUNART.sight_height("raygun")
	var kn: float = GUNART.sight_height("knife")
	v.check("the sight height is per weapon, so one constant could not have served",
		rg > 3.0 * kn,
		"raygun %.2f art units against knife %.2f" % [rg / GUNART.UNIT, kn / GUNART.UNIT])

	p.guns = guns_was
	p.slot = slot_was
	p._ads = ads_was
	vm._melee_t = 0.0
	p.weapon_changed.emit(p.current_gun())
	vm._apply()


## THE FLASH HAS TO FOLLOW THE BARREL, and "it reads `_muzzle.global_position`, so it
## should for free" is precisely how ADS shipped with its camera half and not its
## weapon half.
##
## `flash_anchor()` answers "where does a WORLD-projected quad go so that it lands on
## the barrel ON SCREEN", and the barrel is drawn through the viewmodel's own 55
## degree projection rather than the camera's. The independent path used here shares
## none of its arithmetic: the shader scales only the two SCALE terms of the
## projection matrix, which for a KEEP_HEIGHT camera is exactly a camera at
## VIEWMODEL_FOV, so unprojecting the marker through one is where the muzzle is
## DRAWN. Measured at 0.000 px on both poses.
##
## AND IT IS AN IDENTITY, WHICH IS WHY IT IS NOT ENOUGH. The ratio cancels, and
## both sides read `_muzzle.global_position`, so a marker moved to the grip moves
## both and this still passes — measured: `_muzzle.position = Vector3.ZERO` moves
## the rendered flash 37 px down the screen and leaves this green. The rendered
## half is `the muzzle flash comes out of the barrel, under the aim point` and
## `...is centred on the aim point at the sights` in notes/perf/frames/golden.json.
static func _ads_flash(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var vm: Node3D = main.viewmodel
	var cam := p.camera()
	var ads_was: float = p._ads
	var bad := ""
	var at: Array[Vector2] = []
	for ads: float in [0.0, 1.0]:
		p._ads = ads
		p._apply_fov()
		vm._apply()
		var anchor: Vector3 = vm.flash_anchor(1.5)
		var px_flash := cam.unproject_position(anchor)
		var fov_was := cam.fov
		cam.fov = VIEWMODEL.VIEWMODEL_FOV
		var px_muzzle := cam.unproject_position(vm._muzzle.global_position)
		cam.fov = fov_was
		at.append(px_muzzle)
		if (px_flash - px_muzzle).length() > 0.5:
			bad += "ads=%.0f flash%s vs muzzle%s " % [ads, px_flash, px_muzzle]
	# The KEEP_HEIGHT clause is not padding: under KEEP_WIDTH the substitution above
	# stops being equivalent and the whole comparison would quietly measure nothing.
	v.check("the muzzle flash lands on the barrel at the hip and at the sights",
		bad.is_empty() and cam.keep_aspect == Camera3D.KEEP_HEIGHT,
		"keep_aspect=%d %s" % [cam.keep_aspect, bad])
	# ...and the two are not the same pose, or a rig whose weapon never moved would
	# satisfy the check above twice over. Measured 187 px apart.
	v.check("...and the sighted pose has actually moved the barrel",
		at.size() == 2 and (at[0] - at[1]).length() > 50.0,
		"hip %s -> sighted %s" % [at[0], at[1]])
	p._ads = ads_was
	p._apply_fov()
	vm._apply()


## Puts the rig into the pose the game would draw for `key` at `ads`, through the
## same two entry points the game uses. The knife is not a weapon slot — it is only
## ever on screen through `_apply()`'s melee override — so it is reached the way the
## rig reaches it, and `_melee_t == MELEE_TIME` is the instant the melee channel
## evaluates to sin(0) = 0, which is the first frame of a swing.
static func _pose_weapon(vm: Node3D, p: Player, key: String, ads: float) -> void:
	if key == "knife":
		vm._melee_t = VIEWMODEL.MELEE_TIME
	else:
		vm._melee_t = 0.0
		p.give_gun(key, false)
	p._ads = ads
	vm._apply()


## The highest point of the weapon as DRAWN, in camera space: the corners the mesh is
## built from, through the transform the rig actually wrote to the node.
static func _mesh_top(vm: Node3D, key: String) -> float:
	var xf: Transform3D = vm._mesh.transform
	var top := -1.0e9
	var body: PackedVector3Array = GUNART.body_corners(key)
	for c: Vector3 in body:
		top = maxf(top, (xf * c).y)
	var slide: PackedVector3Array = GUNART.slide_corners(key)
	for c: Vector3 in slide:
		top = maxf(top, (xf * c).y)
	return top


## `Basis.from_euler` and `get_euler` share Godot's default YXZ order, so this comes
## back as the pitch `_mesh_pose` put in rather than a decomposition of it.
static func _mesh_pitch(vm: Node3D) -> float:
	var xf: Transform3D = vm._mesh.transform
	return xf.basis.get_euler().x


# --- where the round actually goes ---------------------------------------------

## Spread bloom, the view kick, and the stream both of them ride.
##
## **THIS SECTION EXISTS BECAUSE OF ONE SENTENCE.** M5's own bottom line:
## *"Nothing anywhere pins a `spread` or a `kick` value. Multiply every one of them
## by ten and the whole suite stays green and the frames gate does not move,
## because the only spread assertion in the suite is a ratio."* That was true — the
## only two `_spread_rad` call sites in `scripts/dev/` fed one ratio assertion, and
## `grep -rn 'kick' scripts/dev/checks/` returned nothing but a comment. So the
## cheap checks here are the ratios and the identities, and the expensive ones are
## the three literals: a cone width in radians, a kick peak in radians, and a draw
## count. Those three are the point.
##
## **AND SCALE-INVARIANCE IS NOT THE ONLY WAY A CHECK CAN SEE NOTHING.** M5 also
## recorded that `spread = 0` cannot fail a "the cone is filled" check, because
## `_spread_rad` returns 0.0 and `_hitscan`'s `if spread > 0.0` then skips the draw
## entirely — every sample's deviation is 0, and `p95 >= 0` passes. That inert case
## is constructed below (`_cone_shape`'s sample-count and floor claims both fail
## against it) rather than assumed away.
##
## **Driven through the real path, everywhere.** The distribution comes off
## `Player.surface_impact` after real `_hitscan` calls, not off a re-rolled cone;
## the bloom comes off real `_shoot` and `_update_bloom` calls, not off a recomputed
## lerp; the kick is read from `RecoilPivot.rotation.x`, which is the node
## `_hitscan` takes its aim through, and not from `p._kick`.
static func _bullet_patterns(v: Verify, main: Node3D) -> void:
	var p: Player = main.player

	var guns_was: Array[Dictionary] = p.guns.duplicate()
	var slot_was: int = p.slot
	var ads_was: float = p._ads
	var bloom_was: float = p._bloom
	var kick_was: float = p._kick
	var kick_v_was: float = p._kick_v
	var shake_was: float = p._shake
	var shot_no_was: int = p._shot_no
	var moving_was: bool = p._moving
	var downed_was: bool = p.is_downed
	var reduce_was: bool = p._reduce_motion
	var rot_was: Vector3 = p._recoil_pivot.rotation
	var pitch_was: float = p._head.rotation.x
	var eye_was: float = p._head.position.y
	var campos_was: Vector3 = p._cam.position
	# Seeded, so every tolerance below is a measurement and not a confidence
	# interval. Restored on the way out for the same reason `checks/frame.gd` does
	# it: a stream left somewhere else moves everything downstream of it.
	var rng: RandomNumberGenerator = Rng.stream(Rng.COMBAT)
	var seed_was: int = rng.seed
	var rstate_was: int = rng.state
	rng.seed = SPREAD_SEED

	p._moving = false
	p.is_downed = false
	p._reduce_motion = false
	p._ads = 0.0
	p._bloom = 0.0

	_spread_table(v)
	_spread_absolutes(v, p)
	_bloom_machine(v, p)
	_cone_shape(v, main, p)
	_view_kick(v, main, p)
	_combat_stream(v, p)

	_clear_projectiles(main)
	p.guns = guns_was
	p.slot = slot_was
	p._ads = ads_was
	p._bloom = bloom_was
	p._kick = kick_was
	p._kick_v = kick_v_was
	p._shake = shake_was
	p._shot_no = shot_no_was
	p._moving = moving_was
	p.is_downed = downed_was
	p._reduce_motion = reduce_was
	p._recoil_pivot.rotation = rot_was
	p._head.rotation.x = pitch_was
	p._head.position.y = eye_was
	p._cam.position = campos_was
	p._apply_fov()
	rng.seed = seed_was
	rng.state = rstate_was


## The twelve hip cones, `kriegsnacht.html:1459-1470`, re-read 2026-08-02. The port
## has never made a spread decision of its own and this is the record of that:
## every one of these is the ancestor's own `spread:` field, and the whole of M5's
## R3 option (a) is the decision to keep them while importing BO1's *shape* around
## them. A rescale to BO1's absolutes — which are 1.7x to 25x wider (M5 F18b) — is
## a defensible call, but it is a BALANCE call, and it has to break this line and
## be re-argued rather than arriving inside a feel package.
const ANCESTOR_SPREAD := {
	"m1911": 0.85, "olympia": 5.4, "m14": 0.6, "mp40": 1.7, "pm63": 2.0,
	"ak74u": 1.5, "stakeout": 4.6, "m16": 1.15, "rpk": 1.9, "chinalake": 0.4,
	"raygun": 0.7, "thundergun": 0.2,
}

## Fixed so the distribution tolerances below are measurements rather than
## confidence intervals. Any seed would do; this one is the date.
const SPREAD_SEED := 20260802

## Samples for the cone-shape claims. Sized off the tightest of them: the
## uniform-in-area fraction is p = 0.25, so one sample's sd is 0.433 and 1000
## samples put the sample mean's sd at 0.0137. The band is +-0.04, which is 2.9 sd
## against a random seed and exact against this one — and the sabotage it exists to
## catch (deleting the `sqrt`) moves it to 0.50, eighteen sd out.
const CONE_SAMPLES := 1000

## First-shots for the fire-add ORDERING claim. Each one is a real `_shoot` from a
## rested bloom, so under a correct implementation every sample is inside the FLOOR
## cone and under the natural wrong one (add before the round leaves) each sample
## is drawn from the ceiling, where P(inside the floor radius) is
## (floor/ceiling)^2 = 0.25 for the M1911. 120 of them makes the wrong version a
## 10^-72 event.
const ORDER_SHOTS := 120

## Shots per weapon for the cross-roster kick range. Twelve is enough that the
## golden-angle walk reaches 0.944 of the bracket, and the same 0.944 for every
## weapon — which is what makes the comparison across the roster a comparison of
## the `kick` column rather than of twelve different sample maxima.
const KICK_SHOTS := 12


## The table, checked against the two things that generated it and against the
## ancestor. None of this drives the rig; `_spread_absolutes` does that.
static func _spread_table(v: Verify) -> void:
	var drift := ""
	var ratio_bad := ""
	var ads_bad := ""
	for key: String in ANCESTOR_SPREAD.keys():
		var d := Weapons.spec(key)
		var want: float = ANCESTOR_SPREAD[key]
		if not v.near(float(d.spread), want, 1e-6):
			drift += "%s %.4f!=%.4f " % [key, float(d.spread), want]
		# `spread_max` is the port's own floor times BO1's StandMax/StandMin, and
		# BLOOM_RATIO is a separate literal so this compares two tables rather than
		# dividing one by itself.
		var r: float = float(Weapons.BLOOM_RATIO[key])
		if not v.near(float(d.spread_max) / float(d.spread), r, 1e-4):
			ratio_bad += "%s %.4f!=%.4f " % [key, float(d.spread_max) / float(d.spread), r]
		if not v.near(float(d.spread_ads), float(d.spread) * Player.ADS_SPREAD, 1e-6):
			ads_bad += "%s %.5f " % [key, float(d.spread_ads)]
	v.check("every hip cone is still the ancestor's own, so the bloom is shape and not a rebalance",
		drift.is_empty(), drift)
	v.check("every saturated ceiling is its own floor through BO1's floor-to-ceiling ratio",
		ratio_bad.is_empty(), ratio_bad)
	v.check("every sighted floor is its own hip floor through ADS_SPREAD",
		ads_bad.is_empty(), ads_bad)


## **A11. One absolute cone width, as a literal in radians.**
##
## Every other spread check in this file and in the suite is scale-free by
## construction, which is why multiplying the whole table by ten used to be
## invisible. These three are not.
##
## The arithmetic, so the next reader can re-derive it rather than trust it. The
## M14's `spread` is 0.6 degrees of FULL cone (ancestor, html:1461) and
## `_spread_rad` returns a HALF-angle in radians, so the standing hip floor is
## deg_to_rad(0.6) * 0.5 = 0.00523599. Its ceiling is `spread_max` 1.40 — 0.6
## through BO1's M14 ratio of 7/3 — giving deg_to_rad(1.4) * 0.5 = 0.01221730. Its
## sighted floor is `spread_ads` 0.27, which is 0.6 through ADS_SPREAD 0.45,
## giving 0.00235619.
##
## **This is also the only check in the suite that can catch the silent factor of
## two M5's R3 warned about**: `_spread_rad` ends in `* 0.5` because the table is a
## full cone, and dropping BO1's own half-angle degrees into that field without
## removing it halves every cone in the game while every ratio stays green.
static func _spread_absolutes(v: Verify, p: Player) -> void:
	var m14 := Weapons.spec("m14")
	p._ads = 0.0
	p._bloom = 0.0
	var floor_rad := p._spread_rad(m14)
	p._bloom = 1.0
	var ceil_rad := p._spread_rad(m14)
	p._bloom = 0.0
	p._ads = 1.0
	var ads_rad := p._spread_rad(m14)
	p._ads = 0.0

	v.check("the M14's standing hip cone is 0.00523599 rad of half-angle, and that is deliberately today's",
		v.near(floor_rad, 0.00523599, 1e-7), "%.8f rad" % floor_rad)
	v.check("...its saturated ceiling is 0.01221730 rad, which is that floor through BO1's 7/3",
		v.near(ceil_rad, 0.01221730, 1e-7), "%.8f rad" % ceil_rad)
	v.check("...and its sighted floor is 0.00235619 rad, which firing may not lift",
		v.near(ads_rad, 0.00235619, 1e-7), "%.8f rad" % ads_rad)


## **A2. The bloom is a state machine, so assert the machine.**
##
## Driven through `_update_bloom` and `_shoot` — the two functions the game calls —
## and never through `_spread_rad`, which is a pure read of `_bloom` and would test
## the lerp instead of the integrator.
static func _bloom_machine(v: Verify, p: Player) -> void:
	var mp40 := Weapons.make_gun("mp40", false)
	p.guns = [mp40]
	p.slot = 0
	var def: Dictionary = mp40.def
	var fire: float = float(def.bloom_fire)
	var decay: float = float(def.bloom_decay)

	# --- firing opens it, and saturates it ---
	p._ads = 0.0
	p._bloom = 0.0
	p._moving = false
	mp40.mag = 32
	p._shoot(mp40)
	var after_one := p._bloom
	for i in 4:
		mp40.mag = 32
		p._shoot(mp40)
	var after_five := p._bloom
	v.check("one round adds exactly the weapon's own fire-add and five saturate the cone",
		v.near(after_one, fire, 1e-6) and v.near(after_five, 1.0, 1e-6),
		"one=%.4f (want %.4f) five=%.4f" % [after_one, fire, after_five])

	# --- standing still is what recovers it, and it takes 1/decay seconds ---
	p._bloom = 1.0
	p._moving = false
	var half_steps := int(round(0.5 / (decay * TICK)))
	for i in half_steps:
		p._update_bloom(TICK, 0.0)
	var halfway := p._bloom
	var steps := 0
	while p._bloom > 0.0 and steps < 600:
		p._update_bloom(TICK, 0.0)
		steps += 1
	var recover := float(steps + half_steps) * TICK
	# Bounded at BOTH ends: it has to reach the floor, and it must not simply snap
	# there — a `_bloom = 0.0` with no integrator passes "it reaches the floor"
	# perfectly.
	# Both tolerances are one tick of the thing being measured and nothing more: the
	# bloom moves in steps of `decay * TICK` (0.0667 for this weapon), so neither
	# the mid-point reading nor the arrival time can be exact, and 0.5 is not even
	# on the lattice. A `_bloom = 0.0` snap — the implementation that would make
	# "it reaches the floor" pass on its own — reads 0.0 half-way and fails by
	# seven and a half ticks.
	v.check("standing still bleeds the cone back to its floor in 1/decay seconds and not instantly",
		v.near(recover, 1.0 / decay, TICK * 1.5)
			and v.near(halfway, 0.5, decay * TICK + 1e-6)
			and v.near(p._bloom, 0.0, 1e-9),
		"recovered in %.4f s (want %.4f), half-way reading %.4f" % [recover, 1.0 / decay, halfway])

	# --- and MOVING SUPPRESSES THAT DECAY ENTIRELY ---
	#
	# **THE SPEED IS PINNED AND IT IS NOT ARBITRARY.** At a full walk the natural
	# wrong implementation — `s += grow*dt; s -= decay*dt` in the same tick — is
	# nearly indistinguishable from this one, because `bloom_move` and `bloom_decay`
	# are within 25% of each other on nine of the twelve rows and the additive
	# version still grows. It is just above `BLOOM_MOVE_MIN` that they separate:
	# at 0.30 m/s the MP40's growth term is 4.0 * 0.30/3.15 = 0.381/s against a
	# decay of 4.00/s, so an additive implementation collapses the cone at 3.6/s
	# while the trigger is released — and a player edging round a corner would be
	# recovering accuracy that the reference does not give them.
	var crawl := Player.BLOOM_MOVE_MIN + 0.02
	p._bloom = 0.5
	p._moving = true
	var crawl_ticks := int(round(0.25 / TICK))
	for i in crawl_ticks:
		p._update_bloom(TICK, crawl)
	var crawled := p._bloom
	var grew: float = float(def.bloom_move) * (crawl / Player.SPEED) * float(crawl_ticks) * TICK
	v.check("a crawl suppresses the decay outright rather than being outrun by it",
		crawled > 0.5 and v.near(crawled, 0.5 + grew, 0.01),
		"0.500 -> %.4f over %.2f s at %.2f m/s (a suppressed decay predicts %.4f)" % [
			crawled, float(crawl_ticks) * TICK, crawl, 0.5 + grew])

	# ...and below the threshold it is not moving at all, which is the other jaw of
	# the same constant.
	p._bloom = 0.5
	p._moving = true
	for i in crawl_ticks:
		p._update_bloom(TICK, Player.BLOOM_MOVE_MIN - 0.02)
	v.check("...and a shuffle under the movement threshold still counts as standing still",
		p._bloom < 0.5 - 0.5 * 0.25 * decay + 0.01 and p._bloom >= 0.0,
		"0.500 -> %.4f" % p._bloom)

	# --- the sights are a floor firing cannot lift ---
	p._moving = false
	p._ads = 1.0
	p._bloom = 0.0
	var sighted_before := p._spread_rad(def)
	for i in 10:
		mp40.mag = 32
		p._shoot(mp40)
	var sighted_after := p._spread_rad(def)
	var sighted_bloom := p._bloom
	p._ads = 0.0
	p._bloom = 0.0
	var hip_before := p._spread_rad(def)
	for i in 10:
		mp40.mag = 32
		p._shoot(mp40)
	var hip_after := p._spread_rad(def)
	p._bloom = 0.0
	# Bounded at both ends by construction: the refusal at the sights, and the
	# acceptance at the hip that stops the refusal passing against a fire-add that
	# has stopped working altogether.
	v.check("ten rounds at the sights do not open the cone, and ten at the hip do",
		v.near(sighted_after, sighted_before, 1e-9) and v.near(sighted_bloom, 0.0, 1e-9)
			and hip_after > hip_before * 1.5,
		"sighted %.8f->%.8f, hip %.8f->%.8f" % [sighted_before, sighted_after,
			hip_before, hip_after])


## **A1. The cone, measured off the impacts rather than off the sampler.**
##
## Points the camera at the floor, drives `p._hitscan` `CONE_SAMPLES` times and
## collects the world points off `Player.surface_impact` — the signal the bullet
## holes are drawn from, so this is the cone the player sees. Nothing here
## re-evaluates the rotation; recomputing the sampler would agree with any sampler.
##
## **The sample set is silently lossy and that is asserted FIRST.** `_hitscan`
## emits nothing when the ray hits nothing and nothing when it stops on a zombie,
## and every one of those losses truncates the distribution INWARD — which moves
## the two statistics below in the passing direction. The floor is used rather than
## a wall for the same reason: it subtends four orders of magnitude more than the
## cone, so nothing can escape it.
static func _cone_shape(v: Verify, main: Node3D, p: Player) -> void:
	var gun := Weapons.make_gun("m1911", false)
	p.guns = [gun]
	p.slot = 0
	var def: Dictionary = gun.def
	p._ads = 0.0
	p._bloom = 0.0
	p._moving = false
	# Level the aim spring first: `_hitscan` reads `_cam.global_transform.basis` and
	# RecoilPivot sits between the head and the camera, so a leftover kick would tilt
	# the axis every deviation below is measured from.
	p._kick = 0.0
	p._kick_v = 0.0
	p._recoil_pivot.rotation = Vector3.ZERO
	p._head.rotation.x = -deg_to_rad(70.0)

	var samples: Array[float] = []
	var origin := p._cam.global_position
	var aim := -p._cam.global_transform.basis.z
	var sink := func(at: Vector3, _n: Vector3) -> void:
		samples.append((at - origin).angle_to(aim))
	p.surface_impact.connect(sink)
	for i in CONE_SAMPLES:
		p._hitscan(def)
	p.surface_impact.disconnect(sink)

	var cone := p._spread_rad(def)
	v.check("every round fired at the floor came back as an impact, so the distribution is not truncated",
		samples.size() == CONE_SAMPLES,
		"%d of %d — a lost sample biases everything below it inward" % [samples.size(), CONE_SAMPLES])

	samples.sort()
	var worst := samples[samples.size() - 1] if samples.size() > 0 else -1.0
	var p95 := samples[int(0.95 * float(samples.size()))] if samples.size() > 20 else -1.0
	var inner := 0
	for a: float in samples:
		if a < cone * 0.5:
			inner += 1
	var frac := float(inner) / float(maxi(1, samples.size()))

	v.check("no round leaves the cone the weapon says it has",
		worst >= 0.0 and worst <= cone + 1e-7,
		"widest %.8f rad against a half-angle of %.8f" % [worst, cone])
	# The other jaw. A cone nothing fills is a cone that is not being sampled, which
	# is exactly what `spread = 0` produces — `_spread_rad` returns 0.0 and
	# `_hitscan` skips the draw, so every deviation is 0 and a bare "nothing left
	# the cone" passes against a weapon that has stopped spreading at all.
	v.check("...and the cone is FILLED, so it is being sampled rather than skipped",
		p95 >= 0.90 * cone and cone > 0.0,
		"95th percentile %.8f against 0.90 x %.8f" % [p95, cone])
	# `sqrt()` on the radius is what makes the disc uniform in AREA. Without it the
	# pellets pile into the middle: P(r < R/2) goes from 0.25 to 0.50.
	v.check("the disc is uniform in area, so a quarter of the rounds land inside half the radius",
		v.near(frac, 0.25, 0.04),
		"%.4f inside half the cone across %d samples" % [frac, samples.size()])

	# --- and the fire-add runs AFTER the round leaves ---
	#
	# M5 F19: BO1 has no first-shot accuracy term at all. What players remember as
	# one is this ordering — with the M1911's `bloom_fire` of 1.00 the first round
	# out of a rested weapon goes into the 0.85 degree floor cone and every one
	# after it into the 1.70 degree ceiling. Assert it where it is visible: reset
	# the bloom, fire a REAL shot, and require the impact to be inside the FLOOR.
	var first: Array[float] = []
	var sink2 := func(at: Vector3, _n: Vector3) -> void:
		first.append((at - origin).angle_to(aim))
	p.surface_impact.connect(sink2)
	for i in ORDER_SHOTS:
		p._bloom = 0.0
		gun.mag = 8
		p._shoot(gun)
	p.surface_impact.disconnect(sink2)
	var over := 0
	for a: float in first:
		if a > cone + 1e-7:
			over += 1
	v.check("a rested weapon's first round is placed BEFORE its own fire-add, every time",
		first.size() == ORDER_SHOTS and over == 0,
		"%d of %d first rounds landed outside the floor cone (%d samples)" % [
			over, ORDER_SHOTS, first.size()])

	p._bloom = 0.0
	p._head.rotation.x = 0.0
	_clear_projectiles(main)


## **A3 and A12. The view kick, read off the node `_hitscan` aims through.**
##
## `RecoilPivot` is the parent of `Camera3D` and `_hitscan` takes its basis from
## the camera, so every number here is a statement about where rounds go and not
## about how the screen feels. `p._moving` is pinned false first: `player.gd`
## writes `Vector3(_kick + slow, 0, roll)` to that node, and the `slow` term is the
## bob's sway — larger, by M5's own F23, than most weapons' entire cone. Without
## pinning it this would be measuring two systems.
static func _view_kick(v: Verify, main: Node3D, p: Player) -> void:
	p._moving = false
	p._reduce_motion = false
	p._ads = 0.0
	p._bloom = 0.0

	var gun := Weapons.make_gun("m1911", false)
	p.guns = [gun]
	p.slot = 0

	# One writer. With the bob pinned off, the pivot's pitch IS the spring and
	# nothing else — if a second writer ever appears on that node this is where it
	# shows up, before it shows up as bullets going somewhere else.
	p._kick = 0.0
	p._kick_v = 0.0
	p._shake = 0.0
	p._shot_no = 0
	gun.mag = 8
	p._shoot(gun)
	p._update_view(TICK, 0.0)
	# 1e-8 and not zero, because `Node3D.rotation` is a `Vector3` of 32-bit floats
	# and `_kick` is a 64-bit one — the round trip through the node costs about
	# 5e-10 at this magnitude. It is still five orders tighter than the smallest
	# thing that could arrive here as a second writer: the bob's `slow` sway is
	# 0.010 rad, which is larger than most weapons' entire cone (M5 F23).
	v.check("nothing but the recoil spring writes the pivot the camera hangs off",
		v.near(p._recoil_pivot.rotation.x, p._kick, 1e-8)
			and v.near(p._recoil_pivot.rotation.y, 0.0, 1e-8),
		"rotation.x %.9f against _kick %.9f" % [p._recoil_pivot.rotation.x, p._kick])

	# The whole excursion, not just its maximum. See the check below for why the
	# maximum on its own is worthless here.
	p._kick = 0.0
	p._kick_v = 0.0
	p._shake = 0.0
	p._shot_no = 0
	gun.mag = 8
	p._shoot(gun)
	var first_frame := 0.0
	var peak := 0.0
	var trough := 0.0
	for i in 60:
		p._update_view(TICK, 0.0)
		var x: float = p._recoil_pivot.rotation.x
		if i == 0:
			first_frame = x
		peak = maxf(peak, x)
		trough = minf(trough, x)
	var residual: float = absf(p._recoil_pivot.rotation.x)

	# **THE SIGN, and it is the single most consequential claim in this package.**
	# Provenance for "up": `player.gd`'s mouse-look line is
	# `_head.rotation.x - event.relative.y * sens`, so a positive rotation.x is
	# looking UP. This was `-=` from the port's first commit — the camera dipped
	# under fire while `viewmodel.gd` raised the muzzle with the same spring
	# constants — and it moves where bullets go, because a rising aim converts body
	# shots into headshots at 1.5x damage.
	#
	# **AND `peak > 0.0` ALONE IS DECORATION. MEASURED, not reasoned:** the first
	# draft of this check asserted exactly that, and restoring the `-=` left it
	# GREEN at 0.00012287 rad. The spring is underdamped, so a downward impulse
	# undershoots and then crosses back above zero on the way home, and a maximum
	# taken over a whole second finds that crossing. What separates the two
	# directions is the FIRST frame — which carries the impulse and nothing else —
	# and the fact that in the correct direction the return undershoot is a rounding
	# error against the peak (measured 0.0203 against 0.00031, a factor of 65)
	# where in the wrong one it is the whole of the motion.
	v.check("the recoil kicks the aim UP, which is BO1's direction and not the ancestor's",
		first_frame > 0.0 and peak > 0.0 and absf(trough) < 0.1 * peak,
		"first frame %.8f, peak %.8f, trough %.8f" % [first_frame, peak, trough])

	# **A12. One absolute view-kick peak, as a literal in radians.**
	#
	# The arithmetic, written out so it can be re-derived rather than trusted.
	# `_shot_no` is pinned to 0, so `fposmod(0 * phi, 1)` is 0 and the bracket
	# multiplier is exactly the M1911's `kick_lo`, 0.55. The impulse is therefore
	# kick 1.3 * KICK_IMPULSE 0.55 * 0.55 = 0.393250 rad/s into the spring.
	#
	# The spring's discrete impulse response peaks at 0.05171506 rad per unit of
	# impulse. MEASURED against the shipped semi-implicit Euler integrator at 60 Hz
	# — NOT taken from the continuous solution, which gives 0.06199 and is 20% out
	# because `KICK_DAMP * dt` is 0.183 and the first step damps the impulse before
	# it has moved the angle at all. So: 0.393250 * 0.05171506 = 0.02033695 rad,
	# which is 1.165 degrees.
	v.check("...and the M1911's first shot peaks at 0.02033695 rad, which is 1.165 degrees",
		v.near(peak, 0.02033695, 2e-6), "%.8f rad = %.4f deg" % [peak, rad_to_deg(peak)])
	v.check("...and the spring gives it all back, so a magazine cannot walk the aim away",
		residual < 0.02 * peak, "%.8f rad left after 1 s against a peak of %.8f" % [residual, peak])

	# **The bracket, filled at both ends.** `min/max` over a walk of the counter is
	# blind to the impulse coefficient and to the `kick` column, and equals
	# `kick_lo / kick_hi` only if BOTH ends are actually reached: a draw pinned to
	# the bracket's midpoint reads 1.0, and a walk that covers [0.6, 1.4] of a
	# [0.55, 1.45] bracket reads 0.4286 against 0.3793.
	var lo_peak := 1e9
	var hi_peak := -1e9
	for n in 60:
		var q := _kick_peak(p, gun, n)
		lo_peak = minf(lo_peak, q)
		hi_peak = maxf(hi_peak, q)
	var want_ratio: float = float(gun.def.kick_lo) / float(gun.def.kick_hi)
	v.check("sixty shots fill the M1911's kick bracket from end to end",
		v.near(lo_peak / hi_peak, want_ratio, 0.02),
		"%.6f..%.6f is a ratio of %.4f against the bracket's %.4f" % [
			lo_peak, hi_peak, lo_peak / hi_peak, want_ratio])

	# **The roster has a RANGE, and it is the `kick` column's.** Provenance: the
	# table runs thundergun 4.2 down to pm63 0.9, a ratio of 4.67 — so a floor of
	# 4.0 fails the moment a retune flattens the column, and it is stated as a range
	# rather than as an order because m16 and rpk both carry 1.5 and no strict
	# ordering over twelve weapons was ever satisfiable.
	var lo_w := 1e9
	var hi_w := -1e9
	var worst_key := ""
	for key: String in ANCESTOR_SPREAD.keys():
		var g := Weapons.make_gun(key, false)
		p.guns = [g]
		var mx := -1e9
		for n in KICK_SHOTS:
			mx = maxf(mx, _kick_peak(p, g, n))
		if mx < lo_w:
			lo_w = mx
			worst_key = key
		hi_w = maxf(hi_w, mx)
	v.check("the loudest weapon kicks the view at least four times as hard as the quietest",
		hi_w / lo_w >= 4.0,
		"%.6f (%s) .. %.6f, a ratio of %.3f" % [lo_w, worst_key, hi_w, hi_w / lo_w])

	# **The clamp, bounded at both ends.** BO1's `CG_KickAngles` stops the
	# integrated kick at +-10 degrees and this spring had no stop at all. It has to
	# BITE on sustained automatic fire — the RPK reaches 14.8 degrees unclamped —
	# and it must NOT bite on a weapon firing one round at a time, or it is not a
	# bound on stacking, it is a flattening of the recoil.
	var rpk := Weapons.make_gun("rpk", false)
	p.guns = [rpk]
	p._kick = 0.0
	p._kick_v = 0.0
	p._shot_no = 0
	var interval := 60.0 / float(rpk.def.rpm)
	var clock := 0.0
	var next_shot := 0.0
	var held := 0.0
	for i in 180:
		if clock >= next_shot:
			rpk.mag = 100
			p._shoot(rpk)
			next_shot += interval
		p._update_view(TICK, 0.0)
		held = maxf(held, p._recoil_pivot.rotation.x)
		clock += TICK
	# Same 32-bit round trip through the node as above, hence 1e-7 rather than an
	# equality. Unclamped this reaches 0.258 rad, which is 48% past the stop, so the
	# band could be a hundred times wider and still name the defect.
	v.check("holding an RPK down walks the aim into BO1's 10 degree stop and no further",
		held <= Player.KICK_MAX + 1e-7 and held >= Player.KICK_MAX - 1e-7
			and peak < Player.KICK_MAX * 0.5,
		"sustained %.8f against the stop at %.8f; one M1911 shot reaches %.8f" % [
			held, Player.KICK_MAX, peak])

	# The accessibility toggle is an aim buff and nothing asserted it. `reduce_motion`
	# DAMPS the kick rather than removing it — `player.gd`'s REDUCE_MOTION_KICK
	# comment argues why — so a player who turns it on gets a flatter aim, and the
	# number they get has to be the stated one.
	p.guns = [gun]
	var full := _kick_peak(p, gun, 0)
	p._reduce_motion = true
	var damped := _kick_peak(p, gun, 0)
	p._reduce_motion = false
	v.check("reduce_motion damps the kick to exactly REDUCE_MOTION_KICK of it and does not zero it",
		v.near(damped, full * Player.REDUCE_MOTION_KICK, 1e-7) and damped > 0.0,
		"%.8f against %.8f x %.3f" % [damped, full, Player.REDUCE_MOTION_KICK])

	p._kick = 0.0
	p._kick_v = 0.0
	p._shake = 0.0
	p._recoil_pivot.rotation = Vector3.ZERO
	p._bloom = 0.0
	_clear_projectiles(main)


## One shot from a rested spring, integrated for a second, returning the highest
## pitch the pivot reached. Deterministic in `shot_no` because the bracket is
## walked by the counter and not by a draw — which is the whole reason the bracket
## can be asserted at all.
static func _kick_peak(p: Player, gun: Dictionary, shot_no: int) -> float:
	p._kick = 0.0
	p._kick_v = 0.0
	p._shake = 0.0
	p._shot_no = shot_no
	gun.mag = int(gun.def.mag)
	p._shoot(gun)
	var peak := 0.0
	for i in 60:
		p._update_view(TICK, 0.0)
		peak = maxf(peak, p._recoil_pivot.rotation.x)
	return peak


## **A13. The draw count inside `_shoot`, which nothing in the suite bounded.**
##
## `checks/frame.gd` bounds the VISUAL draws of `fired` LISTENERS — it emits the
## signal directly and never reaches `_shoot` — and the gameplay-stream check at
## the foot of `_throwables` bounds the five original streams. Between them sat the
## two draws per pellet that decide where the round lands, and they rode `VISUAL`
## from the port's first commit.
##
## Bounded at both ends: COMBAT has to move by EXACTLY two per pellet, and VISUAL
## must not move at all. A revert to the cosmetic stream fails both halves; a
## spread that has stopped drawing fails the first.
static func _combat_stream(v: Verify, p: Player) -> void:
	var def := Weapons.spec("m1911")
	p._ads = 0.0
	p._bloom = 0.0
	p._moving = false
	var combat: RandomNumberGenerator = Rng.stream(Rng.COMBAT)
	var visual: RandomNumberGenerator = Rng.stream(Rng.VISUAL)
	# An ORACLE, not a subtraction. A PCG state is advanced by a multiply-add, so
	# the difference between two states is not a count of draws — it is only equal
	# after exactly the same number of steps, which is what makes this an equality
	# and not an inequality. Same device `checks/frame.gd` uses on VISUAL.
	var oracle := RandomNumberGenerator.new()
	oracle.seed = combat.seed
	oracle.state = combat.state
	for i in 100:
		oracle.randf()
	var v0: int = visual.state
	for i in 50:
		p._hitscan(def)
	v.check("the spread cone is drawn from the gameplay stream, twice a pellet, and spends nothing cosmetic",
		combat.state == oracle.state and visual.state == v0,
		"combat %s 100 draws, visual moved %s" % [
			"is not" if combat.state != oracle.state else "is exactly",
			"yes" if visual.state != v0 else "no"])

	# **R12's RULING, pinned rather than left in a comment.** M5 asked whether the
	# shotgun should get a fixed ring-plus-centre pattern instead of six independent
	# draws from the whole cone. Declined for this package — `player.gd::_shoot`
	# carries the three reasons — and a decision recorded only in prose is a
	# decision that gets reversed by accident. Six pellets, two draws each, twelve
	# draws for one pull of an Olympia's trigger: a ring pattern costs ZERO draws
	# because its positions are constants, so this number is the one thing that
	# separates the two designs from outside.
	var oly := Weapons.make_gun("olympia", false)
	p.guns = [oly]
	p.slot = 0
	oly.mag = 2
	var pellet_oracle := RandomNumberGenerator.new()
	pellet_oracle.seed = combat.seed
	pellet_oracle.state = combat.state
	for i in 12:
		pellet_oracle.randf()
	p._shoot(oly)
	v.check("one pull of the Olympia's trigger is six independent draws from the whole cone, not a pattern",
		combat.state == pellet_oracle.state and int(oly.def.pellets) == 6,
		"%d pellets, and the stream %s advance by twelve" % [int(oly.def.pellets),
			"did" if combat.state == pellet_oracle.state else "did NOT"])

	# The other half of the same rule: COMBAT is a GAMEPLAY stream, so a cosmetic
	# roll may not reach it. Nothing that runs on `fired` is allowed to touch it,
	# and this is the check that says so — the muzzle flash, the smoke and the brass
	# all hang off that signal.
	var c1: int = combat.state
	p.fired.emit(p._cam.global_position - p._cam.global_transform.basis.z * 0.35)
	v.check("...and nothing hanging off `fired` may draw from it",
		combat.state == c1, "moved %d" % (combat.state - c1))


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

	# Constraint 5: nothing in this subsystem may touch a gameplay stream a grenade
	# has no business in — one that moved SPAWN would desynchronise a seeded run
	# every time one was thrown.
	#
	# **REVISED, because this comment used to say "weapon spread rides VISUAL and
	# always has" and that is no longer true.** It rides `Rng.COMBAT` now, which IS
	# a gameplay stream, so `Rng.COMBAT` is deliberately not in the list below and
	# the four Ray Gun rounds fired here move it by exactly eight draws. That is not
	# a hole: `_combat_stream` above bounds it at both ends against an oracle, which
	# is a stronger claim than "it did not move". What this list is still for is the
	# five streams a weapon must never reach.
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
