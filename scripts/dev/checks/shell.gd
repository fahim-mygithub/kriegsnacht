extends RefCounted

## Assertions for the shell: the options store, the menu tree, the four
## accessibility flags, and the HUD's pause gate.
##
## Every one of these is a claim nobody will ever notice going wrong by playing.
## A dropped option looks like the player misremembering where they left a
## slider. A focus chain that does not close looks like the keyboard being
## unsupported, which it was until this milestone, so nobody would think to
## report it. `reduce_motion` failing to reach one of the five effects it
## promises is invisible to everyone who does not need it and unusable for
## everyone who does. And a HUD clock that runs while the tree is held is the
## exact leak wave 1 closed for the world — the kind that comes back the next
## time somebody adds a timer.
##
## THIS SECTION WRITES TO THE PLAYER'S REAL SAVE FILE, because the options store
## is only worth testing through the backend that actually persists it — a
## FileAccess left unflushed fails as an empty file rather than as an error. The
## file, the live Settings values, the tree's pause flag and Game.state are all
## snapshotted at the top of each function and restored on the way out.
##
## What is deliberately NOT here: anything needing a browser. The localStorage
## backend, the service worker's cache version, and the shell's one-gesture
## click all live behind `OS.has_feature("web")`, which is false in a headless
## run — so this exercises the desktop path and the shared validate ladder, and
## the web half is verified by building it (see this package's report).

## preload rather than the global class name: a freshly added script is not in
## the class registry until the editor rescans, and a headless run has no editor.
const MENU := preload("res://scripts/ui/menu.gd")
const STORE := preload("res://scripts/autoload/save_store.gd")
const HUD := preload("res://scripts/ui/hud.gd")

## One non-default value per key, so a load() that quietly did nothing would fail
## the round trip instead of passing it. Asserted to cover DEFAULTS exactly, which
## is what makes "every key" true rather than "every key somebody remembered".
const PROBE := {
	"reduce_motion": true,
	"captions": true,
	"damage_arrows": false,
	"colourblind": 2,
	"mouse_sens": 1.75,
	"fov": 96.0,
	"master_volume": 0.35,
	"sfx_volume": 0.6,
}

## player.gd:229 sets the camera to this and settings.gd's default has to agree:
## a default that does not match what the camera ships with means the first visit
## to the options screen silently changes the view.
const SHIPPED_FOV := 74.0


## Counts the two calls press_primary() must collapse into one. A stub rather
## than the real main because both of its methods are irreversible here —
## start_game() begins round one and restart() reloads the scene out from under
## the rest of the suite.
class StubMain extends RefCounted:
	var starts := 0
	var restarts := 0

	func start_game() -> void:
		starts += 1

	func restart() -> void:
		restarts += 1


static func run(v: Verify, main: Node3D) -> void:
	_settings_roundtrip(v)
	_settings_hostile(v)
	_settings_keeps_the_profile(v)
	_settings_matches_the_game(v, main)
	_menu_tree(v, main)
	_reduce_motion(v, main)
	_captions_and_arrows(v, main)
	_colour_channels(v, main)
	_hud_external_hold(v, main)


# --- the options store --------------------------------------------------------

## Snapshot/restore for the three things every function below can move: the live
## option values, the save file, and the run state.
static func _snapshot() -> Dictionary:
	var defaults: Dictionary = Settings.DEFAULTS
	var live := {}
	for k: String in defaults:
		live[k] = Settings.get_value(k)
	var path: String = STORE.FILE_PATH
	return {
		"live": live,
		"had": FileAccess.file_exists(path),
		"text": FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "",
	}


static func _restore(snap: Dictionary) -> void:
	var live: Dictionary = snap.live
	for k: String in live:
		Settings.set_value(k, live[k])
	var path: String = STORE.FILE_PATH
	if bool(snap.had):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(String(snap.text))
			f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func _settings_roundtrip(v: Verify) -> void:
	var snap := _snapshot()
	var defaults: Dictionary = Settings.DEFAULTS

	# The probe is only a test of "every key" if it *is* every key, and only a
	# test of load() at all if none of its values is already the default.
	var covers := PROBE.size() == defaults.size()
	var novel := true
	for k: String in defaults:
		if not PROBE.has(k):
			covers = false
		elif PROBE[k] == defaults[k]:
			novel = false
	v.check("the round-trip probe covers every key with a non-default value",
		covers and novel, "covers=%s novel=%s" % [covers, novel])

	for k: String in PROBE:
		Settings.set_value(k, PROBE[k])
	var wrote: bool = Settings.save()

	# Scrambled to the defaults first, so a load() that read nothing at all would
	# come back holding defaults and fail every comparison below.
	for k: String in defaults:
		Settings.set_value(k, defaults[k])
	Settings.load()

	var lost := ""
	for k: String in PROBE:
		var got: Variant = Settings.get_value(k)
		var want: Variant = PROBE[k]
		var same := false
		if typeof(want) == TYPE_FLOAT:
			same = typeof(got) == TYPE_FLOAT and v.near(float(got), float(want))
		else:
			same = typeof(got) == typeof(want) and got == want
		if not same:
			lost += "%s(%s) " % [k, got]
	v.check("every option key round-trips through the real store",
		wrote and lost.is_empty(), "wrote=%s lost=%s" % [wrote, lost])

	# JSON has one number type, so the int key has to come back an int rather
	# than the 2.0 the backend hands over — otherwise `colourblind` indexes a
	# palette with a float the day somebody stops calling int() on it.
	v.check("an int option survives JSON as an int",
		typeof(Settings.get_value("colourblind")) == TYPE_INT,
		type_string(typeof(Settings.get_value("colourblind"))))

	_restore(snap)


