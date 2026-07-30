extends RefCounted

## The map itself: the six connectivity invariants across every door state, the
## interior props, the cost field, and the seeded run layer.
##
## Everything here is about a class of bug that has no symptom at the moment it is
## introduced. A crate on the wrong tile, a machine collider a hand too tall, a seed
## that puts the box behind two doors — none of them error, none of them show in a
## frame, and all of them are only visible as "the round hung" or "I could not buy
## the perk" several minutes into a run that has already been ruined.
##
## **Run this LAST.** The seed sweep rolls `MapData`'s static layout tables hundreds
## of times and re-seeds Rng on every iteration; it puts both back on the way out,
## but anything downstream that had cached a wall-buy position would be reading it
## across the churn.
##
## What is deliberately NOT here: anything about whether the props LOOK right (that
## is `--shot`), and anything about crowd behaviour around them (that is `--sim` and
## a stopwatch — the validator can prove a pillar does not break the map, not that
## training around it feels good).

const VALIDATOR := preload("res://scripts/world/map_validator.gd")

## Seeds swept inside `--verify`. Each one costs a full sixteen-state validation, so
## this is a sample and the number is a time budget: 48 seeds is about three seconds.
##
## RAISE IT AND RUN IT BY HAND after any change to the roll or to the props — that is
## what this constant is for, and it is how the shipped number was arrived at. 512
## seeds x 16 door states = 8192 validations, 0 failures, 0 fallbacks, 32.5 s.
const SWEEP_SEEDS := 48
## Where the sweep starts. Fixed rather than random, because a suite that tests
## different seeds every run is a suite that fails on somebody else's machine.
const SWEEP_FIRST := 1000

## What the four doors cost together in the canonical table, restated here rather
## than summed from `DOORS_FIXED`: `_roll_door_costs` reads that same table to build
## its rescale, so a check that summed it would be comparing the roll against its own
## input and would still pass if both drifted.
const CANON_DOOR_TOTAL := 4250
## The most a run may have to save before it can open the map at all. See
## `_door_prices`. 1200 is a price the shipped game already asks for a wall weapon;
## measured maximum over 20 000 rolls is 1100 against a canonical 750.
const FIRST_DOOR_MAX := 1200
## The band a single rolled door price may land in. Both measured over 20 000 rolls,
## which produce 400..1900 against canonical prices of 750/1000/1250/1250.
##
## THE CEILING IS WHAT WATCHES THE RESCALE, and the total does not. Deleting the
## rescale from `_roll_door_costs` outright leaves the total at exactly 4250 — the
## residual line at the end puts the whole error back on one door by itself — so a
## check on the total alone passes on a roll with no rescale in it. What the rescale
## buys is that no single door absorbs that error: without it the dearest door reaches
## 2300. Verified by removing the line and watching this fail and the total not.
const DOOR_COST_MAX := 1900
const DOOR_COST_FLOOR_SEEN := 400
## Door tables rolled for the price checks. Two orders of magnitude more than
## SWEEP_SEEDS because a roll on its own is nearly free and the failure it is looking
## for lives in the tail — see `_door_prices`.
const PRICE_SEEDS := 4000


static func run(v: Verify, main: Node3D) -> void:
	_shipped(v)
	_props(v, main)
	_machines_buyable(v, main)
	_cost_field(v, main)
	_table_agrees(v, main)
	_layout_rolls(v)
	_door_prices(v)
	_sweep(v)


# --- the shipped map ---------------------------------------------------------

