extends Node

## Every interactable in the level and the scan that decides which one the F key
## is currently pointed at: doors, wall buys, the Bowie knife, the perk machines,
## the barricades, the generator, Pack-a-Punch and the mystery box.
##
## Split out of main.gd. The wave-1 split relocated the scan faithfully without
## redesigning it, and this is the redesign it left a seam for. What the scan used
## to be was one distance test over a flat list, with three consequences:
##
##  - you could buy through a wall. Measured, not inferred: the Corridor's corner
##    tile (21,10) is 1.89 m from the MP40 wall buy's interact point at
##    (23.1, 11.5), and tiles (22,10) and (22,11) are both solid.
##  - you could buy something behind you.
##  - every satisfied object was re-tested every frame forever.
##
## So: a facing budget, an occlusion ray, and two buckets instead of one list.

## preload rather than the global class name: a freshly added script is not in
## the class registry until the editor rescans, and a headless run has no editor.
const MYSTERY_BOX := preload("res://scripts/systems/mystery_box.gd")
## The one line-of-sight test in the project, shared with the AI and the hitscan.
## See `_sees()` for why the slack this scan needs is expressed by shortening the
## ray here rather than by adding a parameter there.
const LOS := preload("res://scripts/world/los.gd")
## The electric traps, for TRAP_COST. The switch rows themselves come from the
## bound instance; only the price is a constant, and it is read from there rather
## than restated so the prompt and the spend cannot disagree.
const TRAPS := preload("res://scripts/systems/traps.gd")

const INTERACT_RADIUS := 2.0
const PAP_COST := 5000
const POWER_COST := 0

## Barricade repair: 0.34 s a plank, +10 points each. Six planks is about two
## seconds for sixty points, which is the whole economy of rounds one to three.
const REBUILD_PER_BOARD := 0.34
const WINDOW_RADIUS := 1.7
## Progress bleeds away instead of snapping to zero, in boards per second. A flick
## of the mouse off the barricade — which the facing test below now makes a real
## event rather than an impossible one — must not cost the plank you were most of
## the way through. Full to empty in 0.67 s, so abandoning it still abandons it.
const HOLD_DECAY := 1.5

## THE FACING BUDGET.
##
## The ancestor already has a facing test — `dot < 0.35` beyond 0.4 m, windows
## exempt (html:2684-2687). 0.35 is a 69.5 degree half-angle, and the camera is
## 74 degrees vertical, which at 16:9 is about 106 horizontal: 53 degrees of
## half-frame. So the ancestor's own rule admits things that are off the edge of
## the screen. That is "near it", not "looking at it", and the reference is
## unambiguous that you look at what you buy.
##
## An angle budget instead of a flat dot: 30 degrees, widened by however much of
## the frame the object itself subtends at that range. A machine is a bit over a
## metre across, so the allowance opens as you close — 45 degrees at two metres,
## 59 at one, 78 at half — and unlike the ancestor's `d > 0.4` guard there is no
## step to fall through. Windows are NOT exempt: the exemption is a convenience
## the reference does not have, and at a barricade's range the budget is 60-90
## degrees anyway.
const FACING_HALF_DEG := 30.0
const FACING_SIZE := 0.55
const FACING_MIN_D := 0.2

## THE OCCLUSION RAY.
##
## Height 1.2 m, which is `los.gd:clear_flat`'s own default and the height the AI
## test uses — a torso rather than an eye. The ray ORIGINATES at the camera (see
## `_sees()`), so this is only where it lands.
##
## `slack` is how far short of the target the ray may stop and still count as
## clear, and it exists because a door's interact point is the centre of the door
## tile, which is *inside the door's own collider*. Without it every door in the
## level would be permanently occluded by itself. Half a tile plus a little covers
## the door face; the small value covers a wall-buy plaque standing 0.1 m proud of
## its wall.
const INTERACT_LOS_Y := 1.2
const LOS_SLACK := 0.3
const DOOR_LOS_SLACK := 0.75

## Pack-a-Punch is a machine with a cycle, not a vending slot. 4.2 s of work, then
## the weapon waits on the machine until it is collected — with no timeout, ever,
## which is the whole of "you cannot lose a weapon by walking away".
const PAP_WORK := 4.2
## The throb while it runs, in Hz.
const PAP_THROB := 1.6

