extends RefCounted

## Everything that has to be true of a level before it is worth playing, checked
## against every combination of doors a player can have bought.
##
## WHY THIS EXISTS AND WHY IT IS FIRST. Interior props and a seeded layout are both
## ways of changing the map, and until now nothing in the project could tell a good
## map from a broken one. The failures they produce are silent: a crate that seals a
## corridor does not error, it just makes half the windows dead and the round hang
## on a count that never reaches zero; a seed that strands the mystery box behind a
## door nobody can afford does not error either, it just produces a run the player
## cannot win. Both are invisible in a frame, invisible in a log, and invisible in
## every existing assertion.
##
## SIXTEEN STATES, NOT ONE. Four doors is sixteen combinations and a player can be
## in any of them: buying the debris before the stairwell is a different graph from
## buying the stairwell first, and a map is only correct if it is correct in all of
## them. Checking the shipped state alone would have missed every bug that depends
## on purchase order, which is the interesting half.
##
## Reached by `preload` rather than by a class name, matching the rest of the
## project: a freshly added script is not in the class registry until the editor
## rescans, and a headless run has no editor.

## The player-reachability question is asked with every door bought, because
## "unreachable" only means something once the map is fully open — the Theatre is
## *supposed* to be unreachable in state 0.
const ALL_DOORS := -1

## The electric traps' switch positions, which are fixed map data that no layout
## roll moves — so they are read from the system that owns them rather than
## restated here as a fourth copy.
const TRAPS := preload("res://scripts/systems/traps.gd")

## How many purchases deep a mystery-box spot may be and still be a legal place for
## a run to start. Mirrors `mystery_box.START_DOOR_DEPTH`, and deliberately is not
## imported from it: this file is the thing that would catch the two drifting apart,
## and a validator that reads its expectation out of the code under test proves
## nothing.
const BOX_START_DEPTH := 1


## Every failure the shipped geometry produces, across every door state. Empty means
## the map is sound. Each entry is one line, prefixed with the invariant it broke and
## the state it broke in, so a caller can print the array and be done.
static func check_all_states() -> Array[String]:
	var fails: Array[String] = []
	var n_doors := MapData.DOORS.size()
	var states := 1 << n_doors
	var reach_of: Array[PackedByteArray] = []
	# The all-doors state is state `states - 1`, so the whole-map pass below reuses
	# the map the loop already built rather than building a seventeenth. Sixteen
	# `MapData.build()` calls is most of what this function costs, and the sweep runs
	# the whole of it once per seed.
	var open_map: MapData = null

	for mask in states:
		var m := _state_map(mask)
		reach_of.append(m.reach.duplicate())
		_check_state(m, mask, fails)
		if mask == states - 1:
			open_map = m

	# Monotonicity (R5 I6). Buying a door is the only thing that changes the graph
	# and it can only ever ADD. A prop or a layout that made a purchase take
	# somewhere away would be a run that walks itself into a corner it cannot leave,
	# and the symptom — a window that stops spawning after a purchase — reads as a
	# spawn bug rather than a map bug.
	# A DOOR MUST LEAD SOMEWHERE, and until this line nothing asked. Opening a door
	# always turns its own two tiles into floor, so "did the purchase change
	# anything" is trivially yes and says nothing; the question worth asking is
	# whether it reached anything BEYOND the doorway. A prop that seals the room
	# behind a door produces a purchase that buys two tiles of threshold and a wall,
	# and it fails no other invariant in this file: nothing is orphaned (the sealed
	# tiles are prop_solid and skipped), nothing is lost (monotonicity only forbids
	# shrinking) and the level stays connected the long way round. Measured: sealing
	# the Stairwell with props produced ZERO failures before this.
	#
	# Asked as "in SOME state", not "in every state", because a door is allowed to be
	# redundant once you have gone round the other way — the Stairwell is reachable
	# from the Alley without ever buying it, so in that state the purchase legitimately
	# buys nothing but the threshold.
	var best_gain: Array[int] = []
	for _di in n_doors:
		best_gain.append(0)

	for mask in states:
		for di in n_doors:
			if mask & (1 << di) != 0:
				continue
			var after := mask | (1 << di)
			var lost := 0
			var gained := 0
			for i in reach_of[mask].size():
				if reach_of[mask][i] == 1 and reach_of[after][i] == 0:
					lost += 1
				elif reach_of[mask][i] == 0 and reach_of[after][i] == 1:
					gained += 1
			best_gain[di] = maxi(best_gain[di], gained)
			if lost > 0:
				fails.append("monotone [%s +door%d]: %d tiles stopped being reachable"
					% [_tag(mask), di, lost])

	for di in n_doors:
		var tiles: Array = MapData.DOORS[di].tiles
		if best_gain[di] <= tiles.size():
			fails.append("door-opens-nothing: door %d (%s) never reaches more than its "
				% [di, String(MapData.DOORS[di].label)]
				+ "own %d threshold tiles in any state" % tiles.size())

	_check_open_world(open_map, fails)
	_check_props(open_map, fails)
	_check_box_depth(fails)
	return fails