static func _shipped(v: Verify) -> void:
	var t0 := Time.get_ticks_usec()
	var fails := VALIDATOR.check_all_states()
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	v.check("the shipped map passes every invariant in all %d door states"
		% (1 << MapData.DOORS.size()),
		fails.is_empty(), "%d failures: %s" % [fails.size(), "; ".join(fails)])

	# A validator that is cheap is a validator that can run on every seed, and the
	# whole seeded run layer depends on that being true — the sweep below pays this
	# cost SWEEP_SEEDS times over. Measured at 74 ms per validation on this machine
	# (37 906 ms for 512 seeds x 16 door states): sixteen clones, up to 64 door
	# purchases, sixteen flow solves and sixteen choke floods. It was 52 ms before the
	# choke invariant and the machine grid landed. 120 ms leaves a little over half
	# again in hand; blowing through it means the sweep has quietly become a
	# ten-second item in a developer's inner loop.
	v.check("validating all door states stays inside its sweep budget", ms < 120.0,
		"%.1f ms" % ms)

	# THE NEGATIVE CONTROL, AND IT IS PERMANENT RATHER THAN A THING A REVIEWER DID
	# ONCE. Everything else in this file, and every seed of the sweep, is the same
	# claim: `check_all_states()` came back empty. A validator that had quietly stopped
	# looking — a helper that returned early, a loop over a table that was emptied, an
	# exception swallowed by a caller — reports exactly that, forever, and raises the
	# suite's green count while doing it. The floor cannot see it and `_registered()`
	# cannot see it, because the module runs and its assertions pass.
	#
	# So one deliberately broken map, every run. A box spot inside the border ring is
	# the cheapest lie to tell: no geometry moves, no static is poisoned, and putting
	# the one Vector2 back is the whole undo. The pair matters — the second half is
	# what proves the first half did not simply leave the map broken.
	var was: Vector2 = MapData.BOXSPOTS[0]
	MapData.BOXSPOTS[0] = Vector2(1.5, 1.5)
	var broken := VALIDATOR.check_all_states()
	MapData.BOXSPOTS[0] = was
	v.check("...and a map with a box spot inside masonry does NOT pass it",
		not broken.is_empty(), "the validator found nothing wrong with a buried box")
	v.check("...and the fixture puts the map back the way it found it",
		VALIDATOR.check_all_states().is_empty())


# --- interior geometry -------------------------------------------------------

