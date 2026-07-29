extends Node

## Every interactable in the level and the scan that decides which one the F key
## is currently pointed at: doors, wall buys, the Bowie knife, the perk machines,
## the barricades, the generator, Pack-a-Punch and the mystery box.
##
## Split out of main.gd, and relocated faithfully — the scan below is the one
## main.gd shipped, unchanged. A later package replaces it outright with a facing
## test, an occlusion ray and a radial hold arc; the seam that package needs is
## `_update_interact`, which is the only thing here that reads the player's pose
## or the input, and `_state_of` / `_do_interact`, which do not care how the
## nearest interactable was chosen.

## preload rather than the global class name: a freshly added script is not in
## the class registry until the editor rescans, and a headless run has no editor.
const MYSTERY_BOX := preload("res://scripts/systems/mystery_box.gd")

const INTERACT_RADIUS := 2.0
const PAP_COST := 5000
const POWER_COST := 0

## Barricade repair: 0.34 s a plank, +10 points each. Six planks is about two
## seconds for sixty points, which is the whole economy of rounds one to three.
const REBUILD_PER_BOARD := 0.34
const WINDOW_RADIUS := 1.7

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

var _interactables: Array = []
var _current := -1
var _hold_t := 0.0


func bind(m: MapData, w: WorldBuilder, f: FlowField, p: Player, h: Node,
		lit: Node3D, a: Node3D, b: Node) -> void:
	map = m
	world = w
	flow = f
	player = p
	hud = h
	lighting = lit
	atmos = a
	box = b