## A scratch map with a given set of doors bought. `mask` bit `d` means door `d` is
## open; ALL_DOORS means every one of them.
##
## A fresh MapData every time rather than a live one with doors reopened, because
## `open_door` is one-way — nothing in the game ever shuts a door, so nothing in the
## game has a correct implementation of shutting one, and inventing one here to save
## sixteen builds would be testing a code path that does not exist.
static func _state_map(mask: int) -> MapData:
	var m := _pristine().clone()
	for di in MapData.DOORS.size():
		if mask == ALL_DOORS or (mask & (1 << di)) != 0:
			m.open_door(di)
	return m


## One freshly built, all-doors-shut map, cloned for every state that needs one and
## held across seeds.
##
## The built GRID is layout-invariant and the seed sweep depends on that being true:
## a roll moves which perk is at which alcove, which gun is on which plaque, what a
## door costs and which tile in a room the box is under — and `build()` reads none of
## those. What it does read is the perk machines' POSITIONS, through the cost bump in
## `rebuild_cost()`, and those are the same four points whatever perk is standing on
## them.
##
## `_key` is what keeps that from being a comment rather than a fact: it is the set
## of positions the build actually consumes, and the template is thrown away the
## moment one of them moves. Without it, the day somebody makes a machine position
## seed-dependent, every seed after the first is validated against the first one's
## cost field and the sweep goes quietly blind.
static var _template: MapData = null
static var _key := ""


static func _pristine() -> MapData:
	var key := "%s|%s|%s" % [MapData.GENSPOT, MapData.PAPSPOT,
		str(MapData.PERKSPOTS.map(func(p: Dictionary) -> Vector2:
			return Vector2(p.x, p.y)))]
	if _template == null or key != _key:
		_template = MapData.new()
		_template.build()
		_key = key
	return _template


static func _tag(mask: int) -> String:
	if mask == ALL_DOORS:
		return "all doors"
	if mask == 0:
		return "no doors"
	var out: Array[String] = []
	for di in MapData.DOORS.size():
		if mask & (1 << di) != 0:
			out.append(str(di))
	return "doors " + "+".join(out)


# --- the per-state invariants ------------------------------------------------

