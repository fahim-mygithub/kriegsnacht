extends RefCounted

## Assertions for the electric traps, the widened perk roster, and the HUD's perk
## strip.
##
## The three belong together because they are the same package and, more usefully,
## because two of them are things nobody would ever catch by playing. A trap that
## kills half a metre outside its own gate looks like a zombie dying at a doorway,
## which is what it is supposed to look like. A perk badge that is one purchase
## behind looks like the purchase having failed — the player buys it again, cannot,
## and concludes the machine is broken.
##
## **The strip assertion is a REGRESSION TEST and was confirmed to fail against the
## code it replaced.** `hud._refresh_perks()` was reachable from `_on_weapon` and
## from nowhere else, so `_perk_strip_needs_no_weapon_event` was run against the
## unfixed HUD and reported 0 badges where it wanted 1. It is the only check here
## that is about a bug rather than about a rule.
##
## Nothing in this file needs a rendered frame, a pointer or wall-clock time. What
## it does need is a live tree — the traps sweep reads the `zombies` group — so
## every body it makes is added to `main` and freed before the function returns,
## which is the same shape verify.gd's own `_eyes` and `_losable` use.

## preload rather than the global class name: a freshly added script is not in the
## class registry until the editor rescans, and a headless run has no editor.
const TRAPS := preload("res://scripts/systems/traps.gd")

## A tick long enough that a clock cannot be mistaken for a rounding error and
## short enough that ACTIVE / COOLDOWN still take several of them.
const STEP := 0.5


static func run(v: Verify, main: Node3D) -> void:
	_perk_strip(v, main)
	_perk_roster(v, main)
	_perk_effects(v, main)
	_trap_siting(v, main)
	_trap_volume(v, main)
	_trap_cycle(v, main)
	_trap_paint(v, main)
	_trap_economy(v, main)


# --- part 1: the HUD strip ----------------------------------------------------

## THE REGRESSION TEST. Everything is restored on the way out, because the suite's
## later sections read `Game.perks` and one of them counts on it being empty.
static func _perk_strip(v: Verify, main: Node3D) -> void:
	var h: Node = main.hud
	var p: Player = main.player
	var perks_was: Dictionary = Game.perks.duplicate()

	Game.perks.clear()
	h._process(0.016)
	var empty: int = h._perks.get_child_count()

	# The weapon events are COUNTED, not merely avoided. "The badge appeared" is
	# only the fix if nothing fired `weapon_changed` in the meantime, and the two
	# call sites that used to hide this bug did it by firing exactly that signal —
	# `_go_down`'s spare emit in player.gd, and `_force_slot` on the way past. An
	# assertion that did not count would pass against the broken code the moment
	# anything else in the frame happened to touch a weapon.
	var events: Array[int] = [0]
	var counter := func(_g: Dictionary) -> void:
		events[0] += 1
	p.weapon_changed.connect(counter)

	Game.perks["jug"] = true
	h._process(0.016)
	var one: int = h._perks.get_child_count()
	Game.perks["speed"] = true
	Game.perks["dtap"] = true
	h._process(0.016)
	var three: int = h._perks.get_child_count()
	# Losing one has to land as well: `_go_down` erases `revive` and nothing else
	# tells the strip.
	Game.perks.erase("speed")
	h._process(0.016)
	var two: int = h._perks.get_child_count()

	p.weapon_changed.disconnect(counter)

	v.check("buying a perk lights its badge with no weapon event at all",
		empty == 0 and one == 1 and three == 3 and two == 2 and events[0] == 0,
		"badges %d/%d/%d/%d, weapon events %d" % [empty, one, three, two, events[0]])

	# The other half of the same fix. A rebuild used to leave the outgoing badges in
	# the container until the end of the frame, so the strip drew at double length
	# for one frame every time it was rebuilt — which, on the old driver, was once
	# per shot.
	var stale := false
	for c in h._perks.get_children():
		if c.is_queued_for_deletion():
			stale = true
	v.check("a strip rebuild leaves nothing queued for deletion behind it", not stale)

	Game.perks.clear()
	Game.perks.merge(perks_was)
	h._process(0.016)


# --- part 3: the roster -------------------------------------------------------

