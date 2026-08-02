extends Node

## Two real clients, one room, one live relay. The co-op gate.
##
## WHY THIS EXISTS, AND WHY THE SUITE COULD NOT DO IT. Everything under session.gd
## was asserted headlessly and the lobby was driven by hand in a browser, but until
## this landed NO TWO CLIENTS HAD EVER EXCHANGED A GAMEPLAY MESSAGE. The three files
## that carry a run — session_runtime.gd, replication.gd, remote_player.gd — had zero
## assertions, and an adversarial pass proved the hole by sabotaging seven constants
## across all three while `--verify` still printed "676 passed, 0 failed".
##
## It cannot be closed inside `--verify`, and the reason is structural rather than
## effort: what these files do is only true across two processes and a network. A
## single-process test can only build a fake channel and assert that the codec round
## trips through it, which is a copy of the thing under test — exactly what CLAUDE.md
## means by "a test that does not call what the game calls". So the gate is a second
## OS process, a real Supabase channel, and the actual game on both ends.
##
## WHAT IT PROVES, and each of these is a distinct wire path:
##   avatars_posed  a `me` crossed and was applied     (peer is visible at all)
##   peer_travel    successive `me`s were interpolated (peer moved, in metres)
##   puppets_spawned  the host's `snap`/`spawn` built bodies on the client
##   claims_applied   the client's `dmg` reached the host and it applied it
##   puppet_deaths    the host's `kill` came back and killed the client's copy
##   seed / round     both machines are simulating the same world
## tools/coop.ps1 asserts across the two result lines; this file only observes.
##
## HEADLESS IS FINE HERE and is not the trap CLAUDE.md warns about. That warning is
## `--shot`/`--frames` awaiting `frame_post_draw` with no rendering device; nothing
## below waits on a frame. The net layer was already proven headless against this
## same service (notes/net/2026-07-31-realtime-probe.md).
##
## IT SPENDS REAL EVENTS ON THE FREE TIER. Two clients for `BUDGET` seconds at the
## shipped rates is roughly 60 events/second — about 1/10000th of the monthly two
## million per run. Run it on a change to the net package, not in a loop.

## Frame cap. Headless runs uncapped, which would spin both processes at several
## hundred FPS — burning CPU, and worse, making `dt` so small that the send-rate
## accumulators in session_runtime.gd are exercised at a cadence no real client ever
## sees. 60 is what the game targets and what tools/frames.ps1 pins.
const FPS := 60

## How long the run lasts once both machines are in it. Long enough for round 1 to
## spawn its full complement (the director paces spawns) and for the client to walk
## into contact; short enough that a hung gate does not sit there for a minute.
const BUDGET := 45.0

## Give up waiting for the peer. The join path itself has session.gd's own 12 s
## timeout inside it; this is the outer one that also covers "the other process never
## started" and "the host never pressed go".
const DEADLINE := 75.0

## Let the world finish building before anything is asserted or driven.
const SETTLE := 1.0

const FIRE_PERIOD := 0.22
const TURN_PERIOD := 1.7

## Beyond this the client stops shooting and walks instead; the M1911's hitscan has
## no business claiming a body across the map.
const ENGAGE_RANGE := 18.0

## THE ADMISSION, and it is reported in the result rather than hidden. If the client
## has still not landed a hit by here, it is teleported into contact. Walking is the
## honest path and is tried first, but the client's pathing is a straight line and
## the map has walls — a gate that fails because a bot got stuck on a doorframe would
## teach us nothing about the network, which is the thing under test. `rescued` in
## the result says whether this fired, so a run that needed it cannot read as one
## that did not.
const RESCUE_AT := 26.0
const RESCUE_DIST := 3.2

## THE HOST FORCES A ROUND CHANGE, because otherwise the round assertion is
## decoration. Both machines call `rounds.begin_run()` and both therefore sit on
## round 1 for the whole budget — so "the two simulations agree on the round" would
## pass against a client that never received a single `world` message, which is
## precisely the class of test CLAUDE.md calls a control failure. Bumping the host
## makes the client's round number reachable ONLY through `_apply_round`.
##
## Late, and after the shooting: `force_round` re-rolls the horde's health for the
## new round, and moving it earlier would starve the claim and kill assertions of a
## body the starting pistol can actually drop.
const ROUND_AT := 30.0
const ROUND_TO := 3

var _main: Node
var _role := ""
var _code := ""
var _t := 0.0
var _wall := 0.0
## BUDGET unless `--coop <role> ... <seconds>` overrode it. See `install`.
var _budget := BUDGET
var _running := false
var _done := false
var _seed := -1

