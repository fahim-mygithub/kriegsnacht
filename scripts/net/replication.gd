extends RefCounted

## The snapshot wire format, and nothing else.
##
## Same split, same reason as scripts/net/phoenix.gd: everything here is static and
## pure — data in, data out, no socket, no scene tree, no `Zombie`, no `Player`. That
## is not tidiness. A replication layer fails intermittently and at a distance, and
## the only part of it that can be pinned down by an assertion is the part that has
## no connection in it. Quantisation, packing, bounds, versioning and interpolation
## are all decidable headlessly, so they live here; the node that owns a tick clock
## and a send budget is a layer above and must stay thin.
##
## WHAT CROSSES, AND WHAT DOES NOT.
##
## The topology is settled in notes/design/2026-07-31-coop-topology-decision.md: each
## client simulates its own player, the host simulates every zombie. So the wire
## carries exactly two continuous streams and four event streams:
##
##   snap   host -> everyone, 20 Hz   every live zombie
##   me     anyone -> everyone, 12 Hz that machine's own avatar
##   world  host -> everyone, on change
##   dmg    client -> host, on event  a damage CLAIM
##   kill   host -> everyone, on event
##   spawn  host -> everyone, on event
##
## `me` is a broadcast rather than a send to the host, and that is deliberate: the
## host needs remote positions to aim zombies at them and every client needs them to
## draw an avatar, and one broadcast serves both. Phoenix joins with `self:false`
## (phoenix.gd:101-110), so a sender never gets its own back.
##
## DELIBERATELY NOT ON THE WIRE, because every one of these is a pure function of
## something that is:
##
##   * The atlas row and mirror (`Zombie._view` / `_flip`). `_update_view`
##     (zombie.gd:567-580) picks them from the body's facing AND THE LOCAL CAMERA.
##     They are per-viewer by construction — the host's row is the wrong row for
##     everyone else — so sending them would be worse than wasteful, it would be
##     wrong. Facing is on the wire as `yaw`; the client runs `SpriteLib.view_for`
##     itself.
##   * `speed_scale`. `Zombie.anim_scale_for(speed)` (zombie.gd:487-488) is total in
##     `speed`, and `speed` is fixed at spawn (`_configure`, :374-408) and thereafter
##     only ever multiplied by `CRAWLER_SPEED` when the legs come off (:964-968).
##     So `speed` rides the `spawn` event once and the client re-derives the scale,
##     including across the crawler conversion, which the `type` field announces.
##     A client that missed the spawn (a reconnect) falls back to the class nominal
##     for its `type`, which is within the +/-8% `_configure` already rolls.
##   * The corpse clock. `_begin_collapse` (:1065-1098) sets `_death_timer` from
##     `SpriteLib.SPEC[kind].death / 9.0 + CORPSE_HOLD + CORPSE_FADE` — constants and
##     `kind`. The `kill` event starts it; nothing after that needs the network, and
##     a corpse in the snapshot would cost 10 bytes a tick for a body that is on a
##     rail. The shove direction is the one thing the client cannot derive, so it is
##     in the `kill` record.
##   * The plank colliders. `barricade.gd` builds them from `boards`, so `world`
##     carries the count and the geometry falls out.
##   * `pal`. Set once at spawn, never changes; it rides `spawn`.
##   * Health. A client never needs a zombie's hp — it renders a body and gets told
##     when it dies. Putting hp on the wire is how a client starts drawing health
##     bars nobody asked for and how the host stops being the authority.
##
## ENCODING: FIXED-WIDTH BASE64 RECORDS, AND HERE IS THE ARITHMETIC.
##
## Every record is a fixed number of 6-bit fields written most-significant first into
## the URL-safe base64 alphabet, then concatenated into ONE JSON string. Three things
## follow from "fixed", and they are the reason for the choice:
##
##   1. A truncated payload is detectable exactly — `length % stride != 0` — rather
##      than parsing into a half-read record. That is the failure this whole file is
##      written against.
##   2. A hostile payload is bounded before a single Dictionary is allocated, by
##      dividing the length. No decoder here can be made to allocate from a count
##      field it was handed.
##   3. There is one packing primitive and therefore one charset check, one overflow
##      check and one truncation check, instead of six.
##
## A zombie is 60 bits = 10 chars:
##     id 14 | x 13 | y 6 | z 13 | yaw 9 | state 3 | type 2
##   x,z:  0.01 m step over [-8.00, +73.91] m. The map is 42 x 34 m (MapData.MAPW /
##         MAPH) and every barricade pocket sits inside it, so this is the map plus
##         8 m of margin below zero and 32 m above — CLAMPED, not wrapped, because a
##         body pinned at the edge is a glitch and a body wrapped to the far corner
##         is a teleport.
##   y:    0.02 m step over [0.00, 1.26] m, which exists solely for the vault
##         (`barricade.VAULT_LIFT` is 0.62 m). A walking zombie is at 0 and a corpse
##         slides along the floor, so this field is zero for all but the one or two
##         bodies climbing through a window at any moment. Six bits is the price of
##         not making the client re-derive somebody else's vault curve.
##   yaw:  TAU/512 = 0.703 deg, WRAPPED. Half a step of round-trip error is 0.352
##         deg, which is a fortieth of the 45 deg bucket `SpriteLib.view_for` sorts
##         it into.
##   state/type: Zombie.State has five values and there are three kinds.
##
## A player is 48 bits = 8 chars:
##     x 13 | z 13 | yaw 9 | pitch 9 | firing 1 | downed 1 | sprinting 1 | spare 1
##   pitch: PI/512 = 0.352 deg over [-90, +90) deg, clamped. `Player.PITCH_LIMIT` is
##          85 deg (player.gd:82), so the ends are never reached in practice.
##
## MEASURED, not estimated. `payload_bytes()` stringifies the same payload the
## channel sends, and these are its real outputs for 4 players + 24 zombies —
## THOUGH FOUR PLAYERS IS NOT A ROOM THIS PROJECT CAN HAVE. `session.gd:31-55` pins
## `MAX_PLAYERS` at 2 and shows the arithmetic: Supabase counts an event as a
## message delivered to *or* sent from a client, so a broadcast into a room of N
## costs N events and four players is 2.4x over the free tier. The four-player
## figures below are kept because they are what was measured and because they bound
## the question from above; the room that ships is snap + 2 x me = 334 B, re-measured
## against this file rather than re-derived.
##
##   naive JSON, one object per entity, full floats and full field names   3057 B
##   naive JSON, floats snapped to 2 dp and keys shortened to 8 chars      1939 B
##   THIS CODEC: snap 264 B + 4 x me 37 B                                   412 B
##
##   ...which beats the probe's own measured 654 B for the same content by 37.0%
##   (notes/net/2026-07-31-realtime-probe.md), and at 20 Hz is 8.2 kB/s against
##   13.1 kB/s. The probe's 654 B is the figure to quote, and NOT either of the two
##   above: those are baselines this file generated to bracket the question, and a
##   codec measured against a strawman it wrote itself has proved nothing. The
##   probe's number is fatter than 412 B and leaner than 1939 B, which says its
##   generator was already using short keys and rounded floats — so 37.0% is the
##   honest win and 86.5% is not.
##
##   Where the 412 B goes: 240 B is zombie records (24 x 10) and 24 B is the snap
##   envelope; the four `me` messages are 148 B, of which 32 B is nothing but the
##   `"k"` field saying who is speaking. That last one is why KEY_CHARS exists.
##
## EVERY NUMBER OFF THE WIRE IS A FLOAT. Godot's JSON parser returns TYPE_FLOAT for
## whole numbers, so `payload["id"] == 4` is false where `int(payload["id"]) == 4` is
## true — documented at phoenix.gd:172-176 and it has already cost this project two
## assertions. Nothing in this file reads a payload field without going through
## `_num` or `_flag`, which type-check first and never crash on a Dictionary handed
## where an int was expected.
##
## VERSIONING. Every payload carries `v`. A decode of a payload whose `v` is a
## number but not `PROTOCOL` returns `why == "version"`, which is distinguishable
## from `"malformed"` — so a peer on an old build can be named in the lobby instead
## of quietly producing zombies at the wrong coordinates. `protocol_of()` reads the
## field on its own for exactly that.