## The blob is one devtools line from hand-edited on web, and a truncated write
## parses cleanly into a shorter dictionary. Every arrival shape below is real.
static func _settings_hostile(v: Verify) -> void:
	var snap := _snapshot()

	# An unknown key is refused at the API. Not merely ignored — refused, and
	# without inventing a property for it, because `set()` on a Node with no such
	# member is a silent no-op that would make get_value() lie later.
	var before: Variant = Settings.get_value("reduce_motion")
	Settings.set_value("cheat_god_mode", true)
	v.check("an unknown key is refused by set_value",
		Settings.get_value("cheat_god_mode") == null
			and Settings.get("cheat_god_mode") == null
			and Settings.get_value("reduce_motion") == before)

	# A wrong type is refused and the previous value stands. 1 for true is the
	# case that matters: accepting it is how a key ends up with two spellings.
	Settings.set_value("reduce_motion", false)
	Settings.set_value("reduce_motion", 1)
	var kept_bool: bool = Settings.get_value("reduce_motion") == false
	Settings.set_value("mouse_sens", 1.5)
	Settings.set_value("mouse_sens", "fast")
	var kept_float: bool = v.near(float(Settings.get_value("mouse_sens")), 1.5)
	v.check("a wrong-typed value is refused and the previous one stands",
		kept_bool and kept_float, "bool=%s float=%s" % [kept_bool, kept_float])

	# NaN and infinity survive a JSON round trip through some producers and clamp
	# to themselves, so clampf() alone would let them through into a FOV.
	v.check("NaN and infinity are refused rather than clamped",
		Settings._clean("fov", NAN) == null and Settings._clean("fov", INF) == null)

	# And the same ladder applied to a stored blob rather than to a caller: an
	# unknown key, three wrong types and one out-of-range number, all in one go.
	var blob: Dictionary = STORE.restore()
	blob["settings"] = {
		"bogus": 1,
		"reduce_motion": 3,
		"colourblind": "x",
		"fov": 9000.0,
		"mouse_sens": 2.25,
	}
	STORE.save(blob)
	Settings.load()
	var defaults: Dictionary = Settings.DEFAULTS
	var ok_unknown: bool = Settings.get("bogus") == null
	var ok_bool: bool = Settings.get_value("reduce_motion") == defaults["reduce_motion"]
	var ok_int: bool = Settings.get_value("colourblind") == defaults["colourblind"]
	# Clamped, NOT defaulted: 9000 is hostile but 111 would be a player whose last
	# build had a wider slider, and throwing their setting away for that is worse.
	var ok_clamp: bool = v.near(float(Settings.get_value("fov")), 110.0)
	var ok_good: bool = v.near(float(Settings.get_value("mouse_sens")), 2.25)
	v.check("a hand-edited blob is validated key by key",
		ok_unknown and ok_bool and ok_int and ok_clamp and ok_good,
		"unknown=%s bool=%s int=%s clamp=%s good=%s" % [
			ok_unknown, ok_bool, ok_int, ok_clamp, ok_good])

	# A blob whose whole settings slot is the wrong shape must land on defaults
	# rather than on a crash inside the loop that reads it.
	blob = STORE.restore()
	blob["settings"] = "not a dictionary"
	STORE.save(blob)
	Settings.load()
	var all_default := true
	for k: String in defaults:
		if Settings.get_value(k) != defaults[k]:
			all_default = false
	v.check("a settings slot of the wrong shape falls back to every default",
		all_default)

	_restore(snap)


