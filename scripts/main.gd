extends Node3D

## Ties the port together: builds the level, drives the round loop, owns the
## interactables and the horde. Mirrors sections 11-16 of kriegsnacht.html.

const INTERACT_RADIUS := 2.0
const BOX_COST := 950
const PAP_COST := 5000
const POWER_COST := 0
const BOX_SPIN := 2.9
const BOX_OFFER := 7.0

## Barricade repair: 0.34 s a plank, +10 points each. Six planks is about two
## seconds for sixty points, which is the whole economy of rounds one to three.
const REBUILD_PER_BOARD := 0.34
const WINDOW_RADIUS := 1.7

## Flat chance of a drop on any death, on top of the points threshold.
const DROP_CHANCE := 0.03

var map: MapData
var world: WorldBuilder
## Untyped for the same reason `hud` is: a `Node3D`-typed variable cannot see
## build()/power_on()/env()/materials(), because the script is attached at
## runtime and the compiler only knows the declared base class.
var lighting   # lighting.gd, a Node3D owning the environment and the room lamps
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
var _hold_t := 0.0

var _box_state := "idle"      # idle | spinning | offering
var _box_timer := 0.0
var _box_gun := ""
var _box_node: Sprite3D
var _box_teddy := false
var _perk_nodes := {}
var _gen_node: Sprite3D
var _pap_node: Sprite3D

var _muzzle_light: OmniLight3D
var _muzzle_quad: MeshInstance3D
var _muzzle_mat: StandardMaterial3D
var _muzzle_t := 0.0

## fx.gd, a Node3D that owns blood, surface debris, bullet holes, blood pools and
## tracers. It binds itself to player.impact, player.fired and
## player.surface_impact; nothing here drives it after bind().
var fx: Node3D

## viewmodel.gd, a Node3D that parents itself under the camera in bind() and owns
## everything below it. Untyped for the same reason `fx` and `lighting` are: the
## script is attached at runtime, so bind()/materials()/flash_anchor() resolve
## dynamically rather than off the declared base class.
var viewmodel: Node3D

var _debug := false
var _debug_t := 0.0
var _shot_path := ""
var _shot_frames := -1
var _shot_yaw := 0.0


