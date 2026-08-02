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
##
## FOUR SCREENS HAVE NO ANCESTOR AT ALL. `multiplayer`, `host`, `join` and `lobby`
## are new: kriegsnacht.html is single-player and has nothing to copy. They are
## modelled on the reference instead — BO1 co-op is a room, a code, and one player
## who starts it — and they are recorded here as a deliberate departure rather than
## left to read as an invention. The room they draw lives in the `Net` autoload;
## this file holds none of it.
##
## NOTHING HERE HARD-CODES THE ROOM SIZE. BO1 seats four and this port seats
## `Net.MAX_PLAYERS`, which is two because a broadcast into a room of N costs N
## events against a 100/second project cap (session.gd:31-55). Every seat count,
## every empty row and the subtitle on the first screen are read off that constant,
## so the day the plan moves it, this file follows without being touched.

## The HUD owns the palette and this file borrows it rather than re-declaring the
## same nine colours next to it. Preload rather than the class name: a freshly
## added script is not in the class registry until the editor rescans.
const HUD := preload("res://scripts/ui/hud.gd")

## The room-code alphabet and the two functions that police it. Preloaded rather
## than reached for through `Net`: they are pure statics with no session behind
## them (phoenix.gd:1-11), so the join field can validate a keystroke without the
## autoload existing at all.
const PHX := preload("res://scripts/net/phoenix.gd")

## html:3225 — the epitaph bands, carried over unchanged.
const EPITAPH := [[15, "Legend"], [10, "Veteran"], [5, "Overrun"], [0, "Devoured"]]

## The four co-op screens, and the set `_on_net_state` is allowed to switch
## between. A session transition must never move a player who is mid-run, in the
## options or on the pause plate — the room can go OFFLINE at any moment and a
## screen change on top of a live game is worse than no screen change at all.
const MP_SCREENS := ["multiplayer", "host", "join", "lobby"]

## THE PORT HAS NO NAME ENTRY AND THIS PACKAGE CANNOT GROW ONE. `Settings` holds a
## bool, an int or a float and refuses everything else: DEFAULTS declares the type
## of each key by example (settings.gd:49-58) and `_clean` has arms for exactly
## those three (settings.gd:172-195). Adding TYPE_STRING is a change to a file this
## package does not own, so the name is derived instead — see `_player_name()` —
## and the hunk that would let a player type one is in this package's report.
const CREW := ["Dempsey", "Nikolai", "Takeo", "Richtofen"]

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
## reach it — the button, and the HUD's click-anywhere poll, which since the poll
## narrowed to the game-over screen is the one screen where both land: the poll on
## the mouse press, the button on the release. `restart()` defers a
## `reload_current_scene()` without moving Game.state, so the second call would
## queue a second reload of a scene that is already being replaced.
var _acted := false

var _stat_labels := {}
var _epitaph: Label
var _tip: Label
var _best: Label
var _value_labels := {}

# --- co-op ---------------------------------------------------------------------
## One error line and one roster column per co-op screen, keyed by screen name: a
## screen is its own Control subtree, so a single shared Label could only ever be
## inside one of them.
var _error_labels := {}
var _roster_boxes := {}
var _code_labels := {}
var _host_status: Label
var _host_start: Button
var _lobby_status: Label
var _drop_in: Button
var _join_field: LineEdit
var _join_slots: Label
var _connect: Button
## Re-entrancy latch on the join field's write-back. See `_on_join_text`.
var _join_guard := false
## The host's seed, held between `run_started` arriving and the player pressing
## DROP IN — which on a client are two different frames, deliberately.
var _run_seed := 0
var _name_cache := ""


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
	# The session is an AUTOLOAD and outlives both this node and the scene reload
	# behind `restart()` (session.gd:5-8), so these four are the one place a menu
	# and a room meet — and every one of them has to come back out in `unbind()`.
	Net.state_changed.connect(_on_net_state)
	Net.roster_changed.connect(_on_net_roster)
	Net.error.connect(_on_net_error)
	Net.run_started.connect(_on_run_started)
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
## THE NET LISTENERS ARE THE HALF THAT BITES. `Game` is reset by the next check
## that touches it, but `Net` is an autoload that nothing in the suite resets — a
## leaked listener here survives every later section, and the first roster or
## error event would then be written into the Labels of a freed menu. Enumerated
## rather than listed by hand so a fifth connection added later cannot be
## forgotten; scripts/dev/checks/shell.gd asserts the same thing from the outside,
## by walking Net's signals and looking for callables that point at this object.
func unbind() -> void:
	if Game.state_changed.is_connected(_on_state):
		Game.state_changed.disconnect(_on_state)
	for sig: Signal in [Net.state_changed, Net.roster_changed, Net.error, Net.run_started]:
		for c: Dictionary in sig.get_connections():
			var cb: Callable = c["callable"]
			if cb.get_object() == self:
				sig.disconnect(cb)
	if hud != null:
		hud.set_menu(null)
	hud = null
	main = null


