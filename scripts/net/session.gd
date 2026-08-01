extends Node

## The room: claiming a code, joining one, and holding the lobby together.
##
## Registered as the `Net` autoload. It is an autoload rather than a child of main
## because a session outlives the run — you sit in a lobby before `start_game()` and
## you survive `restart()`, which reloads the whole scene (main.gd:675). A node under
## main would be destroyed by the reload and take the room with it.
##
## THE SPLIT, from the bottom up:
##   phoenix.gd   pure framing and parsing. No socket. Testable headlessly.
##   realtime.gd  one channel: connect, join, heartbeat, presence, reconnect.
##   session.gd   this file. What a ROOM is: a code, a host, a roster, a state.
## Replication of actual gameplay is a layer above this and does not belong here —
## this file must not know what a zombie is.
##
## THE KEY BELOW IS MEANT TO BE PUBLIC. It is a Supabase *publishable* key and it
## ships inside a .pck that anyone who loads the game can download. That is the
## designed use. What protects the data is that `public.rooms` grants nothing to
## anon at all — RLS is on with zero policies, and the only way in is four narrow
## SECURITY DEFINER functions, two of which are token-gated. Verified through this
## exact key over REST, not by reading the SQL back:
## notes/net/2026-07-31-realtime-probe.md.

const PHX := preload("res://scripts/net/phoenix.gd")
const REALTIME := preload("res://scripts/net/realtime.gd")

const PROJECT_URL := "https://qalanxifxfukkeqdhfqh.supabase.co"
const PUBLISHABLE_KEY := "sb_publishable_thiF9P-VTYc-GtiQL3V_DQ_c004iNWQ"

## TWO, NOT THE FOUR BO1 ALLOWS, AND THIS IS ARITHMETIC RATHER THAN A PREFERENCE.
##
## Supabase bills and rate-limits an "event", which its own limits page defines as a
## WebSocket message delivered to *or* sent from a client. So one broadcast into a
## room of N costs 1 send + (N-1) deliveries = N events, not one. The free tier caps
## the whole project at 100 events/second.
##
## At 15 Hz in both directions:
##   2 players: 15x2 (host snapshots) + 15x2 (one client's input)          =  60/s  OK
##   3 players: 15x3               + 2x15x3                                 = 135/s  OVER
##   4 players: 15x4               + 3x15x4                                 = 240/s  2.4x OVER
## Over the limit is not degradation - `tenant_events` DISCONNECTS the sockets.
##
## Four players would need either ~6 Hz (unusable for aim, even interpolated) or the
## Pro plan's 500 events/second. Raising this constant without one of those buys a
## room that dies a few seconds after the first round starts.
##
## The first draft of this file said 4, and the probe note behind it costed a session
## at 60 events/second for FOUR players by counting publishes and forgetting fan-out
## - 4x low. Corrected in notes/net/2026-07-31-realtime-probe.md.
##
## Enforced client-side at the lobby: the arriving client counts the roster and
## leaves if it is surplus. Not enforceable server-side without a private channel,
## which would need accounts.
const MAX_PLAYERS := 2

## How long to wait for the channel before giving up on a join. Generous against a
## 23 ms median because the failure being guarded is a dead room, not a slow one, and
## a premature "no such room" on a real room is the worse error.
const JOIN_TIMEOUT := 12.0

## Keeps the room out of the reaper's two-hour window. Well under it; the point is
## only that a long session does not get collected out from under itself.
const HEARTBEAT_PERIOD := 300.0

signal state_changed(state: int)
signal roster_changed(players: Array)
signal error(message: String)
## The host has started the run. `seed_value` is the host's, so every client builds
## the same world from the same draws.
signal run_started(seed_value: int)

enum {
	OFFLINE,
	CLAIMING,     ## asking the database for a code
	CHECKING,     ## asking whether a typed code exists
	CONNECTING,   ## code in hand, channel coming up
	LOBBY,        ## joined, waiting for the host to start
	IN_RUN,
}

## Wire events. Kept as constants because a typo in a string literal on one side of a
## network is invisible until someone plays co-op.
const EV_START := "start"
const EV_FULL := "full"

var _state := OFFLINE
var _code := ""
var _token := ""
var _is_host := false
var _me := ""
var _name := "Player"
var _net: Node
var _http: HTTPRequest
var _roster := {}
var _hb := 0.0
var _join_wait := 0.0