var map: MapData
var world: WorldBuilder
var flow: FlowField
var player: Player
## hud.gd, lighting.gd, atmosphere.gd and mystery_box.gd. All four are untyped for
## the same reason main.gd's handles are: the scripts are attached at runtime, so
## a typed variable cannot see set_prompt() / power_on() / light_perks() / use().
var hud
var lighting
var atmos
var box
## traps.gd. Untyped for the same reason the four above are: the script is
## attached at runtime, so a typed handle could not see state_of() or arm().
var traps

## Every row ever built. Nothing reads it but the debug console and the assertion
## suite; the scan does not touch it.
var _interactables: Array = []
## The rows the scan actually walks, and the rows that currently offer nothing but
## could again. A door that has been bought or a perk that has been drunk leaves
## `_live` and goes nowhere — it is out of the game. A barricade at six boards
## sleeps, and wakes on one array read the frame a zombie pulls a plank off.
var _live: Array = []
var _sleeping: Array = []

## Which row the hold accumulator belongs to, by stable key rather than by index —
## `_live` is reordered by retirement, so an index would silently re-point.
var _hold_on := ""
var _hold_t := 0.0

var _pap_state := "idle"      # idle | working | ready
var _pap_t := 0.0
var _pap_phase := 0.0
var _pap_key := ""


func bind(m: MapData, w: WorldBuilder, f: FlowField, p: Player, h: Node,
		lit: Node3D, a: Node3D, b: Node, tr: Node3D) -> void:
	map = m
	world = w
	flow = f
	player = p
	hud = h
	lighting = lit
	atmos = a
	box = b
	traps = tr


## The table the scan walks, and the moment every prop in the level is spawned —
## the two were written together in main.gd and the order between them is the
## order the sprites end up in, so they stay together.
##
## Every row carries a `key`: a stable identity for the hold accumulator, the
## debug console and the assertions. An index is not one, because retirement
## reorders `_live`.
func build() -> void:
	_interactables.clear()
	_live.clear()
	_sleeping.clear()

	for d in MapData.DOORS.size():
		var t = MapData.DOORS[d].tiles[0]
		_add({
			"kind": "door", "key": "door:%d" % d, "id": d,
			"pos": Vector2(t[0] + 0.5, t[1] + 0.5),
			"cost": MapData.DOORS[d].cost,
			"label": MapData.DOORS[d].label,
			"radius": 2.4,
			# The door's interact point is inside the door slab itself.
			"slack": DOOR_LOS_SLACK,
		})

	for wb in MapData.WALLBUYS:
		_add({
			"kind": "wallbuy", "key": "wallbuy:%s" % wb.gun, "gun": wb.gun,
			"pos": Vector2(wb.tile[0] + 0.5 + wb.face[0] * 0.6, wb.tile[1] + 0.5 + wb.face[1] * 0.6),
			"cost": wb.cost,
			"label": Weapons.TABLE[wb.gun].name,
			"radius": INTERACT_RADIUS,
		})
		# `wb` is a Variant out of an untyped Array, so every value is pulled out
		# with an explicit type before it reaches the typed signature.
		var wb_gun: String = wb.gun
		var wb_tile: Array = wb.tile
		var wb_face: Array = wb.face
		atmos.spawn_chalk(wb_gun, wb_tile, wb_face)

	_add({
		"kind": "bowie", "key": "bowie",
		"pos": Vector2(MapData.BOWIE.tile[0] + 0.5 + MapData.BOWIE.face[0] * 0.6,
			MapData.BOWIE.tile[1] + 0.5 + MapData.BOWIE.face[1] * 0.6),
		"cost": MapData.BOWIE.cost, "label": "Bowie Knife", "radius": INTERACT_RADIUS,
	})
	var bowie_tile: Array = MapData.BOWIE.tile
	var bowie_face: Array = MapData.BOWIE.face
	atmos.spawn_chalk("bowie", bowie_tile, bowie_face)

	for ps in MapData.PERKSPOTS:
		_add({
			"kind": "perk", "key": "perk:%s" % ps.k, "perk": ps.k, "pos": Vector2(ps.x, ps.y),
			"cost": Game.REVIVE_COST if ps.k == "revive" else Weapons.PERKDEF[ps.k].cost,
			"label": Weapons.PERKDEF[ps.k].name, "radius": INTERACT_RADIUS,
		})
		var spot: Dictionary = ps
		atmos.spawn_perk_marker(spot)

	# Every barricade is a hold-to-repair station. This is the round 1-3 economy
	# and the verb the port dropped entirely: PTS_REBUILD was declared and used
	# nowhere, and the `board` sound was baked and played by nothing.
	for wi in MapData.WINDOWS.size():
		var w: Dictionary = MapData.WINDOWS[wi]
		_add({
			"kind": "window", "key": "window:%d" % wi, "id": wi,
			"pos": Vector2(w.ix + 0.5, w.iy + 0.5),
			"cost": 0, "label": "Rebuild barricade", "radius": WINDOW_RADIUS,
		})

	# The electric traps. Built from the traps system's own rows rather than from a
	# second table here, so a gate that moves moves once. They never retire: a trap
	# is a thing you buy again, which is the whole of its economy.
	for t: Dictionary in traps.spots():
		_add({
			"kind": "trap", "key": "trap:%s" % t.key, "trap": String(t.key),
			"pos": Vector2(t.switch), "cost": TRAPS.TRAP_COST,
			"label": String(t.label), "radius": INTERACT_RADIUS,
		})

	_add({
		"kind": "power", "key": "power", "pos": MapData.GENSPOT, "cost": POWER_COST,
		"label": "Turn on the power", "radius": 2.2,
	})
	atmos.spawn_generator()
	_add({
		"kind": "pap", "key": "pap", "pos": MapData.PAPSPOT, "cost": PAP_COST,
		"label": "Pack-a-Punch", "radius": 2.2,
	})
	atmos.spawn_pap()

	var box_entry := {
		"kind": "box", "key": "box", "pos": MapData.BOXSPOTS[0], "cost": MYSTERY_BOX.BOX_COST,
		"label": "Mystery Box", "radius": 2.2,
	}
	_add(box_entry)
	# The box keeps the row itself, so a relocation writes `pos` here rather than
	# searching this table for the one entry it already had a handle on. It also
	# rolls where it starts, so `pos` above is only what the row is born with.
	box.adopt(box_entry)

	# Every barricade starts full, so every barricade starts asleep. Otherwise the
	# fourteen of them would be distance-tested every frame of round one to prove
	# something one array read already knows.
	_sweep()


