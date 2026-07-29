extends Node

## Automatic render-scale governor — the one mechanism in the ancestor that made
## the build survive a bad machine.
##
## kriegsnacht.html 3379-3388 counted frames over a rolling 1.4 s window and gave
## up one step of its three-step internal resolution whenever the average fell
## under 38:
##
##     frames++; fpsT += dt;
##     if(fpsT > 1.4){ if(frames/fpsT < 38 && quality > 0){ quality--; resize(); } frames=0; fpsT=0; }
##
## The same window drives `Viewport.scaling_3d_scale` here. That rescales the 3D
## render target only: the HUD, the window and the pointer are untouched, which
## is why it is the one quality knob worth moving at runtime.
##
## At runtime it moves the render scale and nothing else, deliberately. Glow,
## SSAO and the colour LUT all look like quality knobs and all are traps — WebGL
## 2.0 exposes no program-binary API, so Godot compiles the GLES3 program cache
## out on web entirely, and every one of those toggles is a full-screen shader
## compiled from GLSL on the main thread, mid-frame. A governor that reached for
## them would hitch a struggling machine harder at the exact moment it is already
## struggling.
##
## `heavy_post()` below is the one exception, and it is an exception precisely
## because it is not a runtime toggle: it is answered once, before the first
## frame is drawn, so the variant it selects compiles behind the title screen
## with all the others. Nothing in `_process` may ever touch it.
##
## This carries more weight than it did in the ancestor: the build ships to
## GitHub Pages on single-threaded WebGL2, to unknown consumer hardware, with no
## telemetry to tell us it went badly and no settings menu to ask the player to
## turn anything down.

## The ancestor's QUAL = [320, 480, 700] base widths, expressed as a fraction of
## the real target instead of an absolute one.
const STEPS := [0.5, 0.75, 1.0]

const WINDOW := 1.4        # the ancestor's window, unchanged
const DOWN_FPS := 38.0     # the ancestor's threshold, unchanged

## The ancestor's governor only ever ratcheted *down*, and for the ancestor that
## was right: a software rasteriser has no compile phase, so a bad window meant a
## genuinely bad machine, and `resize()` reallocated every framebuffer and LUT it
## owned. Neither holds here. The first seconds of a session are dominated by
## uncached shader compiles that will never happen again — every material, every
## light configuration, the first muzzle flash, the first blood puff — so a
## down-only governor converts a one-off compile storm into a permanently halved
## resolution, on a machine that was fine, with no way for the player to undo it.
##
## So it may climb back, but never symmetrically: a 20 fps dead band (anything
## between the two thresholds is left alone, so a machine that settles at a
## steady 45 never touches the render target again), three consecutive good
## windows against one bad one, and a hard budget of two promotions per session.
## After the budget is spent this is exactly the ancestor's governor. Worst case
## for the whole session is four render-target reallocations, which matters
## because each one is itself a hitch.
const UP_FPS := 58.0
const UP_WINDOWS := 3
const UP_BUDGET := 2

## Entering play does not make the frame times meaningful yet — the warm-up pass
## has only just stopped compiling and the first round has not spawned. Measuring
## through that would demote every machine on the planet.
const SETTLE := 2.5

## No single frame may count as worse than 4 fps. On web the first draw of any
## new material is an uncached compile, and one 700 ms hitch inside a 1.4 s
## window is enough to read a healthy machine as a broken one. Capping the
## contribution rather than dropping the frame keeps a genuinely 3 fps machine
## measurable — it still reports 4 fps and still demotes.
const SPIKE := 0.25

var _step := STEPS.size() - 1
var _frames := 0
var _elapsed := 0.0
var _good := 0
var _up_left := UP_BUDGET
var _settle := SETTLE

## `main.restart()` is `reload_current_scene()`, so dying destroys this node and
## builds a fresh one. Without somewhere outside the scene to keep the verdict, a
## bad machine re-learns it after every death — four seconds of exactly the frame
## rate that killed the player — and UP_BUDGET silently becomes a per-life
## allowance instead of the per-session one the comment above promises, which is
## what bounds the number of render-target reallocations. Statics live on the
## script, and `main.gd` holds a `preload` reference to it, so they outlive the
## scene; only a page reload clears them.
static var _kept_step := -1
static var _kept_budget := 0


