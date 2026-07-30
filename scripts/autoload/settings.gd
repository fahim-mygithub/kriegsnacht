extends Node

## Player-facing options: the second thing besides the profile that outlives a run.
##
## The surface below is a contract other packages are written against — the HUD
## reads four accessibility keys, the player reads two view keys, the menu writes
## all eight — so keys are added here and nowhere else, and none of them is renamed.
##
## PERSISTENCE. This shares one stored blob with the profile, through save_store.gd,
## because there is exactly one place a browser build is allowed to keep bytes and
## that file already knows where it is and what it costs (localStorage, synchronous,
## refused outright in incognito — see its header). The blob therefore has two
## authors: game_state.gd owns `best_round` / `best_points` / `runs` at the top
## level, this file owns everything under SLOT. `save()` here is a read-modify-write
## so this half can never drop the profile half. The other direction is game_state's
## to close and it currently does not — see the note on load().
##
## EVERYTHING READ BACK IS HOSTILE. On web the blob is one devtools line from
## hand-edited and a truncated write parses cleanly into a shorter dictionary, so
## every key is validated on its own: wrong type, unknown name, or out of range and
## the default stands. That is the same ladder game_state.gd applies to the profile
## and for the same reason.

## Emitted for every accepted write, including each key in turn after load(). Never
## emitted for a rejected one, so a listener can treat an emission as "this key now
## holds a legal value of the declared type".
signal changed(key: String)

## preload rather than the global class name: a freshly added script is not in the
## class registry until the editor rescans, and a headless run has no editor.
const STORE := preload("res://scripts/autoload/save_store.gd")

## The one key inside the shared blob this file owns. Nested rather than flat so a
## key added here can never collide with a profile key added there.
const SLOT := "settings"

## colourblind, as the HUD's palette switch reads it. Named because `2` at a call
## site is the kind of thing that gets renumbered by accident.
enum { CB_NONE, CB_PROTANOPIA, CB_DEUTERANOPIA, CB_TRITANOPIA }

## Defaults, and — because `typeof()` is read off them — the type each key is
## allowed to hold. A key absent from here does not exist: get_value() refuses it,
## set_value() refuses it, and a stored blob carrying it is ignored.
##
## `fov` is 74.0 because that is what the camera ships with (player.gd:172). A
## default that does not match the camera means the first frame after the options
## screen is opened silently changes the view; scripts/dev/checks/shell.gd asserts
## the two agree.
const DEFAULTS := {
	"reduce_motion": false,
	"captions": false,
	"damage_arrows": true,
	"colourblind": 0,
	"mouse_sens": 1.0,
	"fov": 74.0,
	"master_volume": 1.0,
	"sfx_volume": 1.0,
}

## Inclusive bounds for the numeric keys. A stored value outside them is clamped
## rather than refused: 200 degrees of FOV is a hostile blob, but 111 is a player
## who dragged a slider in a build whose maximum was different, and dropping their
## setting on the floor for that is worse than clamping it.
const BOUNDS := {
	"colourblind": [0, 3],
	"mouse_sens": [0.25, 3.0],
	"fov": [60.0, 110.0],
	"master_volume": [0.0, 1.0],
	"sfx_volume": [0.0, 1.0],
}

## Below this a linear volume is silence. linear_to_db(0.0) is -inf, which is not a
## number an AudioServer bus should ever be handed.
const MUTE_DB := -80.0
const MUTE_LINEAR := 0.0005

var reduce_motion := false
var captions := false
var damage_arrows := true
var colourblind := 0
var mouse_sens := 1.0
var fov := 74.0
var master_volume := 1.0
var sfx_volume := 1.0


## Registered after Sfx in project.godot, deliberately: _apply_audio() needs the
## "SFX" bus that Sfx._ready() creates, and an autoload's _ready runs in
## registration order. The lookup is guarded anyway, because a bus that does not
## exist must degrade to "master only" rather than to an index of -1.
## `self.` is load-bearing: an unqualified `load()` resolves to the GDScript global
## before it resolves to this class's own method, and "Too few arguments for load()"
## is a hard parse error rather than a warning. Outside this file
## `Settings.load()` is unambiguous, which is why the contract can still name it.
func _ready() -> void:
	self.load()


# --- the contract ------------------------------------------------------------

## Null for a key that does not exist. Every real key holds a bool, an int or a
## float, so null is unambiguous.
func get_value(key: String) -> Variant:
	if not DEFAULTS.has(key):
		return null
	return get(key)


