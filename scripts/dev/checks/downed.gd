extends RefCounted

## Assertions for the downed state, solo Quick Revive, and the Thundergun's two
## occlusion gates.
##
## All of it was unreachable before this wave. `Player.revive()` was defined and
## called by nothing, `_go_down` spent a counter that no machine, badge or purchase
## rule read, and the blast scored a 100-point headshot on every body in a 135 degree
## wedge — through walls. None of that is visible in a frame and none of it can be
## reached by playing to it reliably, because getting downed on purpose costs a run.
##
## **Every check here is bounded at both ends.** A previous assertion on this project
## ran a 4-second window against a 3.4-second reload and therefore asserted nothing at
## all, because the magazine had filled completely before it looked. So the bleedout
## is sampled while it is still running *and* after it ends, and the wall test fires
## the same blast at the same range down two of the map's own bearings — one with
## geometry across it and one without — because a "survived" that came from being out
## of range or outside the wedge would prove nothing whatsoever about line of sight.
##
## **This section writes to the player's real save file if it is careless**, so it is
## not: `died` is what main.gd turns into `Game.record_run()`, and the run that has to
## end here is a *test* run. Every listener is disconnected for the duration and put
## back, and the death is observed on a counter of this file's own.
##
## **It also depends on the level's real colliders**, which is not a preference: a
## StaticBody3D built inside `Verify.run` is never flushed into the Jolt space, so it
## is invisible to `intersect_ray` and a wall test built on one passes whatever the
## blast does. See `_cone_occlusion` for the measurement.
##
## Order: run before CHECK_SYSTEMS. This kills zombies through the director's own
## payout path, which draws from the DROPS stream; CHECK_SYSTEMS re-seeds with
## `Rng.new_run(SEED)` before it measures anything, and CURVES after it, so neither
## can see the disturbance. Nothing here touches the spawn queue.

## The shared visibility test, used here to FIND the geometry rather than to stand in
## for it: the assertion below still fires the real blast and reads the real corpse.
## preload rather than the class name, per the convention at the top of los.gd.
const LOS := preload("res://scripts/world/los.gd")

const WEAPONS_THUNDERGUN := "thundergun"

## Far enough to be unambiguously inside the 11 m range and the 4.57 m cylinder, and
## near enough to keep a wall of the map's own between the muzzle and the body.
const TARGET_RANGE := 3.0

## How many bearings the search below sweeps looking for a walled one and an open one.
## 64 is a 5.6 degree step, which is finer than the narrowest pillar on this map
## subtends at these ranges, so neither bearing can be missed between samples.
const BEARINGS := 64

## Ranges the search tries, nearest first, until it finds one that offers BOTH a walled
## and an open bearing. Swept rather than fixed because the player spawns in the middle
## of an open room: at 3 m every one of the 64 bearings is clear, so a fixed range found
## no wall to be stopped by. Every entry is inside the Thundergun's 11 m reach, and a
## body placed along the aim sits at most 0.64 m off the cylinder axis (the drop from
## the 1.55 m camera to a 0.91 m centre), so nothing here can be refused by the volume
## tests instead of by the sight line.
const RANGES: Array[float] = [3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0]


static func run(v: Verify, main: Node3D) -> void:
	_cone_payout(v, main)
	_cone_occlusion(v, main)
	_down_consumes_one_perk(v, main)
	_down_without_the_perk_ends_the_run(v, main)
	_downed_cannot_be_hurt(v, main)
	_bleedout(v, main)


# --- the Thundergun ----------------------------------------------------------