static func _perk_roster(v: Verify, main: Node3D) -> void:
	# The cap has to BIND. It has been 4 since Milestone 1 and the map offered
	# exactly four machines, so "four at once" described the inventory rather than
	# limiting it — `curves.gd::_perks` says so and predicts this exact day.
	v.check("the roster is larger than the cap, so the cap is a choice",
		Weapons.PERKDEF.size() > Game.PERK_CAP,
		"%d perks, cap %d" % [Weapons.PERKDEF.size(), Game.PERK_CAP])
	v.check("the map offers a machine for every perk in the roster",
		MapData.PERKSPOTS.size() == Weapons.PERKDEF.size(),
		"%d machines, %d perks" % [MapData.PERKSPOTS.size(), Weapons.PERKDEF.size()])

	# Every row has to be complete, or the first walk past the machine throws
	# instead of the build failing. Two of the six are new and neither was written
	# by copying a whole row.
	var incomplete := ""
	for k: String in Weapons.PERKDEF:
		var d: Dictionary = Weapons.PERKDEF[k]
		for f: String in ["name", "cost", "col", "col2", "letter", "blurb"]:
			if not d.has(f):
				incomplete += "%s.%s " % [k, f]
	v.check("every perk row carries a full definition", incomplete.is_empty(), incomplete)

	# The cap itself, exercised through the real gate rather than by reading the
	# constant. `can_take_perk` is what the machine's prompt and its purchase both
	# consult, so this is the rule as the player meets it.
	var perks_was: Dictionary = Game.perks.duplicate()
	Game.perks.clear()
	var held: Array[String] = []
	var refused := ""
	for k: String in Weapons.PERKDEF:
		if Game.can_take_perk(k):
			Game.perks[k] = true
			held.append(k)
		else:
			refused += k + " "
	v.check("the fifth perk is refused, whichever four came first",
		held.size() == Game.PERK_CAP and not refused.is_empty(),
		"held %s, refused %s" % [str(held), refused])
	# ...and a perk already held is refused too, which is the other half of
	# `can_take_perk` and the reason a full player cannot re-buy for a free slot.
	v.check("a perk already held cannot be taken again",
		not Game.can_take_perk(held[0]), held[0])
	Game.perks.clear()
	Game.perks.merge(perks_was)


