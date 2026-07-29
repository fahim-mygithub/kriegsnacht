extends CanvasLayer

## HUD, title and game-over screens.
##
## In the browser build this was a DOM overlay; here it is a CanvasLayer of
## Controls. The palette is carried over unchanged — the WWII-bunker read
## depends on it.
##
## The screen-effect layer (vignette, damage wash, low-HP pulse, deny flash) is
## four TextureRects sharing one 128x128 radial gradient baked at startup. It is
## a texture and not a shader on purpose: WebGL2 exposes no program-binary API,
## so there is no shader cache on the web, and every new ShaderMaterial costs a
## mid-frame GLSL compile on the main thread the first time it is drawn — for
## every visitor, on every page load. A baked ImageTexture costs zero compiles.

## The weapon state machine, for the reload readout in _on_weapon. preload rather
## than the class name: a freshly added script is not in the class registry until
## the editor rescans, and a headless run has no editor.
const WEAPON := preload("res://scripts/entities/weapon.gd")

const ASH := Color("0b0c0a")
const BONE := Color("d8d2c0")
const BONE_DIM := Color("8c8578")
const BLOOD := Color("8e1116")
const BLOOD_LIT := Color("c4222a")
const SODIUM := Color("e0a62b")
const RAD := Color("7fa83c")
const RUST := Color("3a3129")
const ALT_DIM := Color("5e594e")

## A18. `Game.toast` carries only a string, so a caller that knows better can
## pass a class and everything else is recovered from the text by `_toast_class`.
enum { TOAST_AUTO, TOAST_NEUTRAL, TOAST_GOOD, TOAST_BAD }

## The em dash is load-bearing: the ancestor's bad toast is the bleed-out warning
## "QUICK REVIVE — hold on", while *buying* the perk is a green one, and both
## start with the same two words.
const TOAST_BAD_TEXT := ["INSTA-KILL", "THE BOX HAS MOVED", "QUICK REVIVE —"]
const TOAST_GOOD_TEXT := ["NUKE", "POWER ON", "POWER RESTORED", "BACK ON YOUR FEET"]

## A17. `dmgFlash += 120` per hit, capped at 255, decaying 260/s
## (kriegsnacht.html:2353 and :3367), normalised to 0-1 here.
const DMG_PER_HIT := 120.0 / 255.0
const DMG_DECAY := 260.0 / 255.0

## A16. `opacity = hp/maxHp < 0.34 ? (0.4 + sin(t*7)*0.22) : 0` — a ~1.1 Hz
## pulse confined to the screen edge (kriegsnacht.html:39 and :3377).
const LOWHP_FRAC := 0.34
const LOWHP_RATE := 7.0
const LOWHP_BASE := 0.4
const LOWHP_SWING := 0.22

## A13. `scale(1.13)` for 110 ms; the CSS transition is 100 ms each way, so the
## whole gesture is up-then-down over twice that. The `+N` line lives 700 ms.
## GAIN_Y clears the "POINTS" caption at its *risen* height, not its resting one:
## the caption's glyphs end around y=81 and the line rises GAIN_RISE before it
## dies, so anything under ~100 puts the delta through the caption for the last
## third of its life.
const POP_SCALE := 1.13
const POP_TIME := 0.11
const FLOAT_TIME := 0.7
const GAIN_X := 30.0
const GAIN_Y := 104.0
const GAIN_RISE := 18.0

## A14. `.empty` blinks `0.55s steps(2)` — a hard two-state square wave between
## full and 0.28 opacity, not a fade.
const BLINK_PERIOD := 0.55
const BLINK_LOW := 0.28

## A15. `min(round, 10)` bars, 4x9 px, `skewX(-14deg)`, 5 px apart.
const TALLY_MAX := 10
const TALLY_W := 4.0
const TALLY_H := 9.0
const TALLY_GAP := 5.0
const TALLY_SKEW := 14.0

## A12. Numeral at `clamp(72px, 14vw, 190px)`, snapped to opacity 1 and faded
## over 2.1 s ease-out. This is the fade alone: the card also holds at full
## opacity for `Sfx.ROUND_SILENCE` first, so `_title_t` starts at the sum.
const TITLE_TIME := 2.1
const TITLE_VW := 0.14
const TITLE_MIN := 72
const TITLE_MAX := 190

const VIG_SIZE := 128

var player: Player
var game: Node3D

var _points: Label
var _round: Label
var _ammo: Label
var _altw: Label
var _prompt: Label
var _toast: Label
var _gain: Label
var _hp_bar: ColorRect
var _hp_back: ColorRect
var _stam_bar: ColorRect
var _stam_back: ColorRect
var _perks: HBoxContainer
var _crosshair: Control
var _marker: Control
var _tally: Control
var _hold: ColorRect
var _vignette: TextureRect
var _lowhp: TextureRect
var _dmg: TextureRect
var _deny_rect: TextureRect
var _overlay: Control
var _overlay_title: Label
var _overlay_body: Label
var _downed: Label
var _float_root: Control
var _title_card: Control
var _title_num: Label
var _title_sub: Label
var _vig_tex: ImageTexture

