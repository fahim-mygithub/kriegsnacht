extends Node

## Self-contained benchmark and visual-verdict harness.
##
## Only runs in a build exported with the `perfprobe` custom feature, or when
## `tools/perf_native.ps1` registers it as an autoload for the duration of one
## run, so it can never activate in the shipped web build. It exists because the
## browser automation tab reports visibilityState=hidden, which throttles
## requestAnimationFrame — any FPS sampled from JS there would be fiction.
## Measuring inside the engine and POSTing the result sidesteps that entirely.
##
## Modes, selected with `?mode=` on web or `--perf-mode` natively:
##
##   base        M-BASE       does the billboard build have any headroom at all?
##   phys        M-PHYS       what do 24 mutually-colliding CharacterBody3D cost?
##   audio       M-AUDIO      where does concurrent 3D voice count start hurting?
##   flow        M-FLOW       what does one flow-field sweep cost?
##   sep         M-SEP        is the separation term still overpowering steering?
##   warm        M-WARM       does the shader warm-up pass remove the first-draw
##                            hitches, and by how much?
##   shadow      M-SHADOW,    what does the torch shadow cost, and does a second
##               M-SHADOW2    shadowed light really re-draw the geometry?
##   ssao        M-SSAO       what do SSAO and the colour LUT cost, separately?
##   particles   M-PARTICLES  how many concurrent emitters fit in the budget?
##   billboard   M-BILLBOARD  does MAIN_CAM_INV_VIEW_MATRIX compile here, and
##                            what does a custom billboard shader cost?
##   vmfov       M-VMFOV      does the vertex-only PROJECTION_MATRIX override
##                            behave, and which sign of [1][1] is upright?
##   mmcolor     M-MMCOLOR    does MultiMesh.set_instance_color reach the
##                            fragment on gl_compatibility?
##   shadowcast  M-SHADOWCAST do alpha-scissor billboards cast shadows?
##
## **Five traps, every one of which has cost a run.**
##
## 1. `--quit-after` counts FRAMES, not seconds. Nothing here uses it; the probe
##    ends itself from `_finish()`.
##
## 2. **Headless frame times carry no information at all.** Godot's low-processor
##    sleep pins them near 6.9 ms regardless of load, `draw_calls` is 0 and
##    `video_mem` is 0 — while `RenderingServer.get_current_rendering_method()`
##    still cheerfully reports `gl_compatibility`. Only `physics_ms`, and the
##    numbers this file computes itself (flow, sep), mean anything under
##    `--headless`. Every mode below is labelled with which of the two it needs.
##
## 3. **A windowed native run is vsynced by default**, which pins every frame at
##    16.67 ms and destroys the signal just as thoroughly as headless does, only
##    less obviously. `begin()` turns vsync off and uncaps `Engine.max_fps`. Web
##    is driven by requestAnimationFrame and cannot be uncapped — which is
##    exactly why the web rows must be read as p99 and worst, never as a mean.
##
## 4. **Desktop OpenGL has a shader cache and the web does not.** `ShaderGLES3`
##    compiles `_load_from_cache`/`_save_to_cache` out under `#ifdef
##    WEB_ENABLED`, so a second native run starts warm and M-WARM measures
##    nothing. The harness deletes `user://shader_cache` before a warm run; the
##    graphics driver's own program cache is outside anyone's control here, which
##    is why the native M-WARM number is a floor and the browser is the answer.
##
## 5. **A capture mode needs a drawn frame.** The three visual modes read the
##    viewport back with `get_texture().get_image()`, which returns nothing under
##    `--headless`. They report `capture: "unavailable"` rather than inventing a
##    verdict.
##
## Nothing here draws from an `Rng` stream; the probe carries its own generator
## so a perf run cannot be confused with a seeded gameplay run. The one
## exception is second-hand: `warm` mode emits `player.fired`, and `main.gd`'s
## handler rolls the muzzle quad's roll from `Rng.VISUAL`. That is main.gd's
## draw, in a build that never ships, and it is noted rather than worked around.

const ENDPOINT := "http://127.0.0.1:8970/result"

## Seconds to let a stage stabilise before sampling. On the web the first stage
## otherwise absorbs the entire shader-compile storm and libels itself — there is
## no program cache in WebGL2, so every visitor compiles every variant from GLSL
## on the main thread. It is also what absorbs the recompile that toggling
## shadows or SSAO provokes, which is why those modes may toggle at all.
const SETTLE_NATIVE := 1.5
const SETTLE_WEB := 3.5
const MEASURE := 5.0

## M-WARM measures a *spike*, not a rate, so its window only has to be long
## enough to contain the first draw and a little after it. A long window would
## dilute the one frame that matters into a mean that hides it.
const MEASURE_WARM := 1.0

## M-SEP asks what a pack does over half a minute of steering, which is the
## span over which a pack either spreads across a corridor or files down it.
const MEASURE_SEP := 30.0

## The capture modes have nothing to average — the readback happens once, at the
## top of the window. The window exists only so the row carries a frame cost too.
const MEASURE_SHORT := 1.0

## M-BASE: the horde ladder.
const STAGES := [0, 6, 12, 18, 24]

## M-AUDIO: concurrent looping 3D voices, with the horde held at 24 so the
## renderer and physics load is constant and only the voice count moves.
const VOICE_STAGES := [0, 4, 8, 12, 16, 24, 32]
const AUDIO_ZOMBIES := 24

## M-PHYS: zombie<->zombie collision off, then on. The shipped game runs with it
## off (mask 1|2) because this number did not exist; boid separation handles
## spacing instead. This is the measurement that decides whether that stays true.
const COLLISION_MODES := [false, true]

## M-SHADOW: shadows off, then on at three atlas sizes. `-1` is the off row.
## Plain Array of ints rather than a Packed constructor — `const X :=
## PackedInt32Array([...])` is a call, and a constant must be a constant
## *expression*, so that form is a parse error.
const SHADOW_STAGES := [-1, 512, 1024, 2048]

## M-PARTICLES: concurrent live emitters, restarting continuously. The shipped
## pools total fourteen (6 blood + 8 debris), so the ladder brackets that.
const PARTICLE_STAGES := [0, 8, 16, 24, 40, 64]

## Held at twelve rather than at the ladder's 24. SYNTHESIS section 5 asks for
## "the actual gameplay scene", and what that is protecting against is an
## empty-scene number — the real level, the real lighting, the real fill. Twelve
## is a genuine round-5 horde; twenty-four would put the frame near budget before
## the first emitter runs and every particle row would read as a crossing.
const PARTICLE_ZOMBIES := 12

## How often the probe emitters are restarted. Short enough that every one of
## them is live essentially all the time, which is what "concurrent" has to mean
## for the number to bound anything.
const PARTICLE_PERIOD := 0.25

## M-FLOW: consecutive solves per stage. The sweep fires on a player tile change
## — about four a second at a sprint — so 200 is far more than a run will ever
## ask for and enough for a p99 to mean something.
const FLOW_SOLVES := 200

## M-SEP: a round-10 pack, piled in a doorway, which is the case the separation
## term was overpowering steering in.
const SEP_ZOMBIES := 24

## M-BILLBOARD: enough sprites to be a horde, few enough to be one screen.
const BILLBOARD_SPRITES := 24
const BILLBOARD_TEX := "res://assets/props/pu_ammo.png"

## M-MMCOLOR: SYNTHESIS section 5 asks for 32 instances with distinct alphas.
const MMCOLOR_INSTANCES := 32

## M-VMFOV: the viewmodel FOV the shader would ship with, and the distance the
## geometric no-clip argument puts the mesh at (player capsule RADIUS is 0.24, so
## nothing in the world can come within it).
const VM_FOV := 55.0
const VM_DIST := 0.15

## Where the near marker sits, measured from the lens. The body is 0.10 m deep
## about VM_DIST, so its front face is at 0.10 — anything at 0.08 is genuinely in
## front of it rather than buried inside it, which is what makes that marker an
## occluder instead of a fourth coloured box floating next to one.
const VM_NEAR_Z := 0.080

## The stage dictionary. Every mode's rows are built by merging over this, so the
## driver can read every key unconditionally and adding an axis cannot break a
## mode that does not use it.
##
## `-1` means "leave the shipping configuration alone" on every key where 0 is a
## meaningful value in its own right. That distinction is load-bearing: a stage
## that means "no emitters" and a stage that means "do not touch the emitters"
## are different measurements, and conflating them silently tears down the
## shipped pools in a mode that was not asking about them.
const STAGE_DEFAULTS := {
	"label": "",
	"zombies": 0, "collide": false, "pile": false,
	"voices": 0, "max_dist": 0.0,
	"shadow": -2,        # -2 untouched, -1 shadows off, >0 atlas size with shadows on
	"omni_shadow": -1,   # -1 untouched, 0 off, 1 on (one room lamp)
	"ssao": -1,          # -1 untouched, 0 off, 1 on
	"lut": -1,           # -1 untouched, 0 off, 1 on
	"emitters": -1,      # -1 untouched, else probe emitter count
	"pamount": 0,        # 0 = the shipped amount
	"pdepth": false,     # true = DRAW_ORDER_VIEW_DEPTH
	"sprites": -1,       # -1 untouched, else probe sprite count
	"tilt": 0,           # 0 SpriteBase3D, 1 tilt shader / INV, 2 tilt shader / MAIN_CAM
	"trigger": "",       # M-WARM: the first-draw event to fire at window start
	"capture": "",       # capture modes: what to read back and how to grade it
	"sign": 0.0,         # M-VMFOV: 0 leaves PROJECTION_MATRIX alone
	"flow_doors": -1,    # M-FLOW: -1 untouched, 1 open every door first
	"sep": false,        # M-SEP: accumulate the separation magnitudes
}

