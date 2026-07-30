extends CanvasLayer

## Title, pause, options and game-over screens — the first real Buttons in this
## project. Until now every screen was a Label and every choice was "click
## anywhere", which meant the game could not be played without a mouse at all.
##
## WHY THIS IS NOT PART OF THE HUD. `--verify` asserts that no full-screen control
## under the HUD accepts the mouse, because the resume click has to reach the
## player's `_unhandled_input` (pointer lock needs transient activation, so the
## re-capture can only be asked for from inside the event). A menu is the exact
## opposite: its panel *must* swallow clicks or every press of OPTIONS would also
## resume the run. Two requirements, two layers. The backdrop stays transparent to
## the mouse so clicking the empty part of the pause screen still resumes, which is
## the gesture the port has taught since Milestone 1.
##
## PROCESS MODE. ALWAYS, not WHEN_PAUSED. Godot gates GUI input on `can_process()`
## exactly as it gates `_process`, and TITLE deliberately does not pause the tree
## (the shader warm-up runs behind it) — so WHEN_PAUSED would give a pause menu
## that works and a title screen whose buttons are dead.
##
## The screens mirror kriegsnacht.html's own set: the keybind table and the
## points-economy hint from the title card (html:258-300), the pause plate
## (html:303-334) and the five game-over statistics (html:3205-3215) — of which
## this port tracks three; see `_stats()`.

## The HUD owns the palette and this file borrows it rather than re-declaring the
## same nine colours next to it. Preload rather than the class name: a freshly
## added script is not in the class registry until the editor rescans.
const HUD := preload("res://scripts/ui/hud.gd")

## html:3225 — the epitaph bands, carried over unchanged.
const EPITAPH := [[15, "Legend"], [10, "Veteran"], [5, "Overrun"], [0, "Devoured"]]

## html:3216-3222, with two corrections. The ancestor's "knifing is a one-hit kill
## for the first four rounds" is false in both codebases — the knife does 150
## (player.gd:790) against a round-2 zombie's 250 (Game.zombie_hp) — and its
## "Esc pauses" line is unfixable in a browser, so P leads here.
const TIPS := [
	"Zombies take the shortest path. Keep moving in circles and they will train up behind you.",
	"The knife does 150 damage and costs no ammunition — a one-hit kill on round one.",
	"The power switch is at the back of the generator hall. No power, no perks.",
	"Juggernog is the single best 2,500 points you will ever spend.",
	"Rebuilding barricades pays 10 points a board. It adds up between rounds.",
	"The Mystery Box moves after a few spins. The teddy bear means it has gone.",
]

const KEYS := [
	["Movement", [["W A S D", "Move"], ["Shift", "Sprint"], ["Mouse", "Look"]]],
	["Combat", [["LMB", "Fire"], ["R", "Reload"], ["V", "Knife"], ["Q", "Swap weapon"]]],
	["Survival", [["F", "Buy · hold to rebuild"], ["L", "Release mouse"], ["P", "Pause"]]],
]

## The options rows, in screen order. `kind` picks the control; `lo`/`hi`/`step`
## are only read for a slider. Driving the build from a table rather than from
## eight hand-written blocks is what keeps the focus chain and the assertion that
## checks it honest — a row added here is a control in the chain automatically.
const ROWS := [
	{"key": "mouse_sens", "label": "Mouse sensitivity", "kind": "slider",
		"lo": 0.25, "hi": 3.0, "step": 0.05, "suffix": "x"},
	{"key": "fov", "label": "Field of view", "kind": "slider",
		"lo": 60.0, "hi": 110.0, "step": 1.0, "suffix": "°"},
	{"key": "master_volume", "label": "Master volume", "kind": "percent",
		"lo": 0.0, "hi": 1.0, "step": 0.05, "suffix": "%"},
	{"key": "sfx_volume", "label": "Effects volume", "kind": "percent",
		"lo": 0.0, "hi": 1.0, "step": 0.05, "suffix": "%"},
	{"key": "reduce_motion", "label": "Reduce motion", "kind": "toggle",
		"hint": "no screen flashes, camera shake or bob"},
	{"key": "captions", "label": "Sound captions", "kind": "toggle",
		"hint": "on-screen text for cues you would otherwise only hear"},
	{"key": "damage_arrows", "label": "Damage direction", "kind": "toggle",
		"hint": "an arrow toward whatever just hit you"},
	{"key": "colourblind", "label": "Colour vision", "kind": "choice",
		"items": ["Standard", "Protanopia", "Deuteranopia", "Tritanopia"]},
]

