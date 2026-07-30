extends CanvasLayer

## The dev console: a drop-down line editor that can put the game into any state
## an iteration loop needs to look at, without playing to it.
##
## The problem it solves is arithmetic. Reaching round 20 to look at round 20 is
## about twenty minutes of play per attempt, so every visual or balance question
## about the late game has, until now, cost twenty minutes to ask once. `round 20`
## costs a keystroke, which is the difference between checking something and
## guessing at it.
##
## **It ships inert.** Availability is `OS.is_debug_build()` AND an explicit
## opt-in: `--console` natively, `?dev=1` on web — the same shape as main.gd's
## `?warm=off` and quality_governor's `?post=off`, because a second convention for
## "turn a build-time decision on for one session" is a second thing to remember.
## An export-release build has `OS.is_debug_build()` false, so the flag alone
## cannot open it in a shipped page.
##
## **It reaches gameplay through a fixed contract and nothing else**: `Game.*`,
## `main.rounds.force_round()` / `spawn_one()` / `alive()`, and `main.player`.
## Every one of those is a name the wave agreed on. Anything it cannot reach
## through them it reaches through `has_method`, so a package that moves a private
## helper turns a command into a printed refusal rather than a crash.
##
## Colours here are DISPLAY space, like the rest of the HUD layer and unlike
## anything 3D in this project: a CanvasLayer is composited after tonemapping, so
## these hex values are the pixels.

## The two ways in. QuoteLeft is the convention; F1 is the fallback for the
## layouts that do not have a backtick anywhere convenient, and neither is bound
## as an InputMap action because project.godot belongs to no package this wave.
const TOGGLE_KEYS: Array = [KEY_QUOTELEFT, KEY_F1]

const SCROLLBACK := 300

const ASH := Color("0b0c0a")
const BONE := Color("d8d2c0")
const SODIUM := Color("e0a62b")
const BLOOD_LIT := Color("c4222a")
const DIM := Color("8c8578")

## Fly speed, and the shift multiplier. Metres a second, so it is comparable with
## Player.SPEED (3.15) — a freecam that moves at the player's pace is useless for
## the thing a freecam is for, which is getting across the map to look at
## something.
const FLY_SPEED := 7.0
const FLY_BOOST := 3.5
const FLY_SENS := 0.0022

var main: Node3D

var _panel: ColorRect
var _out: RichTextLabel
var _line: LineEdit

var _open := false
var _history: Array[String] = []
var _history_at := 0

var _god := false
var _freecam := false
var _cam: Camera3D

## Saved at the moment the console first takes the game and restored when it gives
## it back. Nothing else in the project owns any of the three, so this is one
## writer. `_player_mode_was` is the one that is not obvious — see _sync_hold().
var _held := false
var _paused_was := false
var _mouse_was := Input.MOUSE_MODE_VISIBLE
var _player_mode_was: Node.ProcessMode = Node.PROCESS_MODE_ALWAYS

const COMMANDS := {
	"help": "               list these",
	"round": " <n>          jump to round n",
	"spawn": " <kind> [n]   spawn n of zombie|crawler|hound",
	"give": " <gun> [pap]   hand over a weapon",
	"points": " <n>         set the wallet",
	"perk": " <key>         grant a perk (tab completes the roster)",
	"power": "              throw the generator",
	"god": "                toggle invulnerability",
	"timescale": " <x>      Engine.time_scale",
	"freecam": "            detach the camera and fly (pauses the game)",
	"alive": "              how many are on the map, and in what state",
}

const GUN_KEYS: Array = ["m1911", "olympia", "m14", "mp40", "pm63", "ak74u",
	"stakeout", "m16", "rpk", "chinalake", "raygun", "thundergun"]
## Derived, not listed. `_cmd_perk` has always validated against `Weapons.PERKDEF`
## while the completion pool and the refusal message read this — so the day the
## roster grew from four to six, tab-completion silently stopped offering two perks
## the command would have accepted. A `const` cannot call `.keys()`, hence the
## static and the lazy fill.
static var _perk_keys: Array = []
const SPAWN_KINDS: Array = ["zombie", "crawler", "hound"]


static func perk_keys() -> Array:
	if _perk_keys.is_empty():
		_perk_keys = Weapons.PERKDEF.keys()
	return _perk_keys