## Bumped whenever a record layout, a quantisation constant or a field meaning
## changes. NOT when a message is added — an old client simply never sees the new
## event, and forcing a rebuild for that is how a version becomes a lie nobody
## bumps. Anything that would make an old client MISREAD a byte bumps this.
const PROTOCOL := 1

## Event names, as constants for the reason session.gd:64-66 gives: a typo in a
## string literal on one side of a network is invisible until someone plays co-op.
const EV_SNAP := "snap"
const EV_ME := "me"
const EV_WORLD := "world"
const EV_DMG := "dmg"
const EV_KILL := "kill"
const EV_SPAWN := "spawn"

## URL-safe base64. All 64 glyphs are legal inside a JSON string with no escaping,
## which is what keeps a packed record from silently growing when a `"` or a `\`
## lands in it.
##
## NOT phoenix.gd's ALPHABET, which is 28 glyphs chosen to be readable aloud over a
## voice call. These two must never be unified: one is a human channel and drops
## vowels so a code cannot spell a word, this one is a machine channel and wants
## every bit it can get.
const ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
const BITS_PER_CHAR := 6

# --- record layouts ----------------------------------------------------------

const ID_BITS := 14                ## 16384 ids before the counter wraps
const POS_BITS := 13
const Y_BITS := 6
const YAW_BITS := 9
const PITCH_BITS := 9
const STATE_BITS := 3
const TYPE_BITS := 2
const PAL_BITS := 2
const WINDOW_BITS := 4
const SPEED_BITS := 10
const DAMAGE_BITS := 15
const CAUSE_BITS := 2

const ZOMBIE_CHARS := 10           ## 14+13+6+13+9+3+2 = 60 bits
const PLAYER_CHARS := 8            ## 13+13+9+9+3+1 spare = 48 bits
const CLAIM_CHARS := 5             ## 14+15+1 = 30 bits
const KILL_CHARS := 5              ## 14+1+1+2+1+9+2 spare = 30 bits
const SPAWN_CHARS := 6             ## 14+2+2+4+10+4 spare = 36 bits

## Position origin and step. See the header for why the window is where it is and
## why out-of-range clamps rather than wraps.
const POS_MIN := -8.0
const POS_STEP := 0.01
const Y_MIN := 0.0
const Y_STEP := 0.02

## 0.25 damage per step, 0 .. 8191.75. The largest single hit the game can produce
## is a Pack-a-Punched Ray Gun body shot; Insta-Kill is NOT sent through this,
## because `Zombie.take_damage` raises the amount to 1e9 itself when the power-up is
## up (zombie.gd:920-921) and the host is the one holding that flag. A claim carries
## what the weapon did, and the headshot multiplier is likewise the host's — the
## flag travels, the 1.5x does not (zombie.gd:922-923).
const DAMAGE_STEP := 0.25

## Metres per second, 0 .. 10.23. The fastest body the game can roll is a hound at
## `SPEED_SPRINT * 1.55 * 1.08` = 5.78 m/s (game_state.gd:72, zombie.gd:385, :404),
## so this is a factor of 1.8 of headroom in a field that costs nothing to widen.
const SPEED_STEP := 0.01

## Ceilings, applied BEFORE anything is allocated. The concurrent zombie cap is 24
## (asserted in checks/curves.gd:116); 48 leaves room for a frame in which corpses
## have not yet been dropped from the host's list without letting a hostile payload
## ask for a million dictionaries. The others are sized the same way: 24 bodies can
## die on one Nuke, and a magazine dumped into a crowd inside one 50 ms tick is the
## worst honest claim batch.
const MAX_ZOMBIES := 48
const MAX_CLAIMS := 32
const MAX_KILLS := 32
const MAX_SPAWNS := 16
const MAX_WINDOWS := 32
const MAX_KEY_LEN := 64

## Wire codes for `Zombie.kind`. Ordered, and the order is load-bearing — it is the
## `type` field. Appending is safe; reordering is a protocol break.
const KINDS := ["zombie", "crawler", "hound"]