var _main: Node3D
var _mode := "base"
var _plan: Array[Dictionary] = []
var _stage := -1
var _t := 0.0
var _settle := SETTLE_NATIVE
var _measure_len := MEASURE
var _measuring := false
var _deltas: Array[float] = []
var _mon := {}
var _mon_n := 0
var _results := []
var _boot_ms := 0
var _rng := RandomNumberGenerator.new()
var _voices: Array[AudioStreamPlayer3D] = []

## Whatever the current stage computed for itself — flow timings, separation
## percentiles, a capture verdict. Merged into the row by `_record()`, so a new
## measurement adds fields without touching the row builder.
var _extra := {}

## Probe-owned scene furniture, torn down between stages. Everything here is the
## probe's, never the game's, so nothing below shares a node with a game system.
var _emitters: Array[GPUParticles3D] = []
var _burst_t := 0.0
var _sprites: Array[Node3D] = []
var _rig: Node3D

## The shipped colour LUT, taken once so the SSAO ladder can put it back rather
## than rebuild it — rebuilding would measure a different grade.
var _lut: Texture2D
var _lut_read := false

## Where a capture mode writes its PNGs. Natively this is the deliverable; on web
## the deliverable is the tab, because getting a file out of a browser sandbox is
## more machinery than asking someone to look at the screen.
var _shot_dir := "user://"

## Whether `quality_governor` was found and stopped. See `_freeze_governor()`.
var _gov_frozen := false


## Registered as an autoload only by the perf export and by
## `tools/perf_native.ps1`, so nothing in the shipped game references this file at
## all. Waits for Main to exist, then drives it.
func _ready() -> void:
	_await_main.call_deferred()


func _await_main() -> void:
	var scene := get_tree().current_scene
	if scene == null or not scene.has_method("start_game"):
		await get_tree().process_frame
		_await_main.call_deferred()
		return
	begin(scene)


## Web has no argv, so parameters arrive in the query string; native keeps a
## `--perf-<key>` flag so the same probe can be driven from a script without a
## browser. One reader for both, because otherwise every mode that grew a
## sub-parameter would grow a second copy of this and they would drift.
func _arg(key: String, def: String) -> String:
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("location.search", true)
		var s := str(q) if q != null else ""
		for part in s.trim_prefix("?").split("&"):
			var kv := str(part).split("=")
			if kv.size() == 2 and kv[0] == key:
				return kv[1]
		return def
	var args := OS.get_cmdline_args()
	var i := args.find("--perf-" + key)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return def


## Whether the run was asked to skip `main.gd`'s warm-up pass: `--no-warmup`
## natively, `?warm=off` on web. Shaped exactly like
## `quality_governor._post_forced_off()`, which spells the same idea
## `--no-post-fx` / `?post=off`, because a second convention for the same kind of
## switch is a second thing to remember at three in the morning.
##
## The probe only *reports* this, in `env.warmup_disabled`. `main.gd` is what
## acts on it — so a run whose JSON says `warmup_disabled: true` and whose
## `worst_ms` did not move means the main.gd side of the A/B is missing, not that
## the warm-up pass is worthless.
func _warmup_off() -> bool:
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("location.search", true)
		if q == null:
			return false
		return "warm=off" in str(q)
	return "--no-warmup" in OS.get_cmdline_args()


## Copied key by key rather than with `duplicate()`: a `const` Dictionary is
## read-only, and whether the copy inherits that flag is exactly the kind of
## thing that changes between point releases and fails at the first write.
func _row(over: Dictionary) -> Dictionary:
	var s := {}
	for k: String in STAGE_DEFAULTS:
		s[k] = STAGE_DEFAULTS[k]
	for k: String in over:
		s[k] = over[k]
	return s


## The stage list is data, so every measurement shares one driver instead of a
## dozen near-copies that drift apart.
func _build_plan() -> void:
	_plan.clear()
	_measure_len = MEASURE
	match _mode:
		"phys":
			for collide in COLLISION_MODES:
				var kind := "contact" if collide else "no-contact"
				for n in STAGES:
					_plan.append(_row({"zombies": n, "collide": collide, "pile": true,
						"label": "z%s %s" % [n, kind]}))
		"audio":
			for md in [0.0, 20.0]:
				for v in VOICE_STAGES:
					_plan.append(_row({"zombies": AUDIO_ZOMBIES, "voices": v,
						"max_dist": md, "label": "v%d md%.0f" % [v, md]}))
		"flow":
			# Doors shut first, then every door open, which is both the largest
			# connected component and the state SYNTHESIS section 5 names.
			_measure_len = MEASURE_SHORT
			_plan.append(_row({"label": "doors shut", "flow_doors": 0}))
			_plan.append(_row({"label": "doors open", "flow_doors": 1}))
		"sep":
			_measure_len = MEASURE_SEP
			_plan.append(_row({"zombies": SEP_ZOMBIES, "pile": true, "sep": true,
				"label": "round10 pile"}))
		"warm":
			# Ordered so each stage is genuinely the *first* of its kind: the
			# baseline holds the camera still with nothing new on screen, and no
			# later stage repeats an earlier one's material.
			#
			# The two wall stages come last because they *teleport the player* to
			# stand in front of a wall of the right texture, and a caster spawned
			# three metres ahead of a player who is standing 1.2 m from a wall is
			# spawned inside it. Everything that needs open floor happens first,
			# at the spawn point, which is the middle of the Lobby.
			_measure_len = MEASURE_WARM
			for ev in ["baseline", "shot", "flesh", "caster", "death", "wall", "metal"]:
				_plan.append(_row({"trigger": ev, "label": ev}))
		"shadow":
			# The horde is the caster load, so it is held at the ladder's top for
			# every row; only the shadow configuration moves.
			for res in SHADOW_STAGES:
				var n: int = res
				var tag := "torch off" if n < 0 else "torch %d" % n
				_plan.append(_row({"zombies": 24, "shadow": n, "omni_shadow": 0,
					"label": tag}))
			# M-SHADOW2 rides the same mode because it is the same apparatus with
			# one more light: watch `objects` and `primitives`, not fps.
			_plan.append(_row({"zombies": 24, "shadow": 2048, "omni_shadow": 1,
				"label": "torch 2048 + one omni"}))
		"ssao":
			# Both halves of quality_governor.heavy_post(), separated. Toggling
			# either is an uncached full-screen GLSL compile, which is why the
			# settle has to run between stages and why the shipped build decides
			# this once, before the first frame.
			for row: Array in [[0, 0, "plain"], [1, 0, "ssao"], [0, 1, "lut"],
					[1, 1, "ssao+lut"]]:
				_plan.append(_row({"zombies": 24, "ssao": row[0], "lut": row[1],
					"label": row[2]}))
		"particles":
			for n in PARTICLE_STAGES:
				_plan.append(_row({"zombies": PARTICLE_ZOMBIES, "emitters": n,
					"label": "e%d" % n}))
			# The two questions the ladder cannot answer on its own: whether the
			# CPU depth sort (godot#107633) costs anything on 4.7, and whether the
			# ceiling is emitter count or particle count.
			_plan.append(_row({"zombies": PARTICLE_ZOMBIES, "emitters": 24,
				"pdepth": true, "label": "e24 view-depth"}))
			_plan.append(_row({"zombies": PARTICLE_ZOMBIES, "emitters": 24,
				"pamount": 42, "label": "e24 double amount"}))
		"billboard":
			for row: Array in [[0, "sprite3d"], [1, "tilt INV_VIEW"],
					[2, "tilt MAIN_CAM_INV_VIEW"]]:
				_plan.append(_row({"sprites": BILLBOARD_SPRITES, "tilt": row[0],
					"capture": "billboard", "label": row[1]}))
		"vmfov":
			_measure_len = MEASURE_SHORT
			# One stage per sign, plus the untouched reference every verdict is
			# read against. On web a single sign is selected by `?sign=`, so a
			# human can hold one configuration on screen and look at it.
			var want := _arg("sign", "")
			for sg: float in [0.0, 1.0, -1.0]:
				if want != "" and not is_equal_approx(sg, float(want)):
					continue
				var tag := "reference" if sg == 0.0 else "y_sign %+.0f" % sg
				_plan.append(_row({"sign": sg, "capture": "vmfov", "label": tag}))
		"mmcolor":
			_measure_len = MEASURE_SHORT
			_plan.append(_row({"capture": "mmcolor", "label": "instance colour A/B"}))
		"shadowcast":
			_measure_len = MEASURE_SHORT
			# One zombie, one torch, one variable. The pair of frames is the
			# measurement; a single frame of a zombie on a floor proves nothing,
			# because a dark patch under a sprite is also just a dark floor.
			for row: Array in [[-1, "torch shadow off"], [2048, "torch shadow on"]]:
				_plan.append(_row({"shadow": row[0], "capture": "shadowcast",
					"label": row[1]}))
		_:
			_mode = "base"
			for n in STAGES:
				_plan.append(_row({"zombies": n, "label": "z%d" % n}))


func begin(main: Node3D) -> void:
	_main = main
	_mode = _arg("mode", "base")
	_shot_dir = _arg("shots", "user://")
	if not _shot_dir.ends_with("/"):
		_shot_dir += "/"
	_build_plan()
	_settle = SETTLE_WEB if OS.has_feature("web") else SETTLE_NATIVE
	_boot_ms = Time.get_ticks_msec()
	_rng.seed = 12345

	# Trap 3. A windowed native run is vsynced by default, which reports every
	# frame as 16.67 ms whatever the load — the same shape of lie as the headless
	# 6.9 ms, and harder to spot because it looks like a plausible frame time.
	# Nothing to do on web: the frame clock there is requestAnimationFrame and it
	# is not ours to uncap, which is exactly why the web rows are read as p99.
	Engine.max_fps = 0
	if not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# Beacon immediately so a silent failure is distinguishable from a
	# probe that never started. Before anything that can itself post a warning,
	# so `started` is always the first line of a run.
	_post({"event": "started", "mode": _mode, "boot_ms": _boot_ms,
		"stages": _plan.size(), "settle_s": _settle,
		"adapter": RenderingServer.get_video_adapter_name()})
	_gov_frozen = _freeze_governor()
	_main.start_game()
	# Freeze the round loop so only the stage's own zombies are alive.
	_main._to_spawn = 0
	_main._intermission = true
	_main._round_timer = 99999.0
	_next_stage()


