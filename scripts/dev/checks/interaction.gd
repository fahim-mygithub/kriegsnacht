extends RefCounted

## Assertions for the interaction scan: what the F key can reach, and what it must
## not be able to reach.
##
## The scan is four tests over a table of rows, and three of the four exist because
## the plain distance test the port shipped with let something through. None of the
## three can be checked by looking at a frame, and two of them are invisible in
## play until a player notices they are buying through a wall — which is the sort
## of thing that ships.
##
## **Run this BEFORE `checks/systems.gd`.** Nothing here is destructive, but
## everything here is restored on the way out and `systems.gd` deliberately is not:
## it draws the director's spawn queue down and `curves.gd` re-seeds Rng and drives
## `reset_run()`. This section reads the live map's colliders, so it wants the world
## in the state the rest of the suite left it.
##
## What is deliberately NOT asserted, because a fake version is worse than an honest
## gap: nothing here presses F. `Input.is_action_just_pressed` cannot be driven
## synchronously from inside `Verify.run`, so the hold accumulator's *timing* is out
## of reach and only the per-plank effect it drives is checked. The Pack-a-Punch
## cycle is a pure clock and IS driven by hand, end to end.

## preload rather than the global class name: a freshly added script is not in the
## class registry until the editor rescans, and a headless run has no editor.
const INTERACT := preload("res://scripts/systems/interaction_system.gd")

## THE MEASUREMENT THE OCCLUSION RAY EXISTS FOR.
##
## The Corridor's corner tile (21,10) is 1.89 m from the MP40 plaque's interact
## point, which is inside the 2.0 m radius the distance test would have accepted —
## and tiles (22,10) and (22,11) are both solid, so the two points cannot see each
## other. Before the ray, the MP40 was buyable through the corner of a wall.
const CORNER := Vector2(21.5, 10.5)
const MP40_AT := Vector2(23.1, 11.5)
## Open Theatre floor a short step in front of the same plaque: the positive
## control, without which every occlusion assertion below would also pass against a
## `_sees()` that had been broken to return false forever.
const THEATRE_SIDE := Vector2(24.0, 11.5)

## Door 2 (the generator hall) and the Landing tile in front of it. Door 2 rather
## than door 0 because `Verify._flow` opens door 0 before this section runs.
const DOOR_TEST := 2
const AT_DOOR := Vector2(29.5, 18.5)


static func run(v: Verify, main: Node3D) -> void:
	_rows(v, main)
	_occlusion(v, main)
	_facing(v, main)
	_retirement(v, main)
	_rebuild(v, main)
	_pap(v, main)


static func _row(rows: Array, key: String) -> Dictionary:
	for r: Dictionary in rows:
		if String(r.get("key", "")) == key:
			return r
	return {}


# --- the table ---------------------------------------------------------------

static func _rows(v: Verify, main: Node3D) -> void:
	var sys: Node = main.interact
	var map: MapData = main.map
	var rows: Array = sys.table()

	# The scan reads all five of these off every row without checking for them, so
	# a new kind that forgets one throws inside the hot loop rather than at build.
	var incomplete := ""
	for row: Dictionary in rows:
		for f: String in ["kind", "key", "pos", "cost", "radius"]:
			if not row.has(f):
				incomplete += "%s:%s " % [row.get("key", row.get("kind", "?")), f]
	v.check("every interactable row carries the fields the scan reads",
		incomplete.is_empty(), incomplete)

	# The hold accumulator names its barricade by `key`, so two rows sharing one
	# would hand each other a half-driven plank.
	var seen := {}
	var dupes := ""
	for row: Dictionary in rows:
		var k: String = row.key
		if seen.has(k):
			dupes += k + " "
		seen[k] = true
	v.check("interactable keys are unique", dupes.is_empty(), dupes)

	# Derived from the map rather than typed in: a wall buy added to MapData with
	# no row built for it is a plaque painted on a wall that nothing can sell.
	var want: int = MapData.DOORS.size() + MapData.WALLBUYS.size() \
		+ MapData.PERKSPOTS.size() + MapData.WINDOWS.size() \
		+ 4      # the Bowie, the generator, Pack-a-Punch, the box
	v.check("every interactable in the map data has exactly one row",
		rows.size() == want, "rows=%d want=%d" % [rows.size(), want])

	# An interact point inside a wall is permanently occluded now that there is a
	# ray, so a face offset pointing the wrong way is no longer a cosmetic error —
	# it is an unbuyable object. Doors are the one documented exception: a closed
	# door's point is inside the door slab, which is the whole reason for `slack`.
	var buried := ""
	for row: Dictionary in rows:
		if String(row.kind) == "door":
			continue
		var p: Vector2 = row.pos
		if map.is_blocked(floori(p.x), floori(p.y)):
			buried += "%s " % row.key
	v.check("no interactable except a door stands inside a wall",
		buried.is_empty(), buried)

	# `live` and `sleeping` partition the table minus whatever has been bought
	# outright. A row in both is scanned twice; a row in neither is gone.
	var both := ""
	var live: Array = sys.live()
	for row: Dictionary in sys.sleeping():
		if live.has(row):
			both += "%s " % row.key
	v.check("nothing is both live and asleep at once", both.is_empty(), both)