## Adds the console to `owner_node` if this build is allowed one, and otherwise
## does nothing at all — so main.gd's wiring is one unconditional line and the
## decision about whether a console exists lives here.
static func install(owner_node: Node3D) -> void:
	if not enabled():
		return
	# load() rather than a class reference: a static function cannot call new() on
	# its own script, and this file carries no class_name because nothing outside
	# main.gd's one wiring line should be naming it.
	var script: GDScript = load("res://scripts/dev/console.gd")
	var c: CanvasLayer = script.new()
	c.name = "DevConsole"
	c.set("main", owner_node)
	owner_node.add_child(c)


## Debug build AND an explicit ask. Both halves matter: the flag alone would let a
## shipped page open it with a query string, and the debug check alone would put a
## console in front of everyone running the project from the editor.
static func enabled() -> bool:
	if not OS.is_debug_build():
		return false
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("location.search", true)
		if q == null:
			return false
		return "dev=1" in str(q)
	return "--console" in OS.get_cmdline_args()


func _ready() -> void:
	# The whole reason this is worth stating: another package is moving this
	# project onto real `get_tree().paused` this same wave, and a console that
	# stops processing at exactly the moment you pause to inspect something is
	# worse than no console. ALWAYS also covers the freecam, which is only useful
	# while the world is held still.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Above the HUD (layer 0) and above anything a later package adds there.
	layer = 128
	_build()
	_say("dev console — backquote or F1 closes it, `help` lists the commands")
	_dim("this build is debug and opted in; a release build has no console at all")


func _build() -> void:
	_panel = ColorRect.new()
	_panel.color = Color(ASH.r, ASH.g, ASH.b, 0.92)
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.42
	# The panel is a backdrop, not a button. A Control spanning the top of the
	# screen at the default MOUSE_FILTER_STOP eats clicks aimed at the game behind
	# it — the same bug verify.gd already pins the HUD against.
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	_out = RichTextLabel.new()
	_out.bbcode_enabled = true
	_out.scroll_following = true
	_out.selection_enabled = true
	_out.anchor_right = 1.0
	_out.anchor_bottom = 1.0
	_out.offset_left = 10.0
	_out.offset_top = 6.0
	_out.offset_right = -10.0
	_out.offset_bottom = -30.0
	_out.add_theme_color_override("default_color", BONE)
	_panel.add_child(_out)

	_line = LineEdit.new()
	_line.anchor_top = 1.0
	_line.anchor_right = 1.0
	_line.anchor_bottom = 1.0
	_line.offset_left = 10.0
	_line.offset_top = -28.0
	_line.offset_right = -10.0
	_line.offset_bottom = -4.0
	_line.placeholder_text = "round 20"
	_line.add_theme_color_override("font_color", SODIUM)
	_line.text_submitted.connect(_submit)
	# History and completion have to be stolen before the LineEdit sees them: it
	# spends Up/Down on the caret and Tab on focus navigation, and all three are
	# the keys a console is expected to answer.
	_line.gui_input.connect(_on_line_input)
	_panel.add_child(_line)

	_panel.visible = false


# --- open / close ------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and TOGGLE_KEYS.has(key.physical_keycode):
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if _open and key != null and key.pressed and key.physical_keycode == KEY_ESCAPE:
		_toggle()
		get_viewport().set_input_as_handled()
		return
	# Mouse look for the freecam, and only while the console is shut and the
	# pointer has actually been captured — otherwise a stray motion event while
	# typing would swing the camera out from under the thing being looked at.
	if _freecam and not _open and _cam != null:
		var motion := event as InputEventMouseMotion
		if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_cam.rotation.y -= motion.relative.x * FLY_SENS
			_cam.rotation.x = clampf(_cam.rotation.x - motion.relative.y * FLY_SENS,
				-1.4, 1.4)
			get_viewport().set_input_as_handled()


func _toggle() -> void:
	_open = not _open
	_panel.visible = _open
	if _open:
		_line.grab_focus()
		_line.clear()
	else:
		_line.release_focus()
	_sync_hold()