## Stops `quality_governor` moving `Viewport.scaling_3d_scale` out from under a
## ladder. It demotes after one 1.4 s window below 38 fps and promotes after
## three above 58, and a probe run is minutes long — so without this, stage 4 of
## a ladder can be rendering at 0.75 while stage 1 rendered at 1.0, and the JSON
## records one `render_scale` for both. That is the same failure as the
## mislabelled renderer field: a row whose configuration is not the one it
## claims. `quality_governor._ready()` already does exactly this for `--shot` and
## `--verify` and for exactly this reason; the probe is the third case and cannot
## reuse either flag, because both also change other things it needs left alone.
##
## Not a second writer on the property (rule 7): this removes the only writer
## from the frame loop and leaves the value where the governor last put it, which
## on a fresh process is the top of the ladder. `_record()` still stamps the live
## value on every row, so a scale that moves anyway is visible rather than
## averaged in.
func _freeze_governor() -> bool:
	# By node name, because `quality_governor.gd` carries no `class_name` and
	# `main.gd` names the node when it adds it.
	var g: Node = _main.get_node_or_null("QualityGovernor")
	if g == null:
		_post({"event": "warn", "detail": "no QualityGovernor node; render scale is unpinned"})
		return false
	g.set_process(false)
	return true


func _next_stage() -> void:
	_stage += 1
	if _stage >= _plan.size():
		_finish()
		return
	var s: Dictionary = _plan[_stage]
	_clear()
	_spawn(int(s.zombies), bool(s.collide), bool(s.pile))
	_set_voices(int(s.voices), float(s.max_dist))
	_apply_stage(s)
	_t = 0.0
	_measuring = false
	_deltas.clear()
	_sep_samples.clear()
	_sep_clamped = 0
	_extra.clear()
	_mon.clear()
	_mon_n = 0


func _clear() -> void:
	for z in get_tree().get_nodes_in_group("zombies"):
		z.free()
	_main.rounds.alive().clear()


## `pile` packs the horde into one small disc rather than scattering it across
## the room. A scattered spawn measures 24 bodies that never touch each other,
## which understates the collision cost by a wide margin — the case that matters
## is the doorway pile, where every body is in contact with several others.
func _spawn(n: int, collide: bool, pile: bool) -> void:
	# _main is a plain Node3D here, so its members come back untyped —
	# annotate explicitly or inference fails at compile time.
	var p: Vector3 = _main.player.global_position
	var here := Vector2(p.x, p.z)
	var centre := _pile_centre(here) if pile else Vector2.ZERO
	var placed := 0
	var tries := 0
	while placed < n and tries < 8000:
		tries += 1
		var pos: Vector2
		if pile:
			# Tight disc: at radius 1.4 m, 24 bodies of radius 0.26 m overlap
			# heavily and the broadphase has real work to do.
			var a := _rng.randf() * TAU
			var r := sqrt(_rng.randf()) * 1.4
			pos = centre + Vector2(cos(a), sin(a)) * r
			if _main.map.is_blocked(int(pos.x), int(pos.y)):
				continue
		else:
			var x := _rng.randi_range(3, 14)
			var y := _rng.randi_range(3, 13)
			if _main.map.is_blocked(x, y):
				continue
			pos = Vector2(x + 0.5, y + 0.5)
			if pos.distance_to(here) < 3.0:
				continue
		var z := _spawn_at(Vector3(pos.x, 0.0, pos.y), placed % 3)
		# Layer 4 is the enemy layer, so adding it to the mask is exactly the
		# zombie<->zombie contact the shipped build leaves out.
		if collide:
			z.collision_mask |= 4
		placed += 1
	if placed < n:
		_post({"event": "warn", "detail": "placed %d of %d requested" % [placed, n]})


## One zombie at one place. Round 10 for every mode, because that is the round
## M-SEP names and because a round-1 walker moves too slowly to crowd anything.
func _spawn_at(at: Vector3, pal: int) -> Zombie:
	var z := Zombie.create("zombie", pal, 10, false)
	z.flow = _main.flow
	z.target = _main.player
	z.add_to_group("zombies")
	_main.add_child(z)
	z.global_position = at
	_main.rounds.alive().append(z)
	return z


## A point just inside the nearest doorway, which is where a real horde bunches.
func _pile_centre(here: Vector2) -> Vector2:
	var best := here + Vector2(2.5, 0.0)
	var best_d := 1e9
	for d in MapData.DOORS.size():
		var t: Array = MapData.DOORS[d].tiles[0]
		var c := Vector2(float(t[0]) + 0.5, float(t[1]) + 0.5)
		var dist := c.distance_to(here)
		if dist < best_d:
			best_d = dist
			best = c
	return best


## Raw AudioStreamPlayer3D nodes rather than Sfx.play_at(), which pools at 14 —
## the point of this measurement is to find out whether 14 is the right number,
## so it has to be able to exceed it.
func _set_voices(n: int, max_dist: float) -> void:
	for v in _voices:
		if is_instance_valid(v):
			v.queue_free()
	_voices.clear()
	if n <= 0:
		return
	var p: Vector3 = _main.player.global_position
	var stream: AudioStreamWAV = Sfx._stream("groan0")
	# Looping keeps exactly n voices live for the whole stage. A one-shot would
	# decay out and quietly measure fewer voices than the stage claims.
	stream = stream.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	for i in n:
		var a := float(i) / float(n) * TAU
		var v := AudioStreamPlayer3D.new()
		v.stream = stream
		v.bus = "SFX"
		v.volume_db = -24.0
		v.unit_size = 3.0
		# Match the shipped pool exactly, or the measurement describes a
		# configuration the game never runs. Doppler is dead on web regardless.
		v.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		v.max_polyphony = 1
		# 0.0 means "never culled" — that is the Godot default and the reason
		# this axis exists at all. 20.0 is what Sfx uses for vocalisations.
		v.max_distance = max_dist
		v.position = p + Vector3(cos(a) * 6.0, 1.2, sin(a) * 6.0)
		_main.add_child(v)
		v.play()
		_voices.append(v)


# --- per-stage configuration -------------------------------------------------

## Everything a stage changes about the shipped configuration, in one place, so
## that the teardown of one measurement cannot be forgotten by the next.
func _apply_stage(s: Dictionary) -> void:
	_set_shadow(int(s.shadow), int(s.omni_shadow))
	_set_post(int(s.ssao), int(s.lut))
	_set_emitters(int(s.emitters), int(s.pamount), bool(s.pdepth))
	_set_sprites(int(s.sprites), int(s.tilt))
	_set_rig(String(s.capture), float(s.sign))
	if int(s.flow_doors) == 1:
		for d in MapData.DOORS.size():
			_main.map.open_door(d)
		_main.flow.invalidate()


## The torch is the game's one shadow-casting light. `atlas` is the viewport's
## positional shadow atlas, which is a runtime property — unlike the project
## setting of the same name, which is only read at startup.
func _set_shadow(atlas: int, omni: int) -> void:
	if atlas == -2 and omni < 0:
		return
	var torch: SpotLight3D = _main.player._torch
	if atlas != -2:
		torch.shadow_enabled = atlas > 0
		if atlas > 0:
			get_viewport().positional_shadow_atlas_size = atlas
	if omni >= 0:
		# One room lamp, not all eight. An omni in CubeMap mode is six shadow
		# renders to a spot's one, and Dual Paraboloid ERR_FAILs outright, so a
		# single omni is already the expensive case.
		var lamps: Array = _main.lighting._lamps
		var l: OmniLight3D = lamps[0]
		l.shadow_enabled = omni == 1


## SSAO and the colour LUT, the two halves of `quality_governor.heavy_post()`.
## Toggled here and nowhere else in the project: the shipped build decides this
## once before the first frame, precisely because every combination is a separate
## specialisation of `post.glsl` and there is no program cache on the web.
func _set_post(ssao: int, lut: int) -> void:
	if ssao < 0 and lut < 0:
		return
	var env: Environment = _main.lighting.env()
	if not _lut_read:
		_lut = env.adjustment_color_correction
		_lut_read = true
		# `lighting._make_environment()` only assigns the LUT when
		# `quality_governor.heavy_post()` says yes, and a demoted session or a
		# `--no-post-fx` run answers no. There is then nothing to put back, the
		# "lut" rows are byte-for-byte the "plain" rows, and a flat pair of numbers
		# reads as "the LUT is free" instead of "the LUT was never on". Loud, once.
		if _lut == null:
			_post({"event": "warn",
				"detail": "no colour LUT on the Environment; the lut axis measures nothing"})
	if ssao >= 0:
		env.ssao_enabled = ssao == 1
	if lut >= 0:
		env.adjustment_color_correction = _lut if lut == 1 else null