func _ready() -> void:
	Rng.new_run()
	Game.reset_run()

	map = MapData.new()
	map.build()

	world = WorldBuilder.new()
	world.name = "World"
	add_child(world)
	world.build(map)

	flow = FlowField.new(map)

	# Built before anything is drawn, deliberately: the Environment decides which
	# specialisation of post.glsl gets compiled, and on web that compile has to
	# land behind the title screen with the warm-up pass or it lands mid-frame.
	lighting = LIGHTING_SCRIPT.new()
	lighting.name = "Lighting"
	add_child(lighting)
	lighting.build()

	player = Player.new()
	player.name = "Player"
	add_child(player)
	player.global_position = Vector3(MapData.SPAWN_TILE.x + 0.5, 0.0, MapData.SPAWN_TILE.y + 0.5)
	player.world = self
	player.died.connect(_on_player_died)
	player.fired.connect(_on_player_fired)

	_setup_muzzle()

	# bind() parents it under the camera itself — the only correct parent — and
	# builds every weapon's mesh before it enters the tree, including the ones the
	# player will never pick up, so a SurfaceTool.commit() never lands on the frame
	# the mystery box hands over a Thundergun.
	viewmodel = VIEWMODEL_SCRIPT.new()
	viewmodel.name = "Viewmodel"
	viewmodel.bind(player)

	fx = FX_SCRIPT.new()
	fx.name = "Fx"
	add_child(fx)
	fx.bind(player, map)

	hud = preload("res://scripts/ui/hud.gd").new()
	add_child(hud)
	hud.bind(player, self)

	_build_interactables()

	# Runs behind the title screen, which is the only free moment there is.
	var warm: Node3D = WARMUP_SCRIPT.new()
	add_child(warm)
	# The eyes are the one material no scene node owns until the first zombie
	# spawns, so nothing else can hand it to the warm-up. Calling the accessor
	# here also builds the seven eye meshes up front, off the round-one clock.
	# rim_materials() is the same bargain for the silhouette shader, and it loads
	# all seventeen sprite strips on the way past — so the first spawn of a
	# palette is not also that palette's first texture upload.
	var extra: Array = [_muzzle_mat, Zombie.eye_material()]
	extra.append_array(Zombie.rim_materials())
	extra.append_array(fx.materials())
	extra.append_array(viewmodel.materials())
	# The eight lamp fixtures. Additive, billboarded, unshaded and textured — a
	# variant nothing else in the level draws with, and one of them is on screen
	# on frame one, so it has to be compiled before frame one.
	extra.append_array(lighting.materials())
	# M-WARM is a *difference*: what this pass is worth is what a cold load costs
	# without it, so there has to be a way to turn it off from outside. Mirrors
	# quality_governor's switch exactly — `--no-warmup` natively, `?warm=off` on
	# web — because a second convention for the same kind of flag is a second thing
	# to remember. Only tools/perf_native.ps1 and the perf export ever pass it;
	# `--verify` never does, so the assertion that every material is reachable from
	# this pass still runs against the real pass.
	if not _warmup_disabled():
		warm.warm(player.camera(), world.materials(), extra)
		# Neither the particle process shaders nor the MultiMesh (instanced) draw
		# variants are reachable from that pass at all — see fx.warm().
		fx.warm()

	# Everything above this line is why the governor exists: on a bad machine the
	# frame cost of all of it lands on someone with no settings menu to turn it
	# down and no way to tell us it went badly.
	var quality: Node = QUALITY_SCRIPT.new()
	quality.name = "QualityGovernor"
	add_child(quality)

	Game.set_state(Game.STATE_TITLE)

	# Headless assertion run. Exits non-zero on failure so it can gate a build.
	if "--verify" in OS.get_cmdline_args():
		_run_verify.call_deferred()
		return

	# Lets a headless soak test skip the title screen.
	if "--autostart" in OS.get_cmdline_args():
		_debug = true
		start_game.call_deferred()

	# Visual smoke test: `--shot <file.png> [yaw_deg]` starts the game, waits for
	# the world to settle, writes one frame to disk and quits. Culling, winding,
	# lighting and glow are all things that can only be checked by looking, and
	# this is the only way to look without a human at the keyboard.
	var args := OS.get_cmdline_args()
	if "--shot" in args:
		var i := args.find("--shot")
		_shot_path = args[i + 1] if i + 1 < args.size() else "shot.png"
		if i + 2 < args.size() and args[i + 2].is_valid_float():
			_shot_yaw = deg_to_rad(args[i + 2].to_float())
		_shot_frames = 60
		start_game.call_deferred()



## One persistent light and one persistent quad, toggled by a timer. Allocating
## a flash per shot would mean fifteen node allocations a second at 880 RPM.
func _setup_muzzle() -> void:
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.light_color = Color(1.0, 0.84, 0.51)
	_muzzle_light.light_energy = 4.0
	_muzzle_light.omni_range = 2.6
	# Shadowless keeps it free: OMNI_LIGHT_COUNT is a uniform, not a shader
	# define, so toggling this cannot trigger a mid-fight shader recompile.
	_muzzle_light.shadow_enabled = false
	_muzzle_light.visible = false
	add_child(_muzzle_light)

	_muzzle_mat = StandardMaterial3D.new()
	_muzzle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_muzzle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_muzzle_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_muzzle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_muzzle_mat.albedo_color = Color(1.0, 0.86, 0.55)
	_muzzle_mat.disable_receive_shadows = true

	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	_muzzle_quad = MeshInstance3D.new()
	_muzzle_quad.mesh = quad
	_muzzle_quad.material_override = _muzzle_mat
	_muzzle_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle_quad.visible = false
	add_child(_muzzle_quad)


const MUZZLE_COLOR := {
	"raygun": Color(0.63, 1.0, 0.35),
	"thundergun": Color(0.59, 0.92, 1.0),
}


func _on_player_fired(at: Vector3) -> void:
	var key: String = player.current_gun().key
	var col: Color = MUZZLE_COLOR.get(key, Color(1.0, 0.84, 0.51))
	# The weapon is drawn through a narrowed projection (viewmodel.gd), so a flash
	# placed on the same ray as the barrel does NOT land on the barrel on screen —
	# the viewmodel's screen offset is the world's scaled by
	# tan(74/2)/tan(55/2) = 1.4476. And a 0.34 m quad at the barrel's actual 0.18 m
	# would subtend more than the whole frame. flash_anchor() is the point that
	# satisfies both: same screen position, survivable distance.
	var flash_at: Vector3 = viewmodel.flash_anchor(
		at.distance_to(player.camera().global_position))
	_muzzle_light.light_color = col
	_muzzle_light.omni_range = 5.7 if key == "thundergun" else 2.6
	_muzzle_light.global_position = flash_at
	_muzzle_light.visible = true
	_muzzle_mat.albedo_color = col
	_muzzle_quad.global_position = flash_at
	_muzzle_quad.rotation.z = Rng.randf(Rng.VISUAL) * TAU
	_muzzle_quad.visible = true
	_muzzle_t = 0.05