## The one place the game is taken and given back. Holding is `open or freecam`,
## because the freecam is only meaningful against a world that is standing still
## and because a captured pointer plus a focused LineEdit is not a state anybody
## wants to be in.
##
## `get_tree().paused` rather than `Game.set_state(STATE_PAUSE)`: the state machine
## is being rewritten around real pause this same wave and the HUD owns the
## pointer-lock watchdogs that drive it, so writing that state from here would put
## a second author on it.
##
## **The tree pause is not enough on its own, and this is measured rather than
## assumed.** `player.gd:140` sets the Player to PROCESS_MODE_ALWAYS so the resume
## click can reach `_unhandled_input`, and its `_physics_process` early-returns on
## `Game.state != STATE_PLAY` — which is still STATE_PLAY here, because this
## deliberately does not write that state. So the player kept running: it polls
## `Input.get_vector` directly, the movement actions are bound to W/A/S/D, and
## `Input`'s action state is set before viewport propagation, so a LineEdit with
## focus does not swallow them. Typing `spawn` walked the player 0.74 m; with the
## freecam on and the console shut it drove the player and the camera at once.
## The Player's process mode is therefore lowered to PAUSABLE for exactly as long
## as the console holds the game, and put back to whatever it was on release — the
## same save-and-restore as the pause flag and the mouse mode above it.
func _sync_hold() -> void:
	var want := _open or _freecam
	var p: Player = main.get("player") if main != null else null
	if want and not _held:
		_paused_was = get_tree().paused
		_mouse_was = Input.mouse_mode
		if p != null:
			_player_mode_was = p.process_mode
			p.process_mode = Node.PROCESS_MODE_PAUSABLE
		_held = true
		get_tree().paused = true
	elif not want and _held:
		_held = false
		get_tree().paused = _paused_was
		if p != null:
			p.process_mode = _player_mode_was
		Input.set_mouse_mode(_mouse_was)
		return
	if _held:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if _open
			else Input.MOUSE_MODE_CAPTURED)


func _on_line_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	match key.physical_keycode:
		KEY_UP:
			_recall(-1)
		KEY_DOWN:
			_recall(1)
		KEY_TAB:
			_complete()
		_:
			return
	_line.accept_event()


func _recall(step: int) -> void:
	if _history.is_empty():
		return
	_history_at = clampi(_history_at + step, 0, _history.size())
	_line.text = "" if _history_at >= _history.size() else _history[_history_at]
	_line.caret_column = _line.text.length()


## Completes the command when there is no space yet, and otherwise the first
## argument out of whichever list that command draws from. Deliberately shallow:
## a completion engine is not what makes a console useful, and one that is wrong
## is worse than none.
func _complete() -> void:
	var text := _line.text
	var parts := text.split(" ", false)
	var pool: Array = COMMANDS.keys()
	var prefix := text
	if parts.size() >= 1 and (text.ends_with(" ") or parts.size() > 1):
		var cmd: String = parts[0]
		pool = _arg_pool(cmd)
		prefix = "" if text.ends_with(" ") else parts[parts.size() - 1]
	var hits: Array[String] = []
	for candidate: String in pool:
		if candidate.begins_with(prefix):
			hits.append(candidate)
	if hits.is_empty():
		return
	if hits.size() > 1:
		_dim(" ".join(PackedStringArray(hits)))
		return
	var done: String = hits[0]
	_line.text = done if prefix == text else text.substr(0, text.length() - prefix.length()) + done
	_line.caret_column = _line.text.length()


func _arg_pool(cmd: String) -> Array:
	match cmd:
		"give":
			return GUN_KEYS
		"perk":
			return perk_keys()
		"spawn":
			return SPAWN_KINDS
	return []


# --- command dispatch --------------------------------------------------------

func _submit(text: String) -> void:
	_line.clear()
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	_history.append(trimmed)
	_history_at = _history.size()
	_say("[color=#%s]> %s[/color]" % [SODIUM.to_html(false), trimmed])
	var parts := trimmed.split(" ", false)
	var cmd: String = parts[0].to_lower()
	# Array(), not the PackedStringArray slice itself: the command handlers take a
	# plain Array and the two types are not interchangeable in a typed signature.
	var args := Array(parts.slice(1))
	if not COMMANDS.has(cmd):
		_err("no such command: %s   (try help)" % cmd)
		return
	match cmd:
		"help":
			_help()
		"round":
			_cmd_round(args)
		"spawn":
			_cmd_spawn(args)
		"give":
			_cmd_give(args)
		"points":
			_cmd_points(args)
		"perk":
			_cmd_perk(args)
		"power":
			_cmd_power()
		"god":
			_cmd_god()
		"timescale":
			_cmd_timescale(args)
		"freecam":
			_cmd_freecam()
		"alive":
			_cmd_alive()


func _help() -> void:
	for cmd: String in COMMANDS:
		_say("  [color=#%s]%s[/color]%s" % [SODIUM.to_html(false), cmd, COMMANDS[cmd]])


## `main.rounds` is the contract this wave fixed, and it does not exist until the
## package that owns main.gd lands. Reported rather than assumed, because the
## alternative is a null dereference in the middle of a dev session.
func _rounds() -> Object:
	if main == null or not ("rounds" in main):
		_err("main.rounds is not wired yet — this command needs the round director")
		return null
	var r: Object = main.get("rounds")
	if r == null:
		_err("main.rounds is null")
	return r