## Probe-owned emitters, cloned from the shipped blood emitter so the process
## shader, the draw material and the particle behaviour are the ones the game
## actually runs. Only the counts differ — which is the whole point, since
## `fx.gd` fixes `amount` deliberately (changing it reallocates the buffer).
func _set_emitters(n: int, amount: int, depth_sort: bool) -> void:
	if n < 0:
		return
	for p in _emitters:
		if is_instance_valid(p):
			p.queue_free()
	_emitters.clear()
	_burst_t = 0.0
	if n == 0:
		return
	var fx: Node3D = _main.fx
	var pool: Array = fx._impacts
	var src: GPUParticles3D = pool[0]
	var centre: Vector3 = _main.player.global_position
	for i in n:
		var p := GPUParticles3D.new()
		p.name = "ProbeEmit%d" % i
		p.process_material = src.process_material
		p.draw_pass_1 = src.draw_pass_1
		p.amount = amount if amount > 0 else src.amount
		p.lifetime = src.lifetime
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		p.local_coords = false
		# INDEX is what the game ships with; VIEW_DEPTH is the row that prices the
		# CPU depth sort godot#107633 claims stalls on WebGL2 — a claim with no
		# frame-time measurement attached, which is why it is a row and not a rule.
		if depth_sort:
			p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
		else:
			p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# Scattered in front of the player rather than on top of him: an emitter
		# behind the camera is frustum-culled and costs nothing, which would make
		# the ladder measure how many emitters can be *not drawn*.
		var a := float(i) / float(n) * PI - PI * 0.5
		var r := 2.0 + float(i % 5)
		p.position = centre + Vector3(sin(a) * r, 1.0 + float(i % 3) * 0.4, -cos(a) * r)
		_main.add_child(p)
		_emitters.append(p)


## M-BILLBOARD's cost half. Both stages draw the same texture at the same size in
## the same places; the only difference is the material path, which is the thing
## being priced. The art is deliberately a single-frame prop rather than a zombie
## strip, so no atlas-window bookkeeping can differ between the two sides.
func _set_sprites(n: int, tilt: int) -> void:
	if n < 0:
		return
	for s in _sprites:
		if is_instance_valid(s):
			s.queue_free()
	_sprites.clear()
	if n == 0:
		return
	var tex: Texture2D = load(BILLBOARD_TEX)
	var px := 1.6 / float(maxi(1, tex.get_height()))
	var centre: Vector3 = _main.player.global_position
	var fwd: Vector3 = -_main.player.camera().global_transform.basis.z
	var right := Vector3(-fwd.z, 0.0, fwd.x).normalized()
	for i in n:
		var col := float(i % 6) - 2.5
		var row := floorf(float(i) / 6.0)
		var at := centre + fwd * (3.5 + row * 1.6) + right * col * 0.9 \
			+ Vector3(0.0, 0.9, 0.0)
		var node: Node3D
		if tilt == 0:
			var sp := Sprite3D.new()
			sp.texture = tex
			sp.pixel_size = px
			sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			sp.shaded = false
			sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			sp.alpha_scissor_threshold = 0.35
			node = sp
		else:
			var quad := QuadMesh.new()
			quad.size = Vector2(float(tex.get_width()) * px, float(tex.get_height()) * px)
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = _tilt_material(tilt, tex, float(i) * 0.13)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# A billboard is a vertex rotation, so the mesh AABB never turns with
			# it and a corner of the turned quad leaves the box. Same margin the
			# lamp fixtures take, and for the same reason.
			mi.extra_cull_margin = quad.size.x
			node = mi
		node.position = at
		_main.add_child(node)
		_sprites.append(node)


## The ~6-line billboard rebuild SYNTHESIS section 1.5 describes: `SpriteBase3D`
## billboard modes overwrite MODELVIEW_MATRIX with a camera basis plus the model
## translation, so a local Z roll is not ignored — it is unrepresentable. This
## rebuilds the same basis and post-multiplies the roll, which is the only way
## the vault/clamber tilt can exist at all.
##
## `%CAM%` is substituted rather than branched because the question is whether
## `MAIN_CAM_INV_VIEW_MATRIX` *compiles* here: a branch would still reference it.
## Godot's own generated billboard code uses it; `zombie.gd`'s rim shader
## deliberately uses `INV_VIEW_MATRIX` instead, pending exactly this answer.
const TILT_CODE := """shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D tex : filter_nearest, source_color;
uniform float cut = 0.35;
uniform float roll = 0.0;

void vertex() {
	mat4 inv = %CAM%;
	vec3 bx = normalize(cross(vec3(0.0, 1.0, 0.0), inv[2].xyz));
	vec3 by = vec3(0.0, 1.0, 0.0);
	vec3 bz = normalize(cross(inv[0].xyz, vec3(0.0, 1.0, 0.0)));
	float c = cos(roll);
	float s = sin(roll);
	mat4 face = mat4(
		vec4(bx * c + by * s, 0.0),
		vec4(by * c - bx * s, 0.0),
		vec4(bz, 0.0),
		MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * face;
}

void fragment() {
	vec4 t = texture(tex, UV);
	if (t.a < cut) {
		discard;
	}
	ALBEDO = t.rgb;
}
"""

## One Shader per variant and therefore one GLSL compile per variant, however
## many sprites use it — the same bargain `zombie.gd` makes with its rim shader,
## and it matters more in a *cost* measurement, because 24 compiles of identical
## source would be the number instead of the draw cost.
static var _tilt_shaders := {}


func _tilt_material(tilt: int, tex: Texture2D, roll: float) -> ShaderMaterial:
	var builtin := "MAIN_CAM_INV_VIEW_MATRIX" if tilt == 2 else "INV_VIEW_MATRIX"
	if not _tilt_shaders.has(builtin):
		var sh := Shader.new()
		sh.code = TILT_CODE.replace("%CAM%", builtin)
		_tilt_shaders[builtin] = sh
	var shader: Shader = _tilt_shaders[builtin]
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("cut", 0.35)
	m.set_shader_parameter("roll", roll)
	return m


# --- capture rigs ------------------------------------------------------------

## The viewmodel FOV override, verbatim from SYNTHESIS section 4.1, with the one
## thing that document could not state made into a uniform.
##
## `y_sign` of 0 leaves PROJECTION_MATRIX alone: that is the reference frame
## every other stage's verdict is read against, and having it be the *same* mesh
## through the *same* material is what makes "mirrored" and "upside-down"
## answerable rather than a matter of opinion. No POSITION write, no DEPTH write,
## the depth terms untouched — so this is immune to the reverse-Z breakage that
## invalidated every widely-copied viewmodel shader on 4.3+.
const VM_CODE := """shader_type spatial;
render_mode unshaded, cull_back;

// Deliberately not `: source_color`. That hint applies an sRGB decode to a
// Color handed in from GDScript, and the whole grading step downstream is a
// channel-ratio test on primaries — so the value is passed as a raw vec3 and
// arrives in the shader exactly as written.
uniform vec3 tint = vec3(1.0);
uniform float y_sign = 0.0;
uniform float vm_fov = 55.0;

void vertex() {
	if (y_sign != 0.0) {
		float onetanfov = 1.0 / tan(0.5 * radians(vm_fov));
		PROJECTION_MATRIX[0][0] = onetanfov / (VIEWPORT_SIZE.x / VIEWPORT_SIZE.y);
		PROJECTION_MATRIX[1][1] = onetanfov * y_sign;
	}
}

void fragment() {
	ALBEDO = tint;
}
"""

static var _vm_shader: Shader

## Marker colours, chosen so a per-channel classifier can separate them after
## FILMIC tonemapping and the sRGB encode have had their way with them. Pure
## primaries survive both: the hue ratio is what is tested, never the value.
const MARK_RIGHT := Color(1.0, 0.0, 0.0)
const MARK_TOP := Color(0.0, 1.0, 0.0)
const MARK_NEAR := Color(0.0, 0.0, 1.0)
const MARK_BODY := Color(0.55, 0.55, 0.55)


## Builds whichever capture rig the stage asked for and tears down the previous
## one. The two camera-local rigs put every piece under a single `_rig` node so
## the teardown cannot miss one; `shadowcast` is the exception and says so at its
## own builder, because its caster is a real `Zombie` in the "zombies" group and
## is therefore freed by `_clear()` at the top of the next stage, before this
## function is reached at all.
func _set_rig(what: String, sign_y: float) -> void:
	if _rig != null and is_instance_valid(_rig):
		_rig.queue_free()
		_rig = null
	# `billboard` grades a readback but owns no scene furniture of its own — its
	# sprites are `_set_sprites`'s — so it deliberately builds nothing here rather
	# than an empty node nobody frees.
	if what != "vmfov" and what != "mmcolor" and what != "shadowcast":
		return
	_rig = Node3D.new()
	_rig.name = "ProbeRig"
	match what:
		"vmfov":
			_main.player.camera().add_child(_rig)
			_build_vm_rig(sign_y)
		"mmcolor":
			_main.player.camera().add_child(_rig)
			_build_mm_rig()
		"shadowcast":
			_main.add_child(_rig)
			_build_shadowcast_rig()