## Peer motion, accumulated off the avatar nodes themselves rather than off the
## samples buffer that feeds them — the buffer is the input to interpolation and the
## node is its output, and only the second one is what a player would see.
var _peer_last := {}
var _peer_path := 0.0
var _peer_max := 0.0

var _round_max := 1
var _puppets_max := 0
var _shots := 0
var _rescued := false
var _bumped := false
var _fire_t := 0.0
var _turn_t := 0.0
var _held := ""


static func wanted() -> bool:
	return "--coop" in OS.get_cmdline_args()


## `--coop host [seconds]` / `--coop join <CODE> [seconds]`. Installed from main.gd
## below every headless flag, for the reason stated there: none of those can be
## online.
##
## The optional seconds override BUDGET. tools/coop.ps1 never passes it — the gate
## wants one fixed duration so its numbers are comparable run to run. It exists for
## driving one side BY HAND against the other: pairing the desktop build with the
## shipped web export needs a window long enough for a person to click through a
## lobby, and 45 seconds is not it.
static func install(main_node: Node) -> void:
	var args := OS.get_cmdline_args()
	var i := args.find("--coop")
	var role := args[i + 1] if i + 1 < args.size() else ""
	if role != "host" and role != "join":
		push_error("[coop] --coop needs 'host' or 'join <CODE>'")
		main_node.get_tree().quit(2)
		return
	var probe := new()
	probe.name = "CoopProbe"
	probe._main = main_node
	probe._role = role
	var secs_at := i + 2
	if role == "join":
		probe._code = args[i + 2] if i + 2 < args.size() else ""
		if probe._code.is_empty():
			push_error("[coop] --coop join needs a room code")
			main_node.get_tree().quit(2)
			return
		secs_at = i + 3
	if secs_at < args.size() and args[secs_at].is_valid_float():
		probe._budget = maxf(5.0, args[secs_at].to_float())
	main_node.add_child(probe)


func _ready() -> void:
	Engine.max_fps = FPS
	# Same reasoning as realtime.gd and session.gd: the probe outlives any pause the
	# game might enter, and a probe that stops ticking is a probe that never reports.
	process_mode = Node.PROCESS_MODE_ALWAYS
	Net.error.connect(_on_error)
	Net.roster_changed.connect(_on_roster)
	Net.run_started.connect(_on_run_started)
	if _role == "host":
		Net.state_changed.connect(_on_state)
		Net.host_room("HostBot")
	else:
		Net.join_room(_code, "JoinBot")
	_say("ROLE %s" % _role)


# --- lobby -------------------------------------------------------------------

func _on_state(_s: int) -> void:
	# `code()` is empty until the claim comes back, and the state that follows it is
	# the one that matters — printing on CLAIMING would emit an empty code.
	if _role == "host" and _code.is_empty() and not Net.code().is_empty():
		_code = Net.code()
		_say("CODE %s" % _code)


func _on_roster(players: Array) -> void:
	_say("ROSTER %d" % players.size())
	# The host starts the run the moment the room is full enough to be a co-op run.
	# menu.gd owns this gesture in the real game; here there is nobody to press it.
	if _role == "host" and not _running and players.size() >= 2:
		Net.start_run()
		_begin()


func _on_run_started(seed_value: int) -> void:
	_seed = seed_value
	_say("SEED %d" % seed_value)
	if _role == "join" and not _running:
		# Deferred so main.gd's own `_on_run_started` — connected first, in its
		# `_ready` — has latched the seed before `start_game()` spends it.
		_begin.call_deferred()


func _begin() -> void:
	if _running:
		return
	_running = true
	_t = 0.0
	_main.start_game()
	_say("BEGIN")


# --- the run -----------------------------------------------------------------

func _process(dt: float) -> void:
	if _done:
		return
	_wall += dt
	if not _running:
		# Scaled with the budget, because an overridden budget means a HUMAN is
		# driving the other end — clicking through a lobby in a browser takes longer
		# than the 75 s that is generous for a second process.
		if _wall > maxf(DEADLINE, _budget):
			_fail("timed out waiting for the peer (%.0fs)" % _wall)
		return

	_t += dt
	_observe(dt)
	if _t > SETTLE:
		_drive(dt)
	if _role == "host" and not _bumped and _t >= ROUND_AT:
		_bumped = true
		_main.rounds.force_round(ROUND_TO)
		_say("ROUND %d" % ROUND_TO)
	if _t >= _budget:
		_report()