func _ready() -> void:
	# Same reasoning as realtime.gd: Game.set_state pauses the tree, and a paused
	# session is a session whose socket dies at 25 s.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_http = HTTPRequest.new()
	add_child(_http)
	set_process(false)


# --- what the menu calls -----------------------------------------------------

func host_room(player_name: String) -> void:
	if _state != OFFLINE:
		return
	_name = player_name
	_is_host = true
	_set_state(CLAIMING)
	_rpc("claim_room", {}, _on_claimed)


func join_room(code: String, player_name: String) -> void:
	if _state != OFFLINE:
		return
	var clean := PHX.sanitise_code(code)
	# Shape is decided locally; EXISTENCE is the server's answer. A client that tries
	# to decide existence locally is a client that will one day refuse a real room.
	if not PHX.is_valid_code(clean):
		error.emit("A room code is %d characters." % PHX.CODE_LEN)
		return
	_name = player_name
	_is_host = false
	_code = clean
	_set_state(CHECKING)
	_rpc("room_exists", {"p_code": clean}, _on_checked)


## Leaves cleanly. The host releases its code so the space stays sparse rather than
## waiting two hours for the reaper.
func leave_room() -> void:
	if _state == OFFLINE:
		return
	if _net != null:
		_net.close_channel()
		_net.queue_free()
		_net = null
	if _is_host and not _code.is_empty() and not _token.is_empty():
		# Fire and forget: the reaper is the backstop and a player who has already
		# clicked LEAVE should not wait on a round trip.
		_rpc("release_room", {"p_code": _code, "p_token": _token}, func(_ok: bool, _b: String) -> void: pass)
	_code = ""
	_token = ""
	_roster = {}
	_is_host = false
	set_process(false)
	_set_state(OFFLINE)


## Host only. Broadcasts the seed so every client's Rng starts from the same place.
func start_run() -> void:
	if not _is_host or _state != LOBBY:
		return
	var s: int = Rng.seed_value
	_net.send(EV_START, {"seed": s})
	_set_state(IN_RUN)
	run_started.emit(s)


# --- what everything else reads ----------------------------------------------

func state() -> int:
	return _state


func code() -> String:
	return _code


func is_host() -> bool:
	return _is_host


func is_online() -> bool:
	return _state == LOBBY or _state == IN_RUN


## The lobby list, host first and then join order, so the display does not reshuffle
## every time presence re-stamps an unchanged player.
func players() -> Array:
	var out: Array = []
	for key: String in _roster.keys():
		var meta: Dictionary = _roster[key]
		out.append({
			"key": key,
			"name": str(meta.get("name", "Player")),
			"host": bool(meta.get("host", false)),
			"me": key == _me,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["host"]) != bool(b["host"]):
			return bool(a["host"])
		return str(a["key"]) < str(b["key"]))
	return out


## The transport, for the replication layer above this one. Null when offline.
func channel() -> Node:
	return _net


# --- room claim / check ------------------------------------------------------

func _on_claimed(ok: bool, body: String) -> void:
	if not ok:
		_fail("Could not reach the room service.")
		return
	var parsed: Variant = JSON.parse_string(body)
	# PostgREST returns a single-row set for a table-returning function.
	var row: Dictionary = {}
	if typeof(parsed) == TYPE_ARRAY and (parsed as Array).size() > 0:
		var first: Variant = (parsed as Array)[0]
		if typeof(first) == TYPE_DICTIONARY:
			row = first
	elif typeof(parsed) == TYPE_DICTIONARY:
		row = parsed
	_code = str(row.get("code", ""))
	_token = str(row.get("host_token", ""))
	if _code.is_empty():
		_fail("The room service did not return a code.")
		return
	_open()


func _on_checked(ok: bool, body: String) -> void:
	if not ok:
		_fail("Could not reach the room service.")
		return
	if body.strip_edges() != "true":
		_fail("No room with that code. Check it and try again.")
		return
	_open()


func _open() -> void:
	_set_state(CONNECTING)
	_join_wait = 0.0
	# A per-session identity. Presence needs a stable key and the game has no
	# accounts; a UUID is enough and is regenerated every session on purpose, since
	# nothing here should persist an identifier across runs.
	_me = _uuid()
	_net = REALTIME.new()
	_net.name = "Channel"
	add_child(_net)
	_net.joined.connect(_on_joined)
	_net.failed.connect(func(r: String) -> void: _fail(_friendly(r)))
	_net.dropped.connect(func(r: String) -> void: _fail(_friendly(r)))
	_net.roster_changed.connect(_on_roster)
	_net.message.connect(_on_message)
	_net.open_channel(PROJECT_URL, PUBLISHABLE_KEY, _code, _me,
		{"name": _name, "host": _is_host})
	set_process(true)