## The primary action of whatever screen is up: begin the run, or start another.
## Called by the big button on either screen, and on the game-over screen also by
## hud.gd's click-anywhere poll — see `_acted` for why the two cannot both be
## allowed to land. The title screen no longer reaches here from a bare click, and
## `_poll_menu_click` carries the reason.
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
	_build_multiplayer()
	_build_host()
	_build_join()
	_build_lobby()
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

	# Between the solo start and the options, which is where the reference puts it
	# and also the honest ranking: this is a co-op mode bolted to a game that is
	# playable alone, not the other way round.
	var coop := _button("MULTIPLAYER")
	coop.pressed.connect(_open_multiplayer)
	col.add_child(coop)

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

	var chain: Array[Control] = [start, coop, opts]
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


# --- the co-op screens ---------------------------------------------------------
#
# THE ROOM IS NOT HELD HERE. `Net` owns the code, the token, the roster and the
# state; this file draws them and sends four verbs back (host, join, leave,
# start). That split is not tidiness — a session outlives the run and survives
# `restart()`'s scene reload (session.gd:5-8), so a menu that held any of it would
# lose the room the first time somebody died.
#
# ALL FOUR ARE MODAL. The options screen is modal because a click behind it would
# reach the player and resume the run (see `_screen`); these are modal for the
# neighbouring reason — the join screen owns a text field, and a stray click that
# lands behind the plate takes the focus off it while the player is mid-code.


func _build_multiplayer() -> void:
	var col := _screen("multiplayer", true)
	col.add_child(_title("MULTIPLAYER", 56))
	# Read off the session rather than written out, for the reason in this file's
	# header: the cap is an events-per-second calculation and not a design number.
	col.add_child(_title("%d to a bunker" % int(Net.MAX_PLAYERS), 16, HUD.BONE_DIM))

	var host := _button("HOST A ROOM")
	host.pressed.connect(_on_host_pressed)
	col.add_child(host)

	var join := _button("JOIN A ROOM")
	join.pressed.connect(_on_join_pressed)
	col.add_child(join)

	var back := _button("BACK")
	back.pressed.connect(_on_mp_back)
	col.add_child(back)

	col.add_child(_error_label("multiplayer"))
	var chain: Array[Control] = [host, join, back]
	_chain("multiplayer", chain)


func _build_host() -> void:
	var col := _screen("host", true)
	col.add_child(_title("YOUR ROOM", 40))
	col.add_child(_title("read this out", 15, HUD.BONE_DIM))

	# 72 px and spaced glyph by glyph, because this code gets READ ALOUD. The
	# alphabet has already dropped the vowels and the L/0/1 that get mis-heard
	# (phoenix.gd:52-56); the spacing is the other half of the same job — it is
	# what stops a reader running two glyphs together into one shape. SODIUM
	# rather than BONE: it is the one thing on this screen the player is looking
	# for.
	var code := _title("", 72, HUD.SODIUM)
	_code_labels["host"] = code
	col.add_child(code)

	_host_status = _title("", 16, HUD.BONE_DIM)
	col.add_child(_host_status)
	col.add_child(_roster_box("host"))

	_host_start = _button("START THE RUN")
	_host_start.pressed.connect(_on_host_start)
	col.add_child(_host_start)

	var leave := _button("LEAVE")
	leave.pressed.connect(_on_leave)
	col.add_child(leave)

	col.add_child(_error_label("host"))
	var chain: Array[Control] = [_host_start, leave]
	_chain("host", chain)


