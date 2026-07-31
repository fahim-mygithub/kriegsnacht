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
var _shot_yaw := 0.0

## THE SHUTTER'S CLOCK IS SECONDS OF GAME TIME, NOT FRAMES.
##
## It used to be a frame count, and that made a bare `--shot` and the frame gate
## photograph different states. `tools/frames.ps1` passes `--fixed-fps 60`, so for
## the gate a budget of N frames was N/60 seconds; a bare `--shot`, which CLAUDE.md
## documents for the human pass, runs uncapped at 113-141 fps on this machine and
## the same N frames bought a third to a half of the game time. MEASURED: five of
## the eight scenarios came out different, and `power` came out BYTE-IDENTICAL TO
## ITS OWN CONTROL — the ceremony had reached three of eight lamps and the only one
## in frame had not moved. See scripts/dev/shot_setup.gd for the whole table.
##
## `dt` is the same quantity under both invocations, so accumulating it is the fix.
var _shot_active := false
## Seconds of game time elapsed in the current phase, and frames rendered in it.
var _shot_t := 0.0
var _shot_n := 0
## What the current phase is waiting for: `_shot_wait` seconds, and then
## `_shot_until` if the scenario declared one.
var _shot_wait := 0.0
var _shot_until := Callable()
## `--shot-setup <name>` / `--frames <name>`. The named world state applied after
## the world has settled and before the shutter — see scripts/dev/shot_setup.gd.
var _shot_setup := ""
var _shot_setup_done := false
## `--frames` rather than `--shot`: the same capture, but it also computes the
## frame statistics, runs the scenario's probes and writes them to
## notes/perf/frames/current/ for the headless `--frames-report` gate.
var _frames_mode := false


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
	# The muzzle flash's two additive layers — the tinted halo and the near-white
	# burst — which are Atmosphere's now. Asked for
	# the same way as every other layer's, so main.gd never has to know how many
	# materials any of them own.
	extra.append_array(atmos.materials())
	extra.append_array(fx.materials())
	# The trap posts and the arc sheet. The arc is additive+unshaded, which was a
	# variant only the muzzle flash otherwise drew with until the flash acquired a
	# texture and lost its billboard, and the first one the
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

	# The two halves of the frame gate that need no rendering device, so both are
	# `--headless` and both are safe to call from anywhere. Kept ahead of the
	# `--shot` block below so that the one flag which MUST be windowed is the last
	# thing a reader of this function meets, next to the warning about it.
	#
	# `--frames-list` exists so tools/frames.ps1 does not carry a second copy of
	# the scenario list. A runner with its own list is a runner that silently
	# stops covering a scenario the day somebody adds one.
	if "--frames-list" in OS.get_cmdline_args():
		_run_frames_list.call_deferred()
		return

	# `--frames-report` is THE GATE: it reads every capture the windowed pass
	# left in notes/perf/frames/current/, compares them against the committed
	# golden values and exits non-zero on drift.
	if "--frames-report" in OS.get_cmdline_args():
		_run_frames_report.call_deferred()
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

	# `--shot-setup <name>` puts the world into a named state before the shutter.
	# Three agents hand-patched `_tick_shot` to photograph a state and reverted it
	# again (audit §4); this is that, once, in a file that can be reviewed.
	# Read before both capture flags because either can use it.
	if "--shot-setup" in args:
		var s := args.find("--shot-setup")
		_shot_setup = args[s + 1] if s + 1 < args.size() else ""

	if "--shot" in args:
		var i := args.find("--shot")
		_shot_path = args[i + 1] if i + 1 < args.size() else "shot.png"
		if i + 2 < args.size() and args[i + 2].is_valid_float():
			_shot_yaw = deg_to_rad(args[i + 2].to_float())
		_arm_shot()

	# `--frames <name>`: capture, measure, record. WINDOWED, exactly as `--shot`
	# is and for exactly the same reason — under `--headless` there is no
	# rendering device, so `await RenderingServer.frame_post_draw` never returns
	# and the process hangs forever rather than failing.
	if "--frames" in args:
		var i := args.find("--frames")
		_shot_setup = args[i + 1] if i + 1 < args.size() else ""
		if SHOT_SETUP.settle_of(_shot_setup) < 0.0:
			push_error("[frames] unknown scenario '%s'. Known: %s" % [
				_shot_setup, String(", ").join(SHOT_SETUP.names())])
			get_tree().quit(2)
			return
		_frames_mode = true
		_arm_shot()