## Deliberately non-mirror-symmetric and non-vertically-symmetric: a marker to
## the right, a different one on top, a third nearer the lens, and an off-centre
## body. A symmetric test mesh cannot tell a correct override from a mirrored
## one, which is the failure mode this whole measurement exists to catch.
func _build_vm_rig(sign_y: float) -> void:
	if _vm_shader == null:
		var sh := Shader.new()
		sh.code = VM_CODE
		_vm_shader = sh
	# Camera-local: -Z is forward, so everything sits at VM_DIST in front of the
	# lens, which is inside the 0.24 m player capsule radius and therefore inside
	# the geometric no-clip guarantee §4.1 rests on.
	var parts := [
		[MARK_BODY, Vector3(0.020, -0.030, -VM_DIST), Vector3(0.060, 0.036, 0.100)],
		[MARK_RIGHT, Vector3(0.062, -0.030, -VM_DIST), Vector3(0.018, 0.018, 0.018)],
		[MARK_TOP, Vector3(0.020, 0.004, -VM_DIST), Vector3(0.018, 0.018, 0.018)],
		# In front of the body AND on the same screen point as the body's centre.
		# The second half is the part that is easy to get wrong: the same x and y
		# at a nearer z does *not* land on the same pixel, because the perspective
		# divide is by z — a marker at 0.080 m carrying the body's own 0.020 /
		# -0.030 offsets projects 1.9x further from the optical axis and clears the
		# body almost entirely, leaving a fifteen-pixel sliver of overlap that
		# proves nothing. Scaled by VM_NEAR_Z / VM_DIST it sits dead centre of the
		# body instead, and both points scale by the same factor when the override
		# is applied, so the occlusion holds at every y_sign. That is what makes
		# "the blue marker stopped covering the body" a statement about the depth
		# terms — the one thing this shader deliberately does not touch — rather
		# than a statement about framing.
		[MARK_NEAR,
			Vector3(0.020 * VM_NEAR_Z / VM_DIST, -0.030 * VM_NEAR_Z / VM_DIST, -VM_NEAR_Z),
			Vector3(0.014, 0.014, 0.014)],
	]
	for part: Array in parts:
		var col: Color = part[0]
		var at: Vector3 = part[1]
		var box := BoxMesh.new()
		box.size = part[2]
		var m := ShaderMaterial.new()
		m.shader = _vm_shader
		m.set_shader_parameter("tint", Vector3(col.r, col.g, col.b))
		m.set_shader_parameter("y_sign", sign_y)
		m.set_shader_parameter("vm_fov", VM_FOV)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The override moves vertices in clip space, so the engine's own AABB is
		# a lie about where this ends up on screen. Without the margin the whole
		# rig can be culled at exactly the sign that is being tested for.
		mi.extra_cull_margin = 2.0
		mi.position = at
		_rig.add_child(mi)


## M-MMCOLOR's A/B, and the reason it is an A/B rather than one strip: a single
## uniform strip cannot distinguish "the per-instance colour never reached the
## vertex stream" from "the material was not told to read vertex colour". Strip A
## sets `vertex_color_use_as_albedo`; strip B is identical and does not. `fx.gd`
## depends on A working, and was written to degrade to a wrong tint rather than
## to nothing if it does not.
func _build_mm_rig() -> void:
	# An opaque backdrop, so the alpha half of the ramp blends against a known
	# constant instead of against whatever wall happens to be behind the player.
	var bg := QuadMesh.new()
	bg.size = Vector2(1.6, 0.9)
	var bgm := StandardMaterial3D.new()
	bgm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bgm.albedo_color = Color(0.25, 0.25, 0.25)
	var bgi := MeshInstance3D.new()
	bgi.mesh = bg
	bgi.material_override = bgm
	bgi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bgi.position = Vector3(0.0, 0.0, -0.90)
	_rig.add_child(bgi)

	_mm_points.clear()
	for strip in 2:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.vertex_color_use_as_albedo = strip == 0
		mat.disable_receive_shadows = true
		mat.disable_fog = true
		var quad := QuadMesh.new()
		quad.size = Vector2(0.018, 0.10)
		quad.material = mat

		var mm := MultiMesh.new()
		# Order is load-bearing: `transform_format` and `use_colors` each reset
		# the buffer, so setting either after `instance_count` silently discards
		# every instance already written. Same trap `fx.gd` records.
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = quad
		mm.instance_count = MMCOLOR_INSTANCES
		var y := 0.09 if strip == 0 else -0.06
		for i in MMCOLOR_INSTANCES:
			var x := (float(i) - float(MMCOLOR_INSTANCES - 1) * 0.5) * 0.020
			var at := Vector3(x, y, -0.80)
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, at))
			mm.set_instance_color(i, _mm_color(i))
			_mm_points.append(at)
		var mi := MultiMeshInstance3D.new()
		mi.name = "MMStrip%d" % strip
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_rig.add_child(mi)


## Hue across the strip and alpha down it, so one readback answers both halves of
## the question at once. `fx.gd` uses per-instance colour for tint *and* opacity
## — `HOLE_ALPHA` 0.85, `SPLAT_TINT` alpha 0.55 — so an implementation that
## carried RGB and dropped A would still break it.
func _mm_color(i: int) -> Color:
	var f := float(i) / float(MMCOLOR_INSTANCES)
	var c := Color.from_hsv(f, 0.92, 1.0)
	c.a = 1.0 - f * 0.8
	return c


## The instance centres, in camera-local space, so the readback knows where on
## screen to sample without re-deriving the layout.
var _mm_points: Array[Vector3] = []


## Where the caster stands, in world space, decided once for the whole mode.
##
## Both stages have to put it on the *same* tile or the diff is a picture of a
## zombie that moved. Solving it per stage from the live camera basis very nearly
## works — with no input the bob amplitude is zero and the recoil spring is at
## rest, so the camera is genuinely still — but "very nearly" is how this project
## has lost measurements before, and the caster's screen position is also what
## `sc_bbox` is read against. One vector, computed once, used by the rig and by
## the grader.
var _sc_caster := Vector3.ZERO
var _sc_placed := false


## One zombie, on bare floor, inside the torch cone, with the camera held still.
## The measurement is the difference between this frame with the torch shadow on
## and the same frame with it off — a single frame of a sprite on a dark floor
## proves nothing, because a dark patch under a sprite is also just a dark floor.
##
## The caster is a real `Zombie` and therefore a child of Main and a member of the
## "zombies" group, not a child of `_rig`. That is deliberate: it is what makes
## `_clear()` free it at the top of the next stage, which is the same teardown
## every other mode's horde gets.
func _build_shadowcast_rig() -> void:
	if not _sc_placed:
		var p: Player = _main.player
		var fwd: Vector3 = -p.camera().global_transform.basis.z
		var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
		var at: Vector3 = p.global_position + flat * 3.0
		_sc_caster = Vector3(at.x, 0.0, at.z)
		_sc_placed = true
	var z := _spawn_at(_sc_caster, 0)
	# Parked rather than steering: a caster that walks between the two captures
	# turns the diff into a picture of the walk cycle rather than of a shadow.
	z.set_physics_process(false)
	z.set_process(false)
	# And the sprite has to be stopped separately — `AnimatedSprite3D` runs its
	# own clock, so freezing the Zombie's `_process` leaves the pose cycling and
	# the diff would still be a picture of the walk.
	var spr: AnimatedSprite3D = z._sprite
	spr.stop()
	spr.frame = 0


# --- the driver --------------------------------------------------------------

func _process(dt: float) -> void:
	if _main == null or _stage >= _plan.size():
		return
	# Keep the subject alive; dying mid-run would end the measurement.
	_main.player.hp = 1e9
	_tick_bursts(dt)

	_t += dt
	if not _measuring:
		if _t >= _settle:
			_measuring = true
			_t = 0.0
			_on_measure_begin()
		return

	_deltas.append(dt * 1000.0)
	_accum()
	if bool(_plan[_stage].sep):
		_sample_separation()
	if _t >= _measure_len:
		_record()
		_next_stage()


## Probe emitters are one-shot, so something has to keep restarting them or the
## ladder measures how many emitters can sit idle. Costs nothing in every other
## mode, because the pool is empty.
func _tick_bursts(dt: float) -> void:
	if _emitters.is_empty():
		return
	_burst_t -= dt
	if _burst_t > 0.0:
		return
	_burst_t = PARTICLE_PERIOD
	for p in _emitters:
		p.restart()


## Everything a stage does exactly once, at the top of its measurement window:
## the M-WARM trigger (which must be the first frame measured, or the spike lands
## in the settle and is thrown away), the flow batch, and the capture readbacks.
##
## The flow batch and the capture readback both block for tens of milliseconds,
## and that stall lands in the *next* frame's delta — so `worst_ms` on a `flow`
## or a capture row is this function, not the scene. Those rows are read from
## their own `flow_*` / capture fields; their frame-time columns are noise. The
## `warm` trigger is the opposite case: the spike it causes IS the measurement,
## which is why it has to fire here rather than during the settle.
func _on_measure_begin() -> void:
	var s: Dictionary = _plan[_stage]
	var trigger := String(s.trigger)
	if trigger != "":
		_fire_trigger(trigger)
	if int(s.flow_doors) >= 0:
		_measure_flow()
	var cap := String(s.capture)
	if cap != "":
		_capture(cap)


# --- M-WARM ------------------------------------------------------------------

## The first-draw events, fired one per stage so each spike is attributable. All
## three signals are the player's own public API, so this reproduces the exact
## draw the first trigger pull would, without needing synthetic input.
##
## Note for anyone reading a `warm` row: `main.gd`'s `fired` handler rolls the
## muzzle quad's roll from `Rng.VISUAL`. The probe never draws from a stream
## itself, but this second-hand draw does perturb one — harmless in a build that
## ships to nobody, and recorded rather than worked around.
func _fire_trigger(ev: String) -> void:
	var p: Player = _main.player
	var cam: Camera3D = p.camera()
	var fwd: Vector3 = -cam.global_transform.basis.z
	match ev:
		"baseline":
			pass
		"shot":
			p.fired.emit(cam.global_position + fwd * 0.35)
		"flesh":
			p.impact.emit(cam.global_position + fwd * 2.0, false, false)
		"wall":
			_hit_wall(MapData.TX_CONCRETE)
		"metal":
			_hit_wall(MapData.TX_METAL)
		"caster":
			_spawn_at(_ahead(3.0), 0)
		"death":
			var z := _spawn_at(_ahead(2.5), 1)
			z.take_damage(1e9, 0.0)


func _ahead(d: float) -> Vector3:
	var p: Vector3 = _main.player.global_position
	var fwd: Vector3 = -_main.player.camera().global_transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	return Vector3(p.x, 0.0, p.z) + flat * d


