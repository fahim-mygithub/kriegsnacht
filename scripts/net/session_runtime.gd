extends Node3D

## Replication, for the length of one run. The node that turns a joined channel
## into other people you can see.
##
## THE SPLIT, continued from session.gd's header:
##   phoenix.gd         pure framing and parsing. No socket.
##   realtime.gd        one channel: connect, join, heartbeat, presence, reconnect.
##   session.gd         what a ROOM is: a code, a host, a roster, a state.
##   replication.gd     what a MESSAGE is: quantisation, packing, bounds, sampling.
##   session_runtime.gd this file. What a RUN is: bodies, and where they are.
## session.gd's header says in as many words that it "must not know what a zombie
## is", and replication.gd's says the same. This is the file that does — and it is
## deliberately the only one, because it is the only one that cannot be asserted
## without a scene tree.
##
## A Node3D and a child of main, at the origin, for round_director.gd's reason: the
## puppets it makes need a transform parent and `global_position` has to mean the
## same thing here as it does there. It is NOT an autoload — unlike the room, a run
## does not outlive `main.restart()`, and a node under main is destroyed by the
## reload along with every body it was driving, which is exactly right.
##
## ONE WRITER. Every remote avatar and every client-side zombie puppet is written
## from here and from nowhere else.
##
## THE TOPOLOGY IS SETTLED — notes/design/2026-07-31-coop-topology-decision.md.
## Each client simulates its own player; the host simulates every zombie. So the
## traffic is not symmetric:
##
##   HOST   --snap-->  everyone   20 Hz, every live zombie
##   HOST   --spawn--> everyone   on the snapshot tick, batched
##   HOST   --kill-->  everyone   on the snapshot tick, batched
##   HOST   --world--> everyone   only when it changes
##   any    --me-->    everyone   12 Hz, that client's own body
##   client --dmg-->   host       on the snapshot tick, batched
##
## THE RATES ARE MEASURED, NOT CHOSEN. notes/net/2026-07-31-realtime-probe.md put
## one-way delivery at a 23 ms median and the inter-arrival p95 at 79 ms with a
## 101 ms maximum, which is what buys `replication.gd`'s 100 ms interpolation
## delay. 20 Hz for the horde and 12 Hz for a body come from the co-op decision
## note's budget line.
##
## `me` AT 12 Hz AND NOT THE 20 replication.gd's HEADER SUGGESTS, and the reason is
## realtime.gd's SEND_BUDGET of 40 frames per second PER CLIENT. A host sending 20
## snapshots and 20 bodies is at the ceiling before it has sent one spawn, one kill
## or one world change, and realtime.gd answers a full budget by DROPPING — so at
## 20 Hz the messages that would be lost are exactly the ones that must not be.
##
## AND THE RATES BELOW STILL DO NOT FIT, WHICH IS RECORDED HERE RATHER THAN QUIETLY
## RETUNED, because the number is argued over in three documents and moving it is
## the design owner's call, not this file's. The arithmetic, measured:
##
##   `MAX_PLAYERS` is 2, not 4 (session.gd:31-55). Every budget written for this
##   package — the decision note's "20 + 3x12 = 56", replication.gd's header, and
##   the brief both packages were written against — costs a FOUR-player room the
##   project cannot have, and costs it in PUBLISHES. Supabase bills an EVENT, which
##   its limits page defines as a message delivered to *or* sent from a client, so
##   one broadcast into a room of N costs N events. The free tier cuts the project
##   off at 100 events/second by DISCONNECTING the sockets.
##
##   at rest       20 snap + 2 x 12 me            =  44 publishes/s ->  88 events/s
##   + one client claiming hits (dmg @ 20 Hz)     =  64            -> 128 events/s
##   + kill and world batches on every tick       = 104            -> 208 events/s
##
##   and against realtime.gd's own per-client ceiling of 40: the host is at 32/s
##   with nothing happening and 92/s during a round that is spawning, killing and
##   losing planks — so more than half of the host's frames are refused, and because
##   `tick()` sends the snapshot before the kill and the world change, the frames
##   refused are the one-shot events rather than the stream that supersedes itself.
##
## Nothing in the repo asserts any of this. The two things that would make it safe
## are a lower rate and the host's own body riding the snapshot instead of a second
## broadcast; both are protocol decisions and neither is made here.
##
## SINGLE-PLAYER NEVER BUILDS THIS NODE. main.gd constructs it only when
## `Net.is_online()` is true at `start_game()`, so offline there is no node, no
## tick, no signal connection and no allocation — not a guard that returns early,
## an absence.

## preload rather than the class name: a freshly added script is not in the class
## registry until the editor rescans, and a headless run has no editor.
const REMOTE := preload("res://scripts/entities/remote_player.gd")
const REPL := preload("res://scripts/net/replication.gd")