## The options and the profile share one stored blob because there is exactly one
## place a browser build may keep bytes. That makes both writers capable of
## erasing the other, and a read-modify-write is the only thing stopping it.
static func _settings_keeps_the_profile(v: Verify) -> void:
	var snap := _snapshot()
	var profile_was: Dictionary = Game.profile.duplicate()

	STORE.save({"best_round": 9, "best_points": 4242, "runs": 5})
	Settings.set_value("fov", 88.0)
	Settings.save()
	var back: Dictionary = STORE.restore()
	var kept: bool = int(back.get("best_round", 0)) == 9 \
		and int(back.get("best_points", 0)) == 4242
	var added: bool = typeof(back.get("settings")) == TYPE_DICTIONARY
	v.check("saving the options does not drop the profile beside them",
		kept and added, "kept=%s added=%s blob=%s" % [kept, added, back])

	Game.profile = profile_was
	_restore(snap)


## Two numbers that have to agree with something outside this file, and would
## drift silently: the FOV the camera ships with, and the bounds the menu builds
## its sliders from.
static func _settings_matches_the_game(v: Verify, main: Node3D) -> void:
	var defaults: Dictionary = Settings.DEFAULTS
	v.check("the default FOV is the one the camera ships with",
		v.near(float(defaults["fov"]), SHIPPED_FOV),
		"default=%s shipped=%s" % [defaults["fov"], SHIPPED_FOV])

	var snap := _snapshot()
	var p: Player = main.player
	Settings.set_value("fov", float(defaults["fov"]))
	p._read_settings()
	v.check("the camera lands on the default FOV rather than near it",
		v.near(p.camera().fov, SHIPPED_FOV), "got %.2f" % p.camera().fov)

	# Every bounded key must have a default inside its own bounds, or the very
	# first load() silently clamps it to something the contract does not promise.
	var bounds: Dictionary = Settings.BOUNDS
	var outside := ""
	for k: String in bounds:
		var b: Array = bounds[k]
		var d := float(defaults[k])
		if d < float(b[0]) or d > float(b[1]):
			outside += k + " "
	v.check("every default sits inside its own bounds", outside.is_empty(), outside)

	# Two tables holding the same number: menu.gd builds each slider from its own
	# ROWS entry, and Settings clamps to BOUNDS. A slider whose range is WIDER than
	# the bounds silently clamps the player's drag — the handle moves, the value
	# does not, and it reads as the slider being broken at one end rather than as
	# two constants having drifted apart.
	var drift := ""
	for row: Dictionary in MENU.ROWS:
		var k: String = row.key
		if not row.has("lo") or not bounds.has(k):
			continue
		var rb: Array = bounds[k]
		if not v.near(float(row.lo), float(rb[0])) or not v.near(float(row.hi), float(rb[1])):
			drift += k + " "
	v.check("every options slider spans exactly the range the store clamps to",
		drift.is_empty(), drift)

	_restore(snap)
	p._read_settings()


# --- the menu -----------------------------------------------------------------