func _add(row: Dictionary) -> void:
	_interactables.append(row)
	_live.append(row)


## Every row, live or not. The debug console reads it; nothing writes to it from
## outside.
func table() -> Array:
	return _interactables


## The rows the scan is actually walking this frame.
func live() -> Array:
	return _live


## The rows that currently offer nothing but could again. Together with `live()`
## this partitions everything that has not been bought outright, which is the shape
## the assertions check.
func sleeping() -> Array:
	return _sleeping


func pap_state() -> String:
	return _pap_state


# --- the scan ----------------------------------------------------------------

## Describes what an interactable currently offers. `ok` false with `none` true
## means "nothing to do here" — those are skipped by the scan entirely rather
## than winning the nearest-pick and silently swallowing the F key.
func _state_of(it: Dictionary) -> Dictionary:
	match it.kind:
		"door":
			return {"label": "%s  —  %d" % [it.label, it.cost], "cost": it.cost, "hold": false, "none": false}
		"wallbuy":
			if _owns(it.gun):
				var full := true
				for g in player.guns:
					if g.key == it.gun and g.res < g.def.res:
						full = false
				if full:
					return {"label": "%s — ammo full" % it.label, "cost": 0, "hold": false, "none": true}
				var ammo_cost: int = 4500 if _pap_of(it.gun) else int(it.cost / 2)
				return {"label": "%s ammo  —  %d" % [it.label, ammo_cost], "cost": ammo_cost, "hold": false, "none": false}
			return {"label": "Buy %s  —  %d" % [it.label, it.cost], "cost": it.cost, "hold": false, "none": false}
		"bowie":
			if player.has_bowie:
				return {"none": true}
			return {"label": "%s  —  %d" % [it.label, it.cost], "cost": it.cost, "hold": false, "none": false}
		"perk":
			if Game.has_perk(it.perk):
				return {"none": true}
			# Solo Quick Revive is live from round one and needs no power.
			if it.perk != "revive" and not Game.power_on:
				return {"label": "%s  —  needs power" % it.label, "cost": 0, "hold": false, "none": true}
			if it.perk == "revive" and Game.revive_uses >= Game.REVIVE_MAX_USES:
				return {"none": true}
			if not Game.can_take_perk(it.perk):
				return {"label": "%s  —  perks full" % it.label, "cost": 0, "hold": false, "none": true}
			var blurb: String = Weapons.PERKDEF[it.perk].blurb
			return {"label": "%s  —  %d   (%s)" % [it.label, it.cost, blurb], "cost": it.cost, "hold": false, "none": false}
		"window":
			if map.window_boards[it.id] >= 6:
				return {"none": true}
			# Not while something is pulling them off. Nailing a plank back on over a
			# zombie's hands lets the player out-tick the teardown outright, which
			# turns the round 1-5 barricade from a clock into a stalemate. `none`
			# rather than an unaffordable prompt, because the scan skips `none`
			# entries — so a live interactable behind you can still win the
			# nearest-pick while a window is busy.
			if map.window_workers[it.id] > 0:
				return {"none": true}
			return {"label": "Rebuild barricade", "cost": 0, "hold": true, "none": false}
		"trap":
			# Canon: the traps run off the generator. That gate is most of why a trap
			# cannot touch the early game — the generator is behind two bought doors —
			# so it is stated here rather than left to the map to imply.
			if not Game.power_on:
				return {"label": "%s  —  needs power" % it.label, "cost": 0, "hold": false, "none": true}
			var ts: String = traps.state_of(it.trap)
			if ts == "live":
				# `bare` and NOT `none`: a live gate must go on winning the
				# nearest-pick, so F at a crackling trap says something legible
				# instead of reaching past it to whatever is behind.
				return {"label": "%s  —  live  (%ds)" % [it.label,
					ceili(float(traps.active_left(it.trap)))],
					"cost": 0, "hold": false, "none": false, "bare": true}
			if ts == "cooldown":
				return {"label": "%s  —  cooling down  (%ds)" % [it.label,
					ceili(float(traps.cooldown_left(it.trap)))],
					"cost": 0, "hold": false, "none": false, "bare": true}
			return {"label": "%s  —  %d" % [it.label, it.cost], "cost": it.cost,
				"hold": false, "none": false}
		"power":
			if Game.power_on:
				return {"none": true}
			return {"label": "Turn on the power", "cost": 0, "hold": false, "none": false}
		"pap":
			# The machine's own cycle comes first: it outranks "needs power" and
			# "already upgraded", because while it is running neither is the answer
			# to what the player is looking at.
			if _pap_state == "ready":
				return {"label": "Take the %s" % _pap_name(), "cost": 0, "hold": false, "none": false}
			if _pap_state == "working":
				return {"label": "Pack-a-Punch  —  working", "cost": 0, "hold": false,
					"none": false, "bare": true}
			if not Game.power_on:
				return {"label": "Pack-a-Punch  —  needs power", "cost": 0, "hold": false, "none": true}
			if player.current_gun().pap:
				return {"label": "Pack-a-Punch  —  already upgraded", "cost": 0, "hold": false, "none": true}
			# The ancestor names the weapon going in (html:2727) and the port dropped
			# it, which left one prompt for a decision that costs five thousand
			# points and depends entirely on which gun is in your hands.
			return {"label": "Pack-a-Punch the %s  —  %d" % [player.current_gun().def.name, it.cost],
				"cost": it.cost, "hold": false, "none": false}
		"box":
			var box_state: String = box.state()
			if box_state == "offering":
				var offered: String = box.gun()
				return {"label": "Take the %s" % Weapons.TABLE[offered].name, "cost": 0, "hold": false, "none": false}
			if box_state != "idle":
				# Mid-cycle, and deliberately still selectable rather than `none`.
				# The ancestor does the same — html:2731 returns null, and html:2745
				# then early-returns — so F at a running box never reaches past it to
				# something else. `box.use()` is a no-op in every non-idle state.
				#
				# The label is the reel in words. Four of the eleven box weapons have
				# no chalk plaque in assets/props yet (see
				# `atmosphere.set_box_display`), so the name under the crosshair is
				# what makes the spin legible for all eleven of them.
				var reel: String = box.shown()
				var text: String = "..." if reel.is_empty() else Weapons.TABLE[reel].name
				return {"label": text, "cost": 0, "hold": false, "none": false, "bare": true}
			return {"label": "Mystery Box  —  %d" % it.cost, "cost": it.cost, "hold": false, "none": false}
	return {"none": true}