## SNAP_HZ + ME_HZ MUST STAY UNDER realtime.gd's SEND_BUDGET (24), because a host
## publishes both every second — a snapshot of the horde and its own body.
##
## These were 20 and 12. An adversarial pass measured the result at 88 events/second
## at rest and 208 busy, against a free tier that caps the whole project at 100 and
## enforces it by DISCONNECTING. Two compounding mistakes: every budget in the design
## counted PUBLISHES where Supabase counts EVENTS (a publish into a room of N costs N,
## because delivery counts too), and none of them counted the host's own `me` at all.
##
## 14 + 8 = 22 leaves 2 frames a second of headroom inside the ceiling, and the
## ceiling itself is sized so that even a runaway send path cannot breach the tier —
## see realtime.gd's SEND_BUDGET. checks/net.gd asserts both directions of that
## relationship, so lowering the budget without lowering these fails a named check.
##
## THIS IS THE BACKSTOP, NOT THE FIX. The cost still scales with what happens in the
## game, because `world`, `kill` and `spawn` are separate publishes; a round start or
## a Nuke spikes the rate exactly when the game is busiest. The real fix is folding
## those three into the periodic snapshot so a session costs SNAP_HZ + ME_HZ flat
## whatever is happening. Until then a busy host sheds snapshots at the ceiling,
## which the next snapshot supersedes, while the batched events re-queue.
const SNAP_HZ := 14.0
const ME_HZ := 8.0

## How many snapshots an id may be missing from before it is presumed dead without
## a `kill` record. The normal path is the kill event; this is the backstop for one
## that never arrived, and it is deliberately slower than one tick — a body that
## blinks out and back because a single snapshot was clipped would be worse than a
## corpse that lands 150 ms late.
const MISSING_LIMIT := 3


var _main
var _player: Player
var _chan: Node
var _host := false
var _me := ""

## presence key -> {"node": RemotePlayer, "samples": Array, "pitch": float,
##                  "downed": bool}
var _avatars := {}
## wire id -> {"node": Zombie, "samples": Array, "type": int, "missing": int}
var _puppets := {}
## HOST ONLY. wire id -> Zombie, so an inbound claim can find its body without
## walking the live list.
var _by_id := {}
var _next_id := 1
var _tick := 0

var _snap_accum := 0.0
var _me_accum := 0.0

## HOST ONLY, drained onto the snapshot tick. Batched rather than sent per event:
## a Nuke ends 24 bodies on one frame, and 24 messages would go straight through
## realtime.gd's budget and be dropped — turning the one event a player cannot
## tolerate losing into the one most likely to be lost.
var _pending_spawn: Array = []
var _pending_kill: Array = []
## CLIENT ONLY. Same bargain from the other end: replication.gd's `pack_claim`
## comment works out that an MP5 at 600 RPM is ten claims a second per player.
var _pending_claims: Array = []

## HOST ONLY. The last `world` message's contents, so an unchanged world is silent.
var _world_sig := ""

## Latched from `player.fired` and cleared on every send, so the bit on the wire
## means "fired since the last body message" rather than "was mid-recoil when the
## timer happened to expire".
var _fired := false

var _warned_claim := false
var _warned_flag := false


## Called by main.gd immediately after the run starts, and only when
## `Net.is_online()`.
func bind(main_node, player_node: Player) -> void:
	_main = main_node
	_player = player_node
	_host = Net.is_host()
	_chan = Net.channel()
	for p: Dictionary in Net.players():
		if bool(p.get("me", false)):
			_me = str(p.get("key", ""))
	if _chan != null and is_instance_valid(_chan):
		_chan.message.connect(_on_message)
	Net.roster_changed.connect(_on_roster)
	_player.fired.connect(_on_local_fired)
	# THE DETECTOR FOR A HUNK THAT IS NOT MINE. See `claim_hit()`.
	if not _host:
		_player.hit_confirmed.connect(_on_local_hit)
	_sync_roster(Net.players())


## Whether the round director may run on this machine. False on a co-op client,
## where the horde belongs to the host and a locally-spawned zombie would be a body
## nobody else can see. main.gd reads this; nothing else should.
func simulates_horde() -> bool:
	return _host


# --- the tick ----------------------------------------------------------------