## What the two new perks actually do, checked through the accessors rather than
## against the constants — a constant nothing reads is the failure mode these two
## are most exposed to, because their consumers are one line each in player.gd.
static func _perk_effects(v: Verify, main: Node3D) -> void:
	var perks_was: Dictionary = Game.perks.duplicate()
	# The real player, because the two new perks are measured through its own
	# movement and inventory code rather than through the accessors they call.
	var h: Node = main.hud
	var p: Player = main.player
	Game.perks.clear()

	v.check("unperked, nothing is scaled",
		v.near(Weapons.move_speed_scale(), 1.0)
			and v.near(Weapons.sprint_drain_scale(), 1.0)
			and v.near(Weapons.sprint_recover_scale(), 1.0)
			and Weapons.gun_slots() == Weapons.BASE_SLOTS)

	Game.perks["stamin"] = true
	# THE ONE THAT KEEPS THE GAME LOSABLE. Milestone 1 made sprint finite precisely
	# because a player who cannot be caught cannot lose, and a movement perk is the
	# obvious way for that to come back — through a 2000-point purchase instead of
	# through a constant. A *walking* Stamin-Up player must still be slower than the
	# fastest zombie class. The margin is asserted rather than the multiplier, so
	# retuning Player.SPEED or Game.SPEED_SPRINT cannot silently cross it.
	var walk := Player.SPEED * Weapons.move_speed_scale()
	v.check("Stamin-Up cannot outwalk the sprint class",
		walk < Game.SPEED_SPRINT,
		"perked walk %.3f vs class %.3f" % [walk, Game.SPEED_SPRINT])
	# ...and the player is actually moving at that speed. The bound above is on the
	# constants; this is the line that applies them. See `_walk_speed`.
	var walked := _walk_speed(p)
	v.check("the perked walk speed is the one the player actually moves at",
		v.near(walked, walk, 0.02), "moved %.3f m/s, expected %.3f" % [walked, walk])
	v.check("...and it is not within a hair of doing so either",
		Game.SPEED_SPRINT - walk > 0.05,
		"margin %.4f m/s" % (Game.SPEED_SPRINT - walk))

	Game.perks.clear()

	# Sprint is a duty cycle, not a duration: draining at DRAIN and recovering at
	# RECOVER, the perk has to move the ratio or it is only a longer wait.
	#
	# MEASURED THROUGH `Player._update_sprint`, NOT RECOMPUTED FROM ITS CONSTANTS,
	# and the difference is the whole value of this check. What was here read
	#
	#     1.0 / (Player.SPRINT_DRAIN * Weapons.sprint_drain_scale())
	#
	# which is player.gd:587's own expression copied into the assertion — so it
	# asserted that `sprint_drain_scale()` returns what `STAMIN_DRAIN_MULT` says,
	# against itself, and never once asked whether the player multiplies by it.
	# Deleting `* Weapons.sprint_drain_scale()` from player.gd left every one of
	# these passing. Driving the real function is the only version that can fail
	# for the reason the check is named for.
	var bare := _duty(p)
	Game.perks["stamin"] = true
	var perked := _duty(p)
	v.check("Stamin-Up lengthens the run and shortens the wait, in the player",
		float(perked.run) > float(bare.run) and float(perked.wait) < float(bare.wait)
			and float(perked.duty) > float(bare.duty),
		"run %.2f->%.2f s, wait %.2f->%.2f s, duty %.2f->%.2f"
			% [bare.run, perked.run, bare.wait, perked.wait, bare.duty, perked.duty])
	# The multipliers have to be the ones weapons.gd documents, and the tolerance is
	# one tick of the 60 Hz drive rather than a round number.
	v.check("the measured bar matches the numbers weapons.gd states",
		v.near(float(bare.run), 4.2, 0.02) and v.near(float(perked.run), 8.4, 0.02)
			and v.near(float(bare.wait), 4.0, 0.02)
			and v.near(float(perked.wait), 2.667, 0.02),
		"run %.3f/%.3f wait %.3f/%.3f" % [bare.run, perked.run, bare.wait, perked.wait])
	# ...but it must not become "you never stop sprinting", which would be the
	# finite-sprint change undone by another route.
	v.check("Stamin-Up is not infinite sprint", float(perked.duty) < 0.9,
		"duty %.3f" % perked.duty)
	Game.perks.clear()

	# MULE KICK THROUGH `give_gun`, which is what a wall buy, the box and the
	# console all call — not through `Weapons.gun_slots()`, which is the setter this
	# would otherwise be asserting against its own getter. player.gd:1250 is the line
	# under test; reading the accessor back cannot see it.
	var guns_before: Array[Dictionary] = p.guns.duplicate()
	var slot_before: int = p.slot
	var bare_held := _fill_slots(p)
	Game.perks["mule"] = true
	var mule_held := _fill_slots(p)
	Game.perks.clear()
	p.guns = guns_before
	p.slot = slot_before
	v.check("Mule Kick is exactly one more slot, taken through give_gun",
		bare_held == Weapons.BASE_SLOTS and mule_held == Weapons.BASE_SLOTS + 1,
		"held %d bare, %d with mule" % [bare_held, mule_held])

	# The HUD's [Q] line reads the NEXT gun in the swap cycle rather than "the other
	# one", because `_swap_weapon` steps `(slot + 1) % size` and with three guns the
	# old `guns[1 - slot]` named the wrong weapon from two of the three slots — and
	# named none at all, because it was gated on `size() == 2`. Checked against the
	# swap the player actually performs.
	var guns_was: Array[Dictionary] = p.guns.duplicate()
	var slot_was: int = p.slot
	p.guns = [Weapons.make_gun("m1911", false), Weapons.make_gun("mp40", false),
		Weapons.make_gun("m14", false)]
	var named: Array[String] = []
	var wanted: Array[String] = []
	for i in 3:
		p.slot = i
		h._on_weapon(p.current_gun())
		named.append(h._altw.text)
		var nxt: Dictionary = p.guns[(i + 1) % 3]
		wanted.append(String(nxt.def.name))
	var lines_ok := true
	for i in 3:
		if not named[i].contains(wanted[i]):
			lines_ok = false
	v.check("the [Q] line names the gun the swap key will actually hand over",
		lines_ok, "%s want %s" % [str(named), str(wanted)])
	v.check("a three-gun loadout says there is a third", named[0].contains("+1"),
		named[0])
	p.guns = guns_was
	p.slot = slot_was
	h._on_weapon(p.current_gun())
	Game.perks.merge(perks_was)


# --- part 2: the traps --------------------------------------------------------