## The table the scan walks, and the moment every prop in the level is spawned —
## the two were written together in main.gd and the order between them is the
## order the sprites end up in, so they stay together.
func build() -> void:
	_interactables.clear()

	for d in MapData.DOORS.size():
		var t = MapData.DOORS[d].tiles[0]
		_interactables.append({
			"kind": "door", "id": d,
			"pos": Vector2(t[0] + 0.5, t[1] + 0.5),
			"cost": MapData.DOORS[d].cost,
			"label": MapData.DOORS[d].label,
			"radius": 2.4,
		})

	for wb in MapData.WALLBUYS:
		_interactables.append({
			"kind": "wallbuy", "gun": wb.gun,
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

	_interactables.append({
		"kind": "bowie", "pos": Vector2(MapData.BOWIE.tile[0] + 0.5 + MapData.BOWIE.face[0] * 0.6,
			MapData.BOWIE.tile[1] + 0.5 + MapData.BOWIE.face[1] * 0.6),
		"cost": MapData.BOWIE.cost, "label": "Bowie Knife", "radius": INTERACT_RADIUS,
	})
	var bowie_tile: Array = MapData.BOWIE.tile
	var bowie_face: Array = MapData.BOWIE.face
	atmos.spawn_chalk("bowie", bowie_tile, bowie_face)

	for ps in MapData.PERKSPOTS:
		_interactables.append({
			"kind": "perk", "perk": ps.k, "pos": Vector2(ps.x, ps.y),
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
		_interactables.append({
			"kind": "window", "id": wi,
			"pos": Vector2(w.ix + 0.5, w.iy + 0.5),
			"cost": 0, "label": "Rebuild barricade", "radius": WINDOW_RADIUS,
		})

	_interactables.append({
		"kind": "power", "pos": MapData.GENSPOT, "cost": POWER_COST,
		"label": "Turn on the power", "radius": 2.2,
	})
	atmos.spawn_generator()
	_interactables.append({
		"kind": "pap", "pos": MapData.PAPSPOT, "cost": PAP_COST,
		"label": "Pack-a-Punch", "radius": 2.2,
	})
	atmos.spawn_pap()

	var box_entry := {
		"kind": "box", "pos": MapData.BOXSPOTS[0], "cost": MYSTERY_BOX.BOX_COST,
		"label": "Mystery Box", "radius": 2.2,
	}
	_interactables.append(box_entry)
	# The box keeps the row itself, so a relocation writes `pos` here rather than
	# searching this table for the one entry it already had a handle on.
	box.adopt(box_entry)


## The live table. The debug console reads it; nothing writes to it from outside.
func table() -> Array:
	return _interactables


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
			# rather than an unaffordable prompt, because `_update_interact` skips
			# `none` entries in the scan — so a live interactable behind you can still
			# win the nearest-pick while a window is busy.
			if map.window_workers[it.id] > 0:
				return {"none": true}
			return {"label": "Rebuild barricade", "cost": 0, "hold": true, "none": false}
		"power":
			if Game.power_on:
				return {"none": true}
			return {"label": "Turn on the power", "cost": 0, "hold": false, "none": false}
		"pap":
			if not Game.power_on:
				return {"label": "Pack-a-Punch  —  needs power", "cost": 0, "hold": false, "none": true}
			if player.current_gun().pap:
				return {"label": "Pack-a-Punch  —  already upgraded", "cost": 0, "hold": false, "none": true}
			return {"label": "Pack-a-Punch  —  %d" % it.cost, "cost": it.cost, "hold": false, "none": false}
		"box":
			var box_state: String = box.state()
			if box_state == "offering":
				var offered: String = box.gun()
				return {"label": "Take the %s" % Weapons.TABLE[offered].name, "cost": 0, "hold": false, "none": false}
			if box_state == "spinning":
				return {"label": "...", "cost": 0, "hold": false, "none": true}
			return {"label": "Mystery Box  —  %d" % it.cost, "cost": it.cost, "hold": false, "none": false}
	return {"none": true}


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
	var here := player.grid_pos()
	var best := -1
	var best_d := 1e9
	var best_state := {}
	for i in _interactables.size():
		var it: Dictionary = _interactables[i]
		var d: float = here.distance_to(it.pos)
		if d > it.radius:
			continue
		var st := _state_of(it)
		# Skip anything with nothing to offer, so a satisfied object cannot beat
		# a live one on distance and eat the interact key.
		if st.get("none", true):
			continue
		if d < best_d:
			best_d = d
			best = i
			best_state = st

	if best != _current:
		_hold_t = 0.0
	_current = best

	if best < 0:
		hud.set_prompt("")
		hud.set_hold(0.0)
		return

	var it: Dictionary = _interactables[best]
	var affordable: bool = Game.points >= int(best_state.get("cost", 0))
	var verb := "Hold F" if best_state.get("hold", false) else "[F]"
	hud.set_prompt("%s  %s" % [verb, best_state.label], affordable)

	if best_state.get("hold", false):
		if Input.is_action_pressed("interact"):
			_hold_t += dt
			if _hold_t >= REBUILD_PER_BOARD:
				_hold_t = 0.0
				_rebuild_board(it)
		else:
			_hold_t = 0.0
		hud.set_hold(_hold_t / REBUILD_PER_BOARD)
		return

	hud.set_hold(0.0)
	if Input.is_action_just_pressed("interact"):
		_do_interact(it, best_state)


func _rebuild_board(it: Dictionary) -> void:
	var wi: int = it.id
	if map.window_boards[wi] >= 6:
		return
	world.set_window_boards(wi, map.window_boards[wi] + 1)
	Game.add_points(Game.PTS_REBUILD)
	Sfx.play_at("board", Vector3(it.pos.x, 1.0, it.pos.y), -6.0)


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
				_interactables.erase(it)
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
				Sfx.play("buy")
			else:
				_deny()
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
			Sfx.play("buy")
		"pap":
			var gun := player.current_gun()
			if Game.spend(cost):
				player.give_gun(gun.key, true)
				Game.toast.emit(Weapons.PAP_NAMES.get(gun.key, "Upgraded"))
				Sfx.play("buy")
			else:
				_deny()
		"box":
			if not box.use():
				_deny()


func _deny() -> void:
	Sfx.play("deny")
	hud.flash_deny()