func _pap_name() -> String:
	return Weapons.PAP_NAMES.get(_pap_key, "upgrade")


func _pap_of(key: String) -> bool:
	for g in player.guns:
		if g.key == key:
			return g.pap
	return false


func _owns(key: String) -> bool:
	for g in player.guns:
		if g.key == key:
			return true
	return false


## Driven from main.gd rather than from this node's own `_process` — see the note
## on the drive order there. Runs last, exactly where main.gd's `_update_interact`
## used to sit, because a purchase made here can draw from the BOX stream.
func tick(dt: float) -> void:
	_sweep()
	_tick_pap(dt)

	var pick := _scan()
	var it: Dictionary = pick.get("it", {})
	var st: Dictionary = pick.get("st", {})
	var key: String = it.get("key", "")

	# A different object is a different job. Looking away at nothing is not: that
	# falls through to the decay below, which is the point of the accumulator.
	if not key.is_empty() and key != _hold_on:
		_hold_t = 0.0
		_hold_on = key

	if it.is_empty():
		hud.set_prompt("")
		_bleed(dt)
		return

	var affordable: bool = Game.points >= int(st.get("cost", 0))
	if st.get("bare", false):
		hud.set_prompt(String(st.label), affordable)
	else:
		var verb := "Hold F" if st.get("hold", false) else "[F]"
		hud.set_prompt("%s  %s" % [verb, st.label], affordable)

	if st.get("hold", false):
		if Input.is_action_pressed("interact"):
			_hold_t += dt
			# Subtract rather than zero, so the remainder inside a frame is carried
			# into the next plank. Zeroing quantises every board up to a whole frame
			# and makes the delivered rebuild rate depend on the frame rate — the
			# same bug the weapon cadence had, for the same reason.
			while _hold_t >= REBUILD_PER_BOARD:
				_hold_t -= REBUILD_PER_BOARD
				if not _rebuild_board(it):
					_hold_t = 0.0
					break
		else:
			_bleed(dt)
		hud.set_hold(_hold_t / REBUILD_PER_BOARD)
		return

	_bleed(dt)
	hud.set_hold(_hold_t / REBUILD_PER_BOARD)
	if Input.is_action_just_pressed("interact"):
		_do_interact(it, st)