## Stand the player in front of a wall of the given texture and spray it.
##
## The teleport is the point rather than a shortcut: a burst fired at a wall on
## the far side of the map is occluded, and a fragment that never rasterises
## compiles no fragment stage — so the measurement would report that the shader
## was already warm when in fact it had never been drawn. This is the same
## reasoning `shader_warmup.gd` spreads its quads apart for.
##
## This writes the player's yaw, which the player otherwise owns alone (rule 7).
## It is the same licence `main.gd::_tick_shot` takes for `--shot`, and it is safe
## for the same reason: in a `warm` run there is no input, no `--shot`, and no
## other writer awake. `tools/perf_native.ps1` refusing to pass `--shot` is what
## keeps that true, and it says so in its own header.
func _hit_wall(tex: int) -> void:
	var found := _find_wall(tex)
	if found.is_empty():
		_post({"event": "warn", "detail": "no wall of texture %d found" % tex})
		return
	var face: Vector3 = found.face
	var normal: Vector3 = found.normal
	var p: Player = _main.player
	p.global_position = face + normal * 1.2
	# A Node3D looks down its own -Z, so turning -Z onto -normal means turning +Z
	# onto +normal, which is atan2(nx, nz) — the same expression `main.gd` uses to
	# hang a chalk plaque out of a wall, and for the same reason.
	p.rotation.y = atan2(normal.x, normal.z)
	p.surface_impact.emit(face, normal)


## A solid tile carrying `tex` with an open 4-neighbour, returned as the point on
## the shared face and the normal pointing out of the wall. `fx.gd` steps half a
## tile back along that normal to read the texture, so the pair has to be stated
## in exactly those terms or it reads the wrong side.
func _find_wall(tex: int) -> Dictionary:
	var m: MapData = _main.map
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(1, MapData.MAPH - 1):
		for x in range(1, MapData.MAPW - 1):
			if not m.is_blocked(x, y):
				continue
			if m.wtex[MapData.ix(x, y)] != tex:
				continue
			for d: Vector2i in dirs:
				if m.is_blocked(x + d.x, y + d.y):
					continue
				var face := Vector3(float(x) + 0.5 + float(d.x) * 0.5, 1.2,
					float(y) + 0.5 + float(d.y) * 0.5)
				return {"face": face, "normal": Vector3(float(d.x), 0.0, float(d.y))}
	return {}


# --- M-FLOW ------------------------------------------------------------------

## Worst case by construction: solve from the tile furthest from any wall, which
## is the source whose wavefront has to travel furthest before it meets anything
## that stops it.
##
## **The native number is a lower bound, not a translation of the web one.**
## `FlowField.solve()` writes its distances into a `PackedInt32Array` but drives
## the sweep off `var q: Array[int] = [start]` and grows it with `append()` — up
## to one entry per open tile — so a solve is a heap allocation and a GDScript
## `Array` reallocation as well as integer arithmetic, and single-threaded wasm is
## not obliged to keep the same ratio on either. The reason to run this natively
## anyway is that it is cheap and it brackets the answer from below; the reason to
## run the same mode on web is that only that one is the answer.
func _measure_flow() -> void:
	var f: FlowField = _main.flow
	var origin := _open_tile_furthest_from_wall()
	var ms := PackedFloat32Array()
	for _i in FLOW_SOLVES:
		var t0 := Time.get_ticks_usec()
		f.solve(origin)
		ms.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	# Leave the field as the game expects to find it rather than solved from a
	# corner of the map nobody is standing in.
	f.invalidate()
	var sorted: Array[float] = []
	for v in ms:
		sorted.append(v)
	sorted.sort()
	var reachable := 0
	for i in MapData.MAPW * MapData.MAPH:
		if f.dist[i] >= 0:
			reachable += 1
	_extra["flow_origin"] = "%d,%d" % [origin.x, origin.y]
	_extra["flow_solves"] = FLOW_SOLVES
	var n := sorted.size()
	_extra["flow_min_ms"] = snappedf(sorted[0], 0.001)
	_extra["flow_median_ms"] = snappedf(sorted[int(float(n) * 0.5)], 0.001)
	_extra["flow_p99_ms"] = snappedf(sorted[mini(n - 1, int(float(n) * 0.99))], 0.001)
	_extra["flow_max_ms"] = snappedf(sorted[n - 1], 0.001)
	_extra["flow_reachable_tiles"] = reachable


## Multi-source BFS out of every blocked tile at once, so one sweep gives every
## open tile its distance to the nearest wall. 1428 cells; it costs less than one
## of the 200 solves it is choosing an origin for.
func _open_tile_furthest_from_wall() -> Vector2i:
	var m: MapData = _main.map
	var n := MapData.MAPW * MapData.MAPH
	var d := PackedInt32Array()
	d.resize(n)
	d.fill(-1)
	var q := PackedInt32Array()
	for y in MapData.MAPH:
		for x in MapData.MAPW:
			if m.is_blocked(x, y):
				var i := MapData.ix(x, y)
				d[i] = 0
				q.append(i)
	var head := 0
	var best := Vector2i(MapData.SPAWN_TILE.x, MapData.SPAWN_TILE.y)
	var best_d := -1
	while head < q.size():
		var i: int = q[head]
		head += 1
		var x := i % MapData.MAPW
		var y := i / MapData.MAPW
		if d[i] > best_d:
			best_d = d[i]
			best = Vector2i(x, y)
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := x + step.x
			var ny := y + step.y
			if nx < 0 or ny < 0 or nx >= MapData.MAPW or ny >= MapData.MAPH:
				continue
			var ni := MapData.ix(nx, ny)
			if d[ni] >= 0:
				continue
			d[ni] = d[i] + 1
			q.append(ni)
	return best


# --- M-SEP -------------------------------------------------------------------

var _sep_samples: Array[float] = []
var _sep_clamped := 0

## Recomputed here rather than read off the zombie, because `_separation()`
## returns the value *after* `limit_length(SEPARATION_LIMIT)` and the question is
## how far past the limit the raw sum reaches. Both are recorded: the raw
## percentiles say whether the clamp is load-bearing, and the clamped fraction
## says how often it actually fires.
##
## This is a copy of `Zombie._separation()`'s inner loop and it will rot if that
## changes. Cited by symbol rather than by line deliberately — zombie.gd is under
## active edit and every line number in this project's notes has drifted at least
## once. There is a `verify.gd` assertion proposed alongside this file that pins
## the three constants and the clamp behaviour, so the rot is loud, not silent.
func _sample_separation() -> void:
	var alive: Array = _main.rounds.alive()
	var radius: float = Zombie.SEPARATION_RADIUS
	var limit: float = Zombie.SEPARATION_LIMIT
	for a in alive:
		if not is_instance_valid(a):
			continue
		var here := Vector2(a.global_position.x, a.global_position.z)
		var push := Vector2.ZERO
		for b in alive:
			if b == a or not is_instance_valid(b):
				continue
			var o := Vector2(b.global_position.x, b.global_position.z)
			var d := here - o
			var l := d.length()
			if l > 0.001 and l < radius:
				push += d / l * (1.0 - l / radius)
		var mag := push.length()
		_sep_samples.append(mag)
		if mag > limit:
			_sep_clamped += 1


func _record_separation() -> void:
	if _sep_samples.is_empty():
		return
	var s := _sep_samples.duplicate()
	s.sort()
	var n := s.size()
	var force: float = Zombie.SEPARATION_FORCE
	_extra["sep_samples"] = n
	_extra["sep_p50"] = snappedf(s[int(float(n) * 0.5)], 0.001)
	_extra["sep_p90"] = snappedf(s[mini(n - 1, int(float(n) * 0.90))], 0.001)
	_extra["sep_p99"] = snappedf(s[mini(n - 1, int(float(n) * 0.99))], 0.001)
	_extra["sep_max"] = snappedf(s[n - 1], 0.001)
	_extra["sep_clamped_frac"] = snappedf(float(_sep_clamped) / float(n), 0.001)
	# The decision rule from SYNTHESIS section 5 is stated against the *scaled*
	# term, because what matters is its size next to the unit-length flow vector
	# that it is added to. Scaling here means nobody has to remember to.
	_extra["sep_p90_scaled"] = snappedf(s[mini(n - 1, int(float(n) * 0.90))] * force, 0.001)
	_extra["sep_limit_scaled"] = snappedf(Zombie.SEPARATION_LIMIT * force, 0.001)


# --- capture readbacks -------------------------------------------------------

## Reads the viewport back and grades it. Called from `_process`, one full settle
## after the rig went up, so the last completed frame already contains it and no
## `RenderingServer.frame_post_draw` await is needed — unlike `main.gd`'s
## `--shot`, which captures on a specific frame index and therefore does race the
## renderer.
##
## Returns nothing under `--headless`, where there is no frame to read. That case
## is recorded as `capture: "unavailable"` rather than graded as a result,
## because a verdict derived from an empty image is exactly the kind of number
## that looks like an answer and is not.
func _capture(what: String) -> void:
	var img := _grab()
	if img == null:
		_extra["capture"] = "unavailable"
		return
	_extra["capture"] = what
	_extra["shot_w"] = img.get_width()
	_extra["shot_h"] = img.get_height()
	# The stage index rather than the label, because a label carries spaces and a
	# plus sign and this has to be a filename on three platforms. The label is in
	# the row next to `shot`, so the pairing is one column away.
	var path := "%s%s-%d.png" % [_shot_dir, _mode, _stage]
	var err := img.save_png(path)
	if err == OK:
		_extra["shot"] = path
	else:
		# Almost always a `--perf-shots` directory that does not exist. Silence
		# here means the three modes whose deliverable is a PNG produce a verdict
		# and no picture to check it against, which is the wrong way round.
		_extra["shot"] = "FAILED err=%d %s" % [err, path]
		_post({"event": "warn", "detail": "save_png failed (%d) for %s" % [err, path]})
	match what:
		"vmfov":
			_grade_vmfov(img)
		"mmcolor":
			_grade_mmcolor(img)
		"shadowcast":
			_grade_shadowcast(img)
		"billboard":
			_grade_billboard(img)