static func _props(v: Verify, main: Node3D) -> void:
	var map: MapData = main.map
	var world: WorldBuilder = main.world

	# The props exist as physics, not just as pixels. This is the entire point of
	# T3.4: a training pivot the horde walks through is a decoration.
	var body: StaticBody3D = world._prop_body
	var shapes := 0
	if body != null:
		for c in body.get_children():
			if c is CollisionShape3D:
				shapes += 1
	# The mystery box's shape is discounted rather than counted, because whether it
	# exists yet is a race: it is created by `world._process` the first time it sees
	# `Game.box_spot`, and `--verify` is deferred into the same first frame.
	if world._box_shape != null and is_instance_valid(world._box_shape):
		shapes -= 1
	var want: int = MapData.PROPS.size() + map.machine_positions().size()
	v.check("every prop and every machine has a real collider",
		body != null and shapes == want, "shapes=%d want=%d" % [shapes, want])

	# ...and the box gets one too, wherever it happens to be standing. Driven by hand
	# rather than waited for, so the assertion does not depend on frame order.
	world._process(0.0)
	var box_at: Vector2 = MapData.BOXSPOTS[Game.box_spot]
	var cs: CollisionShape3D = world._box_shape
	v.check("the mystery box carries its collider to whichever spot it is on",
		cs != null and is_instance_valid(cs)
			and Vector2(cs.position.x, cs.position.z).is_equal_approx(box_at),
		"box at %s, collider at %s" % [box_at, "none" if cs == null else str(cs.position)])

	# ...and the grid block travels with the shape, in the same call. Driven twice, to
	# the far spot and back, because the failure this catches is a block LEFT BEHIND:
	# a wall in the field at a tile the teddy bear has already emptied.
	var home: int = Game.box_spot
	var away := (home + 2) % MapData.BOXSPOTS.size()
	var away_at: Vector2 = MapData.BOXSPOTS[away]
	world.set_box_collider(away_at)
	var moved: bool = map.is_blocked(int(away_at.x), int(away_at.y)) \
		and not map.is_blocked(int(box_at.x), int(box_at.y))
	world.set_box_collider(box_at)
	v.check("the box's grid block follows it and leaves nothing behind",
		moved and map.is_blocked(int(box_at.x), int(box_at.y))
			and not map.is_blocked(int(away_at.x), int(away_at.y)),
		"home %s away %s" % [box_at, away_at])
	v.check("the props are on the world layer, so the shared LOS test sees them",
		body != null and (body.collision_layer & 1) != 0,
		"layer=%d" % (body.collision_layer if body != null else -1))

	# THE HEIGHT RULE, from both ends, and neither end is obvious.
	#
	# A blocking prop must be TALLER than `los.clear_flat`'s 1.2 m, because
	# `zombie._physics_process` overrides the flow field with a straight line
	# whenever that ray is clear inside 9 m — a waist-high crate that stops a body
	# but not a sight line is a thing the horde grinds against forever.
	#
	# A machine collider must be SHORTER than it, because `interaction_system._sees`
	# aims its occlusion ray at exactly that height and stops it `LOS_SLACK` short of
	# a point that is the machine's own centre. A machine that reached the ray would
	# occlude itself and could never be bought.
	var short_prop := ""
	for pi in MapData.PROPS.size():
		var p: Dictionary = MapData.PROPS[pi]
		if float(p.h) <= MapData.LOS_HEIGHT:
			short_prop += "%d@%.2f " % [pi, float(p.h)]
	v.check("every blocking prop stands above the shared sight line",
		short_prop.is_empty() and MapData.PROP_BLOCK_H > MapData.LOS_HEIGHT, short_prop)
	v.check("every machine collider ducks under the interaction ray",
		MapData.MACHINE_H < MapData.LOS_HEIGHT,
		"machine=%.2f ray=%.2f" % [MapData.MACHINE_H, MapData.LOS_HEIGHT])

	# The grid and the geometry are two descriptions of the same crate, written in
	# two files, and only one of them is what a zombie steers by.
	var stamped := 0
	for i in map.prop_at.size():
		if map.prop_at[i] >= 0:
			stamped += 1
	var tiles := 0
	for p: Dictionary in MapData.PROPS:
		if float(p.h) >= MapData.PROP_BLOCK_H:
			tiles += (int(p.x1) - int(p.x0) + 1) * (int(p.y1) - int(p.y0) + 1)
	v.check("every blocking prop tile is stamped into the pathing grid",
		stamped == tiles, "stamped=%d tiles=%d" % [stamped, tiles])
	v.check("a stamped tile is blocked and an unstamped one is not",
		map.is_blocked(int(MapData.PROPS[0].x0), int(MapData.PROPS[0].y0))
			and not map.is_blocked(MapData.SPAWN_TILE.x, MapData.SPAWN_TILE.y))

	# THE ONE THE MACHINES NEEDED AND DID NOT HAVE. A machine collider is a metre of
	# layer-1 geometry that a body cannot cross and — because MACHINE_H has to stay
	# under LOS_HEIGHT — that no sight line will ever report. If the grid does not
	# carry it, the flow field routes bodies into it and `zombie._has_los` keeps its
	# straight-line override on all the way to the impact, which is a horde that
	# grinds against Juggernog for the rest of the round.
	var unstamped := ""
	for m2: Vector2 in map.machine_positions():
		if not map.is_blocked(int(m2.x), int(m2.y)):
			unstamped += "%s " % m2
	v.check("every machine collider is a wall to the flow field as well as to a body",
		unstamped.is_empty(), unstamped)

	# THE PRICE OF THAT, WRITTEN DOWN. Eight machines stand one tile from a wall, and
	# a metre-wide collider a metre from masonry is a one-abreast gap by R5's own
	# arithmetic — twelve tiles of the shipped level, measured. That is what a perk
	# alcove is and none of the twelve is a choke (the validator's `choke` invariant
	# proves no single one is the only route anywhere), but it is not free and it must
	# not grow quietly: a ninth machine dropped a tile from a wall would add two more
	# and nothing else in the suite would say a word.
	var squeeze: Array[String] = []
	for p: Vector2i in VALIDATOR._pinches(map):
		if VALIDATOR._pinch_source(map, p) == "machine":
			squeeze.append(str(p))
	v.check("the machines narrow no more of the level than the twelve tiles measured",
		squeeze.size() <= 12, "%d: %s" % [squeeze.size(), " ".join(squeeze)])

	# THE SCREEN THAT COULD MAKE AN INVARIANT VACUOUS. `_cannot_cut` is a local 3x3
	# test that decides whether the per-state box-choke check bothers to flood, and it
	# runs sixteen times per validation and therefore ~800 times per sweep. A screen
	# that started answering "cannot cut" everywhere would cost nothing, break nothing
	# and turn that invariant into a function that always passes — so it is asserted
	# from both ends, and neither end alone would do.
	#
	# SOUNDNESS first: whenever the screen waves a tile through, a real flood must
	# agree that removing the tile costs the fill exactly itself. This is the property
	# the box-choke check leans on and it is checked against the ground truth, not
	# against a restatement of the screen.
	var whole: int = VALIDATOR._flood_size(map, Vector2i(-1, -1))
	var unsound: Array[String] = []
	for p: Vector2i in VALIDATOR._pinches(map):
		if not VALIDATOR._cannot_cut(map, p):
			continue
		if VALIDATOR._flood_size(map, p) < whole - 1:
			unsound.append(str(p))
	v.check("the cut-vertex screen never waves through a tile that really does cut",
		unsound.is_empty(), "waved through: %s" % " ".join(unsound))

	# ...and DISCRIMINATION, which soundness cannot give: a healthy map has no cut
	# vertices at all, so "the screen was never wrong" is exactly what a screen stuck
	# at true would also report. Built rather than found, because the shipped level
	# does not contain the case — the tile is walled east and west with the diagonals
	# gone, which leaves the ring in two arcs and is what a one-tile corridor looks
	# like. The same tile untouched is open floor in the middle of the spawn room.
	var probe := map.clone()
	var sp := MapData.SPAWN_TILE
	var was_open: bool = VALIDATOR._cannot_cut(probe, sp)
	for d: Vector2i in [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1),
			Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]:
		probe.prop_solid[MapData.ix(sp.x + d.x, sp.y + d.y)] = 1
	v.check("...and it still tells a one-tile corridor from open floor",
		was_open and not VALIDATOR._cannot_cut(probe, sp),
		"open floor=%s, walled corridor=%s" % [was_open,
			VALIDATOR._cannot_cut(probe, sp)])