static func _check_state(m: MapData, mask: int, fails: Array[String]) -> void:
	var tag := _tag(mask)
	var flow := FlowField.new(m)
	flow.solve(MapData.SPAWN_TILE)

	# I5: THE FLOW FIELD SOLVES FROM EVERY REACHABLE TILE.
	#
	# `reach` is a 4-connected flood from the spawn and so is the field, so this
	# looks tautological — and it is not, because the two disagree about what a wall
	# is. `compute_reach` treats a barricade as a reachable EDGE (that is how it
	# decides which windows are live) and refuses to enter an exterior pocket;
	# `is_blocked` knows neither rule. A tile that `reach` believes in and the field
	# does not is a tile a zombie can stand on with no downhill step available, which
	# is a body that stops moving for the rest of the round.
	var unsolved := 0
	var worst := Vector2i.ZERO
	for i in m.reach.size():
		if m.reach[i] != 1 or m.solid[i] == 1 or m.pocket_at[i] >= 0:
			continue
		if flow.dist[i] < 0:
			unsolved += 1
			worst = Vector2i(i % MapData.MAPW, i / MapData.MAPW)
	if unsolved > 0:
		fails.append("flow-solves [%s]: %d reachable tiles have no path, e.g. %s"
			% [tag, unsolved, worst])

	# The player's own footing. Everything else in this file assumes the fill has
	# somewhere to start from.
	var si := MapData.ix(MapData.SPAWN_TILE.x, MapData.SPAWN_TILE.y)
	if m.solid[si] == 1 or m.prop_solid[si] == 1:
		fails.append("spawn-enclosed [%s]: the player spawn tile is not standable" % tag)

	# NO SPAWN POINT ENCLOSED, for the other kind of spawn. A round ends when
	# everything queued has died and `spawn_one` returns without spawning when
	# nothing is live — so a state with no live window does not fail, it hangs the
	# round forever with the count on screen. That is the single worst thing a map
	# edit can do and it has no error message anywhere.
	var live := m.live_windows()
	if live.is_empty():
		fails.append("no-live-window [%s]: the horde has nowhere to arrive from" % tag)
	for wi in live:
		var w: Dictionary = MapData.WINDOWS[wi]
		var ii := MapData.ix(int(w.ix), int(w.iy))
		if m.solid[ii] == 1 or m.prop_solid[ii] == 1:
			fails.append("window-inside [%s]: window %d opens into geometry" % [tag, wi])
		elif flow.dist[ii] < 0:
			fails.append("window-inside [%s]: window %d is live but its inside tile "
				% [tag, wi] + "has no path to the player")

	# EVERY WINDOW REACHABLE FROM OUTSIDE. The pocket is where a zombie stands to
	# work the boards and where the vault starts, and it has to be real floor that
	# the player can never get to — `compute_reach` has an explicit rule for the
	# second half and this is what proves the rule is still doing something.
	for wi in MapData.WINDOWS.size():
		var w: Dictionary = MapData.WINDOWS[wi]
		var p := m.window_pocket(wi)
		if p.x < 0 or p.y < 0 or p.x >= MapData.MAPW or p.y >= MapData.MAPH:
			fails.append("window-outside [%s]: window %d has no pocket on the map"
				% [tag, wi])
			continue
		var pi := MapData.ix(p.x, p.y)
		if m.solid[pi] == 1 or m.prop_solid[pi] == 1:
			fails.append("window-outside [%s]: window %d has nowhere to stand" % [tag, wi])
		if m.pocket_at[pi] != wi:
			fails.append("window-outside [%s]: window %d's pocket is not marked as one"
				% [tag, wi])
		if m.reach[pi] == 1:
			fails.append("window-outside [%s]: window %d's pocket is player-reachable"
				% [tag, wi])
		if absi(p.x - int(w.x)) + absi(p.y - int(w.y)) != 1:
			fails.append("window-outside [%s]: window %d's pocket is not against it"
				% [tag, wi])

	# NO INTERACTABLE INSIDE GEOMETRY. A door's point is inside its own slab by
	# design — `interaction_system.DOOR_LOS_SLACK` exists for exactly that — so a
	# shut door is the one exemption, and it stops being exempt the moment it opens.
	for row: Dictionary in interact_points(m):
		var at: Vector2 = row.pos
		var x := floori(at.x)
		var y := floori(at.y)
		if x < 0 or y < 0 or x >= MapData.MAPW or y >= MapData.MAPH:
			fails.append("interact-buried [%s]: %s is off the map at %s"
				% [tag, row.key, at])
			continue
		var i := MapData.ix(x, y)
		var shut_door: bool = bool(row.door) and m.solid[i] == 1
		if shut_door:
			continue
		if m.solid[i] == 1:
			fails.append("interact-buried [%s]: %s stands inside a wall" % [tag, row.key])
		elif m.prop_solid[i] == 1 and not (bool(row.machine) and m.machine_at[i] >= 0):
			fails.append("interact-buried [%s]: %s stands inside a prop" % [tag, row.key])

	# EVERY BOX SPOT REACHABLE, once the spot is in a room that has been opened. A
	# spot the player can see but the field cannot solve to is a box the horde walks
	# past, which is the worst place in the level for that to be true.
	#
	# ...and NO BOX SPOT IS A CUT VERTEX, IN THIS STATE. That second half is what
	# licenses `MapData.set_box_block()` to skip `compute_reach()`, and it has to be
	# asked per state rather than with the map open: the box relocates mid-run in
	# whatever door state the run is in, and fewer doors is strictly fewer routes, so
	# "not a cut vertex with everything open" does not imply it anywhere else. The
	# comment on `set_box_block` claimed every door state and the check was only ever
	# run on one.
	#
	# Nearly free despite being sixteen times as many questions, because of the
	# `_cannot_cut` screen — a local 3x3 test that settles almost every spot without
	# touching the grid. Only a spot it cannot settle pays for a flood.
	var whole := -1
	for bi in MapData.BOXSPOTS.size():
		var s: Vector2 = MapData.BOXSPOTS[bi]
		var b := Vector2i(int(s.x), int(s.y))
		var i := MapData.ix(b.x, b.y)
		if m.solid[i] == 1 or m.prop_solid[i] == 1:
			fails.append("box-buried [%s]: box spot %d is inside geometry" % [tag, bi])
			continue
		if m.reach[i] == 1 and flow.dist[i] < 0:
			fails.append("box-buried [%s]: box spot %d is reachable but unsolvable"
				% [tag, bi])
		if m.reach[i] != 1 or _cannot_cut(m, b):
			continue
		if whole < 0:
			whole = _flood_size(m, Vector2i(-1, -1))
		if _flood_size(m, b) < whole - 1:
			fails.append("box-choke [%s]: the box's own collider at spot %d cuts the "
				% [tag, bi] + "level in two, and set_box_block() does not re-flood")

	# The cost field and the blocking grid have to agree, or a solver that reads one
	# and a body that collides with the other are steering by different maps.
	var mismatch := 0
	for i in m.cost.size():
		var shut: bool = m.solid[i] == 1 or m.prop_solid[i] == 1
		if (m.cost[i] >= MapData.COST_WALL) != shut:
			mismatch += 1
	if mismatch > 0:
		fails.append("cost-agrees [%s]: %d tiles where cost and is_blocked disagree"
			% [tag, mismatch])