## Whether this session may pay for the expensive half of the post pass — SSAO
## and the colour-correction LUT. `lighting.gd` asks once, while it is building
## the `Environment`, and never again.
##
## This is the one quality decision that is *not* a runtime knob, and the
## distinction is the whole reason it lives here rather than in `_process`.
## `post.glsl` is specialised on the combination of glow, BCS, SSAO and colour
## correction, so switching either of the last two on or off mid-session is a
## full-screen GLSL compile on the main thread with no program cache behind it —
## the exact hitch this governor exists to avoid, delivered at the moment the
## machine is least able to absorb it. Asked before the first frame, the compile
## instead lands behind the title screen alongside the warm-up pass.
##
## The signal is a verdict this page load has already reached. `_kept_step`
## outlives the scene reload that a death performs, so a machine that could not
## hold full render scale in its last life starts its next one without the two
## effects it can least afford, and pays for that variant behind the title card
## rather than mid-round. A fresh page load starts optimistic, because the
## opening seconds are compile-dominated and would libel a healthy machine.
##
## `--verify` and `--shot` never demote, so both always see the shipping
## configuration and a capture is reproducible.
static func heavy_post() -> bool:
	if _post_forced_off():
		return false
	return _kept_step < 0 or _kept_step >= STEPS.size() - 1


## The manual override exists because M-SSAO needs an A/B — SSAO's cost on
## WebGL2 is unmeasured, and the measurement has to happen in the exported build
## served over HTTP, where there is no command line. So it mirrors the perf
## probe's convention: `?post=off` on web, `--no-post-fx` natively. Paired with
## `--shot` it also gives the before/after frames R1 asks for, of a muzzle flash
## and a machine glow, to check that SSAO is not eating the emissives.
static func _post_forced_off() -> bool:
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("location.search", true)
		if q == null:
			return false
		return "post=off" in str(q)
	return "--no-post-fx" in OS.get_cmdline_args()


func _ready() -> void:
	# A --shot capture has to be reproducible frame for frame, and --verify runs
	# headless where the frame rate describes nothing at all. Neither may be
	# allowed to move the render scale under the thing it is measuring — and
	# neither may inherit a verdict, which is why this sits above the restore.
	var args := OS.get_cmdline_args()
	if "--shot" in args or "--verify" in args:
		set_process(false)
		return
	if _kept_step >= 0:
		_step = _kept_step
		_up_left = _kept_budget
	var vp := get_viewport()
	# Bilinear is the only scaling mode Compatibility implements; FSR1/FSR2 are
	# Forward+ only and fall back silently.
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	# Own the property from the first frame rather than inheriting whatever the
	# project default happens to be — one writer per setting.
	vp.scaling_3d_scale = _scale()


func _process(dt: float) -> void:
	# The load screen, the title card, the pause overlay and the death screen are
	# all measuring the wrong thing: behind the first of them the warm-up pass is
	# deliberately compiling every shader variant in the project, and behind the
	# rest almost nothing is being drawn.
	if Game.state != Game.STATE_PLAY:
		_frames = 0
		_elapsed = 0.0
		_good = 0
		_settle = SETTLE
		return

	if _settle > 0.0:
		_settle -= dt
		return

	_frames += 1
	_elapsed += minf(dt, SPIKE)
	if _elapsed < WINDOW:
		return

	var fps := float(_frames) / _elapsed
	_frames = 0
	_elapsed = 0.0

	if fps < DOWN_FPS:
		_good = 0
		_shift(-1, fps)
		return

	if fps >= UP_FPS and _up_left > 0 and _step < STEPS.size() - 1:
		_good += 1
		if _good >= UP_WINDOWS:
			_good = 0
			_up_left -= 1
			_shift(1, fps)
		return

	_good = 0


func _shift(dir: int, fps: float) -> void:
	var next := clampi(_step + dir, 0, STEPS.size() - 1)
	if next == _step:
		return
	_step = next
	_kept_step = _step
	_kept_budget = _up_left
	get_viewport().scaling_3d_scale = _scale()
	# There is no telemetry from a GitHub Pages build, so the browser console is
	# the only place a report of "it looked blurry" can ever be corroborated.
	print("[quality] render scale -> %.2f (%.0f fps over %.1fs)" % [_scale(), fps, WINDOW])


## STEPS is an untyped Array, so the element has to be annotated on the way out.
func _scale() -> float:
	var s: float = STEPS[_step]
	return s