# --- the occlusion ray -------------------------------------------------------

static func _occlusion(v: Verify, main: Node3D) -> void:
	var sys: Node = main.interact
	var map: MapData = main.map
	var rows: Array = sys.table()
	var eye: float = MapData.EYE

	var mp40: Dictionary = _row(rows, "wallbuy:mp40")
	if mp40.is_empty():
		v.check("the MP40 wall buy has a row", false)
		return

	# The three preconditions. Without all three the assertion that follows proves
	# nothing at all: the plaque has to be where the regression was measured, the
	# corner has to be inside the radius that would have sold it, and there has to
	# be wall in between.
	var at: Vector2 = mp40.pos
	v.check("the MP40 plaque sits where the regression was measured",
		at.is_equal_approx(MP40_AT), str(at))
	var d: float = CORNER.distance_to(at)
	v.check("...and the Corridor corner is inside its interact radius",
		d < float(mp40.radius), "%.3f m against %.1f m" % [d, float(mp40.radius)])
	v.check("...with solid wall on the line between the two",
		map.is_blocked(22, 10) and map.is_blocked(22, 11))

	v.check("the MP40 cannot be bought through the corner of the Corridor wall",
		not sys._sees(Vector3(CORNER.x, eye, CORNER.y), mp40))
	v.check("...and can be bought from the Theatre side, in the open",
		sys._sees(Vector3(THEATRE_SIDE.x, eye, THEATRE_SIDE.y), mp40))

	# A closed door's interact point is the centre of the door tile, which is
	# inside the door's own collider — so an unshortened ray is blocked by the very
	# thing being bought and NO door in the level is purchasable. That is a run
	# that cannot leave the Lobby, from a one-line change with no visible symptom
	# anywhere else, which is why both halves are pinned here.
	var door: Dictionary = _row(rows, "door:%d" % DOOR_TEST)
	if door.is_empty():
		v.check("door %d has a row" % DOOR_TEST, false)
		return
	v.check("door %d is still shut, so the slack test is testing something" % DOOR_TEST,
		map.door_open[DOOR_TEST] == 0)
	var stand := Vector3(AT_DOOR.x, eye, AT_DOOR.y)
	var unslacked: Dictionary = door.duplicate()
	unslacked["slack"] = 0.0
	v.check("a shut door occludes itself when the ray is not stopped short",
		not sys._sees(stand, unslacked))
	v.check("...and its own slack is exactly what keeps it buyable",
		sys._sees(stand, door))

	# The slack is a tolerance for a collider the target sits inside, not a licence
	# to shoot through walls. A door's is the largest in the table, so if any of
	# them can reach through a wall it is that one.
	var far_door: Dictionary = door.duplicate()
	far_door["pos"] = MP40_AT
	v.check("even the largest slack does not reach through a wall",
		not sys._sees(Vector3(CORNER.x, eye, CORNER.y), far_door))


# --- the facing budget -------------------------------------------------------