# --- the whole-map invariants ------------------------------------------------

## EVERY WALKABLE TILE REACHABLE FROM SPAWN, asked in the only state where the
## question is fair. An orphaned pocket of floor is a room the player can see through
## a doorway and never enter, and it is also somewhere a nuke can leave a zombie
## alive forever.
static func _check_open_world(m: MapData, fails: Array[String]) -> void:
	var orphan := 0
	var worst := Vector2i.ZERO
	for i in m.solid.size():
		if m.solid[i] == 1 or m.prop_solid[i] == 1 or m.pocket_at[i] >= 0:
			continue
		if m.reach[i] == 0:
			orphan += 1
			worst = Vector2i(i % MapData.MAPW, i / MapData.MAPW)
	if orphan > 0:
		fails.append("orphan-floor [all doors]: %d walkable tiles cannot be reached "
			% orphan + "from spawn, e.g. %s" % worst)

	# A machine's own tile is unreachable by construction now that it has a body in
	# it, so the question for one is whether you can get to the FLOOR BESIDE it. Get
	# this wrong and the symptom is a perk you can see and never buy.
	for row: Dictionary in interact_points(m):
		var at: Vector2 = row.pos
		var x := floori(at.x)
		var y := floori(at.y)
		var i := MapData.ix(x, y)
		if bool(row.machine):
			if _reachable_neighbour(m, x, y) == Vector2i(-1, -1):
				fails.append("interact-stranded [all doors]: %s has no reachable tile "
					% row.key + "beside it")
		elif m.reach[i] != 1:
			fails.append("interact-stranded [all doors]: %s cannot be walked to"
				% row.key)

	# R5 I1. A one-tile-wide passage is a guaranteed conga line —
	# `agents_abreast(W) = floor((W - 0.52) / 0.62) + 1` puts two tiles at three
	# abreast and one tile at one.
	#
	# ABSOLUTE FOR PROPS, because the measurement says it can be: the bare grid with
	# every door open has ZERO one-abreast tiles outside the pockets, so the delta
	# form this used to be was comparing against an empty set and paying a whole
	# extra `_state_map(ALL_DOORS)` — a build, a cost rebuild and a flood — for every
	# validation and therefore for every seed of the sweep.
	#
	# THE MACHINES ARE JUDGED DIFFERENTLY, and not to let them off. Eight of them sit
	# one tile from a wall, so eight of them narrow that gap to one-abreast, and that
	# is what a perk alcove IS — Kino's Juggernog is a squeeze too. What must never be
	# true is that the squeeze is the only way past: see `_check_chokes`.
	var pinched := _pinches(m)
	var by_prop: Array[String] = []
	for p: Vector2i in pinched:
		if _pinch_source(m, p) == "prop":
			by_prop.append(str(p))
	if not by_prop.is_empty():
		fails.append("prop-pinch [all doors]: props narrowed %d tiles to one-abreast: %s"
			% [by_prop.size(), " ".join(by_prop)])

	_check_chokes(m, pinched, fails)