func _bleed(dt: float) -> void:
	_hold_t = maxf(0.0, _hold_t - HOLD_DECAY * REBUILD_PER_BOARD * dt)
	hud.set_hold(_hold_t / REBUILD_PER_BOARD)


## Nearest live interactable that has something to offer, that the player is
## looking at, and that the player can actually see.
##
## The ray is cast only for candidates that would beat the current best, because a
## physics query is the expensive part of this function and the distance and
## facing tests reject almost everything for free. A nearer candidate that fails
## the ray does not shadow a farther one: `best_d` is only moved after the ray
## comes back clear.
func _scan() -> Dictionary:
	var here := player.grid_pos()
	var eye := player.camera().global_position
	var fwd := -player.global_transform.basis.z
	var face := Vector2(fwd.x, fwd.z).normalized()
	var best: Dictionary = {}
	var best_d := 1e9
	for it: Dictionary in _live:
		var d: float = here.distance_to(it.pos)
		if d > float(it.radius):
			continue
		if not _facing(here, face, it.pos, d):
			continue
		var st := _state_of(it)
		if st.get("none", true):
			continue
		if d >= best_d:
			continue
		if not _sees(eye, it):
			continue
		best_d = d
		best = {"it": it, "st": st}
	return best


func _facing(here: Vector2, face: Vector2, at: Vector2, d: float) -> bool:
	var to := at - here
	if to.length_squared() < 0.0001:
		return true
	return absf(face.angle_to(to)) <= deg_to_rad(FACING_HALF_DEG) \
		+ atan(FACING_SIZE / maxf(d, FACING_MIN_D))