## Driven from main.gd rather than from this node's own `_process`, for exactly
## round_director.gd's reason: the drive order in main lives where a reader can
## check it, and a node with its own `_process` hides its position in tree order.
##
## It is the LAST thing main drives and it draws from no `Rng` stream at all, so it
## cannot perturb the seeded-run contract the four systems above it depend on — see
## the comment over `main.gd::_process`.
func tick(dt: float) -> void:
	if _chan == null or not is_instance_valid(_chan):
		return

	_me_accum += dt
	if _me_accum >= 1.0 / ME_HZ:
		# Reset rather than subtract: a frame that ran long should send one message
		# and not a burst catching up, which is how a hitch becomes a rate limit.
		_me_accum = 0.0
		_send_me()

	_snap_accum += dt
	if _snap_accum >= 1.0 / SNAP_HZ:
		_snap_accum = 0.0
		if _host:
			# SPAWNS BEFORE THE SNAPSHOT AND KILLS AFTER IT, and the order is the
			# whole of what makes a client's lifecycle unambiguous. The channel is
			# one TCP socket, so delivery is in send order: a body's spawn record —
			# which carries the palette and the speed the snapshot has no room for —
			# always lands before the first pose that mentions it, and its kill
			# always lands after the last one.
			#
			# `_send_spawns()` IS NOT CALLED HERE, and that is the fix rather than an
			# omission. A body's spawn record is queued by `_send_snapshot` itself, on
			# the frame it first sees the body — so calling the drain first drained an
			# empty queue and the record went out one whole tick BEHIND the snapshot
			# that had already named the body. The client made the puppet from the
			# snapshot, `_apply_spawn` skipped an id it already had, and the palette,
			# the host's rolled speed and the barricade were silently discarded for
			# every zombie in the game. MEASURED: host pal 2, client pal 0; with the
			# same payloads replayed spawn-first, client pal 2. The drain therefore
			# lives inside `_send_snapshot`, between building the rows and sending
			# them, which is the only point at which the queue is both full and ahead.
			_send_snapshot()
			_send_kills()
			_send_world()
		else:
			_send_claims()

	_drive()


## Everything remote, moved to where it was `INTERP_DELAY` ago.
func _drive() -> void:
	var at := REPL.render_time(_now())
	for key: String in _avatars.keys():
		var rec: Dictionary = _avatars[key]
		var node = rec["node"]
		if not is_instance_valid(node):
			continue
		var s: Dictionary = REPL.sample_at(rec["samples"], at)
		if not bool(s.get("ok", false)):
			continue
		# Shown on the frame it first has a pose, exactly as `_spawn_puppet` hides a
		# body until one arrives — and it was the one half of that rule this file did
		# not apply. `_sync_roster` builds an avatar off the presence diff, which is
		# a different server-side path from the broadcast that carries a position, so
		# between the two a teammate stood at the world origin with a lit torch. The
		# origin is tile (0,0), which is solid wall, and the torch is UNSHADOWED
		# (remote_player.gd:229) — so what a joining player actually produced was a
		# cone of light leaking out of the corner of the map.
		node.visible = true
		# `y` is zero for a player and not on the wire at all: replication.gd packs
		# x and z only, because this map is flat and a body's height is a constant.
		node.apply(Vector3(float(s["x"]), 0.0, float(s["z"])), float(s["yaw"]),
			float(rec["pitch"]), float(s["speed"]), bool(rec["downed"]))
		rec["samples"] = REPL.trim(rec["samples"], at)

	for id: int in _puppets.keys():
		var rec: Dictionary = _puppets[id]
		var z: Zombie = rec["node"]
		if not is_instance_valid(z):
			_puppets.erase(id)
			continue
		var s: Dictionary = REPL.sample_at(rec["samples"], at)
		if not bool(s.get("ok", false)):
			continue
		z.visible = true
		z.set_remote_pose(
			Vector3(float(s["x"]), float(s["y"]), float(s["z"])),
			Vector2.from_angle(float(s["yaw"])))
		rec["samples"] = REPL.trim(rec["samples"], at)


## Seconds, on this machine's clock.
##
## LOCAL ARRIVAL TIME AND NOT THE HOST'S, which is a decision rather than an
## oversight. Stamping the sender's clock into the payload would need real clock
## synchronisation to be usable — an offset estimator, a drift term and a way to
## re-converge after a stall — to absorb jitter that a 100 ms buffer already
## absorbs. What it costs instead is that playback carries the arrival jitter,
## which against the probe's 63 ms median on a 50 ms target is under a fifth of a
## frame and invisible.
func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


# --- outbound: this machine's own body ---------------------------------------

func _on_local_fired(_muzzle: Vector3) -> void:
	_fired = true


## `me`, which the host sends too — it is a body like any other, and folding it
## into the snapshot instead would tie the rate a player's avatar moves at to the
## rate the horde does.
##
## `sprinting` is DERIVED from the speed rather than read off `Player._sprinting`,
## which is private: `SPEED * SPRINT_MULT` is 4.88 m/s against a walk of 3.15, so
## the midpoint between them separates the two states under every multiplier the
## perks apply. `firing` is the latch above. Neither has a consumer in the avatar
## yet — remote FX is item 3 of the design note's deferred list — and both are
## sent truthfully anyway because they are single bits inside a fixed-width record
## that is the same size with or without them, and because a hardcoded `false`
## reads as a working feature.
func _send_me() -> void:
	var cam := _player.camera()
	# Pitch off the CAMERA rather than the head node: it needs no accessor added to
	# player.gd, and it carries the recoil and the shake — so a teammate's torch
	# beam kicks when they fire, which is the only "that player is shooting" cue
	# this package ships.
	var fwd := -cam.global_transform.basis.z if cam != null else Vector3.FORWARD
	var v := _player.velocity
	var spd := Vector2(v.x, v.z).length()
	var was_firing := _fired
	_fired = false
	_chan.send(REPL.EV_ME, REPL.encode_me(_me,
		_player.global_position.x, _player.global_position.z,
		_player.global_rotation.y,
		asin(clampf(fwd.y, -1.0, 1.0)),
		was_firing, _player.is_downed,
		spd > (Player.SPEED + Player.SPEED * Player.SPRINT_MULT) * 0.5))