# --- rounds ------------------------------------------------------------------

func start_game() -> void:
	Game.set_state(Game.STATE_PLAY)
	Player.set_capture(true)
	_intermission = true
	_round_timer = Game.FIRST_ROUND_DELAY
	Game.round_no = 0


func _process(dt: float) -> void:
	if _shot_frames >= 0:
		_tick_shot()

	if _muzzle_t > 0.0:
		_muzzle_t -= dt
		if _muzzle_t <= 0.0:
			_muzzle_light.visible = false
			_muzzle_quad.visible = false

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
		if _to_spawn > 0 and _spawn_timer <= 0.0 and _alive.size() < Game.max_alive():
			_spawn_one()
			_spawn_timer = Game.spawn_interval()
		if _to_spawn <= 0 and _alive.is_empty():
			_end_round()

	_update_box(dt)
	_update_powerups(dt)
	_update_interact(dt)

	if _debug:
		_debug_t += dt
		if _debug_t >= 2.0:
			_debug_t = 0.0
			# The state histogram is here because the barricade added two states a
			# zombie can sit in indefinitely, and a soak that only prints `alive`
			# cannot tell "six of them are working windows" from "six of them are
			# stuck". Boards are printed for the same reason: they are the clock.
			var by_state := {}
			for z in _alive:
				var n: String = Zombie.State.keys()[z.state]
				by_state[n] = int(by_state.get(n, 0)) + 1
			var boards := 0
			for wi in MapData.WINDOWS.size():
				boards += map.window_boards[wi]
			print("[soak] round=%d alive=%d %s queued=%d kills=%d pts=%d hp=%.0f boards=%d live_windows=%d stam=%.2f" % [
				Game.round_no, _alive.size(), by_state, _to_spawn, Game.kills,
				Game.points, player.hp, boards, map.live_windows().size(),
				player.stamina()])


func _begin_round() -> void:
	_intermission = false
	Game.round_no += 1
	_to_spawn = Game.zombie_count()
	# html:2863 is `G.spawnTimer = 0.4`, and the port had 0.0 — so the first
	# zombie of a round arrived on the frame the round began. Now it is the length
	# of the beat of silence, which is the ancestor's intent (a pause before the
	# wave) carried to the ceremony's own clock: nothing walks in over the toll.
	_spawn_timer = Sfx.ROUND_SILENCE
	# The card first, the toll second. Sfx cuts the ambient bed on this call, holds
	# ROUND_SILENCE seconds of nothing and only then plays the sting, so the
	# numeral is already on screen through the beat and the most recognisable cue
	# in the game lands into silence instead of on top of the last kill.
	Game.round_changed.emit(Game.round_no, Game.is_dog_round())
	Sfx.round_ceremony(Game.round_no, Game.is_dog_round())


func _end_round() -> void:
	# A dog round having finished, roll when the next one lands. Their arrival is
	# no longer a fixed multiple the player can count on.
	if Game.is_dog_round():
		_grant_max_ammo()
		Game.advance_dog_round()
	_intermission = true
	_round_timer = Game.INTERMISSION
	# Between rounds each barricade has a chance to regain a board. Kept low so
	# that repairing them yourself still matters.
	#
	# The ancestor's figure was 0.5 (html:2888) and the port already halved it to
	# 0.28, but both were calibrated against a placeholder in which a window lost
	# exactly one board per zombie routed through it. It loses all six now, inside
	# the first ten seconds of a round, to two bodies working it — so the demand
	# side has saturated and this is the only thing besides the player and the
	# Carpenter power-up that ever puts a plank back. 0.12 is about one board per
	# window per eight rounds: slow enough that a run which never rebuilds arrives
	# at round ten with the map genuinely open, fast enough that a window stripped
	# in round three is not silently free for the rest of a two-hour run.
	for wi in MapData.WINDOWS.size():
		if Rng.randf(Rng.ROUNDS) < 0.12 and map.window_boards[wi] < 6:
			world.set_window_boards(wi, map.window_boards[wi] + 1)


