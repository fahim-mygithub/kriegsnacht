extends Node

## One Supabase Realtime channel, held open.
##
## This is the half of the transport that needs a socket. All the framing, parsing
## and presence folding lives in scripts/net/phoenix.gd as pure static functions so
## it can be asserted headlessly; what is left here is genuinely stateful — a
## connection, a join handshake, a heartbeat, a reconnect ladder — and none of it can
## be tested without a network. Keeping the split sharp is what stops the untestable
## part from growing.
##
## PROCESS_MODE_ALWAYS, AND THIS IS LOAD-BEARING. Game.set_state() pauses the tree for
## STATE_PAUSE and STATE_OVER (game_state.gd:282). A node on the default process mode
## stops running `_process` when the tree pauses, which here would stop the heartbeat
## — and the server closes an idle socket after 25 seconds. So a player who opened the
## pause menu for half a minute would come back to a dead connection that looks
## exactly like their internet dropping. The pause screen must not be able to kill the
## session; the same reasoning menu.gd:109 applies to input applies to a socket.
##
## ONE WRITER. This node owns the socket and the roster and nothing else owns either.
## Callers get signals out and three methods in.

const PHX := preload("res://scripts/net/phoenix.gd")

## Emitted once the channel is joined and usable. Not on socket open — an open socket
## whose phx_join was rejected is useless, and the difference matters to the lobby.
signal joined(roster: Dictionary)

## Terminal. `reason` is player-facing where the server gave us one.
signal failed(reason: String)

## A peer's game message, already unwrapped from the broadcast envelope.
signal message(event: String, payload: Dictionary)

## The lobby changed. Carries the whole roster rather than a delta because every
## consumer so far wants the whole list and folding deltas twice invites drift.
signal roster_changed(roster: Dictionary)

## The channel went away after having been joined. Distinct from `failed`, which is
## a channel that never came up at all.
signal dropped(reason: String)

enum {
	IDLE,
	CONNECTING,   ## socket opening
	JOINING,      ## socket open, phx_join sent, waiting on the reply
	READY,        ## joined; broadcasts flow
	CLOSED,       ## terminal for this instance
}

## The JS client's ladder, adopted rather than invented: 1s, 2s, 5s, 10s and then
## 10s forever. The server adds its own backoff before replying to a rejected join,
## so retrying faster than this does not get you in sooner — it just gets you
## rate-limited, which is a slower way to fail.
const BACKOFF := [1.0, 2.0, 5.0, 10.0]

## Outbound budget. The relay tolerated a 30-message burst with no throttle during
## the probe, but a bug that spins the send path would trip a real per-channel limit
## and the recovery for that is a channel close. A local ceiling turns a runaway loop
## into dropped frames instead of a dead session.
const SEND_BUDGET := 40
const SEND_WINDOW := 1.0

var _ws: WebSocketPeer
var _state := IDLE
var _url := ""
var _topic := ""
var _meta := {}
var _presence_key := ""

## Phoenix refs are opaque and only have to be unique per socket. A counter is
## enough; the join's ref is kept because it is the only way to recognise the join
## reply among every other phx_reply.
var _ref := 0
var _join_ref := ""

var _roster := {}
var _hb := 0.0
var _attempt := 0
var _retry_in := 0.0
var _sent_in_window := 0
var _window := 0.0
var _dropped_sends := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


## Opens a channel for `code`. `meta` is this client's lobby entry and comes straight
## back to every peer inside presence — a display name and the host flag ride here.
func open_channel(project_url: String, apikey: String, code: String, presence_key: String,
		meta: Dictionary) -> void:
	_url = PHX.socket_url(project_url, apikey)
	_topic = PHX.topic_for(code)
	_presence_key = presence_key
	_meta = meta.duplicate(true)
	_attempt = 0
	_roster = {}
	set_process(true)
	_dial()


## Fire-and-forget. Returns false when the frame was dropped, which the caller is
## free to ignore for a snapshot (the next one supersedes it) and should not ignore
## for a one-shot event.
func send(event: String, payload: Variant) -> bool:
	if _state != READY:
		return false
	if _sent_in_window >= SEND_BUDGET:
		_dropped_sends += 1
		return false
	_sent_in_window += 1
	_ws.send_text(PHX.broadcast_frame(_topic, _next_ref(), _join_ref, event, payload))
	return true


## Leaves cleanly so peers see the departure immediately rather than waiting out the
## presence timeout. Best-effort: a socket that is already gone cannot say goodbye.
func close_channel() -> void:
	if _ws != null and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(PHX.leave_frame(_topic, _next_ref(), _join_ref))
		_ws.poll()   # flush the leave before the close frame follows it down
		_ws.close()
	_state = CLOSED
	set_process(false)


func roster() -> Dictionary:
	return _roster.duplicate(true)


func state() -> int:
	return _state


## Exposed for the HUD's connection pip and for diagnosing a session that feels bad:
## a non-zero count means the budget above is discarding frames.
func dropped_sends() -> int:
	return _dropped_sends


func _dial() -> void:
	_ws = WebSocketPeer.new()
	_state = CONNECTING
	var err := _ws.connect_to_url(_url)
	if err != OK:
		# A malformed URL fails here rather than asynchronously. Retrying would just
		# reproduce it, so this is terminal.
		_state = CLOSED
		set_process(false)
		failed.emit("could not open a socket (error %d)" % err)