# --- outbound: the horde (host only) -----------------------------------------

## Every live zombie, at 20 Hz.
##
## Ids are assigned HERE and stored on the body as metadata rather than being
## `get_instance_id()`. Instance ids are 64 bits and JSON carries a double, so
## anything past 2^53 would arrive rounded — silently, and as a different zombie.
## replication.gd packs 14 bits and wraps, which a counter can live with and an
## engine handle cannot.
func _send_snapshot() -> void:
	var rows: Array = []
	var live: Array = _main.rounds.alive()
	for z: Zombie in live:
		if not is_instance_valid(z) or z.state == Zombie.State.DYING:
			continue
		var id: int = int(z.get_meta("net_id", -1))
		if id < 0:
			id = _next_id
			_next_id += 1
			z.set_meta("net_id", id)
			_by_id[id] = z
			# Connected on first sight rather than at spawn, because this file does
			# not make host zombies — the director does, and reaching into its
			# `spawn_one` to add a second connection would be a second writer of the
			# director's own wiring. `died` carries the two flags `Zombie` keeps
			# private, which is the whole reason the kill record can be exact.
			z.died.connect(_on_host_zombie_died)
			_pending_spawn.append({
				"id": id,
				"type": REPL.type_of(z.kind),
				"pal": z.pal,
				"window": _nearest_window(z.global_position),
				"speed": z.speed,
			})
		var f := z.facing()
		rows.append({
			"id": id,
			"x": z.global_position.x,
			"y": z.global_position.y,
			"z": z.global_position.z,
			# `_facing` is not derivable from two positions, which is why it is on
			# the wire at all: a body tearing planks faces the window while standing
			# perfectly still. Everything derived FROM it — the atlas row, the
			# mirror, which eye quads light — stays off, per the design note.
			"yaw": atan2(f.y, f.x),
			"state": z.state,
			"type": REPL.type_of(z.kind),
		})
	_tick += 1
	# THE ROWS ARE BUILT, SO THE SPAWN QUEUE IS NOW FULL — drain it here, one line
	# above the snapshot that names those bodies. See `tick()` for what calling it
	# a line too early cost.
	_send_spawns()
	_chan.send(REPL.EV_SNAP, REPL.encode_snap(_tick, rows))


## What a refused batch keeps, and why anything is kept at all.
##
## realtime.gd:105-107 says `send()` returns false when the frame was dropped and
## that a caller "should not ignore" that for a one-shot event. All three of the
## batched senders below did — they cleared the queue whether or not the frame went
## — and the three costs are not equal: a refused `dmg` batch is a client whose
## shots did full local damage on its own screen and none at all on the host, for
## ever. Nor is the next tick a second chance the old code was relying on:
## `_sent_in_window` resets on a whole-second boundary rather than a sliding window
## (realtime.gd:170-173), so a refusal means the rest of that second is refused too.
##
## The queue is capped at the codec's own batch ceiling and the OLDEST records are
## the ones dropped on overflow. That is the safe end: a kill old enough to fall off
## has already been covered by the `MISSING_LIMIT` backstop, whereas the newest
## records are the ones nothing else will ever describe.
static func _keep(queue: Array, cap: int) -> Array:
	return queue if queue.size() <= cap else queue.slice(queue.size() - cap)


func _send_spawns() -> void:
	if _pending_spawn.is_empty():
		return
	var batch := _pending_spawn.slice(0, REPL.MAX_SPAWNS)
	if not _chan.send(REPL.EV_SPAWN, REPL.encode_spawn(batch)):
		_pending_spawn = _keep(_pending_spawn, REPL.MAX_SPAWNS)
		return
	_pending_spawn = _pending_spawn.slice(batch.size())


func _send_kills() -> void:
	if _pending_kill.is_empty():
		return
	# The key attributes the whole batch and this file does not track who claimed
	# which body, so it sends "" — replication.gd:765-768 documents that as the
	# no-owner case, which is what a Nuke is. The consequence is that a client
	# cannot yet award ITSELF the kill points for a body it killed; points stay
	# per-client by design and the host is currently the only machine that pays
	# them. Named here rather than left to be discovered.
	var batch := _pending_kill.slice(0, REPL.MAX_KILLS)
	if not _chan.send(REPL.EV_KILL, REPL.encode_kill("", batch)):
		_pending_kill = _keep(_pending_kill, REPL.MAX_KILLS)
		return
	_pending_kill = _pending_kill.slice(batch.size())