## THE ASSERTION THIS WHOLE PACKAGE COULD HAVE SHIPPED BROKEN.
##
## Giving the machines colliders on the world layer puts a solid object at the exact
## point the interaction scan aims its occlusion ray at. Get the height wrong by ten
## centimetres and every perk machine, Pack-a-Punch and the generator becomes
## permanently unbuyable — a run with no perks and no power, from a change whose only
## visible effect is that the prompt never appears. The height rule above says the
## geometry is right; this says the actual ray, through the actual physics space,
## against the actual rows, still comes back clear.
static func _machines_buyable(v: Verify, main: Node3D) -> void:
	var sys: Node = main.interact
	var map: MapData = main.map
	var blind := ""
	# EVERY ROW, not just the machines. Twenty-eight new BoxShape3Ds went onto the one
	# collision layer `_sees` casts against, and a 2.8 m column three tiles from a
	# chalk plaque occludes it exactly as thoroughly as a machine occludes itself. A
	# scan restricted to perk/pap/power would have proved the height rule and missed
	# every wall buy, trap switch and barricade in the level.
	for row: Dictionary in sys.table():
		var kind := String(row.kind)
		# A shut door's point is inside its own slab by design; `DOOR_LOS_SLACK` is
		# how it is bought, and it is not a thing a prop can break.
		if kind == "door":
			continue
		var at: Vector2 = row.pos
		var stand := _stand_near(map, at)
		if stand == Vector2.ZERO:
			blind += "%s(nowhere to stand) " % row.key
			continue
		if not sys._sees(Vector3(stand.x, MapData.EYE, stand.y), row):
			blind += "%s " % row.key
	v.check("every interactable can still be seen from the floor beside it, through "
		+ "the new prop and machine colliders", blind.is_empty(), blind)


## Where a player would stand to buy something, as a world point.
##
## The point's own tile when that is walkable — a chalk plaque and a barricade are
## both bought from the floor directly in front of them — and otherwise the nearest
## open tile around it, which is the machine case: a machine's interact point is its
## own centre and its own centre now has a metre of collider in it. Diagonals count
## because three of the perk alcoves have a wall on at least one orthogonal side.
static func _stand_near(m: MapData, at: Vector2) -> Vector2:
	var cx := floori(at.x)
	var cy := floori(at.y)
	if not m.is_blocked(cx, cy) and m.pocket_at[MapData.ix(cx, cy)] < 0:
		return Vector2(cx + 0.5, cy + 0.5)
	for d: Vector2i in MapData.NEIGHBOURS8:
		var x := cx + d.x
		var y := cy + d.y
		if m.is_blocked(x, y):
			continue
		if m.pocket_at[MapData.ix(x, y)] >= 0:
			continue
		return Vector2(x + 0.5, y + 0.5)
	return Vector2.ZERO