## main.gd, for start_game() and restart(). Untyped for the same reason main's own
## `hud` handle is: the script is attached at runtime, so a Node3D-typed variable
## cannot see either method.
var main
var hud

var _root: Control
var _screens := {}
var _chains := {}
## Which screen BACK returns to. The options screen is reachable from two places
## and returning to the wrong one strands the player on a title card mid-run.
var _options_from := "title"
var _current := ""

## One-shot latch on the primary action for the frame it fires in. Two paths
## reach it — the button, and the HUD's click-anywhere poll that web/shell.html's
## single gesture drives — and on the game-over screen both would land: the poll
## on the mouse press, the button on the release. `restart()` defers a
## `reload_current_scene()` without moving Game.state, so the second call would
## queue a second reload of a scene that is already being replaced.
var _acted := false

var _stat_labels := {}
var _epitaph: Label
var _tip: Label
var _best: Label
var _value_labels := {}


func _ready() -> void:
	# Above the HUD (layer 1, unset) and below the debug console (128), so the
	# console can still be typed into over a paused menu.
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind(main_node, hud_node) -> void:
	main = main_node
	hud = hud_node
	_build()
	Game.state_changed.connect(_on_state)
	# The HUD stops drawing its own screen text and stops treating a click as
	# "start the game" — otherwise the title button and the HUD's poll both fire
	# start_game() on the same frame and the first round begins twice.
	if hud != null:
		hud.set_menu(self)
	_on_state(["title", "play", "pause", "over"][Game.state])


## The way back out, for scripts/dev/checks/shell.gd — which has to be able to
## build a menu over a running main, assert against it and leave the tree exactly
## as it found it. Without this the check would leave a second Game.state_changed
## listener and a HUD that had stopped drawing its own screens behind it, and
## every assertion after it would be running against a different game.
func unbind() -> void:
	if Game.state_changed.is_connected(_on_state):
		Game.state_changed.disconnect(_on_state)
	if hud != null:
		hud.set_menu(null)
	hud = null
	main = null


## The primary action of whatever screen is up: begin the run, or start another.
## Called by the big button AND by hud.gd's click-anywhere poll, which is the
## gesture web/shell.html forwards to the canvas — see `_acted` for why the two
## cannot both be allowed to land.
func press_primary() -> void:
	if _acted or main == null:
		return
	# THE SCREEN THAT IS UP IS THE AUTHORITY, NOT Game.state — and this is not
	# defensive tidying, it is a bug that made the options screen unusable. Opening
	# OPTIONS does not move Game.state, so from the title or the game-over screen
	# the state still reads TITLE / OVER underneath it. hud.gd's click-anywhere poll
	# reads the Input singleton, and a Control consuming a click does not suppress
	# that — `set_input_as_handled()` stops propagation to `_unhandled_input`, it
	# does not rewind the action state the event already wrote. So every click on a
	# slider, a checkbox and the BACK button also arrived here, and the first drag
	# of the mouse-sensitivity slider started the run out from under the player.
	match Game.state:
		Game.STATE_TITLE:
			if _current != "title":
				return
			_acted = true
			main.start_game()
		Game.STATE_OVER:
			if _current != "over":
				return
			_acted = true
			main.restart()


# --- construction ------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_build_title()
	_build_pause()
	_build_options()
	_build_over()
	for name: String in _screens:
		var s: Control = _screens[name]
		s.visible = false