func _process(dt: float) -> void:
	if _state == CLOSED or _state == IDLE:
		return

	# Reconnect ladder. Held here rather than on a Timer so it obeys the same
	# process mode as everything else in this node.
	if _ws == null:
		_retry_in -= dt
		if _retry_in <= 0.0:
			_dial()
		return

	_ws.poll()

	_window += dt
	if _window >= SEND_WINDOW:
		_window = 0.0
		_sent_in_window = 0

	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if _state == CONNECTING:
				_send_join()
			_pump()
			_beat(dt)
		WebSocketPeer.STATE_CLOSED:
			_on_socket_closed()
		_:
			pass   # CONNECTING / CLOSING: nothing to do but wait for poll()


func _send_join() -> void:
	_state = JOINING
	_join_ref = _next_ref()
	_ws.send_text(PHX.join_frame(_topic, _join_ref, _presence_key))


func _beat(dt: float) -> void:
	_hb += dt
	if _hb < PHX.HEARTBEAT_PERIOD:
		return
	_hb = 0.0
	_ws.send_text(PHX.heartbeat_frame(_next_ref()))


func _pump() -> void:
	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		# Protocol 1.0.0 is text-only. A binary frame here means the server is
		# speaking 2.0.0, which would mean the vsn pin in the URL stopped working —
		# worth ignoring quietly rather than feeding to a JSON parser.
		if not _ws.was_string_packet():
			continue
		_handle(PHX.decode(pkt.get_string_from_utf8(), _join_ref))


func _handle(msg: Dictionary) -> void:
	var kind: int = msg["kind"]
	match kind:
		PHX.KIND_JOIN_OK:
			_state = READY
			_attempt = 0
			# Presence is tracked immediately on join, not lazily: until this lands
			# the peers cannot see us, and a lobby that shows three of four players
			# is indistinguishable from one that is broken.
			_ws.send_text(PHX.presence_frame(_topic, _next_ref(), _join_ref, _meta))
			joined.emit(roster())
		PHX.KIND_JOIN_ERROR:
			var reason: String = msg["reason"]
			# Auth and config errors are permanent; retrying re-fails identically and
			# the server backs off harder each time. Only transient classes retry.
			if _permanent(reason):
				_state = CLOSED
				set_process(false)
				failed.emit(reason if not reason.is_empty() else "the room refused the connection")
			else:
				_retry("join rejected: " + reason)
		PHX.KIND_PRESENCE_STATE:
			_roster = PHX.presence_state(msg["payload"])
			roster_changed.emit(roster())
		PHX.KIND_PRESENCE_DIFF:
			_roster = PHX.presence_diff(_roster, msg["payload"])
			roster_changed.emit(roster())
		PHX.KIND_BROADCAST:
			message.emit(msg["event"], msg["payload"])
		PHX.KIND_SYSTEM:
			# Channel-level system errors are always followed by phx_close, so this
			# is a diagnosis and not an action. Surfacing it matters because "Too
			# many messages per second" is the one failure whose cause is our own
			# tick rate rather than the network.
			var text: String = msg["reason"]
			if not text.is_empty():
				push_warning("realtime: " + text)
		PHX.KIND_ERROR, PHX.KIND_CLOSE:
			_retry("the channel closed")


func _on_socket_closed() -> void:
	var code := _ws.get_close_code()
	var why := _ws.get_close_reason()
	_ws = null
	# 1000 is a clean close, which after close_channel() is expected and after
	# anything else means the server sent us away deliberately.
	if _state == CLOSED:
		return
	_retry("socket closed (%d) %s" % [code, why])


## Schedules another dial, or gives up. A session that has already been joined
## reports `dropped` so the game can pause and say so, rather than silently
## reconnecting into a match that has moved on without it.
func _retry(why: String) -> void:
	var was_ready := _state == READY
	if _ws != null:
		_ws.close()
		_ws = null
	_roster = {}
	if _attempt >= 6:
		_state = CLOSED
		set_process(false)
		if was_ready:
			dropped.emit(why)
		else:
			failed.emit(why)
		return
	var step: float = BACKOFF[mini(_attempt, BACKOFF.size() - 1)]
	_attempt += 1
	_retry_in = step
	_state = CONNECTING
	if was_ready:
		# Told once, on the transition. A reconnecting client that keeps emitting
		# would redraw the lobby every frame of the outage.
		dropped.emit(why)


## The error classes the protocol documents as "do not retry". Matched on the code
## prefix the server puts in front of the human message ("<Code>: <text>"), with the
## one documented exception — UnknownErrorOnChannel arrives as a bare string — left
## to fall through as retryable, which is the safer default for an unknown.
static func _permanent(reason: String) -> bool:
	for code: String in ["MalformedJWT", "JwtSignatureError", "Unauthorized",
			"TopicNameRequired", "TenantNotFound", "RealtimeDisabledForTenant",
			"RealtimeDisabledForConfiguration"]:
		if reason.begins_with(code):
			return true
	return false


func _next_ref() -> String:
	_ref += 1
	return str(_ref)