## Builds a menu over the running main if one is not wired yet, asserts against
## it, and takes it back out. `unbind()` exists for exactly this: a menu left
## bound would keep a second Game.state_changed listener and a HUD that had
## stopped drawing its own screens, and every assertion after this one would be
## running against a different game.
static func _menu_tree(v: Verify, main: Node3D) -> void:
	var menu = main.get("menu")
	var borrowed := false
	if menu == null:
		menu = MENU.new()
		menu.name = "MenuCheck"
		main.add_child(menu)
		menu.bind(main, main.hud)
		borrowed = true

	var screens: Dictionary = menu.screens()
	var missing := ""
	for name: String in ["title", "pause", "options", "over"]:
		if not screens.has(name):
			missing += name + " "
	v.check("the menu has a title, a pause, an options and a game-over screen",
		missing.is_empty(), missing)

	# THERE WERE NO BUTTONS IN THIS PROJECT AT ALL before this milestone, so the
	# game could not be played without a mouse. A screen with no focusable control
	# is that state again, one screen at a time.
	var unfocusable := ""
	var broken := ""
	for name: String in screens:
		var ring: Array = menu.chain(name)
		if ring.is_empty():
			unfocusable += name + " "
			continue
		for c: Control in ring:
			if c.focus_mode != Control.FOCUS_ALL:
				unfocusable += "%s/%s " % [name, c.get_class()]
		# Walk the ring the way the engine does — by resolving the NodePath, not
		# by trusting the array it was built from. `focus_next` and
		# `focus_neighbor_bottom` are separate properties and Tab uses the first
		# while the arrow keys use the second, so both are walked: a chain wired
		# on one and not the other works with Tab and strands the arrows.
		for prop: String in ["focus_next", "focus_neighbor_bottom"]:
			var at: Control = ring[0]
			var seen := {}
			for _i in ring.size():
				seen[at.get_instance_id()] = true
				var path: NodePath = at.get(prop)
				var nxt: Node = at.get_node_or_null(path)
				if nxt == null or not (nxt is Control):
					at = null
					break
				at = nxt
			if at != ring[0] or seen.size() != ring.size():
				broken += "%s/%s " % [name, prop]
	v.check("every menu screen has a focusable control", unfocusable.is_empty(),
		unfocusable)
	v.check("every focus chain visits each control once and closes the ring",
		broken.is_empty(), broken)

	# html:3205-3215 shows five statistics. This port measures three of them
	# (round, kills, headshots) and does not measure shots fired, shots hit or an
	# elapsed clock — so accuracy and time are OMITTED rather than shown as a zero,
	# which would read as "you hit nothing" and "you survived no time at all".
	# The assertion is on the rule, not on the list: every row the screen offers
	# has to render to something, so the day Game grows the fields and _stats()
	# starts returning them, this catches a formatter that was never written.
	var blank := ""
	for row: Array in menu._stats():
		var key := String(row[0])
		if menu._stat_text(key).is_empty():
			blank += key + " "
	v.check("every game-over statistic the menu offers renders to something",
		blank.is_empty(), blank)

	# html:3216, the four epitaph bands, at their boundaries and one below each.
	var round_was: int = Game.round_no
	var bands := {15: "LEGEND", 14: "VETERAN", 10: "VETERAN", 9: "OVERRUN",
		5: "OVERRUN", 4: "DEVOURED", 0: "DEVOURED"}
	var wrong := ""
	for r: int in bands:
		Game.round_no = r
		menu._refresh_over()
		if menu._epitaph.text != String(bands[r]):
			wrong += "%d=%s " % [r, menu._epitaph.text]
	Game.round_no = round_was
	v.check("the epitaph bands match the ancestor at every boundary",
		wrong.is_empty(), wrong)

	# Two paths reach the primary action — the button on the mouse release and
	# hud.gd's click-anywhere poll on the press — and on the game-over screen both
	# land in the same frame. restart() defers a reload without moving Game.state,
	# so an unguarded second call queues a second reload of a dying scene.
	var stub := StubMain.new()
	var main_was = menu.main
	var state_was: int = Game.state
	var screen_was: String = menu.current()
	menu.main = stub
	# Assigned rather than set through Game.set_state, which would pause the tree
	# and emit into every listener in the game for the sake of a latch test.
	Game.state = Game.STATE_TITLE
	menu.show_screen("title")
	menu._acted = false
	menu.press_primary()
	menu.press_primary()
	Game.state = Game.STATE_OVER
	menu.show_screen("over")
	menu._acted = false
	menu.press_primary()
	menu.press_primary()
	v.check("the primary action fires once per screen however many paths reach it",
		stub.starts == 1 and stub.restarts == 1,
		"starts=%d restarts=%d" % [stub.starts, stub.restarts])

	# THE OTHER WAY THE PRIMARY ACTION FIRED WHEN IT MUST NOT, and it shipped:
	# opening OPTIONS does not move Game.state, so underneath the options screen
	# the state still reads TITLE or OVER. hud.gd's click-anywhere poll reads the
	# Input singleton, and a Control consuming a click does not suppress that —
	# `set_input_as_handled()` stops the event reaching `_unhandled_input`, it does
	# not rewind the action state the event already wrote. Every click on a slider,
	# a checkbox and the BACK button therefore also arrived at press_primary(), and
	# the first drag of the sensitivity slider started the run.
	#
	# Asserted from BOTH states because they are two separate `match` arms and a
	# guard added to one of them is the shape this bug would come back in.
	Game.state = Game.STATE_TITLE
	menu._acted = false
	menu.show_screen("options")
	menu.press_primary()
	Game.state = Game.STATE_OVER
	menu._acted = false
	menu.press_primary()
	v.check("a click on the options screen is not a click-anywhere-to-start",
		stub.starts == 1 and stub.restarts == 1,
		"starts=%d restarts=%d" % [stub.starts, stub.restarts])

	Game.state = state_was
	menu.main = main_was
	menu.show_screen(screen_was)

	if borrowed:
		menu.unbind()
		main.remove_child(menu)
		menu.queue_free()


# --- accessibility ------------------------------------------------------------