# --- the cost field ----------------------------------------------------------

## NOTHING IN THE GAME READS THIS FIELD YET, and the assertion names say so on
## purpose. `flow_field.solve()` is still an unweighted BFS over `is_blocked()`, so
## what is checked below is that the array is CORRECT, not that it is doing anything:
## a green line here must not be read as "wall-hug avoidance works". Turning it on is
## one edit to `flow_field.gd`, which this package does not own.
##
## Keeping the field in step with the blocking grid is worth an assertion even while
## it is inert, because the day the solver starts reading it is the day a divergence
## would become a zombie walking through a crate.
static func _cost_field(v: Verify, main: Node3D) -> void:
	var map: MapData = main.map

	# The blur, stated as the thing it is for: hugging a wall costs more than walking
	# down the middle, which is R5's published fix for corner bunching.
	var open_mid := MapData.ix(MapData.SPAWN_TILE.x, MapData.SPAWN_TILE.y)
	var against_wall := MapData.ix(3, 4)
	v.check("(unconsumed) a wall-hugging tile costs more than an open one",
		map.cost[against_wall] > map.cost[open_mid]
			and map.cost[open_mid] >= MapData.COST_BASE,
		"wall=%d open=%d" % [map.cost[against_wall], map.cost[open_mid]])

	# A machine is impassable in the cost field for the same reason it is impassable
	# in `is_blocked`: there is a metre of BoxShape3D standing on the tile. It used to
	# be COST_MACHINE dearer and still passable, which was a solver paying forty extra
	# to walk into a wall.
	var perk: Dictionary = MapData.PERKSPOTS[0]
	var pi := MapData.ix(int(perk.x), int(perk.y))
	v.check("(unconsumed) a machine tile is impassable, not merely expensive",
		map.cost[pi] >= MapData.COST_WALL, "cost=%d" % map.cost[pi])

	# The whole field against the whole blocking grid, which is the property the
	# validator's `cost-agrees` asserts per door state and this asserts on the live
	# map the game is actually running.
	var disagree := 0
	for i in map.cost.size():
		var x := i % MapData.MAPW
		var y := i / MapData.MAPW
		if (map.cost[i] >= MapData.COST_WALL) != map.is_blocked(x, y):
			disagree += 1
	v.check("the cost field and the blocking grid describe the same map",
		disagree == 0, "%d tiles disagree" % disagree)


# --- the derived table -------------------------------------------------------

## The validator derives the interactable set from the map data because it has to
## validate layouts that have never been built. That derivation is a second copy of
## `interaction_system.build()`'s arithmetic, and a second copy is a thing that
## drifts — so the two are compared here, where a live table exists.
## The comparison runs DERIVED -> LIVE and not the other way round, deliberately.
## The claim being made is "everything this file thinks is on the map really is,
## where it thinks it is" — not "this file knows about everything on the map". The
## live table also carries rows for objects that are not level data at all: the
## mystery box, whose position is run state, and the traps, which are their own
## package's. Asserting the reverse direction would make this check fail every time
## somebody adds an interactable, which is the opposite of useful.
static func _table_agrees(v: Verify, main: Node3D) -> void:
	var sys: Node = main.interact
	var live := {}
	for row: Dictionary in sys.table():
		live[String(row.key)] = row.pos
	var wrong := ""
	for row: Dictionary in VALIDATOR.interact_points(main.map):
		var k := String(row.key)
		if k.begins_with("boxspot:"):
			continue
		if not live.has(k):
			wrong += "%s(no row) " % k
			continue
		var a: Vector2 = row.pos
		var b: Vector2 = live[k]
		if not a.is_equal_approx(b):
			wrong += "%s(%s vs %s) " % [k, a, b]
	v.check("everything the validator derives really is on the map, where it says",
		wrong.is_empty(), wrong)

	# ...and the one row whose position is run state rather than level data still has
	# to be standing on one of the spots the validator checked.
	var box_at: Vector2 = live.get("box", Vector2(-1.0, -1.0))
	var on_spot := false
	for s: Vector2 in MapData.BOXSPOTS:
		if s.is_equal_approx(box_at):
			on_spot = true
	v.check("the mystery box is standing on a validated box spot", on_spot,
		"box at %s, spots %s" % [box_at, str(MapData.BOXSPOTS)])