func _cmd_round(args: Array) -> void:
	if args.is_empty() or not String(args[0]).is_valid_int():
		_err("round <n>")
		return
	var director := _rounds()
	if director == null:
		return
	var n: int = maxi(1, int(String(args[0])))
	director.call("force_round", n)
	_say("round %d — %d zombies, %.0f hp each, cap %d"
		% [n, Game.zombie_count(n), Game.zombie_hp(n), Game.max_alive(n)])


func _cmd_spawn(args: Array) -> void:
	var kind: String = String(args[0]) if args.size() > 0 else "zombie"
	if not SPAWN_KINDS.has(kind):
		_err("spawn <%s> [n]" % "|".join(PackedStringArray(SPAWN_KINDS)))
		return
	var n := 1
	if args.size() > 1 and String(args[1]).is_valid_int():
		n = clampi(int(String(args[1])), 1, 64)
	var director := _rounds()
	if director == null:
		return
	for i in n:
		director.call("spawn_one", kind)
	_say("spawned %d %s" % [n, kind])


func _cmd_give(args: Array) -> void:
	if args.is_empty() or not Weapons.TABLE.has(String(args[0])):
		_err("give <%s> [pap]" % "|".join(PackedStringArray(GUN_KEYS)))
		return
	if main == null or main.get("player") == null:
		_err("main.player is not available")
		return
	var pap := args.size() > 1 and String(args[1]).to_lower() in ["pap", "1", "true"]
	var p: Player = main.get("player")
	p.give_gun(String(args[0]), pap)
	_say("gave %s%s" % [args[0], " (Pack-a-Punched)" if pap else ""])


func _cmd_points(args: Array) -> void:
	if args.is_empty() or not String(args[0]).is_valid_int():
		_err("points <n>")
		return
	Game.points = maxi(0, int(String(args[0])))
	Game.points_changed.emit(Game.points)
	_say("points = %d" % Game.points)


func _cmd_perk(args: Array) -> void:
	var key: String = String(args[0]) if args.size() > 0 else ""
	if not Weapons.PERKDEF.has(key):
		_err("perk <%s>" % "|".join(PackedStringArray(perk_keys())))
		return
	Game.perks[key] = true
	if key == "revive":
		Game.revives_left += 1
	var p: Player = main.get("player") if main != null else null
	if key == "jug" and p != null:
		# Juggernog raises the ceiling, and the bar has to be told: the HUD reads
		# max_health() only when health_changed fires.
		p.hp = Game.max_health()
		p.health_changed.emit(p.hp, Game.max_health())
	var perk_name: String = Weapons.PERKDEF[key].name
	Game.toast.emit(perk_name)
	_say("perk %s — %d of %d held" % [key, Game.perk_count(), Game.PERK_CAP])


## Power is more than a flag: the perk machines and the generator change texture,
## the Generator Hall's metal plate lifts, and the lamps run their ceremony. Only
## the first of those is `Game.*`, so the other three are asked for by name,
## mirroring interaction_system.gd's own `"power"` branch — and each is skipped if
## the package that owns it has moved it. Skipped and *reported*, not faked: a
## console that half-does something in silence is how a session ends up debugging
## the console instead of the game. The list already earned that: `_light_perks`
## moved off main and onto `atmos` mid-wave, and this printed which calls it made.
func _cmd_power() -> void:
	Game.power_on = true
	var did: Array[String] = ["Game.power_on"]
	for pair: Array in [["atmos", "light_perks"], ["world", "set_power_on"],
			["lighting", "power_on"]]:
		var holder_name := String(pair[0])
		var method := String(pair[1])
		var holder: Object = main.get(holder_name) if main != null else null
		if holder != null and holder.has_method(method):
			holder.call(method)
			did.append("%s.%s()" % [holder_name, method])
	Game.toast.emit("POWER ON")
	_say("power on — %s" % ", ".join(PackedStringArray(did)))


## Invulnerability is pinned rather than switched, because the switch would have
## to live in `player.take_damage` and player.gd belongs to another package. The
## hit still lands, the wash still flashes, and the health is put back on the same
## frame — see _process.
func _cmd_god() -> void:
	_god = not _god
	_say("god %s%s" % ["ON" if _god else "OFF",
		"  (damage still registers; health is restored each frame)" if _god else ""])


func _cmd_timescale(args: Array) -> void:
	if args.is_empty() or not String(args[0]).is_valid_float():
		_err("timescale <x>   (1.0 is normal)")
		return
	Engine.time_scale = clampf(String(args[0]).to_float(), 0.05, 10.0)
	_say("time_scale = %.2f%s" % [Engine.time_scale,
		"  — note the console holds the tree paused while it is open" if _held else ""])