## Where the three gates are, checked against the live map rather than against the
## table they were written from. A rect with a solid tile in it is half a gate
## behind a wall, and a switch inside its own kill volume is a switch you have to
## stand in the trap to reach.
static func _trap_siting(v: Verify, main: Node3D) -> void:
	var m: MapData = main.map
	var buried := ""
	var inside := ""
	var unreachable := ""
	for row: Dictionary in TRAPS.SPOTS:
		var rect: Rect2 = row.rect
		var key: String = row.key
		var x := int(floor(rect.position.x))
		while x < int(ceil(rect.end.x)):
			var y := int(floor(rect.position.y))
			while y < int(ceil(rect.end.y)):
				if m.is_blocked(x, y):
					buried += "%s(%d,%d) " % [key, x, y]
				y += 1
			x += 1
		var sw: Vector2 = row.switch
		if rect.has_point(sw):
			inside += key + " "
		if m.is_blocked(int(floor(sw.x)), int(floor(sw.y))):
			unreachable += "%s(%.1f,%.1f) " % [key, sw.x, sw.y]
	v.check("every trap volume is open floor end to end", buried.is_empty(), buried)
	v.check("no trap switch is inside its own kill volume", inside.is_empty(), inside)
	v.check("every trap switch stands on a tile the player can occupy",
		unreachable.is_empty(), unreachable)

	# The switch has to be reachable from outside the volume as well as be outside
	# it: the interaction scan's radius is 2.0 m and it measures from the player's
	# tile, so a switch further than that from anywhere standable is a switch with
	# no prompt. Measured against the nearest open tile that is not in the rect.
	var far := ""
	for row: Dictionary in TRAPS.SPOTS:
		var sw: Vector2 = row.switch
		var rect: Rect2 = row.rect
		var best := 1e9
		for dx in [-2, -1, 0, 1, 2]:
			for dy in [-2, -1, 0, 1, 2]:
				var tx := int(floor(sw.x)) + int(dx)
				var ty := int(floor(sw.y)) + int(dy)
				if m.is_blocked(tx, ty):
					continue
				var here := Vector2(float(tx) + 0.5, float(ty) + 0.5)
				if rect.has_point(here):
					continue
				best = minf(best, here.distance_to(sw))
		if best > 2.0:
			far += "%s(%.2f m) " % [row.key, best]
	v.check("every trap switch can be reached from outside the trap",
		far.is_empty(), far)

	# Three gates, and the reference's own count for Der Riese. Asserted so that
	# deleting one to fix a placement problem is a decision somebody has to make
	# rather than something that quietly happens.
	v.check("there are three gates and every key is distinct",
		TRAPS.SPOTS.size() == 3 and _keys(TRAPS.SPOTS).size() == 3,
		str(_keys(TRAPS.SPOTS)))

	# THE PRICE. traps.gd's header answers the brief's "is it worth its cost against
	# the same points a player would spend on a wall-buy" by making the two numbers
	# the same, and says so — but `const TRAP_COST := 1000` restates the figure
	# rather than reading it, because constraint 3 makes a `const` initialised from a
	# call a hard parse error. A restated number with nothing holding it is a number
	# that drifts, so this is the thing holding it, and the header points here.
	var mp40 := -1
	for w: Dictionary in MapData.WALLBUYS:
		if String(w.gun) == "mp40":
			mp40 = int(w.cost)
	v.check("the trap is priced at the MP40 wall buy", TRAPS.TRAP_COST == mp40,
		"trap %d, mp40 %d" % [TRAPS.TRAP_COST, mp40])

	# ...and in the state a real run is in rather than only the canonical one. The
	# run layer shuffles which wall each gun hangs on and the price travels with the
	# gun (map_data.gd:99), so this should hold across every roll — asserted rather
	# than assumed, because "the price travels with the weapon" is a property of the
	# shuffle that a future shuffle could stop having.
	# A local generator, so this sweep draws from no `Rng` stream at all and cannot
	# move a seeded run. `roll_layout` reads only the generator it is handed.
	var rng := RandomNumberGenerator.new()
	var drifted := 0
	for k in 64:
		rng.seed = 5000 + k
		MapData.roll_layout(rng)
		for w: Dictionary in MapData.WALLBUYS:
			if String(w.gun) == "mp40" and int(w.cost) != TRAPS.TRAP_COST:
				drifted += 1
	MapData.reset_layout()
	v.check("...and stays priced at it under every shuffled layout",
		drifted == 0, "%d of 64 layouts moved it" % drifted)

	# THE GATE'S ORIENTATION, WHICH NOTHING ELSE HERE CAN SEE. `axis` decides which
	# way the arc sheet and its two posts are turned, and the kill test is a
	# point-in-rect that is completely indifferent to it — so transposing "z" and
	# "x" on any row rotates that gate ninety degrees into the walls and every other
	# assertion in this file still passes. It was checked: flipping the Corridor to
	# "x" cost nothing and the frame showed a gate side-on across the corridor.
	#
	# The rule is that the sheet spans the choke's WIDE dimension, because a band a
	# player walks through is thin along the direction of travel and wide across it.
	# The Tunnel's rect is square, which is exactly why the field is declared in the
	# table rather than inferred from the rect's proportions — so a square rect is
	# the one case this cannot judge, and it says so instead of pretending.
	var turned := ""
	for row: Dictionary in TRAPS.SPOTS:
		var rect: Rect2 = row.rect
		if v.near(rect.size.x, rect.size.y, 0.001):
			continue
		var wide_axis := "x" if rect.size.x > rect.size.y else "z"
		if String(row.axis) != wide_axis:
			turned += "%s(%s, rect %.0fx%.0f) " % [row.key, row.axis,
				rect.size.x, rect.size.y]
	v.check("every non-square gate is turned across its choke, not along it",
		turned.is_empty(), turned)


