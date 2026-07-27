extends Node3D

## Ties the port together: builds the level, drives the round loop, owns the
## interactables and the horde. Mirrors sections 11-16 of kriegsnacht.html.

const INTERACT_RADIUS := 2.0
const BOX_COST := 950
const PAP_COST := 5000
const POWER_COST := 0
const BOX_SPIN := 2.9
const BOX_OFFER := 7.0

var map: MapData
var world: WorldBuilder
var player: Player
var flow: FlowField
var hud   # hud.gd, a CanvasLayer with bind()/set_prompt()

var _round_timer := 0.0
var _spawn_timer := 0.0
var _to_spawn := 0
var _alive: Array[Zombie] = []
var _intermission := true
var _interactables: Array = []
var _current_interact := -1
var _powerups: Array = []

var _box_state := "idle"      # idle | spinning | offering
var _box_timer := 0.0
var _box_gun := ""
var _box_node: Sprite3D
var _box_teddy := false
var _perk_nodes := {}
var _gen_node: Sprite3D

var _rng := RandomNumberGenerator.new()
var _debug := false
var _debug_t := 0.0


func _ready() -> void:
	_rng.randomize()
	Game.reset()

	map = MapData.new()
	map.build()

	world = WorldBuilder.new()
	world.name = "World"
	add_child(world)
	world.build(map)

	flow = FlowField.new(map)

	_setup_environment()

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(MapData.SPAWN_TILE.x + 0.5, 0.0, MapData.SPAWN_TILE.y + 0.5)
	player.world = self
	player.died.connect(_on_player_died)

	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	hud.bind(player, self)

	_build_interactables()

	Game.set_state(Game.STATE_TITLE)

	# Lets a headless soak test skip the title screen.
	if "--autostart" in OS.get_cmdline_args():
		_debug = true
		start_game.call_deferred()


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.024, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.32, 0.36)
	env.ambient_light_energy = 0.30
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.07, 0.075)
	env.fog_density = 0.055
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.88
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Sodium-lamp fill so rooms are not pitch black outside the torch cone.
	for r in MapData.ROOMS:
		var l := OmniLight3D.new()
		l.position = Vector3((r.x0 + r.x1) * 0.5 + 0.5, MapData.WALL_H - 0.45, (r.y0 + r.y1) * 0.5 + 0.5)
		l.light_color = Color(0.98, 0.72, 0.34)
		l.light_energy = 1.5
		l.omni_range = maxf(r.x1 - r.x0, r.y1 - r.y0) + 6.0
		l.shadow_enabled = false
		add_child(l)


# --- rounds ------------------------------------------------------------------

func start_game() -> void:
	Game.set_state(Game.STATE_PLAY)
	Player.set_capture(true)
	_intermission = true
	_round_timer = Game.FIRST_ROUND_DELAY
	Game.round_no = 0


func _process(dt: float) -> void:
	if Game.state != Game.STATE_PLAY:
		return

	Game.tick_timers(dt)
	flow.update(player.grid_pos())

	# Hand every zombie the current neighbour list for separation.
	var live: Array[Zombie] = []
	for z in _alive:
		if is_instance_valid(z):
			live.append(z)
	_alive = live
	for z in _alive:
		z.neighbours = _alive

	if _intermission:
		_round_timer -= dt
		if _round_timer <= 0.0:
			_begin_round()
	else:
		_spawn_timer -= dt
		if _to_spawn > 0 and _spawn_timer <= 0.0 and _alive.size() < Game.MAX_ALIVE:
			_spawn_one()
			_spawn_timer = Game.spawn_interval()
		if _to_spawn <= 0 and _alive.is_empty():
			_end_round()

	_update_box(dt)
	_update_powerups(dt)
	_update_interact()

	if _debug:
		_debug_t += dt
		if _debug_t >= 2.0:
			_debug_t = 0.0
			print("[soak] round=%d alive=%d queued=%d kills=%d pts=%d hp=%.0f live_windows=%d" % [
				Game.round_no, _alive.size(), _to_spawn, Game.kills, Game.points,
				player.hp, map.live_windows().size()])


