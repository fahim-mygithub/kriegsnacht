extends RefCounted

## The Supabase Realtime wire format, and nothing else.
##
## Deliberately has no socket in it. Every function here is static and pure: text in,
## text out. That is not tidiness — it is the only way this layer gets tested. The
## frame gate taught the project that a subsystem which can only be exercised against
## live hardware is a subsystem nobody exercises, and a network is worse than a GPU
## because it also fails intermittently. Framing, parsing, presence folding and the
## room-code alphabet are all decidable with no connection at all, so they live here
## and `scripts/net/realtime.gd` owns the parts that genuinely need a socket.
##
## PROTOCOL VERSION 1.0.0, NOT 2.0.0, and this is a choice rather than an oversight.
## 2.0.0 encodes each frame as a positional JSON array plus two binary frame types;
## 1.0.0 uses one flat JSON object per frame. The binary form would save perhaps 40
## bytes a frame against a snapshot budget where the payload dwarfs the envelope, and
## it costs a hand-rolled byte-packer on both ends. `vsn=1.0.0` is requested
## explicitly in the URL because the server's own default is 1.0.0 *today* — an
## unpinned default is a silent breaking change waiting for a server upgrade.
##
## Every shape below was verified against the live project before this file was
## written, not read out of the documentation and hoped for. Two anonymous clients
## holding only the publishable key joined one public channel, exchanged presence and
## broadcasts, and sustained 15 Hz with zero loss. The measurements, and the one
## discarded bogus figure, are in notes/net/2026-07-31-realtime-probe.md.

## Pinned; see the class comment. Sent as a query parameter, not a header, because a
## browser's WebSocket constructor cannot set request headers and the web export is
## the only target that matters.
const VSN := "1.0.0"

## Phoenix reserves this topic for connection-level traffic. A heartbeat addressed to
## a real channel is ignored and the socket dies at the 25 s mark looking like a
## network fault.
const SYSTEM_TOPIC := "phoenix"

## Under 25 s, with 10 s of margin. The server closes an idle socket at 25 s.
##
## THE MARGIN ABSORBS A STALLED FRAME OR A BACKGROUNDED TAB, NOT A LOST BEAT — an
## earlier version of this comment claimed one dropped heartbeat was survivable, and
## the arithmetic refutes it: two periods is 30 s, which is past the close. It is also
## the wrong worry. WebSocket is TCP, so a frame is never dropped, only delayed; what
## this margin actually buys is room for the delay.
const HEARTBEAT_PERIOD := 15.0

## Channel topics are namespaced so a room code can never collide with some other
## channel this project might one day open on the same project ref.
const TOPIC_PREFIX := "realtime:room:"

## Mirrors public.room_alphabet() in the database, and the duplication is deliberate.
## The client needs this to validate a typed code BEFORE spending a round trip, and a
## round trip to fetch a constant that has never changed would be worse. The database
## copy is the authority; scripts/dev/checks/net.gd asserts the two agree in shape
## (28 glyphs, no vowels, no L/0/1) so a divergence is caught here rather than by a
## player typing a code the server cannot represent.
##
## No vowels, so a generated code can never spell a word — free to prevent, and this
## code gets read aloud. No L, 0 or 1, which are the glyphs people mis-hear and
## mistype. Six characters gives 28^6 = 481,890,304.
const ALPHABET := "BCDFGHJKMNPQRSTVWXYZ23456789"
const CODE_LEN := 6

## Frame kinds, normalised by decode() so callers match on one small closed set
## instead of on raw Phoenix event strings.
enum {
	KIND_UNKNOWN,
	KIND_JOIN_OK,       ## phx_reply, status ok, answering our join
	KIND_JOIN_ERROR,    ## phx_reply, status error — carries a reason worth showing
	KIND_REPLY,         ## any other phx_reply
	KIND_BROADCAST,     ## a peer's game message
	KIND_PRESENCE_STATE,
	KIND_PRESENCE_DIFF,
	KIND_SYSTEM,        ## rate limits and token trouble arrive here
	KIND_CLOSE,
	KIND_ERROR,         ## phx_error: the channel process died, rejoin with backoff
}


# --- outbound ----------------------------------------------------------------

## The socket URL. The key rides in the query string for the reason given above; it
## is a *publishable* key and is meant to be visible, so this is not a leak.
static func socket_url(project_url: String, apikey: String) -> String:
	var base := project_url.strip_edges().trim_suffix("/")
	# Only the scheme changes. Rebuilding the host from parts would break the moment
	# someone points this at a self-hosted instance on a non-default port.
	if base.begins_with("https://"):
		base = "wss://" + base.substr(8)
	elif base.begins_with("http://"):
		base = "ws://" + base.substr(7)
	return "%s/realtime/v1/websocket?apikey=%s&vsn=%s" % [base, apikey.uri_encode(), VSN]


static func topic_for(code: String) -> String:
	return TOPIC_PREFIX + code.strip_edges().to_upper()