## The one that matters: inside dies, outside does not.
static func _trap_volume(v: Verify, main: Node3D) -> void:
	var t := _mount(main)
	var power_was: bool = Game.power_on
	Game.power_on = true

	var row: Dictionary = TRAPS.SPOTS[0]
	var rect: Rect2 = row.rect
	var mid := rect.get_center()

	# Four bodies: dead centre, a hair inside the west face, a hair outside it, and
	# one two metres clear. The pair straddling the face is the assertion — "inside
	# dies" is easy and "the edge is where the table says it is" is what actually
	# goes wrong.
	var at_centre := _body(main, mid)
	var just_in := _body(main, Vector2(rect.position.x + 0.05, mid.y))
	var just_out := _body(main, Vector2(rect.position.x - 0.05, mid.y))
	var well_out := _body(main, Vector2(rect.position.x - 2.0, mid.y))

	v.check("the trap arms with the power on", t.arm(String(row.key)))
	t.tick(0.016)

	v.check("a trap kills everything inside its volume",
		at_centre.state == Zombie.State.DYING and just_in.state == Zombie.State.DYING,
		"centre=%s edge=%s" % [at_centre.state, just_in.state])
	v.check("a trap kills nothing outside it, not even five centimetres outside",
		just_out.state != Zombie.State.DYING and well_out.state != Zombie.State.DYING,
		"just_out=%s well_out=%s" % [just_out.state, well_out.state])
	v.check("the kill count only counts what it killed", t.kills() == 2,
		"got %d" % t.kills())

	# The other two gates are the same code with different rectangles, so what is
	# worth checking is that each one's rectangle is where the SPOTS row says — a
	# transposed axis would put the Landing's gate across the wrong two metres and
	# nothing else here would notice.
	var wrong := ""
	for i in range(1, TRAPS.SPOTS.size()):
		var r2: Dictionary = TRAPS.SPOTS[i]
		var rr: Rect2 = r2.rect
		var body := _body(main, rr.get_center())
		var outside := _body(main, rr.get_center() + Vector2(rr.size.x, rr.size.y))
		t.arm(String(r2.key))
		t.tick(0.016)
		if body.state != Zombie.State.DYING or outside.state == Zombie.State.DYING:
			wrong += String(r2.key) + " "
		body.queue_free()
		outside.queue_free()
	v.check("every gate kills inside its own rectangle and only there",
		wrong.is_empty(), wrong)

	for z: Zombie in [at_centre, just_in, just_out, well_out]:
		z.queue_free()
	Game.power_on = power_was
	_unmount(main, t)


## Arm, live, expire, cool, idle — and every refusal in between.
static func _trap_cycle(v: Verify, main: Node3D) -> void:
	var t := _mount(main)
	var power_was: bool = Game.power_on

	Game.power_on = false
	v.check("a trap cannot be armed without the power",
		not t.arm("corridor") and t.state_of("corridor") == "idle")

	Game.power_on = true
	v.check("an idle trap arms", t.arm("corridor") and t.state_of("corridor") == "live")
	v.check("an armed trap refuses to be armed again",
		not t.arm("corridor"), "double-arm accepted")
	# ...and it must not be refunded or extended by the attempt either.
	var left: float = t.active_left("corridor")
	v.check("the refused re-arm neither extends nor shortens the window",
		v.near(left, TRAPS.ACTIVE, 0.001), "%.3f of %.3f" % [left, TRAPS.ACTIVE])

	var steps := 0
	while t.state_of("corridor") == "live" and steps < 1000:
		t.tick(STEP)
		steps += 1
	v.check("the window closes on time",
		v.near(float(steps) * STEP, TRAPS.ACTIVE, STEP + 0.001),
		"%d steps of %.2f s against a %.1f s window" % [steps, STEP, TRAPS.ACTIVE])
	v.check("it goes straight onto cooldown rather than back to idle",
		t.state_of("corridor") == "cooldown", t.state_of("corridor"))
	v.check("a cooling trap refuses to be armed", not t.arm("corridor"))

	steps = 0
	while t.state_of("corridor") == "cooldown" and steps < 1000:
		t.tick(STEP)
		steps += 1
	v.check("the cooldown runs from the moment it switched off, not from the buy",
		v.near(float(steps) * STEP, TRAPS.COOLDOWN, STEP + 0.001),
		"%d steps of %.2f s against a %.1f s cooldown" % [steps, STEP, TRAPS.COOLDOWN])
	v.check("and then it can be bought again",
		t.state_of("corridor") == "idle" and t.arm("corridor"))

	# THE DUTY CYCLE IS THE BALANCE LEVER. A trap that is lit more than it is dark
	# is a wall the round has to get through rather than a tool the player spends
	# points on, and every sim number in the header was measured at this ratio.
	var duty := TRAPS.ACTIVE / (TRAPS.ACTIVE + TRAPS.COOLDOWN)
	v.check("a trap is dark for more than twice as long as it is lit",
		duty < 1.0 / 3.0, "duty %.3f" % duty)

	# Three gates, three clocks. One shared timer would let a player pay once and
	# light the map, which is the cheapest possible way for this to be broken.
	v.check("arming one gate does not arm the others",
		t.state_of("tunnel") == "idle" and t.state_of("landing") == "idle",
		"tunnel=%s landing=%s" % [t.state_of("tunnel"), t.state_of("landing")])

	Game.power_on = power_was
	_unmount(main, t)