## Both capture flags open with the same phase: let the world settle for
## WORLD_SETTLE seconds of game time before the scenario lands or the shutter
## fires. Seconds and not frames, for the reason at `_shot_active`.
func _arm_shot() -> void:
	_shot_active = true
	_shot_t = 0.0
	_shot_n = 0
	_shot_wait = WORLD_SETTLE
	_shot_until = Callable()
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
	# A CAPTURE RUN MUST NOT CAPTURE THE POINTER, and this is not tidiness.
	# `player._unhandled_input` turns mouse motion into camera rotation whenever
	# `Input.mouse_mode == MOUSE_MODE_CAPTURED`, so a windowed `--shot` or
	# `--frames` with a real mouse anywhere near the window photographs whatever
	# direction the hand happened to leave it pointing. It cost a false gate
	# failure to find: the frame gate run inside tools/build.ps1 reported 95
	# drifts, four relations out of band, on scenarios the sabotage under test
	# could not possibly have touched — `ads.mean / spawn.mean` came back 2.13
	# against a golden 0.91 because the camera had turned to face a lit wall.
	#
	# The HUD's pause-on-lost-pointer does not fire either, because `_lock_seen`
	# never arms without a lock to lose — which is the same path every headless
	# and MCP-driven run already takes.
	if not _shot_active:
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
	if _shot_active:
		_tick_shot(dt)

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
const SHOT_SETUP := preload("res://scripts/dev/shot_setup.gd")
const FRAME_STATS := preload("res://scripts/dev/frame_stats.gd")
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


## Seconds of game time the world gets to settle before the scenario lands. Was
## 60 frames, which was 1.0 s only under `--fixed-fps 60`.
const WORLD_SETTLE := 1.0

## How much game time past its own `settle` an arrival predicate gets before the
## capture is declared a failure. Generous on purpose — a predicate that fires
## LATE is a scenario whose animation somebody lengthened, and waiting for it is
## the right answer; a predicate that never fires is a broken scenario, and three
## extra seconds is long enough to tell those apart for every state here.
const ARRIVAL_GRACE := 3.0

## Comparing accumulated game time against a budget, so it needs a hair of slack:
## twenty-one additions of `1.0/60.0` do not land exactly on 0.35. 1e-6 s is ten
## orders of magnitude above the double-precision drift over the longest budget
## here and four below one frame at 60 fps, so it can neither miss a frame nor add
## one.
const SHOT_EPS := 1e-6

## The runaway guard, and it is NOT the deadline — the deadline above is in game
## time, which is the only frame-rate-independent way to say "long enough". This
## catches the one thing a game-time budget cannot: a `dt` that has stopped
## advancing at all (a paused tree, a zero delta), where waiting for seconds would
## spin forever inside tools/frames.ps1's own timeout with nothing to report.
const SHOT_MAX_FRAMES := 60000


## True once the current phase's budget is spent AND its arrival predicate, if it
## has one, is satisfied. Fails the process loudly rather than returning true on a
## predicate that never fires — a capture that shoots early is a golden row of the
## wrong state, which is exactly the failure this replaced.
func _shot_ready() -> bool:
	if _shot_n > SHOT_MAX_FRAMES:
		push_error(("[shot] '%s' rendered %d frames for %.3f s of game time — dt is "
			+ "not advancing. Nothing can be photographed from here.") % [
			_shot_setup, _shot_n, _shot_t])
		_shot_active = false
		get_tree().quit(3)
		return false
	if _shot_t + SHOT_EPS < _shot_wait:
		return false
	if not _shot_until.is_valid():
		return true
	if bool(_shot_until.call(self)):
		return true
	if _shot_t > _shot_wait + ARRIVAL_GRACE:
		push_error(("[shot] '%s' never arrived: %.3f s of game time over %d frames, "
			+ "budget %.2f s + %.2f s grace, and its arrival predicate is still "
			+ "false. Refusing to photograph a state the scenario did not reach.") % [
			_shot_setup, _shot_t, _shot_n, _shot_wait, ARRIVAL_GRACE])
		_shot_active = false
		get_tree().quit(3)
	return false


