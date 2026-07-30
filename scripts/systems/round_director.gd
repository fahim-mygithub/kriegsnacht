extends Node3D

## The round loop and the horde: intermission, spawn cadence, the live list, the
## neighbour hand-off for separation, and what a death is worth.
##
## Split out of main.gd. Everything here keeps the order it had inside main's
## `_process`, because that order is the order the gameplay Rng streams are drawn
## in and a seeded run is only reproducible while it holds — see `tick()`.
##
## A Node3D rather than a plain Node so the zombies it makes have a transform
## parent. It sits at the origin under main, so `z.global_position` still means
## exactly what it did when main.gd was the parent.

## The Monkey Bomb's lure, for the flow-field goal. preload rather than the class
## name: a freshly added script is not in the class registry until the editor
## rescans, and a headless run has no editor.
const THROWABLES := preload("res://scripts/systems/throwables.gd")

## Flat chance of a drop on any death, on top of the points threshold.
const DROP_CHANCE := 0.03

var map: MapData
var world: WorldBuilder
var flow: FlowField
var player: Player
## powerup_manager.gd. Handed in at construction rather than reached for through
## main every death: a death is the only thing in this file that can make a drop,
## and it should not have to know where the drop layer is hung.
##
## Untyped for the same reason main.gd's `hud` and `lighting` are: the script is
## attached at runtime, so a `Node`-typed variable cannot see `spawn()`.
var powerups

var _round_timer := 0.0
var _spawn_timer := 0.0
var _to_spawn := 0
var _alive: Array[Zombie] = []
var _intermission := true


func bind(m: MapData, w: WorldBuilder, f: FlowField, p: Player, pu: Node3D) -> void:
	map = m
	world = w
	flow = f
	player = p
	powerups = pu


## Called by start_game(). The first round is a delay rather than an immediate
## wave, so the player has a moment on their feet before anything arrives.
func begin_run() -> void:
	_intermission = true
	_round_timer = Game.FIRST_ROUND_DELAY
	Game.round_no = 0


# --- the loop ----------------------------------------------------------------

## Driven from main.gd rather than from this node's own `_process`, and
## deliberately: the four systems draw from the gameplay streams in a fixed order
## and tree order is not a contract anyone reading this file can see. main.gd's
## drive order is that contract.
func tick(dt: float) -> void:
	# The flow field solves to the LURE when a Monkey Bomb is live, not to the
	# player. Without this only zombies with line of sight divert — `_goal_point`
	# is the direct-chase path — and everything pathing round a corner keeps
	# walking to you, which is most of the horde and the whole point of the
	# throwable. Returns the fallback untouched when nothing is thrown.
	flow.update(THROWABLES.flow_goal(player.grid_pos()))

	# Hand every zombie the current neighbour list for separation.
	var live: Array[Zombie] = []
	for z in _alive:
		if is_instance_valid(z):
			live.append(z)
	_alive = live
	for z in _alive:
		z.neighbours = _alive

	if _intermission:
		_round_timer -= dt
		if _round_timer <= 0.0:
			_begin_round()
	else:
		_spawn_timer -= dt
		if _to_spawn > 0 and _spawn_timer <= 0.0 and _alive.size() < Game.max_alive():
			spawn_one()
			_spawn_timer = Game.spawn_interval()
		if _to_spawn <= 0 and _alive.is_empty():
			_end_round()


## The live horde. Handed out as a plain Array because the debug console reads it
## and cannot see `Array[Zombie]`; it is the director's own array, not a copy, so
## a caller that intends to outlive a frame must duplicate it.
func alive() -> Array:
	return _alive


## What is still owed to the current round. Read by the soak print in main.gd and
## by the debug console; nothing acts on it.
func queued() -> int:
	return _to_spawn


func in_intermission() -> bool:
	return _intermission


## Jumps straight into round `n`. For the debug console.
##
## The horde already standing is deliberately left alone: killing it would run
## every one of them through `_on_zombie_died`, which pays points, rolls DROPS and
## can spawn power-ups — so "jump to round 30" would silently move three gameplay
## streams and hand the player a pile of drops on the way past.
func force_round(n: int) -> void:
	Game.round_no = maxi(0, n - 1)
	_to_spawn = 0
	_intermission = false
	_begin_round()


func _begin_round() -> void:
	_intermission = false
	Game.round_no += 1
	_to_spawn = Game.zombie_count()
	# html:2862 — `G.dropsThisRound=0` inside startRound. Without it the four-a-round
	# cap below is four a RUN, because nothing else clears the counter: reset_run()
	# only fires at boot and _grant_max_ammo() only at the end of a dog round. The
	# balance sim is what found it — its `drops` column read 4, 4, 4, 4 and then zero
	# for every remaining round of a twenty-round run, which is not a curve any
	# designer wrote.
	Game.begin_round_drops()
	# html:2863 is `G.spawnTimer = 0.4`, and the port had 0.0 — so the first
	# zombie of a round arrived on the frame the round began. Now it is the length
	# of the beat of silence, which is the ancestor's intent (a pause before the
	# wave) carried to the ceremony's own clock: nothing walks in over the toll.
	_spawn_timer = Sfx.ROUND_SILENCE
	# The card first, the toll second. Sfx cuts the ambient bed on this call, holds
	# ROUND_SILENCE seconds of nothing and only then plays the sting, so the
	# numeral is already on screen through the beat and the most recognisable cue
	# in the game lands into silence instead of on top of the last kill.
	Game.round_changed.emit(Game.round_no, Game.is_dog_round())
	Sfx.round_ceremony(Game.round_no, Game.is_dog_round())