## The last hound of a dog round always leaves Max Ammo, and the per-round drop
## cap is cleared first so the guarantee cannot be swallowed by it.
func _grant_max_ammo() -> void:
	Game.drop_count = 0
	player.refill_ammo()
	Game.toast.emit("MAX AMMO")
	Sfx.play("powerup", -4.0)


## Windows nearer the player are likelier to be used, so opening more of the map
## does not reduce the pressure on you. A uniform pick made late rounds calmer
## the more doors you bought — exactly backwards.
func _pick_window(live: Array[int]) -> int:
	var here := player.grid_pos()
	var best: int = live[0]
	var best_w := -1.0
	for wi in live:
		var w: Dictionary = MapData.WINDOWS[wi]
		var d := here.distance_to(Vector2(w.ix + 0.5, w.iy + 0.5))
		var weight := (1.0 / (1.0 + d * 0.14)) * Rng.randf_range(Rng.SPAWN, 0.4, 1.6)
		# A window already being worked is a window whose six planks are coming off
		# in half the time, and a third body there stands inside the other two.
		# Divided rather than rejected so the pick can never run out of candidates,
		# and the SPAWN draw above happens either way — a seeded run stays
		# bit-identical.
		weight /= 1.0 + float(map.window_workers[wi])
		if weight > best_w:
			best_w = weight
			best = wi
	return best


func _spawn_one() -> void:
	var live := map.live_windows()
	if live.is_empty():
		return
	var wi := _pick_window(live)
	var pos := map.window_stand_pos(wi)

	var kind := "zombie"
	if Game.is_dog_round():
		kind = "hound"
	elif Rng.randf(Rng.SPAWN) < Game.crawler_chance():
		kind = "crawler"

	var z := Zombie.create(kind, Rng.stream(Rng.SPAWN).randi() % 3, Game.round_no,
		Game.insta_kill > 0.0)
	z.flow = flow
	z.target = player
	z.add_to_group("zombies")
	add_child(z)
	z.global_position = Vector3(pos.x, 0.0, pos.y)
	z.set_entering(wi)
	z.died.connect(_on_zombie_died)
	_alive.append(z)
	_to_spawn -= 1
	# The board that used to come off here comes off in `Zombie._tick_boards` now,
	# one plank at a time, with a body standing outside pulling it. `set_entering`
	# above has already put this one in the barricade's exterior pocket and started
	# its first plank timer — or, at a window somebody already stripped, started the
	# vault instead.


func _on_zombie_died(z: Zombie, was_headshot: bool, by_melee: bool) -> void:
	_alive.erase(z)
	Game.kills += 1
	if was_headshot:
		Game.headshots += 1

	if Game.insta_kill > 0.0:
		# Insta-Kill pays a flat rate rather than the full headshot/melee bonus,
		# so it is a survival tool rather than pure economic upside.
		Game.add_points(Game.PTS_INSTAKILL)
	else:
		var pts := Game.PTS_HEADSHOT if was_headshot else Game.PTS_KILL
		if by_melee:
			pts += Game.PTS_MELEE_BONUS
		Game.add_points(pts)

	var earned := Game.check_points_drop()
	var lucky := Rng.randf(Rng.DROPS) < DROP_CHANCE
	if (earned or lucky) and Game.drop_count < 4:
		Game.drop_count += 1
		_spawn_powerup(z.global_position)