## A screen is a full-rect Control that ignores the mouse, holding a centred plate
## that does not. `modal` makes the backdrop swallow clicks too: the options screen
## is modal because a click landing behind it would otherwise reach the player and
## resume the run out from under the slider being dragged.
func _screen(name: String, modal := false) -> VBoxContainer:
	var s := Control.new()
	s.name = name
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.mouse_filter = Control.MOUSE_FILTER_STOP if modal else Control.MOUSE_FILTER_IGNORE
	_root.add_child(s)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(centre)

	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_STOP
	plate.add_theme_stylebox_override("panel", _plate_style())
	centre.add_child(plate)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	plate.add_child(col)

	_screens[name] = s
	return col


## 0.94 rather than the 0.86 this shipped with. The plate is drawn over a live 3D
## frame — the title screen runs the warm-up behind it and the pause screen holds
## the room the player is standing in — and at 0.86 the lit ceiling came through
## the options screen's 13 px hint text hard enough to make it unreadable.
## Checked against a captured frame, not reasoned about.
func _plate_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(HUD.ASH.r, HUD.ASH.g, HUD.ASH.b, 0.94)
	sb.border_color = Color(HUD.RUST.r, HUD.RUST.g, HUD.RUST.b, 0.9)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(30)
	return sb


func _title(text: String, size := 64, col := HUD.BONE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Buttons carry a visible focus ring because the whole point of this file is that
## the game can be played from the keyboard, and Godot's default focus style is a
## one-pixel outline that is invisible against a dark plate.
func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", HUD.BONE)
	b.add_theme_color_override("font_hover_color", HUD.SODIUM)
	b.add_theme_color_override("font_focus_color", HUD.SODIUM)
	b.add_theme_color_override("font_pressed_color", HUD.SODIUM)
	b.add_theme_stylebox_override("normal", _button_style(Color(0, 0, 0, 0.35), HUD.RUST))
	b.add_theme_stylebox_override("hover", _button_style(Color(0.10, 0.09, 0.07, 0.6), HUD.SODIUM))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.14, 0.11, 0.06, 0.8), HUD.SODIUM))
	b.add_theme_stylebox_override("focus", _button_style(Color(0, 0, 0, 0.0), HUD.SODIUM))
	b.custom_minimum_size = Vector2(320, 44)
	return b


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_content_margin_all(8)
	return sb


func _build_title() -> void:
	var col := _screen("title")
	col.add_child(_title("KRIEGSNACHT", 72, HUD.BONE))
	col.add_child(_title("survive the night", 16, HUD.BONE_DIM))

	col.add_child(_keys_grid())

	var start := _button("ENTER THE BUNKER")
	start.pressed.connect(_on_start)
	col.add_child(start)

	var opts := _button("OPTIONS")
	opts.pressed.connect(_open_options.bind("title"))
	col.add_child(opts)

	# html:296-298, the points-economy hint. It is the only place the game explains
	# that points are a currency rather than a score, which is the single idea a
	# player has to arrive with.
	var hint := _title("Kill zombies to earn points. Spend them on doors, wall weapons and the Mystery Box.\n"
		+ "The perk machines are dead until you find the generator and switch the power on.", 15, HUD.BONE_DIM)
	col.add_child(hint)

	_best = _title("", 15, HUD.SODIUM)
	col.add_child(_best)

	var chain: Array[Control] = [start, opts]
	_chain("title", chain)


func _keys_grid() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	for group: Array in KEYS:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 3)
		var head := _title(String(group[0]).to_upper(), 14, HUD.SODIUM)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		col.add_child(head)
		for pair: Array in group[1]:
			var line := _title("%s   %s" % [pair[0], pair[1]], 15, HUD.BONE_DIM)
			line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			col.add_child(line)
		row.add_child(col)
	return row