var _toast_time := 0.0
var _flash := 0.0
var _deny := 0.0
var _last_hp := -1.0
var _hp_frac := 1.0

## Hit marker state: ticks scale up and fade, and turn blood-red on a kill.
var _marker_t := 0.0
var _marker_kill := false
var _marker_head := false

var _last_points := 0
var _pop_t := 0.0
var _float_t := 0.0
var _spend := false
var _blink_t := 0.0
var _pulse_t := 0.0
var _title_t := 0.0
var _ammo_empty := false
var _tally_round := 0

## The default theme font has no Dingbats block, so the ✦ the ancestor uses for a
## Pack-a-Punched weapon is resolved against the real font in `_build()` rather
## than assumed — see there.
var _pap_mark := " *"

## Armed only once the pointer lock has actually been observed — see `_process`.
var _lock_seen := false

## The mirror of `_lock_seen` for the way back: armed only once the pointer has
## been observed *released*. Both are cleared by `_on_state`.
var _resume_armed := false


## PROCESS_MODE_ALWAYS, and it has to be ALWAYS rather than WHEN_PAUSED: this
## `_process` is the pause overlay's watchdog *and* the whole HUD's clock, so
## WHEN_PAUSED would leave the bars, the marker and the toast frozen during play —
## the failure mode looks like the HUD being broken rather than like a pause bug.
## The gameplay clocks inside it are gated on the state instead; see `_process`.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func bind(p: Player, g: Node3D) -> void:
	player = p
	game = g
	_build()
	player.health_changed.connect(_on_health)
	player.weapon_changed.connect(_on_weapon)
	player.downed_changed.connect(_on_downed)
	player.hit_confirmed.connect(_on_hit)
	Game.points_changed.connect(_on_points)
	Game.round_changed.connect(_on_round)
	Game.state_changed.connect(_on_state)
	Game.toast.connect(show_toast)
	_last_hp = p.hp
	_last_points = Game.points
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


## The ancestor's per-pixel vignette LUT (kriegsnacht.html:1707-1714) baked once
## into an alpha ramp: 0 at the crosshair, rising to the corners.
##
## `d` is normalised by the half-*diagonal in pixels*, not per axis, so the ramp
## is aspect-dependent: on a 16:9 frame it reaches 0.89 at the left and right
## edges but only 0.58 at the top and bottom — a wide vignette, which is what the
## CSS `#vig` (`ellipse 78% 68%`) agrees it should be. Normalising x and y each
## to [-1,1] and letting the stretch put the aspect back does not reproduce that;
## it transposes the ellipse, giving corner-correct but 0.32/0.50 edges instead
## of 0.61/0.15 — a darker ceiling than walls. So the viewport's half-extents go
## into the coefficients here and the square texture is correct at the aspect it
## was baked for. `canvas_items` stretch with the default `keep` aspect pins that
## aspect for the life of the process, so it is baked once and never revisited.
##
## Quadrant-folded because `d` depends only on px² and py². 16k GDScript
## iterations with a sqrt and a pow apiece is a boot hitch on wasm — this runs
## inside main's `_ready()`, next to Sfx's bake — and it buys nothing.
func _make_vignette_texture(view: Vector2) -> ImageTexture:
	var n := VIG_SIZE
	var half := n >> 1
	var cx := view.x * 0.5
	var cy := view.y * 0.5
	var mr := sqrt(cx * cx + cy * cy)
	# 1.02 horizontally, 1.18 vertically: the ancestor's anisotropy, on top of the
	# aspect. Folded into the axes so the inner loop is one sqrt and one pow.
	var kx := cx / mr * 1.02
	var ky := cy / mr * 1.18
	var data := PackedByteArray()
	data.resize(n * n * 4)
	var step := 2.0 / float(n - 1)
	var off := PackedInt32Array([0, 0, 0, 0])
	for y in half:
		var py := (float(y) * step - 1.0) * ky
		var qy := py * py
		var top := y * n
		var bot := (n - 1 - y) * n
		for x in half:
			var px := (float(x) * step - 1.0) * kx
			var d := minf(1.0, sqrt(px * px + qy))
			var lit := clampf(1.06 - pow(d, 2.7) * 0.92, 0.0, 1.0)
			var a := roundi((1.0 - lit) * 255.0)
			var xm := n - 1 - x
			off[0] = (top + x) * 4
			off[1] = (top + xm) * 4
			off[2] = (bot + x) * 4
			off[3] = (bot + xm) * 4
			for o: int in off:
				data[o] = 255
				data[o + 1] = 255
				data[o + 2] = 255
				data[o + 3] = a
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	return ImageTexture.create_from_image(img)


