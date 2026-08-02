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

## Outbound ceiling, and it is sized to make exceeding the free tier IMPOSSIBLE
## rather than unlikely.
##
## Supabase bills and limits an "event", defined on its own limits page as a message
## delivered to *or* sent from a client. One publish into a room of N therefore costs
## N events. With MAX_PLAYERS = 2 and both ends publishing:
##
##   worst case events/s = 2 clients x 2 events per publish x SEND_BUDGET
##                       = 4 x SEND_BUDGET
##
## The free tier caps the project at 100 events/second and enforces it by
## DISCONNECTING the sockets (`tenant_events`), which the client then reconnects
## into a loop. 4 x 24 = 96, so this value cannot breach it no matter what the layer
## above asks for.
##
## It was 40. An adversarial pass measured the shipped rates at 88 events/s at rest
## and 208 busy — over the limit — because every budget in the design counted
## PUBLISHES where the limit counts EVENTS, and none of them counted the host's own
## `me`. Lowering this is the load-shedding backstop, not the fix: the real fix is
## folding the host's per-event messages (world / kill / spawn) into the periodic
## snapshot so the cost stops scaling with what happens in the game. Until that
## lands, a busy host sheds here — and it sheds SNAPSHOTS, which the next one
## supersedes, while session_runtime.gd re-queues the batched events that a refusal
## would otherwise have destroyed.
const SEND_BUDGET := 24
const SEND_WINDOW := 1.0

## THE WEB PULSE, AND IT EXISTS BECAUSE A BACKGROUNDED TAB USED TO LOSE THE ROOM.
##
## Godot's web main loop runs on `requestAnimationFrame`, and Chrome throttles rAF to
## nothing on a tab that is not foreground. No main loop means `_process` never runs,
## which means the heartbeat never goes out, and the server closes an idle socket at
## 25 s. MEASURED in Chrome against the shipped build: leave the tab unfocused for
## about a minute and the session dies with "Lost the connection to the room" —
## notes/net/2026-07-31-realtime-probe.md.
##
## `PROCESS_MODE_ALWAYS` above does NOT help here, and the distinction is worth being
## precise about: that defends against `get_tree().paused`, which is a *tree* state.
## This is the *engine* not being ticked at all. From inside GDScript the two look
## identical and only one of them is fixable from there.
##
## `setInterval` survives what rAF does not. Chrome throttles a hidden tab's timers by
## raising their MINIMUM interval to one second — it does not halt them — so a 5 s
## pulse is not slowed at all. Measured in the shipped build with the tab hidden for
## 129 s: 25 fires, inter-arrival 4993-5007 ms.
##
## THE LIMIT PREDICTED HERE DID NOT MATERIALISE. This comment used to say that
## "intensive throttling" would drop timers to once a minute after about five minutes
## hidden and the heartbeat would lapse again. Measured instead: a room hosted in the
## shipped web build survived 550 s (9.2 minutes) hidden and untouched with no
## presence leave at any point. The mechanism is not established — Chrome may exempt
## a page holding an open WebSocket, or the audio context may mark the tab audible —
## so no upper bound is claimed in either direction. See
## notes/net/2026-07-31-realtime-probe.md.
##
## Native builds never install it: `OS.has_feature("web")` is false, there is no
## bridge, and the frame loop was never throttled in the first place.
const PULSE_MS := 5000

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
## WALL CLOCK (msec), not an accumulated dt, because the heartbeat now has TWO
## drivers — the frame loop and the web pulse. Accumulating in both double-counts;
## accumulating in one leaves the other unable to tell whether a beat is owed.
var _hb_at := 0
var _attempt := 0
var _retry_in := 0.0
var _sent_in_window := 0
var _window := 0.0
var _dropped_sends := 0

## Web only, and null everywhere else. Held rather than passed straight to the
## bridge because `create_callback` does not retain it — see `_install_pulse`.
var _pulse_cb: JavaScriptObject


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
	_install_pulse()
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
	_clear_pulse()


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
	# So the first beat is owed one full period from the dial rather than immediately.
	_hb_at = Time.get_ticks_msec()
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
			_beat_if_due()
		WebSocketPeer.STATE_CLOSED:
			_on_socket_closed()
		_:
			pass   # CONNECTING / CLOSING: nothing to do but wait for poll()


func _send_join() -> void:
	_state = JOINING
	_join_ref = _next_ref()
	_ws.send_text(PHX.join_frame(_topic, _join_ref, _presence_key))


## Idempotent and safe to call from either driver — see `_hb_at`.
func _beat_if_due() -> void:
	var now := Time.get_ticks_msec()
	if now - _hb_at < int(PHX.HEARTBEAT_PERIOD * 1000.0):
		return
	_hb_at = now
	_ws.send_text(PHX.heartbeat_frame(_next_ref()))


# --- the web pulse -----------------------------------------------------------

## A `setInterval` on the JS side that pokes the socket when the frame loop cannot.
## See PULSE_MS for why this is needed and what it does not buy.
##
## `save_store.gd` is the precedent for reaching the browser this way, and its reason
## for routing through `eval()` rather than `get_interface()` holds here too: the
## whole call is wrapped so a browser that refuses any of it fails as a return value
## rather than as an uncatchable exception on the JS side.
func _install_pulse() -> void:
	if not OS.has_feature("web"):
		return
	# Held on the instance because the bridge does not retain it: a collected callback
	# turns the interval into a silent no-op, which is exactly the bug being fixed.
	_pulse_cb = JavaScriptBridge.create_callback(_on_pulse)
	var window: JavaScriptObject = JavaScriptBridge.get_interface("window")
	if window == null:
		return
	window.__kn_pulse = _pulse_cb
	# The previous interval is cleared first. session.gd builds a FRESH channel node
	# for every join (`_open`), so without this a second lobby in one page load would
	# leave the first one's interval running against a freed callback.
	JavaScriptBridge.eval("""
		(function () {
			if (window.__kn_pulse_id) { clearInterval(window.__kn_pulse_id); }
			window.__kn_pulse_id = setInterval(function () {
				if (window.__kn_pulse) { window.__kn_pulse(); }
			}, %d);
		})();
	""" % PULSE_MS, true)


func _clear_pulse() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("""
		if (window.__kn_pulse_id) {
			clearInterval(window.__kn_pulse_id);
			window.__kn_pulse_id = 0;
		}
		window.__kn_pulse = null;
	""", true)
	_pulse_cb = null


## Deliberately does the MINIMUM: poll, so the socket's state and inbound queue
## advance, and beat if one is owed. It does not `_pump()` — dispatching game
## messages into a tab that is not rendering would drive the session from outside the
## frame loop, and there is nothing to draw the result on. The packets sit in the
## queue and `_process` drains them on the first real frame after the tab comes back.
func _on_pulse(_args: Array) -> void:
	if _ws == null or _state == CLOSED or _state == IDLE:
		return
	_ws.poll()
	if _state == READY and _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_beat_if_due()


## The interval outlives this node otherwise, and session.gd frees the channel on
## every leave.
func _exit_tree() -> void:
	_clear_pulse()


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
