extends RefCounted

## The co-op net layer's headless half: everything about the wire that can be
## decided without a wire.
##
## ---------------------------------------------------------------------------
## THE BOUNDARY, stated first, because a fake version of it would be worse than an
## honest gap. This is the same argument scripts/dev/checks/frame.gd makes for the
## rendered frame, and it is made here for the same reason: a subsystem that can
## only be exercised against live hardware is a subsystem nobody exercises, and a
## network is worse than a GPU because it also fails intermittently.
##
## NOTHING BELOW OPENS A SOCKET. Not one assertion reaches the relay, the room
## service, or the network at all — `Net.host_room()` and `Net.join_room()` are
## never called, no `WebSocketPeer` is constructed, no `HTTPRequest` is issued.
## `--verify` is hermetic and fast and must stay both; a suite that needs the
## internet is a suite that goes red on a train. The last assertion in this file
## re-reads `Net.channel()` and fails if anything here left a transport behind.
##
## What that leaves, and it is most of the layer's surface:
##
##   - the outbound frame shapes, parsed back out of the JSON rather than compared
##     as strings, including the heartbeat's missing `join_ref` — the one that
##     kills the socket at 25 s while looking exactly like a network fault;
##   - `decode()` normalising every documented event, and both directions of the
##     join-reply rule, which is the only thing separating an ack from a join;
##   - `decode()` against hostile input: truncated JSON, an array, a null payload,
##     non-JSON garbage. One failure shape, never a crash;
##   - the fact that EVERY NUMBER OFF THE WIRE IS A FLOAT, and the consequence
##     that actually bites (see `_numbers`);
##   - presence folding, and the diff applying leaves BEFORE joins;
##   - the room-code alphabet, checked against the one the database generates
##     from, and `sanitise_code` / `is_valid_code` bounded at both ends;
##   - `Net`'s public API existing under the names the menu will call, its state
##     machine, and its lobby ordering.
##
## What is NOT covered here and must not be claimed: whether the relay ACCEPTS
## these frames, the join handshake, the heartbeat's cadence in real time, the
## reconnect ladder actually laddering, and the four `rooms` RPCs. Those need a
## socket. They were measured by hand once, against the live project, and the
## numbers are in notes/net/2026-07-31-realtime-probe.md — which is evidence, not
## a gate, and the difference is worth being honest about.
##
## ONE GAP IS DELIBERATE AND WORTH NAMING. `join_room()` rejects a malformed code
## locally, before any request (session.gd:102-107), and that branch is decidable
## with no network — but only while the guard is there. Driving it means calling
## `join_room()`, and if the guard were ever removed the call would fire a real
## HTTP request out of `--verify`, which is precisely the property this file is
## supposed to protect. So the RULE is asserted here through the two functions the
## guard calls, and the BRANCH belongs to the menu package, which can drive it
## against a stubbed transport.
##
## NOTHING BELOW IS A SOFT SKIP. Every check either asserts or fails; there is no
## `v.check("...", true, "needs a network")` in this file, because one such check
## passed for an entire wave of this project while testing nothing.

const PHX := preload("res://scripts/net/phoenix.gd")
const REALTIME := preload("res://scripts/net/realtime.gd")
## For the periodic rates only. The send ceiling has to be checked against what the
## layer above actually asks of it, not against a number restated here — a constant
## copied into a test is a constant that stops tracking the thing it describes.
const RUNTIME := preload("res://scripts/net/session_runtime.gd")

## The alphabet the DATABASE generates codes from, stated here independently
## rather than read out of phoenix.gd, so that the two are compared instead of one
## being compared with itself — the same reason frame.gd's REQUIRED list is not
## `registry.keys()`.
##
## PROVENANCE, and it is a query and not a memory:
##   select public.room_alphabet();  -> 'BCDFGHJKMNPQRSTVWXYZ23456789'
## run against project qalanxifxfukkeqdhfqh on 2026-07-31. `public.claim_room()`
## picks six glyphs out of it (`for i in 0..5`), which is where CODE_LEN comes
## from, and `room_exists`/`release_room`/`heartbeat_room` all `upper(p_code)`,
## which is why sanitise_code upper-casing is not cosmetic.
const DB_ALPHABET := "BCDFGHJKMNPQRSTVWXYZ23456789"
const DB_CODE_LEN := 6

## The server's idle close, from phoenix.gd:36-38 and the reason HEARTBEAT_PERIOD
## exists at all. Restated here so the relation below is an assertion about two
## independent numbers rather than about one number and itself.
const IDLE_CLOSE := 25.0

## `delete from public.rooms where last_seen < now() - interval '2 hours'` — the
## lazy reap inside `public.claim_room()`, read off the live project on 2026-07-31
## at the same time as the alphabet. Session.HEARTBEAT_PERIOD has to sit well
## inside it or a long lobby gets collected out from under itself.
const REAP_WINDOW := 7200.0


static func run(v: Verify, _main: Node3D) -> void:
	# Takes no `main`: not one assertion here needs the tree, the map or the
	# player. The net layer's headless half is pure functions plus one autoload.
	_alphabet(v)
	_codes(v)
	_frames(v)
	_url(v)
	_decode(v)
	_hostile(v)
	_numbers(v)
	_presence(v)
	_reconnect(v)
	_session(v)
	_identity(v)
	_hermetic(v)


# --- helpers ------------------------------------------------------------------