## Whether the player can actually see the thing they are about to buy.
##
## Goes through the shared `los.gd` rather than casting its own ray: four callers
## have to agree about what "can see" means, and this scan is one of them. The
## helper landed this wave and this was the last raw `intersect_ray` left.
##
## SLACK IS APPLIED BY SHORTENING THE RAY, not by asking the helper for it. The
## helper answers one question — is anything solid between these two points — and
## it is worth more as that question than as a question with an exception
## parameter that only this call site ever passes. Stopping the ray `slack` short
## of the target is the same test: for a hit on the segment, "within slack of the
## far end" and "past length - slack" are the same condition, so tolerating the
## first is refusing to look at the second.
##
## The ray starts at the camera's real origin rather than at a fixed eye height,
## because that is where the player is actually looking from — pinning it would
## let a crouch change what is buyable.
func _sees(eye: Vector3, it: Dictionary) -> bool:
	var target := Vector3(it.pos.x, INTERACT_LOS_Y, it.pos.y)
	var slack: float = float(it.get("slack", LOS_SLACK))
	var span := target - eye
	var dist := span.length()
	# Already inside the slack sphere: there is no segment left to test, and
	# normalising a zero-length span would be a division by zero.
	if dist <= slack:
		return true
	return LOS.clear(player.get_world_3d(), eye, eye + span * ((dist - slack) / dist))


# --- retirement --------------------------------------------------------------

## Whether a row that currently offers nothing might offer something again.
##
## Only the barricades, and only on being full: a full barricade is the common
## case for most of a round, and the test that brings it back is one read out of a
## PackedInt32Array. Everything else that is temporarily `none` — an unpowered
## machine, a topped-up wall buy, a busy window — stays in `_live` and is filtered,
## because there are at most a dozen of those and their wake conditions are not
## cheaper than the filter.
func _sleeps(it: Dictionary) -> bool:
	return it.kind == "window" and map.window_boards[it.id] >= 6


## Out of the game for good: a bought door, a drunk perk, a thrown generator. No
## wake condition exists, so nothing looks for one.
func _retire_forever(it: Dictionary) -> void:
	_live.erase(it)


## Moves barricades between `_live` and `_sleeping`, in BOTH directions, once a
## tick.
##
## Both directions and in one place, because the scan cannot be the one to do it.
## A scan only ever looks at what is in range, so a barricade refilled by a
## Carpenter drop while the player is across the map would sit in `_live` until the
## player next walked up to it — which makes "a full barricade is not scanned" true
## only sometimes, and a claim that is true only sometimes is not worth making. The
## unconditional version costs fourteen array reads a tick and lets the assertions
## state the invariant flatly.
##
## The two conditions this has to survive are exactly the two that do not route
## through this file: `powerup_manager` fills all fourteen at once, and
## `barricade.gd` empties one plank at a time.
func _sweep() -> void:
	var i := _live.size() - 1
	while i >= 0:
		var it: Dictionary = _live[i]
		if _sleeps(it):
			_live.remove_at(i)
			_sleeping.append(it)
		i -= 1
	i = _sleeping.size() - 1
	while i >= 0:
		var it2: Dictionary = _sleeping[i]
		if not _sleeps(it2):
			_sleeping.remove_at(i)
			_live.append(it2)
		i -= 1


# --- Pack-a-Punch ------------------------------------------------------------

## The machine takes the job, runs for PAP_WORK seconds and then holds the
## upgraded weapon out until it is collected.
##
## It does NOT take the weapon out of the player's hands, which is the one place
## this departs from the reference. In BO1 you are bare-handed for the cycle, and
## that is the tension — but this game gives the player one weapon at the start,
## `Player.current_gun()` indexes `guns[0]` unconditionally, and the viewmodel has
## no empty pose. An empty-handed state is a change to three files this package
## does not own; the report asks for it. What is here already satisfies the harder
## half: the cycle is real, it is interruptible, and `ready` never times out, so
## walking away can never cost a weapon.
func _tick_pap(dt: float) -> void:
	if _pap_state != "working":
		return
	_pap_t -= dt
	_pap_phase += dt
	atmos.pap_glow(0.5 + 0.5 * sin(_pap_phase * TAU * PAP_THROB))
	if _pap_t > 0.0:
		return
	_pap_state = "ready"
	atmos.pap_glow(1.0)
	Sfx.play_at("powerup", _pap_pos(), -4.0)


func _pap_pos() -> Vector3:
	return Vector3(MapData.PAPSPOT.x, INTERACT_LOS_Y, MapData.PAPSPOT.y)


# --- doing the thing ---------------------------------------------------------