func _on_joined(_r: Dictionary) -> void:
	_set_state(LOBBY)


func _on_roster(r: Dictionary) -> void:
	_roster = r
	# Enforced by the ARRIVING client, not by the room. Every peer can see the roster,
	# so the newcomer is the one that knows it is fifth — and having the newcomer
	# leave is the only rule that cannot make two clients disagree about who was
	# ejected. A host-side kick would race with a second simultaneous arrival.
	if not _is_host and _roster.size() > MAX_PLAYERS and _roster.has(_me):
		var ahead := 0
		for key: String in _roster.keys():
			if key < _me:
				ahead += 1
		if ahead >= MAX_PLAYERS:
			leave_room()
			error.emit("That room is full.")
			return
	roster_changed.emit(players())


func _on_message(event: String, payload: Dictionary) -> void:
	match event:
		EV_START:
			if _is_host:
				return   # the host started it; it does not need telling
			# Wire numbers arrive as float (phoenix.gd::decode says so), so the seed
			# must be cast rather than compared. A float seed would silently start
			# every client on a different world.
			var s := int(payload.get("seed", 0))
			_set_state(IN_RUN)
			run_started.emit(s)
		EV_FULL:
			pass


func _process(dt: float) -> void:
	if _state == CONNECTING:
		_join_wait += dt
		if _join_wait > JOIN_TIMEOUT:
			# Distinguishes "the code is real but nobody is there" from "the code is
			# wrong", which room_exists already ruled out. A host that quit without
			# releasing leaves exactly this state behind.
			_fail("That room did not answer. The host may have left.")
		return
	if not is_online() or not _is_host:
		return
	_hb += dt
	if _hb >= HEARTBEAT_PERIOD:
		_hb = 0.0
		_rpc("heartbeat_room", {"p_code": _code, "p_token": _token},
			func(_ok: bool, _b: String) -> void: pass)


# --- plumbing ----------------------------------------------------------------

## One in-flight request at a time, which is all this file ever needs — claim, check
## and heartbeat are never concurrent. HTTPRequest refuses a second call while busy,
## so this reports rather than silently dropping it.
func _rpc(fn: String, body: Dictionary, done: Callable) -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		done.call(false, "")
		return
	for c: Callable in _http.request_completed.get_connections().map(
			func(d: Dictionary) -> Callable: return d["callable"]):
		_http.request_completed.disconnect(c)
	_http.request_completed.connect(
		func(_result: int, response_code: int, _headers: PackedStringArray, data: PackedByteArray) -> void:
			done.call(response_code == 200, data.get_string_from_utf8()),
		CONNECT_ONE_SHOT)
	var headers := PackedStringArray([
		"apikey: " + PUBLISHABLE_KEY,
		"Authorization: Bearer " + PUBLISHABLE_KEY,
		"Content-Type: application/json",
	])
	var err := _http.request(PROJECT_URL + "/rest/v1/rpc/" + fn,
		headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		done.call(false, "")


func _set_state(s: int) -> void:
	if _state == s:
		return
	_state = s
	state_changed.emit(s)


func _fail(message: String) -> void:
	var was := _state
	leave_room()
	if was != OFFLINE:
		error.emit(message)


## Turns a protocol string into something worth showing a player. The raw reasons are
## useful in a log and meaningless on a menu.
static func _friendly(reason: String) -> String:
	if reason.contains("RateLimit"):
		return "The room service is busy. Try again in a moment."
	if reason.contains("Unauthorized") or reason.contains("JWT"):
		return "The room service refused the connection."
	return "Lost the connection to the room."


## Rng.VISUAL, not a gameplay stream: a presence key has no effect on simulation, and
## a draw from SPAWN or ROUNDS here would shift every seeded run by the act of
## opening a lobby. Constraint 6.
static func _uuid() -> String:
	const HEX := "0123456789abcdef"
	var s := ""
	for i in 32:
		s += HEX[Rng.randi_range(Rng.VISUAL, 0, 15)]
	return s