func _begin_round() -> void:
	_intermission = false
	Game.round_no += 1
	_to_spawn = Game.zombie_count()
	_spawn_timer = 0.0
	Sfx.play("round", -6.0)
	Game.round_changed.emit(Game.round_no, Game.is_dog_round())
	Game.drop_count = 0


func _end_round() -> void:
	_intermission = true
	_round_timer = Game.INTERMISSION
	# Between rounds each barricade has a chance to regain a board.
	for wi in MapData.WINDOWS.size():
		if _rng.randf() < 0.5 and map.window_boards[wi] < 6:
			world.set_window_boards(wi, map.window_boards[wi] + 1)


func _spawn_one() -> void:
	var live := map.live_windows()
	if live.is_empty():
		return
	var wi: int = live[_rng.randi() % live.size()]
	var pos := map.window_stand_pos(wi)

	var kind := "zombie"
	if Game.is_dog_round():
		kind = "hound"
	elif _rng.randf() < Game.crawler_chance():
		kind = "crawler"

	var z := Zombie.create(kind, _rng.randi() % 3, Game.round_no, Game.insta_kill > 0.0)
	z.flow = flow
	z.target = player
	z.add_to_group("zombies")
	add_child(z)
	z.global_position = Vector3(pos.x, 0.0, pos.y)
	z.set_entering(wi)
	z.died.connect(_on_zombie_died)
	_alive.append(z)
	_to_spawn -= 1

	# Working the boards is what lets them in.
	if map.window_boards[wi] > 0:
		world.set_window_boards(wi, map.window_boards[wi] - 1)


func _on_zombie_died(z: Zombie, was_headshot: bool, by_melee: bool) -> void:
	_alive.erase(z)
	Game.kills += 1
	if was_headshot:
		Game.headshots += 1
	var pts := Game.PTS_HEADSHOT if was_headshot else Game.PTS_KILL
	if by_melee:
		pts += Game.PTS_MELEE_BONUS
	Game.add_points(pts)

	Game.drop_tick += 1
	if Game.drop_tick >= Game.next_drop_at and Game.drop_count < 4:
		Game.drop_tick = 0
		Game.next_drop_at = 16 + _rng.randi() % 14
		Game.drop_count += 1
		_spawn_powerup(z.global_position)


func _on_player_died() -> void:
	Game.set_state(Game.STATE_OVER)
	Player.set_capture(false)


# --- power-ups ---------------------------------------------------------------

const POWER_POOL := ["ammo", "ammo", "insta", "nuke", "points", "points", "carp"]
const POWER_COLOR := {
	"ammo": Color(0.95, 0.82, 0.30), "insta": Color(0.90, 0.20, 0.18),
	"nuke": Color(0.45, 0.80, 0.95), "points": Color(0.55, 0.85, 0.35),
	"carp": Color(0.80, 0.55, 0.25),
}


func _spawn_powerup(at: Vector3) -> void:
	var kind: String = POWER_POOL[_rng.randi() % POWER_POOL.size()]
	var node := _prop_sprite("pu_" + kind, POWERUP_PX,
		Vector2(at.x, at.z), "Powerup_" + kind)
	# Drops hover and glow so they read across a dark room.
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.modulate = POWER_COLOR[kind] * 1.6
	node.position.y = 0.7
	_powerups.append({"node": node, "kind": kind, "life": 26.0, "t": 0.0})


func _update_powerups(dt: float) -> void:
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
			for z in _alive.duplicate():
				if is_instance_valid(z):
					z.take_damage(1e9, 0.0)
			Game.toast.emit("NUKE")
		"carp":
			Game.add_points(Game.PTS_CARPENTER)
			for wi in MapData.WINDOWS.size():
				world.set_window_boards(wi, 6)
			Game.toast.emit("CARPENTER")


# --- interactables -----------------------------------------------------------