## Returns false when there was nothing left to nail on, so the accumulator can
## drop the carry rather than spending it on a finished barricade.
func _rebuild_board(it: Dictionary) -> bool:
	var wi: int = it.id
	if map.window_boards[wi] >= 6:
		return false
	world.set_window_boards(wi, map.window_boards[wi] + 1)
	Game.add_points(Game.PTS_REBUILD)
	Sfx.play_at("board", Vector3(it.pos.x, 1.0, it.pos.y), -6.0)
	return true


func _do_interact(it: Dictionary, st: Dictionary) -> void:
	var cost: int = int(st.get("cost", 0))
	match it.kind:
		"door":
			if Game.spend(cost):
				world.open_door(it.id)
				# The field is stale the instant a wall stops being a wall, and
				# it only re-solves when the player changes tile — so a player
				# who buys a door and stands still leaves the whole horde
				# steering around a door that is now open.
				flow.invalidate()
				_retire_forever(it)
				Sfx.play("buy")
			else:
				_deny()
		"wallbuy":
			if Game.spend(cost):
				if _owns(it.gun):
					player.refill_gun(it.gun)
				else:
					player.give_gun(it.gun, false)
				Sfx.play("buy")
			else:
				_deny()
		"bowie":
			if Game.spend(cost):
				player.has_bowie = true
				_retire_forever(it)
				Sfx.play("buy")
			else:
				_deny()
		"perk":
			if Game.spend(cost):
				Game.perks[it.perk] = true
				if it.perk == "jug":
					player.hp = Game.max_health()
					player.health_changed.emit(player.hp, Game.max_health())
				elif it.perk == "revive":
					Game.revive_uses += 1
					Game.revives_left += 1
				Game.toast.emit(Weapons.PERKDEF[it.perk].name)
				# Quick Revive is the one machine you come back to: it is spent on
				# a down and re-buyable until REVIVE_MAX_USES. Every other perk is
				# a one-time purchase and never has anything to say again.
				if it.perk != "revive" or Game.revive_uses >= Game.REVIVE_MAX_USES:
					_retire_forever(it)
				Sfx.play("buy")
			else:
				_deny()
		"trap":
			# The wallet is spent HERE and not inside `arm()`, exactly as it is for
			# every door, wall buy and perk machine above: traps.gd has no other
			# business with the economy and should not become a second writer of it.
			# `arm()` re-checks the state and the power for itself, so a refusal is
			# reported rather than paid for.
			if traps.state_of(it.trap) != "idle":
				return
			if not Game.spend(cost):
				_deny()
				return
			if not traps.arm(it.trap):
				# Nothing here can reach this today — the prompt refuses on power and
				# the state was just tested — so if it ever does, the money goes back
				# rather than vanishing into a switch that did not throw.
				Game.add_points(cost)
				_deny()
				return
			Sfx.play("buy")
		"power":
			Game.power_on = true
			atmos.light_perks()
			# The Generator Hall's metal plate lifts with the lamps.
			world.set_power_on()
			# Three flickers, then one room per 0.15 s in distance-from-generator
			# order, under the ancestor's whine. The loop this replaces set every
			# lamp to 1.15 against a build value of 1.2, so throwing the generator
			# made the whole level four percent darker.
			lighting.power_on()
			Game.toast.emit("POWER ON")
			_retire_forever(it)
			Sfx.play("buy")
		"pap":
			if _pap_state == "ready":
				# give_gun() upgrades the slot already holding this key, and falls
				# back to the current slot if the player swapped it away — so the
				# upgrade always arrives somewhere, and the machine always empties.
				player.give_gun(_pap_key, true)
				Game.toast.emit(Weapons.PAP_NAMES.get(_pap_key, "Upgraded"))
				_pap_state = "idle"
				_pap_key = ""
				atmos.pap_glow(0.0)
				Sfx.play("buy")
				return
			if _pap_state != "idle":
				return
			var gun := player.current_gun()
			if not Game.spend(cost):
				_deny()
				return
			_pap_key = gun.key
			_pap_state = "working"
			_pap_t = PAP_WORK
			_pap_phase = 0.0
			Sfx.play("buy")
			Sfx.play_at("power_on", _pap_pos(), -12.0, 1.45)
		"box":
			if not box.use():
				_deny()


func _deny() -> void:
	Sfx.play("deny")
	hud.flash_deny()