## Wire codes for `Zombie.State`, reproduced rather than preloaded: this file must
## not depend on zombie.gd, or the codec stops being testable without the game. The
## enum is append-only for its own reasons (zombie.gd:9-14), which is what makes
## mirroring it safe — and checks/net.gd should assert the two agree BY VALUE, so a
## renumber is caught here rather than by a zombie that attacks while it walks.
const ST_ENTERING := 0
const ST_CHASING := 1
const ST_ATTACKING := 2
const ST_DYING := 3
const ST_TEARING := 4

## Wire codes for `Zombie.Cause` (zombie.gd:163), mirrored for the same reason.
const CA_BULLET := 0
const CA_MELEE := 1
const CA_BLAST := 2
const CA_NUKE := 3

## How far behind the newest snapshot a remote entity is drawn.
##
## Not a preference. The probe measured inter-arrival p95 at 79 ms and max at 101 ms
## over a sustained run (notes/net/2026-07-31-realtime-probe.md), so a buffer shorter
## than 100 ms stalls at the p95 and one much longer buys latency for nothing. This
## is the single number that decides whether other people's avatars glide or stutter.
const INTERP_DELAY := 0.100

## Snapshots the buffer has to hold for `sample_at` to bracket at all times.
##
## WAS 3, AND 3 IS ONE MILLISECOND SHORT. Three snapshots at 20 Hz span exactly
## 0.100 s, and the probe's worst measured inter-arrival gap was 0.101 s — so the
## one outlier the buffer exists for is the one it would have missed, and every
## client would have clamped for a frame at the same instant. Four spans 0.150 s,
## which covers the max with 49 ms of margin at a cost of one Dictionary per entity.
## Found by an assertion comparing the constant against the probe's own figure
## rather than by reasoning about it; the reasoning had already been done and was
## wrong.
const BUFFER_MIN := 4

## How much of a 32-hex-character presence key travels on every `me`. The full key
## at 20 Hz for four players is 2.9 kB/s of pure identity, which is a third of the
## whole snapshot budget spent on saying who you are. Eight hex characters is 32
## bits; the chance that any two of four random keys share a prefix is about 1.4e-9,
## and `resolve_key` reports the collision rather than guessing if it ever happens.
const KEY_CHARS := 8


# --- base64 primitives -------------------------------------------------------

## ASCII -> value, 255 for "not in the alphabet". Built once and cached, because the
## alternative is `ALPHABET.find(ch)` — a 64-glyph scan, 240 times per snapshot,
## 20 times a second. A `const` cannot hold it: a computed PackedByteArray is not a
## constant expression, and that is one of the two hard parse errors in this project.
static var _dec_lut := PackedByteArray()

static func _lut() -> PackedByteArray:
	if _dec_lut.size() == 128:
		return _dec_lut
	var t := PackedByteArray()
	t.resize(128)
	t.fill(255)
	for i in ALPHABET.length():
		t[ALPHABET.unicode_at(i)] = i
	_dec_lut = t
	return _dec_lut


## `n` characters, most significant first. MSB-first so a record sorts the same way
## it reads, which matters only when a human is staring at a captured frame — which
## is exactly when it matters.
static func _to_chars(bits: int, n: int) -> String:
	var out := ""
	for i in n:
		out += ALPHABET[(bits >> (BITS_PER_CHAR * (n - 1 - i))) & 63]
	return out


## Reads `n` characters at `at`. Returns -1 for any glyph outside the alphabet, and
## -1 is unambiguous because `n` is never large enough for a legal value to be
## negative (10 chars = 60 bits, against a 63-bit positive range).
##
## The caller has already bounds-checked `at + n <= s.length()`. That check lives at
## the call site rather than here because the call sites all do it once for a whole
## blob rather than once per record.
static func _from_chars(s: String, at: int, n: int) -> int:
	var lut := _lut()
	var bits := 0
	for i in n:
		var c := s.unicode_at(at + i)
		if c < 0 or c > 127:
			return -1
		var v: int = lut[c]
		if v > 63:
			return -1
		bits = (bits << BITS_PER_CHAR) | v
	return bits


# --- quantisation ------------------------------------------------------------

## A magnitude. CLAMPED at both ends: a value off the end of the range is a body
## pressed against the edge of the world, which reads as a glitch, and the
## alternative — letting it wrap — reads as a teleport across the map. One of those
## is survivable.
static func _q(value: float, lo: float, step: float, bits: int) -> int:
	if not is_finite(value):
		# NaN and INF both survive arithmetic and both come out of a division nobody
		# guarded. Sending either would put a body at a coordinate the decoder cannot
		# reproduce, so it is pinned to the low end where it is at least visible.
		return 0
	return clampi(int(roundf((value - lo) / step)), 0, (1 << bits) - 1)


static func _dq(n: int, lo: float, step: float) -> float:
	return lo + float(n) * step


## An angle. WRAPPED, because that is what an angle is — and because the top bucket
## has to fold back onto zero or a body facing 359.9 degrees would quantise to a
## value the field cannot hold.
static func _qa(rad: float, bits: int) -> int:
	if not is_finite(rad):
		return 0
	var steps := 1 << bits
	return posmod(int(roundf(wrapf(rad, 0.0, TAU) / TAU * float(steps))), steps)


## Back to [-PI, PI), which is the range every consumer here wants: `lerp_angle` and
## `angle_difference` are both defined on it, and a facing handed to
## `SpriteLib.view_for` as a vector does not care either way.
static func _dqa(n: int, bits: int) -> float:
	return wrapf(float(n) / float(1 << bits) * TAU, -PI, PI)


# --- untrusted-payload readers -----------------------------------------------

## A number, or the fallback. This is the whole of the TYPE_FLOAT trap: a JSON `4`
## arrives as 4.0, a JSON `"4"` arrives as a String, and a hostile payload can put a
## Dictionary where an int belongs — `int(v)` on that last one is a runtime error,
## not a zero.
static func _num(v: Variant, fallback: float) -> float:
	var t := typeof(v)
	if t == TYPE_FLOAT or t == TYPE_INT:
		return float(v)
	return fallback