func _vig_rect(col: Color) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _vig_tex
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	# The project pins the default canvas filter to Nearest for the pixel-art
	# sprites. A 128 px gradient blown up to the viewport under Nearest reads as
	# concentric squares, so this one has to opt back into linear.
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate = col
	return r


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Only the ratio is used, and `canvas_items` stretch keeps it constant, so the
	# fallback exists purely so a viewport that has not been sized yet cannot bake
	# a divide-by-zero into the ramp.
	var view := get_viewport().get_visible_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		view = Vector2(16.0, 9.0)
	_vig_tex = _make_vignette_texture(view)

	# The permanent vignette, the damage wash, the low-HP pulse and the deny
	# flash used to share one ColorRect and a ternary picked whichever was
	# loudest, so they could never overlap and the wash covered the crosshair —
	# exactly backwards from A17. Four nodes, one texture, no arbitration.
	# Corner colour from the ancestor's #vig stop, rgba(4,5,4,.92).
	# 0.58 was the ancestor's strength, but the ancestor stacked it over a
	# raycaster frame that carried its own exposure. Here it lands on a scene that
	# is already dark by three other means — ambient 0.22, fog, and a filmic
	# tonemap — and 0.58 x the ramp's 0.86 corner erased the outer third of the
	# frame: at 960x540 the left and right walls were not merely dim, they were
	# gone. The vignette's job is to make the periphery darker than the centre,
	# not unreadable. Checked against a rendered frame, not reasoned about.
	_vignette = _vig_rect(Color(0.016, 0.020, 0.016, 0.32))
	root.add_child(_vignette)

	# A16 — rgba(140,8,10,.8).
	_lowhp = _vig_rect(Color(0.549, 0.031, 0.039, 0.0))
	# The three transient rects are hidden rather than left at alpha 0. A browser
	# composites an `opacity:0` layer away; Godot still rasterises and blends the
	# quad, and three full-screen blends a frame is not free on a target §1.4f
	# already calls fill-rate-bound.
	_lowhp.visible = false
	root.add_child(_lowhp)

	# A17 — the ancestor pulls red toward 150 and crushes green and blue at half
	# the rate, which an alpha blend of this colour reproduces closely enough.
	_dmg = _vig_rect(Color(0.588, 0.039, 0.047, 0.0))
	_dmg.visible = false
	root.add_child(_dmg)

	_deny_rect = _vig_rect(Color(0.55, 0.10, 0.10, 0.0))
	_deny_rect.visible = false
	root.add_child(_deny_rect)

	_build_title_card(root)

	# points, top-left
	_points = _label(40, SODIUM)
	_points.position = Vector2(28, 20)
	# Scale from the left edge so the pop does not walk the readout off its anchor.
	_points.pivot_offset = Vector2(0, 23)
	root.add_child(_points)

	var plabel := _label(14, RUST)
	plabel.text = "POINTS"
	plabel.position = Vector2(30, 66)
	root.add_child(plabel)

	_float_root = Control.new()
	_float_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_float_root)

	# A13 — the floating +N / -N delta.
	_gain = _label(17, RAD)
	_gain.position = Vector2(GAIN_X, GAIN_Y)
	_gain.size = Vector2(300, 22)
	_gain.modulate.a = 0.0
	_float_root.add_child(_gain)

	# round, bottom-left
	_round = _label(46, BLOOD)
	_round.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_round.position = Vector2(28, -96)
	root.add_child(_round)

	# A15 — the tally pips, drawn under the round numeral.
	_tally = Control.new()
	_tally.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tally.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tally.draw.connect(_draw_tally)
	root.add_child(_tally)

	# health bar, bottom-left above round. ColorRect defaults to MOUSE_FILTER_STOP,
	# so every bar on screen was quietly eating clicks that landed on it — which
	# now matters, because the resume click has to reach the player unhandled.
	_hp_back = ColorRect.new()
	_hp_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_back.position = Vector2(28, -132)
	_hp_back.size = Vector2(220, 10)
	_hp_back.color = Color(0, 0, 0, 0.55)
	_hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_back)

	_hp_bar = ColorRect.new()
	_hp_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_bar.position = Vector2(28, -132)
	_hp_bar.size = Vector2(220, 10)
	_hp_bar.color = BONE
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hp_bar)

	# stamina, a thinner bar under health — sprint is a resource now, so it has
	# to be visible or running out reads as the game breaking.
	_stam_back = ColorRect.new()
	_stam_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stam_back.position = Vector2(28, -118)
	_stam_back.size = Vector2(220, 5)
	_stam_back.color = Color(0, 0, 0, 0.45)
	_stam_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stam_back)

	_stam_bar = ColorRect.new()
	_stam_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stam_bar.position = Vector2(28, -118)
	_stam_bar.size = Vector2(220, 5)
	_stam_bar.color = Color(RAD.r, RAD.g, RAD.b, 0.75)
	_stam_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_stam_bar)

	# perks strip
	_perks = HBoxContainer.new()
	_perks.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_perks.position = Vector2(28, -172)
	_perks.add_theme_constant_override("separation", 6)
	root.add_child(_perks)

	# A14 — the alt-weapon line, above the ammo block because the ammo readout's
	# second line already runs down to the bottom edge.
	_altw = _label(13, ALT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_altw.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_altw.position = Vector2(-320, -124)
	_altw.size = Vector2(290, 18)
	root.add_child(_altw)

	# ammo, bottom-right
	_ammo = _label(38, BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# Two lines of 38 px need ~92 px, against the 50 this rect used to claim from
	# an offset of -96 — so the reserve count sat on, and just past, the bottom
	# edge. Pre-existing, and invisible until a screenshot was taken at 540p.
	_ammo.position = Vector2(-320, -104)
	_ammo.size = Vector2(290, 96)
	root.add_child(_ammo)

	# A14's ✦ is U+2726, which lives in Dingbats. The project configures no theme
	# and no font, so this is Godot's default Open Sans, whose coverage stops well
	# short of that block and which has no fallback chain — an unchecked ✦ is a
	# tofu box on every Pack-a-Punched weapon, in the editor and in the browser
	# alike. The em dash and middle dot elsewhere in this file prove nothing about
	# Dingbats, so ask the font instead of guessing, and keep the asterisk the
	# port already shipped as the answer when it says no.
	var f := _ammo.get_theme_font("font")
	if f != null and f.has_char(0x2726):
		_pap_mark = " ✦"

	# crosshair
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	root.add_child(_crosshair)

	# hit marker, its own layer so it can redraw without touching the crosshair
	_marker = Control.new()
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	root.add_child(_marker)

	# interact prompt
	_prompt = _label(22, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-400, -190)
	_prompt.size = Vector2(800, 30)
	root.add_child(_prompt)

	# hold-to-interact progress, directly under the prompt
	_hold = ColorRect.new()
	_hold.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hold.position = Vector2(-90, -158)
	_hold.size = Vector2(0, 4)
	_hold.color = SODIUM
	_hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hold)

	_downed = _label(30, BLOOD, HORIZONTAL_ALIGNMENT_CENTER)
	_downed.set_anchors_preset(Control.PRESET_CENTER)
	_downed.position = Vector2(-400, -40)
	_downed.size = Vector2(800, 80)
	_downed.visible = false
	root.add_child(_downed)

	# toast
	_toast = _label(34, SODIUM, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-400, 120)
	_toast.size = Vector2(800, 44)
	_toast.modulate.a = 0.0
	root.add_child(_toast)

	_build_overlay(root)


## A12. Backdrop is the ancestor's radial blood wash — rgba(120,8,10,.30) at the
## centre falling to rgba(10,2,2,.86) at the edge — which is a flat rect plus the
## shared vignette ramp rather than a second gradient texture.
func _build_title_card(root: Control) -> void:
	_title_card = Control.new()
	_title_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_card.visible = false
	root.add_child(_title_card)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.47, 0.031, 0.039, 0.30)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_card.add_child(bg)

	_title_card.add_child(_vig_rect(Color(0.039, 0.008, 0.008, 0.72)))

	_title_num = _label(TITLE_MAX, BLOOD_LIT, HORIZONTAL_ALIGNMENT_CENTER)
	_title_num.set_anchors_preset(Control.PRESET_CENTER)
	_title_num.position = Vector2(-500, -140)
	_title_num.size = Vector2(1000, 200)
	_title_num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_card.add_child(_title_num)

	_title_sub = _label(15, BONE_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_title_sub.set_anchors_preset(Control.PRESET_CENTER)
	_title_sub.position = Vector2(-500, 70)
	_title_sub.size = Vector2(1000, 24)
	_title_card.add_child(_title_sub)


func _build_overlay(root: Control) -> void:
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Nothing here is clickable, and STOP swallowed the button event before
	# _unhandled_input could see it — which is where the resume click has to
	# land, because that is the only place transient activation exists.
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(ASH.r, ASH.g, ASH.b, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


## Four ticks at 45 degrees that snap outward and fade. Fires on every damaging
## hit, not only on kills — confirming the shot is the entire point, and firing
## a weapon previously produced no visible change anywhere on screen.
func _draw_marker() -> void:
	if _marker_t <= 0.0:
		return
	var c := _marker.size * 0.5
	var k := 1.0 - _marker_t / 0.22
	var scale := lerpf(0.55, 1.0, minf(1.0, k * 2.2))
	var alpha := clampf(_marker_t / 0.22, 0.0, 1.0)
	var col := BONE
	if _marker_kill:
		col = Color("c4222a")
	elif _marker_head:
		col = SODIUM
	col.a = alpha
	var inner := 5.0 * scale
	var outer := 13.0 * scale
	for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		_marker.draw_line(c + d * inner, c + d * outer, col, 2.0)


## A15. One pip a round to ten, sheared 14 degrees. Past round ten the tenth pip
## turns sodium — that colour change is the only signal the row has stopped
## counting, so it carries the whole readout after round ten.
func _draw_tally() -> void:
	if _tally_round <= 0:
		return
	var n := mini(_tally_round, TALLY_MAX)
	var x0 := 28.0
	var y0 := _tally.size.y - 36.0
	var skew := tan(deg_to_rad(TALLY_SKEW)) * TALLY_H
	for i in n:
		var x := x0 + float(i) * (TALLY_W + TALLY_GAP)
		var col := SODIUM if (_tally_round > TALLY_MAX and i == TALLY_MAX - 1) else BLOOD
		# Stands in for the ancestor's 6 px box-shadow glow.
		_tally.draw_colored_polygon(PackedVector2Array([
			Vector2(x - 2.0, y0 - 2.0),
			Vector2(x + TALLY_W + 2.0, y0 - 2.0),
			Vector2(x + TALLY_W + 2.0 - skew, y0 + TALLY_H + 2.0),
			Vector2(x - 2.0 - skew, y0 + TALLY_H + 2.0),
		]), Color(col.r, col.g, col.b, 0.26))
		_tally.draw_colored_polygon(PackedVector2Array([
			Vector2(x, y0),
			Vector2(x + TALLY_W, y0),
			Vector2(x + TALLY_W - skew, y0 + TALLY_H),
			Vector2(x - skew, y0 + TALLY_H),
		]), col)


func _process(dt: float) -> void:
	var playing := Game.state == Game.STATE_PLAY

	# EVERY CLOCK ON THIS SCREEN IS THE PLAY CLOCK, and this node is one of the
	# three that keep processing while the tree is paused — so the gate below is
	# what stops the pause overlay eating the toast, the hit marker and the damage
	# wash that were on screen when the player hit P. The ancestor's frame loop
	# does exactly this: `G.dmgFlash`, `G.shake` and `G.t` all decay inside
	# `if(G.state==='play')` (kriegsnacht.html:3350-3369) while the renderer keeps
	# drawing the frozen frame (:3393).
	#
	# The rects are left showing whatever they were showing. That is what frozen
	# means, and re-asserting values that cannot have changed would be work.
	if playing:
		if _toast_time > 0.0:
			_toast_time -= dt
			_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)

		# The wash decays on its own clock and is refreshed only by an actual damage
		# event. It used to be recomputed from the current health fraction on every
		# health_changed emission — including the per-frame regen ticks — so it sat
		# on screen continuously the whole time you were hurt instead of flashing.
		if _flash > 0.0:
			_flash = maxf(0.0, _flash - dt * DMG_DECAY)
		if _deny > 0.0:
			_deny = maxf(0.0, _deny - dt * 3.8)
		# A17: because the shared ramp is zero at the crosshair and peaks in the
		# corners, the wash is strongest exactly where the vignette is darkest and
		# never touches the centre of the screen — `k = (dmg*(255-v))>>8`.
		_dmg.modulate.a = _flash
		_dmg.visible = _flash > 0.0
		_deny_rect.modulate.a = _deny * 0.42
		_deny_rect.visible = _deny > 0.0

		if _marker_t > 0.0:
			_marker_t = maxf(0.0, _marker_t - dt)
			_marker.queue_redraw()

		_pulse_t += dt
		_blink_t += dt
		_pop_t = maxf(0.0, _pop_t - dt)
		_float_t = maxf(0.0, _float_t - dt)
		_title_t = maxf(0.0, _title_t - dt)

	# Not a clock: the stamina bar is a readout of a value that simply cannot move
	# while the player's own physics step is frozen, so gating it would only mean
	# it could be stale after a state change rather than merely idle.
	if player and is_instance_valid(player):
		_stam_bar.size.x = 220.0 * player.stamina()
		_stam_back.visible = player.stamina() < 0.999
		_stam_bar.visible = _stam_back.visible

	# A16: an edge-weighted ~1.1 Hz pulse under a third health.
	var pulse := 0.0
	if playing and _hp_frac < LOWHP_FRAC:
		pulse = maxf(0.0, LOWHP_BASE + sin(_pulse_t * LOWHP_RATE) * LOWHP_SWING)
	_lowhp.modulate.a = pulse
	_lowhp.visible = pulse > 0.0

	# A13: the pop ramps up over POP_TIME and back down over the next, which is
	# what the CSS `transition:transform .1s` plus a 110 ms class does.
	if _pop_t > 0.0:
		var pk := _pop_t / (POP_TIME * 2.0)
		_points.scale = Vector2.ONE * (1.0 + (POP_SCALE - 1.0) * (1.0 - absf(pk * 2.0 - 1.0)))
	elif _points.scale.x != 1.0:
		_points.scale = Vector2.ONE

	if _float_t > 0.0:
		var f := _float_t / FLOAT_TIME
		_gain.modulate.a = clampf(f * 1.8, 0.0, 1.0)
		_gain.position.y = GAIN_Y - (1.0 - f) * GAIN_RISE
	elif _gain.modulate.a > 0.0:
		_gain.modulate.a = 0.0
		if _spend:
			_spend = false
			_points.add_theme_color_override("font_color", SODIUM)

	# A14: `steps(2)` is a square wave, so this is a hard two-state flip rather
	# than a fade — an empty magazine should read as broken, not as breathing.
	if _ammo_empty:
		_ammo.modulate.a = 1.0 if fmod(_blink_t, BLINK_PERIOD) < BLINK_PERIOD * 0.5 else BLINK_LOW

	if _title_t > 0.0:
		# The card goes up on the round change and the sting lands
		# `Sfx.ROUND_SILENCE` later, so it holds at full opacity through the beat
		# and only then starts fading — the ancestor fires both in the same frame
		# (html:2865-2867), and against the beat that leaves the numeral two-thirds
		# gone before the toll it is announcing arrives.
		#
		# `transition: opacity 2.1s ease-out` from 1 to 0 — squaring the
		# remaining fraction is that curve.
		var tk := minf(1.0, _title_t / TITLE_TIME)
		_title_card.modulate.a = tk * tk
	elif _title_card.visible:
		_title_card.visible = false

	# Losing the pointer lock IS the pause event. `requestPointerLock()` needs
	# transient activation and WHATWG explicitly excludes Escape from the input
	# events that grant it, so the old "Esc to resume -> set_capture(true)" path
	# could never re-lock in any browser. Inverting it is also correct when the
	# player alt-tabs or the tab loses focus.
	#
	# The detector arms only once the lock has actually been observed. On web the
	# grant is asynchronous, so the frames between start_game()'s set_capture(true)
	# and the browser honouring it would otherwise pause the game instantly on
	# every start; the same guard is what keeps a headless run (which can never
	# capture at all) from pausing itself. DisplayServerWeb::mouse_get_mode()
	# queries the browser live in 4.7 — the 4.4-era desync was fixed by PR
	# #102719 — so polling Input.mouse_mode is a reliable detector.
	if Game.state == Game.STATE_PLAY:
		# ...unless something outside the state machine is holding the tree. The two
		# move together — Game.set_state is the only writer of both — so a paused
		# tree during play can only be an external holder, and the debug console is
		# one: it takes `get_tree().paused` and releases the pointer so its LineEdit
		# can be typed into. Without this the watchdog reads that release as an
		# alt-tab and pauses the run, and closing the console restores the tree to
		# a state machine now stuck in STATE_PAUSE with a pointer it never lost —
		# neither branch below can resume from that, so the overlay stays up until
		# the player clicks. Standing down keeps `_lock_seen` unarmed through the
		# hold too, which is what makes the first frame after it re-arm correctly.
		if not get_tree().paused:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_lock_seen = true
			if Input.is_action_just_pressed("pause"):
				_pause()
			elif _lock_seen and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				_pause()
	elif Game.state == Game.STATE_PAUSE:
		# Whoever wins the mouse back is the resume: the click path lives in the
		# player, and toggle_capture (L) has to land somewhere coherent too —
		# L releases the mouse and pauses, L again takes it back and resumes.
		#
		# Armed only after the pointer has been observed released, which is the
		# mirror of _lock_seen and load-bearing for the same reason: exitPointerLock()
		# is asynchronous too, so pausing with P while still locked leaves
		# document.pointerLockElement set for a frame or two and an unarmed check
		# reads that as the resume gesture — the pause would flicker straight back
		# to play and only stick once the release finally landed.
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			_resume_armed = true
		elif _resume_armed:
			Game.set_state(Game.STATE_PLAY)

	if Game.state == Game.STATE_TITLE or Game.state == Game.STATE_OVER:
		if Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("interact"):
			if Game.state == Game.STATE_TITLE:
				game.start_game()
			else:
				game.restart()


## Pausing never re-captures. Resume is a click, which is the only gesture that
## carries the transient activation the browser demands. `_on_state` disarms both
## watchdogs on the way through, so neither is touched here.
func _pause() -> void:
	Game.set_state(Game.STATE_PAUSE)
	Player.set_capture(false)


func set_prompt(text: String, affordable := true) -> void:
	_prompt.text = text
	_prompt.add_theme_color_override("font_color",
		BONE if affordable else Color(BLOOD.r + 0.25, BLOOD.g + 0.08, BLOOD.b + 0.08))


func set_hold(fraction: float) -> void:
	_hold.size.x = 180.0 * clampf(fraction, 0.0, 1.0)


func flash_deny() -> void:
	_deny = 1.0


func show_toast(text: String, cls := TOAST_AUTO) -> void:
	_toast.text = text
	_toast_time = 2.4
	_toast.modulate.a = 1.0
	var c: int = cls if cls != TOAST_AUTO else _toast_class(text)
	match c:
		TOAST_GOOD:
			_toast.add_theme_color_override("font_color", RAD)
		TOAST_BAD:
			_toast.add_theme_color_override("font_color", BLOOD_LIT)
		_:
			_toast.add_theme_color_override("font_color", SODIUM)


## A18. Every toast was sodium. `Game.toast` carries only a string, so the class
## is recovered from the text using the ancestor's own call sites
## (kriegsnacht.html 2367/2376/2428/2779/2787/2794/2828): green for something
## gained for good, red for a warning, sodium for an ordinary purchase.
func _toast_class(text: String) -> int:
	var t := text.to_upper()
	for s: String in TOAST_BAD_TEXT:
		if t.begins_with(s):
			return TOAST_BAD
	for s: String in TOAST_GOOD_TEXT:
		if t.begins_with(s):
			return TOAST_GOOD
	for k: String in Weapons.PERKDEF:
		var d: Dictionary = Weapons.PERKDEF[k]
		var pname: String = d.name
		if t.begins_with(pname.to_upper()):
			return TOAST_GOOD
	for k: String in Weapons.PAP_NAMES:
		var pap: String = Weapons.PAP_NAMES[k]
		if t == pap.to_upper():
			return TOAST_GOOD
	return TOAST_NEUTRAL


func _on_hit(headshot: bool, killed: bool) -> void:
	_marker_t = 0.22
	_marker_kill = killed
	_marker_head = headshot
	_marker.queue_redraw()


func _on_points(p: int) -> void:
	var delta := p - _last_points
	_last_points = p
	_points.text = _commas(p)
	# Points move outside play too — the starting stake, and reset_run() on a
	# restart — and neither of those is a gameplay event worth announcing.
	if delta == 0 or Game.state != Game.STATE_PLAY:
		return
	_pop_t = POP_TIME * 2.0
	_gain.text = ("+" if delta > 0 else "") + _commas(delta)
	_gain.add_theme_color_override("font_color", RAD if delta > 0 else BLOOD_LIT)
	_gain.position = Vector2(GAIN_X, GAIN_Y)
	_float_t = FLOAT_TIME
	# A spend turns the number blood-red. The ancestor leaves the class on until
	# the next points event, which in this port can be a whole round; bounding it
	# to the life of the floating delta keeps it reading as a flash.
	_spend = delta < 0
	_points.add_theme_color_override("font_color", BLOOD_LIT if _spend else SODIUM)


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


func _on_round(r: int, dogs: bool) -> void:
	_round.text = "ROUND %d" % r
	_round.add_theme_color_override("font_color", SODIUM if dogs else BLOOD)
	_tally_round = r
	_tally.queue_redraw()
	# The title card supersedes the toast for the round announcement; showing
	# both put the same words on screen twice, 200 px apart.
	_show_title_card(r, dogs)


## A12. The numeral is `clamp(72px, 14vw, 190px)` in the ancestor's CSS, so it is
## recomputed from the viewport each round rather than frozen at one size.
func _show_title_card(r: int, dogs: bool) -> void:
	var vw := get_viewport().get_visible_rect().size.x
	_title_num.add_theme_font_size_override("font_size",
		clampi(roundi(vw * TITLE_VW), TITLE_MIN, TITLE_MAX))
	_title_num.text = str(r)
	# A hound round gets its own cue, its own subtitle and its own colour in the
	# corner readout; the numeral on the card was the one place the distinction
	# went missing, which left the loudest element on screen saying nothing.
	_title_num.add_theme_color_override("font_color", SODIUM if dogs else BLOOD_LIT)
	# The ancestor's full set: hounds get their own line, round one gets the
	# opener, and every other round shows the numeral alone.
	var sub := ""
	if dogs:
		sub = "the hounds are loose"
	elif r == 1:
		sub = "the dead are coming"
	_title_sub.text = _spaced(sub)
	_title_card.visible = true
	_title_card.modulate.a = 1.0
	# Held at full opacity through the sting's beat of silence and faded across
	# A12's 2.1 s afterwards, so the numeral is still whole when the toll lands.
	# See `_process` for the curve.
	_title_t = TITLE_TIME + Sfx.ROUND_SILENCE


## Label has no letter-spacing property and the subtitle is tracked at 0.5em in
## the ancestor. One space between glyphs lands close at this size, and costs
## nothing — a FontVariation would mean a second font resource for one line.
func _spaced(s: String) -> String:
	var out := ""
	for i in s.length():
		if i > 0:
			out += " "
		out += s[i]
	return out


func _on_health(hp: float, max_hp: float) -> void:
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	_hp_frac = frac
	_hp_bar.size.x = 220.0 * frac
	_hp_bar.color = BONE if frac > 0.55 else (SODIUM if frac > 0.25 else BLOOD)
	# Only an actual drop counts as being hit.
	if _last_hp >= 0.0 and hp < _last_hp - 0.01:
		# A17: accumulates rather than resetting, so a second hit inside the
		# decay window washes the screen harder than the first.
		_flash = minf(1.0, _flash + DMG_PER_HIT)
	_last_hp = hp


func _on_downed(is_down: bool, time_left: float) -> void:
	_downed.visible = is_down
	if is_down:
		_downed.text = "YOU ARE DOWN\nbleeding out — %d" % ceili(time_left)


func _on_weapon(gun: Dictionary) -> void:
	if gun.is_empty():
		return
	var gun_name: String = gun.def.name
	var mag: int = gun.mag
	var reloading: float = gun.reloading
	# A shell reload puts rounds in one at a time and emits weapon_changed on each,
	# so the count is live and worth watching — it is the whole point of loading
	# shell by shell. A magazine reload has nothing to show until it lands, which
	# is what "--" is for.
	var by_shell: bool = gun.state == WEAPON.State.RELOAD_SHELL
	var mag_txt := "--" if reloading > 0.0 and not by_shell else str(mag)
	# A14: a Pack-a-Punched weapon carries a trailing ✦ where the font has one.
	_ammo.text = "%s%s\n%s / %d" % [gun_name, _pap_mark if gun.pap else "", mag_txt, gun.res]

	# `.low` stops at one round so it never fights `.empty`, which owns zero.
	var cap: int = int(gun.def.mag)
	var low := mag > 0 and float(mag) <= float(cap) * 0.25
	_ammo.add_theme_color_override("font_color", SODIUM if low else BONE)
	_ammo_empty = mag <= 0 and reloading <= 0.0
	if not _ammo_empty:
		_ammo.modulate.a = 1.0

	# A14: the other gun, so swapping is a decision rather than a discovery.
	_altw.text = ""
	if player and is_instance_valid(player) and player.guns.size() == 2:
		var alt: Dictionary = player.guns[1 - player.slot]
		var alt_name: String = alt.def.name
		_altw.text = "[Q] %s   %d / %d" % [alt_name, alt.mag, alt.res]

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
	# Any transition disarms both pointer-lock watchdogs; each branch of _process
	# re-arms its own on the first frame it observes the condition it waits for.
	_lock_seen = false
	_resume_armed = false
	# The pop, the floating delta and the round card all run off the play clock,
	# so a state change mid-animation strands them: the death screen would carry a
	# half-faded round numeral and a blood-red points readout into the next run,
	# because _on_points refuses to touch either outside play.
	_title_t = 0.0
	_title_card.visible = false
	_float_t = 0.0
	_gain.modulate.a = 0.0
	_pop_t = 0.0
	_points.scale = Vector2.ONE
	_spend = false
	_points.add_theme_color_override("font_color", SODIUM)
	match s:
		"title":
			_overlay.visible = true
			_overlay_title.text = "KRIEGSNACHT"
			var best := ""
			if Game.profile.best_round > 0:
				best = "\n\nbest: round %d  ·  %s points" % [
					Game.profile.best_round, _commas(Game.profile.best_points)]
			_overlay_body.text = "WASD move  ·  SHIFT sprint  ·  MOUSE look  ·  LMB fire\nR reload  ·  F interact / hold to rebuild  ·  V knife  ·  Q swap\n\nClick to begin." + best
		"pause":
			_overlay.visible = true
			_overlay_title.text = "PAUSED"
			# Not "Esc to resume": Escape is excluded from the input events that
			# grant transient activation, so it can never re-lock the pointer.
			_overlay_body.text = "Click to resume."
		"over":
			_overlay.visible = true
			_overlay_title.text = "YOU DIED"
			_overlay_body.text = "Round %d  ·  %d kills  ·  %d headshots  ·  %s points\n\nClick to try again." % [
				Game.round_no, Game.kills, Game.headshots, _commas(Game.points)]
		_:
			_overlay.visible = false
			_downed.visible = false
