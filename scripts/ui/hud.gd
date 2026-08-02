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

## --- accessibility -----------------------------------------------------------
##
## Four Settings keys land in this file because this file owns every node they
## touch. Applying them from the menu instead would put a second writer on
## `_dmg.modulate` and on the toast colour, and the first time one of them stuck
## on there would be no way to tell which author left it there.
##
## Milestone 1 made directional audio the PRIMARY threat cue and Milestone 2
## added a flash, a wash, a pulse and a shake on top of it. Both changes made the
## game harder to play for somebody it was already harder for, so none of what is
## below is decoration: `captions` is the only channel a deaf player has for the
## groan behind them, and `damage_arrows` is the only one for which direction it
## came from.

## Longer than the toast's 2.4 s because a caption is read rather than glanced
## at, and three is what fits between the prompt and the crosshair.
const CAPTION_LIFE := 3.0
const CAPTION_MAX := 3

## Long enough to survive the two-hit death an unperked player takes at 60 damage
## a swing (see `--verify`'s "2 hits to down unperked"), so the arrow from the
## first hit is still up when the second lands.
const ARROW_LIFE := 1.5

## `take_damage(amount, from)` carries the attacker's instance id but
## `health_changed` does not, and widening that signal would break every listener
## for one consumer. The attacker is recovered instead: a zombie only damages at
## `melee_reach` (zombie.gd:146, 1.15 m; hounds 1.05), so the nearest live body
## inside twice that is the one that just swung. Doubled rather than tight
## because the hit lands on the physics step and this reads on the frame step,
## with both bodies having moved in between.
const ARROW_RANGE := 2.5
const ARROW_RADIUS := 104.0
const ARROW_LEN := 26.0
const ARROW_HALF := 11.0

## Directly ahead and directly behind are cones rather than points: "ahead" is
## the leading quarter-turn, "behind" the trailing one, and the two flanks split
## what is left. Words rather than glyphs because the default theme font is Open
## Sans with no fallback chain — the ✦ probe below is what that costs.
const CAPTION_AHEAD := PI * 0.25
const CAPTION_BEHIND := PI * 0.75

## Distance past which a positional cue is captioned without a direction. Matches
## sfx.gd's MAX_DIST_VOICE: past it the voice is culled entirely, so a caption
## claiming a bearing would be describing a sound that was never played.
const CAPTION_DIST := 20.0

## Meaning-bearing hues, per Settings.colourblind. Indexed [mode][slot], mode in
## the same order as the Settings contract (0 none, 1 protanopia, 2 deuteranopia,
## 3 tritanopia).
##
## What is actually being fixed is ONE collision: RAD (#7fa83c, olive green) reads
## "gained" and BLOOD_LIT (#c4222a) reads "lost", and under protanopia and
## deuteranopia those are the same colour. Green moves to a sky blue in both,
## which no other HUD element uses. Red is left alone under deuteranopia — a
## deuteranope sees it as a distinct dark warm — and lightened under protanopia,
## where long wavelengths lose most of their luminance and #c4222a lands close to
## black on a plate that is already nearly black.
##
## Tritanopia does not confuse red and green at all; it confuses blue and yellow,
## so the pair above is left alone and SODIUM (#e0a62b) — which sits against BONE
## (#d8d2c0) on the points readout — moves to a pink instead.
##
## Hue is never the only channel either way: every call site below also carries a
## sign, a letter, a word or a shape. This makes the two readable at a glance; the
## second channel is what makes them readable at all.
enum { HUE_GOOD, HUE_BAD, HUE_WARN }
const CB_HUES := [
	[RAD, BLOOD_LIT, SODIUM],
	[Color("56b4e9"), Color("f2705a"), SODIUM],
	[Color("56b4e9"), BLOOD_LIT, SODIUM],
	[RAD, BLOOD_LIT, Color("e8709f")],
]

## The audio-only channels that no signal on Game or Player exposes, matched by
## PREFIX so `groan0`..`groan3` (one per zombie palette, sfx.gd's play_at at
## zombie.gd:535) are one row rather than four that a fifth palette would break.
##
## Reached through Sfx's `cue` signal, which this package does not own — see the
## guard in bind(). The round sting, the box and the power are deliberately NOT
## here: this file can observe all three without the signal, and a cue row for
## them would caption each of them twice the moment the signal lands.
const CUE_CAPTIONS := [
	["groan", "zombie groans"],
	["bark", "hound snarls"],
	["board", "boards splintering"],
	["melee", "a swing connects"],
]

## Under reduce_motion the two pure flashes go to zero and the low-HP edge is
## pinned to the MIDDLE of its swing rather than switched off. The flashes carry
## nothing the wash's own colour and the hit marker do not; the low-HP edge is the
## only warning that health is critical, and a player who turned motion off is not
## asking to stop being told they are about to die.
const LOWHP_STATIC := LOWHP_BASE

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
var _readouts: Control
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

## Same probe, same reason: U+2717 is Dingbats too. "X" is the answer when the
## font says no, and it is the second channel on an unaffordable prompt — see
## `set_prompt`, where red-on-its-own was the whole signal.
var _deny_mark := "X  "

## menu.gd, or null on a build that has not wired one yet. Untyped for the reason
## `game` would be if it were not a Node3D: the script is attached at runtime, so
## a typed handle could not see press_primary().
var _menu

## Cached from Settings.changed rather than read per frame — four autoload
## property reads a frame, times a `_process` that already does real work.
var _reduce_motion := false
var _captions_on := false
var _arrows_on := true
var _colourblind := 0

## Live captions, newest last: [{"text": String, "t": float}]. Rendered into the
## three fixed labels rather than into created-and-freed ones, because a cue can
## arrive on any frame and allocating a Control per zombie groan is not free.
var _caps: Array[Dictionary] = []
var _cap_labels: Array[Label] = []
var _cap_box: VBoxContainer