## WHAT THE GATE LOOKS LIKE, WHICH IS THE ONLY READOUT IT HAS.
##
## There is no HUD element for a trap. The posts are always-drawn geometry and
## their emission is the whole of what tells a player across the room whether a
## gate is armed, so "lit" and "live" have to be the same bit. They were not: one
## `_mat_post` was shared by all six posts and `_paint()` wrote it only on the
## live branch, so arming the Corridor lit the Tunnel's posts through a wall and
## every post on the map stayed lit for the rest of the run after the first
## activation. Both were plain in `--shot` and invisible to all forty assertions
## that existed before this one — which is the reason this section reads the
## material off the MeshInstance3D the renderer actually draws rather than a field
## on the row.
static func _trap_paint(v: Verify, main: Node3D) -> void:
	var t := _mount(main)
	var power_was: bool = Game.power_on
	Game.power_on = true

	v.check("every gate is dark before anything is armed",
		_lit(t).is_empty(), str(_lit(t)))

	var first: String = String(TRAPS.SPOTS[0].key)
	t.arm(first)
	t.tick(0.016)
	v.check("arming one gate lights that gate and only that gate",
		_lit(t) == [first], "lit %s" % str(_lit(t)))

	# Straight past the window in one step. The state machine is `_trap_cycle`'s
	# business; what this wants is the frame after the last live one.
	t.tick(TRAPS.ACTIVE + 0.1)
	v.check("a gate that has run out goes dark instead of staying lit",
		t.state_of(first) == "cooldown" and _lit(t).is_empty(),
		"state %s, lit %s" % [t.state_of(first), str(_lit(t))])

	# The arc sheet and the light are hidden by an instance flag rather than by a
	# material, so they are the half of the visual that never had the bug — checked
	# anyway, because a fix that moved the posts onto their own material could just
	# as easily have moved the wrong write with them.
	var mismatched := ""
	for row: Dictionary in t._live:
		var live: bool = float(row.t) > 0.0
		if row.arc.visible != live or row.light.visible != live:
			mismatched += String(row.key) + " "
	v.check("the arc and its light agree with the clock at every gate",
		mismatched.is_empty(), mismatched)

	# THE TABLE SAYS ONE THING; THIS READS WHAT WAS BUILT. `_trap_siting` checks that
	# `axis` is declared consistently with the rect, which catches a bad table row —
	# it cannot catch `_build_one` applying it backwards, because the quarter turn
	# and the post offsets are two separate expressions and only one of them is
	# gated on `along_z`. Measured off the world AABB of the mesh the renderer draws.
	var wrong_way := ""
	for row: Dictionary in t._live:
		var rect: Rect2 = row.rect
		var arc: MeshInstance3D = row.arc
		var box := arc.global_transform * arc.get_aabb()
		var along_z: bool = String(_axis_of(String(row.key))) == "z"
		# What it must span, and what it must be thin across.
		var want_span: float = rect.size.y if along_z else rect.size.x
		var got_span: float = box.size.z if along_z else box.size.x
		var got_thin: float = box.size.x if along_z else box.size.z
		if not v.near(got_span, want_span, 0.02) or got_thin > 0.05:
			wrong_way += "%s(span %.2f want %.2f, thickness %.2f) " % [
				row.key, got_span, want_span, got_thin]
		# ...and the posts stand at the two ends of that span rather than beside it.
		var posts: Array = row.posts
		var a: Vector3 = posts[0].position
		var b: Vector3 = posts[1].position
		var apart: float = absf(a.z - b.z) if along_z else absf(a.x - b.x)
		var sideways: float = absf(a.x - b.x) if along_z else absf(a.z - b.z)
		if apart < want_span - TRAPS.POST_W - 0.01 or sideways > 0.001:
			wrong_way += "%s(posts %.2f apart, %.2f sideways) " % [
				row.key, apart, sideways]
	v.check("every gate is built turned the way its row declares",
		wrong_way.is_empty(), wrong_way)

	Game.power_on = power_was
	_unmount(main, t)