func _on_player_died() -> void:
	Game.record_run()
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
	var kind: String = Rng.pick(Rng.DROPS, POWER_POOL)
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
			# One scaled cue rather than up to 24 phase-coherent copies of the
			# same buffer in a single frame, which summed about 21 dB hot.
			Sfx.play("death", -2.0, 0.72)
			for z in _alive.duplicate():
				if is_instance_valid(z):
					z.take_damage(1e9, 0.0)
			Game.toast.emit("NUKE")
		"carp":
			Game.add_points(Game.PTS_CARPENTER)
			for wi in MapData.WINDOWS.size():
				world.set_window_boards(wi, 6)
			Sfx.play("board", -6.0)
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
		# `wb` is a Variant out of an untyped Array, so every value is pulled out
		# with an explicit type before it reaches the typed signature.
		var wb_gun: String = wb.gun
		var wb_tile: Array = wb.tile
		var wb_face: Array = wb.face
		_spawn_chalk(wb_gun, wb_tile, wb_face)

	_interactables.append({
		"kind": "bowie", "pos": Vector2(MapData.BOWIE.tile[0] + 0.5 + MapData.BOWIE.face[0] * 0.6,
			MapData.BOWIE.tile[1] + 0.5 + MapData.BOWIE.face[1] * 0.6),
		"cost": MapData.BOWIE.cost, "label": "Bowie Knife", "radius": INTERACT_RADIUS,
	})
	var bowie_tile: Array = MapData.BOWIE.tile
	var bowie_face: Array = MapData.BOWIE.face
	_spawn_chalk("bowie", bowie_tile, bowie_face)

	for ps in MapData.PERKSPOTS:
		_interactables.append({
			"kind": "perk", "perk": ps.k, "pos": Vector2(ps.x, ps.y),
			"cost": Game.REVIVE_COST if ps.k == "revive" else Weapons.PERKDEF[ps.k].cost,
			"label": Weapons.PERKDEF[ps.k].name, "radius": INTERACT_RADIUS,
		})
		_spawn_perk_marker(ps)

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
	_gen_node = _prop_sprite("gen_off", PROP_PX, MapData.GENSPOT, "Generator")
	_interactables.append({
		"kind": "pap", "pos": MapData.PAPSPOT, "cost": PAP_COST,
		"label": "Pack-a-Punch", "radius": 2.2,
	})
	# The machine had no art at all until now, and the reason turns out to be an
	# extraction bug rather than an art decision: makePaP is at html:1986-2012,
	# seven hundred lines outside the range the original export pass replayed.
	_pap_node = _prop_sprite("pap_off", PAP_PX, MapData.PAPSPOT, "PackAPunch")

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
## 1.7 m of drawn machine over 64 source px — html:2092. The generic PROP_PX
## would render it 1.60 m, which is the perk machines' scale, not this one's.
const PAP_PX := 0.0265625


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


## Chalk wall-buy plaques, drawn from each weapon's own GUNART parts.
##
## The plaque hangs on the wall face, not at the interact point: html:2035 puts
## both at tile centre + face * 0.52, which is 0.02 m proud of the wall plane —
## enough to clear it without reading as a floating panel. Height and lift are the
## ancestor's, from html:2105 `add(CHALK[b.gun], b.x, b.y, 0.72, 1.30)`: 0.72 m of
## plaque with its bottom edge 1.30 m off the floor, under a 2.8 m ceiling.
const CHALK_PX := 0.018         # 0.72 m over 40 source px
const CHALK_LIFT := 1.30        # floor to the plaque's bottom edge
const CHALK_PROUD := 0.52       # tile centre to the drawing plane


func _spawn_chalk(gun: String, tile: Array, face: Array) -> void:
	var s := Sprite3D.new()
	s.name = "Chalk_" + gun
	s.texture = load(PROP_DIR + "chalk_" + gun + ".png")
	s.pixel_size = CHALK_PX
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = true
	# Not a billboard: it is painted on a specific wall, and turning to face the
	# player would break the illusion the moment you walked past it.
	s.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# The plaque's own ground is rgba(12,14,11,.74) across all 52x40 px
	# (html:1247), so every pixel clears a 0.35 scissor and ALPHA_CUT_DISCARD would
	# render it as an opaque slab. Blend it, so the wall reads through at 26% the
	# way the raycaster composited it.
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	var px: float = float(tile[0]) + 0.5 + float(face[0]) * CHALK_PROUD
	var pz: float = float(tile[1]) + 0.5 + float(face[1]) * CHALK_PROUD
	s.position = Vector3(px, CHALK_LIFT + s.texture.get_height() * CHALK_PX * 0.5, pz)
	# A Sprite3D's quad normal is local +Z, and rotating by this angle sends +Z to
	# (face[0], 0, face[1]) — out of the wall, into the room.
	s.rotation.y = atan2(float(face[0]), float(face[1]))
	add_child(s)


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
	# The machine is gated on power in the ancestor too — html:2092 tests G.power.
	if _pap_node and is_instance_valid(_pap_node):
		_pap_node.texture = load(PROP_DIR + "pap_on.png")


