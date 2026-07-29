extends RefCounted

## The one place that knows where a save physically lives.
##
## Deliberately NOT an autoload: it is reached with preload() from game_state.gd,
## because a new script's class_name is absent from the class registry until the
## editor rescans and a headless run has no editor.
##
## Web does not use `user://`, and the reason is not "mid-write tab close". The
## engine hooks FileAccess close and flags an IndexedDB sync that only fires on the
## *next* main_loop_iterate(), which then runs an async IDB transaction with no
## completion signal — and a backgrounded tab stops the main loop entirely. So the
## commonest way a player leaves, write -> switch tab -> close tab, loses the
## write. `JavaScriptBridge.force_fs_sync()` does not help; it sets that same flag.
## localStorage is synchronous by spec and committed before setItem() returns, with
## ~5 MB of quota against a profile blob well under 1 KB. There is no beforeunload
## flush either — a backgrounded tab cannot run one. (SYNTHESIS §1.4b.)
##
## Every failure path degrades to "no save", never to a crash and never to a
## half-written profile: a first run has no key at all, incognito refuses
## localStorage outright, and a third-party-cookie-blocked iframe throws on the
## `localStorage` property access itself before any method is called.

## Bumped when the shape of the stored dictionary changes. A blob from another
## version is discarded rather than parsed, so a schema change is detected instead
## of silently misread as the current one.
const VERSION := 1

const WEB_KEY := "kriegsnacht/profile"
const FILE_PATH := "user://profile.json"

const KEY_VERSION := "v"
const KEY_DATA := "data"


## Writes the blob. Returns false when storage is unavailable — the caller decides
## what, if anything, that is worth saying to the player.
static func save(data: Dictionary) -> bool:
	# Built by assignment rather than as a literal so the keys are unambiguously
	# the constants above and not their identifier names.
	var blob := {}
	blob[KEY_VERSION] = VERSION
	blob[KEY_DATA] = data
	var text := JSON.stringify(blob)
	return _web_write(text) if OS.has_feature("web") else _file_write(text)


## Returns the stored dictionary, or an empty one for every kind of absence and
## every kind of damage: no backend, no key, unparseable text, a blob that is not a
## dictionary, or a version this build does not understand. Named `restore` rather
## than `load` because `load` is a GDScript global and shadowing it warns, and
## warnings are errors here.
static func restore() -> Dictionary:
	var text: String = _web_read() if OS.has_feature("web") else _file_read()
	if text.is_empty():
		return {}
	# JSON.new().parse() rather than the JSON.parse_string() helper: both handle
	# malformed input without throwing, but the static helper *logs* the failure.
	# A truncated blob is an expected arrival shape here, not an incident — and on
	# web it would push a red parse error into the console of every visitor whose
	# localStorage entry got clipped, for a case this function already handles.
	var j := JSON.new()
	if j.parse(text) != OK:
		return {}
	if typeof(j.data) != TYPE_DICTIONARY:
		return {}
	var blob: Dictionary = j.data
	var ver: Variant = blob.get(KEY_VERSION)
	# JSON round-trips small integers as int, but a hand-edited "v": 1.0 arrives as
	# a float; both are legitimate, anything else is not.
	if typeof(ver) != TYPE_INT and typeof(ver) != TYPE_FLOAT:
		return {}
	if int(ver) != VERSION:
		return {}
	var body: Variant = blob.get(KEY_DATA)
	if typeof(body) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = body
	return out


# --- web backend -------------------------------------------------------------

## The whole point of routing through eval() rather than
## `JavaScriptBridge.get_interface("localStorage")` is this try/catch. A direct
## interface call that throws — incognito, blocked third-party storage, quota —
## unwinds through the Wasm boundary, and there is nothing on the GDScript side to
## catch it. Handling the failure in JS turns every one of those into a false.
##
## Both calls pass `true` for the global execution context, as R3's adopt-verbatim
## sketch and perf_probe.gd:77 already do. With `false` the snippet runs as a
## direct eval inside whatever engine function happens to call it, so it inherits
## that scope's strictness and survives only as long as nothing minifies it;
## indirect eval always lands in global scope, where `window` is `window`.
static func _web_write(text: String) -> bool:
	var js := "(function(){try{window.localStorage.setItem(%s,%s);return true;}catch(e){return false;}})()" % [
		_js_literal(WEB_KEY), _js_literal(text)]
	var ok: Variant = JavaScriptBridge.eval(js, true)
	# eval() hands back null when the bridge is not there at all, and a JS boolean
	# arrives as TYPE_BOOL. A number is accepted as well, because a false negative
	# here is a spurious warning on every single death and this branch cannot be
	# exercised outside a real browser.
	if typeof(ok) == TYPE_BOOL:
		return bool(ok)
	if typeof(ok) == TYPE_INT or typeof(ok) == TYPE_FLOAT:
		return float(ok) > 0.5
	return false


static func _web_read() -> String:
	# getItem returns null for a key that was never written — a first visit — which
	# would arrive as TYPE_NIL. Normalised to "" in JS so there is one empty case.
	var js := "(function(){try{var v=window.localStorage.getItem(%s);return (typeof v==='string')?v:'';}catch(e){return '';}})()" % _js_literal(WEB_KEY)
	var raw: Variant = JavaScriptBridge.eval(js, true)
	if typeof(raw) != TYPE_STRING:
		return ""
	var text: String = raw
	return text


## JSON string syntax is a subset of JS string-literal syntax, so stringify() is
## the correct quoter for pasting a Godot string into JS source — with one
## exception: U+2028 and U+2029 are legal in JSON but were illegal inside a JS
## string literal before ES2019. Escaped so the store cannot be broken by whatever
## a later schema decides to put in the blob.
static func _js_literal(s: String) -> String:
	return JSON.stringify(s).replace("\u2028", "\\u2028").replace("\u2029", "\\u2029")


# --- desktop backend ---------------------------------------------------------

static func _file_write(text: String) -> bool:
	var f := FileAccess.open(FILE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	# close() is called explicitly rather than left to the handle going out of
	# scope, and the handle is a local rather than a member for the same reason: a
	# FileAccess held open is a FileAccess that never flushed.
	f.close()
	return true


static func _file_read() -> String:
	if not FileAccess.file_exists(FILE_PATH):
		return ""
	var f := FileAccess.open(FILE_PATH, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text