## Every death on this machine, including the ones no client claimed.
##
## `_shove` is read back rather than reconstructed: it is the only thing in the
## collapse a client cannot derive (zombie.gd:1073-1096 — it decides which way the
## body topples and whether the death row is mirrored), and reconstructing it as
## "away from the player" would be wrong for every kill now that `_apply_hit`
## passes a real direction (player.gd:1044).
func _on_host_zombie_died(z: Zombie, headshot: bool, melee: bool) -> void:
	var id: int = int(z.get_meta("net_id", -1))
	if id < 0:
		return
	_by_id.erase(id)
	var dir := z.shove()
	var flat := Vector2(dir.x, dir.z)
	_pending_kill.append({
		"id": id,
		"headshot": headshot,
		"melee": melee,
		"cause": z.last_cause,
		"has_dir": flat.length_squared() > 1e-6,
		"dir": atan2(flat.y, flat.x),
	})


## Round, power, doors and boards — but only when one of them has moved.
##
## `_world_sig` is the change detector rather than a per-field diff because the
## message is one packet either way and four booleans that have to agree with four
## fields is four more things to get wrong.
func _send_world() -> void:
	var boards: Array = []
	var doors := 0
	var map: MapData = _main.map
	for i in map.window_boards.size():
		boards.append(map.window_boards[i])
	for i in map.door_open.size():
		if map.door_open[i] != 0:
			doors |= 1 << i
	var sig := "%d|%d|%d|%s" % [Game.round_no, 1 if Game.power_on else 0, doors,
		String(",").join(boards.map(func(n: int) -> String: return str(n)))]
	if sig == _world_sig:
		return
	_world_sig = sig
	_chan.send(REPL.EV_WORLD,
		REPL.encode_world(Game.round_no, Game.power_on, doors, boards))


## Which barricade a body belongs to, from where it is standing.
##
## Derived rather than threaded: `set_entering` takes a window index and
## deliberately records nothing (zombie.gd:600-601 says the field it used to keep
## "was read by nothing at all"), and re-adding it to carry one wire field would be
## state on every zombie in single-player for a message single-player never sends.
## A body is at its barricade on the frame it spawns, which is the only frame this
## is asked.
func _nearest_window(at: Vector3) -> int:
	var best := 0
	var best_d := INF
	for i in MapData.WINDOWS.size():
		var w: Dictionary = MapData.WINDOWS[i]
		var d := Vector2(float(w.ix) + 0.5 - at.x, float(w.iy) + 0.5 - at.z).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


# --- inbound -----------------------------------------------------------------

func _on_message(event: String, payload: Dictionary) -> void:
	match event:
		REPL.EV_ME:
			_apply_me(REPL.decode_me(payload))
		REPL.EV_SNAP:
			if not _host:
				_apply_snap(REPL.decode_snap(payload))
		REPL.EV_SPAWN:
			if not _host:
				_apply_spawn(REPL.decode_spawn(payload))
		REPL.EV_KILL:
			if not _host:
				_apply_kill(REPL.decode_kill(payload))
		REPL.EV_WORLD:
			if not _host:
				_apply_world(REPL.decode_world(payload))
		REPL.EV_DMG:
			if _host:
				_apply_dmg(REPL.decode_dmg(payload))


## One player's body. Everyone receives these, the host included — it needs remote
## positions for the same reason a client does, and one broadcast serves both.
func _apply_me(m: Dictionary) -> void:
	if not bool(m.get("ok", false)):
		return
	# The key on the wire is a PREFIX (replication.gd:918-944) and is resolved
	# against the roster, which refuses an ambiguous one rather than guessing —
	# guessing puts one player's movement on another player's avatar and the
	# symptom is indistinguishable from lag.
	var key := REPL.resolve_key(str(m.get("key", "")), _avatars.keys())
	if key.is_empty():
		# A body arriving ahead of the presence diff that announces it. Presence and
		# broadcast are different server-side paths and nothing orders them, so a
		# late joiner's first message can beat their own roster entry. Dropped
		# rather than guessed at: `_sync_roster` is one frame away and it is the
		# thing that knows the display name and the coat.
		return
	var rec: Dictionary = _avatars[key]
	# Pitch and the downed flag are not interpolable state and are not in
	# `sample_at`'s contract, so they are held at their latest value; the avatar
	# eases the beam itself.
	rec["pitch"] = float(m.get("pitch", 0.0))
	rec["downed"] = bool(m.get("downed", false))
	var samples: Array = rec["samples"]
	samples.append({
		"t": _now(), "x": float(m.get("x", 0.0)), "y": 0.0,
		"z": float(m.get("z", 0.0)), "yaw": float(m.get("yaw", 0.0)),
	})