## An open, player-reachable tile orthogonally or diagonally adjacent to (x, y), or
## (-1, -1). Diagonals count because three of the perk alcoves have a wall on at least
## one orthogonal side.
static func _reachable_neighbour(m: MapData, x: int, y: int) -> Vector2i:
	for d: Vector2i in MapData.NEIGHBOURS8:
		var nx := x + d.x
		var ny := y + d.y
		if nx < 0 or ny < 0 or nx >= MapData.MAPW or ny >= MapData.MAPH:
			continue
		if m.is_blocked(nx, ny):
			continue
		var i := MapData.ix(nx, ny)
		if m.pocket_at[i] >= 0 or m.reach[i] != 1:
			continue
		return Vector2i(nx, ny)
	return Vector2i(-1, -1)


## What narrowed a tile: "machine" if either blocker across the narrow axis is one,
## "prop" if either is a prop, "wall" otherwise. Machine wins, because a tile pinched
## between a wall and a Juggernog is the Juggernog's doing.
static func _pinch_source(m: MapData, p: Vector2i) -> String:
	var out := "wall"
	for d: Vector2i in MapData.NEIGHBOURS4:
		var nx := p.x + d.x
		var ny := p.y + d.y
		if nx < 0 or ny < 0 or nx >= MapData.MAPW or ny >= MapData.MAPH:
			continue
		var i := MapData.ix(nx, ny)
		if m.machine_at[i] >= 0:
			return "machine"
		if m.prop_at[i] >= 0:
			out = "prop"
	return out


## NO ONE-ABREAST TILE MAY BE THE ONLY WAY THROUGH.
##
## This is the invariant that makes a machine squeeze acceptable and a machine in a
## doorway not. A one-tile gap beside Juggernog is a squeeze the player chooses; the
## same gap where it is the single link between two halves of the level is a permanent
## conga line with no alternative, and R5 I1 is really about the second case.
##
## THE BOX SPOTS USED TO BE PROBED HERE AND ARE NOT ANY MORE, and the move is the
## point rather than a tidy-up. What licenses `MapData.set_box_block()` to skip
## `compute_reach()` is that the box's collider is never a cut vertex IN THE STATE THE
## RUN IS IN, and this function only ever runs with every door bought — the state with
## the most routes and therefore the fewest cut vertices, which is the wrong end of
## the question. It lives in `_check_state` now, once per door state, behind the
## `_ring_open` screen that keeps sixteen times the questions costing about the same.
##
## Cheap because it is only asked of the few tiles that are narrow: one flood each,
## in one door state, rather than a biconnectivity pass over the whole grid. A
## one-abreast tile is a property of masonry, props and machines, none of which a door
## purchase or a seed moves, so one state is the right number for this half.
static func _check_chokes(m: MapData, pinched: Array[Vector2i],
		fails: Array[String]) -> void:
	var whole := _flood_size(m, Vector2i(-1, -1))
	for p: Vector2i in pinched:
		if m.is_blocked(p.x, p.y):
			continue
		if _flood_size(m, p) < whole - 1:
			fails.append("choke [all doors]: the one-abreast tile at %s is the only "
				% p + "route between two parts of the level")


## The eight cells around a tile, in cyclic order. Consecutive entries are 4-ADJACENT
## TO EACH OTHER — N to NE differs by (1,0), NE to E by (0,1), and so on all the way
## round — which is the whole reason the screen below works.
const RING8 := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]


## A tile that provably cannot disconnect anything when it is removed, decided from
## its own 3x3 and nothing else.
##
## If the open cells of the ring form a single contiguous arc, then any two open
## neighbours of the tile are joined by a walk along that arc — consecutive ring cells
## are 4-adjacent — so every path through the middle has a detour around it and the
## tile is not a cut vertex. Two or more arcs and it might be, and only then is a
## flood worth paying for.
##
## This is why sixteen door states of box-choke cost about what one used to: on the
## shipped table and on every jittered one swept so far, no spot in any state has ever
## needed the flood. A spot in the middle of a room passes, a spot flat against a wall
## passes (five cells in one arc), a spot in a room corner passes (three); a spot in a
## doorway does not, which is the case the invariant is for.
static func _cannot_cut(m: MapData, p: Vector2i) -> bool:
	var open_at: Array[bool] = []
	for d: Vector2i in RING8:
		var nx := p.x + d.x
		var ny := p.y + d.y
		var ok := nx >= 0 and ny >= 0 and nx < MapData.MAPW and ny < MapData.MAPH
		if ok:
			ok = not m.is_blocked(nx, ny) and m.pocket_at[MapData.ix(nx, ny)] < 0
		open_at.append(ok)
	var runs := 0
	for k in 8:
		if open_at[k] and not open_at[(k + 7) % 8]:
			runs += 1
	# `runs == 0` is either an isolated tile or a fully open ring; removing either
	# disconnects nothing.
	return runs <= 1