## Everything the gate asserts on is sampled here, off the live tree.
func _observe(_dt: float) -> void:
	var session: Node = _main.get("_session")
	if session == null or not is_instance_valid(session):
		return
	_round_max = maxi(_round_max, Game.round_no)
	var stats: Dictionary = session.stats()
	_puppets_max = maxi(_puppets_max, int(stats["puppets_live"]))

	for child in session.get_children():
		if not String(child.name).begins_with("Remote_"):
			continue
		# An avatar is hidden until `_drive` has a pose for it, so an invisible one has
		# no position worth measuring — counting it would report a peer parked at the
		# origin as a peer that never moved.
		if not child.visible:
			continue
		var key := String(child.name)
		var at: Vector3 = child.global_position
		if not _peer_last.has(key):
			_peer_last[key] = {"prev": at, "first": at}
			continue
		var rec: Dictionary = _peer_last[key]
		var prev: Vector3 = rec["prev"]
		var first: Vector3 = rec["first"]
		_peer_path += prev.distance_to(at)
		_peer_max = maxf(_peer_max, first.distance_to(at))
		rec["prev"] = at


## A bot with two jobs: be somewhere the peer can watch it move, and — on the client
## — get into contact so the claim path is exercised. Everything goes through the
## real input actions and the real weapon FSM; nothing calls `_shoot` directly, so a
## break anywhere between an action and a bullet fails this gate too.
func _drive(dt: float) -> void:
	var player: Player = _main.player
	if player == null or not is_instance_valid(player):
		return
	# THE BOTS DO NOT DIE, and this is the difference between a gate and a coin flip.
	# What is under test is the wire, not whether a bot with a starting pistol can
	# hold a corner at round 3 — and it cannot: a dying client leaves STATE_PLAY,
	# main.gd stops driving `_session.tick`, and every counter downstream flatlines
	# into what looks exactly like a network fault. Topping HP up is the smallest
	# intervention that removes the whole class; the alternative was tuning ROUND_TO
	# down until the bots happened to survive, which is a threshold that rots the
	# first time the horde is rebalanced.
	player.hp = Game.max_health()
	var session: Node = _main.get("_session")
	var target: Node3D = _nearest_body(session, player)

	_turn_t += dt
	if target != null:
		# Facing the thing we are about to shoot. `rotation.y` and `_head.rotation.x`
		# are written the same way shot_setup.gd:554-567 writes them — the dev
		# harnesses are the one place outside player.gd allowed to pose the camera
		# chain, because there is no hand on a mouse.
		var to: Vector3 = target.global_position - player.global_position
		player.rotation.y = atan2(-to.x, -to.z)
		player._head.rotation.x = 0.0
	elif _turn_t >= TURN_PERIOD:
		_turn_t = 0.0
		# No target: wander, so the peer has something to interpolate. VISUAL, because
		# a bot's heading is cosmetic and must not move a gameplay stream (constraint 5).
		player.rotation.y = Rng.randf_range(Rng.VISUAL, -PI, PI)

	_walk(target == null or player.global_position.distance_to(target.global_position) > 2.6)

	if target == null:
		return
	var dist: float = player.global_position.distance_to(target.global_position)
	# BOTH ROLES SHOOT, and the host's half is not decoration. A host that only
	# stands there survives round 1 and is eaten alive the moment `force_round`
	# raises the horde — which took `Game.state` out of STATE_PLAY, stopped
	# `main._process` driving `_session.tick`, and silently froze every outbound
	# message on the host while this probe (PROCESS_MODE_ALWAYS) kept happily
	# sampling. The symptom was a `world_sig` pinned at round 1 next to a
	# `round_now` of 3, and it read exactly like a replication bug for two runs.
	if dist <= ENGAGE_RANGE:
		_fire_t += dt
		if _fire_t >= FIRE_PERIOD:
			_fire_t = 0.0
			_fire(player)
	if _role != "join":
		return
	# The last resort, announced in the result. See RESCUE_AT.
	if not _rescued and _t >= RESCUE_AT and int(_session_stat(session, "claims_pending")) == 0 \
			and int(_session_stat(session, "puppet_deaths")) == 0:
		_rescued = true
		var away: Vector3 = (player.global_position - target.global_position).normalized()
		if away.length() < 0.5:
			away = Vector3.FORWARD
		player.global_position = target.global_position + away * RESCUE_DIST
		_say("RESCUE")