func _build_pause() -> void:
	var col := _screen("pause")
	col.add_child(_title("PAUSED", 64))
	# The ancestor's `pausesub` (html:306), which is the one line that tells a
	# returning player where they left off.
	var sub := _title("", 16, HUD.BONE_DIM)
	sub.name = "PauseSub"
	col.add_child(sub)

	var resume := _button("RESUME")
	resume.pressed.connect(_on_resume)
	col.add_child(resume)

	var opts := _button("OPTIONS")
	opts.pressed.connect(_open_options.bind("pause"))
	col.add_child(opts)

	var quit := _button("ABANDON RUN")
	quit.pressed.connect(_on_abandon)
	col.add_child(quit)

	col.add_child(_title("Clicking anywhere outside this panel also resumes.", 13, HUD.BONE_DIM))

	var chain: Array[Control] = [resume, opts, quit]
	_chain("pause", chain)


func _build_over() -> void:
	var col := _screen("over")
	_epitaph = _title("OVERRUN", 64, HUD.BLOOD_LIT)
	col.add_child(_epitaph)
	col.add_child(_title("you did not survive the night", 16, HUD.BONE_DIM))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 26)
	for row: Array in _stats():
		var cell := VBoxContainer.new()
		var v := _title("0", 40, HUD.BONE)
		var k := _title(String(row[1]).to_upper(), 13, HUD.BONE_DIM)
		cell.add_child(v)
		cell.add_child(k)
		grid.add_child(cell)
		_stat_labels[row[0]] = v
	col.add_child(grid)

	var again := _button("TRY AGAIN")
	again.pressed.connect(_on_restart)
	col.add_child(again)

	var opts := _button("OPTIONS")
	opts.pressed.connect(_open_options.bind("over"))
	col.add_child(opts)

	_tip = _title("", 15, HUD.BONE_DIM)
	col.add_child(_tip)

	var chain: Array[Control] = [again, opts]
	_chain("over", chain)


## THREE OF THE ANCESTOR'S FIVE, PLUS ONE IT DOES NOT SHOW. The ancestor's set is
## round, kills, headshots, accuracy and time (html:3209-3215). `shots_fired` /
## `shots_hit` and an elapsed-run clock exist there (html:1635, :3351) and in no
## Godot file, so accuracy and time are omitted rather than displayed as a zero —
## which would read as "you hit nothing" and "you survived no time at all". They
## appear here the moment Game grows the fields; see this package's report.
##
## `points` is the DELIBERATE ADDITION and is recorded here as one rather than
## left to look like a fourth thing the ancestor had: the port made points a
## currency the whole title screen explains, so the number a player spent the run
## accumulating belongs on the screen that reports the run.
func _stats() -> Array:
	var out: Array = [["round", "rounds"], ["kills", "kills"], ["headshots", "headshots"],
		["points", "points"]]
	if Game.get("shots_fired") != null:
		out.append(["accuracy", "accuracy"])
	if Game.get("run_time") != null:
		out.append(["time", "survived"])
	return out


func _build_options() -> void:
	var col := _screen("options", true)
	col.add_child(_title("OPTIONS", 48))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	var chain: Array[Control] = []
	for row: Dictionary in ROWS:
		var key: String = row.key
		var name_label := _title(String(row.label), 18, HUD.BONE)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_label.custom_minimum_size = Vector2(230, 0)
		grid.add_child(name_label)

		var control := _row_control(row)
		grid.add_child(control)
		chain.append(control)

		var value := _title("", 16, HUD.SODIUM)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		value.custom_minimum_size = Vector2(70, 0)
		grid.add_child(value)
		_value_labels[key] = value

		if row.has("hint"):
			var hint := _title(String(row.hint), 13, HUD.BONE_DIM)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			grid.add_child(_title("", 13))
			grid.add_child(hint)
			grid.add_child(_title("", 13))
	col.add_child(grid)

	var back := _button("BACK")
	back.pressed.connect(_close_options)
	col.add_child(back)
	chain.append(back)
	_chain("options", chain)
	_refresh_options()