## Live damage arrows: [{"angle": float, "t": float}]. Screen-space bearing,
## resolved once at the moment of the hit — an arrow that tracked its attacker
## would swing while the player turned, which reads as the arrow being wrong
## rather than as the player having turned.
var _arrows: Array[Dictionary] = []
var _arrow_layer: Control
var _hp_hatch: Control

## Deferred so the round caption lands with the toll rather than with the card —
## Sfx.round_ceremony holds ROUND_SILENCE seconds of nothing first (sfx.gd:750).
var _round_cap_t := 0.0
var _round_cap_r := 0

## Edge detectors for the two cues this file can observe without reaching into a
## system it does not own: the box's own state accessor and Game.power_on.
var _box_state := ""
var _power_seen := false

## THE PERK STRIP IS POLLED, and that is the fix for a bug that survived three
## milestones: `_refresh_perks()` was reachable from `_on_weapon` and from nowhere
## else, so BUYING A PERK DID NOT LIGHT ITS BADGE until the next shot, reload or
## swap. It was live enough that two other files had already grown a workaround
## for it rather than a fix — player.gd emits a spare `weapon_changed` from
## `_go_down`, beside its `Game.perks.erase("revive")`, with a comment naming
## this exact cause; console.gd's `perk` command has no workaround at all, so a
## perk granted from the console stays invisible until you shoot.
##
## Removing the call from `_on_weapon` fixes a second thing hiding in the same
## line. `weapon_changed` is emitted on EVERY SHOT — the last line of `_shoot` —
## so the strip was freeing and reallocating up to four ColorRects and four
## Labels 14.7 times a second while an MP40 was held down. The strip changes a
## handful of times in a run; it was being rebuilt thousands.
##
## Polled and not signalled, deliberately. `Game.perks` is a plain public
## Dictionary with FIVE writers outside this file — the perk machine in
## interaction_system.gd, `_go_down`'s erase, `reset_run`'s clear, the console's
## `perk` command and the assertion suite — so a `perks_changed` signal would have
## to be emitted by every one of them, and the failure mode of a missed emission is
## exactly the bug being fixed, silently stale, again. A signal is right only once
## the dictionary is private behind a mutator; until then the poll is the only
## detector that cannot be forgotten. It costs one `Dictionary.hash()` over at most
## four entries per frame.
var _perks_key := 0

## The third edge detector, and the one that is not optional: `downed_changed`
## arrives every frame while down rather than on the transition. See `_on_downed`.
var _downed_seen := false

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
	Settings.changed.connect(_on_setting)
	# The Sfx cue channel is what carries the zombie vocalisations, which are the
	# ones this file cannot observe any other way — a groan is a timer inside
	# zombie.gd and nothing it touches is public. Guarded rather than assumed,
	# because the signal is a one-line addition to sfx.gd that this package does
	# not own: without it captions still cover the round sting, the box and the
	# power, and the guard is what keeps the HUD from failing to bind at all.
	if Sfx.has_signal("cue"):
		Sfx.cue.connect(_on_cue)
	_read_settings()
	_last_hp = p.hp
	_last_points = Game.points
	_on_health(player.hp, Game.max_health())
	_on_weapon(player.current_gun())
	_on_points(Game.points)
	# Drawn once here rather than as a side effect of the weapon readout, and the
	# fingerprint is taken from the same state that was just drawn so the first
	# `_process` cannot rebuild a strip that is already correct.
	_refresh_perks()
	_perks_key = Game.perks.hash()


## menu.gd hands itself over here. Two things change: this file stops drawing its
## own title/pause/over plates, because the menu draws better ones with real
## buttons on them, and `_poll_menu_click` narrows to the game-over screen — the
## title screen's three buttons become the only way into a run, for the reason
## written out over that function. Unbinding restores both.
func set_menu(m) -> void:
	_menu = m
	# Re-run the state handler either way: binding has to hide this file's own
	# screens and its readouts, and unbinding has to put both back, and there is
	# exactly one place that decides what each state looks like.
	_on_state(["title", "play", "pause", "over"][Game.state])


func _on_setting(_key: String) -> void:
	_read_settings()


## Applied live, never at boot only. An accessibility option is opened *because*
## something is already uncomfortable, and one that needs a restart cannot be
## evaluated by the person who needs it.
func _read_settings() -> void:
	_reduce_motion = bool(Settings.reduce_motion)
	_captions_on = bool(Settings.captions)
	_arrows_on = bool(Settings.damage_arrows)
	_colourblind = clampi(int(Settings.colourblind), 0, CB_HUES.size() - 1)
	if _reduce_motion:
		# Cancelling what is already in flight, for the same reason player.gd
		# zeroes its shake here: otherwise the flash that sent the player to the
		# options screen goes on decaying underneath it.
		_flash = 0.0
		_deny = 0.0
	if not _captions_on:
		_caps.clear()
		_refresh_captions()
	if not _arrows_on:
		_arrows.clear()
		_arrow_layer.queue_redraw()
	# Re-assert everything whose colour is a decision rather than a constant. The
	# points readout and the toast are both mid-flight state, so neither would
	# pick the new palette up until the next event that happened to rewrite it.
	_points.add_theme_color_override("font_color",
		_hue(HUE_BAD) if _spend else _hue(HUE_WARN))
	_gain.add_theme_color_override("font_color",
		_hue(HUE_GOOD) if _gain.text.begins_with("+") else _hue(HUE_BAD))
	# The downed readout is written on the edge rather than per frame, so it is the
	# one meaning-bearing colour that would otherwise sit on the old palette for as
	# long as the player stayed down — which is the whole time it is on screen.
	_downed.add_theme_color_override("font_color", _hue(HUE_BAD))
	_hp_hatch.queue_redraw()
	_tally.queue_redraw()