func _grab() -> Image:
	var vp := get_viewport()
	if vp == null:
		return null
	var tex := vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.get_width() == 0 or img.get_height() == 0:
		return null
	return img


## Marker centroids, in pixels, for whichever of the three primaries dominates.
## The test is a channel *ratio*, never a value: FILMIC and the sRGB encode both
## move the values a long way and neither reorders the channels.
func _centroid(img: Image, ch: int) -> Dictionary:
	var sx := 0.0
	var sy := 0.0
	var n := 0
	var w := img.get_width()
	var h := img.get_height()
	# Every fourth pixel on each axis. A centroid does not need every sample, and
	# a full 1280x720 scan in GDScript is a second of stall per stage. The channel
	# is picked with a match rather than by indexing a `[r, g, b]` array, because
	# that array would be allocated once per sampled pixel — tens of thousands of
	# allocations to avoid three lines.
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			var mine := c.r
			var a := c.g
			var b := c.b
			match ch:
				1:
					mine = c.g
					a = c.r
				2:
					mine = c.b
					a = c.r
					b = c.g
			if mine > 0.20 and mine > a * 1.8 and mine > b * 1.8:
				sx += float(x)
				sy += float(y)
				n += 1
			x += 4
		y += 4
	if n == 0:
		return {"n": 0, "x": -1.0, "y": -1.0}
	return {"n": n, "x": sx / float(n), "y": sy / float(n)}


## The M-VMFOV verdict, stated so that a `--shot` PNG and this row say the same
## thing and neither is a matter of opinion.
##
## **`rg_dx` and `rg_dy` are the two numbers that answer the question.** They are
## the red marker's position minus the green marker's, in pixels, and being
## marker-to-marker rather than marker-to-screen-centre they cannot be moved by
## anything that merely shifts the rig. In the rig's own geometry red is 0.042 m
## to the right of green and 0.034 m below it, so with the frame the right way up
## `rg_dx` is positive and `rg_dy` is positive (image rows grow downward). Read
## against the reference stage, `rg_dx` flipping sign is a **mirror** and `rg_dy`
## flipping sign is an **upside-down** frame, and each is independent of the
## other.
##
## `right_dx` and `top_dy` are the same two markers measured from the screen
## centre instead. They are kept because they say where the rig *is*, which is
## what a person compares the PNG against — but they are the weaker signal:
## green's centre sits only about a dozen pixels off the optical axis, so a
## translation of the whole rig can swamp them where it cannot touch `rg_*`.
##
## `span_px` divided by the reference's span is the magnification the narrower
## viewmodel FOV should be producing — tan(74/2)/tan(55/2) = 1.448 for the
## shipped camera.
func _grade_vmfov(img: Image) -> void:
	var cx := float(img.get_width()) * 0.5
	var cy := float(img.get_height()) * 0.5
	var red := _centroid(img, 0)
	var green := _centroid(img, 1)
	var blue := _centroid(img, 2)
	_extra["red_px"] = int(red.n)
	_extra["green_px"] = int(green.n)
	_extra["blue_px"] = int(blue.n)
	if int(red.n) == 0 or int(green.n) == 0:
		# Which is itself a result: the override can push the whole rig outside
		# the frustum, and "nothing is drawn" is the third of the three outcomes
		# SYNTHESIS section 5 asks the decision rule to distinguish.
		_extra["vm_verdict"] = "markers not visible"
		return
	var rx: float = red.x
	var ry: float = red.y
	var gx: float = green.x
	var gy: float = green.y
	_extra["rg_dx"] = snappedf(rx - gx, 0.1)
	_extra["rg_dy"] = snappedf(ry - gy, 0.1)
	_extra["right_dx"] = snappedf(rx - cx, 0.1)
	_extra["top_dy"] = snappedf(gy - cy, 0.1)
	_extra["span_px"] = snappedf(Vector2(rx - gx, ry - gy).length(), 0.1)
	var cam_fov: float = _main.player.camera().fov
	_extra["expected_span_ratio"] = snappedf(
		tan(deg_to_rad(cam_fov * 0.5)) / tan(deg_to_rad(VM_FOV * 0.5)), 0.001)
	_extra["blue_visible"] = int(blue.n) > 0
	_extra["vm_verdict"] = "rg_dx/rg_dy against the reference row decide it; span_px checks the scale"


## The M-MMCOLOR verdict. Strip 0 reads vertex colour as albedo and strip 1 does
## not; both carry the same 32-instance ramp. Sampled at the projected centre of
## every instance, which is exact because these use the ordinary projection.
##
## Absolute colours are not compared to the values written — they have been
## through FILMIC, glow, SSAO and the LUT by the time they reach the framebuffer.
## What is compared is how many *distinct* values came back, which is the only
## part of the question that survives grading.
func _grade_mmcolor(img: Image) -> void:
	var cam: Camera3D = _main.player.camera()
	var w := img.get_width()
	var h := img.get_height()
	var seen := [{}, {}]
	# PackedStringArray rather than Array[String] because the only thing done with
	# it is `String.join()`, whose parameter is a PackedStringArray — handing it a
	# typed Array relies on an implicit Variant conversion that is not worth
	# discovering the limits of in a file nobody can compile here.
	var samples := PackedStringArray()
	for i in _mm_points.size():
		var local: Vector3 = _mm_points[i]
		var world: Vector3 = cam.global_transform * local
		var p := cam.unproject_position(world)
		var x := clampi(int(p.x), 0, w - 1)
		var y := clampi(int(p.y), 0, h - 1)
		var c := img.get_pixel(x, y)
		var strip := 0 if i < MMCOLOR_INSTANCES else 1
		# Quantised to 5 bits a channel: two adjacent hues in a 32-step ramp are
		# far more than one quantum apart, so this counts genuinely distinct
		# instances and not dither.
		var key := "%d,%d,%d" % [int(c.r * 31.0), int(c.g * 31.0), int(c.b * 31.0)]
		var bucket: Dictionary = seen[strip]
		bucket[key] = true
		if i % 8 == 0:
			samples.append("s%d[%d]=%s" % [strip, i % MMCOLOR_INSTANCES, key])
	var a: Dictionary = seen[0]
	var b: Dictionary = seen[1]
	_extra["mm_distinct_albedo"] = a.size()
	_extra["mm_distinct_no_albedo"] = b.size()
	_extra["mm_samples"] = ", ".join(samples)
	# Half the instances is a deliberately loose bar. Two adjacent hues can land in
	# the same 5-bit bucket after grading, and a strip that came back with sixteen
	# distinct values has already answered the question — the failure being tested
	# for is one value, not thirty-one.
	if a.size() >= int(float(MMCOLOR_INSTANCES) * 0.5) and b.size() <= 2:
		_extra["mm_verdict"] = "set_instance_color reaches the fragment; vertex_color_use_as_albedo is the gate"
	elif a.size() <= 2:
		_extra["mm_verdict"] = "FAIL: per-instance colour does not reach the fragment"
	else:
		_extra["mm_verdict"] = "ambiguous — read the PNG"


## The M-SHADOWCAST verdict. The two stages differ in exactly one property, so
## every pixel that got darker between them is something the torch shadow did.
## The first stage stores its image; the second diffs against it.
func _grade_shadowcast(img: Image) -> void:
	if _shadow_ref == null:
		_shadow_ref = img
		_extra["sc_verdict"] = "reference frame stored"
		return
	var w := mini(img.get_width(), _shadow_ref.get_width())
	var h := mini(img.get_height(), _shadow_ref.get_height())
	var darker := 0
	var total := 0
	var min_y := h
	var max_y := 0
	var min_x := w
	var max_x := 0
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var before := _shadow_ref.get_pixel(x, y)
			var after := img.get_pixel(x, y)
			total += 1
			# Luminance rather than any single channel: a sodium-lit floor moves
			# in all three at once and a per-channel test would count a hue shift
			# as a shadow.
			var lb := before.r * 0.2126 + before.g * 0.7152 + before.b * 0.0722
			var la := after.r * 0.2126 + after.g * 0.7152 + after.b * 0.0722
			if lb - la > 0.02:
				darker += 1
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
				min_y = mini(min_y, y)
				max_y = maxi(max_y, y)
			x += 2
		y += 2
	var cam: Camera3D = _main.player.camera()
	# `_sc_caster`, not a fresh `_ahead(3.0)`: the grader must describe the body
	# that is actually standing there, not recompute where one would go if it were
	# placed now. 0.9 m up it is roughly mid-chest on a 1.82 m walker.
	var caster := _sc_caster + Vector3(0.0, 0.9, 0.0)
	var sp := cam.unproject_position(caster)
	_extra["sc_darker_px"] = darker
	_extra["sc_sampled_px"] = total
	_extra["sc_darker_frac"] = snappedf(float(darker) / float(maxi(1, total)), 0.0001)
	_extra["sc_bbox"] = "%d,%d %dx%d" % [min_x, min_y, maxi(0, max_x - min_x),
		maxi(0, max_y - min_y)]
	_extra["sc_caster_screen"] = "%d,%d" % [int(sp.x), int(sp.y)]
	if darker == 0:
		_extra["sc_verdict"] = "nothing darkened — no shadow cast, or the caster is outside the cone"
	else:
		_extra["sc_verdict"] = "read sc_bbox against sc_caster_screen, then look at both PNGs"