## Settings.reduce_motion, over the five effects this file owns. The two pure
## flashes go to a hard zero, the low-HP edge is pinned to the middle of its
## swing rather than switched off (it is the only warning that health is about to
## run out) and the title card holds flat instead of fading.
##
## Driven by hand. Every one of these is a value written inside `_process`, so a
## test that only set the flag and looked at the node would be reading the frame
## before the change.
static func _reduce_motion(v: Verify, main: Node3D) -> void:
	var h: Node = main.get("hud")
	var snap := _snapshot()
	var state_was: int = Game.state
	var paused_was: bool = main.get_tree().paused
	var flash_was: float = h._flash
	var deny_was: float = h._deny
	var frac_was: float = h._hp_frac
	var title_was: float = h._title_t

	Game.state = Game.STATE_PLAY
	main.get_tree().paused = false

	# Off first, so "zeroed" is measured against a run in which the same setup
	# demonstrably produces something. A gate that zeroes everything always would
	# otherwise pass every assertion below.
	Settings.set_value("reduce_motion", false)
	h._flash = 1.0
	h._deny = 1.0
	h._hp_frac = 0.1
	h._title_t = HUD.TITLE_TIME * 0.5
	h._process(0.016)
	var loud: bool = h._dmg.modulate.a > 0.0 and h._deny_rect.modulate.a > 0.0 \
		and h._lowhp.modulate.a > 0.0 and h._title_card.modulate.a < 1.0

	Settings.set_value("reduce_motion", true)
	h._flash = 1.0
	h._deny = 1.0
	h._hp_frac = 0.1
	h._title_t = HUD.TITLE_TIME * 0.5
	h._process(0.016)
	var quiet: bool = v.near(h._dmg.modulate.a, 0.0) and not h._dmg.visible \
		and v.near(h._deny_rect.modulate.a, 0.0) and not h._deny_rect.visible \
		and v.near(h._title_card.modulate.a, 1.0)
	v.check("reduce_motion zeroes the damage wash, the deny flash and the card fade",
		loud and quiet, "loud=%s quiet=%s" % [loud, quiet])

	# The low-HP edge is the one that is damped rather than removed, so the
	# assertion is that it is STILL VISIBLE and no longer moving. Two steps a
	# quarter-second apart is a third of the pulse's period at LOWHP_RATE.
	var a1: float = h._lowhp.modulate.a
	h._process(0.25)
	var a2: float = h._lowhp.modulate.a
	h._process(0.25)
	var a3: float = h._lowhp.modulate.a
	v.check("reduce_motion holds the low-health edge visible and still",
		a1 > 0.0 and v.near(a1, a2) and v.near(a2, a3),
		"%.3f %.3f %.3f" % [a1, a2, a3])

	# Shake, bob, cant and recoil are player.gd's half of the same flag. Asserted
	# from here anyway: the flag is one contract and splitting its test across two
	# files is how half of it stops being checked.
	var p: Player = main.player
	p._read_settings()
	p._shake = 0.0
	p.add_shake(1.0)
	v.check("reduce_motion refuses camera shake at the source", v.near(p._shake, 0.0),
		"got %.3f" % p._shake)

	Settings.set_value("reduce_motion", false)
	p._read_settings()
	p._shake = 0.0
	p.add_shake(1.0)
	v.check("camera shake still works with reduce_motion off", p._shake > 0.0)
	p._shake = 0.0

	Game.state = state_was
	main.get_tree().paused = paused_was
	h._flash = flash_was
	h._deny = deny_was
	h._hp_frac = frac_was
	h._title_t = title_was
	_restore(snap)
	p._read_settings()