func _end_round() -> void:
	# A dog round having finished, roll when the next one lands. Their arrival is
	# no longer a fixed multiple the player can count on.
	if Game.is_dog_round():
		_grant_max_ammo()
		Game.advance_dog_round()
	_intermission = true
	_round_timer = Game.INTERMISSION
	# Between rounds each barricade has a chance to regain a board. Kept low so
	# that repairing them yourself still matters.
	#
	# The ancestor's figure was 0.5 (html:2888) and the port already halved it to
	# 0.28, but both were calibrated against a placeholder in which a window lost
	# exactly one board per zombie routed through it. It loses all six now, inside
	# the first ten seconds of a round, to two bodies working it — so the demand
	# side has saturated and this is the only thing besides the player and the
	# Carpenter power-up that ever puts a plank back. 0.12 is about one board per
	# window per eight rounds: slow enough that a run which never rebuilds arrives
	# at round ten with the map genuinely open, fast enough that a window stripped
	# in round three is not silently free for the rest of a two-hour run.
	for wi in MapData.WINDOWS.size():
		if Rng.randf(Rng.ROUNDS) < 0.12 and map.window_boards[wi] < 6:
			world.set_window_boards(wi, map.window_boards[wi] + 1)


## The last hound of a dog round always leaves Max Ammo, and the per-round drop
## cap is cleared first so the guarantee cannot be swallowed by it.
func _grant_max_ammo() -> void:
	Game.drop_count = 0
	player.refill_ammo()
	Game.toast.emit("MAX AMMO")
	Sfx.play("powerup", -4.0)


## Windows nearer the player are likelier to be used, so opening more of the map
## does not reduce the pressure on you. A uniform pick made late rounds calmer
## the more doors you bought — exactly backwards.
func _pick_window(live: Array[int]) -> int:
	var here := player.grid_pos()
	var best: int = live[0]
	var best_w := -1.0
	for wi in live:
		var w: Dictionary = MapData.WINDOWS[wi]
		var d := here.distance_to(Vector2(w.ix + 0.5, w.iy + 0.5))
		var weight := (1.0 / (1.0 + d * 0.14)) * Rng.randf_range(Rng.SPAWN, 0.4, 1.6)
		# A window already being worked is a window whose six planks are coming off
		# in half the time, and a third body there stands inside the other two.
		# Divided rather than rejected so the pick can never run out of candidates,
		# and the SPAWN draw above happens either way — a seeded run stays
		# bit-identical.
		weight /= 1.0 + float(map.window_workers[wi])
		if weight > best_w:
			best_w = weight
			best = wi
	return best


## Puts one enemy at a live window. `kind` empty means "roll it", which is the
## only thing the round loop ever asks for.
##
## A named kind comes from the debug console and draws nothing for itself, so
## poking at the horde from the console cannot shift a seeded run's kind roll. The
## window pick above still draws, because there is no way to place a body without
## choosing where — that is the honest cost of a console spawn.
func spawn_one(kind := "") -> void:
	var live := map.live_windows()
	if live.is_empty():
		return
	var wi := _pick_window(live)
	var pos := map.window_stand_pos(wi)

	if kind.is_empty():
		kind = "zombie"
		if Game.is_dog_round():
			kind = "hound"
		elif Rng.randf(Rng.SPAWN) < Game.crawler_chance():
			kind = "crawler"

	var z := Zombie.create(kind, Rng.stream(Rng.SPAWN).randi() % 3, Game.round_no,
		Game.insta_kill > 0.0)
	z.flow = flow
	z.target = player
	z.add_to_group("zombies")
	add_child(z)
	z.global_position = Vector3(pos.x, 0.0, pos.y)
	z.set_entering(wi)
	z.died.connect(_on_zombie_died)
	_alive.append(z)
	_to_spawn -= 1
	# The board that used to come off here comes off in `Zombie._tick_boards` now,
	# one plank at a time, with a body standing outside pulling it. `set_entering`
	# above has already put this one in the barricade's exterior pocket and started
	# its first plank timer — or, at a window somebody already stripped, started the
	# vault instead.


func _on_zombie_died(z: Zombie, was_headshot: bool, by_melee: bool) -> void:
	_alive.erase(z)
	Game.kills += 1
	if was_headshot:
		Game.headshots += 1

	# One rule, one place — see Game.kill_points(). The branch that used to be here
	# paid a flat 50 for a KNIFE kill under Insta-Kill, and R4 §3 is Tier 1 that BO1
	# zeroes only the hit-location bonus: a melee kill still routes through MOD_MELEE
	# and keeps its bonus, so it stays at the full 130. Insta-Kill plus the Bowie is
	# the most canonical points play in the genre and it was paying 38% of rate.
	Game.add_points(Game.kill_points(was_headshot, by_melee))

	# The draw happens on every death, used or not — see Game.try_drop for why that
	# is load-bearing rather than wasteful.
	var lucky := Rng.randf(Rng.DROPS) < DROP_CHANCE
	if Game.try_drop(lucky):
		powerups.spawn(z.global_position)
