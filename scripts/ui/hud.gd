extends CanvasLayer

## HUD, title and game-over screens.
##
## In the browser build this was a DOM overlay; here it is a CanvasLayer of
## Controls. The palette is carried over unchanged — the WWII-bunker read
## depends on it.

const ASH := Color("0b0c0a")
const BONE := Color("d8d2c0")
const BLOOD := Color("8e1116")
const SODIUM := Color("e0a62b")
const RAD := Color("7fa83c")
const RUST := Color("3a3129")

var player: Player
var game: Node3D

var _points: Label
var _round: Label
var _ammo: Label
var _prompt: Label
var _toast: Label
var _hp_bar: ColorRect
var _hp_back: ColorRect
var _perks: HBoxContainer
var _crosshair: Control
var _vignette: ColorRect
var _overlay: Control
var _overlay_title: Label
var _overlay_body: Label
var _toast_time := 0.0
var _flash := 0.0


func bind(p: Player, g: Node3D) -> void:
	player = p
	game = g
	_build()
	player.health_changed.connect(_on_health)
	player.weapon_changed.connect(_on_weapon)
	Game.points_changed.connect(_on_points)
	Game.round_changed.connect(_on_round)
	Game.state_changed.connect(_on_state)
	Game.toast.connect(show_toast)
	_on_health(player.hp, Game.max_health())
	_on_weapon(player.current_gun())
	_on_points(Game.points)


func _label(size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = align
	return l


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.color = Color(BLOOD.r, BLOOD.g, BLOOD.b, 0.0)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_vignette)

	# points, top-left
	_points = _label(40, SODIUM)
	_points.position = Vector2(28, 20)
	root.add_child(_points)

	var plabel := _label(14, RUST)
	plabel.text = "POINTS"
	plabel.position = Vector2(30, 66)
	root.add_child(plabel)

	# round, bottom-left
	_round = _label(46, BLOOD)
	_round.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_round.position = Vector2(28, -96)
	root.add_child(_round)

	# health bar, bottom-left above round
	_hp_back = ColorRect.new()
	_hp_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_back.position = Vector2(28, -132)
	_hp_back.size = Vector2(220, 10)
	_hp_back.color = Color(0, 0, 0, 0.55)
	root.add_child(_hp_back)

	_hp_bar = ColorRect.new()
	_hp_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_bar.position = Vector2(28, -132)
	_hp_bar.size = Vector2(220, 10)
	_hp_bar.color = BONE
	root.add_child(_hp_bar)

	# perks strip
	_perks = HBoxContainer.new()
	_perks.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_perks.position = Vector2(28, -168)
	_perks.add_theme_constant_override("separation", 6)
	root.add_child(_perks)

	# ammo, bottom-right
	_ammo = _label(38, BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_ammo.position = Vector2(-320, -96)
	_ammo.size = Vector2(290, 50)
	root.add_child(_ammo)

	# crosshair
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	root.add_child(_crosshair)

	# interact prompt
	_prompt = _label(22, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-400, -190)
	_prompt.size = Vector2(800, 30)
	root.add_child(_prompt)

	# toast
	_toast = _label(34, SODIUM, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-400, 120)
	_toast.size = Vector2(800, 44)
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	_build_overlay(root)


func _build_overlay(root: Control) -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(ASH.r, ASH.g, ASH.b, 0.92)
	_overlay.add_child(bg)

	_overlay_title = _label(84, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_overlay_title.set_anchors_preset(Control.PRESET_CENTER)
	_overlay_title.position = Vector2(-500, -130)
	_overlay_title.size = Vector2(1000, 100)
	_overlay.add_child(_overlay_title)

	_overlay_body = _label(20, Color(BONE.r, BONE.g, BONE.b, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	_overlay_body.set_anchors_preset(Control.PRESET_CENTER)
	_overlay_body.position = Vector2(-500, -10)
	_overlay_body.size = Vector2(1000, 240)
	_overlay.add_child(_overlay_body)


func _draw_crosshair() -> void:
	var c := _crosshair.size * 0.5
	var col := Color(BONE.r, BONE.g, BONE.b, 0.75)
	var gap := 5.0
	var len := 9.0
	_crosshair.draw_line(c + Vector2(-gap - len, 0), c + Vector2(-gap, 0), col, 2.0)
	_crosshair.draw_line(c + Vector2(gap, 0), c + Vector2(gap + len, 0), col, 2.0)
	_crosshair.draw_line(c + Vector2(0, -gap - len), c + Vector2(0, -gap), col, 2.0)
	_crosshair.draw_line(c + Vector2(0, gap), c + Vector2(0, gap + len), col, 2.0)
	_crosshair.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), col)


func _process(dt: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= dt
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - dt * 2.2)
		_vignette.color.a = _flash * 0.45

	if Input.is_action_just_pressed("pause"):
		if Game.state == Game.STATE_PLAY:
			Game.set_state(Game.STATE_PAUSE)
			Player.set_capture(false)
		elif Game.state == Game.STATE_PAUSE:
			Game.set_state(Game.STATE_PLAY)
			Player.set_capture(true)

	if Game.state == Game.STATE_TITLE or Game.state == Game.STATE_OVER:
		if Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("interact"):
			if Game.state == Game.STATE_TITLE:
				game.start_game()
			else:
				game.restart()


func set_prompt(text: String) -> void:
	_prompt.text = text


func show_toast(text: String) -> void:
	_toast.text = text
	_toast_time = 2.4
	_toast.modulate.a = 1.0


func _on_points(p: int) -> void:
	_points.text = str(p)


func _on_round(r: int, dogs: bool) -> void:
	_round.text = "ROUND %d" % r
	_round.add_theme_color_override("font_color", SODIUM if dogs else BLOOD)
	show_toast("HELLHOUNDS" if dogs else "ROUND %d" % r)


func _on_health(hp: float, max_hp: float) -> void:
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	_hp_bar.size.x = 220.0 * frac
	_hp_bar.color = BONE if frac > 0.55 else (SODIUM if frac > 0.25 else BLOOD)
	if frac < 0.999:
		_flash = maxf(_flash, 1.0 - frac)


func _on_weapon(gun: Dictionary) -> void:
	if gun.is_empty():
		return
	var name: String = gun.def.name
	_ammo.text = "%s\n%d / %d" % [name, gun.mag, gun.res]
	_refresh_perks()


func _refresh_perks() -> void:
	for c in _perks.get_children():
		c.queue_free()
	for k in Game.perks:
		var d: Dictionary = Weapons.PERKDEF[k]
		var badge := ColorRect.new()
		badge.custom_minimum_size = Vector2(26, 26)
		badge.color = d.col
		var l := _label(16, ASH, HORIZONTAL_ALIGNMENT_CENTER)
		l.text = d.letter
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		badge.add_child(l)
		_perks.add_child(badge)


func _on_state(s: String) -> void:
	match s:
		"title":
			_overlay.visible = true
			_overlay_title.text = "KRIEGSNACHT"
			_overlay_body.text = "WASD move  ·  SHIFT sprint  ·  MOUSE look  ·  LMB fire\nR reload  ·  F interact  ·  V knife  ·  Q swap  ·  L mouse capture\n\nClick to begin."
		"pause":
			_overlay.visible = true
			_overlay_title.text = "PAUSED"
			_overlay_body.text = "Esc to resume."
		"over":
			_overlay.visible = true
			_overlay_title.text = "YOU DIED"
			_overlay_body.text = "Round %d  ·  %d kills  ·  %d headshots  ·  %d points\n\nClick to try again." % [
				Game.round_no, Game.kills, Game.headshots, Game.points]
		_:
			_overlay.visible = false