## Settings.captions and Settings.damage_arrows. Both are off-by-default
## channels that carry information nothing else on screen carries, so "does it
## appear at all" and "does it stop when switched off" are the whole test.
static func _captions_and_arrows(v: Verify, main: Node3D) -> void:
	var h: Node = main.get("hud")
	var snap := _snapshot()
	var state_was: int = Game.state
	var paused_was: bool = main.get_tree().paused
	# The revive branch of `_on_downed` clears the damage wash, which this function
	# drives by hand — so it is state this section moves and therefore state this
	# section puts back.
	var flash_was: float = h._flash
	var downed_was: bool = h._downed_seen

	Game.state = Game.STATE_PLAY
	main.get_tree().paused = false

	Settings.set_value("captions", false)
	h._caps.clear()
	h.caption("a groan")
	var silent: bool = h._caps.is_empty()

	Settings.set_value("captions", true)
	h.caption("a groan")
	h.caption("a groan")
	var one: bool = h._caps.size() == 1
	h.caption("boards splintering")
	h.caption("the box sings")
	h.caption("the power whines up")
	# Bounded at CAPTION_MAX, because a caption stack that grows with the horde
	# reaches the crosshair.
	var capped: bool = h._caps.size() == HUD.CAPTION_MAX
	v.check("captions appear only when asked for, de-duplicate and stay bounded",
		silent and one and capped,
		"silent=%s one=%s size=%d" % [silent, one, h._caps.size()])

	# A caption is a play clock like every other clock on this screen, so it has
	# to hold while the tree is held — otherwise a line raised on the frame the
	# player opened the menu is gone by the time they come back to read it.
	var live: int = h._caps.size()
	# Every read of `_caps[0]` below is guarded on the stack still being there. A
	# leaking gate empties it, and an unguarded index would take this whole
	# function down with a runtime error — which unwinds silently and DELETES the
	# assertions rather than failing them. That is exactly the blind spot the floor
	# at the end of verify.gd exists for, and a check that hides in it is worse
	# than no check at all. Confirmed by reverting the gate and watching the suite
	# come back five assertions shorter and still green.
	var age: float = float(h._caps[0].t) if live > 0 else 0.0
	main.get_tree().paused = true
	h._process(5.0)
	var held: bool = live > 0 and h._caps.size() == live \
		and v.near(float(h._caps[0].t), age)
	main.get_tree().paused = false
	h._process(0.5)
	var ages: bool = not h._caps.is_empty() and float(h._caps[0].t) < age
	v.check("a caption ages in play and holds through a pause",
		held and ages, "held=%s ages=%s" % [held, ages])

	# The direction is the whole point of the caption for a positional cue, and
	# it is the half a deaf player has no other source for. Bearings are measured
	# off the player's own basis, so build the four cases from it rather than
	# from world axes — the assertion has to survive the spawn being rotated.
	var p: Player = main.player
	var b := p.global_transform.basis
	var here := p.global_position
	var cases := {
		"ahead": here - b.z * 4.0,
		"behind you": here + b.z * 4.0,
		"to your right": here + b.x * 4.0,
		"to your left": here - b.x * 4.0,
		"far off": here - b.z * (HUD.CAPTION_DIST + 5.0),
	}
	var wrong := ""
	for want: String in cases:
		h._caps.clear()
		h.caption_at("cue", cases[want])
		if h._caps.is_empty() or not String(h._caps[0].text).ends_with(want):
			wrong += want + " "
	v.check("a positional caption names the right bearing", wrong.is_empty(), wrong)
	h._caps.clear()
	h._refresh_captions()

	# The downed readout, which is fed by a signal that is a LEVEL: player.gd:422
	# emits `downed_changed` every frame while down. The countdown must follow the
	# argument frame by frame, and everything else must not — `caption()` collapses
	# a repeat only while the line is still the newest, so one cue landing
	# underneath it made the next frame's "you are down" a fresh entry and the
	# three-line stack filled with duplicates at sixty a second.
	h._caps.clear()
	h._downed_seen = false
	h._on_downed(true, 7.0)
	var counts: bool = h._downed.text.ends_with("7")
	h.caption("a cue from somewhere")
	h._on_downed(true, 6.4)
	h._on_downed(true, 6.3)
	h._on_downed(true, 3.2)
	counts = counts and h._downed.text.ends_with("4")
	var said_once: bool = h._caps.size() == 2
	h._on_downed(false, 0.0)
	var stood_up: bool = not h._downed.visible and h._caps.size() == 3
	v.check("the downed readout counts every frame and captions exactly once",
		counts and said_once and stood_up,
		"counts=%s once=%s(%d) up=%s" % [counts, said_once, h._caps.size(), stood_up])
	h._caps.clear()
	h._refresh_captions()
	h._downed_seen = false
	h._downed.visible = false

	# Damage arrows. Raised by hand rather than by taking real damage, because
	# `take_damage` would need a live zombie inside reach and a scripted round.
	#
	# THE STAND-IN BODY IS THE POINT OF THIS BLOCK. `_raise_arrow` is silent when
	# nothing sits within ARROW_RANGE, so on an empty map "the switch refused it"
	# and "there was nobody to point at" are the same observation — the off-case
	# passed vacuously and would have gone on passing with the flag read deleted
	# outright. The decoy only has to be a Node3D in the "zombies" group;
	# `_nearest_attacker` reads nothing else off it.
	var decoy := Node3D.new()
	decoy.name = "ArrowDecoy"
	main.add_child(decoy)
	decoy.add_to_group("zombies")
	decoy.global_position = here - b.z * 1.0

	Settings.set_value("damage_arrows", false)
	h._arrows.clear()
	h._raise_arrow()
	var refused: bool = h._arrows.is_empty()

	Settings.set_value("damage_arrows", true)
	h._arrows.clear()
	h._raise_arrow()
	var raised: bool = h._arrows.size() == 1

	# And the range rule, which is what keeps an arrow from pointing at a bystander
	# when the damage came from a bleed. Asserted on the decoy by identity rather
	# than on the arrow list being empty, so a real zombie left standing near the
	# player by an earlier section cannot decide the result.
	decoy.global_position = here - b.z * (HUD.ARROW_RANGE + 1.0)
	var out_of_reach: bool = h._nearest_attacker() != decoy
	v.check("an arrow is raised only with the switch on and a body inside reach",
		refused and raised and out_of_reach,
		"refused=%s raised=%s ranged=%s" % [refused, raised, out_of_reach])

	decoy.remove_from_group("zombies")
	main.remove_child(decoy)
	decoy.queue_free()

	h._arrows.clear()
	h._arrows.append({"angle": PI, "t": HUD.ARROW_LIFE})
	main.get_tree().paused = true
	h._process(5.0)
	var arrow_held: bool = h._arrows.size() == 1 \
		and v.near(float(h._arrows[0].t), HUD.ARROW_LIFE)
	main.get_tree().paused = false
	h._process(HUD.ARROW_LIFE + 0.1)
	var expires: bool = h._arrows.is_empty()
	v.check("a damage arrow holds through a pause and then expires",
		arrow_held and expires,
		"held=%s expires=%s" % [arrow_held, expires])

	# Bearings again, this time as the arrow draws them: straight ahead is 0 and
	# straight behind is half a turn, which is what pins the sign convention the
	# wedge is rotated by.
	var ahead: float = absf(h._bearing(here - b.z * 3.0))
	var behind: float = absf(h._bearing(here + b.z * 3.0))
	var right: float = h._bearing(here + b.x * 3.0)
	v.check("a bearing is zero ahead, half a turn behind and positive to the right",
		v.near(ahead, 0.0, 0.01) and v.near(behind, PI, 0.01) and right > 0.0,
		"ahead=%.3f behind=%.3f right=%.3f" % [ahead, behind, right])

	Game.state = state_was
	main.get_tree().paused = paused_was
	h._flash = flash_was
	h._downed_seen = downed_was
	_restore(snap)