## The one place a meaning-bearing hue is chosen. Everything that used a literal
## RAD / BLOOD_LIT / SODIUM to mean good, bad or warn goes through here instead,
## so adding a colour-vision mode is a row in CB_HUES rather than a search.
func _hue(slot: int) -> Color:
	var row: Array = CB_HUES[_colourblind]
	return row[slot]


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

	# EVERY GAMEPLAY READOUT LIVES UNDER ONE NODE, so the menu can take the screen
	# without them showing through it. Before menu.gd there was nothing to hide
	# behind: this file's own full-screen `_overlay` covered the lot at 92% ash on
	# the title and game-over screens. The menu draws a centred plate instead, and
	# the first capture of it had a starting stake of 500 points and a full M1911
	# magazine sitting behind a screen already reporting the run's real numbers.
	#
	# Nothing above this line joins it: the vignette, the wash, the low-HP edge and
	# the round card are screen effects rather than readouts, and the ancestor
	# keeps its own frame — vignette and all — visible behind every screen
	# (html:3393 goes on drawing while `G.state !== 'play'`).
	_readouts = Control.new()
	_readouts.set_anchors_preset(Control.PRESET_FULL_RECT)
	_readouts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_readouts)

	# points, top-left
	_points = _label(40, SODIUM)
	_points.position = Vector2(28, 20)
	# Scale from the left edge so the pop does not walk the readout off its anchor.
	_points.pivot_offset = Vector2(0, 23)
	_readouts.add_child(_points)

	var plabel := _label(14, RUST)
	plabel.text = "POINTS"
	plabel.position = Vector2(30, 66)
	_readouts.add_child(plabel)

	_float_root = Control.new()
	_float_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_float_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readouts.add_child(_float_root)

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
	_readouts.add_child(_round)

	# A15 — the tally pips, drawn under the round numeral.
	_tally = Control.new()
	_tally.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tally.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tally.draw.connect(_draw_tally)
	_readouts.add_child(_tally)

	# health bar, bottom-left above round. ColorRect defaults to MOUSE_FILTER_STOP,
	# so every bar on screen was quietly eating clicks that landed on it — which
	# now matters, because the resume click has to reach the player unhandled.
	_hp_back = ColorRect.new()
	_hp_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_back.position = Vector2(28, -132)
	_hp_back.size = Vector2(220, 10)
	_hp_back.color = Color(0, 0, 0, 0.55)
	_hp_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readouts.add_child(_hp_back)

	_hp_bar = ColorRect.new()
	_hp_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hp_bar.position = Vector2(28, -132)
	_hp_bar.size = Vector2(220, 10)
	_hp_bar.color = BONE
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readouts.add_child(_hp_bar)

	# stamina, a thinner bar under health — sprint is a resource now, so it has
	# to be visible or running out reads as the game breaking.
	_stam_back = ColorRect.new()
	_stam_back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stam_back.position = Vector2(28, -118)
	_stam_back.size = Vector2(220, 5)
	_stam_back.color = Color(0, 0, 0, 0.45)
	_stam_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readouts.add_child(_stam_back)

	_stam_bar = ColorRect.new()
	_stam_bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_stam_bar.position = Vector2(28, -118)
	_stam_bar.size = Vector2(220, 5)
	_stam_bar.color = Color(RAD.r, RAD.g, RAD.b, 0.75)
	_stam_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readouts.add_child(_stam_bar)

	# The health bar's three colours (bone / sodium / blood) were the only signal
	# that health was low, and all three are the same colour to a protanope. The
	# hatch is the second channel: a static diagonal pattern over the remaining
	# fill below LOWHP_FRAC, which is also the one low-health warning that survives
	# reduce_motion — the edge pulse is a pulse and this is not.
	_hp_hatch = Control.new()
	_hp_hatch.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_hatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_hatch.draw.connect(_draw_hp_hatch)
	_readouts.add_child(_hp_hatch)

	# perks strip
	_perks = HBoxContainer.new()
	_perks.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_perks.position = Vector2(28, -172)
	_perks.add_theme_constant_override("separation", 6)
	_readouts.add_child(_perks)

	# A14 — the alt-weapon line, above the ammo block because the ammo readout's
	# second line already runs down to the bottom edge.
	_altw = _label(13, ALT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_altw.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_altw.position = Vector2(-320, -124)
	_altw.size = Vector2(290, 18)
	_readouts.add_child(_altw)

	# ammo, bottom-right
	_ammo = _label(38, BONE, HORIZONTAL_ALIGNMENT_RIGHT)
	_ammo.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	# Two lines of 38 px need ~92 px, against the 50 this rect used to claim from
	# an offset of -96 — so the reserve count sat on, and just past, the bottom
	# edge. Pre-existing, and invisible until a screenshot was taken at 540p.
	_ammo.position = Vector2(-320, -104)
	_ammo.size = Vector2(290, 96)
	_readouts.add_child(_ammo)

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
	if f != null and f.has_char(0x2717):
		_deny_mark = "✗  "

	# crosshair
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.draw.connect(_draw_crosshair)
	_readouts.add_child(_crosshair)

	# hit marker, its own layer so it can redraw without touching the crosshair
	_marker = Control.new()
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	_readouts.add_child(_marker)

	# Damage arrows ring the crosshair rather than sitting at the screen edge, so
	# reading one costs no eye movement away from the thing you have to shoot.
	_arrow_layer = Control.new()
	_arrow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_arrow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow_layer.draw.connect(_draw_arrows)
	_readouts.add_child(_arrow_layer)

	# Captions sit above the interact prompt, which is the one band of screen that
	# is already text and already read. Newest at the bottom, nearest the prompt.
	_cap_box = VBoxContainer.new()
	_cap_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_cap_box.position = Vector2(-400, -296)
	_cap_box.size = Vector2(800, 90)
	_cap_box.alignment = BoxContainer.ALIGNMENT_END
	_cap_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cap_box.add_theme_constant_override("separation", 2)
	_readouts.add_child(_cap_box)
	for i in CAPTION_MAX:
		var cl := _label(18, BONE, HORIZONTAL_ALIGNMENT_CENTER)
		cl.visible = false
		_cap_box.add_child(cl)
		_cap_labels.append(cl)

	# interact prompt
	_prompt = _label(22, BONE, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.position = Vector2(-400, -190)
	_prompt.size = Vector2(800, 30)
	_readouts.add_child(_prompt)

	# hold-to-interact progress, directly under the prompt
	_hold = ColorRect.new()
	_hold.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hold.position = Vector2(-90, -158)
	_hold.size = Vector2(0, 4)
	_hold.color = SODIUM
	_hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_readouts.add_child(_hold)

	_downed = _label(30, BLOOD, HORIZONTAL_ALIGNMENT_CENTER)
	_downed.set_anchors_preset(Control.PRESET_CENTER)
	_downed.position = Vector2(-400, -40)
	_downed.size = Vector2(800, 80)
	_downed.visible = false
	_readouts.add_child(_downed)

	# toast
	_toast = _label(34, SODIUM, HORIZONTAL_ALIGNMENT_CENTER)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(-400, 120)
	_toast.size = Vector2(800, 44)
	_toast.modulate.a = 0.0
	_readouts.add_child(_toast)

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
##
## Hit, headshot and kill used to differ in colour alone (bone / sodium / red),
## which is one signal for three outcomes as soon as red and its neighbours stop
## separating. Each now differs in COUNT as well: four ticks for a hit, four and a
## pip for a headshot, eight for a kill. Cheap, and legible with no colour at all.
func _draw_marker() -> void:
	if _marker_t <= 0.0:
		return
	var c := _marker.size * 0.5
	var k := 1.0 - _marker_t / 0.22
	var scale := lerpf(0.55, 1.0, minf(1.0, k * 2.2))
	var alpha := clampf(_marker_t / 0.22, 0.0, 1.0)
	var col := BONE
	if _marker_kill:
		col = _hue(HUE_BAD)
	elif _marker_head:
		col = _hue(HUE_WARN)
	col.a = alpha
	var inner := 5.0 * scale
	var outer := 13.0 * scale
	var dirs := marker_ticks()
	for d: Vector2 in dirs:
		_marker.draw_line(c + d * inner, c + d * outer, col, 2.0)
	if _marker_head and not _marker_kill:
		_marker.draw_rect(Rect2(c - Vector2(2, 2), Vector2(4, 4)), col)


## The marker's shape channel, as a value. Split out rather than inlined above
## because a `draw` callback cannot be invoked outside NOTIFICATION_DRAW — this
## is the only part of the marker an assertion can reach, and asserting a
## re-derivation of it instead would be testing the test.
func marker_ticks() -> Array:
	var dirs := [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]
	if _marker_kill:
		dirs.append_array([Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)])
	return dirs


## The colourblind second channel on the health bar. Diagonal, static, and drawn
## over the *remaining* fill only, so the pattern shortens with the bar and does
## not need its own colour to be read.
func _draw_hp_hatch() -> void:
	if _hp_frac >= LOWHP_FRAC or _hp_frac <= 0.0:
		return
	var w := 220.0 * _hp_frac
	var top := _hp_hatch.size.y - 132.0
	var col := Color(ASH.r, ASH.g, ASH.b, 0.85)
	# 10 px pitch across a 10 px-tall bar gives a 45-degree stripe; the loop starts
	# one pitch negative so the leftmost stripe is not clipped away.
	var x := -10.0
	while x < w:
		var a := Vector2(28.0 + maxf(0.0, x), top + minf(10.0, maxf(0.0, -x)))
		var b := Vector2(28.0 + minf(w, x + 10.0), top + 10.0 - minf(10.0, maxf(0.0, x + 10.0 - w)))
		_hp_hatch.draw_line(a, b, col, 2.0)
		x += 10.0


## Settings.damage_arrows. A wedge on a ring around the crosshair, pointing at
## where the hit came from, fading over ARROW_LIFE.
##
## Not gated on reduce_motion: an arrow is information, and the only movement in
## it is the fade. Gated on colourblind only in its colour, which is why the
## shape is a wedge rather than a dot — position on the ring is the channel that
## carries the meaning, and it works with no colour vision at all.
func _draw_arrows() -> void:
	if _arrows.is_empty():
		return
	var c := _arrow_layer.size * 0.5
	var col := _hue(HUE_BAD)
	for a: Dictionary in _arrows:
		var k: float = clampf(float(a.t) / ARROW_LIFE, 0.0, 1.0)
		col.a = k
		var ang: float = float(a.angle)
		# Screen space: 0 is straight up, which is `Vector2.UP` rotated by the
		# bearing. Everything below is that one basis, so the wedge cannot end up
		# mirrored relative to the tip.
		var dir := Vector2.UP.rotated(ang)
		var side := Vector2(-dir.y, dir.x)
		var tip := c + dir * (ARROW_RADIUS + ARROW_LEN)
		var base := c + dir * ARROW_RADIUS
		_arrow_layer.draw_colored_polygon(PackedVector2Array([
			tip, base + side * ARROW_HALF, base - side * ARROW_HALF]), col)


## A15. One pip a round to ten, sheared 14 degrees. Past round ten the tenth pip
## turns sodium — that colour change USED to be the only signal the row had
## stopped counting, which made the whole readout unreadable to a protanope. The
## overflow pip is now a chevron as well as a different colour: a shape channel,
## which costs one extra vertex and survives every colour-vision mode.
func _draw_tally() -> void:
	if _tally_round <= 0:
		return
	var n := mini(_tally_round, TALLY_MAX)
	var x0 := 28.0
	var y0 := _tally.size.y - 36.0
	var skew := tan(deg_to_rad(TALLY_SKEW)) * TALLY_H
	for i in n:
		var x := x0 + float(i) * (TALLY_W + TALLY_GAP)
		var over := _tally_round > TALLY_MAX and i == TALLY_MAX - 1
		var col := _hue(HUE_WARN) if over else BLOOD
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
		# The shape channel: the overflow pip grows a chevron above the row, so
		# "the count has stopped" is visible without separating two warm hues.
		if over:
			var tipx := x + TALLY_W * 0.5
			_tally.draw_colored_polygon(PackedVector2Array([
				Vector2(tipx, y0 - 10.0),
				Vector2(x + TALLY_W + 2.0, y0 - 4.0),
				Vector2(x - 2.0, y0 - 4.0),
			]), col)


func _process(dt: float) -> void:
	# `and not paused` is not redundant with the state check, and the case it
	# covers is live today: the debug console takes `get_tree().paused` while
	# leaving Game.state at STATE_PLAY, so on the state alone every clock below
	# went on running with the world stopped — the toast that was up when the
	# console opened expired behind it, the hit marker faded, and the damage wash
	# drained. The same is true of anything else that ever holds the tree. Wave 1
	# closed this leak for the world and this is the HUD's half of it; the pointer
	# watchdog further down already had to make the same distinction for its own
	# reasons and is left reading `get_tree().paused` directly.
	var playing: bool = Game.state == Game.STATE_PLAY and not get_tree().paused

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
		#
		# Both go to a hard zero under reduce_motion rather than to a smaller
		# number. They are full-screen flashes and there is no amount of a
		# full-screen flash that is not a full-screen flash; what they were saying
		# is said by the health bar and its hatch, by the damage arrow, and by the
		# deny cue and the prompt's own X.
		var wash := 0.0 if _reduce_motion else _flash
		_dmg.modulate.a = wash
		_dmg.visible = wash > 0.0
		var deny := 0.0 if _reduce_motion else _deny * 0.42
		_deny_rect.modulate.a = deny
		_deny_rect.visible = deny > 0.0

		if _marker_t > 0.0:
			_marker_t = maxf(0.0, _marker_t - dt)
			_marker.queue_redraw()

		_tick_captions(dt)
		_tick_arrows(dt)

		_pulse_t += dt
		_blink_t += dt
		_pop_t = maxf(0.0, _pop_t - dt)
		_float_t = maxf(0.0, _float_t - dt)
		_title_t = maxf(0.0, _title_t - dt)

	# Not a clock either, and OUTSIDE the `playing` gate on purpose: the console
	# grants perks with the tree held and `reset_run()` clears them with
	# the state already off play, so a gated poll would leave the strip showing
	# the last run's badges on the title screen of the next one. See _perks_key.
	var perk_key := Game.perks.hash()
	if perk_key != _perks_key:
		_perks_key = perk_key
		_refresh_perks()

	# Not a clock: the stamina bar is a readout of a value that simply cannot move
	# while the player's own physics step is frozen, so gating it would only mean
	# it could be stale after a state change rather than merely idle.
	if player and is_instance_valid(player):
		_stam_bar.size.x = 220.0 * player.stamina()
		_stam_back.visible = player.stamina() < 0.999
		_stam_bar.visible = _stam_back.visible

	# A16: an edge-weighted ~1.1 Hz pulse under a third health. Held at the middle
	# of its own swing under reduce_motion rather than switched off — see
	# LOWHP_STATIC. `_pulse_t` is frozen with everything else while paused, so the
	# sine is already static there without a second branch.
	var pulse := 0.0
	if playing and _hp_frac < LOWHP_FRAC:
		pulse = LOWHP_STATIC if _reduce_motion \
			else maxf(0.0, LOWHP_BASE + sin(_pulse_t * LOWHP_RATE) * LOWHP_SWING)
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
			_points.add_theme_color_override("font_color", _hue(HUE_WARN))

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
		#
		# Under reduce_motion the card holds flat and then goes, which is the only
		# honest reading of "no animation" for something whose whole animation IS
		# the fade. The numeral is still on screen for the same length of time, so
		# nothing that the card was telling the player is lost.
		var tk := minf(1.0, _title_t / TITLE_TIME)
		_title_card.modulate.a = 1.0 if _reduce_motion else tk * tk
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

	_poll_menu_click()


## CLICK-ANYWHERE SURVIVES ON THE GAME-OVER SCREEN AND NOWHERE ELSE. The title
## screen's exemption is a DELIBERATE DEPARTURE from the ancestor, which begins a
## run from a click on either overlay (html:1043, `canvas.onmousedown`).
##
## The ancestor's title screen had exactly one action on it, so "click anywhere"
## and "press the only button" were the same sentence. This one has three, and on
## the web there is a fourth click the player never aimed: web/shell.html dispatches
## a mousedown at the canvas to resume the audio driver, and while the title screen
## honoured click-anywhere that synthetic gesture pressed ENTER THE BUNKER. A
## browser player therefore went from the loading page straight into a solo run and
## never saw MULTIPLAYER or OPTIONS at all — reported against the live GitHub Pages
## build, reproduced there, and the reason this function exists.
##
## That is the THIRD defect shaped "a click nobody aimed at the primary button
## pressed it anyway": the mouse-sensitivity slider starting a run and every co-op
## screen doing the same are the other two, both guarded inside `press_primary()`.
## Those guards stay — but a guard that has to enumerate every screen is one new
## screen away from failing again, so the source is removed as well.
##
## The game-over screen keeps the gesture: it still has one action a player wants in
## a hurry, and no shell click arrives in that state to misfire.
##
## The null-menu fallback is NOT dead code. `set_menu` is called from menu.gd's
## `bind()`, so a build that has not wired a menu has no buttons at all and this
## poll is its only way out of either screen.
##
## SPLIT IN TWO SO THE HALF THAT BROKE CAN BE ASSERTED. `is_action_just_pressed`
## is true only on the frame the press arrives, and a `--verify` check is a
## synchronous call inside one physics frame with no frame boundary to cross:
## measured in situ at physics frame 1, neither `Input.action_press` nor
## `parse_input_event` + `flush_buffered_events` makes it read true. So the Input
## read stays here, uncovered and unchanged, and everything that decides what a
## click MEANS — which is the part that shipped wrong — moves into `_menu_click`,
## which checks/shell.gd drives directly.
func _poll_menu_click() -> void:
	if Input.is_action_just_pressed("fire") or Input.is_action_just_pressed("interact"):
		_menu_click()


## What a click means on the screen that is up. See `_poll_menu_click` for why the
## title screen is not in this list and for the two lines that are not covered.
func _menu_click() -> void:
	if Game.state != Game.STATE_TITLE and Game.state != Game.STATE_OVER:
		return
	if _menu == null:
		if Game.state == Game.STATE_TITLE:
			game.start_game()
		else:
			game.restart()
		return
	# A menu is bound, so the title screen's own buttons are the way in and this
	# click was not aimed at any of them. press_primary() is still the route for the
	# game-over screen, and is still guarded for the case where the click also
	# landed on the menu's button in the same frame.
	if Game.state == Game.STATE_OVER:
		_menu.press_primary()


## Pausing never re-captures. Resume is a click, which is the only gesture that
## carries the transient activation the browser demands. `_on_state` disarms both
## watchdogs on the way through, so neither is touched here.
func _pause() -> void:
	Game.set_state(Game.STATE_PAUSE)
	Player.set_capture(false)


## "You cannot afford this" was a hue and nothing else — bone against a lifted
## blood red, which is the same colour to a protanope and close to it under a
## filmic tonemap for everybody else. The mark is the second channel, and it is
## unconditional rather than colourblind-only: "there is a cross on it" is a
## faster read than "the text is a slightly different warm" for anyone.
func set_prompt(text: String, affordable := true) -> void:
	_prompt.text = text if affordable else _deny_mark + text
	_prompt.add_theme_color_override("font_color",
		BONE if affordable else Color(BLOOD.r + 0.25, BLOOD.g + 0.08, BLOOD.b + 0.08))


func set_hold(fraction: float) -> void:
	_hold.size.x = 180.0 * clampf(fraction, 0.0, 1.0)


func flash_deny() -> void:
	_deny = 1.0


func show_toast(text: String, cls := TOAST_AUTO) -> void:
	_toast_time = 2.4
	_toast.modulate.a = 1.0
	var c: int = cls if cls != TOAST_AUTO else _toast_class(text)
	match c:
		TOAST_GOOD:
			_toast.add_theme_color_override("font_color", _hue(HUE_GOOD))
		TOAST_BAD:
			_toast.add_theme_color_override("font_color", _hue(HUE_BAD))
		_:
			_toast.add_theme_color_override("font_color", _hue(HUE_WARN))
	# Good and bad differ in hue alone. A leading rule is the second channel, and
	# it is only drawn in a colour-vision mode because the toast is the loudest
	# thing on screen when it is up and the plain form is the shipped look — the
	# affordability mark above is unconditional precisely because it is not.
	var mark := ""
	if _colourblind != 0 and c != TOAST_NEUTRAL:
		mark = "+ " if c == TOAST_GOOD else "! "
	_toast.text = mark + text


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
	# The sign is already the second channel here — "+400" and "-950" do not need
	# a colour to be told apart — so the hue is a reinforcement rather than the
	# signal, and it still goes through the palette so it does not collide with
	# the readout it floats under.
	_gain.text = ("+" if delta > 0 else "") + _commas(delta)
	_gain.add_theme_color_override("font_color",
		_hue(HUE_GOOD) if delta > 0 else _hue(HUE_BAD))
	_gain.position = Vector2(GAIN_X, GAIN_Y)
	_float_t = FLOAT_TIME
	# A spend turns the number blood-red. The ancestor leaves the class on until
	# the next points event, which in this port can be a whole round; bounding it
	# to the life of the floating delta keeps it reading as a flash.
	_spend = delta < 0
	_points.add_theme_color_override("font_color",
		_hue(HUE_BAD) if _spend else _hue(HUE_WARN))


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
	# A hound round used to be sodium instead of blood in this corner and nothing
	# else, so the one readout that stays on screen for the whole round said
	# nothing at all to a protanope. The word is the second channel; the card's
	# subtitle only says it for the first two seconds.
	_round.text = "ROUND %d%s" % [r, "  HOUNDS" if dogs else ""]
	_round.add_theme_color_override("font_color", _hue(HUE_WARN) if dogs else BLOOD)
	_tally_round = r
	_tally.queue_redraw()
	# The title card supersedes the toast for the round announcement; showing
	# both put the same words on screen twice, 200 px apart.
	_show_title_card(r, dogs)
	# Deferred to the far side of Sfx.ROUND_SILENCE so the caption lands with the
	# toll rather than with the card, which is where a hearing player gets it.
	if _captions_on:
		_round_cap_r = r
		_round_cap_t = Sfx.ROUND_SILENCE


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
	_title_num.add_theme_color_override("font_color",
		_hue(HUE_WARN) if dogs else _hue(HUE_BAD))
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
	_hp_bar.color = BONE if frac > 0.55 else (_hue(HUE_WARN) if frac > 0.25 else BLOOD)
	_hp_hatch.queue_redraw()
	# Only an actual drop counts as being hit.
	if _last_hp >= 0.0 and hp < _last_hp - 0.01:
		# A17: accumulates rather than resetting, so a second hit inside the
		# decay window washes the screen harder than the first.
		_flash = minf(1.0, _flash + DMG_PER_HIT)
		_raise_arrow()
	_last_hp = hp


## Settings.damage_arrows. See ARROW_RANGE for why the attacker is recovered by
## proximity rather than read off the signal: `health_changed` does not carry it
## and widening it for one listener is not worth it.
##
## Silent when nothing is in reach — a bleed, a scripted loss or a hound that has
## already bounced away — because an arrow pointing at the nearest body when the
## nearest body did not hit you is worse than no arrow at all.
func _raise_arrow() -> void:
	if not _arrows_on or player == null or not is_instance_valid(player):
		return
	var at := _nearest_attacker()
	if at == null:
		return
	_arrows.append({"angle": _bearing(at.global_position), "t": ARROW_LIFE})
	# Bounded: three simultaneous arrows is already every direction worth reading,
	# and Game.MAX_ALIVE is 24.
	while _arrows.size() > 3:
		_arrows.pop_front()
	_arrow_layer.queue_redraw()


func _nearest_attacker() -> Node3D:
	var best: Node3D = null
	var best_d := ARROW_RANGE * ARROW_RANGE
	var here := player.global_position
	for z in get_tree().get_nodes_in_group("zombies"):
		var n: Node3D = z
		if not is_instance_valid(n):
			continue
		var d := here.distance_squared_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


## World position to a screen-space bearing, 0 straight up. Taken off the player
## body's yaw rather than the camera's, deliberately: the camera is the last node
## in a chain that recoil, shake and bob all write (see the one-writer note in
## player.gd), so a bearing read from it would jitter with the recoil of the shot
## that was fired at the same moment.
func _bearing(at: Vector3) -> float:
	var local := player.global_transform.basis.inverse() * (at - player.global_position)
	return atan2(local.x, -local.z)


## THIS SIGNAL IS A LEVEL, NOT AN EDGE. player.gd:422 emits it EVERY FRAME while
## down, so the countdown is rendered straight off the argument — the HUD keeps no
## clock of its own, because the HUD processes while paused and the bleedout does
## not — but everything else here has to be behind a transition test.
##
## `caption()` collapses a repeat only while the line is still the NEWEST one, so
## a single groan arriving underneath it was enough to make the next frame's
## "you are down" a fresh entry: at sixty frames a second the three-line stack
## became "down / cue / down" and re-pushed a duplicate for every cue that landed.
## The colour override is behind the same test for the cheaper reason — it is a
## hash write and a redraw notification per frame for a value that only changes
## when the palette does, and _read_settings() re-asserts it when that happens.
func _on_downed(is_down: bool, time_left: float) -> void:
	_downed.visible = is_down
	if is_down:
		_downed.text = "YOU ARE DOWN\nbleeding out — %d" % ceili(time_left)
	if is_down == _downed_seen:
		return
	_downed_seen = is_down
	if is_down:
		_downed.add_theme_color_override("font_color", _hue(HUE_BAD))
		caption("you are down — bleeding out")
	else:
		# `reviveUp()` clears the damage overlay (html:2374) and restores full
		# health. The health half arrives on the health_changed that follows this
		# signal; the overlay is this file's and would otherwise finish decaying
		# over a player who is already standing at full.
		_flash = 0.0
		_dmg.modulate.a = 0.0
		_dmg.visible = false
		caption("back on your feet")


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
	#
	# THE NEXT GUN IN THE SWAP CYCLE, not "the other one". `_swap_weapon` steps the
	# slot by `(slot + 1) % guns.size()`, so with Mule Kick's third slot the
	# old `guns[1 - slot]` named the wrong weapon from two of the three slots — and
	# in fact named none at all, because the whole line was gated on `size() == 2`.
	# The `+N` says how many more are behind it, so a three-gun loadout does not
	# read as a two-gun one.
	_altw.text = ""
	if player and is_instance_valid(player) and player.guns.size() > 1:
		var alt: Dictionary = player.guns[(player.slot + 1) % player.guns.size()]
		var alt_name: String = alt.def.name
		var behind := player.guns.size() - 2
		_altw.text = "[Q] %s   %d / %d%s" % [alt_name, alt.mag, alt.res,
			"" if behind <= 0 else "   +%d" % behind]


## The perk strip is the one hue-coded element that already had its second
## channel: every PERKDEF carries a distinct `letter` and the badge draws it.
## Juggernog's red and Speed Cola's green ARE the same colour to a protanope, so
## the letter is not decoration — it is the readout, and scripts/dev/checks/shell.gd
## asserts they stay distinct. Six rows now share that namespace rather than four,
## which makes the assertion binding rather than a formality.
##
## Called from the `_perks_key` poll in `_process` and from `bind()`, and from
## nowhere else. It used to be called from `_on_weapon` — see `_perks_key`.
func _refresh_perks() -> void:
	# remove_child BEFORE queue_free, which is not belt-and-braces: a queue_free'd
	# node stays a child — and stays DRAWN — until the end of the frame, so a
	# rebuild put the old badges and the new ones in the same HBoxContainer for one
	# frame and the strip visibly doubled in length. Invisible at one rebuild per
	# purchase; it was one rebuild per shot before this function stopped hanging off
	# `weapon_changed`. It is also what lets an assertion read the child count
	# without waiting a frame for the queue to drain.
	for c in _perks.get_children():
		_perks.remove_child(c)
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
	_points.add_theme_color_override("font_color", _hue(HUE_WARN))
	# Same argument, one layer down: a caption and a damage arrow are both play
	# clocks, so a state change mid-life would strand them on the death screen.
	_caps.clear()
	_refresh_captions()
	_arrows.clear()
	_arrow_layer.queue_redraw()
	_round_cap_t = 0.0
	# The box state and the power flag are edge detectors, and a restart resets
	# both underlying values — without this the first spin of the next run is not
	# an edge and never gets captioned.
	_box_state = ""
	_power_seen = Game.power_on
	# menu.gd draws these three screens itself, with buttons on them. Nothing else
	# in this match is state the menu duplicates, so it still runs.
	_readouts.visible = true
	if _menu != null:
		_overlay.visible = false
		# TITLE and OVER have no live run behind them, so the readouts would be
		# reporting a starting stake and an untouched magazine underneath a screen
		# that is already reporting the run's real numbers. PAUSE keeps them: the
		# plate is centred, the readouts are at the edges, and the ammo count is
		# part of what a player pauses to look at.
		_readouts.visible = s == "play" or s == "pause"
		if s == "play":
			_downed.visible = false
		return
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


# --- captions -----------------------------------------------------------------
#
# Settings.captions. Milestone 1 made positional audio the PRIMARY way the horde
# is perceived — "everything used to arrive dead-centre at the same volume
# regardless of where it happened" (sfx.gd:717) — which is an improvement for a
# hearing player and a regression for everyone else, because the information that
# moved into the audio channel did not exist anywhere on screen.
#
# Four cues carry position or timing that nothing visible carries: the groan
# behind you, the box's jingle, the round toll, and the generator's whine. Three
# of them are observable from inside this file; the fourth needs the Sfx hook.


## Non-directional caption. Public because the cue sources are spread across
## `_process`, `_on_round` and `_on_downed`.
func caption(text: String) -> void:
	if not _captions_on or text.is_empty():
		return
	# Cheapest possible de-duplication, and the case it exists for is twelve
	# zombies groaning inside one second: repeating the newest line adds nothing a
	# player can act on and pushes the two below it off the stack.
	if not _caps.is_empty() and String(_caps[-1].text) == text:
		_caps[-1].t = CAPTION_LIFE
		return
	_caps.append({"text": text, "t": CAPTION_LIFE})
	while _caps.size() > CAPTION_MAX:
		_caps.pop_front()
	_refresh_captions()


## Directional caption. The bearing is a word rather than an arrow because the
## caption band is text and a glyph would need a font this project does not ship
## (see the ✦ probe in `_build`).
func caption_at(text: String, at: Vector3) -> void:
	if not _captions_on:
		return
	caption(text + _direction_suffix(at))


func _direction_suffix(at: Vector3) -> String:
	if player == null or not is_instance_valid(player):
		return ""
	var away := player.global_position.distance_to(at)
	# Past the cull distance the voice was never played, so claiming a bearing for
	# it would be captioning silence. Distance is still worth saying: "somewhere
	# far off" is exactly what a hearing player gets from a cue at the edge.
	if away > CAPTION_DIST:
		return "  ·  far off"
	var a := absf(_bearing(at))
	if a <= CAPTION_AHEAD:
		return "  ·  ahead"
	if a >= CAPTION_BEHIND:
		return "  ·  behind you"
	return "  ·  to your right" if _bearing(at) > 0.0 else "  ·  to your left"


## Rendered into three fixed labels, oldest at the top. Alpha carries the age so
## the stack reads in order without needing to be re-sorted.
func _refresh_captions() -> void:
	for i in _cap_labels.size():
		var l: Label = _cap_labels[i]
		if i >= _caps.size():
			l.visible = false
			continue
		var c: Dictionary = _caps[i]
		l.visible = true
		l.text = String(c.text)
		l.modulate.a = clampf(float(c.t) / (CAPTION_LIFE * 0.4), 0.25, 1.0)


## The caption clock, called from inside `_process`'s `playing` gate — so every
## line on screen freezes with everything else the moment the tree is paused.
func _tick_captions(dt: float) -> void:
	if _round_cap_t > 0.0:
		_round_cap_t -= dt
		if _round_cap_t <= 0.0:
			caption("round %d — the toll sounds" % _round_cap_r)
	_poll_cues()
	if _caps.is_empty():
		return
	var live: Array[Dictionary] = []
	for c: Dictionary in _caps:
		c.t = float(c.t) - dt
		if float(c.t) > 0.0:
			live.append(c)
	_caps = live
	_refresh_captions()


## The two cues this file can see without reaching into a system it does not own.
##
## The box exposes `state()` (mystery_box.gd:79) and its position is
## `MapData.BOXSPOTS[Game.box_spot]`, which is public run state rather than the
## box's private field — so the caption survives the box relocating under it. The
## power is `Game.power_on`, and the whine is played at the generator
## (lighting.gd:582), which is a map constant.
##
## Edge detectors are updated whether or not captions are on, so switching them
## on mid-run does not immediately fire a caption for a spin that started before.
func _poll_cues() -> void:
	var st := ""
	if game != null and is_instance_valid(game) and game.box != null:
		st = String(game.box.state())
	if st != _box_state:
		var was := _box_state
		_box_state = st
		if _captions_on and was != "":
			if st == "spinning":
				caption_at("the box sings", _spot(MapData.BOXSPOTS[Game.box_spot]))
			elif st == "teddy":
				caption_at("the teddy bear laughs", _spot(MapData.BOXSPOTS[Game.box_spot]))
	if Game.power_on != _power_seen:
		_power_seen = Game.power_on
		if _captions_on and _power_seen:
			caption_at("the power whines up", _spot(MapData.GENSPOT))


## Map tiles are Vector2 in XZ; 1.2 m is the eye height sfx.gd's positional voices
## and scripts/world/los.gd both pin to.
func _spot(v: Vector2) -> Vector3:
	return Vector3(v.x, 1.2, v.y)


## Sfx's cue channel — see CUE_CAPTIONS and the guard in bind(). Everything that
## arrives here is positional; the non-positional cues are the UI ones, which are
## already on screen as a toast.
func _on_cue(id: String, at: Vector3, positional: bool) -> void:
	if not _captions_on or not positional:
		return
	for row: Array in CUE_CAPTIONS:
		if id.begins_with(String(row[0])):
			caption_at(String(row[1]), at)
			return


## The arrow clock. Inside the `playing` gate for the same reason the caption
## clock is: an arrow that kept fading behind the pause overlay would be gone by
## the time the player looked at it.
func _tick_arrows(dt: float) -> void:
	if _arrows.is_empty():
		return
	var live: Array[Dictionary] = []
	for a: Dictionary in _arrows:
		a.t = float(a.t) - dt
		if float(a.t) > 0.0:
			live.append(a)
	_arrows = live
	_arrow_layer.queue_redraw()
