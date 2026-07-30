extends Node3D

## Composition root. Builds the level, constructs the systems, wires them to each
## other, drives them in a fixed order and handles the command-line flags. It owns
## no rule of the game itself.
##
## What used to be here — the round loop, the power-ups, every interactable, the
## mystery box, the muzzle flash and the prop sprites — is in scripts/systems/,
## one file per concern. Mirrors sections 11-16 of kriegsnacht.html between them.

var map: MapData
var world: WorldBuilder
## Untyped for the same reason `hud` is: a `Node3D`-typed variable cannot see
## build()/power_on()/env()/materials(), because the script is attached at
## runtime and the compiler only knows the declared base class.
var lighting   # lighting.gd, a Node3D owning the environment and the room lamps
var player: Player
var flow: FlowField
var hud   # hud.gd, a CanvasLayer with bind()/set_prompt()

## fx.gd, a Node3D that owns blood, surface debris, bullet holes, blood pools and
## tracers. It binds itself to player.impact, player.fired and
## player.surface_impact; nothing here drives it after bind().
var fx: Node3D

## viewmodel.gd, a Node3D that parents itself under the camera in bind() and owns
## everything below it. Untyped for the same reason `fx` and `lighting` are: the
## script is attached at runtime, so bind()/materials()/flash_anchor() resolve
## dynamically rather than off the declared base class.
var viewmodel: Node3D

## The five systems, under the names the debug console and the assertion suite
## reach them by. All untyped for the reason above: their scripts are attached at
## runtime, so a typed handle could not call tick() or force_round().
var rounds      # round_director.gd
var powerups    # powerup_manager.gd
var interact    # interaction_system.gd
var box         # mystery_box.gd
var atmos       # atmosphere.gd
var traps       # traps.gd

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

	_build_systems()

	# Runs behind the title screen, which is the only free moment there is.
	var warm: Node3D = WARMUP_SCRIPT.new()
	add_child(warm)
	# The eyes are the one material no scene node owns until the first zombie
	# spawns, so nothing else can hand it to the warm-up. Calling the accessor
	# here also builds the seven eye meshes up front, off the round-one clock.
	# rim_materials() is the same bargain for the silhouette shader, and it loads
	# all seventeen sprite strips on the way past — so the first spawn of a
	# palette is not also that palette's first texture upload.
	var extra: Array = [Zombie.eye_material()]
	extra.append_array(Zombie.rim_materials())
	# The muzzle flash's additive billboard, which is Atmosphere's now. Asked for
	# the same way as every other layer's, so main.gd never has to know how many
	# materials any of them own.
	extra.append_array(atmos.materials())
	extra.append_array(fx.materials())
	# The trap posts and the arc sheet. The arc is additive+unshaded, which is a
	# variant only the muzzle flash otherwise draws with, and the first one the
	# player sees is at the far end of a corridor with a horde in it.
	extra.append_array(traps.materials())
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

	# THE MIXER DOES NOT FREEZE WITH THE WORLD. Autoloads hang off the root and
	# inherit PROCESS_MODE_PAUSABLE, and a pausable AudioStreamPlayer fades to
	# silence on NOTIFICATION_PAUSED — so the default would clip the last hurt cue
	# in half at the exact instant the death screen appears, and clip whatever was
	# in the air when the player hit P. The ancestor never stops its WebAudio graph
	# for either (html:3192-3203, :3204-3216); pause and game over there change
	# what is *started*, not what is already ringing. That distinction is already
	# this project's model too — sfx.gd's `_on_state` cuts the ambient bed on pause
	# and brings it back on resume, and its round ceremony sequences off a
	# `process_always` SceneTreeTimer — so nothing about the bed or the ceremony
	# depends on the mixer's own process mode, and one-shots ring out.
	#
	# Set from the composition root because this package does not own sfx.gd, and
	# because "who keeps running while paused" is a composition decision: it is the
	# counterpart of Game.set_state()'s `get_tree().paused`, and the two answers
	# belong where they can be read together.
	Sfx.process_mode = Node.PROCESS_MODE_ALWAYS

	Game.set_state(Game.STATE_TITLE)

	# Headless assertion run. Exits non-zero on failure so it can gate a build.
	if "--verify" in OS.get_cmdline_args():
		_run_verify.call_deferred()
		return

	# Headless balance sim: writes CSV to notes/balance/ and quits. Same shape as
	# --verify because it answers the same kind of question — one a person cannot
	# answer by playing, because playing to round 20 costs twenty minutes an
	# attempt. See notes/balance/README.md for what it can and cannot answer.
	if "--sim" in OS.get_cmdline_args():
		_run_sim.call_deferred()
		return

	# Debug builds that asked for it get a console. The gate is inside install():
	# OS.is_debug_build() AND `--console` natively / `?dev=1` on web, mirroring
	# _warmup_disabled()'s `?warm=off`. A release build gets nothing at all.
	CONSOLE_SCRIPT.install(self)

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