## Writes one key and announces it. A rejected write is silent to the caller and
## leaves the previous value in place — the menu cannot produce one (its controls
## are built from BOUNDS) and a caller that can is a bug worth a warning, not a
## crash mid-round.
func set_value(key: String, v: Variant) -> void:
	if not DEFAULTS.has(key):
		push_warning("Settings: refused unknown key '%s'" % key)
		return
	var clean: Variant = _clean(key, v)
	if clean == null:
		push_warning("Settings: refused %s for '%s' (wants %s)" % [
			type_string(typeof(v)), key, type_string(typeof(DEFAULTS[key]))])
		return
	set(key, clean)
	if key == "master_volume" or key == "sfx_volume":
		_apply_audio()
	changed.emit(key)


## Read-modify-write, so writing the options cannot lose the profile sitting next
## to them in the same blob. Returns false when storage refused — incognito and a
## third-party-cookie-blocked iframe both do — which the menu reports once rather
## than on every slider drag.
func save() -> bool:
	var blob: Dictionary = STORE.restore()
	blob[SLOT] = _to_dict()
	return STORE.save(blob)


## Named `load` because the contract names it that, which shadows the GDScript
## global `load()` inside this file. Nothing here loads a resource, so the cost is
## a warning and no behaviour; the alternative was a name other packages would have
## to remember is different from the one they were told.
##
## The other half of the shared blob is game_state.gd's, and its two writes
## (`_on_round_changed`, `record_run`) currently save `profile` alone — so with the
## hunk in this package's report unapplied, the first round boundary of a run drops
## everything under SLOT. That is why this reads on boot only and re-reads nothing:
## the in-memory values are the truth for the life of the process either way.
func load() -> void:
	var blob: Dictionary = STORE.restore()
	var raw: Variant = blob.get(SLOT)
	var stored: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	for key: String in DEFAULTS:
		var clean: Variant = _clean(key, stored.get(key))
		set(key, DEFAULTS[key] if clean == null else clean)
	_apply_audio()
	# One emission per key rather than one "everything changed" broadcast: a
	# listener written as a match on the key name would ignore the broadcast, and
	# the difference would not show up until somebody's option quietly stopped
	# applying at boot.
	for key: String in DEFAULTS:
		changed.emit(key)


# --- validation --------------------------------------------------------------

## The whole ladder, in one place. Returns null for "not acceptable", which the two
## callers turn into "keep what you had" and "fall back to the default".
func _clean(key: String, v: Variant) -> Variant:
	if not DEFAULTS.has(key):
		return null
	var want := typeof(DEFAULTS[key])
	match want:
		TYPE_BOOL:
			# Strict. JSON round-trips a bool as a bool, so anything else here is
			# either a hand-edit or a caller passing 1 for true, and silently
			# accepting the second is how a key ends up with two spellings.
			if typeof(v) != TYPE_BOOL:
				return null
			return v
		TYPE_INT:
			# JSON gives back int for a whole number and float for one that was
			# edited to carry a decimal point. Both are legitimate arrivals.
			if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
				return null
			return _bound_int(key, int(v))
		TYPE_FLOAT:
			if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
				return null
			var f := float(v)
			# NaN and infinity survive a JSON round trip through some producers and
			# clamp to themselves, so they have to be rejected by name.
			if is_nan(f) or is_inf(f):
				return null
			return _bound_float(key, f)
	return null


func _bound_int(key: String, v: int) -> int:
	if not BOUNDS.has(key):
		return v
	var b: Array = BOUNDS[key]
	return clampi(v, int(b[0]), int(b[1]))


func _bound_float(key: String, v: float) -> float:
	if not BOUNDS.has(key):
		return v
	var b: Array = BOUNDS[key]
	return clampf(v, float(b[0]), float(b[1]))


func _to_dict() -> Dictionary:
	var out := {}
	for key: String in DEFAULTS:
		out[key] = get(key)
	return out


# --- what this file applies itself -------------------------------------------

## The two volumes, and only the two volumes. Everything else is applied by the
## node that owns the thing it changes — the HUD reads the accessibility keys, the
## player reads `fov` and `mouse_sens` — because an autoload reaching into the
## scene to set properties on nodes it does not own is the second writer that
## makes a bug unattributable.
##
## Buses rather than per-voice gain: sfx.gd sets `volume_db` on every player it
## pools and a second author of that field would fight it on every shot. Bus gain
## is composited after all of them and nothing else writes it. No AudioEffect is
## involved — every one of them is dead on this platform (see the renderer note in
## project.godot); a bus's own volume is not an effect.
func _apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, _db(master_volume))
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, _db(sfx_volume))


func _db(linear: float) -> float:
	return MUTE_DB if linear <= MUTE_LINEAR else linear_to_db(linear)