func _build_interactables() -> void:
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

	_interactables.append({
		"kind": "bowie", "pos": Vector2(MapData.BOWIE.tile[0] + 0.5 + MapData.BOWIE.face[0] * 0.6,
			MapData.BOWIE.tile[1] + 0.5 + MapData.BOWIE.face[1] * 0.6),
		"cost": MapData.BOWIE.cost, "label": "Bowie Knife", "radius": INTERACT_RADIUS,
	})

	for ps in MapData.PERKSPOTS:
		_interactables.append({
			"kind": "perk", "perk": ps.k, "pos": Vector2(ps.x, ps.y),
			"cost": Weapons.PERKDEF[ps.k].cost,
			"label": Weapons.PERKDEF[ps.k].name, "radius": INTERACT_RADIUS,
		})
		_spawn_perk_marker(ps)

	_interactables.append({
		"kind": "power", "pos": MapData.GENSPOT, "cost": POWER_COST,
		"label": "Turn on the power", "radius": 2.2,
	})
	_gen_node = _prop_sprite("gen_off", PROP_PX, MapData.GENSPOT, "Generator")
	_interactables.append({
		"kind": "pap", "pos": MapData.PAPSPOT, "cost": PAP_COST,
		"label": "Pack-a-Punch", "radius": 2.2,
	})

	Game.box_spot = 0
	_place_box(0)
	_interactables.append({
		"kind": "box", "pos": MapData.BOXSPOTS[0], "cost": BOX_COST,
		"label": "Mystery Box", "radius": 2.2,
	})


## Props reuse the browser build's own art, exported to assets/props/ by
## replaying its canvas drawing code. They are billboards for the same reason
## the zombies are: the original had no 3D geometry for them either.
const PROP_DIR := "res://assets/props/"
const PROP_PX := 0.025          # metres per source pixel
const POWERUP_PX := 0.018


func _prop_sprite(tex: String, px: float, pos: Vector2, sprite_name: String) -> Sprite3D:
	var s := Sprite3D.new()
	s.name = sprite_name
	s.texture = load(PROP_DIR + tex + ".png")
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.alpha_scissor_threshold = 0.35
	# Sprite origin is its centre, so lift it half its own height off the floor.
	s.position = Vector3(pos.x, s.texture.get_height() * px * 0.5, pos.y)
	add_child(s)
	return s


func _spawn_perk_marker(ps: Dictionary) -> void:
	_perk_nodes[ps.k] = _prop_sprite("perk_%s_off" % ps.k, PROP_PX,
		Vector2(ps.x, ps.y), "Perk_" + ps.k)


## The machines only light up once the generator is thrown.
func _light_perks() -> void:
	for k in _perk_nodes:
		var s: Sprite3D = _perk_nodes[k]
		if is_instance_valid(s):
			s.texture = load(PROP_DIR + "perk_%s_on.png" % k)
	if _gen_node and is_instance_valid(_gen_node):
		_gen_node.texture = load(PROP_DIR + "gen_on.png")


func _place_box(spot: int) -> void:
	if _box_node and is_instance_valid(_box_node):
		_box_node.queue_free()
	_box_node = _prop_sprite("box_closed", PROP_PX, MapData.BOXSPOTS[spot], "MysteryBox")


func _set_box_art(which: String) -> void:
	if _box_node and is_instance_valid(_box_node):
		_box_node.texture = load(PROP_DIR + "box_" + which + ".png")


func _update_interact() -> void:
	var here := player.grid_pos()
	var best := -1
	var best_d := 1e9
	for i in _interactables.size():
		var it: Dictionary = _interactables[i]
		var d: float = here.distance_to(it.pos)
		if d > it.radius:
			continue
		if d < best_d:
			best_d = d
			best = i
	_current_interact = best

	if best < 0:
		hud.set_prompt("")
		return

	var it: Dictionary = _interactables[best]
	hud.set_prompt(_prompt_for(it))

	if Input.is_action_just_pressed("interact"):
		_do_interact(it)