func _row_control(row: Dictionary) -> Control:
	var key: String = row.key
	match String(row.kind):
		"toggle":
			var cb := CheckButton.new()
			cb.focus_mode = Control.FOCUS_ALL
			cb.button_pressed = bool(Settings.get_value(key))
			cb.toggled.connect(_on_toggle.bind(key))
			return cb
		"choice":
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_ALL
			for item: String in row["items"]:
				ob.add_item(item)
			ob.selected = int(Settings.get_value(key))
			ob.item_selected.connect(_on_choice.bind(key))
			return ob
		_:
			var s := HSlider.new()
			s.focus_mode = Control.FOCUS_ALL
			s.custom_minimum_size = Vector2(240, 24)
			s.min_value = float(row.lo)
			s.max_value = float(row.hi)
			s.step = float(row.step)
			s.value = float(Settings.get_value(key))
			s.value_changed.connect(_on_slide.bind(key))
			return s


## Cyclic in both directions and on both axes, so the focus can never fall off the
## end of a screen and leave the keyboard doing nothing. Stored as well as wired
## because scripts/dev/checks/shell.gd walks the ring to prove it closes.
func _chain(name: String, controls: Array[Control]) -> void:
	_chains[name] = controls
	var n := controls.size()
	for i in n:
		var c: Control = controls[i]
		var nxt: Control = controls[(i + 1) % n]
		var prv: Control = controls[(i - 1 + n) % n]
		c.focus_neighbor_bottom = c.get_path_to(nxt)
		c.focus_neighbor_top = c.get_path_to(prv)
		c.focus_next = c.get_path_to(nxt)
		c.focus_previous = c.get_path_to(prv)


# --- the public shape scripts/dev/checks/shell.gd asserts against -------------

func screens() -> Dictionary:
	return _screens


func chain(name: String) -> Array:
	var out: Array = _chains.get(name, [])
	return out


func current() -> String:
	return _current


# --- screen switching --------------------------------------------------------

func show_screen(name: String) -> void:
	_current = name
	for k: String in _screens:
		var s: Control = _screens[k]
		s.visible = k == name
	if name.is_empty():
		return
	if name == "options":
		_refresh_options()
	elif name == "over":
		_refresh_over()
	elif name == "title":
		_refresh_title()
	elif name == "pause":
		_refresh_pause()
	_focus_first.call_deferred(name)


## Focuses the first control of a screen so the keyboard works without a click
## first. DEFERRED, because grab_focus() on a control whose screen was made
## visible this frame lands before the container has laid it out — and RE-CHECKED
## on arrival, because a deferred call outlives the reason for it. Two ways it
## arrives stale: the screen changed again in the same frame (a click on the title
## button switches to "play" before the focus lands), and the whole menu was
## removed from the tree in the same frame, which is exactly what
## scripts/dev/checks/shell.gd does — `grab_focus()` on a control that is no
## longer inside the tree is an engine error, not a no-op.
func _focus_first(name: String) -> void:
	if name.is_empty() or _current != name:
		return
	var ring: Array = _chains.get(name, [])
	if ring.is_empty():
		return
	var first: Control = ring[0]
	if is_instance_valid(first) and first.is_inside_tree():
		first.grab_focus()


func _on_state(s: String) -> void:
	# Released on every transition. `main.start_game()` emits this synchronously
	# from inside press_primary(), so the latch is already down again by the time
	# the button's release arrives — which is fine, because press_primary() also
	# checks the state and "play" has no primary action.
	_acted = false
	match s:
		"title":
			show_screen("title")
		"pause":
			show_screen("pause")
		"over":
			show_screen("over")
		_:
			show_screen("")


## ui_cancel is Escape, which is also bound to `pause` — but the HUD only reads
## `pause` during play, so there is no collision here. Handled rather than left to
## fall through because a player who opened the options from the pause screen has
## no other way back on the keyboard.
func _unhandled_input(event: InputEvent) -> void:
	if _current == "options" and event.is_action_pressed("ui_cancel"):
		_close_options()
		get_viewport().set_input_as_handled()


# --- refreshes ---------------------------------------------------------------