## Reachable open tiles from the spawn, with one extra tile treated as blocked.
static func _flood_size(m: MapData, skip: Vector2i) -> int:
	var seen := PackedByteArray()
	seen.resize(MapData.MAPW * MapData.MAPH)
	var start := MapData.ix(MapData.SPAWN_TILE.x, MapData.SPAWN_TILE.y)
	if m.is_blocked(MapData.SPAWN_TILE.x, MapData.SPAWN_TILE.y):
		return 0
	var q: Array[int] = [start]
	seen[start] = 1
	var head := 0
	var n := 0
	while head < q.size():
		var i: int = q[head]
		head += 1
		n += 1
		var x := i % MapData.MAPW
		var y := i / MapData.MAPW
		for d: Vector2i in MapData.NEIGHBOURS4:
			var nx := x + d.x
			var ny := y + d.y
			if nx == skip.x and ny == skip.y:
				continue
			if nx < 0 or ny < 0 or nx >= MapData.MAPW or ny >= MapData.MAPH:
				continue
			if m.is_blocked(nx, ny):
				continue
			var ni := MapData.ix(nx, ny)
			if seen[ni] == 1 or m.pocket_at[ni] >= 0:
				continue
			seen[ni] = 1
			q.append(ni)
	return n


## Tiles that are one tile wide across one axis: open, with both neighbours on that
## axis blocked. Pockets are excluded because a pocket is a one-tile alcove by
## construction and is never on a route.
static func _pinches(m: MapData) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in MapData.MAPH:
		for x in MapData.MAPW:
			var i := MapData.ix(x, y)
			if m.is_blocked(x, y) or m.pocket_at[i] >= 0:
				continue
			var ew := m.is_blocked(x - 1, y) and m.is_blocked(x + 1, y)
			var ns := m.is_blocked(x, y - 1) and m.is_blocked(x, y + 1)
			if ew or ns:
				out.append(Vector2i(x, y))
	return out


## The props themselves, checked against the two rules that make them work at all.
static func _check_props(m: MapData, fails: Array[String]) -> void:
	for pi in MapData.PROPS.size():
		var p: Dictionary = MapData.PROPS[pi]

		# TALLER THAN THE SIGHT LINE, WITHOUT EXCEPTION.
		#
		# `world_builder._build_props()` gives EVERY row here a `BoxShape3D` on layer
		# 1, whatever its height, and `MapData._stamp_props()` only puts a row in
		# `prop_solid` at or above PROP_BLOCK_H. So a prop below that height is solid
		# to a body, absent from the field, and — below LOS_HEIGHT — invisible to
		# `zombie._has_los` as well, which is the exact thing the whole height rule
		# exists to forbid: the horde walks into it and grinds against it forever.
		#
		# This used to carry `and p.h > MACHINE_H`, which whitelisted the WORST case
		# rather than the safe one — a 0.8 m crate was declared fine for "ducking
		# under the interact ray", a property only a machine needs and no prop has.
		if float(p.h) > 0.0 and float(p.h) < MapData.PROP_BLOCK_H:
			fails.append("prop-height: prop %d at %.2f m is solid to a body and under "
				% [pi, float(p.h)] + "the %.2f m sight line" % MapData.PROP_BLOCK_H)

		for y in range(int(p.y0), int(p.y1) + 1):
			for x in range(int(p.x0), int(p.x1) + 1):
				# Bounds first. A prop authored off the grid used to index straight
				# into the Packed arrays, and a runtime error here unwinds the whole
				# check — the validator would go quiet instead of complaining.
				if x < 0 or y < 0 or x >= MapData.MAPW or y >= MapData.MAPH:
					fails.append("prop-off-map: prop %d covers (%d,%d)" % [pi, x, y])
					continue
				var i := MapData.ix(x, y)
				if m.solid[i] == 1:
					fails.append("prop-in-wall: prop %d covers masonry at (%d,%d)"
						% [pi, x, y])
				if m.pocket_at[i] >= 0:
					fails.append("prop-in-pocket: prop %d covers a barricade pocket at "
						% pi + "(%d,%d)" % [x, y])

	# A machine that stood taller than the interaction ray would occlude its own
	# interact point and be unbuyable — the bug `DOOR_LOS_SLACK` was written for,
	# and the one thing about this pass that can take a perk out of the game.
	if MapData.MACHINE_H >= MapData.LOS_HEIGHT:
		fails.append("machine-height: a machine collider at %.2f m reaches the %.2f m "
			% [MapData.MACHINE_H, MapData.LOS_HEIGHT] + "interaction ray")

	# ...and the other half of that bargain. A machine that ducks under the sight line
	# is a machine no ray will ever report, so the GRID has to carry it or the field
	# steers bodies into a metre of solid crate. This is the same claim `cost-agrees`
	# makes about the cost field, made about the physics space.
	var pts := m.machine_positions()
	for mi in pts.size():
		var mp: Vector2 = pts[mi]
		var mx := int(mp.x)
		var my := int(mp.y)
		if mx < 0 or my < 0 or mx >= MapData.MAPW or my >= MapData.MAPH:
			fails.append("machine-off-map: machine %d at %s" % [mi, mp])
			continue
		var i := MapData.ix(mx, my)
		if m.solid[i] == 1:
			fails.append("machine-in-wall: machine %d at %s stands in masonry" % [mi, mp])
		elif m.machine_at[i] != mi:
			fails.append("machine-unstamped: machine %d at %s is solid to a body and "
				% [mi, mp] + "open to the flow field")
		if m.prop_at[i] >= 0:
			fails.append("machine-on-prop: machine %d at %s shares a tile with prop %d"
				% [mi, mp, m.prop_at[i]])

	# Nothing may stand on a tile something else already needs. Props are authored by
	# hand against a tile grid and this is the typo that costs a perk machine.
	for row: Dictionary in interact_points(m):
		var at: Vector2 = row.pos
		var i := MapData.ix(floori(at.x), floori(at.y))
		if m.prop_at[i] >= 0:
			fails.append("prop-on-interactable: prop %d sits on %s"
				% [m.prop_at[i], row.key])
	var spawn_i := MapData.ix(MapData.SPAWN_TILE.x, MapData.SPAWN_TILE.y)
	if m.prop_at[spawn_i] >= 0:
		fails.append("prop-on-spawn: prop %d sits on the player spawn" % m.prop_at[spawn_i])