## A flag. Accepts a real bool and a 0/1 number, because a hand-written client or a
## future encoder is entitled to send either and neither is ambiguous.
static func _flag(v: Variant) -> bool:
	var t := typeof(v)
	if t == TYPE_BOOL:
		return bool(v)
	if t == TYPE_FLOAT or t == TYPE_INT:
		return float(v) != 0.0
	return false


## A string, or "". Not `str(v)` — that renders a Dictionary as text and would turn
## a malformed payload into a plausible-looking key.
static func _text(v: Variant, limit: int) -> String:
	if typeof(v) != TYPE_STRING:
		return ""
	var s: String = v
	if s.length() > limit:
		return ""
	return s


## The one failure shape, mirroring phoenix.gd::decode. Every decoder in this file
## returns a Dictionary with `ok` and `why`, and every caller can branch on `ok`
## alone — a half-read result is never produced.
static func _bad(why: String, extra: Dictionary) -> Dictionary:
	var out := {"ok": false, "why": why}
	out.merge(extra)
	return out


## Reads and validates the version stamp. Returns "" when the payload is ours,
## "version" when it is a different build's, "malformed" when it is not a payload.
static func _check_version(payload: Variant) -> String:
	if typeof(payload) != TYPE_DICTIONARY:
		return "malformed"
	var p: Dictionary = payload
	var v := int(_num(p.get("v"), -1.0))
	if v < 0:
		return "malformed"
	if v != PROTOCOL:
		return "version"
	return ""


## The protocol a payload claims, or 0 when it does not claim one. Exposed so the
## lobby can say "that player is on build 1 and you are on 2" instead of showing a
## peer who never moves.
static func protocol_of(payload: Variant) -> int:
	if typeof(payload) != TYPE_DICTIONARY:
		return 0
	var p: Dictionary = payload
	return maxi(0, int(_num(p.get("v"), 0.0)))


## The exact bytes the channel would put on the wire for this payload. Used by the
## budget assertions and by anyone re-measuring the figures in the header — a size
## computed any other way is a size that drifts away from what is really sent.
static func payload_bytes(payload: Variant) -> int:
	return JSON.stringify(payload).to_utf8_buffer().size()


# --- snap: host -> everyone, 20 Hz -------------------------------------------

## One live zombie, 10 characters.
##
## `id` WRAPS at 16384 rather than clamping, because the caller allocates ids from a
## counter and wrapping is what a counter does. A collision needs 16384 spawns
## between one body's spawn and its removal — about 546 rounds at the ancestor's
## count curve — which is past any run this game has seen. Clamping instead would
## make every id above the ceiling the same id, which is the collision, immediately.
static func pack_zombie(id: int, x: float, y: float, z: float, yaw: float,
		state: int, type_code: int) -> String:
	var bits := posmod(id, 1 << ID_BITS)
	bits = (bits << POS_BITS) | _q(x, POS_MIN, POS_STEP, POS_BITS)
	bits = (bits << Y_BITS) | _q(y, Y_MIN, Y_STEP, Y_BITS)
	bits = (bits << POS_BITS) | _q(z, POS_MIN, POS_STEP, POS_BITS)
	bits = (bits << YAW_BITS) | _qa(yaw, YAW_BITS)
	bits = (bits << STATE_BITS) | clampi(state, 0, (1 << STATE_BITS) - 1)
	bits = (bits << TYPE_BITS) | clampi(type_code, 0, (1 << TYPE_BITS) - 1)
	return _to_chars(bits, ZOMBIE_CHARS)


## The inverse. Empty on a glyph outside the alphabet, which is the only way this can
## fail once the caller has checked the stride.
static func unpack_zombie(blob: String, at: int) -> Dictionary:
	var bits := _from_chars(blob, at, ZOMBIE_CHARS)
	if bits < 0:
		return {}
	var type_code := bits & ((1 << TYPE_BITS) - 1)
	bits >>= TYPE_BITS
	var state := bits & ((1 << STATE_BITS) - 1)
	bits >>= STATE_BITS
	var yaw := bits & ((1 << YAW_BITS) - 1)
	bits >>= YAW_BITS
	var qz := bits & ((1 << POS_BITS) - 1)
	bits >>= POS_BITS
	var qy := bits & ((1 << Y_BITS) - 1)
	bits >>= Y_BITS
	var qx := bits & ((1 << POS_BITS) - 1)
	bits >>= POS_BITS
	return {
		"id": bits & ((1 << ID_BITS) - 1),
		"x": _dq(qx, POS_MIN, POS_STEP),
		"y": _dq(qy, Y_MIN, Y_STEP),
		"z": _dq(qz, POS_MIN, POS_STEP),
		"yaw": _dqa(yaw, YAW_BITS),
		"state": state,
		"type": type_code,
	}


## The payload around an already-built blob. Split from `encode_snap` so the host's
## hot path can append 24 records into one String and never build 24 Dictionaries to
## throw away — at 20 Hz that is 480 allocations a second saved for nothing.
## `tick` is floored at 0 to match `encode_world`'s round number, and because the
## decoder treats a negative tick as malformed — an encoder that could produce a
## payload its own decoder refuses is a round trip with a hole in it.
static func snap_payload(tick: int, blob: String) -> Dictionary:
	return {"v": PROTOCOL, "t": maxi(0, tick), "z": blob}


## `rows` is an Array of {id, x, y, z, yaw, state, type}. The convenient form, used
## by the assertions and by anything that already has the data in a Dictionary.
static func encode_snap(tick: int, rows: Array) -> Dictionary:
	var blob := ""
	for i in rows.size():
		if typeof(rows[i]) != TYPE_DICTIONARY:
			continue
		var r: Dictionary = rows[i]
		blob += pack_zombie(
			int(_num(r.get("id"), 0.0)),
			_num(r.get("x"), 0.0), _num(r.get("y"), 0.0), _num(r.get("z"), 0.0),
			_num(r.get("yaw"), 0.0),
			int(_num(r.get("state"), 0.0)), int(_num(r.get("type"), 0.0)))
	return snap_payload(tick, blob)