## Joins a PUBLIC channel. `private` is false and that is load-bearing: a private
## channel is gated by RLS and would need a signed JWT, which would need accounts,
## which this game does not have. Public channels were verified to accept an
## anonymous client holding only the publishable key.
##
## `self` is false so the sender never receives its own broadcast — the host would
## otherwise ingest and apply its own authoritative snapshot one relay round trip
## after producing it, which is a stutter with no upside.
static func join_frame(topic: String, ref: String, presence_key: String) -> String:
	return _frame(topic, "phx_join", ref, ref, {
		"config": {
			"broadcast": {"ack": false, "self": false},
			# The lobby roster is presence and nothing else. It survives a tab dying,
			# which a table row does not.
			"presence": {"enabled": true, "key": presence_key},
			"private": false,
		},
	})


## The `join_ref` is deliberately absent — a heartbeat belongs to the socket, not to
## a channel, and the server rejects one that claims otherwise.
static func heartbeat_frame(ref: String) -> String:
	return _frame(SYSTEM_TOPIC, "heartbeat", ref, "", {})


static func broadcast_frame(topic: String, ref: String, join_ref: String, event: String,
		payload: Variant) -> String:
	return _frame(topic, "broadcast", ref, join_ref, {
		"type": "broadcast",
		"event": event,
		"payload": payload,
	})


## Publishes this client's lobby entry. Whatever is in `meta` comes straight back to
## every other client inside presence_state / presence_diff, so this is where a
## display name and the host flag travel.
static func presence_frame(topic: String, ref: String, join_ref: String,
		meta: Dictionary) -> String:
	return _frame(topic, "presence", ref, join_ref, {
		"type": "presence",
		"event": "track",
		"payload": meta,
	})


static func leave_frame(topic: String, ref: String, join_ref: String) -> String:
	return _frame(topic, "phx_leave", ref, join_ref, {})


## One flat object per frame — the whole of protocol 1.0.0. `join_ref` is omitted
## rather than sent empty when a frame does not belong to a channel, because Phoenix
## distinguishes absent from empty and the heartbeat is the case that cares.
static func _frame(topic: String, event: String, ref: String, join_ref: String,
		payload: Variant) -> String:
	var f := {}
	f["topic"] = topic
	f["event"] = event
	f["payload"] = payload
	f["ref"] = ref
	if not join_ref.is_empty():
		f["join_ref"] = join_ref
	return JSON.stringify(f)


# --- inbound -----------------------------------------------------------------

## Normalises one server frame into `{kind, event, payload, ref, topic, reason}`.
##
## Everything arriving here is untrusted in the same sense save_store.gd's blob is:
## it crossed a network, and a truncated or hostile frame must produce a KIND_UNKNOWN
## rather than a crash or a half-read dictionary. So every field is type-checked
## before it is read, and there is exactly one failure shape.
##
## `join_ref_sent` is the ref this client used for its own phx_join. It is how a join
## reply is told apart from every other phx_reply — without it, the ack for a routine
## broadcast looks exactly like a successful join.
##
## EVERY NUMBER IN THE RETURNED PAYLOAD IS A FLOAT. Godot's JSON parser hands back
## TYPE_FLOAT for whole numbers, so a zombie id written as `4` arrives as `4.0`.
##
## `payload["id"] == 4` is TRUE — GDScript compares int and float numerically, and an
## earlier version of this comment claimed otherwise. What actually breaks is
## everything that is not `==`: `{4: zombie}.has(payload["id"])` is FALSE, because a
## float key never matches an int key, so any per-id entity table misses every single
## lookup; and `str(payload["id"])` is "4.0", not "4". Consumers must cast at the
## boundary. Measured rather than reasoned about — scripts/dev/checks/net.gd::_numbers
## asserts each of these so the correction cannot quietly regress.
static func decode(text: String, join_ref_sent: String) -> Dictionary:
	var out := {
		"kind": KIND_UNKNOWN, "event": "", "payload": {}, "ref": "", "topic": "", "reason": "",
	}
	# JSON.new().parse() rather than parse_string(), matching save_store.gd:62 — the
	# static helper logs, and a clipped frame is an expected arrival shape on a
	# network, not an incident worth a red line in every player's console.
	var j := JSON.new()
	if j.parse(text) != OK:
		return out
	if typeof(j.data) != TYPE_DICTIONARY:
		return out
	var msg: Dictionary = j.data

	var event: String = str(msg.get("event", ""))
	out["event"] = event
	out["topic"] = str(msg.get("topic", ""))
	out["ref"] = str(msg.get("ref", ""))

	var body: Variant = msg.get("payload")
	var payload: Dictionary = body if typeof(body) == TYPE_DICTIONARY else {}
	out["payload"] = payload

	match event:
		"phx_reply":
			var status := str(payload.get("status", ""))
			var resp: Variant = payload.get("response")
			var response: Dictionary = resp if typeof(resp) == TYPE_DICTIONARY else {}
			out["reason"] = str(response.get("reason", ""))
			# Only the reply carrying our own join ref is a join result. Broadcasts
			# are acked with phx_reply too when ack is on, and a future change that
			# turns ack on must not start reporting spurious joins.
			if out["ref"] == join_ref_sent:
				out["kind"] = KIND_JOIN_OK if status == "ok" else KIND_JOIN_ERROR
			else:
				out["kind"] = KIND_REPLY
		"broadcast":
			out["kind"] = KIND_BROADCAST
			# A broadcast nests the user event one level down: the outer envelope is
			# always "broadcast" and the inner "event" is ours. Callers want the
			# inner one, so it is hoisted here rather than at four call sites.
			out["event"] = str(payload.get("event", ""))
			var inner: Variant = payload.get("payload")
			out["payload"] = inner if typeof(inner) == TYPE_DICTIONARY else {}
		"presence_state":
			out["kind"] = KIND_PRESENCE_STATE
		"presence_diff":
			out["kind"] = KIND_PRESENCE_DIFF
		"system":
			out["kind"] = KIND_SYSTEM
			out["reason"] = str(payload.get("message", ""))
		"phx_close":
			out["kind"] = KIND_CLOSE
		"phx_error":
			out["kind"] = KIND_ERROR
	return out