static func _facing(v: Verify, main: Node3D) -> void:
	var sys: Node = main.interact
	var half: float = float(INTERACT.FACING_HALF_DEG)
	var here := Vector2(10.0, 10.0)
	var face := Vector2(0.0, -1.0)      # north, in the scan's own 2-D frame

	v.check("something dead ahead is faced",
		sys._facing(here, face, here + Vector2(0.0, -2.0), 2.0))
	v.check("something directly behind is not",
		not sys._facing(here, face, here + Vector2(0.0, 2.0), 2.0))
	v.check("something square off the shoulder is not",
		not sys._facing(here, face, here + Vector2(2.0, 0.0), 2.0))

	# THE REASON THE ANCESTOR'S OWN TEST WAS NOT PORTED AS WRITTEN. `dot >= 0.35`
	# (html:2684) is a 69.5 degree half-angle, and the camera's horizontal half-frame
	# is about 53 degrees — so the ancestor will sell you something that is off the
	# side of the screen. For "you are looking at it" to mean anything the cone has
	# to stay inside the frame, and it has to keep doing so if someone widens the FOV
	# slider, which is why this reads the live camera rather than a constant.
	var cam: Camera3D = main.player.camera()
	var h_half := rad_to_deg(atan(tan(deg_to_rad(cam.fov) * 0.5) * 16.0 / 9.0))
	v.check("the facing cone is tighter than the screen is wide",
		half < h_half, "cone=%.1f half-frame=%.1f" % [half, h_half])
	v.check("...and tighter than the ancestor's 0.35 dot",
		half < rad_to_deg(acos(0.35)),
		"cone=%.1f ancestor=%.1f" % [half, rad_to_deg(acos(0.35))])

	# The size term is what replaces the ancestor's `d > 0.4` exemption, and it
	# replaces it SMOOTHLY: there is no step to fall through. Same object at the
	# same angle off centre, twice — not looked at from across the room, looked at
	# from arm's length.
	var off := Vector2(sin(deg_to_rad(50.0)), -cos(deg_to_rad(50.0)))
	v.check("a 50-degree offset is refused at range and allowed up close",
		not sys._facing(here, face, here + off * 4.0, 4.0)
			and sys._facing(here, face, here + off * 0.5, 0.5))

	# Standing on top of something is looking at it: the allowance has to be finite
	# rather than divide by a zero distance.
	v.check("a zero-distance target does not divide by zero",
		sys._facing(here, face, here, 0.0))


# --- retirement --------------------------------------------------------------

static func _retirement(v: Verify, main: Node3D) -> void:
	var sys: Node = main.interact
	var world: WorldBuilder = main.world
	var map: MapData = main.map
	var was: int = map.window_boards[0]

	# The invariant the sweep buys, stated flatly. A full barricade is not in the
	# scan at all — not filtered by it, absent from it.
	world.set_window_boards(0, 6)
	sys._sweep()
	v.check("a full barricade is not in the scan at all",
		not _live_window(sys, 0))

	# ...and it is back the tick after a zombie takes a plank off. This is the one
	# retirement that must be reversible, and neither thing that reverses it routes
	# through the interaction system: `powerup_manager` fills all fourteen at once
	# and `barricade.gd` empties them one at a time.
	world.set_window_boards(0, 3)
	sys._sweep()
	v.check("a torn-down barricade wakes back into the scan",
		_live_window(sys, 0))

	world.set_window_boards(0, 6)
	sys._sweep()
	v.check("...and sleeps again the moment it is whole, wherever the player is",
		not _live_window(sys, 0))

	# Bought-once things leave for good. A door that is open, a knife that is
	# bought and a generator that is thrown have no wake condition, so nothing
	# should be looking for one — a row that went to `_sleeping` by mistake would
	# be walked forever by a sweep that can never retire it.
	var parked := ""
	for row: Dictionary in sys.sleeping():
		if String(row.kind) != "window":
			parked += "%s " % row.key
	v.check("only barricades ever sleep", parked.is_empty(), parked)

	world.set_window_boards(0, was)
	sys._sweep()


static func _live_window(sys: Node, id: int) -> bool:
	for row: Dictionary in sys.live():
		if String(row.kind) == "window" and int(row.id) == id:
			return true
	return false


# --- the plank economy -------------------------------------------------------

## The verb the port dropped outright: `PTS_REBUILD` was declared and read by
## nothing, and the baked `board` cue was played by nothing. Rounds one to three
## are almost entirely this.
static func _rebuild(v: Verify, main: Node3D) -> void:
	var sys: Node = main.interact
	var world: WorldBuilder = main.world
	var map: MapData = main.map
	var row: Dictionary = _row(sys.table(), "window:0")
	if row.is_empty():
		v.check("barricade 0 has a row", false)
		return

	var was: int = map.window_boards[0]
	var pts_was := Game.points
	var earned_was := Game.points_earned
	var dbl_was := Game.dbl_points
	Game.dbl_points = 0.0

	world.set_window_boards(0, 0)
	var nailed := 0
	var paid := 0
	for i in 8:
		Game.points = 0
		if sys._rebuild_board(row):
			nailed += 1
			paid += Game.points
	v.check("six planks go on and the seventh does not",
		nailed == 6 and map.window_boards[0] == 6,
		"nailed=%d boards=%d" % [nailed, map.window_boards[0]])
	v.check("each plank pays the canon rebuild points",
		paid == 6 * Game.PTS_REBUILD, "paid=%d" % paid)

	# The whole barricade, as a price in seconds and a payout. Both halves are load
	# bearing: too fast and a player out-ticks a zombie's teardown and the round 1-5
	# barricade stops being a clock; too slow and nobody ever does it.
	v.check("a full barricade is about two seconds of holding for sixty points",
		v.near(6.0 * float(INTERACT.REBUILD_PER_BOARD), 2.04, 0.001)
			and 6 * Game.PTS_REBUILD == 60,
		"%.2f s, %d points" % [6.0 * float(INTERACT.REBUILD_PER_BOARD), 6 * Game.PTS_REBUILD])

	# Nailing a plank back on over a zombie's hands would let a player out-tick the
	# teardown outright, so a barricade with somebody at it offers nothing at all —
	# `none` rather than an unaffordable prompt, so the scan skips it and something
	# live behind the player can still win.
	var workers_was: int = map.window_workers[0]
	world.set_window_boards(0, 2)
	map.window_workers[0] = 1
	var busy: Dictionary = sys._state_of(row)
	map.window_workers[0] = 0
	var quiet: Dictionary = sys._state_of(row)
	v.check("a barricade being torn down cannot be repaired, and is not merely greyed out",
		busy.get("none", false) and not quiet.get("none", false), str(busy))
	map.window_workers[0] = workers_was

	world.set_window_boards(0, was)
	sys._sweep()
	Game.points = pts_was
	Game.points_earned = earned_was
	Game.dbl_points = dbl_was