func _build_join() -> void:
	var col := _screen("join", true)
	col.add_child(_title("JOIN A ROOM", 40))
	col.add_child(_title("type the code you were read", 15, HUD.BONE_DIM))

	# The slot readout, above the field rather than inside it: a player who has
	# typed four of six needs to see that two are missing, and a text field can
	# only show what is in it.
	_join_slots = _title("", 48, HUD.SODIUM)
	col.add_child(_join_slots)

	_join_field = LineEdit.new()
	_join_field.name = "JoinCode"
	_join_field.focus_mode = Control.FOCUS_ALL
	_join_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_field.placeholder_text = "ROOM CODE"
	_join_field.custom_minimum_size = Vector2(320, 40)
	_join_field.add_theme_font_size_override("font_size", 22)
	# THE ONLY CONTROL IN THIS FILE WITH NO HELPER BEHIND IT, so it borrows the
	# buttons' two styleboxes rather than growing a third visual language. Found by
	# rendering the screen and looking at it: on Godot's default theme the field
	# came out a pale grey box with a white caret, which against a rust-bordered
	# plate reads as a browser widget that has leaked through the game.
	_join_field.add_theme_stylebox_override("normal",
		_button_style(Color(0, 0, 0, 0.35), HUD.RUST))
	_join_field.add_theme_stylebox_override("focus",
		_button_style(Color(0.10, 0.09, 0.07, 0.6), HUD.SODIUM))
	_join_field.add_theme_color_override("font_color", HUD.BONE)
	_join_field.add_theme_color_override("font_placeholder_color", HUD.ALT_DIM)
	_join_field.add_theme_color_override("caret_color", HUD.SODIUM)
	_join_field.add_theme_color_override("font_selected_color", HUD.ASH)
	_join_field.add_theme_color_override("selection_color", HUD.SODIUM)
	# DELIBERATELY NO `max_length`. Six looks right and is wrong: the filter is
	# what lets "bcdf-23", "bcdf 23" and "BCDF23" all arrive as BCDF23
	# (phoenix.gd:316-337), and a hard length cap would eat the seventh keystroke
	# of a hyphenated code before the filter ever saw it. `sanitise_code` clips.
	_join_field.text_changed.connect(_on_join_text)
	_join_field.text_submitted.connect(_on_join_submit)
	col.add_child(_join_field)

	_connect = _button("CONNECT")
	_connect.pressed.connect(_on_connect)
	col.add_child(_connect)

	var back := _button("BACK")
	back.pressed.connect(_on_join_back)
	col.add_child(back)

	col.add_child(_error_label("join"))
	var chain: Array[Control] = [_join_field, _connect, back]
	_chain("join", chain)
	_refresh_join()


func _build_lobby() -> void:
	var col := _screen("lobby", true)
	col.add_child(_title("THE ROOM", 40))
	var code := _title("", 48, HUD.SODIUM)
	_code_labels["lobby"] = code
	col.add_child(code)

	_lobby_status = _title("", 16, HUD.BONE_DIM)
	col.add_child(_lobby_status)
	col.add_child(_roster_box("lobby"))

	# THE NON-HOST'S OWN GESTURE, and the reason it is a button at all is written
	# out in full at `_on_run_started`. Disabled until the host has started; the
	# label says which of the two it currently is, because a dead button with no
	# explanation reads as a broken one.
	_drop_in = _button("DROP IN")
	_drop_in.pressed.connect(_on_drop_in)
	col.add_child(_drop_in)

	var leave := _button("LEAVE")
	leave.pressed.connect(_on_leave)
	col.add_child(leave)

	col.add_child(_error_label("lobby"))
	var chain: Array[Control] = [_drop_in, leave]
	_chain("lobby", chain)


## One error line per co-op screen. Every message is written to all four
## (`_set_net_error`) and only the visible one is ever read — which is both
## cheaper than routing by `_current` and more robust, because an error raised on
## the frame before a screen change is still there when the player arrives.
##
## The minimum size is held whether or not there is a message, so the plate does
## not grow under the cursor the moment the room service says no.
func _error_label(screen: String) -> Label:
	var l := _title("", 15, HUD.BLOOD_LIT)
	l.custom_minimum_size = Vector2(360, 20)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_labels[screen] = l
	return l