# --- presence ----------------------------------------------------------------

## Folds a presence_state payload into a flat `{key: meta}` roster.
##
## The wire shape is `{key: {metas: [{phx_ref, ...}]}}` — an ARRAY of metas per key,
## because Phoenix supports the same identity being present from several sockets at
## once. This game does not: one tab is one player. So the first meta wins and the
## rest are dropped, which is a real decision and not a shortcut — a player who
## reconnects before the server has expired their old entry would otherwise appear in
## the lobby twice.
static func presence_state(payload: Dictionary) -> Dictionary:
	var roster := {}
	for key: String in payload.keys():
		var entry: Variant = payload[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var meta := _first_meta(entry)
		if not meta.is_empty():
			roster[key] = meta
	return roster


## Applies a presence_diff to a roster and returns the new one.
##
## LEAVES ARE APPLIED BEFORE JOINS. A reconnecting client produces a diff holding the
## same key in both halves, and in that order the surviving entry is the new one. The
## other order silently deletes a player who is actually present, which reads as a
## random disconnect and is the kind of bug that takes an afternoon.
static func presence_diff(roster: Dictionary, payload: Dictionary) -> Dictionary:
	var out := roster.duplicate(true)
	var leaves: Variant = payload.get("leaves")
	if typeof(leaves) == TYPE_DICTIONARY:
		var gone: Dictionary = leaves
		for key: String in gone.keys():
			out.erase(key)
	var joins: Variant = payload.get("joins")
	if typeof(joins) == TYPE_DICTIONARY:
		var came: Dictionary = joins
		for key: String in came.keys():
			var entry: Variant = came[key]
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var meta := _first_meta(entry)
			if not meta.is_empty():
				out[key] = meta
	return out


## `phx_ref` is Phoenix's own bookkeeping and means nothing to the game. It is
## stripped here so a roster comparison in the lobby does not see a change every time
## the server re-stamps an unchanged player.
static func _first_meta(entry: Dictionary) -> Dictionary:
	var metas: Variant = entry.get("metas")
	if typeof(metas) != TYPE_ARRAY:
		return {}
	var list: Array = metas
	if list.is_empty():
		return {}
	if typeof(list[0]) != TYPE_DICTIONARY:
		return {}
	var meta: Dictionary = list[0]
	var out := meta.duplicate(true)
	out.erase("phx_ref")
	return out


# --- room codes --------------------------------------------------------------

## True for a code this client could plausibly send. Shape only — whether the room
## EXISTS is the server's answer, and a client that tries to decide it locally is a
## client that will one day refuse a valid room.
static func is_valid_code(code: String) -> bool:
	var c := code.strip_edges().to_upper()
	if c.length() != CODE_LEN:
		return false
	for i in c.length():
		if not ALPHABET.contains(c[i]):
			return false
	return true


## What the JOIN field should hold as the player types: upper-cased, stripped of
## anything not in the alphabet, and clipped to length. Filtering rather than
## rejecting means separators survive contact — "bcdf-23", "bcdf 23" and "BCDF23"
## all arrive as BCDF23 instead of bouncing with an error the player cannot act on.
##
## IT DOES NOT RESCUE PROSE, and an earlier version of this comment claimed it did.
## "code: bcdf-23" sanitises to CDBCDF, because C and D are themselves legal glyphs
## and the filter has no way to know they came from the word "code". Caught by a test
## asserting the claim rather than the behaviour. Anything cleverer — stripping a
## leading "code", splitting on the last separator — guesses at the player's intent
## and guesses wrong on the codes that happen to look like the prefix. The paste case
## is handled by the player deleting the extra characters, which they can see.
static func sanitise_code(raw: String) -> String:
	var out := ""
	var up := raw.to_upper()
	for i in up.length():
		var ch := up[i]
		if ALPHABET.contains(ch):
			out += ch
		if out.length() >= CODE_LEN:
			break
	return out