## Returns {ok, why, tick, zombies}. `zombies` is always an Array — empty on any
## failure — so a caller that ignores `ok` still cannot half-read a snapshot.
static func decode_snap(payload: Variant) -> Dictionary:
	var empty := {"tick": -1, "zombies": [] as Array[Dictionary]}
	var why := _check_version(payload)
	if not why.is_empty():
		return _bad(why, empty)
	var p: Dictionary = payload
	var raw: Variant = p.get("z")
	if typeof(raw) != TYPE_STRING:
		return _bad("malformed", empty)
	var blob: String = raw
	# The ceiling is checked BEFORE the stride and before a single Dictionary is
	# allocated, so an oversized payload is refused rather than parsed — and
	# "overflow" stays distinguishable from "truncated", which is the difference
	# between a hostile peer and a clipped frame.
	if blob.length() > MAX_ZOMBIES * ZOMBIE_CHARS:
		return _bad("overflow", empty)
	if blob.length() % ZOMBIE_CHARS != 0:
		return _bad("truncated", empty)
	var tick := int(_num(p.get("t"), -1.0))
	if tick < 0:
		return _bad("malformed", empty)

	var out: Array[Dictionary] = []
	var n := blob.length() / ZOMBIE_CHARS
	for i in n:
		var z := unpack_zombie(blob, i * ZOMBIE_CHARS)
		if z.is_empty():
			return _bad("charset", empty)
		out.append(z)
	return {"ok": true, "why": "", "tick": tick, "zombies": out}


# --- me: anyone -> everyone, 12 Hz -------------------------------------------
#
# 12 and not 20: session_runtime.gd:61-62 is the sender and its header has the
# arithmetic. The host sends one too — it is a body like any other — which no
# budget in this package's notes counted.

static func pack_player(x: float, z: float, yaw: float, pitch: float,
		firing: bool, downed: bool, sprinting: bool) -> String:
	var bits := _q(x, POS_MIN, POS_STEP, POS_BITS)
	bits = (bits << POS_BITS) | _q(z, POS_MIN, POS_STEP, POS_BITS)
	bits = (bits << YAW_BITS) | _qa(yaw, YAW_BITS)
	# Pitch is signed and never wraps — a head that rolled past vertical would be a
	# bug in the writer, not a wrap to reproduce — so it is a clamped magnitude over
	# [-PI/2, +PI/2) rather than an angle.
	bits = (bits << PITCH_BITS) | _q(pitch, -PI * 0.5, PI / float(1 << PITCH_BITS), PITCH_BITS)
	bits = (bits << 1) | (1 if firing else 0)
	bits = (bits << 1) | (1 if downed else 0)
	bits = (bits << 1) | (1 if sprinting else 0)
	# One spare bit, kept rather than spent, so the next flag does not change the
	# stride — a stride change is a protocol break and a spare bit is not.
	bits <<= 1
	return _to_chars(bits, PLAYER_CHARS)


static func unpack_player(blob: String, at: int) -> Dictionary:
	var bits := _from_chars(blob, at, PLAYER_CHARS)
	if bits < 0:
		return {}
	bits >>= 1
	var sprinting := (bits & 1) == 1
	bits >>= 1
	var downed := (bits & 1) == 1
	bits >>= 1
	var firing := (bits & 1) == 1
	bits >>= 1
	var qpitch := bits & ((1 << PITCH_BITS) - 1)
	bits >>= PITCH_BITS
	var qyaw := bits & ((1 << YAW_BITS) - 1)
	bits >>= YAW_BITS
	var qz := bits & ((1 << POS_BITS) - 1)
	bits >>= POS_BITS
	return {
		"x": _dq(bits & ((1 << POS_BITS) - 1), POS_MIN, POS_STEP),
		"z": _dq(qz, POS_MIN, POS_STEP),
		"yaw": _dqa(qyaw, YAW_BITS),
		"pitch": _dq(qpitch, -PI * 0.5, PI / float(1 << PITCH_BITS)),
		"firing": firing,
		"downed": downed,
		"sprinting": sprinting,
	}


## `key` is the sender's presence key, shortened. Phoenix broadcasts carry no sender
## identity of their own, so without this a client cannot tell which avatar moved.
static func encode_me(key: String, x: float, z: float, yaw: float, pitch: float,
		firing: bool, downed: bool, sprinting: bool) -> Dictionary:
	return {
		"v": PROTOCOL,
		"k": short_key(key),
		"p": pack_player(x, z, yaw, pitch, firing, downed, sprinting),
	}


## Returns {ok, why, key, x, z, yaw, pitch, firing, downed, sprinting}. `key` is the
## SHORT key; the consumer resolves it against the roster with `resolve_key`, which
## is where an unknown sender is rejected — the codec does not know what a roster is.
static func decode_me(payload: Variant) -> Dictionary:
	var empty := {
		"key": "", "x": 0.0, "z": 0.0, "yaw": 0.0, "pitch": 0.0,
		"firing": false, "downed": false, "sprinting": false,
	}
	var why := _check_version(payload)
	if not why.is_empty():
		return _bad(why, empty)
	var p: Dictionary = payload
	var key := _text(p.get("k"), MAX_KEY_LEN)
	if key.is_empty():
		return _bad("malformed", empty)
	var blob := _text(p.get("p"), PLAYER_CHARS)
	if blob.length() != PLAYER_CHARS:
		return _bad("truncated", empty)
	var body := unpack_player(blob, 0)
	if body.is_empty():
		return _bad("charset", empty)
	var out := {"ok": true, "why": "", "key": key}
	out.merge(body)
	return out


# --- world: host -> everyone, on change --------------------------------------

## Round number, power, doors and the barricades.
##
## `doors` is a bitfield over `MapData.DOORS` — four of them today — and `boards` is
## one character per window carrying `MapData.window_boards`. The board counts are
## here rather than in the snapshot for the same reason the doors are: they change on
## an event, not on a tick, and a barricade that a client renders with all six planks
## while zombies walk through it is the visible half of the bug. The plank COLLIDERS
## are not sent; `barricade.gd` rebuilds them from the count.
##
## No packing beyond the board string: this message fires a handful of times a round
## and legibility in a captured frame is worth more than the twenty bytes.
static func encode_world(round_no: int, power_on: bool, door_bits: int,
		boards: Array) -> Dictionary:
	var b := ""
	for i in mini(boards.size(), MAX_WINDOWS):
		b += ALPHABET[clampi(int(_num(boards[i], 0.0)), 0, 63)]
	return {
		"v": PROTOCOL,
		"r": maxi(0, round_no),
		"pw": 1 if power_on else 0,
		"d": door_bits,
		"b": b,
	}