func _tick_shot(dt: float) -> void:
	# THE CAMERA IS HELD, EVERY FRAME, ALL THE WAY TO THE SHUTTER.
	#
	# Belt and braces over `start_game`'s refusal to capture the pointer: that
	# closes the only route a stray mouse has into the camera today, and this
	# makes the pose an invariant rather than a consequence of that one guard
	# still being there. Before the scenario lands the pose is the command line's
	# yaw and a level pitch; afterwards it is whatever the scenario aimed at,
	# because a scenario aims the camera at the thing it exists to photograph —
	# the Corridor trap gate is 90 degrees off the spawn heading — and re-writing
	# the yaw here would point every one of them at the same wall.
	if player and is_instance_valid(player):
		if _shot_setup_done:
			SHOT_SETUP.hold(self)
		else:
			SHOT_SETUP.aim(self, _shot_yaw, 0.0)
	_shot_t += dt
	_shot_n += 1
	if not _shot_ready():
		return

	# The scenario lands once, after the world has settled and before the
	# shutter, and it gets its OWN budget and its OWN arrival predicate. A state
	# whose subject is a timed animation is not photographable at the budget a
	# static state wants — the power-on ceremony is 2.13 s of tween and the Ray
	# Gun bolt is 0.15 s of flight — and a state that has to ARRIVE is not
	# photographable at any budget at all, only at the moment it gets there.
	if not _shot_setup.is_empty() and not _shot_setup_done:
		_shot_setup_done = true
		var settle := SHOT_SETUP.apply(_shot_setup, self)
		if settle < 0.0:
			# Fail, never fall through. A typo that silently photographs the
			# default view is a golden row that certifies nothing.
			push_error("[shot] unknown --shot-setup '%s'. Known: %s" % [
				_shot_setup, String(", ").join(SHOT_SETUP.names())])
			_shot_active = false
			get_tree().quit(2)
			return
		# Latched here and not inside the scenario, so a scenario cannot forget.
		SHOT_SETUP.latch(self)
		_shot_t = 0.0
		_shot_n = 0
		_shot_wait = settle
		_shot_until = SHOT_SETUP.arrival_of(_shot_setup)
		if not _shot_ready():
			return

	_shot_active = false
	# Both numbers, every capture. The frame count is the one that moves between a
	# bare run and `--fixed-fps 60`, and printing them side by side is what makes
	# a mis-timed capture visible in a log instead of only in the pixels.
	print("[shot] %s: %.4f s of game time over %d frames" % [
		_shot_setup if not _shot_setup.is_empty() else "(default view)",
		_shot_t, _shot_n])
	# Grab after the frame has actually been drawn, or the capture races the
	# renderer and comes back empty.
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if _frames_mode:
		await _finish_frames(img)
		return
	img.save_png(_shot_path)
	print("[shot] wrote %s (%dx%d)" % [_shot_path, img.get_width(), img.get_height()])
	get_tree().quit()


## Measures the captured frame and writes it to notes/perf/frames/current/.
##
## It does NOT gate. The comparison is `--frames-report`'s, so that one bad
## scenario cannot stop the runner before the other six have been captured and
## so the verdict is one table rather than seven exit codes. What this exits
## non-zero for is a capture that is structurally broken — a scenario whose probe
## came back empty means the thing it was pointed at was not there, and a golden
## row taken from that would bless the absence.
## The same instant with the viewmodel hidden, so a probe can locate the weapon by
## DIFFERENCE rather than by a colour mask — see `frame_stats.changed_box()`.
##
## THE TREE IS PAUSED ACROSS THE SECOND DRAW, and that is the whole trick. Without
## it the two frames are a `dt` apart: the torch flicker, the fixture glow, the arc
## sheet and every other `_process`-driven light would have moved, and the
## difference would be most of the room instead of the gun. Paused, the only thing
## that changed between them is the thing this function turned off.
##
## THE CONTROL FOR THAT CLAIM, run rather than assumed: with this one line patched
## to `visible = true` — the second draw taken without hiding anything — both
## scenarios that use the difference report a box of `x -1..-1  y -1..-1  (0 px
## over 0 rows)`, at a threshold of 1 as well as at the shipped 3. The noise floor
## is exactly nothing, so every pixel the difference finds is the weapon.
func _bare_frame() -> Image:
	if viewmodel == null or not is_instance_valid(viewmodel):
		return null
	var was_paused := get_tree().paused
	var was_visible: bool = viewmodel.visible
	get_tree().paused = true
	viewmodel.visible = false
	await RenderingServer.frame_post_draw
	var out := get_viewport().get_texture().get_image()
	viewmodel.visible = was_visible
	get_tree().paused = was_paused
	return out