func _prompt_for(it: Dictionary) -> String:
	match it.kind:
		"door":
			return "[F] %s  —  %d" % [it.label, it.cost]
		"wallbuy":
			var owned := _owns(it.gun)
			if owned:
				return "[F] %s ammo  —  %d" % [it.label, it.cost / 2]
			return "[F] Buy %s  —  %d" % [it.label, it.cost]
		"bowie":
			if player.has_bowie:
				return ""
			return "[F] %s  —  %d" % [it.label, it.cost]
		"perk":
			if Game.has_perk(it.perk):
				return ""
			if not Game.power_on:
				return "%s  —  needs power" % it.label
			return "[F] %s  —  %d" % [it.label, it.cost]
		"power":
			if Game.power_on:
				return ""
			return "[F] Turn on the power"
		"pap":
			if not Game.power_on:
				return "Pack-a-Punch  —  needs power"
			return "[F] Pack-a-Punch  —  %d" % it.cost
		"box":
			if _box_state == "offering":
				return "[F] Take the %s" % Weapons.TABLE[_box_gun].name
			if _box_state == "spinning":
				return "..."
			return "[F] Mystery Box  —  %d" % it.cost
	return ""


func _owns(key: String) -> bool:
	for g in player.guns:
		if g.key == key:
			return true
	return false


func _do_interact(it: Dictionary) -> void:
	match it.kind:
		"door":
			if Game.spend(it.cost):
				world.open_door(it.id)
				_interactables.erase(it)
				Sfx.play("buy")
			else:
				Sfx.play("deny")
		"wallbuy":
			var owned := _owns(it.gun)
			var cost: int = it.cost / 2 if owned else it.cost
			if Game.spend(cost):
				if owned:
					player.refill_ammo()
				else:
					player.give_gun(it.gun, false)
				Sfx.play("buy")
			else:
				Sfx.play("deny")
		"bowie":
			if not player.has_bowie and Game.spend(it.cost):
				player.has_bowie = true
				Sfx.play("buy")
			else:
				Sfx.play("deny")
		"perk":
			if Game.has_perk(it.perk) or not Game.power_on:
				return
			if Game.spend(it.cost):
				Game.perks[it.perk] = true
				if it.perk == "jug":
					player.hp = Game.max_health()
					player.health_changed.emit(player.hp, Game.max_health())
				Game.toast.emit(Weapons.PERKDEF[it.perk].name)
				Sfx.play("buy")
			else:
				Sfx.play("deny")
		"power":
			if not Game.power_on:
				Game.power_on = true
				_light_perks()
				Game.toast.emit("POWER ON")
				Sfx.play("buy")
		"pap":
			if not Game.power_on:
				return
			var gun := player.current_gun()
			if gun.pap:
				Sfx.play("deny")
				return
			if Game.spend(it.cost):
				player.give_gun(gun.key, true)
				Game.toast.emit(Weapons.PAP_NAMES.get(gun.key, "Upgraded"))
				Sfx.play("buy")
			else:
				Sfx.play("deny")
		"box":
			_use_box(it)


func _use_box(it: Dictionary) -> void:
	if _box_state == "offering":
		player.give_gun(_box_gun, false)
		_box_state = "idle"
		if _box_teddy:
			_relocate_box(it)
		return
	if _box_state != "idle":
		return
	if not Game.spend(it.cost):
		Sfx.play("deny")
		return
	Game.box_uses += 1
	_box_state = "spinning"
	_box_timer = BOX_SPIN
	_set_box_art("open")
	_box_gun = Weapons.roll_box(_rng)
	# The teddy bear starts becoming likely after four pulls.
	_box_teddy = Game.box_uses > 3 and _rng.randf() < 0.16 * (Game.box_uses - 3)
	Sfx.play("box")


func _update_box(dt: float) -> void:
	if _box_state == "idle":
		return
	_box_timer -= dt
	if _box_timer <= 0.0:
		if _box_state == "spinning":
			_box_state = "offering"
			_box_timer = BOX_OFFER
			_set_box_art("teddy" if _box_teddy else "open")
		else:
			_box_state = "idle"
			_set_box_art("closed")
			if _box_teddy:
				for i in _interactables.size():
					if _interactables[i].kind == "box":
						_relocate_box(_interactables[i])
						break


func _relocate_box(it: Dictionary) -> void:
	_box_teddy = false
	Game.box_uses = 0
	var next := Game.box_spot
	while next == Game.box_spot:
		next = _rng.randi() % MapData.BOXSPOTS.size()
	Game.box_spot = next
	it.pos = MapData.BOXSPOTS[next]
	_place_box(next)
	Game.toast.emit("THE BOX HAS MOVED")


func restart() -> void:
	get_tree().reload_current_scene()