## CLIENT ONLY. Where every body is, this tick.
func _apply_snap(s: Dictionary) -> void:
	if not bool(s.get("ok", false)):
		return
	var rows: Array = s.get("zombies", [])
	var seen := {}
	var t := _now()
	for row: Dictionary in rows:
		var id := int(row["id"])
		seen[id] = true
		if not _puppets.has(id):
			# A spawn record we never saw — a client that joined mid-round, or a
			# dropped frame. replication.gd:60-63 anticipates this and says the
			# fallback is the class nominal; here that means palette 0 and the
			# speed `_configure` rolls, which is within the +/-8% it rolls anyway.
			# The BODY still appears, which is the part that matters.
			_spawn_puppet(id, int(row["type"]), 0, -1.0)
		var rec: Dictionary = _puppets[id]
		rec["missing"] = 0
		if int(rec["type"]) != int(row["type"]):
			# A walker whose legs came off. `Zombie._become_crawler` rebuilds nine
			# things off `kind` and is not reachable from outside that file, so the
			# body is replaced — one frame of pop, at the least subtle moment in the
			# game to hide one, against nine ways to get the conversion half-done.
			_free_puppet(id)
			_spawn_puppet(id, int(row["type"]), 0, -1.0)
			rec = _puppets[id]
		var samples: Array = rec["samples"]
		samples.append({
			"t": t, "x": float(row["x"]), "y": float(row["y"]),
			"z": float(row["z"]), "yaw": float(row["yaw"]),
		})

	# The backstop, NOT the kill path. A body normally leaves through `_apply_kill`
	# with the death animation the host sent; this is for a kill record that never
	# arrived, and it frees the body silently rather than faking a death — a corpse
	# with no sound and no shove is a worse lie than a body that is simply gone.
	for id: int in _puppets.keys():
		if seen.has(id):
			continue
		var rec: Dictionary = _puppets[id]
		rec["missing"] = int(rec["missing"]) + 1
		if int(rec["missing"]) > MISSING_LIMIT:
			_free_puppet(id)


## CLIENT ONLY. A new body, with the two things the snapshot has no room for.
func _apply_spawn(s: Dictionary) -> void:
	if not bool(s.get("ok", false)):
		return
	for row: Dictionary in s.get("spawns", []):
		var id := int(row["id"])
		if _puppets.has(id):
			continue
		_spawn_puppet(id, int(row["type"]), int(row["pal"]), float(row["speed"]))
		var z: Zombie = (_puppets[id] as Dictionary)["node"]
		# Stood at its barricade on the frame it arrives rather than hidden until
		# the first snapshot, which is what the `window` field is for.
		var wi := int(row["window"])
		if wi >= 0 and wi < MapData.WINDOWS.size():
			var p: Vector2 = _main.map.window_stand_pos(wi)
			z.set_remote_pose(Vector3(p.x, 0.0, p.y), Vector2(0.0, 1.0))
			z.visible = true


## CLIENT ONLY. The host confirmed these bodies are dead.
func _apply_kill(k: Dictionary) -> void:
	if not bool(k.get("ok", false)):
		return
	for row: Dictionary in k.get("kills", []):
		var id := int(row["id"])
		if not _puppets.has(id):
			continue
		var rec: Dictionary = _puppets[id]
		var z: Zombie = rec["node"]
		# Dropped from the map BEFORE the death, so `_drive` never writes a pose
		# into a body that is running its own collapse — the corpse slide is
		# `_tick_death`'s and a second writer would fight it every frame.
		_puppets.erase(id)
		if not is_instance_valid(z):
			continue
		var dir := Vector3.ZERO
		if bool(row["has_dir"]):
			var a := float(row["dir"])
			dir = Vector3(cos(a), 0.0, sin(a))
		z.remote_die(bool(row["headshot"]), bool(row["melee"]), int(row["cause"]), dir)


## CLIENT ONLY. The round, the barricades and the doors.
##
## POWER IS CARRIED AND DELIBERATELY NOT APPLIED. Turning it on is a 2.13 s tween
## across eight fixtures owned by lighting.gd and driven by interaction_system.gd;
## setting `Game.power_on` from here would make this file a second writer of that
## state and would light the perks without the ceremony. It is on the wire because
## the codec's record has the bit either way and because the package that lands
## shared world interaction — item 2 of the design note's deferred list — will need
## it to already be there.
func _apply_world(w: Dictionary) -> void:
	if not bool(w.get("ok", false)):
		return
	var boards: PackedInt32Array = w.get("boards", PackedInt32Array())
	for i in mini(boards.size(), _main.map.window_boards.size()):
		if _main.map.window_boards[i] != boards[i]:
			_main.world.set_window_boards(i, boards[i])
	var doors := int(w.get("doors", 0))
	for i in _main.map.door_open.size():
		if (doors & (1 << i)) != 0 and _main.map.door_open[i] == 0:
			_main.world.open_door(i)
	_apply_round(int(w.get("round", 0)))