func _refresh_title() -> void:
	if Game.profile.best_round > 0:
		_best.text = "best: round %d  ·  %s points" % [
			Game.profile.best_round, _commas(int(Game.profile.best_points))]
	else:
		_best.text = ""


func _refresh_pause() -> void:
	var sub: Label = _screens["pause"].find_child("PauseSub", true, false)
	if sub != null:
		sub.text = "round %d  ·  %d kills" % [Game.round_no, Game.kills]


func _refresh_over() -> void:
	for key: String in _stat_labels:
		var l: Label = _stat_labels[key]
		l.text = _stat_text(key)
	var word := "Devoured"
	for band: Array in EPITAPH:
		if Game.round_no >= int(band[0]):
			word = String(band[1])
			break
	_epitaph.text = word.to_upper()
	# Cosmetic, so it draws from VISUAL and never from a gameplay stream —
	# constraint 6. A tip picked off SPAWN would shift every seeded run's spawns by
	# one draw at the moment the player died, which is exactly the kind of
	# invisible desync the split streams exist to make impossible.
	_tip.text = String(Rng.pick(Rng.VISUAL, TIPS))


func _stat_text(key: String) -> String:
	match key:
		"round":
			return str(Game.round_no)
		"kills":
			return str(Game.kills)
		"headshots":
			return str(Game.headshots)
		"points":
			return _commas(Game.points)
		"accuracy":
			var fired: int = int(Game.get("shots_fired"))
			var hit: int = int(Game.get("shots_hit"))
			return "%d%%" % (roundi(float(hit) / float(fired) * 100.0) if fired > 0 else 0)
		"time":
			var t := float(Game.get("run_time"))
			return "%d:%02d" % [int(t / 60.0), int(fmod(t, 60.0))]
	return ""


func _refresh_options() -> void:
	for row: Dictionary in ROWS:
		var key: String = row.key
		var l: Label = _value_labels.get(key)
		if l == null:
			continue
		var v: Variant = Settings.get_value(key)
		match String(row.kind):
			"percent":
				l.text = "%d%%" % roundi(float(v) * 100.0)
			"slider":
				l.text = "%.2f%s" % [float(v), String(row.suffix)] if key == "mouse_sens" \
					else "%d%s" % [roundi(float(v)), String(row.suffix)]
			"toggle":
				l.text = "on" if bool(v) else "off"
			_:
				l.text = ""


func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


# --- what the buttons do -----------------------------------------------------

## Both of these ask for the pointer from inside the button's own press. That is
## the whole reason the menu is clickable rather than a keypress: `requestPointerLock`
## needs transient activation, and a mouse press grants it while Escape provably
## does not (WHATWG excludes it). The state change itself is left to the HUD's
## watchdog, which flips to play the frame the lock is actually observed — one
## writer, and it is already correct for the alt-tab case.
func _on_start() -> void:
	press_primary()


func _on_resume() -> void:
	Player.set_capture(true)


func _on_restart() -> void:
	press_primary()


func _on_abandon() -> void:
	# The scene reload lands on the title screen, which is where "abandon" should
	# go — and it is the only way to drop a run's worth of state without a second
	# reset path that would then have to be kept in step with reset_run().
	main.restart()


func _open_options(from: String) -> void:
	_options_from = from
	show_screen("options")


## The one place the options are committed. Saving per slider tick would be a
## synchronous localStorage write per pixel of drag on web; saving on the way out
## is one write per visit to this screen.
func _close_options() -> void:
	if not Settings.save():
		# Incognito and third-party-cookie-blocked iframes refuse storage outright.
		# The options still apply for this session, so this is a note, not a failure.
		push_warning("settings save unavailable — storage refused the write")
	show_screen(_options_from)


func _on_toggle(pressed: bool, key: String) -> void:
	Settings.set_value(key, pressed)
	_refresh_options()


func _on_choice(index: int, key: String) -> void:
	Settings.set_value(key, index)
	_refresh_options()


func _on_slide(value: float, key: String) -> void:
	Settings.set_value(key, value)
	_refresh_options()