## The shadows-off frame, kept so the shadows-on stage has something to diff
## against. Held across stages, so it is a member rather than part of `_extra`,
## which is cleared per stage.
var _shadow_ref: Image


## M-BILLBOARD's compile half, folded into the cost ladder so one run answers
## both. A shader that fails to build renders nothing at all here, so the count
## of pixels the sprites cover is the whole test: the two tilt stages must agree
## with each other, and both must be in the same neighbourhood as the
## `SpriteBase3D` control.
func _grade_billboard(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var lit := 0
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			# The prop art is a bright warm token against a very dark level; a
			# luminance gate is enough to separate it and needs no reference.
			if c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722 > 0.30:
				lit += 1
			x += 2
		y += 2
	_extra["bb_lit_px"] = lit
	_extra["bb_sprites"] = _sprites.size()
	_extra["bb_verdict"] = "compare lit_px across the three rows; 0 means the shader did not build"


# --- accumulation and reporting ----------------------------------------------

const MONITORS := {
	"draw_calls": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
	# The direct signal for M-SHADOW2: in Compatibility every shadow-casting
	# light adds one full additive re-draw of every instance it touches, so this
	# is what rises when a second shadowed light is enabled — frame rate is a
	# lagging, noisier version of the same fact.
	"objects": Performance.RENDER_TOTAL_OBJECTS_IN_FRAME,
	"primitives": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
	"video_mem_mb": Performance.RENDER_VIDEO_MEM_USED,
	"static_mem_mb": Performance.MEMORY_STATIC,
	"process_ms": Performance.TIME_PROCESS,
	"physics_ms": Performance.TIME_PHYSICS_PROCESS,
	"nodes": Performance.OBJECT_NODE_COUNT,
	# If this rises as N^2 rather than N, boid separation and the broadphase are
	# fighting each other and the pile is the wrong shape for this backend.
	"collision_pairs": Performance.PHYSICS_3D_COLLISION_PAIRS,
	"active_objects": Performance.PHYSICS_3D_ACTIVE_OBJECTS,
}


func _accum() -> void:
	_mon_n += 1
	for key in MONITORS:
		_mon[key] = _mon.get(key, 0.0) + Performance.get_monitor(MONITORS[key])


## One HTTPRequest per message — a single node can only carry one in flight.
func _post(obj: Dictionary) -> void:
	var body := JSON.stringify(obj)
	print("PERF: ", body)
	var r := HTTPRequest.new()
	add_child(r)
	r.request(ENDPOINT, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)


func _pct(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	var i := clampi(int(sorted.size() * p), 0, sorted.size() - 1)
	return snappedf(sorted[i], 0.01)


func _record() -> void:
	if bool(_plan[_stage].sep):
		_record_separation()
	var d := _deltas.duplicate()
	d.sort()
	var sum := 0.0
	for v in d:
		sum += v
	var mean: float = sum / maxf(1.0, d.size())
	var worst := 0.0
	if not d.is_empty():
		worst = snappedf(d[d.size() - 1], 0.01)
	var s: Dictionary = _plan[_stage]
	var row := {
		"label": String(s.label),
		"zombies": int(s.zombies),
		"collide": bool(s.collide),
		"voices": int(s.voices),
		"max_dist": float(s.max_dist),
		"frames": d.size(),
		"avg_fps": snappedf(1000.0 / maxf(0.001, mean), 0.1),
		"mean_ms": snappedf(mean, 0.01),
		"median_ms": _pct(d, 0.50),
		"p95_ms": _pct(d, 0.95),
		"p99_ms": _pct(d, 0.99),
		"worst_ms": worst,
		# Message pressure shows up as rising p99 against a flat median long
		# before anything is audible, so the ratio is the signal, not the mean.
		"audio_latency_ms": snappedf(AudioServer.get_output_latency() * 1000.0, 0.1),
		# Per row, not just once in `env`. `_freeze_governor()` should hold this
		# still for the whole run, and this column is how that is checked rather
		# than assumed — two rows of a ladder at different render scales are two
		# measurements wearing one label.
		"render_scale": snappedf(get_viewport().scaling_3d_scale, 0.01),
	}
	row["jitter"] = snappedf(float(row.p99_ms) / maxf(0.001, float(row.median_ms)), 0.01)
	# The axis fields, so a row is self-describing in the JSON without anyone
	# having to line it up against the plan that produced it.
	for k: String in ["shadow", "omni_shadow", "ssao", "lut", "emitters", "pamount",
			"sprites", "tilt"]:
		if int(s[k]) != int(STAGE_DEFAULTS[k]):
			row[k] = int(s[k])
	if bool(s.pdepth):
		row["draw_order"] = "view_depth"
	for k in _mon:
		var avg: float = _mon[k] / maxf(1.0, _mon_n)
		if k.ends_with("_mb"):
			row[k] = snappedf(avg / 1048576.0, 0.1)
		elif k.ends_with("_ms"):
			row[k] = snappedf(avg * 1000.0, 0.02)
		else:
			row[k] = int(avg)
	for k in _extra:
		row[k] = _extra[k]
	_results.append(row)
	_post({"event": "stage", "mode": _mode, "data": row})


func _space_class() -> String:
	var w := get_viewport().get_world_3d()
	if w == null or w.direct_space_state == null:
		return "?"
	return w.direct_space_state.get_class()


## The accepted values for physics/3d/physics_engine, straight from the setting's
## own property hint. An unrecognised name here does not fail — it falls back.
func _engine_hint() -> String:
	for p in ProjectSettings.get_property_list():
		if p.get("name", "") == "physics/3d/physics_engine":
			return str(p.get("hint_string", "?"))
	return "?"


func _finish() -> void:
	# Capture modes on web are held rather than torn down: the deliverable there
	# is the tab, because the browser sandbox makes getting a PNG out more
	# machinery than asking someone to look at the screen. `?sign=` selects one
	# configuration so the thing on screen is the thing the row describes.
	var hold := OS.has_feature("web") and not _plan.is_empty() \
		and not String(_plan[_plan.size() - 1].capture).is_empty()
	if not hold:
		_clear()
		_set_voices(0, 0.0)
		_set_emitters(0, 0, false)
		_set_sprites(0, 0)
	var vp := get_viewport().get_visible_rect().size
	var env: Environment = _main.lighting.env()
	var payload := {
		"env": {
			"mode": _mode,
			"platform": OS.get_name(),
			"adapter": RenderingServer.get_video_adapter_name(),
			"api": RenderingServer.get_video_adapter_api_version(),
			# Ask the server what it is ACTUALLY running, not what the project
			# setting says. The setting has no `.web` override, so it reported
			# "forward_plus" in builds that were really on gl_compatibility —
			# every number this probe ever emitted carried the wrong label.
			# Note for anyone reading a headless run: these report what the engine
			# was CONFIGURED with, not that anything was drawn. Under --headless
			# they still say gl_compatibility/opengl3 while draw_calls is 0 and
			# video_mem is 0, and the frame time is a low-processor sleep target
			# rather than work — so `physics_ms` is the only load-bearing timing
			# number in a headless run.
			"renderer": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"display_server": DisplayServer.get_name(),
			"physics": ProjectSettings.get_setting("physics/3d/physics_engine", "?"),
			# The setting above is only what was ASKED for. An unrecognised name
			# falls back silently, so a backend comparison that trusts it can
			# compare a backend against itself and call the result a tie. This is
			# the concrete server that actually got instantiated.
			# PhysicsServer3D.get_class() is no use here — it returns the wrapper
			# name for every backend. The space state is a concrete object owned by
			# whichever server actually got instantiated, so its class name is the
			# one thing that distinguishes them, and the hint string is the
			# authoritative list of names the setting will accept. Without both, a
			# backend comparison can silently compare a backend against itself.
			"physics_server": _space_class(),
			"physics_choices": _engine_hint(),
			"threads": OS.get_processor_count(),
			"viewport": "%dx%d" % [vp.x, vp.y],
			# Every one of these describes the configuration the numbers above
			# were taken under, and every one of them has been wrong in a
			# committed result at least once. A row without its configuration is
			# not a measurement.
			"render_scale": snappedf(get_viewport().scaling_3d_scale, 0.01),
			"msaa_3d": int(get_viewport().msaa_3d),
			"shadow_atlas": get_viewport().positional_shadow_atlas_size,
			"torch_shadow": bool(_main.player._torch.shadow_enabled),
			"ssao_enabled": env.ssao_enabled,
			"lut_enabled": env.adjustment_color_correction != null,
			"glow_enabled": env.glow_enabled,
			"warmup_disabled": _warmup_off(),
			# False means `quality_governor` was left running and the render
			# scale was free to move under the ladder — read every row's own
			# `render_scale` column before comparing any two rows.
			"governor_frozen": _gov_frozen,
			"camera_fov": _main.player.camera().fov,
			# get_ticks_msec() is time since engine start, so this is a real
			# duration: engine init through to the probe taking control.
			"boot_to_probe_ms": _boot_ms,
			"max_fps_setting": Engine.max_fps,
			"settle_s": _settle,
			"measure_s": _measure_len,
		},
		"stages": _results,
	}
	payload["event"] = "final"
	_post(payload)
	if hold:
		# Nothing else to do; the rig stays on screen and the tab is the report.
		_stage = _plan.size()
		return
	_main = null
	# On web the tab stays open and the run is over. Natively nothing else ends
	# the process, so a scripted matrix run hangs on the first engine until its
	# harness times out and kills it — which is how the first M-PHYS pass got its
	# numbers and then sat there for ten minutes. Give the POST a frame to leave
	# the socket before quitting, or the final payload is lost to the shutdown.
	if not OS.has_feature("web"):
		await get_tree().create_timer(1.5).timeout
		get_tree().quit()