## Settings.colourblind, and the audit behind it. Every element that used to
## encode meaning in hue ALONE now carries a second channel, and the palette
## makes sure the hues that remain do not collide in the mode they are for.
static func _colour_channels(v: Verify, main: Node3D) -> void:
	var h: Node = main.get("hud")
	var snap := _snapshot()

	var collide := ""
	for mode in HUD.CB_HUES.size():
		Settings.set_value("colourblind", mode)
		var good: Color = h._hue(HUD.HUE_GOOD)
		var bad: Color = h._hue(HUD.HUE_BAD)
		var warn: Color = h._hue(HUD.HUE_WARN)
		if good == bad or good == warn or bad == warn:
			collide += str(mode) + " "
	v.check("no colour-vision mode maps two meanings to the same colour",
		collide.is_empty(), collide)

	# The collision the palette exists for is RAD against BLOOD_LIT under
	# protanopia and deuteranopia. If those two modes still hand back RAD, the
	# table is present and doing nothing — which is the failure that looks like
	# success from every angle except the one that matters.
	var moved := true
	for mode in [Settings.CB_PROTANOPIA, Settings.CB_DEUTERANOPIA]:
		Settings.set_value("colourblind", mode)
		if h._hue(HUD.HUE_GOOD) == HUD.RAD:
			moved = false
	Settings.set_value("colourblind", Settings.CB_NONE)
	var untouched: bool = h._hue(HUD.HUE_GOOD) == HUD.RAD \
		and h._hue(HUD.HUE_BAD) == HUD.BLOOD_LIT and h._hue(HUD.HUE_WARN) == HUD.SODIUM
	v.check("the red-green modes move green and the default mode moves nothing",
		moved and untouched, "moved=%s untouched=%s" % [moved, untouched])

	# The perk strip's second channel, and the reason it was already fine:
	# Juggernog's red and Speed Cola's green are the same colour to a protanope,
	# so the letter is the readout rather than a label on it.
	var letters := {}
	var dupes := ""
	for k: String in Weapons.PERKDEF:
		var d: Dictionary = Weapons.PERKDEF[k]
		var letter: String = d.letter
		if letter.is_empty() or letters.has(letter):
			dupes += k + " "
		letters[letter] = true
	v.check("every perk badge carries its own letter", dupes.is_empty(), dupes)

	# The affordability colouring, which was a hue and nothing else. The mark is
	# unconditional rather than colourblind-only, because "there is a cross on
	# it" is a faster read than "the text is a slightly different warm".
	h.set_prompt("BUY M14 — 500", true)
	var plain: String = h._prompt.text
	h.set_prompt("BUY M14 — 500", false)
	var denied: String = h._prompt.text
	v.check("an unaffordable prompt is marked as well as coloured",
		plain == "BUY M14 — 500" and denied != plain and denied.ends_with(plain),
		"plain=%s denied=%s" % [plain, denied])

	# The hit marker's three outcomes differed in colour alone. `marker_ticks()` is
	# the function the draw callback itself calls, so this reads the real shape
	# rather than a re-derivation of it — a draw handler cannot be invoked outside
	# NOTIFICATION_DRAW, which is why the count is a function at all.
	var head_was: bool = h._marker_head
	var kill_was: bool = h._marker_kill
	h._marker_head = false
	h._marker_kill = false
	var plain_ticks: int = h.marker_ticks().size()
	h._marker_kill = true
	var kill_ticks: int = h.marker_ticks().size()
	h._marker_head = head_was
	h._marker_kill = kill_was
	v.check("a kill draws more ticks than a hit, so the two differ without colour",
		kill_ticks > plain_ticks, "hit=%d kill=%d" % [plain_ticks, kill_ticks])

	# The tally row's tenth pip turning sodium past round ten was, by the code's
	# own admission, "the only signal the row has stopped counting". The chevron is
	# the shape channel and is asserted by construction only — a draw callback is
	# not reachable from here (see the report). What IS reachable is the colour it
	# uses, which must stay distinct from the ordinary pip in EVERY mode, because
	# the chevron sits directly above one.
	var clash := ""
	for mode in HUD.CB_HUES.size():
		Settings.set_value("colourblind", mode)
		if h._hue(HUD.HUE_WARN) == HUD.BLOOD:
			clash += str(mode) + " "
	v.check("the tally's overflow pip never takes the ordinary pip's colour",
		clash.is_empty(), clash)

	_restore(snap)