## Returns {ok, why, round, power, doors, boards}. `boards` is a PackedInt32Array so
## a consumer can index it against `MapData.WINDOWS` without a second conversion.
static func decode_world(payload: Variant) -> Dictionary:
	var empty := {"round": 0, "power": false, "doors": 0, "boards": PackedInt32Array()}
	var why := _check_version(payload)
	if not why.is_empty():
		return _bad(why, empty)
	var p: Dictionary = payload
	var round_no := int(_num(p.get("r"), -1.0))
	if round_no < 0:
		return _bad("malformed", empty)
	var raw: Variant = p.get("b")
	if typeof(raw) != TYPE_STRING:
		return _bad("malformed", empty)
	var b: String = raw
	if b.length() > MAX_WINDOWS:
		return _bad("overflow", empty)
	var boards := PackedInt32Array()
	for i in b.length():
		var n := _from_chars(b, i, 1)
		if n < 0:
			return _bad("charset", empty)
		boards.append(n)
	return {
		"ok": true, "why": "",
		"round": round_no,
		"power": _flag(p.get("pw")),
		"doors": int(_num(p.get("d"), 0.0)),
		"boards": boards,
	}


# --- dmg: client -> host, on event -------------------------------------------

## One claim, 5 characters.
##
## BATCHED, and that is not a micro-optimisation. An MP5 at 600 RPM lands ten hits a
## second; four players doing that is forty messages a second on top of the 56 the
## session already budgets (notes/design/2026-07-31-coop-topology-decision.md:118-125)
## and it is the one path in this design that can trip the relay's per-channel limit.
## A client coalescing one tick's hits into one message keeps the claim stream at
## most 4 x 20 Hz whatever the fire rate.
static func pack_claim(id: int, amount: float, headshot: bool) -> String:
	var bits := posmod(id, 1 << ID_BITS)
	bits = (bits << DAMAGE_BITS) | _q(amount, 0.0, DAMAGE_STEP, DAMAGE_BITS)
	bits = (bits << 1) | (1 if headshot else 0)
	return _to_chars(bits, CLAIM_CHARS)


## `claims` is an Array of {id, amount, headshot}. `key` is who is claiming — the
## host pays that client's points, and points stay per-client by design.
static func encode_dmg(key: String, claims: Array) -> Dictionary:
	var blob := ""
	for i in mini(claims.size(), MAX_CLAIMS):
		if typeof(claims[i]) != TYPE_DICTIONARY:
			continue
		var c: Dictionary = claims[i]
		blob += pack_claim(int(_num(c.get("id"), 0.0)), _num(c.get("amount"), 0.0),
			_flag(c.get("headshot")))
	return {"v": PROTOCOL, "k": short_key(key), "c": blob}


static func decode_dmg(payload: Variant) -> Dictionary:
	var empty := {"key": "", "claims": [] as Array[Dictionary]}
	var why := _check_version(payload)
	if not why.is_empty():
		return _bad(why, empty)
	var p: Dictionary = payload
	var key := _text(p.get("k"), MAX_KEY_LEN)
	if key.is_empty():
		return _bad("malformed", empty)
	var raw: Variant = p.get("c")
	if typeof(raw) != TYPE_STRING:
		return _bad("malformed", empty)
	var blob: String = raw
	if blob.length() > MAX_CLAIMS * CLAIM_CHARS:
		return _bad("overflow", empty)
	if blob.length() % CLAIM_CHARS != 0:
		return _bad("truncated", empty)
	var out: Array[Dictionary] = []
	for i in blob.length() / CLAIM_CHARS:
		var bits := _from_chars(blob, i * CLAIM_CHARS, CLAIM_CHARS)
		if bits < 0:
			return _bad("charset", empty)
		var head := (bits & 1) == 1
		bits >>= 1
		var amount := bits & ((1 << DAMAGE_BITS) - 1)
		bits >>= DAMAGE_BITS
		out.append({
			"id": bits & ((1 << ID_BITS) - 1),
			"amount": _dq(amount, 0.0, DAMAGE_STEP),
			"headshot": head,
		})
	return {"ok": true, "why": "", "key": key, "claims": out}


# --- kill: host -> everyone, on event ----------------------------------------

## One confirmed death, 5 characters.
##
## `dir` is the direction the body is pushed — `Zombie._die`'s `from_dir`, as an
## angle in XZ. It is on the wire because it is the one thing about a corpse a client
## CANNOT derive: everything else in `_die` and `_begin_collapse` is a function of
## the cause and the kind, but the shove decides which way the body topples and
## whether the death row is mirrored (zombie.gd:1090-1096). `has_dir` is a separate
## bit because zero is a legal angle and "no direction given" is a distinct case that
## `_die` handles by falling back to away-from-the-player.
static func pack_kill(id: int, headshot: bool, melee: bool, cause: int,
		has_dir: bool, dir: float) -> String:
	var bits := posmod(id, 1 << ID_BITS)
	bits = (bits << 1) | (1 if headshot else 0)
	bits = (bits << 1) | (1 if melee else 0)
	bits = (bits << CAUSE_BITS) | clampi(cause, 0, (1 << CAUSE_BITS) - 1)
	bits = (bits << 1) | (1 if has_dir else 0)
	bits = (bits << YAW_BITS) | _qa(dir, YAW_BITS)
	bits <<= 2   # two spare, same bargain as the player's one
	return _to_chars(bits, KILL_CHARS)