## THE PAYOUT. `_apply_hit` aimed the blast's synthetic hit point at
## `head_threshold() + 0.01`, so every kill in the wedge was credited as a headshot
## and paid 100 instead of 60. The ancestor passes `false` for headshot (html:2543)
## and BO1 pays a *falling* scale for a blast kill, so the old number was wrong twice.
##
## Measured through the director's real `_on_zombie_died` rather than by reading the
## flag off the corpse: the flag being false is necessary but not sufficient, and a
## director that paid the headshot rate anyway is exactly the bug worth catching.
static func _cone_payout(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var rounds: Node = main.get("rounds")
	var save := _snapshot()

	# Insta-Kill pays a flat 50 and Double Points doubles everything, so both have to
	# be down or the number being measured is a different number.
	Game.insta_kill = 0.0
	Game.dbl_points = 0.0
	# The per-round cap swallows the drop this death would otherwise roll, so no
	# power-up is spawned into the level by a headless assertion.
	Game.drop_count = Game.DROP_CAP
	Game.points_earned = 0

	var z := _target(main, p, TARGET_RANGE)
	z.died.connect(Callable(rounds, "_on_zombie_died"))

	var heads_before := Game.headshots
	var points_before := Game.points
	p._cone_blast(Weapons.spec(WEAPONS_THUNDERGUN))
	var gained := Game.points - points_before
	var heads_gained := Game.headshots - heads_before

	# First, because every number below is meaningless if the blast missed — and a
	# missed blast is a live possibility now that the wedge has a line-of-sight test
	# and the spawn point in front of the camera is wherever the map put it.
	v.check("the blast kills a body 3 m in front of the muzzle",
		z.state == Zombie.State.DYING,
		"state=%d hp=%.0f" % [z.state, z.hp])
	v.check("a Thundergun kill pays the body rate and is not scored as a headshot",
		gained == Game.PTS_KILL and heads_gained == 0,
		"paid %d, want %d; headshots +%d" % [gained, Game.PTS_KILL, heads_gained])
	# States the pair rather than the tolerance: "60 not 100" is only a meaningful
	# assertion while 60 and 100 are still what a body and a head are worth.
	v.check("...and the 60/100 split it is measured against is still canon",
		Game.PTS_KILL == 60 and Game.PTS_HEADSHOT == 100,
		"kill=%d head=%d" % [Game.PTS_KILL, Game.PTS_HEADSHOT])

	z.died.disconnect(Callable(rounds, "_on_zombie_died"))
	_drop(z)
	_restore(save)


## THE WALL. `_cone_blast` had no occlusion test at all, so the one weapon in the game
## that needs positioning killed through geometry. The ancestor gates it
## (html:2541) and so does the reference (`DamageConeTrace`).
##
## **Fired along two of the map's own bearings, not at a wall this file builds.** The
## obvious version of this check — drop a StaticBody3D between the muzzle and the body
## — cannot work here and fails SILENTLY, which is worse: `Verify.run` is synchronous
## and `--verify` reaches it through `call_deferred` from `_ready`, so a body added to
## the tree inside it is never flushed into the Jolt space. `intersect_ray` returns
## empty against that slab, the blast sees no wall, the zombie dies, and the check
## reads exactly like a missing line-of-sight test. Measured: a ray fired straight at
## the freshly-added slab returned `{ }` while a ray down the same space into the real
## level returned `WorldCollision`. The level's own geometry was built during
## world_builder's pass and IS in the space, so that is what the blast is fired at.
##
## Both ends, as everywhere in this file: the walled bearing proves the blast is
## stopped, and the open bearing proves the same blast at the same range still kills —
## without which a wedge that had simply stopped working would pass. The search itself
## is asserted too, because "no walled bearing exists" would otherwise quietly demote
## this to a single-ended test.
static func _cone_occlusion(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var cam := p.camera()
	var world3d := main.get_world_3d()
	var save := _snapshot()
	var yaw_was := p.rotation.y
	Game.insta_kill = 0.0
	Game.dbl_points = 0.0
	Game.drop_count = Game.DROP_CAP

	# How far a body's centre sits above its feet, read off a real one rather than
	# assumed: `centre()` is the point `_cone_blast` aims at, so it is the height the
	# sight line has to be searched at or the search answers a different question.
	var lift := _centre_lift(main)

	# Both bearings are taken at the SAME range, so the pair differs by geometry and
	# by nothing else. A walled bearing at 8 m against an open one at 3 m would also
	# differ in range, and "it survived" would have two candidate explanations again.
	var walled := 0.0
	var open := 0.0
	var range_used := 0.0
	var have_walled := false
	var have_open := false
	for dist: float in RANGES:
		var w := 0.0
		var o := 0.0
		var got_w := false
		var got_o := false
		for i in BEARINGS:
			var yaw := float(i) * TAU / float(BEARINGS)
			p.rotation.y = yaw
			var feet := cam.global_position + _flat_forward(cam) * dist
			if LOS.clear(world3d, cam.global_position, Vector3(feet.x, lift, feet.z)):
				if not got_o:
					o = yaw
					got_o = true
			elif not got_w:
				w = yaw
				got_w = true
		if got_w and got_o:
			walled = w
			open = o
			range_used = dist
			have_walled = true
			have_open = true
			break

	# First, and separately: without this, a map that stopped offering one of the two
	# would report a tidy pass on the half of the pair it could still run.
	v.check("the map offers a walled and an open bearing at one range to fire the blast along",
		have_walled and have_open,
		"none of %s worked from %s" % [RANGES, cam.global_position])

	var survived := false
	var behind_hp := 0.0
	if have_walled:
		p.rotation.y = walled
		var behind := _target(main, p, range_used)
		p._cone_blast(Weapons.spec(WEAPONS_THUNDERGUN))
		survived = behind.state != Zombie.State.DYING
		behind_hp = behind.hp
		_drop(behind)

	var died := false
	if have_open:
		p.rotation.y = open
		var clear := _target(main, p, range_used)
		p._cone_blast(Weapons.spec(WEAPONS_THUNDERGUN))
		died = clear.state == Zombie.State.DYING
		_drop(clear)

	v.check("the blast is stopped by a wall and kills along an open bearing at the same range",
		survived and died,
		"at %.1f m — walled bearing %.2f rad: survived=%s hp=%.0f / open %.2f rad: killed=%s" % [
			range_used, walled, survived, behind_hp, open, died])

	p.rotation.y = yaw_was
	_restore(save)


# --- going down --------------------------------------------------------------

## SOLO, NOT CO-OP. SYNTHESIS.md's "perk loss on down" is the co-op rule; the ancestor
## deletes `P.perks.revive` and nothing else (html:2361-2362), which is solo BO1 and
## is what this game is. Four perks in, three out, and the three that stay are named.
static func _down_consumes_one_perk(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var save := _snapshot()
	var muted := _mute_death(p)
	_clear_gate(p)

	Game.perks.clear()
	for k: String in ["jug", "speed", "dtap", "revive"]:
		Game.perks[k] = true
	Game.revives_left = 1
	# Two guns with the second in hand, so "forces slot 0" is a move rather than a
	# coincidence. `P.slot=0` (html:2364) is the first slot, not a named weapon.
	p.guns = [Weapons.make_gun("m1911", false), Weapons.make_gun("mp40", false)]
	p.slot = 1
	p.is_downed = false
	p.hp = Game.max_health()

	p.take_damage(1e6, 4242)

	var kept := Game.has_perk("jug") and Game.has_perk("speed") and Game.has_perk("dtap")
	v.check("going down with Quick Revive downs the player rather than killing them",
		p.is_downed and _deaths(muted) == 0,
		"downed=%s deaths=%d" % [p.is_downed, _deaths(muted)])
	v.check("exactly Quick Revive is consumed, and no other perk",
		not Game.has_perk("revive") and kept and Game.perks.size() == 3,
		"perks left: %s" % str(Game.perks.keys()))
	v.check("the bleedout clock starts at the canon seven seconds",
		v.near(p.downed_time, Game.DOWNED_TIME) and v.near(Game.DOWNED_TIME, 7.0),
		"downed_time=%.2f DOWNED_TIME=%.2f" % [p.downed_time, Game.DOWNED_TIME])
	v.check("going down forces the first slot", p.slot == 0, "slot=%d" % p.slot)

	p.is_downed = false
	p.downed_time = 0.0
	_unmute_death(p, muted)
	_restore(save)


## ...and without it the run is over on the spot. Observed on a counter of this
## file's own, with main.gd's listener disconnected: `died` is what becomes
## `Game.record_run()`, and a test must not write the player's profile.
static func _down_without_the_perk_ends_the_run(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var save := _snapshot()
	var muted := _mute_death(p)
	_clear_gate(p)

	Game.perks.clear()
	# Deliberately left standing: `_go_down` gates on the perk, and a spare counter
	# that could still buy a down would be an authority nothing else in the game can
	# see — not the machine, not the badges, not `can_take_perk`.
	Game.revives_left = 3
	p.is_downed = false
	p.hp = Game.max_health()

	p.take_damage(1e6, 4243)

	v.check("going down with no Quick Revive ends the run instead of downing",
		_deaths(muted) == 1 and not p.is_downed,
		"deaths=%d downed=%s revives_left=%d" % [
			_deaths(muted), p.is_downed, Game.revives_left])

	p.is_downed = false
	_unmute_death(p, muted)
	_restore(save)


## A DOWNED PLAYER CANNOT BE HURT. `hurtPlayer` early-returns on `P.downed`
## (html:2349), which is what makes the ancestor's own downed-crawl attack branch
## (html:2331) dead code. Health is parked well above zero first, so the guard failing
## would be a visible subtraction rather than a clamp at a floor it was already on.
static func _downed_cannot_be_hurt(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var save := _snapshot()
	var muted := _mute_death(p)
	_clear_gate(p)

	Game.perks.clear()
	p.is_downed = true
	p.downed_time = Game.DOWNED_TIME
	p.hp = 40.0

	# A fresh attacker id each time, so nothing is refused by the per-attacker grace
	# window instead of by the downed guard — which would pass for the wrong reason.
	for i in 5:
		p.take_damage(10.0, 5550 + i)
	var held := v.near(p.hp, 40.0, 0.001)

	# The converse, standing up, in the same shape: five hits of ten off forty is
	# fifty of damage that has to actually land, or the check above proves only that
	# take_damage does nothing at all.
	p.is_downed = false
	p.hp = 40.0
	for i in 5:
		p.take_damage(6.0, 5560 + i)
	var landed := v.near(p.hp, 10.0, 0.001)

	v.check("five attackers cannot scratch a downed player, and can hurt a standing one",
		held and landed and _deaths(muted) == 0,
		"downed hp=%.1f (want 40) / standing hp=%.1f (want 10)" % [40.0 if held else p.hp, p.hp])

	p.is_downed = false
	_unmute_death(p, muted)
	_restore(save)


## THE BLEEDOUT ENDS IN A REVIVE. `if(P.downT<=0) reviveUp()` (html:2926), and
## `reviveUp` restores FULL health (html:2373) — the port emitted `died` instead, so
## Quick Revive bought seven seconds of crawling and then the same death.
##
## Driven by hand at a fixed 60 Hz rather than by waiting: `Verify.run` is
## synchronous. Sampled half a second SHORT of the timer and then past it, because a
## single sample after the end would pass equally well against a timer that fired on
## the first frame — which is the failure this project has already shipped once.
static func _bleedout(v: Verify, main: Node3D) -> void:
	var p: Player = main.player
	var save := _snapshot()
	var muted := _mute_death(p)
	_clear_gate(p)
	var state_was: int = Game.state
	Game.set_state(Game.STATE_PLAY)

	Game.perks.clear()
	Game.perks["revive"] = true
	Game.revives_left = 1
	p.is_downed = false
	p.hp = Game.max_health()
	p.take_damage(1e6, 4244)

	# Half a second short of the seven, so the near end of the window is real.
	var short := int((Game.DOWNED_TIME - 0.5) * 60.0)
	for i in short:
		p._physics_process(1.0 / 60.0)
	var still_down := p.is_downed and p.hp <= 0.0 and p.downed_time > 0.0
	var left := p.downed_time

	# ...and 0.83 s more, comfortably past the 0.5 s remaining and comfortably under
	# a second bleedout, so "it came up" cannot be a second cycle.
	for i in 50:
		p._physics_process(1.0 / 60.0)
	var up := not p.is_downed and v.near(p.hp, Game.max_health(), 0.01)

	v.check("the bleedout is still running at 6.5 s and has ended by 7.33 s",
		still_down and up,
		"at 6.5s: downed=%s hp=%.1f left=%.2f / after: downed=%s hp=%.1f" % [
			p.is_downed if not still_down else true, p.hp, left, p.is_downed, p.hp])
	v.check("standing up restores FULL health, not the health you went down with",
		v.near(p.hp, Game.max_health(), 0.01) and Game.max_health() > 0.0,
		"hp=%.1f of %.1f" % [p.hp, Game.max_health()])
	# The perk is spent by the down and must not come back with the player: the
	# machine is what sells the next one, three times a run.
	v.check("the revive is spent, not refunded, by getting back up",
		not Game.has_perk("revive"), str(Game.perks.keys()))

	# The eye is mid-climb after a revive — 0.36 s of travel against the 0.83 s just
	# run, so it is home, but pinned rather than assumed because _hit_geometry
	# asserts this exact value and may run either side of this file.
	p.is_downed = false
	p._head.position.y = Player.EYE
	Game.set_state(state_was)
	_unmute_death(p, muted)
	_restore(save)


# --- fixtures ----------------------------------------------------------------

## The camera's forward, flattened onto the floor plane. Flattened because the bearing
## search and the body placement have to agree to the millimetre: a pitched camera
## scales the raw basis vector's horizontal part by cos(pitch), so searching with one
## and placing with the other would put the body off the line that was tested.
static func _flat_forward(cam: Camera3D) -> Vector3:
	var fwd := -cam.global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z)
	# A camera pitched at the ceiling has no horizontal forward to sweep along.
	return flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD


## How far `centre()` sits above a body's feet, measured off a real one. Freed again
## immediately and never in the group, so no blast can see it.
static func _centre_lift(main: Node3D) -> float:
	var probe := Zombie.create("zombie", 0, 1, false)
	main.add_child(probe)
	probe.global_position = Vector3.ZERO
	var lift: float = probe.centre().y
	probe.queue_free()
	return lift


## One live zombie, `n` metres straight ahead of the camera on the floor. In the
## group, because `_cone_blast` walks the group and not the director's list.
static func _target(main: Node3D, p: Player, n: float) -> Zombie:
	var at := p.camera().global_position + _flat_forward(p.camera()) * n
	var z := Zombie.create("zombie", 0, 1, false)
	main.add_child(z)
	z.add_to_group("zombies")
	z.global_position = Vector3(at.x, 0.0, at.z)
	return z


## Out of the group BEFORE the free, because `queue_free` is deferred: a body left in
## the group would still be walked by the next blast in this same synchronous run.
static func _drop(z: Zombie) -> void:
	z.remove_from_group("zombies")
	z.queue_free()


# --- state this file is not allowed to keep ----------------------------------

## The per-attacker grace window, emptied.
##
## `Player._hurt_gate` is only ticked down by `_physics_process`, and only while the
## state is PLAY — so an attacker id spent by an earlier assertion is still live by the
## time this file runs. verify.gd's own `_losable` hits attacker 4242 and this file
## reused the same number, so the first `take_damage` here was refused outright: no
## down, no death, no damage, and four checks failing at once with nothing wrong in the
## game. Cleared rather than dodged with fresh ids, so no future check has to know
## which numbers some other file has already spent.
static func _clear_gate(p: Player) -> void:
	p._hurt_gate.clear()


## `died` is main.gd's cue to call `Game.record_run()`, which writes the player's
## real profile to disk. Two of the checks above have to end a run, so every listener
## comes off for the duration and a counter of this file's own goes on instead.
## Read back through `_deaths` rather than through the state machine, which nothing
## here is allowed to move either.
static func _mute_death(p: Player) -> Array:
	var was: Array[Callable] = []
	for c: Dictionary in p.died.get_connections():
		var cb: Callable = c.callable
		was.append(cb)
		p.died.disconnect(cb)
	var count: Array[int] = [0]
	var counter := func() -> void:
		count[0] += 1
	p.died.connect(counter)
	return [was, count, counter]


static func _deaths(muted: Array) -> int:
	var count: Array = muted[1]
	return int(count[0])


static func _unmute_death(p: Player, muted: Array) -> void:
	var was: Array = muted[0]
	var counter: Callable = muted[2]
	p.died.disconnect(counter)
	for cb: Callable in was:
		p.died.connect(cb)


## Everything on Game and on the player that any check here writes. Kept as one
## dictionary rather than a dozen locals per function because the restore is the part
## that gets forgotten, and a partial one leaves the rest of the suite measuring a
## run this file invented.
static func _snapshot() -> Dictionary:
	return {
		"points": Game.points,
		"kills": Game.kills,
		"headshots": Game.headshots,
		"perks": Game.perks.duplicate(),
		"revives_left": Game.revives_left,
		"revive_uses": Game.revive_uses,
		"insta_kill": Game.insta_kill,
		"dbl_points": Game.dbl_points,
		"drop_count": Game.drop_count,
		"points_earned": Game.points_earned,
		"next_drop_at": Game.next_drop_at,
		"drop_index": Game.drop_index,
	}


static func _restore(s: Dictionary) -> void:
	Game.points = s.points
	Game.kills = s.kills
	Game.headshots = s.headshots
	Game.perks = s.perks
	Game.revives_left = s.revives_left
	Game.revive_uses = s.revive_uses
	Game.insta_kill = s.insta_kill
	Game.dbl_points = s.dbl_points
	Game.drop_count = s.drop_count
	Game.points_earned = s.points_earned
	Game.next_drop_at = s.next_drop_at
	Game.drop_index = s.drop_index