## Frames are asserted by PARSING them, never by comparing strings. Godot's
## `JSON.stringify` sorts keys, so the literal text of a frame is an artefact of
## the serialiser rather than of the protocol, and a string comparison would break
## on a key rename that the server would not even notice.
static func _obj(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = parsed
	return out


static func _sub(d: Dictionary, key: String) -> Dictionary:
	var got: Variant = d.get(key)
	if typeof(got) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = got
	return out


## A wire flag as a tri-state: 1 true, 0 false, -1 "not a JSON boolean at all".
## Comparing a Variant to a bool with `==` throws when the Variant turns out to be
## a String, and a check that CRASHES on the sabotage it is named for reports
## nothing at all — CONTROLLED 2026-07-31: with `"private": false` written as the
## string `"false"`, the first version of this section died on the comparison and
## took SEVEN assertions down with it, reporting 60 green and 0 red. Through
## `_flag` the same sabotage reddens exactly the two checks it should.
static func _flag(d: Dictionary, key: String) -> int:
	var got: Variant = d.get(key)
	if typeof(got) != TYPE_BOOL:
		return -1
	return 1 if bool(got) else 0


# --- the room code alphabet ---------------------------------------------------

## Six characters read aloud over voice chat is the entire design constraint, and
## every property below follows from it.
static func _alphabet(v: Verify) -> void:
	var a: String = PHX.ALPHABET
	var seen := {}
	var dupe := ""
	var illegal := ""
	for i in a.length():
		var ch := a[i]
		if seen.has(ch):
			dupe += ch
		seen[ch] = true
		# No vowel, so a generated code can never spell a word — free to prevent,
		# and this one gets read out to a friend. No L, 0 or 1: the glyphs that are
		# mis-heard and mis-typed. phoenix.gd:52-54.
		if ch in "AEIOU":
			illegal += "vowel:%s " % ch
		if ch in "L01":
			illegal += "confusable:%s " % ch
		if ch != ch.to_upper():
			illegal += "lowercase:%s " % ch
	v.check("the room-code alphabet is 28 distinct glyphs with no vowel and no L/0/1",
		a.length() == 28 and dupe.is_empty() and illegal.is_empty(),
		"len=%d dupes='%s' %s" % [a.length(), dupe, illegal])

	# THE MIRROR. phoenix.gd:45-50 promises this file makes this comparison, and
	# without it the client can happily refuse a code the server just issued.
	v.check("the client's alphabet is the one the database generates codes from",
		a == DB_ALPHABET,
		"client='%s' database='%s'" % [a, DB_ALPHABET])
	v.check("a code is six glyphs, which is what public.claim_room() emits",
		PHX.CODE_LEN == DB_CODE_LEN, "CODE_LEN=%d" % PHX.CODE_LEN)
	# phoenix.gd:54 quotes the size of the space; pinned so the quote cannot rot
	# quietly if either factor moves.
	v.check("the code space is the 481,890,304 the comment claims",
		v.near(pow(a.length(), PHX.CODE_LEN), 481890304.0, 0.5),
		"got %.0f" % pow(a.length(), PHX.CODE_LEN))


# --- sanitise / validate ------------------------------------------------------

## BOUNDED AT BOTH ENDS THROUGHOUT. A code test that only asserts the refusals
## passes just as well against a function that has stopped accepting anything —
## which is the shape of several green tests this project has already shipped.
static func _codes(v: Verify) -> void:
	# What a player actually types or pastes. Every one of these is the same room.
	var accepted := {
		"bcdf23": "BCDF23", "BCDF23": "BCDF23", "bcdf-23": "BCDF23",
		"bcdf 23": "BCDF23", " bcdf23 ": "BCDF23", "b-c-d-f-2-3": "BCDF23",
		"BcDf23": "BCDF23",
	}
	var wrong := ""
	for raw: String in accepted.keys():
		var want: String = accepted[raw]
		if PHX.sanitise_code(raw) != want:
			wrong += "'%s'->'%s' " % [raw, PHX.sanitise_code(raw)]
	v.check("sanitise_code accepts case, spaces and separators as the same code",
		wrong.is_empty(), wrong)

	# ...and the other end: glyphs that are not in the alphabet vanish, and the
	# field stops at six so a pasted line cannot overrun it.
	var refused := {"aeiou": "", "l01": "", "LOI": "", "!!!": "",
		"bcdf234567": "BCDF23", "": ""}
	var kept := ""
	for raw: String in refused.keys():
		var want: String = refused[raw]
		if PHX.sanitise_code(raw) != want:
			kept += "'%s'->'%s' (want '%s') " % [raw, PHX.sanitise_code(raw), want]
	v.check("sanitise_code drops illegal glyphs and clips at six", kept.is_empty(), kept)

	# THE DOCUMENTED LIMITATION, asserted as the behaviour rather than as the
	# behaviour anyone would prefer. phoenix.gd:321-327: C and D are legal glyphs,
	# the filter cannot know they came from the word "code", and every cleverer
	# rule guesses wrong on the codes that look like the prefix. An earlier version
	# of that comment claimed the prose case worked; this is the assertion that
	# caught it, and it stays because the claim is tempting to re-introduce.
	v.check("sanitise_code does not rescue prose, and CDBCDF is the real answer",
		PHX.sanitise_code("code: bcdf-23") == "CDBCDF",
		"got '%s'" % PHX.sanitise_code("code: bcdf-23"))

	v.check("is_valid_code accepts a real code in either case and with spaces",
		PHX.is_valid_code("BCDF23") and PHX.is_valid_code("bcdf23")
			and PHX.is_valid_code(" bcdf23 "))
	var admitted := ""
	for bad: String in ["", "BCDF2", "BCDF234", "BCDFA3", "BCDFE3", "BCDFL3",
			"BCDF03", "BCDF13", "bcdf-23", "BCDF 3", "BCDF2!"]:
		if PHX.is_valid_code(bad):
			admitted += "'%s' " % bad
	v.check("is_valid_code refuses the wrong length, vowels, L/0/1 and separators",
		admitted.is_empty(), "admitted %s" % admitted)

	# Every glyph, not just the seven that happen to appear in BCDF23. A filter
	# that had lost one character of the alphabet would pass everything above.
	var lost := ""
	for i in PHX.ALPHABET.length():
		var code := PHX.ALPHABET[i].repeat(PHX.CODE_LEN)
		if not PHX.is_valid_code(code) or PHX.sanitise_code(code.to_lower()) != code:
			lost += PHX.ALPHABET[i]
	v.check("every glyph in the alphabet is legal in a code and survives sanitising",
		lost.is_empty(), "rejected: %s" % lost)

	# The two functions have to compose: whatever the field holds after sanitising
	# is either a code the server can be asked about or too short to send. It must
	# never be six characters of something the server would reject.
	var unsound := ""
	for raw: String in ["code: bcdf-23", "aeiou", "!!!!!!!!", "bcdf234567",
			"the code is BCDF23 ok?", "  ", "l0l0l0l0"]:
		var clean: String = PHX.sanitise_code(raw)
		if clean.length() > PHX.CODE_LEN:
			unsound += "'%s' too long " % raw
		if clean.length() == PHX.CODE_LEN and not PHX.is_valid_code(clean):
			unsound += "'%s'->'%s' unsendable " % [raw, clean]
	v.check("sanitise_code's output is never a six-character code the server would refuse",
		unsound.is_empty(), unsound)


# --- outbound framing ---------------------------------------------------------

static func _frames(v: Verify) -> void:
	var topic: String = PHX.topic_for("bcdf23")

	# THE LOAD-BEARING ONE. A heartbeat belongs to the SOCKET, not to a channel:
	# Phoenix reserves the "phoenix" topic for connection-level traffic, and a
	# heartbeat carrying a join_ref is rejected. The symptom is the socket dying at
	# the 25 s idle close, which is indistinguishable from the player's internet
	# dropping — so it would be diagnosed as a network fault forever.
	# phoenix.gd:32-38 and :113-116.
	var hb := _obj(PHX.heartbeat_frame("7"))
	v.check("a heartbeat is addressed to the socket and carries NO join_ref",
		String(hb.get("topic", "")) == PHX.SYSTEM_TOPIC
			and String(hb.get("topic", "")) == "phoenix"
			and not hb.has("join_ref")
			and String(hb.get("event", "")) == "heartbeat"
			and String(hb.get("ref", "")) == "7",
		str(hb))
	# ...and the other half of the same rule: the system topic is not a channel
	# topic. A heartbeat sent to the room would be silently ignored.
	v.check("the heartbeat's topic is not the room's",
		PHX.SYSTEM_TOPIC != topic and not PHX.SYSTEM_TOPIC.begins_with(PHX.TOPIC_PREFIX),
		"system='%s' room='%s'" % [PHX.SYSTEM_TOPIC, topic])

	# The converse, which is what makes the check above discriminate: every frame
	# that DOES belong to the channel carries the join_ref, and it is the ref the
	# join was sent with. A channel frame without one is dropped by the server.
	var missing := ""
	for text: String in [PHX.join_frame(topic, "1", "k"),
			PHX.broadcast_frame(topic, "5", "1", "snap", {}),
			PHX.presence_frame(topic, "6", "1", {}),
			PHX.leave_frame(topic, "7", "1")]:
		var f := _obj(text)
		if String(f.get("join_ref", "")) != "1" or String(f.get("topic", "")) != topic:
			missing += "%s " % String(f.get("event", "?"))
	v.check("every channel frame carries the join ref and the room's topic",
		missing.is_empty(), missing)

	# The join's own ref IS its join_ref — that is what makes the reply
	# identifiable at all, and decode()'s whole join rule rests on it.
	var join := _obj(PHX.join_frame(topic, "1", "presence-key"))
	v.check("phx_join's ref and join_ref are the same value",
		String(join.get("event", "")) == "phx_join"
			and String(join.get("ref", "")) == "1"
			and String(join.get("join_ref", "")) == "1",
		str(join))

	# PUBLIC, not private. A private channel is gated by RLS, which needs a signed
	# JWT, which needs accounts, which this game does not have — so `private:true`
	# would refuse every anonymous player. `self:false` keeps the host from
	# ingesting its own authoritative snapshot a round trip after producing it.
	# Presence is the lobby roster and nothing else. phoenix.gd:93-110.
	var cfg := _sub(_sub(join, "payload"), "config")
	var presence := _sub(cfg, "presence")
	var broadcast := _sub(cfg, "broadcast")
	v.check("the join asks for a public channel with presence on and self-echo off",
		_flag(cfg, "private") == 0 and _flag(presence, "enabled") == 1
			and String(presence.get("key", "")) == "presence-key"
			and _flag(broadcast, "self") == 0 and _flag(broadcast, "ack") == 0,
		str(cfg))
	# ...as real JSON booleans. `"false"` is a non-empty string on the far side and
	# every server in the world reads it as true, so a quoted flag would turn the
	# channel private while every value above still read correctly.
	v.check("the join's flags are JSON booleans, not strings or numbers",
		_flag(cfg, "private") >= 0 and _flag(presence, "enabled") >= 0
			and _flag(broadcast, "self") >= 0 and _flag(broadcast, "ack") >= 0,
		"private=%d enabled=%d self=%d ack=%d" % [typeof(cfg.get("private")),
			typeof(presence.get("enabled")), typeof(broadcast.get("self")),
			typeof(broadcast.get("ack"))])

	# A broadcast nests the game's event one level down: the outer envelope is
	# always "broadcast" and the inner event is ours. decode() hoists the inner one
	# back out, and the pair of assertions is what stops the two from drifting.
	var bc := _obj(PHX.broadcast_frame(topic, "5", "1", Net.EV_START, {"seed": 99}))
	var bp := _sub(bc, "payload")
	v.check("a broadcast wraps the game event in a broadcast envelope",
		String(bc.get("event", "")) == "broadcast"
			and String(bp.get("type", "")) == "broadcast"
			and String(bp.get("event", "")) == Net.EV_START
			and int(_sub(bp, "payload").get("seed", 0)) == 99,
		str(bc))

	# Presence is a `track` inside a `presence` envelope, and whatever is in `meta`
	# comes straight back to every peer — this is how the display name and the host
	# flag travel, so an empty or renamed payload is an anonymous lobby.
	var pf := _obj(PHX.presence_frame(topic, "6", "1", {"name": "Ann", "host": true}))
	var pp := _sub(pf, "payload")
	var meta := _sub(pp, "payload")
	v.check("presence tracks this client's lobby entry verbatim",
		String(pf.get("event", "")) == "presence"
			and String(pp.get("type", "")) == "presence"
			and String(pp.get("event", "")) == "track"
			and String(meta.get("name", "")) == "Ann" and _flag(meta, "host") == 1,
		str(pf))

	var lv := _obj(PHX.leave_frame(topic, "7", "1"))
	v.check("a leave is phx_leave on the channel with an empty payload",
		String(lv.get("event", "")) == "phx_leave" and _sub(lv, "payload").is_empty(),
		str(lv))

	# PROTOCOL 1.0.0: one flat JSON OBJECT per frame. 2.0.0 is a positional array
	# and two binary frame types; the version is pinned in the URL precisely so the
	# server cannot switch us. A frame that stopped being a flat object with these
	# keys would mean the pin had failed. phoenix.gd:13-19 and :144-146.
	var shape := ""
	var legal := ["topic", "event", "payload", "ref", "join_ref"]
	for text: String in [PHX.heartbeat_frame("1"), PHX.join_frame(topic, "1", "k"),
			PHX.broadcast_frame(topic, "2", "1", "e", {}),
			PHX.presence_frame(topic, "3", "1", {}), PHX.leave_frame(topic, "4", "1")]:
		var f := _obj(text)
		if f.is_empty():
			shape += "not an object; "
			continue
		for k: String in f.keys():
			if not legal.has(k):
				shape += "stray key %s; " % k
		for k: String in ["topic", "event", "payload", "ref"]:
			if not f.has(k):
				shape += "missing %s; " % k
		if typeof(f.get("payload")) != TYPE_DICTIONARY:
			shape += "payload is type %d; " % typeof(f.get("payload"))
	v.check("every frame is one flat 1.0.0 object with only the protocol's keys",
		shape.is_empty(), shape)

	# The topic is namespaced so a room code can never collide with another channel
	# on the same project ref, and it is normalised so that a code typed in lower
	# case lands in the SAME room as the one the host was issued. Two players in
	# two channels with one code is the failure this prevents.
	v.check("the channel topic is namespaced and case-normalised",
		PHX.TOPIC_PREFIX.begins_with("realtime:")
			and topic == PHX.TOPIC_PREFIX + "BCDF23"
			and PHX.topic_for(" bcdf23 ") == topic
			and PHX.topic_for(PHX.sanitise_code("bcdf-23")) == topic,
		topic)


# --- the socket URL -----------------------------------------------------------

static func _url(v: Verify) -> void:
	var url: String = PHX.socket_url("https://qalanxifxfukkeqdhfqh.supabase.co", "KEY")
	v.check("the socket URL swaps https for wss and appends the realtime path once",
		url == "wss://qalanxifxfukkeqdhfqh.supabase.co/realtime/v1/websocket?apikey=KEY&vsn=1.0.0",
		url)
	# A trailing slash on the project URL is the obvious way to get `//` in the
	# path, and it is the kind of thing that is copied out of a dashboard.
	v.check("a trailing slash on the project URL does not become a double slash",
		not PHX.socket_url("https://x.supabase.co/", "K").contains(".co//")
			and PHX.socket_url("https://x.supabase.co/", "K")
				== PHX.socket_url("https://x.supabase.co", "K"),
		PHX.socket_url("https://x.supabase.co/", "K"))
	# The self-hosted case, with a port. Only the scheme may change: rebuilding the
	# host from parts would drop the port. phoenix.gd:80-81.
	v.check("http becomes ws and the host and port survive untouched",
		PHX.socket_url("http://localhost:54321", "K")
			== "ws://localhost:54321/realtime/v1/websocket?apikey=K&vsn=1.0.0",
		PHX.socket_url("http://localhost:54321", "K"))

	# The key rides in the query string because a browser's WebSocket constructor
	# cannot set headers. A raw `+` in a query string decodes to a space, so an
	# unescaped key is an Unauthorized close that looks like a bad key.
	var enc: String = PHX.socket_url("https://x.supabase.co", "sb_publishable_a+b/c=")
	v.check("the api key is percent-encoded into the query string",
		enc.contains("apikey=sb_publishable_a%2Bb%2Fc%3D")
			and not enc.contains("a+b/c"),
		enc)

	# THE PIN. The server's own default is 1.0.0 today; an unpinned default is a
	# silent breaking change waiting for a server upgrade, and 2.0.0 would arrive
	# as binary frames that _pump() drops on the floor. phoenix.gd:13-19.
	v.check("the protocol version is pinned to 1.0.0 in the URL",
		PHX.VSN == "1.0.0" and url.ends_with("&vsn=" + PHX.VSN),
		"VSN=%s url=%s" % [PHX.VSN, url])

	# ...and the constant the game actually ships with, through the same function.
	# The web export is served over https, and a browser refuses a `ws://` socket
	# from an https page as mixed content — with no error the game can catch and no
	# symptom on any desktop build, which is the worst possible shape for a defect
	# on a web-first target.
	var live: String = PHX.socket_url(Net.PROJECT_URL, Net.PUBLISHABLE_KEY)
	v.check("the shipped project URL yields a wss socket, not a blockable ws one",
		live.begins_with("wss://") and not live.contains("http"),
		live)


# --- decode(), the happy paths ------------------------------------------------

static func _reply(ref: String, status: String, reason: String) -> String:
	return JSON.stringify({"topic": "realtime:room:BCDF23", "event": "phx_reply",
		"ref": ref, "payload": {"status": status, "response": {"reason": reason}}})


static func _decode(v: Verify) -> void:
	# BOTH DIRECTIONS OF THE JOIN RULE, on the SAME frame. A phx_reply is a join
	# result only when its ref is the one we sent our phx_join with; every other
	# phx_reply is an ack. Without the ref test, the ack for a routine broadcast
	# (once `ack` is ever turned on) reads as a successful join, and the session
	# would report itself joined to a channel it never entered.
	var text := _reply("1", "ok", "")
	var mine := PHX.decode(text, "1")
	var theirs := PHX.decode(text, "9")
	v.check("a phx_reply is a JOIN reply only when its ref is the one we joined with",
		int(mine["kind"]) == PHX.KIND_JOIN_OK and int(theirs["kind"]) == PHX.KIND_REPLY,
		"ours=%d theirs=%d" % [mine["kind"], theirs["kind"]])

	# A rejected join carries a reason worth showing, and it has to survive
	# normalisation — realtime.gd classifies retryable against permanent on that
	# string alone, so losing it turns every rejection into an infinite retry.
	var err := PHX.decode(_reply("1", "error", "Unauthorized: nope"), "1")
	v.check("a rejected join is JOIN_ERROR and keeps the server's reason",
		int(err["kind"]) == PHX.KIND_JOIN_ERROR
			and String(err["reason"]) == "Unauthorized: nope",
		str(err))

	# The broadcast envelope, unwrapped. Callers want the inner event, which is why
	# it is hoisted here rather than at four call sites.
	var bc := PHX.decode(PHX.broadcast_frame("realtime:room:BCDF23", "5", "1", "snap",
		{"tick": 12}), "1")
	var payload: Dictionary = bc["payload"]
	v.check("a broadcast is unwrapped to the game's own event and payload",
		int(bc["kind"]) == PHX.KIND_BROADCAST and String(bc["event"]) == "snap"
			and int(payload.get("tick", 0)) == 12,
		str(bc))

	# The rest of the closed set. `system` is the one that carries a message, and
	# it is the only warning a player ever gets that our own tick rate tripped a
	# rate limit.
	var kinds := {
		"presence_state": PHX.KIND_PRESENCE_STATE,
		"presence_diff": PHX.KIND_PRESENCE_DIFF,
		"system": PHX.KIND_SYSTEM,
		"phx_close": PHX.KIND_CLOSE,
		"phx_error": PHX.KIND_ERROR,
	}
	var mis := ""
	for event: String in kinds.keys():
		var want: int = kinds[event]
		var d := PHX.decode(JSON.stringify({"topic": "t", "event": event, "ref": "2",
			"payload": {"message": "Too many messages per second"}}), "1")
		if int(d["kind"]) != want:
			mis += "%s->%d(want %d) " % [event, d["kind"], want]
	v.check("every documented server event normalises to its own kind", mis.is_empty(), mis)
	var sysmsg := PHX.decode(JSON.stringify({"topic": "t", "event": "system",
		"payload": {"message": "Too many messages per second"}}), "1")
	v.check("a system event surfaces its message as the reason",
		String(sysmsg["reason"]) == "Too many messages per second", str(sysmsg))

	# An event nobody has taught this layer about is UNKNOWN — but it still comes
	# back fully normalised, so a caller logging it has something to log.
	var odd := PHX.decode(JSON.stringify({"topic": "realtime:room:BCDF23",
		"event": "phx_reply_v2", "ref": "3", "payload": {}}), "1")
	v.check("an unrecognised event is UNKNOWN without losing its topic, ref or name",
		int(odd["kind"]) == PHX.KIND_UNKNOWN and String(odd["event"]) == "phx_reply_v2"
			and String(odd["ref"]) == "3"
			and String(odd["topic"]) == "realtime:room:BCDF23",
		str(odd))

	# The kinds are a closed set and must stay distinct: two names sharing a value
	# would make realtime.gd's `match` take the wrong branch, silently.
	var vals := [PHX.KIND_UNKNOWN, PHX.KIND_JOIN_OK, PHX.KIND_JOIN_ERROR, PHX.KIND_REPLY,
		PHX.KIND_BROADCAST, PHX.KIND_PRESENCE_STATE, PHX.KIND_PRESENCE_DIFF,
		PHX.KIND_SYSTEM, PHX.KIND_CLOSE, PHX.KIND_ERROR]
	var uniq := {}
	for k: int in vals:
		uniq[k] = true
	v.check("the ten frame kinds are ten distinct values", uniq.size() == vals.size(),
		"%d distinct of %d" % [uniq.size(), vals.size()])


# --- decode(), hostile input --------------------------------------------------

## Everything arriving here crossed a network, so a truncated or hostile frame is
## an ARRIVAL SHAPE and not an incident: it must produce one defined failure kind
## rather than a crash or a half-read dictionary. phoenix.gd:161-176.
##
## THE ONE THING THESE CANNOT DO, said plainly. GDScript has no way to catch a
## runtime error, so when the sabotage makes `decode()` itself throw — deleting
## the `typeof(j.data) != TYPE_DICTIONARY` guard and feeding it `[1,2,3]`, or
## deleting either payload guard and feeding it `null` — this section unwinds and
## its assertions report NEITHER pass nor fail. CONTROLLED 2026-07-31, all three
## sabotages: 69 green becomes 65, 65 and 67 green with ZERO red. That silence is
## exactly what `verify.gd`'s ASSERTION_FLOOR exists to catch, which is why the
## floor must be raised by the real count added here and not rounded.
##
## Each of those three assertions therefore also carries a control that does NOT
## crash — a guard that admits the wrong thing rather than throwing — so none of
## them rests on the short-count signal alone: `KIND_UNKNOWN` swapped for
## `KIND_REPLY` in the initialiser reddens the junk sweep, and the inner-payload
## fallback returning `{"x": 1}` instead of `{}` reddens the payload check.
static func _hostile(v: Verify) -> void:
	var junk := ["", "{", "{\"event\":\"broadcast\"", "[1,2,3]", "[]", "null", "42",
		"\"a bare string\"", "not json at all", "{\"event\":null,\"payload\":null}",
		"\t", "{\"topic\":[],\"event\":{},\"payload\":7,\"ref\":[1]}"]
	var survived := ""
	for text: String in junk:
		var d := PHX.decode(text, "1")
		if int(d["kind"]) != PHX.KIND_UNKNOWN:
			survived += "'%s'->%d " % [text, d["kind"]]
		if typeof(d["payload"]) != TYPE_DICTIONARY:
			survived += "'%s' payload type %d " % [text, typeof(d["payload"])]
	v.check("truncated, non-object and non-JSON frames all land on one defined kind",
		survived.is_empty(), survived)

	# ONE FAILURE SHAPE. Every caller reads msg["kind"], msg["payload"], and often
	# msg["reason"] without checking they exist; a decode that returned a short
	# dictionary on the hostile path would crash at the read instead of at the
	# parse. So the key set and the types are asserted for hostile AND valid input
	# together — asserting only the hostile half would pass against a decode that
	# had stopped filling anything in.
	var want_types := {"kind": TYPE_INT, "event": TYPE_STRING, "payload": TYPE_DICTIONARY,
		"ref": TYPE_STRING, "topic": TYPE_STRING, "reason": TYPE_STRING}
	var bad := ""
	var samples: Array[String] = ["not json", _reply("1", "ok", ""),
		PHX.broadcast_frame("t", "1", "1", "e", {}),
		JSON.stringify({"event": "presence_diff", "payload": {}})]
	for text: String in samples:
		var d := PHX.decode(text, "1")
		if d.size() != want_types.size():
			bad += "%d keys; " % d.size()
		for k: String in want_types.keys():
			var want: int = want_types[k]
			if not d.has(k):
				bad += "missing %s; " % k
			elif typeof(d[k]) != want:
				bad += "%s is type %d want %d; " % [k, typeof(d[k]), want]
	v.check("decode always returns the same six keys with the same six types",
		bad.is_empty(), bad)

	# A payload that is present but is not an object — null, an array, a number —
	# must normalise to an empty dictionary rather than being handed on. This is
	# the case a malicious peer can produce at will, since the relay forwards a
	# broadcast payload without inspecting it.
	var nulled := PHX.decode(JSON.stringify({"topic": "t", "event": "broadcast",
		"ref": "1", "payload": null}), "1")
	var arrayed := PHX.decode(JSON.stringify({"topic": "t", "event": "broadcast",
		"ref": "1", "payload": [1, 2]}), "1")
	var inner := PHX.decode(JSON.stringify({"topic": "t", "event": "broadcast",
		"ref": "1", "payload": {"event": "snap", "payload": [1, 2]}}), "1")
	v.check("a null, array or non-object payload becomes an empty dictionary",
		(nulled["payload"] as Dictionary).is_empty()
			and (arrayed["payload"] as Dictionary).is_empty()
			and (inner["payload"] as Dictionary).is_empty()
			and int(inner["kind"]) == PHX.KIND_BROADCAST,
		"null=%s array=%s inner=%s" % [str(nulled), str(arrayed), str(inner)])

	# ...and a phx_reply whose `response` is not an object still classifies, rather
	# than throwing while reaching for `reason`.
	var resp := PHX.decode(JSON.stringify({"topic": "t", "event": "phx_reply", "ref": "1",
		"payload": {"status": "error", "response": [1, 2]}}), "1")
	v.check("a reply with a non-object response still classifies, with an empty reason",
		int(resp["kind"]) == PHX.KIND_JOIN_ERROR and String(resp["reason"]).is_empty(),
		str(resp))


# --- every number off the wire is a float -------------------------------------

## THE RULE THAT COSTS AN AFTERNOON IF IT IS FORGOTTEN, and it is asserted here so
## it cannot change under the replication layer without something going red.
##
## Godot's JSON parser has one number type. `{"id": 4}` is serialised as `4` and
## comes back as `4.0`, TYPE_FLOAT, on every platform.
##
## PHOENIX.GD:172-176 STATES THE CONSEQUENCE WRONG, and the correction is the
## reason this check is shaped the way it is. It says `payload["id"] == 4` is
## false. MEASURED: it is TRUE — GDScript compares int and float numerically, so
## `4.0 == 4` holds and an assertion built on that claim would fail against
## correct code. What actually bites is everything that is not `==`:
##
##   {4: zombie}.has(payload["id"])   -> FALSE. A float key never matches an int
##                                       key, so a per-id Dictionary — which is
##                                       how any entity table is written — misses
##                                       every lookup.
##   str(payload["id"])               -> "4.0", not "4". Node names, log lines and
##                                       any id concatenated into a string.
##   int(payload["id"])               -> 4. The cast at the boundary, which
##                                       session.gd:271 already does for the seed.
static func _numbers(v: Verify) -> void:
	var d := PHX.decode(PHX.broadcast_frame("t", "1", "1", "snap", {"id": 4}), "9")
	var payload: Dictionary = d["payload"]
	# `.get`, not `[]`, and the typeof test first: `and` short-circuits, so a
	# payload that arrived empty fails this assertion instead of throwing inside
	# it. An assertion that crashes on the sabotage it is named for reports
	# nothing at all.
	var id: Variant = payload.get("id")
	var by_id := {4: "the zombie"}
	v.check("a whole number off the wire is a float, and a float is not an int key",
		typeof(id) == TYPE_FLOAT and not by_id.has(id) and str(id) == "4.0"
			and int(id) == 4 and id == 4,
		"typeof=%d has_int_key=%s str='%s'" % [typeof(id), str(by_id.has(id)), str(id)])

	# It is not only the top level: an id nested inside an array of dictionaries —
	# which is exactly the shape of a zombie snapshot — is a float too.
	var snap := PHX.decode(PHX.broadcast_frame("t", "1", "1", "snap",
		{"z": [{"id": 7, "hp": 150}]}), "9")
	var body: Dictionary = snap["payload"]
	var nested: Variant = body.get("z")
	var first: Dictionary = {}
	if typeof(nested) == TYPE_ARRAY and (nested as Array).size() == 1 \
			and typeof((nested as Array)[0]) == TYPE_DICTIONARY:
		first = (nested as Array)[0]
	v.check("numbers nested inside an array of objects are floats as well",
		typeof(first.get("id")) == TYPE_FLOAT and typeof(first.get("hp")) == TYPE_FLOAT
			and int(first.get("id", 0)) == 7,
		str(first))

	# THE CONSUMER, driven end to end: the host's seed. session.gd:271 casts with
	# `int()` and says why; this is the assertion that the cast is both necessary
	# and sufficient across the range the seed can actually take. Rng.new_run()
	# draws `int(boot.randi())` (rng.gd:45-48), so the top of the range is 2^32-1.
	var lost := ""
	for s: int in [0, 1, 12345, 2147483647, 4294967295]:
		var frame := PHX.broadcast_frame("t", "1", "1", Net.EV_START, {"seed": s})
		var got: Dictionary = PHX.decode(frame, "9")["payload"]
		if int(got.get("seed", -1)) != s:
			lost += "%d->%s " % [s, str(got.get("seed"))]
		if typeof(got.get("seed")) != TYPE_FLOAT:
			lost += "%d arrived as type %d " % [s, typeof(got.get("seed"))]
	v.check("every seed Rng can produce survives the wire exactly once it is cast",
		lost.is_empty(), lost)

	# The other end of that bound, and the reason "cast it" is not the whole story
	# for anything else: a double holds 53 bits of mantissa, so an integer past
	# 2^53 comes back CHANGED and no cast can recover it. Seeds are safe; a 64-bit
	# hash or a snowflake id put on this wire would not be.
	var big := 9007199254740993
	var over: Dictionary = PHX.decode(
		PHX.broadcast_frame("t", "1", "1", "e", {"n": big}), "9")["payload"]
	var back: int = int(over.get("n", 0))
	v.check("an integer past 2^53 does NOT survive, which is why seeds are 32-bit",
		back != big and back == 9007199254740992,
		"%d came back %d" % [big, back])


# --- presence -----------------------------------------------------------------

static func _presence(v: Verify) -> void:
	# The wire shape is `{key: {metas: [...]}}` — an array per key, because Phoenix
	# allows one identity on several sockets. This game does not: one tab is one
	# player, so the first meta wins and the rest are dropped. `phx_ref` is
	# Phoenix's own bookkeeping and is stripped, or the lobby sees a "change" every
	# time the server re-stamps an unchanged player.
	var roster := PHX.presence_state({
		"A": {"metas": [{"phx_ref": "r1", "name": "Ann", "host": true},
			{"phx_ref": "r2", "name": "SECOND SOCKET"}]},
		"B": {"metas": [{"phx_ref": "r3", "name": "Bob", "host": false}]},
	})
	var a: Dictionary = roster.get("A", {})
	v.check("presence_state folds one meta per key and strips phx_ref",
		roster.size() == 2 and String(a.get("name", "")) == "Ann"
			and a.get("host") == true and not a.has("phx_ref")
			and String((roster.get("B", {}) as Dictionary).get("name", "")) == "Bob",
		str(roster))

	# ...and it FOLDS the frame rather than consuming it. `_first_meta` strips
	# `phx_ref` from its own copy; without the copy it strips it out of the caller's
	# payload, and the caller here is a decoded frame that realtime.gd may still be
	# reading. CONTROLLED 2026-07-31: with `meta.duplicate(true)` reduced to `meta`,
	# every other presence assertion in this file still passed — presence_diff's own
	# `roster.duplicate(true)` hides the aliasing from anything that looks only at
	# the output. This is the one that sees it.
	var wire := {"A": {"metas": [{"phx_ref": "r1", "name": "Ann"}]}}
	var folded := PHX.presence_state(wire)
	var folded_a: Dictionary = folded["A"]
	folded_a["name"] = "TAMPERED"
	var wire_metas: Array = (wire["A"] as Dictionary)["metas"]
	var wire_meta: Dictionary = wire_metas[0]
	v.check("presence_state copies out of the frame instead of consuming it",
		wire_meta.has("phx_ref") and String(wire_meta["name"]) == "Ann",
		str(wire))

	# Every malformed entry the relay could hand us. None may crash and none may
	# enter the roster as a half-player the lobby would then draw.
	var junk := PHX.presence_state({
		"good": {"metas": [{"phx_ref": "r", "name": "Ann"}]},
		"not_a_dict": "hello",
		"no_metas": {},
		"metas_not_array": {"metas": {"phx_ref": "r"}},
		"metas_empty": {"metas": []},
		"meta_not_dict": {"metas": ["hello"]},
	})
	v.check("a malformed presence entry is skipped rather than half-admitted",
		junk.size() == 1 and junk.has("good"), str(junk))

	# THE ORDER, AND IT IS THE WHOLE POINT. A reconnecting client produces a diff
	# holding the same key in BOTH halves. Leaves first means the survivor is the
	# new entry; joins first means a player who is actually present is deleted, and
	# that reads as a random disconnect. phoenix.gd:257-262.
	var base := PHX.presence_state({
		"A": {"metas": [{"phx_ref": "r1", "name": "Ann", "host": true}]},
		"B": {"metas": [{"phx_ref": "r3", "name": "Bob"}]},
	})
	var after := PHX.presence_diff(base, {
		"joins": {"A": {"metas": [{"phx_ref": "r9", "name": "Ann", "host": true}]},
			"C": {"metas": [{"phx_ref": "r8", "name": "Cal"}]}},
		"leaves": {"A": {"metas": [{"phx_ref": "r1", "name": "Ann", "host": true}]},
			"B": {"metas": [{"phx_ref": "r3", "name": "Bob"}]}},
	})
	v.check("a key in both halves of a diff survives, because leaves are applied first",
		after.has("A") and String((after.get("A", {}) as Dictionary).get("name", "")) == "Ann",
		"reconnecting player was deleted: %s" % str(after))
	# ...bounded at the other end by the same diff: a leave with no matching join
	# must actually remove, and a join with no leave must actually add. Without
	# these two the check above would pass against a presence_diff that had stopped
	# doing anything at all.
	v.check("a leave removes and a join adds",
		not after.has("B") and after.has("C") and after.size() == 2, str(after))

	# The roster handed in is not the roster handed back, one level down as well as
	# at the top. realtime.gd keeps `_roster` across diffs and hands copies out to
	# the lobby, so a shared reference would let a consumer's edit rewrite the
	# session's own state — and a shallow copy would share the metas, which is the
	# half that looks fine until somebody writes to one.
	var before := base.duplicate(true)
	var out := PHX.presence_diff(base, {"leaves": {"B": {}}})
	out["INJECTED"] = {}
	var out_a: Dictionary = out["A"]
	out_a["name"] = "TAMPERED"
	var base_a: Dictionary = base["A"]
	v.check("presence_diff deep-copies rather than aliasing the roster it was given",
		base.size() == before.size() and not base.has("INJECTED")
			and String(base_a["name"]) == "Ann" and not out.has("B"),
		"base=%s out=%s" % [str(base), str(out)])

	# Junk in either half is ignored rather than throwing — `joins` and `leaves` are
	# read straight off an untrusted frame.
	var unharmed := PHX.presence_diff(before, {"joins": 5, "leaves": "gone"})
	v.check("a diff with non-object halves leaves the roster alone",
		unharmed.size() == 2 and unharmed.has("A") and unharmed.has("B"), str(unharmed))


# --- the reconnect ladder and the heartbeat -----------------------------------

## realtime.gd's stateful half cannot be exercised without a socket, but the two
## decisions inside it that are pure — which errors are worth retrying, and how
## long to wait — can be, and both are the kind of thing that is edited without
## being re-argued.
static func _reconnect(v: Verify) -> void:
	# The protocol's documented "do not retry" classes. Retrying these re-fails
	# identically while the server backs off harder each time, so a permanent error
	# treated as transient is a slower way to fail. realtime.gd:291-301.
	var leaked := ""
	for reason: String in ["MalformedJWT: bad token", "JwtSignatureError",
			"Unauthorized: no", "TopicNameRequired", "TenantNotFound",
			"RealtimeDisabledForTenant", "RealtimeDisabledForConfiguration"]:
		if not REALTIME._permanent(reason):
			leaked += "%s " % reason
	v.check("every documented permanent error class is terminal", leaked.is_empty(), leaked)
	# The other end, and it is the half that matters more: an unknown reason must
	# fall through as RETRYABLE, or a transient blip becomes a dead session. A
	# classifier that returned true for everything would pass the check above.
	var stuck := ""
	for reason: String in ["UnknownErrorOnChannel", "", "socket closed (1006)",
			"RateLimitExceeded: slow down", "the channel closed"]:
		if REALTIME._permanent(reason):
			stuck += "'%s' " % reason
	v.check("an unknown or transient reason stays retryable", stuck.is_empty(), stuck)

	# The JS client's ladder, adopted rather than invented. Ascending is the
	# property that matters: a ladder that went flat or backwards would hammer a
	# server that is already telling us to slow down.
	var ladder: Array = REALTIME.BACKOFF
	var rising := ladder.size() > 0
	for i in range(1, ladder.size()):
		if float(ladder[i]) <= float(ladder[i - 1]):
			rising = false
	v.check("the reconnect backoff is a rising ladder starting at a whole second",
		rising and float(ladder[0]) >= 1.0, str(ladder))

	# THE 25 SECOND CLOSE. The server closes an idle socket at 25 s, so the beat
	# has to be comfortably inside it — this is the constant whose failure mode is
	# a session that dies on its own after half a minute and looks like the
	# player's internet. The margin is what absorbs a stalled frame or a
	# backgrounded tab, not a lost packet: WebSocket is TCP and nothing is dropped.
	v.check("the heartbeat period leaves real margin against the 25 s idle close",
		PHX.HEARTBEAT_PERIOD > 0.0 and PHX.HEARTBEAT_PERIOD < IDLE_CLOSE
			and IDLE_CLOSE - PHX.HEARTBEAT_PERIOD >= 5.0,
		"period=%.1f close=%.1f" % [PHX.HEARTBEAT_PERIOD, IDLE_CLOSE])

	# THE SEND CEILING MUST MAKE A DISCONNECT ARITHMETICALLY IMPOSSIBLE.
	#
	# Supabase's limits page defines an event as a message delivered to OR sent from
	# a client, so one publish into a room of N costs N events. With every client
	# publishing at its ceiling that is `MAX_PLAYERS^2 * SEND_BUDGET` events/second
	# against the free tier's 100 — and breaching it does not degrade, it
	# DISCONNECTS (`tenant_events`), which reconnects into a loop.
	#
	# Bounded at BOTH ends deliberately. The upper bound is the safety property. The
	# lower bound matters just as much: a budget dropped to 1 would satisfy "cannot
	# breach the limit" perfectly while shedding every snapshot in the game, and an
	# assertion that only checked the ceiling would call that a pass.
	const TIER_EVENTS := 100
	var cap: int = int(Net.MAX_PLAYERS)
	var worst: int = cap * cap * int(REALTIME.SEND_BUDGET)
	v.check("the send ceiling cannot breach the free tier's event limit",
		worst <= TIER_EVENTS,
		"%d players x %d events/publish x budget %d = %d events/s, limit %d" % [
			cap, cap, int(REALTIME.SEND_BUDGET), worst, TIER_EVENTS])
	v.check("the send ceiling still clears the periodic rates it has to carry",
		# A host publishes a snapshot AND its own body every second; anything under
		# that sheds during ordinary play rather than only when the game is busy.
		float(REALTIME.SEND_BUDGET) >= RUNTIME.SNAP_HZ + RUNTIME.ME_HZ
			and v.near(float(REALTIME.SEND_WINDOW), 1.0),
		"budget=%s snap=%.0f me=%.0f window=%s" % [
			REALTIME.SEND_BUDGET, RUNTIME.SNAP_HZ, RUNTIME.ME_HZ, REALTIME.SEND_WINDOW])


# --- the Net autoload's contract ----------------------------------------------

## The menu package and the replication layer are both written against the names
## below. A renamed method is a silent break — GDScript resolves an autoload call
## at runtime, so the first symptom is a button that does nothing.
static func _session(v: Verify) -> void:
	var sc: Script = Net.get_script()
	v.check("Net is an autoload node backed by scripts/net/session.gd",
		Net is Node and sc != null and sc.resource_path == "res://scripts/net/session.gd",
		str(sc))

	# Arity and return type, not merely existence: `join_room(code)` losing its
	# name argument, or `state()` starting to return a String, would both pass a
	# has_method() check and break every caller.
	var found := {}
	for m: Dictionary in sc.get_script_method_list():
		found[String(m["name"])] = m
	var api := {
		"host_room": [1, TYPE_NIL], "join_room": [2, TYPE_NIL],
		"leave_room": [0, TYPE_NIL], "start_run": [0, TYPE_NIL],
		"state": [0, TYPE_INT], "code": [0, TYPE_STRING],
		"is_host": [0, TYPE_BOOL], "is_online": [0, TYPE_BOOL],
		"players": [0, TYPE_ARRAY], "channel": [0, TYPE_OBJECT],
	}
	var broken := ""
	for name: String in api.keys():
		var want: Array = api[name]
		if not Net.has_method(name) or not found.has(name):
			broken += "%s(absent) " % name
			continue
		var m: Dictionary = found[name]
		var args: Array = m["args"]
		if args.size() != int(want[0]):
			broken += "%s(arity %d want %d) " % [name, args.size(), int(want[0])]
		var ret: Dictionary = m["return"]
		if int(ret["type"]) != int(want[1]):
			broken += "%s(returns %d want %d) " % [name, int(ret["type"]), int(want[1])]
	v.check("every method the menu calls exists with the right arity and return type",
		broken.is_empty(), broken)

	# Declared signals, read off the script rather than off the node — Node brings
	# a dozen of its own and `has_signal` would happily accept `renamed`.
	var declared := {}
	for s: Dictionary in sc.get_script_signal_list():
		declared[String(s["name"])] = true
	var absent := ""
	for name: String in ["state_changed", "roster_changed", "error", "run_started"]:
		if not declared.has(name) or not Net.has_signal(name):
			absent += "%s " % name
	v.check("the four session signals are declared on session.gd itself",
		absent.is_empty(), absent)

	# The state machine's own constants. Distinct values, because `_set_state`
	# compares and `state()` is matched on; six of them, because the menu has a
	# screen for each phase.
	var states := {"OFFLINE": Net.OFFLINE, "CLAIMING": Net.CLAIMING,
		"CHECKING": Net.CHECKING, "CONNECTING": Net.CONNECTING, "LOBBY": Net.LOBBY,
		"IN_RUN": Net.IN_RUN}
	var seen := {}
	for name: String in states.keys():
		seen[int(states[name])] = true
	v.check("the six session states are six distinct values",
		seen.size() == states.size(), str(states))
	# THE CAP IS NOT PINNED TO A VALUE, IT IS PINNED TO THE TWO ARGUMENTS THAT
	# DECIDE IT, and that is deliberate: this assertion was written against a
	# MAX_PLAYERS of 4 and the constant became 2 underneath it the same afternoon
	# (session.gd:31-55). Both numbers had a case; a check that snapshots either one
	# just records which agent wrote last.
	#
	# The ceiling is canon: BO1 co-op is four, and more than four is not the game
	# the project is porting. The floor is that a co-op room holds more than one
	# player.
	var cap := int(Net.MAX_PLAYERS)
	v.check("the lobby holds more than one player and never more than BO1's four",
		cap >= 2 and cap <= 4, "MAX_PLAYERS=%d" % cap)
	# ...and the real constraint underneath it, as arithmetic. Supabase counts an
	# "event" as a message delivered to OR sent from a client, so one broadcast into
	# a room of N costs N events — 1 send plus N-1 deliveries — and the free tier
	# cuts the project off at 100 events/second by DISCONNECTING sockets rather than
	# by degrading. With the host publishing and every client publishing at the same
	# rate, the room spends rate x N^2 events a second, so the cap decides how much
	# rate each stream may have: 25 Hz at two players, 11.1 Hz at three, 6.25 Hz at
	# four. (The shipped rates are asymmetric — 20 Hz snapshots, 12 Hz input — so
	# two players actually spend 64 of the 100.)
	#
	# 12 Hz is the floor because it is the slowest stream this project ships for
	# anything a player aims at (session_runtime.gd's MOVE_HZ). IF THE PROJECT EVER
	# MOVES TO THE PRO PLAN, change FREE_TIER_EVENTS below and re-argue the cap —
	# do not delete this check, because the failure it guards is a room that dies a
	# few seconds into the first round and looks like the relay being flaky.
	const FREE_TIER_EVENTS := 100.0
	const PLAYABLE_HZ := 12.0
	var budget: float = FREE_TIER_EVENTS / float(cap * cap)
	v.check("the cap leaves a playable tick rate inside the free tier's 100 events/s",
		budget >= PLAYABLE_HZ,
		"%d players leaves %.2f Hz per stream, under the %.0f Hz floor" % [
			cap, budget, PLAYABLE_HZ])

	# AT REST, and this is also the first half of the hermeticity guard: a suite
	# that had opened a session would fail here rather than quietly leaving a
	# socket in the tree.
	v.check("an untouched session is offline, with no code, no roster and no channel",
		int(Net.state()) == int(Net.OFFLINE) and Net.code().is_empty()
			and not Net.is_host() and not Net.is_online()
			and (Net.players() as Array).is_empty() and Net.channel() == null,
		"state=%d code='%s' players=%s channel=%s" % [Net.state(), Net.code(),
			str(Net.players()), str(Net.channel())])

	# `is_online()` is what the HUD's pip and the replication layer both read, so
	# it is driven across EVERY state rather than sampled at the one it starts in.
	# Bounded at both ends: the four states that must read offline and the two that
	# must read online. `_set_state` is the real setter — going through it means a
	# state added later without a rule here shows up as a failure.
	var was := int(Net.state())
	var wrong := ""
	var online := {int(Net.LOBBY): true, int(Net.IN_RUN): true}
	for s: int in [int(Net.OFFLINE), int(Net.CLAIMING), int(Net.CHECKING),
			int(Net.CONNECTING), int(Net.LOBBY), int(Net.IN_RUN)]:
		Net._set_state(s)
		if Net.is_online() != online.has(s):
			wrong += "state %d reads online=%s " % [s, str(Net.is_online())]
		if int(Net.state()) != s:
			wrong += "state %d did not stick " % s
	Net._set_state(was)
	v.check("a session is online in the lobby and in a run, and nowhere else",
		wrong.is_empty() and int(Net.state()) == was, wrong)

	# The lobby list. Host first, then join order by key, so the display does not
	# reshuffle every time presence re-stamps an unchanged player — a list that
	# jumped around would look like players joining and leaving. Driven through the
	# real `players()` against a hand-set roster, which is the only part of the
	# lobby that needs no socket.
	var roster_was: Dictionary = Net._roster
	var me_was: String = Net._me
	Net._me = "kkk"
	Net._roster = {
		"zzz": {"name": "Zoe", "host": false},
		"aaa": {"name": "Ann", "host": false},
		"kkk": {"name": "Me", "host": false},
		"mmm": {"name": "Host", "host": true},
	}
	var list: Array = Net.players()
	var order := ""
	for row: Dictionary in list:
		order += String(row["key"]) + " "
	var mine: Dictionary = list[2] if list.size() > 2 else {}
	v.check("the lobby lists the host first, then join order, and marks you",
		order == "mmm aaa kkk zzz " and bool((list[0] as Dictionary)["host"])
			and bool(mine.get("me", false)) and list.size() == 4,
		"order='%s' rows=%s" % [order, str(list)])
	# A peer whose meta never arrived still has to draw as somebody. An empty name
	# in the lobby reads as a broken client rather than as a slow one.
	Net._roster = {"nnn": {}}
	var bare: Dictionary = (Net.players() as Array)[0]
	v.check("a player with no meta yet still gets a name and is not the host",
		String(bare["name"]) == "Player" and bare["host"] == false
			and bare["me"] == false, str(bare))
	Net._roster = roster_was
	Net._me = me_was

	# The room heartbeat is a different clock from the socket's: it keeps the row
	# out of the reaper's window, which `public.claim_room()` implements as
	# `last_seen < now() - interval '2 hours'` (read off the live project
	# 2026-07-31). Well inside it, and not so tight that a lobby costs a request a
	# minute. JOIN_TIMEOUT must be finite for the same reason from the other side:
	# a host that quit without releasing leaves a code that answers nothing, and
	# the menu cannot wait on it forever.
	v.check("the room heartbeat sits well inside the two-hour reaper window",
		float(Net.HEARTBEAT_PERIOD) >= 60.0
			and float(Net.HEARTBEAT_PERIOD) <= REAP_WINDOW * 0.25,
		"period=%.0f reap=%.0f" % [Net.HEARTBEAT_PERIOD, REAP_WINDOW])
	v.check("the join wait is finite and generous against the measured 23 ms median",
		float(Net.JOIN_TIMEOUT) >= 5.0 and float(Net.JOIN_TIMEOUT) <= 60.0,
		"%.1f s" % Net.JOIN_TIMEOUT)


# --- the presence key and constraint 5 ----------------------------------------

## `Rng` is the single RNG authority and a cosmetic draw must never advance a
## gameplay stream, or opening a lobby would shift every seeded run. The presence
## key is 32 draws, so this is the largest single cosmetic draw in the project and
## the one most worth pinning.
##
## The stream states are captured and PUT BACK, so running this section changes
## nothing for the sections after it — `state` is exactly restorable, which is
## checked here by taking the same key twice.
static func _identity(v: Verify) -> void:
	var streams: Array[StringName] = [Rng.SPAWN, Rng.BOX, Rng.DROPS, Rng.ROUNDS,
		Rng.AI, Rng.VISUAL]
	var was: Array[int] = []
	for s: StringName in streams:
		was.append(Rng.stream(s).state)

	var key: String = Net._uuid()
	var moved := ""
	for i in streams.size():
		if Rng.stream(streams[i]).state != was[i] and streams[i] != Rng.VISUAL:
			moved += "%s " % streams[i]
	var visual_moved: bool = Rng.stream(Rng.VISUAL).state != was[streams.size() - 1]

	var hex := true
	for i in key.length():
		if not "0123456789abcdef".contains(key[i]):
			hex = false
	# Bounded at both ends: the gameplay streams must be untouched AND the visual
	# stream must have moved. Without the second half this would pass against a
	# `_uuid()` that had stopped drawing at all — which would hand every client in
	# the room the same presence key and collapse the roster to one player.
	v.check("the presence key is 32 hex digits drawn from VISUAL and no gameplay stream",
		key.length() == 32 and hex and moved.is_empty() and visual_moved,
		"key='%s' perturbed: %s visual_moved=%s" % [key, moved, str(visual_moved)])

	for i in streams.size():
		Rng.stream(streams[i]).state = was[i]
	var restored := ""
	for i in streams.size():
		if Rng.stream(streams[i]).state != was[i]:
			restored += "%s " % streams[i]
	v.check("this section put every rng stream back where it found it",
		restored.is_empty(), restored)


# --- the hermeticity guard ----------------------------------------------------

## LAST, AND IT IS AN ASSERTION ABOUT THIS FILE RATHER THAN ABOUT THE NET LAYER.
## `--verify` must never touch the network: a suite that does is a suite that goes
## red on a train and green in a coffee shop, and nobody trusts it after that. If
## a check above ever grows a `host_room()` or a `WebSocketPeer`, the session will
## be holding a channel by now and this fails.
static func _hermetic(v: Verify) -> void:
	v.check("nothing in this file opened a socket or left a session behind",
		Net.channel() == null and int(Net.state()) == int(Net.OFFLINE)
			and not Net.is_online() and (Net.players() as Array).is_empty(),
		"state=%d channel=%s players=%s" % [Net.state(), str(Net.channel()),
			str(Net.players())])