## `key` attributes the WHOLE batch, which is why a batch is grouped by claimer
## before it is sent. In practice a batch has one claimer or none: a magazine that
## drops three bodies is one player's, and a Nuke belongs to nobody and sends "".
static func encode_kill(key: String, kills: Array) -> Dictionary:
	var blob := ""
	for i in mini(kills.size(), MAX_KILLS):
		if typeof(kills[i]) != TYPE_DICTIONARY:
			continue
		var k: Dictionary = kills[i]
		blob += pack_kill(int(_num(k.get("id"), 0.0)), _flag(k.get("headshot")),
			_flag(k.get("melee")), int(_num(k.get("cause"), 0.0)),
			_flag(k.get("has_dir")), _num(k.get("dir"), 0.0))
	return {"v": PROTOCOL, "k": short_key(key), "x": blob}


static func decode_kill(payload: Variant) -> Dictionary:
	var empty := {"key": "", "kills": [] as Array[Dictionary]}
	var why := _check_version(payload)
	if not why.is_empty():
		return _bad(why, empty)
	var p: Dictionary = payload
	var raw: Variant = p.get("x")
	if typeof(raw) != TYPE_STRING:
		return _bad("malformed", empty)
	var blob: String = raw
	if blob.length() > MAX_KILLS * KILL_CHARS:
		return _bad("overflow", empty)
	if blob.length() % KILL_CHARS != 0:
		return _bad("truncated", empty)
	var out: Array[Dictionary] = []
	for i in blob.length() / KILL_CHARS:
		var bits := _from_chars(blob, i * KILL_CHARS, KILL_CHARS)
		if bits < 0:
			return _bad("charset", empty)
		bits >>= 2
		var qdir := bits & ((1 << YAW_BITS) - 1)
		bits >>= YAW_BITS
		var has_dir := (bits & 1) == 1
		bits >>= 1
		var cause := bits & ((1 << CAUSE_BITS) - 1)
		bits >>= CAUSE_BITS
		var melee := (bits & 1) == 1
		bits >>= 1
		var head := (bits & 1) == 1
		bits >>= 1
		out.append({
			"id": bits & ((1 << ID_BITS) - 1),
			"headshot": head,
			"melee": melee,
			"cause": cause,
			"has_dir": has_dir,
			"dir": _dqa(qdir, YAW_BITS),
		})
	# An empty key is legal here and means "nobody" — a Nuke, a trap, a bleedout —
	# so unlike `dmg` this does not reject it. That asymmetry is the point: a CLAIM
	# with no claimant is malformed; a DEATH with no killer is Tuesday.
	#
	# One consequence, recorded rather than left to be discovered: a key that fails
	# `_text` (wrong type, or longer than MAX_KEY_LEN) degrades to "" and the batch
	# is attributed to nobody. That is the fail-SAFE direction — nobody is paid —
	# and it is why it is a degradation rather than a rejection. The opposite choice
	# would let one malformed field discard a batch of real deaths, leaving corpses
	# standing on every client.
	return {"ok": true, "why": "", "key": _text(p.get("k"), MAX_KEY_LEN), "kills": out}


# --- spawn: host -> everyone, on event ---------------------------------------

## One new body, 6 characters. This is where the per-zombie CONSTANTS ride: `pal`
## and `speed` never change after this (bar the crawler conversion, which the
## snapshot's `type` field announces and which is a fixed multiply the client applies
## itself), so paying for them once is what keeps them out of the 20 Hz stream.
##
## `window` is the barricade index the body arrives at, so a client can put it in the
## right exterior pocket facing the right way on its first frame instead of sliding
## in from wherever the first snapshot lands.
static func pack_spawn(id: int, type_code: int, pal: int, window: int,
		speed: float) -> String:
	var bits := posmod(id, 1 << ID_BITS)
	bits = (bits << TYPE_BITS) | clampi(type_code, 0, (1 << TYPE_BITS) - 1)
	bits = (bits << PAL_BITS) | clampi(pal, 0, (1 << PAL_BITS) - 1)
	bits = (bits << WINDOW_BITS) | clampi(window, 0, (1 << WINDOW_BITS) - 1)
	bits = (bits << SPEED_BITS) | _q(speed, 0.0, SPEED_STEP, SPEED_BITS)
	bits <<= 4
	return _to_chars(bits, SPAWN_CHARS)


static func encode_spawn(spawns: Array) -> Dictionary:
	var blob := ""
	for i in mini(spawns.size(), MAX_SPAWNS):
		if typeof(spawns[i]) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = spawns[i]
		blob += pack_spawn(int(_num(s.get("id"), 0.0)), int(_num(s.get("type"), 0.0)),
			int(_num(s.get("pal"), 0.0)), int(_num(s.get("window"), 0.0)),
			_num(s.get("speed"), 0.0))
	return {"v": PROTOCOL, "s": blob}


static func decode_spawn(payload: Variant) -> Dictionary:
	var empty := {"spawns": [] as Array[Dictionary]}
	var why := _check_version(payload)
	if not why.is_empty():
		return _bad(why, empty)
	var p: Dictionary = payload
	var raw: Variant = p.get("s")
	if typeof(raw) != TYPE_STRING:
		return _bad("malformed", empty)
	var blob: String = raw
	if blob.length() > MAX_SPAWNS * SPAWN_CHARS:
		return _bad("overflow", empty)
	if blob.length() % SPAWN_CHARS != 0:
		return _bad("truncated", empty)
	var out: Array[Dictionary] = []
	for i in blob.length() / SPAWN_CHARS:
		var bits := _from_chars(blob, i * SPAWN_CHARS, SPAWN_CHARS)
		if bits < 0:
			return _bad("charset", empty)
		bits >>= 4
		var qspeed := bits & ((1 << SPEED_BITS) - 1)
		bits >>= SPEED_BITS
		var window := bits & ((1 << WINDOW_BITS) - 1)
		bits >>= WINDOW_BITS
		var pal := bits & ((1 << PAL_BITS) - 1)
		bits >>= PAL_BITS
		var type_code := bits & ((1 << TYPE_BITS) - 1)
		bits >>= TYPE_BITS
		out.append({
			"id": bits & ((1 << ID_BITS) - 1),
			"type": type_code,
			"pal": pal,
			"window": window,
			"speed": _dq(qspeed, 0.0, SPEED_STEP),
		})
	return {"ok": true, "why": "", "spawns": out}


# --- kinds ---------------------------------------------------------------------