## The round number is the host's, because the round loop is.
##
## Written the way round_director.gd:123-144 writes it — the field, then the
## signal, then the ceremony — rather than by calling into the director, which on
## this machine is deliberately not running at all (`simulates_horde()`). Without
## this a client's HUD would sit on round 0 for the whole session, because the one
## thing that moves `Game.round_no` is the tick main.gd is suppressing.
##
## `is_dog_round()` is NOT on the wire and does not need to be: it is a pure
## function of `Game.next_dog_round`, which `main.gd::_apply_net_seed` re-derives
## from the host's seed before the run starts. That is the payoff for seeding
## properly, and if the two ever disagree the seeding is what is broken.
func _apply_round(n: int) -> void:
	if n <= 0 or n == Game.round_no:
		return
	Game.round_no = n
	var dog := Game.is_dog_round()
	Game.round_changed.emit(n, dog)
	Sfx.round_ceremony(n, dog)


# --- damage claims -----------------------------------------------------------

## CLIENT ONLY, and called from player.gd — see this package's report for the hunk.
##
## A client's shot resolves against the puppet locally for FEEDBACK (the blood, the
## hitmarker, the sound and the hit points, all of which stay in `_apply_hit`) and
## the DAMAGE travels as a claim, because the body belongs to the host. That is the
## design note's "one relay round trip between your shot and the zombie dying on
## your screen", and the reason it is acceptable is that the half a player feels is
## the half that stayed local.
##
## Coalesced onto the snapshot tick rather than sent per hit, for the arithmetic in
## replication.gd:685-693: an MP5 at 600 RPM is ten claims a second per player and
## four players doing that would trip the relay's per-channel limit on its own.
func claim_hit(z: Zombie, amount: float, headshot: bool) -> void:
	if _host or _chan == null or not is_instance_valid(_chan):
		return
	if not is_instance_valid(z):
		return
	var id: int = int(z.get_meta("net_id", -1))
	if id < 0:
		return
	_pending_claims.append({"id": id, "amount": amount, "headshot": headshot})


func _send_claims() -> void:
	if _pending_claims.is_empty():
		return
	# Kept on refusal, for `_keep`'s reason and more sharply than the other two: a
	# discarded claim is damage the player watched land — the blood, the hitmarker
	# and the hit points all fired locally off the same raycast — that the host was
	# never told about. There is no backstop for it and no second copy of it.
	var batch := _pending_claims.slice(0, REPL.MAX_CLAIMS)
	if not _chan.send(REPL.EV_DMG, REPL.encode_dmg(_me, batch)):
		_pending_claims = _keep(_pending_claims, REPL.MAX_CLAIMS)
		return
	_pending_claims = _pending_claims.slice(batch.size())


## HOST ONLY. A client says it hit a body; the host is the one that decides.
##
## THIS IS HALF A CONTRACT AND IT SAYS SO. `Game.remote_kill` does not exist yet —
## it is a two-line addition to game_state.gd reported as a hunk by this package —
## and without it the host would bank the points and the drop credit for every kill
## every other player makes. So the claim is REFUSED rather than mis-paid, loudly,
## once.
##
## The `in Game` test is zombie.gd:829-838's, and so is the reason for it: the
## Monkey Bomb was inert for a whole wave because its two halves were published in
## different places, `"lure_position" in Game` was false, and neither package's
## assertions said a word. A missing half must fail visibly at the seam.
##
## `hit_y` is RECONSTRUCTED from the headshot bit and not sent. `take_damage`
## applies the 1.5x itself (zombie.gd:919-923), so passing the head threshold
## reproduces the client's own arithmetic exactly. The cost is that a claimed shot
## can never take the legs off: the conversion needs `0 < hit_y < leg_threshold()`
## and a body shot arrives as zero. Named because it is a real gameplay difference
## between hosting and joining, not a rounding error.
func _apply_dmg(d: Dictionary) -> void:
	if not bool(d.get("ok", false)):
		return
	if not ("remote_kill" in Game):
		if not _warned_flag:
			_warned_flag = true
			push_error("[net] a client claimed a hit and the host refused it: "
				+ "Game.remote_kill is missing. Until the game_state.gd hunk in "
				+ "this package's report lands, nothing any client shoots can die.")
		return
	for row: Dictionary in d.get("claims", []):
		var id := int(row["id"])
		if not _by_id.has(id):
			continue
		var z: Zombie = _by_id[id]
		if not is_instance_valid(z) or z.state == Zombie.State.DYING:
			continue
		var hit_y := z.head_threshold() if bool(row["headshot"]) else 0.0
		# Bracketed exactly as powerup_manager.gd:104-108 brackets the Nuke: up for
		# one application and down on the other side of it, so a payout suppressed
		# here cannot leak into the next death.
		#
		# `Game.set()` rather than `Game.remote_kill =`. The autoload's type is
		# known to the analyser, so a plain assignment to a property game_state.gd
		# does not declare yet is a COMPILE error — and a compile error in a script
		# reachable from the main scene hangs Godot rather than reporting
		# (constraint 3). The dynamic form is late-bound; the `in Game` guard above
		# is what makes it safe rather than silent.
		Game.set("remote_kill", true)
		z.take_damage(float(row["amount"]), hit_y)
		Game.set("remote_kill", false)