## The box has to be somewhere a run can actually get to before the run is over.
## `mystery_box.start_spots()` filters to spots at most one purchase deep and falls
## back to spot 0 if that set is empty — so an empty set is not an error there, it is
## a silent revert, and this is the only thing that would notice.
static func _check_box_depth(fails: Array[String]) -> void:
	var depth := spot_depths()
	var shallow := 0
	for bi in depth.size():
		if depth[bi] >= 0 and depth[bi] <= BOX_START_DEPTH:
			shallow += 1
	if shallow == 0:
		fails.append("box-start: every box spot is more than %d purchases deep (%s), "
			% [BOX_START_DEPTH, str(depth)] + "so a run has no box until the map is open")


## How many door purchases deep each box spot is, by widening one layer at a time.
## Every door on the current frontier opens together, because opening them one at a
## time would let a door bought in this layer expose another in the same layer and
## understate everything behind it.
##
## All four spots in ONE walk, and that matters: this used to be a walk per spot, and
## a walk is a `MapData.build()` plus four door purchases. Four of them is a quarter
## of the cost of the entire sixteen-state validation, paid for an answer the first
## walk already had.
##
## Deliberately a second implementation of `mystery_box.spot_door_depth()` rather
## than a call into it: a validator that reads its expectation out of the code under
## test proves nothing, and this file is what would catch the two drifting apart.
static func spot_depths() -> Array[int]:
	var pts: Array[Vector2] = []
	for s: Vector2 in MapData.BOXSPOTS:
		pts.append(s)
	return point_depths(pts)


## The walk itself, for any set of points. Also how the seed sweep reports where a
## roll actually put Juggernog, which is the one thing about the run layer that a
## player would call difficulty — and the only part of it that anything in this
## project can measure, because the balance sim has no map at all
## (notes/balance/README.md, "Missing: No map").
static func point_depths(points: Array[Vector2]) -> Array[int]:
	var m := _pristine().clone()
	var depth: Array[int] = []
	for _i in points.size():
		depth.append(-1)
	var layer := 0
	while true:
		var pending := false
		for bi in points.size():
			if depth[bi] >= 0:
				continue
			var s: Vector2 = points[bi]
			if _standable_at(m, int(s.x), int(s.y)):
				depth[bi] = layer
			else:
				pending = true
		if not pending:
			return depth
		var frontier: Array[int] = []
		for di in MapData.DOORS.size():
			if m.door_open[di] == 0 and _door_touchable(m, di):
				frontier.append(di)
		if frontier.is_empty():
			return depth
		for di in frontier:
			m.open_door(di)
		layer += 1
	return depth