# --- Pack-a-Punch ------------------------------------------------------------

## The machine is a cycle, not a vending slot, and the cycle is a pure clock — so
## unlike the hold accumulator it can be driven end to end from here.
static func _pap(v: Verify, main: Node3D) -> void:
	var sys: Node = main.interact
	var player: Player = main.player
	var row: Dictionary = _row(sys.table(), "pap")
	if row.is_empty():
		v.check("Pack-a-Punch has a row", false)
		return

	var pts_was := Game.points
	var earned_was := Game.points_earned
	var power_was := Game.power_on
	var state_was: String = sys.pap_state()

	Game.power_on = true
	Game.points = 10000
	sys._pap_state = "idle"
	sys._pap_key = ""

	var key: String = player.current_gun().key
	var cost: int = int(INTERACT.PAP_COST)
	sys._do_interact(row, {"cost": cost})
	v.check("paying starts the machine and takes the points",
		String(sys.pap_state()) == "working" and Game.points == 10000 - cost,
		"state=%s points=%d" % [sys.pap_state(), Game.points])

	# By KEY, not by a reference into `player.guns`. Nothing the player does to
	# their loadout mid-cycle can leave the machine holding a Dictionary that is no
	# longer theirs.
	v.check("the machine remembers the weapon by key rather than by slot",
		String(sys._pap_key) == key, str(sys._pap_key))

	# The cycle is a real wait rather than a swap dressed up as one.
	sys._tick_pap(float(INTERACT.PAP_WORK) * 0.5)
	v.check("it is still working half way through",
		String(sys.pap_state()) == "working")
	sys._tick_pap(float(INTERACT.PAP_WORK) * 0.5 + 0.01)
	v.check("...and holds the weapon out at the end of it",
		String(sys.pap_state()) == "ready")

	# THE ONE THAT MATTERS. Five thousand points must not be losable by walking
	# away, so there is no timeout for it to be lost to. An hour of ticking has to
	# leave the machine exactly where it was.
	for i in 60:
		sys._tick_pap(60.0)
	v.check("a finished cycle never expires", String(sys.pap_state()) == "ready")

	# Collecting upgrades the weapon in place and empties the machine.
	sys._do_interact(row, {"cost": 0})
	var upgraded := false
	for g: Dictionary in player.guns:
		if String(g.key) == key and bool(g.pap):
			upgraded = true
	v.check("collecting upgrades the weapon and empties the machine",
		upgraded and String(sys.pap_state()) == "idle",
		"upgraded=%s state=%s" % [upgraded, sys.pap_state()])

	# ...and the machine has nothing left to sell for that weapon, rather than
	# taking another five thousand for the same upgrade.
	var st: Dictionary = sys._state_of(row)
	v.check("an already-upgraded weapon is refused rather than sold twice",
		st.get("none", false), str(st))

	# An unpowered machine says so and cannot be paid. It stays visible — `none`
	# would be silence in front of a machine the player is standing at — but the
	# scan must never let it take money.
	Game.power_on = false
	sys._pap_state = "idle"
	sys._pap_key = ""
	var dark: Dictionary = sys._state_of(row)
	v.check("an unpowered Pack-a-Punch explains itself and charges nothing",
		int(dark.get("cost", -1)) == 0 and String(dark.get("label", "")).contains("power"),
		str(dark))

	for g: Dictionary in player.guns:
		if String(g.key) == key:
			g.pap = false
	sys._pap_state = state_was
	sys._pap_key = ""
	Game.power_on = power_was
	Game.points = pts_was
	Game.points_earned = earned_was