# --- the pause gate this package added ----------------------------------------

## `Game.state == STATE_PLAY` and `get_tree().paused` move together everywhere
## except one place: an external holder. The debug console is one — it takes the
## tree so its LineEdit can be typed into, and leaves the state alone. On the
## state check alone every clock on this screen went on running behind it: the
## toast that was up when the console opened expired, the hit marker faded, the
## damage wash drained, and a caption raised a moment earlier was gone.
##
## checks/systems.gd already covers the STATE_PAUSE direction. This is the other
## one, and it is the one that was still leaking.
static func _hud_external_hold(v: Verify, main: Node3D) -> void:
	var h: Node = main.get("hud")
	var snap := _snapshot()
	var state_was: int = Game.state
	var paused_was: bool = main.get_tree().paused
	var flash_was: float = h._flash
	var toast_was: float = h._toast_time
	var marker_was: float = h._marker_t
	var blink_was: float = h._blink_t
	var pulse_was: float = h._pulse_t
	var title_was: float = h._title_t

	Settings.set_value("reduce_motion", false)
	Settings.set_value("captions", true)

	# Game.state stays PLAY throughout: the whole point is that the state says
	# "playing" and the tree says otherwise.
	Game.state = Game.STATE_PLAY
	main.get_tree().paused = true
	h._flash = 0.6
	h._toast_time = 2.0
	h._marker_t = 0.20
	h._title_t = 1.0
	h._blink_t = 0.0
	h._pulse_t = 0.0
	h._caps.clear()
	h.caption("held")
	h._process(5.0)
	var holds: bool = v.near(h._flash, 0.6) and v.near(h._toast_time, 2.0) \
		and v.near(h._marker_t, 0.20) and v.near(h._title_t, 1.0) \
		and v.near(h._blink_t, 0.0) and v.near(h._pulse_t, 0.0) \
		and h._caps.size() == 1 and v.near(float(h._caps[0].t), HUD.CAPTION_LIFE)

	# And the wrong direction, which looks identical from a screenshot: a gate
	# that never lets anything move at all.
	main.get_tree().paused = false
	h._process(0.1)
	# `not is_empty()` before the index, for the reason spelled out in
	# _captions_and_arrows: a leaking gate expires the caption during the held five
	# seconds, and an unguarded read deletes this assertion instead of failing it.
	var moves: bool = h._flash < 0.6 and h._toast_time < 2.0 and h._marker_t < 0.20 \
		and h._title_t < 1.0 and h._blink_t > 0.0 and h._pulse_t > 0.0 \
		and not h._caps.is_empty() and float(h._caps[0].t) < HUD.CAPTION_LIFE

	v.check("no HUD clock advances while an external holder has the tree",
		holds and moves, "holds=%s moves=%s" % [holds, moves])

	h._caps.clear()
	h._refresh_captions()
	Game.state = state_was
	main.get_tree().paused = paused_was
	h._flash = flash_was
	h._toast_time = toast_was
	h._marker_t = marker_was
	h._blink_t = blink_was
	h._pulse_t = pulse_was
	h._title_t = title_was
	_restore(snap)