## Whether a run that has bought this many doors can get to a point — which is not
## "is its tile reachable", and the difference is eight of the twelve points anything
## ever asks about.
##
## T3.4 gave every machine a body, so a machine's own tile is `prop_solid` and
## `compute_reach` can never enter it. `point_depths` asked `reach[tile] == 1` and so
## reported EVERY perk machine, Pack-a-Punch and the generator as depth -1 —
## permanently unreachable — for every seed. Nothing failed, because the one caller
## printed the answer instead of asserting it: `[mapgen] Juggernog door depth
## { -1: 48 }` shipped for a whole wave as the only difficulty number the run layer
## produces. Same rule as `_check_open_world` uses for the same reason: you buy a perk
## from the floor beside it.
static func _standable_at(m: MapData, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= MapData.MAPW or y >= MapData.MAPH:
		return false
	var i := MapData.ix(x, y)
	if not m.is_blocked(x, y) and m.pocket_at[i] < 0:
		return m.reach[i] == 1
	return _reachable_neighbour(m, x, y) != Vector2i(-1, -1)


static func _door_touchable(m: MapData, di: int) -> bool:
	var tiles: Array = MapData.DOORS[di].tiles
	for t: Array in tiles:
		for d: Vector2i in MapData.NEIGHBOURS4:
			var nx: int = int(t[0]) + d.x
			var ny: int = int(t[1]) + d.y
			if nx < 0 or ny < 0 or nx >= MapData.MAPW or ny >= MapData.MAPH:
				continue
			var ni := MapData.ix(nx, ny)
			if m.solid[ni] == 0 and m.prop_solid[ni] == 0 and m.reach[ni] == 1:
				return true
	return false


# --- what counts as an interactable ------------------------------------------

## Every point in the level the F key can be pointed at, derived from the map data
## rather than from the live interact table.
##
## Derived on purpose: `interaction_system.build()` runs once, against whatever
## layout was live at the time, and this file has to be able to validate a layout
## that has never been built. The two agreeing is itself asserted, in
## `checks/mapgen.gd`, which has a live table to compare against.
## `door` and `machine` are the two exemptions from "an interact point stands on open
## floor", and they are exemptions for opposite reasons. A door's point is inside its
## own slab until it is bought (`interaction_system.DOOR_LOS_SLACK` exists for that);
## a machine's point is its own centre and the machine now has a body there, so a
## machine standing inside its own collider is not a bug, it is what a machine is.
## Both still have to be walkable TO — see `_check_open_world`.
static func interact_points(m: MapData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for di in MapData.DOORS.size():
		var tiles: Array = MapData.DOORS[di].tiles
		var t: Array = tiles[0]
		out.append({"key": "door:%d" % di,
			"pos": Vector2(float(t[0]) + 0.5, float(t[1]) + 0.5),
			"door": true, "machine": false})
	for wb: Dictionary in MapData.WALLBUYS:
		out.append({"key": "wallbuy:%s" % wb.gun, "pos": MapData.wallbuy_point(wb),
			"door": false, "machine": false})
	out.append({"key": "bowie", "pos": MapData.wallbuy_point(MapData.BOWIE),
		"door": false, "machine": false})
	for ps: Dictionary in MapData.PERKSPOTS:
		out.append({"key": "perk:%s" % ps.k, "pos": Vector2(ps.x, ps.y),
			"door": false, "machine": true})
	for wi in MapData.WINDOWS.size():
		var w: Dictionary = MapData.WINDOWS[wi]
		out.append({"key": "window:%d" % wi,
			"pos": Vector2(float(w.ix) + 0.5, float(w.iy) + 0.5),
			"door": false, "machine": false})
	for tr: Dictionary in TRAPS.SPOTS:
		out.append({"key": "trap:%s" % tr.key, "pos": Vector2(tr.switch),
			"door": false, "machine": false})
	out.append({"key": "power", "pos": MapData.GENSPOT, "door": false, "machine": true})
	out.append({"key": "pap", "pos": MapData.PAPSPOT, "door": false, "machine": true})
	for bi in MapData.BOXSPOTS.size():
		out.append({"key": "boxspot:%d" % bi, "pos": MapData.BOXSPOTS[bi],
			"door": false, "machine": false})
	return out