func _cmd_alive() -> void:
	var director := _rounds()
	if director == null:
		return
	var live: Array = director.call("alive")
	var by_state := {}
	for z: Zombie in live:
		if not is_instance_valid(z):
			continue
		var n: String = Zombie.State.keys()[z.state]
		by_state[n] = int(by_state.get(n, 0)) + 1
	_say("%d alive  %s   round %d, cap %d"
		% [live.size(), by_state, Game.round_no, Game.max_alive()])


# --- freecam -----------------------------------------------------------------

## A second Camera3D that takes the viewport, rather than any change to the
## player's camera chain — Player > Head > RecoilPivot > Camera3D each have
## exactly one writer and this adds none.
##
## Verified against Godot 4.7 headless rather than assumed, because the restore
## path is the half that fails quietly: setting `current = true` on the new camera
## clears the player camera's own `current` flag, and setting it back to false
## hands the viewport to the player's camera again with no further help. Freeing
## the freecam while it is still current does the same. So there is no state to
## put back by hand, and doing so would be a second writer on a flag the engine is
## already managing.
func _cmd_freecam() -> void:
	if main == null:
		_err("no main scene to attach a camera to")
		return
	_freecam = not _freecam
	if _freecam:
		_cam = Camera3D.new()
		_cam.name = "FreeCam"
		_cam.fov = 74.0
		_cam.near = 0.05
		_cam.far = 120.0
		main.add_child(_cam)
		var p: Player = main.get("player")
		if p != null:
			_cam.global_transform = p.camera().global_transform
		_cam.current = true
		_say("freecam ON — WASD, Q/E down/up, shift to boost. The game is held.")
		_dim("close the console to fly; `freecam` again to give it back")
	else:
		if _cam != null and is_instance_valid(_cam):
			_cam.current = false
			_cam.queue_free()
		_cam = null
		_say("freecam OFF")
	_sync_hold()


func _process(dt: float) -> void:
	if _god:
		var p: Player = main.get("player") if main != null else null
		if p != null and is_instance_valid(p) and p.hp < Game.max_health():
			p.hp = Game.max_health()
			p.is_downed = false
			p.health_changed.emit(p.hp, Game.max_health())

	if not _freecam or _open or _cam == null:
		return
	# Polled, not action-driven: `move_forward` and friends are the player's
	# bindings and the player is held, so the InputMap cannot be the source here.
	#
	# PHYSICAL keycodes, like the toggle above and like project.godot's own
	# movement bindings, which are all `physical_keycode` (87 for W). `is_key_pressed`
	# asks which character the key produces, so on AZERTY the freecam would have
	# flown on ZQSD while the player walked on WASD — two different sets of keys for
	# the same four directions in the same build.
	var fwd := (1.0 if Input.is_physical_key_pressed(KEY_W) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(KEY_S) else 0.0)
	var side := (1.0 if Input.is_physical_key_pressed(KEY_D) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(KEY_A) else 0.0)
	var lift := (1.0 if Input.is_physical_key_pressed(KEY_E) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(KEY_Q) else 0.0)
	var speed := FLY_SPEED * (FLY_BOOST if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	var basis := _cam.global_transform.basis
	# `dt` IS scaled by Engine.time_scale, even here. PROCESS_MODE_ALWAYS decides
	# whether a node is stepped while the tree is paused; time_scale is applied to
	# the whole tree's step upstream of that and reaches every node regardless.
	# Measured: with time_scale 0.1 this node saw 0.00046 s against an unscaled
	# 0.0046. Divided back out, because `timescale 0.1` is exactly what somebody
	# types to look at something in slow motion and it must not also make the
	# freecam take ten times as long to fly there.
	var real_dt := dt / maxf(0.01, Engine.time_scale)
	_cam.global_position += (basis.z * -fwd + basis.x * side + Vector3.UP * lift) * speed * real_dt


# --- output ------------------------------------------------------------------

func _say(text: String) -> void:
	_out.append_text(text + "\n")
	# Bounded, or a soak with `spawn` on a loop grows a Control until the tab dies.
	while _out.get_paragraph_count() > SCROLLBACK:
		_out.remove_paragraph(0)


func _err(text: String) -> void:
	_say("[color=#%s]%s[/color]" % [BLOOD_LIT.to_html(false), text])


func _dim(text: String) -> void:
	_say("[color=#%s]%s[/color]" % [DIM.to_html(false), text])