static func type_of(kind: String) -> int:
	var i := KINDS.find(kind)
	# An unknown kind becomes a walker rather than refusing to encode. A body drawn
	# as the wrong sort of body is a bug somebody sees and reports; a body that never
	# arrives is a bug nobody can describe.
	return i if i >= 0 else 0


static func kind_of(type_code: int) -> String:
	if type_code < 0 or type_code >= KINDS.size():
		return KINDS[0]
	return KINDS[type_code]


# --- identity ------------------------------------------------------------------

## The prefix of a presence key that travels on every tick. See KEY_CHARS.
static func short_key(key: String) -> String:
	return key.substr(0, KEY_CHARS)


## Maps a short key back onto a full roster key. Returns "" when nothing matches AND
## when more than one thing does — an ambiguous prefix must not be guessed, because
## guessing puts one player's movement on another player's avatar and the symptom is
## indistinguishable from lag.
static func resolve_key(short: String, roster_keys: Array) -> String:
	if short.is_empty():
		return ""
	var found := ""
	for i in roster_keys.size():
		if typeof(roster_keys[i]) != TYPE_STRING:
			continue
		var k: String = roster_keys[i]
		if not k.begins_with(short):
			continue
		if not found.is_empty():
			return ""
		found = k
	return found


# --- interpolation buffer ------------------------------------------------------

## The render clock for remote entities: INTERP_DELAY behind the local clock, so
## there are normally two snapshots bracketing it.
static func render_time(now: float) -> float:
	return now - INTERP_DELAY


## The transform of one remote entity at `at`, from a series of timestamped samples.
##
## `samples` is an Array of {t, x, y, z, yaw} in ASCENDING t. Returns
## {ok, clamped, x, y, z, yaw, speed}.
##
## YAW GOES THE SHORT WAY, via `lerp_angle`. A remote player crossing PI holds two
## samples at +3.13 and -3.13 rad; a plain lerp walks the 359 degrees between them
## and the avatar spins on the spot. This is the single most likely visible defect in
## the whole client and it is one function call.
##
## IT DOES NOT EXTRAPOLATE. Past the newest sample it holds the newest one and says
## `clamped`. Extrapolating is the textbook answer and it is wrong here: the entities
## being extrapolated are zombies pathing around walls, and a body carried 100 ms
## along its last velocity walks into geometry and then snaps back out. A held pose
## for one dropped snapshot is a stutter; a body inside a wall is a bug report.
##
## `speed` comes out of the same bracketing pair as the position, and it is what the
## client feeds `Zombie.anim_scale_for` when it has no `spawn` record for that id.
static func sample_at(samples: Array, at: float) -> Dictionary:
	var miss := {
		"ok": false, "clamped": false,
		"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "speed": 0.0,
	}
	if samples.is_empty():
		return miss

	var lo := -1
	var hi := -1
	for i in samples.size():
		if typeof(samples[i]) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = samples[i]
		var t := _num(s.get("t"), NAN)
		if not is_finite(t):
			continue
		if t <= at:
			lo = i
		elif hi < 0:
			hi = i
	# Neither end found means every entry was malformed. A defined empty result, not
	# a crash and not the first element of an array that might not hold one.
	if lo < 0 and hi < 0:
		return miss
	if lo < 0:
		return _hold(samples[hi])
	if hi < 0:
		return _hold(samples[lo])

	var a: Dictionary = samples[lo]
	var b: Dictionary = samples[hi]
	var ta := _num(a.get("t"), 0.0)
	var tb := _num(b.get("t"), 0.0)
	var span := tb - ta
	# Two samples stamped at the same instant is a duplicate snapshot, which the
	# relay is entitled to deliver. Dividing by it would be an INF, so the later one
	# wins — the newest state is always the safer answer.
	if span <= 0.0:
		return _hold(b)
	# `lo` is the LAST sample at or before `at` and `hi` is the FIRST after it, so
	# `ta <= at < tb` holds by construction and this clamp can never fire. It is kept
	# for float error at the endpoints only — and it is recorded as unable to
	# discriminate, because a control that replaced it with a bare divide changed no
	# assertion at all. The no-extrapolation rule is the `hi < 0` branch above, not
	# this line, and anyone reading this for the rule should look there.
	var f := clampf((at - ta) / span, 0.0, 1.0)

	var ax := _num(a.get("x"), 0.0)
	var az := _num(a.get("z"), 0.0)
	var bx := _num(b.get("x"), 0.0)
	var bz := _num(b.get("z"), 0.0)
	return {
		"ok": true,
		"clamped": false,
		"x": lerpf(ax, bx, f),
		"y": lerpf(_num(a.get("y"), 0.0), _num(b.get("y"), 0.0), f),
		"z": lerpf(az, bz, f),
		"yaw": lerp_angle(_num(a.get("yaw"), 0.0), _num(b.get("yaw"), 0.0), f),
		"speed": Vector2(bx - ax, bz - az).length() / span,
	}


## One sample, held. `speed` is zero because a held pose has no measured motion —
## reporting the last known speed would keep a stalled body's legs walking on the
## spot, which is exactly the tell that the connection has stopped.
static func _hold(entry: Variant) -> Dictionary:
	if typeof(entry) != TYPE_DICTIONARY:
		return {"ok": false, "clamped": false,
			"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0, "speed": 0.0}
	var s: Dictionary = entry
	return {
		"ok": true, "clamped": true,
		"x": _num(s.get("x"), 0.0),
		"y": _num(s.get("y"), 0.0),
		"z": _num(s.get("z"), 0.0),
		"yaw": _num(s.get("yaw"), 0.0),
		"speed": 0.0,
	}


## Drops samples the buffer can no longer need, KEEPING THE LAST ONE AT OR BEFORE
## `before` — that one is the left half of the bracketing pair and dropping it is how
## an interpolation buffer starts clamping every frame while looking like it is full.
## Returns a new Array; the caller assigns it back.
static func trim(samples: Array, before: float) -> Array:
	var keep := 0
	for i in samples.size():
		if typeof(samples[i]) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = samples[i]
		if _num(s.get("t"), INF) <= before:
			keep = i
	if keep <= 0:
		return samples
	return samples.slice(keep)