## THE CHECK THAT FAILS UNTIL THE player.gd HUNK LANDS.
##
## `hit_confirmed` fires from `_apply_hit` and from `_knife`, and the hunk puts
## `claim_hit()` immediately before the first of them. So a client that registers a
## hit without ever having queued a claim is a client running an unpatched
## player.gd — which looks exactly like working co-op right up until nothing ever
## dies. A reported hunk that nothing detects is a hunk that gets dropped silently;
## ADS shipped with its camera half and not its weapon half exactly that way.
func _on_local_hit(_headshot: bool, _killed: bool) -> void:
	if _warned_claim or not _pending_claims.is_empty():
		return
	_warned_claim = true
	push_error("[net] this client registered a hit and has queued no damage claim. "
		+ "The player.gd hunk in this package's report has not landed, so nothing "
		+ "this client shoots will ever die.")


# --- avatars -----------------------------------------------------------------

func _on_roster(players: Array) -> void:
	_sync_roster(players)


## Builds an avatar for everyone who is not us and frees the ones who left.
##
## The COAT is the player's index in `Net.players()`, which session.gd:164-180
## sorts host-first and then by presence key — a total order every client computes
## from the same roster, so all four machines dress the same person the same way
## without a byte on the wire agreeing it.
func _sync_roster(players: Array) -> void:
	var live := {}
	var i := -1
	for p: Dictionary in players:
		i += 1
		var key := str(p.get("key", ""))
		if key.is_empty() or bool(p.get("me", false)):
			continue
		live[key] = true
		if _avatars.has(key):
			continue
		var fresh = REMOTE.new()
		fresh.name = "Remote_" + REPL.short_key(key)
		# Hidden until `_drive` has a pose for it — see the note there. Set before it
		# enters the tree so there is not even one frame of a teammate at the origin.
		fresh.visible = false
		add_child(fresh)
		fresh.setup(str(p.get("name", "Player")), i)
		_avatars[key] = {"node": fresh, "samples": [], "pitch": 0.0, "downed": false}
	for key: String in _avatars.keys():
		if live.has(key):
			continue
		var rec: Dictionary = _avatars[key]
		var node = rec["node"]
		if is_instance_valid(node):
			node.queue_free()
		_avatars.erase(key)


# --- puppets -----------------------------------------------------------------

## One host-owned zombie, rendered here and simulated nowhere.
##
## `target` IS LEFT NULL AND THAT IS THE MECHANISM. `Zombie._physics_process`
## (zombie.gd:729-741) runs `_tick_death`, `_tick_flash` and `_update_view` — the
## death clock, the damage tint and the atlas row, which is the whole of how a
## zombie LOOKS — and then returns at `if target == null` before the groan, the
## barricade, the vault, the steering, the attack test and `move_and_slide`.
## MEASURED, not assumed: a puppet driven through thirty physics ticks does not
## move a millimetre and its walk cycle keeps playing, while the same body with a
## target covers 0.54 m over the same thirty.
##
## It is built through `Zombie.create()` and not by hand, deliberately: that is the
## path the game uses, and a puppet assembled some other way is one whose height,
## collider, sprite set and eye meshes can drift from a real body's without
## anything noticing. The cost is three draws from `Rng.AI` per puppet — a gameplay
## stream, and legal here only because this function is unreachable offline.
##
## NOT ADDED TO THE `zombies` GROUP, and this one is load-bearing. The group is how
## `traps.gd:497` finds bodies to electrocute and how `player.gd::_knife` finds one
## to stab, and both would then kill a host-owned body LOCALLY — a corpse on one
## screen and a live zombie on every other. The hitscan does NOT use the group
## (`player.gd:894` masks layers 1|4), so shooting a puppet still works and still
## routes through the claim. The knife and the traps are inert against puppets
## until the claim path covers them, which is a missing feature; a client deleting
## the host's horde would be a desync, and a missing feature is the smaller of two.
func _spawn_puppet(id: int, type_code: int, pal: int, speed: float) -> void:
	var z := Zombie.create(REPL.kind_of(type_code), clampi(pal, 0, 2),
		maxi(1, Game.round_no), false)
	z.flow = null
	z.target = null
	if speed > 0.0:
		# The host's own rolled speed, so the walk cycle runs at the rate that body
		# is actually travelling — `_apply_anim` re-derives `speed_scale` from this
		# on the next bearing change, which on a moving body is within a few frames.
		z.speed = speed
	# Hidden until it has a pose. A body drawn at the origin for one interpolation
	# buffer is a zombie standing in the middle of the map for a tenth of a second.
	z.visible = false
	add_child(z)
	z.set_meta("net_id", id)
	_puppets[id] = {"node": z, "samples": [], "type": type_code, "missing": 0}


func _free_puppet(id: int) -> void:
	if not _puppets.has(id):
		return
	var rec: Dictionary = _puppets[id]
	var z: Zombie = rec["node"]
	if is_instance_valid(z):
		z.queue_free()
	_puppets.erase(id)