## The declared axis for a gate key, read from the table rather than from the built
## row — `_live` deliberately does not carry it, because nothing in the running game
## needs it after the geometry exists.
static func _axis_of(key: String) -> String:
	for row: Dictionary in TRAPS.SPOTS:
		if String(row.key) == key:
			return String(row.axis)
	return ""


## The keys of every gate whose posts are emitting, read off the drawn instance.
static func _lit(t: Node3D) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in t._live:
		var post: MeshInstance3D = row.posts[0]
		var mat: StandardMaterial3D = post.material_override
		if mat.emission_energy_multiplier > 0.0:
			out.append(String(row.key))
	return out


## The rule that stops the trap being an economy: a trap kill pays nothing, and
## draws nothing it should not.
static func _trap_economy(v: Verify, main: Node3D) -> void:
	var t := _mount(main)
	var power_was: bool = Game.power_on
	var points_was: int = Game.points
	var earned_was: int = Game.points_earned
	var kills_was: int = Game.kills
	Game.power_on = true

	# `trap_clearing` must exist and must be the thing `add_points` reads. Asserted
	# separately from the kill below so that a missing flag reads as a missing flag
	# rather than as a trap that pays.
	Game.trap_clearing = true
	Game.points = 1000
	Game.points_earned = 0
	Game.add_points(500)
	var gated: bool = Game.points == 1000 and Game.points_earned == 0
	Game.trap_clearing = false
	Game.add_points(500)
	var ungated: bool = Game.points == 1500
	v.check("Game.trap_clearing suppresses a payout and clearing it restores one",
		gated and ungated, "gated=%s ungated=%s points=%d" % [gated, ungated, Game.points])

	# ...and the trap actually uses it. Six bodies in the gate, and not one point.
	var row: Dictionary = TRAPS.SPOTS[0]
	var rect: Rect2 = row.rect
	var mid := rect.get_center()
	var bodies: Array[Zombie] = []
	for i in 6:
		bodies.append(_body(main, Vector2(mid.x, rect.position.y + 0.2 + float(i) * 0.5)))
	Game.points = 4242
	Game.points_earned = 77
	t.arm(String(row.key))
	t.tick(0.016)
	v.check("six bodies in the gate and the wallet has not moved",
		Game.points == 4242 and Game.points_earned == 77 and t.kills() == 6,
		"points=%d earned=%d kills=%d" % [Game.points, Game.points_earned, t.kills()])
	v.check("the flag does not survive the sweep that set it",
		not Game.trap_clearing)

	for z: Zombie in bodies:
		z.queue_free()

	# Constraint 6, from the same direction verify.gd's `_impacts` takes with fx.gd:
	# the arc's flicker, its pitch and its crackle cadence are all functions of the
	# clock, so a live trap must draw from NO stream at all. Weapon spread rides
	# VISUAL, so even a cosmetic draw here would move every shot of a seeded run.
	#
	# These bodies are not connected to the director, so the DROPS draw a real trap
	# kill makes through `_on_zombie_died` is not in scope — that draw belongs to the
	# death, not to the trap, and it is why main.gd ticks this system at a fixed
	# point in the drive order.
	# The body is made BEFORE the snapshot, and finding that out is what this
	# assertion caught on its first run: `Zombie.create` rolls a speed class off AI
	# and `_ready` rolls an animation rate off VISUAL, so a snapshot taken first
	# reported the trap perturbing two streams it never touches. The spawn's draws
	# belong to the spawn.
	var victim := _body(main, mid)
	var streams: Array[StringName] = [Rng.SPAWN, Rng.BOX, Rng.DROPS, Rng.ROUNDS,
		Rng.AI, Rng.VISUAL]
	var state_was: Array[int] = []
	for s: StringName in streams:
		state_was.append(Rng.stream(s).state)
	t.reset()
	t.arm(String(row.key))
	for i in 240:
		t.tick(1.0 / 60.0)
	var moved := ""
	for i in streams.size():
		if Rng.stream(streams[i]).state != state_was[i]:
			moved += str(streams[i]) + " "
	v.check("four seconds of live trap draw from no rng stream at all",
		moved.is_empty(), "perturbed %s" % moved)
	victim.queue_free()

	Game.points = points_was
	Game.points_earned = earned_was
	Game.kills = kills_was
	Game.power_on = power_was
	_unmount(main, t)


# --- fixtures -----------------------------------------------------------------

## A traps system of its own, not main's. The suite must be able to run these
## before main.gd is wired for traps at all, and a private instance also means the
## clocks these checks wind forward are never the ones the player's run is holding.
static func _mount(main: Node3D) -> Node3D:
	var t: Node3D = TRAPS.new()
	t.name = "VerifyTraps"
	t.bind(main.player)
	main.add_child(t)
	t.build()
	return t