## Sized for a full room from the start, for the same reason: a lobby that grows
## a row every time somebody joins moves LEAVE under the cursor of a player who
## was reaching for START.
func _roster_box(screen: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size = Vector2(320, 26.0 * float(int(Net.MAX_PLAYERS)))
	_roster_boxes[screen] = box
	return box


## Rebuilt whole rather than diffed. Four rows is not worth a diff, and a diff
## would need row identity that presence does not promise: a client that
## reconnects comes back under a fresh presence key (session.gd:245-248) and would be
## a new row either way.
##
## REMOVE THEN FREE, IN THAT ORDER. `queue_free()` alone leaves the node in
## `get_children()` until the end of the frame, so two roster events in one frame
## — which `presence_state` immediately followed by a `presence_diff` is, and it
## is the ordinary arrival shape on join (realtime.gd:233-238) — would stack a
## second set of rows underneath the first and leak them both.
func _rebuild_roster(players: Array) -> void:
	for screen: String in _roster_boxes:
		var box: VBoxContainer = _roster_boxes[screen]
		for c: Node in box.get_children():
			box.remove_child(c)
			c.queue_free()
		# Empty seats are drawn rather than omitted: "one of two" is the fact a player
		# wants while they are waiting, and the ceiling is enforced by the ARRIVING
		# client rather than by the room (session.gd:268-280) — so drawing the empty
		# seats is also drawing the rule that fills them.
		for i in int(Net.MAX_PLAYERS):
			var row: Label
			if i < players.size():
				var p: Dictionary = players[i]
				var marks: Array[String] = []
				if bool(p.get("host", false)):
					marks.append("host")
				if bool(p.get("me", false)):
					marks.append("you")
				var suffix := "" if marks.is_empty() else "   (%s)" % "  ·  ".join(marks)
				row = _title(str(p.get("name", "?")) + suffix, 18, HUD.BONE)
			else:
				row = _title("— empty —", 18, HUD.ALT_DIM)
			box.add_child(row)


## The code as six slots, which is one function for two jobs: on the host screen
## it spaces a full code out for reading aloud, and on the join screen the blanks
## are how a player sees how many characters are left. Padded rather than
## clipped — `sanitise_code` has already guaranteed no more than CODE_LEN.
func _slots(code: String) -> String:
	var out: Array[String] = []
	for i in int(PHX.CODE_LEN):
		out.append(code[i] if i < code.length() else "_")
	return " ".join(out)


## BO1's four, picked by the seed the process booted with.
##
## NOT A DRAW. `Rng.seed_value` is already random per process and reading it
## consumes nothing, where `Rng.randi_range(Rng.VISUAL, ...)` here would advance
## the one stream weapon spread still rides (constraint 5's recorded violation) on
## every visit to this menu. Two players can land on the same crewman; the roster
## marks your own row, and the fix is a real name box — see the Settings hunk in
## this package's report.
func _player_name() -> String:
	if _name_cache.is_empty():
		_name_cache = _crew_name(int(Rng.seed_value))
	return _name_cache


## Split out from the cache so it can be asserted across seeds.
static func _crew_name(seed_value: int) -> String:
	return String(CREW[absi(seed_value) % CREW.size()])


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
	elif name == "host":
		_refresh_host()
	elif name == "lobby":
		_refresh_lobby()
	elif name == "join":
		_refresh_join()
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
	# A DISABLED CONTROL IS NOT SOMEWHERE THE FOCUS MAY LAND. Both co-op screens
	# put their primary affordance at the head of the ring and ship it disabled —
	# START THE RUN until the room has a code, DROP IN until the host has started —
	# so the first control of the ring is routinely a dead key, and a keyboard
	# player who arrives on it has to guess that Tab is what unsticks them. Falls
	# back to ring[0] if every control is disabled, because a focus somewhere is
	# better than a focus nowhere.
	var first: Control = ring[0]
	for c: Control in ring:
		if c is BaseButton and (c as BaseButton).disabled:
			continue
		first = c
		break
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
##
## The two co-op screens that back out on Escape are the two that own nothing: the
## menu itself and the code field. "host" and "lobby" deliberately do NOT, because
## backing out of those means `leave_room()` — releasing a code three other people
## have already been read — and a key that is right next to the one a player has
## been mashing to pause is not where that belongs.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _current == "options":
		_close_options()
		get_viewport().set_input_as_handled()
	elif _current == "multiplayer":
		_on_mp_back()
		get_viewport().set_input_as_handled()
	elif _current == "join":
		_on_join_back()
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


## Both co-op refreshes are pure functions of the session's state, and they take
## it as an argument for one reason: `Net.state()` cannot be moved off OFFLINE
## without a live socket, so this is the seam scripts/dev/checks/shell.gd drives
## the readouts through. The default is the only thing the game ever passes.
func _refresh_host(st := -1) -> void:
	if st < 0:
		st = int(Net.state())
	var code: Label = _code_labels["host"]
	code.text = _slots(str(Net.code()))
	# if/elif rather than `match`, because a match pattern has to be a constant the
	# parser can fold and `Net.CLAIMING` is an attribute read on an autoload.
	if st == Net.CLAIMING:
		# The window in which there is no code yet: the row is being INSERTed
		# against a UNIQUE constraint, which is the one job the rooms table exists
		# to do (notes/net/2026-07-31-realtime-probe.md, "claiming a code without a
		# race"). Nothing to read out and nothing to start.
		_host_status.text = "claiming a room…"
	elif st == Net.CONNECTING:
		_host_status.text = "opening the channel…"
	elif st == Net.LOBBY:
		_host_status.text = "waiting for the others"
	elif st == Net.IN_RUN:
		_host_status.text = "the run has begun"
	else:
		_host_status.text = ""
	# `Net.start_run()` refuses anything but a joined host (session.gd:158-160), so
	# the button is disabled on exactly the condition the session would refuse —
	# rather than on a second, drifting copy of the rule.
	_host_start.disabled = not (st == Net.LOBBY and bool(Net.is_host()))


func _refresh_lobby(st := -1) -> void:
	if st < 0:
		st = int(Net.state())
	var code: Label = _code_labels["lobby"]
	code.text = _slots(str(Net.code()))
	# One writer for the drop-in button, and it is the session rather than the
	# `run_started` handler: a client that is IN_RUN and is not the host is exactly
	# the client that has been told to come in and has not come in yet.
	var armed: bool = st == Net.IN_RUN and not bool(Net.is_host())
	_drop_in.disabled = not armed
	_drop_in.text = "DROP IN" if armed else "WAITING FOR THE HOST"
	if armed:
		_lobby_status.text = "the host has started"
		return
	if st == Net.CHECKING:
		_lobby_status.text = "checking that code…"
	elif st == Net.CONNECTING:
		_lobby_status.text = "opening the channel…"
	elif st == Net.LOBBY:
		_lobby_status.text = "waiting for the host"
	else:
		_lobby_status.text = ""


func _refresh_join() -> void:
	var typed: String = _join_field.text
	_join_slots.text = _slots(typed)
	# SHAPE ONLY. Whether a room with this code EXISTS is the server's answer and
	# a client that tries to decide it locally is a client that will one day refuse
	# a real room (phoenix.gd:303-305).
	_connect.disabled = not bool(PHX.is_valid_code(typed))


func _set_net_error(message: String) -> void:
	for screen: String in _error_labels:
		var l: Label = _error_labels[screen]
		l.text = message


## Cleared when the player does something, never on a state change. `_fail()`
## takes the session OFFLINE and *then* emits the message (session.gd:351-355), so
## clearing on OFFLINE would wipe the one thing the player needs to read.
func _clear_net_error() -> void:
	_set_net_error("")


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


# --- what the co-op buttons do ---------------------------------------------------

func _open_multiplayer() -> void:
	_clear_net_error()
	show_screen("multiplayer")


func _on_mp_back() -> void:
	_clear_net_error()
	show_screen("title")


func _on_host_pressed() -> void:
	_clear_net_error()
	# Shown before the call rather than after it: `host_room()` emits CLAIMING
	# synchronously and `_on_net_state` only follows the session while a co-op
	# screen is up — which "multiplayer" is, so either order works today. This
	# order also puts the player somewhere legible if the session refuses the
	# request outright (it does, if a room is already open).
	show_screen("host")
	Net.host_room(_player_name())


func _on_join_pressed() -> void:
	_clear_net_error()
	show_screen("join")


func _on_join_back() -> void:
	_clear_net_error()
	show_screen("multiplayer")


## THE WRITE-BACK IS GUARDED AND THE GUARD IS MEASURED, NOT ASSUMED. Probed on
## 4.7: neither `set_text()`, nor the property, nor `insert_text_at_caret()`, nor
## `delete_text()` re-emits `text_changed` — only `clear()` does — so on this
## engine the latch closes nothing. It stays because it costs one bool and the
## failure it prevents is unbounded recursion inside a text field, which is a
## stack overflow rather than a wrong pixel.
func _on_join_text(raw: String) -> void:
	if _join_guard:
		return
	_join_guard = true
	var clean: String = PHX.sanitise_code(raw)
	if clean != raw:
		_join_field.text = clean
		# Without this the caret snaps to 0 on every rejected keystroke and the
		# next character is typed in front of the code rather than after it.
		_join_field.caret_column = clean.length()
	_join_guard = false
	_refresh_join()


## Enter in the field is the same verb as the button, and refused on the same
## condition — reading `_connect.disabled` rather than re-testing the code, so
## there is one gate and not two that can drift.
func _on_join_submit(_text: String) -> void:
	if not _connect.disabled:
		_on_connect()


## No `show_screen` here on purpose. `join_room` refuses a malformed code with an
## error and NO state change (session.gd:126-128), so a screen change made here
## would drop the player into an empty lobby holding a message about a code they
## are no longer looking at. The screen follows the session, in `_on_net_state`.
func _on_connect() -> void:
	_clear_net_error()
	Net.join_room(_join_field.text, _player_name())


func _on_leave() -> void:
	_clear_net_error()
	# → OFFLINE → `_on_net_state` → the multiplayer screen. The host also releases
	# its code on the way out (session.gd:145-148).
	Net.leave_room()


## Net emits `run_started` synchronously from inside this call (session.gd:162-164),
## so `_on_run_started` runs while this button press is still on the stack — which
## is the whole reason the pointer capture inside `start_game()` is legal. Nothing
## on this path may be deferred.
func _on_host_start() -> void:
	_clear_net_error()
	Net.start_run()


func _on_drop_in() -> void:
	_enter_run()


# --- what the session says -------------------------------------------------------

## ONE WRITER FOR WHICH CO-OP SCREEN IS UP, and it is the session rather than the
## buttons. Each button calling `show_screen` itself gives two authors for
## `_current`, and they disagree at exactly the moment the player needs the screen
## to be right — when the server has refused something.
func _on_net_state(s: int) -> void:
	# A session transition must never move a player who is mid-run, in the options
	# or on the pause plate. The room can go OFFLINE at any moment.
	if not MP_SCREENS.has(_current):
		return
	if s == Net.OFFLINE:
		show_screen("multiplayer")
	elif s == Net.IN_RUN:
		# `_on_run_started` owns this one: the host is already entering the run and
		# the client needs its lobby left up with DROP IN armed on it.
		_refresh_host()
		_refresh_lobby()
	else:
		show_screen("host" if bool(Net.is_host()) else "lobby")


func _on_net_roster(players: Array) -> void:
	_rebuild_roster(players)


func _on_net_error(message: String) -> void:
	_set_net_error(message)


## THE POINTER LOCK IS THE WHOLE PROBLEM, AND THE HOST AND THE CLIENT ARE NOT IN
## THE SAME SITUATION.
##
## The host reaches here synchronously from its own START THE RUN press
## (session.gd:158-164), so the browser's transient activation is still live and
## `start_game()`'s `requestPointerLock` is granted — the same rule menu.gd:1086-1091
## already lives by.
##
## The client reaches here off a broadcast (session.gd:284-294). There is no user
## gesture anywhere near that frame, WHATWG grants activation only to a real input
## event, and a capture asked for without one is refused. The player would land in
## the bunker with a free cursor, no camera control and no way back: hud.gd's
## re-capture watchdog arms only once a lock has been OBSERVED (hud.gd:1118-1131),
## so with a lock that was never granted it never arms, and the click-anywhere path
## is gated on STATE_TITLE / STATE_OVER and so has already stopped running.
##
## So the client is handed a button and drops in on its own press. It costs the
## client the second it takes to read one line and press one key; it is the only
## version of this that works in a browser. `Net.is_host()` is the exact
## discriminator — it is precisely the flag that decides which of the two code
## paths in session.gd emitted this signal.
func _on_run_started(seed_value: int) -> void:
	_run_seed = seed_value
	if bool(Net.is_host()):
		_enter_run()
		return
	# `_refresh_lobby` arms DROP IN off the session's own IN_RUN, so this only has
	# to make sure the lobby is the screen that is up.
	show_screen("lobby")


## EVERY CLIENT RE-SEEDS FROM THE HOST'S SEED, THE HOST INCLUDED, and that is not
## a formality on the host's side. Opening a room draws thirty-two values out of
## Rng.VISUAL for the presence key (session.gd:371-376), and the host draws them at
## a different moment from every client — so the two processes arrive at START THE
## RUN with VISUAL in different places, and VISUAL is the stream weapon spread
## still rides (constraint 5's recorded violation). `new_run()` clears every stream
## and rebuilds all six from the one seed, which is the only thing that puts them
## level.
##
## Latched on `_acted` like every other primary action in this file: DROP IN and
## hud.gd's click-anywhere poll can both land in one frame.
func _enter_run() -> void:
	if _acted or main == null:
		return
	_acted = true
	Rng.new_run(_run_seed)
	main.start_game()