func _finish_frames(img: Image) -> void:
	var stats := FRAME_STATS.of(img)
	# THE LIVE-SCENE PROBES RUN BEFORE THE SECOND DRAW, and the order is load
	# bearing. They unproject world positions — the Ray Gun bolt, the trap gate, the
	# lamp fixture — through the live camera, and `_bare_frame()` renders another
	# frame during which the bolt moves. Taking it first moved `raygun`'s bolt_mean
	# by 2.8% on a frame whose every whole-frame statistic was bit-identical: the
	# measurement had drifted off the thing it was measuring. Found by blessing and
	# reading the diff, which is what the three-way table in a bless is for.
	var probes := SHOT_SETUP.probe(_shot_setup, self, img)
	var bare: Image = await _bare_frame()
	probes.merge(SHOT_SETUP.probe_silhouette(_shot_setup, img, bare))
	stats["probes"] = probes
	stats["settle"] = SHOT_SETUP.settle_of(_shot_setup)
	FRAME_STATS.record(_shot_setup, stats, img)
	print("[frames] %s  mean=%.6f (code %.1f)  median=%.6f  black=%.4f  blown=%.4f" % [
		_shot_setup, stats["mean"], FRAME_STATS.code(stats["mean"]),
		stats["median"], stats["black"], stats["blown"]])
	for k: String in probes.keys():
		print("[frames]   %s = %.5f" % [k, float(probes[k])])
	# The viewmodel's silhouette in PIXELS, printed and deliberately not recorded.
	# VM_RECT_HIP and VM_RECT_ADS in shot_setup.gd are hand-set rects whose comment
	# says they were "read off the reference frames with a pixel ruler" — this is
	# that ruler, so re-reading one after the weapon moves is a line in a log rather
	# than an afternoon in an image editor. Not a golden value: a bounding box in
	# pixels is a snapshot that has to be re-blessed at every resolution, and the
	# two RATIOS derived from it are the half that survives.
	# Only for the scenarios that MEASURE the silhouette. On `raygun` the same
	# difference reports the whole frame — the bolt and its light advance between
	# the two draws, because pausing the tree does not stop everything — and a line
	# reading `viewmodel box x 0..1279` under a scenario that has no viewmodel
	# measurement is an invitation to chase a bug that is not there.
	if bare != null and SHOT_SETUP.silhouette_expected(_shot_setup):
		var box := FRAME_STATS.changed_box(img, bare)
		print("[frames]   viewmodel box  x %d..%d  y %d..%d  (%d px over %d rows)" % [
			box["x0"], box["x1"], box["y0"], box["y1"], box["count"], box["rows"]])
	var broken := SHOT_SETUP.probes_expected(_shot_setup) and probes.is_empty()
	if broken:
		push_error("[frames] %s produced no probe values — its subject was not in the scene"
			% _shot_setup)
	# A silhouette scenario whose difference found nothing has photographed a frame
	# with no weapon in it. The relations would catch it — `sight_top_over_centre`
	# comes back -1.0, outside every band — but a capture that knows it is broken
	# should say so where it happened rather than three scenarios later in a table.
	if SHOT_SETUP.silhouette_expected(_shot_setup) and float(probes.get("gun_px", 0.0)) <= 0.0:
		push_error(("[frames] %s: hiding the viewmodel changed nothing, so there was "
			+ "no viewmodel in the frame.") % _shot_setup)
		broken = true
	get_tree().quit(1 if broken else 0)


func _run_frames_list() -> void:
	for n: String in SHOT_SETUP.names():
		print(n)
	get_tree().quit(0)


func _run_frames_report() -> void:
	get_tree().quit(FRAME_STATS.report(SHOT_SETUP.names()))


func restart() -> void:
	# The death screen is a paused tree (see Game.set_state), and the reload has to
	# be able to run: the incoming scene's _ready is what clears the pause, so
	# leaving it set would mean asking a paused tree to build the thing that
	# unpauses it. Cleared here rather than relied upon.
	get_tree().paused = false
	get_tree().reload_current_scene()