## The nearest thing worth pointing at: a host's own zombie on the host, a puppet on
## the client. Both are read off the tree rather than off a dictionary, so a body
## that was booked and never built cannot be aimed at.
func _nearest_body(session: Node, player: Player) -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	var pool: Array = []
	if _role == "host":
		pool = _main.rounds.alive()
	elif session != null and is_instance_valid(session):
		for child in session.get_children():
			if child is Zombie and child.visible:
				pool.append(child)
	for body in pool:
		if not is_instance_valid(body) or not (body is Node3D):
			continue
		var z := body as Node3D
		var d: float = player.global_position.distance_to(z.global_position)
		if d < best_d:
			best_d = d
			best = z
	return best


func _walk(forward: bool) -> void:
	var want := "move_forward" if forward else ""
	if want == _held:
		return
	if not _held.is_empty():
		Input.action_release(_held)
	if not want.is_empty():
		Input.action_press(want)
	_held = want


## Through `parse_input_event`, not `action_press`. `player._unhandled_input` reads
## the fire button off an EVENT (player.gd:470) while movement reads the Input
## singleton's state (player.gd:536), so the two need different doors — and pressing
## the action would set a state nothing ever reads for a trigger.
func _fire(player: Player) -> void:
	var gun: Dictionary = player.current_gun()
	if int(gun.get("mag", 0)) <= 0:
		var r := InputEventAction.new()
		r.action = "reload"
		r.pressed = true
		Input.parse_input_event(r)
		return
	_shots += 1
	for down: bool in [true, false]:
		var ev := InputEventAction.new()
		ev.action = "fire"
		ev.pressed = down
		Input.parse_input_event(ev)


func _session_stat(session: Node, key: String) -> Variant:
	if session == null or not is_instance_valid(session):
		return 0
	var s: Dictionary = session.stats()
	return s.get(key, 0)


# --- reporting ---------------------------------------------------------------

func _report() -> void:
	if _done:
		return
	_done = true
	var session: Node = _main.get("_session")
	var stats: Dictionary = {}
	if session != null and is_instance_valid(session):
		stats = session.stats()
	var out := {
		"role": _role,
		"code": _code,
		"seed": _seed,
		"round": _round_max,
		"avatars": int(stats.get("avatars", 0)),
		"avatars_posed": int(stats.get("avatars_posed", 0)),
		"peer_path_m": snappedf(_peer_path, 0.01),
		"peer_max_m": snappedf(_peer_max, 0.01),
		"puppets_spawned": int(stats.get("puppets_spawned", 0)),
		"puppets_peak": _puppets_max,
		"puppet_deaths": int(stats.get("puppet_deaths", 0)),
		"claims_applied": int(stats.get("claims_applied", 0)),
		"claims_pending": int(stats.get("claims_pending", 0)),
		"world_applied": int(stats.get("world_applied", 0)),
		"world_round": int(stats.get("world_round", -1)),
		"world_sent": int(stats.get("world_sent", 0)),
		"world_sig": str(stats.get("world_sig", "")),
		"round_now": Game.round_no,
		"dropped_sends": int(stats.get("dropped_sends", -1)),
		"shots": _shots,
		"rescued": _rescued,
		"kills": Game.kills,
		"points": Game.points,
		# STILL PLAYING? Everything above is only evidence if the run was still
		# running. `main._process` returns before `_session.tick` on any state but
		# STATE_PLAY, so a client that died stops sending — and every downstream
		# count then flatlines at whatever it had reached, which reads as a network
		# fault rather than a corpse. tools/coop.ps1 asserts on this FIRST.
		"playing": Game.state == Game.STATE_PLAY,
	}
	_say("RESULT " + JSON.stringify(out))
	_quit(0)


func _on_error(message: String) -> void:
	_fail(message)


func _fail(why: String) -> void:
	if _done:
		return
	_done = true
	_say("ERROR " + why)
	_quit(3)


func _quit(code: int) -> void:
	if not _held.is_empty():
		Input.action_release(_held)
	Net.leave_room()
	# One frame for the leave frame to reach the socket before the process goes away.
	# `close_channel()` polls it out, but the quit still has to happen after the call.
	get_tree().create_timer(0.25, true, false, true).timeout.connect(
		func() -> void: get_tree().quit(code))


## One prefix, so tools/coop.ps1 can read two interleaved processes apart from
## Godot's own chatter without parsing anything it did not write.
func _say(line: String) -> void:
	print("COOP %s" % line)