## Constructed in dependency order, then cross-wired: the director needs the drop
## layer to pay a death out, and the drop layer needs the director's live list for
## a Nuke, so one of the two edges can only be closed after both exist.
##
## Every system is handed the siblings it needs here rather than reaching through
## main for them each frame — a system that knows the shape of its composition
## root cannot be tested, moved or replaced without it.
func _build_systems() -> void:
	atmos = ATMOSPHERE_SCRIPT.new()
	atmos.name = "Atmosphere"
	add_child(atmos)
	atmos.bind(player, viewmodel)

	rounds = ROUNDS_SCRIPT.new()
	rounds.name = "RoundDirector"
	add_child(rounds)

	powerups = POWERUPS_SCRIPT.new()
	powerups.name = "PowerupManager"
	add_child(powerups)

	box = BOX_SCRIPT.new()
	box.name = "MysteryBox"
	add_child(box)
	box.bind(player, atmos)

	# Before the interaction system, which reads `traps.spots()` in its build().
	traps = TRAPS_SCRIPT.new()
	traps.name = "Traps"
	add_child(traps)
	traps.bind(player)
	traps.build()

	interact = INTERACT_SCRIPT.new()
	interact.name = "InteractionSystem"
	add_child(interact)

	rounds.bind(map, world, flow, player, powerups)
	powerups.bind(world, player, atmos, rounds)
	interact.bind(map, world, flow, player, hud, lighting, atmos, box, traps)

	interact.build()


func start_game() -> void:
	Game.set_state(Game.STATE_PLAY)
	Player.set_capture(true)
	rounds.begin_run()


## The systems' drive order, and the only reason main still has a `_process`.
##
## Constraint 6 is load-bearing here: these four draw from the gameplay Rng
## streams, and a seeded run only replays while they are drawn in the same order.
## Tree order would deliver the same order today and is not written down anywhere
## a reader can check, so the order lives here instead — round loop, box,
## power-ups, interact, exactly as main.gd's `_process` ran them before the split.
## `Game.tick_timers` stays ahead of all of it because `spawn_one` reads
## `Game.insta_kill` on the frame it expires.
func _process(dt: float) -> void:
	if _shot_frames >= 0:
		_tick_shot()

	if Game.state != Game.STATE_PLAY:
		return

	Game.tick_timers(dt)
	rounds.tick(dt)
	# Immediately after the round loop, and the position is part of the contract
	# rather than a preference: a trap kill routes through `Zombie.died` into the
	# director's payout path, which draws from the DROPS stream. Here it sees a
	# horde the director has just finished stepping, and it sees it at the same
	# point of every frame, which is what a seeded run needs.
	traps.tick(dt)
	box.tick(dt)
	powerups.tick(dt)
	interact.tick(dt)

	if _debug:
		_debug_t += dt
		if _debug_t >= 2.0:
			_debug_t = 0.0
			_soak_line()


## `--autostart`'s heartbeat. The state histogram is here because the barricade
## added two states a zombie can sit in indefinitely, and a soak that only prints
## `alive` cannot tell "six of them are working windows" from "six of them are
## stuck". Boards are printed for the same reason: they are the clock.
func _soak_line() -> void:
	var live: Array = rounds.alive()
	var by_state := {}
	for z: Zombie in live:
		var n: String = Zombie.State.keys()[z.state]
		by_state[n] = int(by_state.get(n, 0)) + 1
	var boards := 0
	for wi in MapData.WINDOWS.size():
		boards += map.window_boards[wi]
	print("[soak] round=%d alive=%d %s queued=%d kills=%d pts=%d hp=%.0f boards=%d live_windows=%d stam=%.2f" % [
		Game.round_no, live.size(), by_state, rounds.queued(), Game.kills,
		Game.points, player.hp, boards, map.live_windows().size(),
		player.stamina()])


func _on_player_died() -> void:
	Game.record_run()
	Game.set_state(Game.STATE_OVER)
	Player.set_capture(false)


## preload rather than the global class name: a freshly added script is not in
## the class registry until the editor rescans, and a headless run has no editor.
const VERIFY_SCRIPT := preload("res://scripts/dev/verify.gd")
const SIM_SCRIPT := preload("res://scripts/dev/balance_sim.gd")
const CONSOLE_SCRIPT := preload("res://scripts/dev/console.gd")
const WARMUP_SCRIPT := preload("res://scripts/world/shader_warmup.gd")
const QUALITY_SCRIPT := preload("res://scripts/world/quality_governor.gd")
const LIGHTING_SCRIPT := preload("res://scripts/world/lighting.gd")
const FX_SCRIPT := preload("res://scripts/world/fx.gd")
const VIEWMODEL_SCRIPT := preload("res://scripts/entities/viewmodel.gd")
const ATMOSPHERE_SCRIPT := preload("res://scripts/systems/atmosphere.gd")
const ROUNDS_SCRIPT := preload("res://scripts/systems/round_director.gd")
const POWERUPS_SCRIPT := preload("res://scripts/systems/powerup_manager.gd")
const INTERACT_SCRIPT := preload("res://scripts/systems/interaction_system.gd")
const BOX_SCRIPT := preload("res://scripts/systems/mystery_box.gd")
const TRAPS_SCRIPT := preload("res://scripts/systems/traps.gd")


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


## Non-zero when a build stalled or a weapon was refused, so a sim run can gate a
## script the same way --verify gates a build.
func _run_sim() -> void:
	Game.set_state(Game.STATE_PLAY)
	get_tree().quit(SIM_SCRIPT.new().run(self))


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
	# The death screen is a paused tree (see Game.set_state), and the reload has to
	# be able to run: the incoming scene's _ready is what clears the pause, so
	# leaving it set would mean asking a paused tree to build the thing that
	# unpauses it. Cleared here rather than relied upon.
	get_tree().paused = false
	get_tree().reload_current_scene()