func _place_box(spot: int) -> void:
	if _box_node and is_instance_valid(_box_node):
		_box_node.queue_free()
	_box_node = _prop_sprite("box_closed", PROP_PX, MapData.BOXSPOTS[spot], "MysteryBox")


func _set_box_art(which: String) -> void:
	if _box_node and is_instance_valid(_box_node):
		_box_node.texture = load(PROP_DIR + "box_" + which + ".png")


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
			if _box_state == "offering":
				return {"label": "Take the %s" % Weapons.TABLE[_box_gun].name, "cost": 0, "hold": false, "none": false}
			if _box_state == "spinning":
				return {"label": "...", "cost": 0, "hold": false, "none": true}
			return {"label": "Mystery Box  —  %d" % it.cost, "cost": it.cost, "hold": false, "none": false}
	return {"none": true}


func _pap_of(key: String) -> bool:
	for g in player.guns:
		if g.key == key:
			return g.pap
	return false


func _update_interact(dt: float) -> void:
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

	if best != _current_interact:
		_hold_t = 0.0
	_current_interact = best

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


func _owns(key: String) -> bool:
	for g in player.guns:
		if g.key == key:
			return true
	return false


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
			_light_perks()
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
			_use_box(it)


func _deny() -> void:
	Sfx.play("deny")
	hud.flash_deny()


func _use_box(it: Dictionary) -> void:
	if _box_state == "offering":
		player.give_gun(_box_gun, false)
		_box_state = "idle"
		_set_box_art("closed")
		if _box_teddy:
			_relocate_box(it)
		return
	if _box_state != "idle":
		return
	if not Game.spend(BOX_COST):
		_deny()
		return
	Game.box_uses += 1
	_box_state = "spinning"
	_box_timer = BOX_SPIN
	_set_box_art("open")
	_box_gun = Weapons.roll_box(Rng.stream(Rng.BOX))
	# The teddy bear starts becoming likely after four pulls.
	_box_teddy = Game.box_uses > 3 and Rng.randf(Rng.BOX) < 0.16 * (Game.box_uses - 3)
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
		next = Rng.stream(Rng.BOX).randi() % MapData.BOXSPOTS.size()
	Game.box_spot = next
	it.pos = MapData.BOXSPOTS[next]
	_place_box(next)
	Game.toast.emit("THE BOX HAS MOVED")


## preload rather than the global class name: a freshly added script is not in
## the class registry until the editor rescans, and a headless run has no editor.
const VERIFY_SCRIPT := preload("res://scripts/dev/verify.gd")
const WARMUP_SCRIPT := preload("res://scripts/world/shader_warmup.gd")
const QUALITY_SCRIPT := preload("res://scripts/world/quality_governor.gd")
const LIGHTING_SCRIPT := preload("res://scripts/world/lighting.gd")
const FX_SCRIPT := preload("res://scripts/world/fx.gd")
const VIEWMODEL_SCRIPT := preload("res://scripts/entities/viewmodel.gd")


## The M-WARM control, recorded in notes/perf/README.md. `--no-warmup` natively,
## `?warm=off` on web — the same shape as quality_governor's own switch,
## deliberately, so there is one convention for "turn a build-time decision off for
## one measurement" rather than two.
##
## The ShaderWarmup node is still created and still frees itself after three
## frames. Leaving it is the point: `warm._spawned` being empty is exactly what
## "warm-up disabled" should look like to anything inspecting it.
func _warmup_disabled() -> bool:
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("location.search", true)
		if q == null:
			return false
		return "warm=off" in str(q)
	return "--no-warmup" in OS.get_cmdline_args()


func _run_verify() -> void:
	Game.set_state(Game.STATE_PLAY)
	var failures: int = VERIFY_SCRIPT.new().run(self)
	print("sfx bake: %d ms" % Sfx.bake_ms())
	get_tree().quit(1 if failures > 0 else 0)


func _tick_shot() -> void:
	if player and is_instance_valid(player):
		player.rotation.y = _shot_yaw
	_shot_frames -= 1
	if _shot_frames > 0:
		return
	_shot_frames = -1
	# Grab after the frame has actually been drawn, or the capture races the
	# renderer and comes back empty.
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	print("[shot] wrote %s (%dx%d)" % [_shot_path, img.get_width(), img.get_height()])
	get_tree().quit()


func restart() -> void:
	get_tree().reload_current_scene()