# --- the seeded run layer ----------------------------------------------------

static func _layout_rolls(v: Verify) -> void:
	var seed_was := Rng.seed_value

	Rng.new_run(4242)
	MapData.roll_layout(Rng.stream(Rng.ROUNDS))
	var first := MapData.layout_signature()
	Rng.new_run(4242)
	MapData.roll_layout(Rng.stream(Rng.ROUNDS))
	v.check("the same seed produces the same layout",
		MapData.layout_signature() == first)

	# A run layer that produces one layout is not a run layer. Twenty seeds is enough
	# to catch a shuffle that never swaps anything, which is the way this fails.
	var seen := {}
	for s in 20:
		Rng.new_run(9000 + s)
		MapData.roll_layout(Rng.stream(Rng.ROUNDS))
		seen[MapData.layout_signature()] = true
	v.check("different seeds produce different layouts", seen.size() >= 15,
		"%d distinct layouts from 20 seeds" % seen.size())

	# THE COSMETIC STREAM MUST NOT MOVE THE LAYOUT. Constraint 6, from the direction
	# that actually bites: the layout is a gameplay draw, so it comes out of ROUNDS,
	# and a VISUAL draw between two runs of the same seed must change nothing.
	Rng.new_run(4242)
	for i in 40:
		Rng.randf(Rng.VISUAL)
	MapData.roll_layout(Rng.stream(Rng.ROUNDS))
	v.check("cosmetic draws cannot move the layout",
		MapData.layout_signature() == first)

	MapData.reset_layout()
	var canon := MapData.layout_signature()
	Rng.new_run(4242)
	MapData.roll_layout(Rng.stream(Rng.ROUNDS))
	MapData.reset_layout()
	v.check("reset_layout puts the canonical map back exactly",
		MapData.layout_signature() == canon)

	Rng.new_run(seed_was)


## THE DOOR PRICES, ON THEIR OWN AND AT A SAMPLE SIZE THAT CAN SEE THE TAIL.
##
## Separate from `_sweep` and not folded into it, which is the whole point. The map
## sweep costs a sixteen-state validation per seed and so affords 48 of them; the
## thing that can go wrong with `_roll_door_costs` is a DISTRIBUTION, and 48 samples
## of a distribution cannot see its tail. Measured: deleting the rescale entirely
## changes the dearest door from 1900 to 2300 and breaks the total once in 20 000
## rolls — and 48 seeds show neither. A roll on its own costs nothing, so this asks
## the same questions of two orders of magnitude more of them.
static func _door_prices(v: Verify) -> void:
	var seed_was := Rng.seed_value
	var totals := {}
	var hi := 0
	var lo := 999999
	var first_hi := 0
	for k in PRICE_SEEDS:
		Rng.new_run(SWEEP_FIRST + k)
		MapData.roll_layout(Rng.stream(Rng.ROUNDS))
		var total := 0
		for d: Dictionary in MapData.DOORS:
			var c := int(d.cost)
			total += c
			hi = maxi(hi, c)
			lo = mini(lo, c)
		totals[total] = int(totals.get(total, 0)) + 1
		# Doors 0 and 1 are the two whose thresholds touch the spawn room; every other
		# door is behind one of them, so the cheaper of that pair is the number a run
		# has to reach before the map opens at all.
		first_hi = maxi(first_hi,
			mini(int(MapData.DOORS[0].cost), int(MapData.DOORS[1].cost)))
	MapData.reset_layout()
	Rng.new_run(seed_was)

	v.check("a rolled door table always costs what the canonical one does, over %d rolls"
		% PRICE_SEEDS,
		totals.size() == 1 and totals.has(CANON_DOOR_TOTAL), "totals seen: %s" % str(totals))
	v.check("...and no single door absorbs the whole rescaling residual",
		hi <= DOOR_COST_MAX, "dearest door %d" % hi)
	# The floor is what makes the total conservation safe: the residual is applied with
	# a `maxi(..., DOOR_COST_MIN)` clamp, and a roll that ever reached that clamp would
	# silently stop conserving the total. 400 against a DOOR_COST_MIN of 300 says the
	# clamp has never fired.
	v.check("...and no door is ever cheap enough to reach the price floor",
		lo >= DOOR_COST_FLOOR_SEEN, "cheapest door %d, floor is %d"
			% [lo, MapData.DOOR_COST_MIN])
	v.check("...and the first door a run can walk to stays inside round one's reach",
		first_hi <= FIRST_DOOR_MAX, "dearest first door %d" % first_hi)