static func _unmount(main: Node3D, t: Node3D) -> void:
	main.remove_child(t)
	t.queue_free()


## One body, in the group the sweep reads, at a grid position. Never given a flow
## field or a target: nothing here runs a physics frame, so it never needs one.
static func _body(main: Node3D, at: Vector2) -> Zombie:
	var z := Zombie.create("zombie", 0, 1, false)
	z.add_to_group("zombies")
	main.add_child(z)
	z.global_position = Vector3(at.x, 0.0, at.y)
	return z


static func _keys(rows: Array) -> Dictionary:
	var out := {}
	for r: Dictionary in rows:
		out[String(r.key)] = true
	return out


## One full sprint bar and one full refill, driven through the player's own
## `_update_sprint` at the rate main.gd drives it. Returns seconds, not ticks.
##
## `Input.action_press` and not a flag on the player: `_update_sprint` reads the
## action directly, so anything short of pressing it is testing a different
## function. Released on every path out — a latched action would leak into every
## check that runs after this one.
static func _duty(p: Player) -> Dictionary:
	var dt := 1.0 / 60.0
	var stamina_was: float = p._stamina
	var sprinting_was: bool = p._sprinting

	p._stamina = 1.0
	p._sprinting = false
	Input.action_press("sprint")
	var run := 0.0
	var n := 0
	while p._stamina > 0.0 and n < 100000:
		p._update_sprint(dt, true)
		run += dt
		n += 1
	Input.action_release("sprint")

	var wait := 0.0
	n = 0
	while p._stamina < 1.0 and n < 100000:
		p._update_sprint(dt, false)
		wait += dt
		n += 1

	p._stamina = stamina_was
	p._sprinting = sprinting_was
	return {"run": run, "wait": wait, "duty": run / (run + wait)}


## The ground speed the player actually ends up moving at, in metres per second,
## read off `velocity` after one real `_physics_process` step with the forward key
## held.
##
## THE THIRD OF STAMIN-UP'S THREE EFFECTS, and the only one still uncovered after
## the sprint bar and the third gun were hooked up to their consumers. Deleting
## `spd *= Weapons.move_speed_scale()` from player.gd:552 left the whole suite
## green — the two checks that mention walking speed both compute
## `Player.SPEED * Weapons.move_speed_scale()` themselves, which is a bound on the
## constants and cannot see the line that applies them.
##
## `velocity` and not the travelled distance: `_physics_process` sets `velocity`
## from `spd` and only then calls `move_and_slide()`, so reading the vector tests
## the same statement without depending on the collision result — the player stands
## in a corridor and a step into a wall would measure the wall, not the perk.
## Position, velocity and health are all put back, because this drives the real
## player that every later section is still using.
static func _walk_speed(p: Player) -> float:
	var pos_was: Vector3 = p.global_position
	var vel_was: Vector3 = p.velocity
	var hp_was: float = p.hp
	# THE WHOLE CAMERA CHAIN, not just the body. `_physics_process` also runs
	# `_update_view`, which advances `_bob_phase` and writes Camera3D.position and
	# RecoilPivot.rotation — and leaving those moved made shell.gd's "ADS writes the
	# camera's field of view and nothing else in the chain" fail with cam.x 0.01078
	# several sections later. A fixture that drives the real player has to put the
	# real player back, and constraint 5's one-writer chain is exactly the list of
	# what to save.
	var bob_was: float = p._bob_phase
	var cam_was: Vector3 = p._cam.position
	var pivot_was: Vector3 = p._recoil_pivot.rotation
	var head_was: float = p._head.position.y
	var regen_was: float = p._regen_wait
	Input.action_press("move_forward")
	p._physics_process(1.0 / 60.0)
	Input.action_release("move_forward")
	var got := Vector2(p.velocity.x, p.velocity.z).length()
	p.global_position = pos_was
	p.velocity = vel_was
	p.hp = hp_was
	p._bob_phase = bob_was
	p._cam.position = cam_was
	p._recoil_pivot.rotation = pivot_was
	p._head.position.y = head_was
	p._regen_wait = regen_was
	return got


## How many weapons the player ends up holding after being handed more distinct
## guns than any roster allows. Four different keys, so the `already held` branch of
## `give_gun` can never be the one that caps it.
static func _fill_slots(p: Player) -> int:
	p.guns = [Weapons.make_gun("m1911", false)]
	p.slot = 0
	for k: String in ["mp40", "m14", "olympia", "stakeout"]:
		p.give_gun(k)
	return p.guns.size()