## THE ONE THAT DECIDES WHETHER THE RUN LAYER IS SHIPPABLE.
##
## "A seed that strands the box behind a door nobody can afford is a run the player
## cannot win, and it will happen." It cannot be reasoned about — the constraint
## interactions between a gun permutation, a perk permutation, four rescaled door
## prices and four jittered box spots are not something anyone can hold in their
## head — so it is swept instead, and the sweep runs every one of the sixteen door
## states for every seed.
static func _sweep(v: Verify) -> void:
	var seed_was := Rng.seed_value
	var t0 := Time.get_ticks_usec()
	var bad := 0
	var fallbacks := 0
	var first_fail := ""
	var reasons := {}
	# Where the roll put Juggernog, as a histogram over door depth. Not asserted —
	# Jug two purchases deep is a hard run, not a broken one, and forbidding it would
	# throw away the most interesting seeds. Printed because it is the only
	# difficulty number anything in this project can produce about the run layer: the
	# balance sim has no map (notes/balance/README.md, "Missing: No map"), so no
	# assertion about training, routing or purchase order can come from there.
	var jug_depth := {}

	for k in SWEEP_SEEDS:
		var s := SWEEP_FIRST + k
		Rng.new_run(s)
		if not MapData.roll_layout(Rng.stream(Rng.ROUNDS)):
			fallbacks += 1
		var pts: Array[Vector2] = []
		for ps: Dictionary in MapData.PERKSPOTS:
			if String(ps.k) == "jug":
				pts.append(Vector2(ps.x, ps.y))
		if not pts.is_empty():
			var d: int = VALIDATOR.point_depths(pts)[0]
			jug_depth[d] = int(jug_depth.get(d, 0)) + 1
		var fails := VALIDATOR.check_all_states()
		if fails.is_empty():
			continue
		bad += 1
		if first_fail.is_empty():
			first_fail = "seed %d: %s" % [s, fails[0]]
		for f: String in fails:
			var name := f.split(" ")[0]
			reasons[name] = int(reasons.get(name, 0)) + 1

	MapData.reset_layout()
	Rng.new_run(seed_was)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0

	v.check("every one of %d shuffled layouts is playable in all %d door states"
		% [SWEEP_SEEDS, 1 << MapData.DOORS.size()],
		bad == 0, "%d bad seeds, reasons %s, first: %s" % [bad, str(reasons), first_fail])

	# A fallback is the roll giving up and shipping the canonical map. It is not a
	# crash and it is not visible in play — the run is simply not the run the seed
	# asked for — so the only way it is ever noticed is here.
	v.check("no seed had to fall back to the canonical layout", fallbacks == 0,
		"%d of %d fell back" % [fallbacks, SWEEP_SEEDS])

	# THE HISTOGRAM BELOW WAS `{ -1: 48 }` FOR A WHOLE WAVE and nothing said a word,
	# because it was printed and not asserted. -1 is `point_depths` reporting a point
	# it never reached in any number of purchases, and every machine read -1 from the
	# moment T3.4 gave them colliders: the walk asked whether the machine's own tile was
	# reachable and a machine's own tile is `prop_solid` by construction. A printed
	# diagnostic with no assertion under it is a check that passes by not looking.
	var stranded: int = int(jug_depth.get(-1, 0))
	v.check("no seed strands Juggernog somewhere no run can walk to", stranded == 0,
		"%d of %d seeds put it out of reach" % [stranded, SWEEP_SEEDS])

	print("[mapgen] swept %d seeds x %d door states in %.0f ms (%d bad); "
		% [SWEEP_SEEDS, 1 << MapData.DOORS.size(), ms, bad]
		+ "Juggernog door depth %s" % str(jug_depth))
