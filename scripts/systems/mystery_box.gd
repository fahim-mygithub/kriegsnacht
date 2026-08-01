extends Node

## The mystery box: the five-state machine, the reel, the roll, the teddy bear
## and the relocation.
##
## Split out of main.gd. The box's own art is a prop, so the sprite comes from
## Atmosphere; the box's *interactable* — the row in the interact table that
## carries its position — is handed over once by InteractionSystem rather than
## searched for in that table every time a relocation lands. Both files used to be
## the same file, which is the only reason the search existed.
##
## The port shipped three states (idle, spinning, offering). The ancestor has five
## (html:2818-2843) and the two extra ones ARE the theatre: `teddy` replaces the
## offer outright, and `closing` gives the lid 0.6 s to come down instead of
## snapping. Both are here now.

## preload rather than the global class name: a freshly added script is not in
## the class registry until the editor rescans, and a headless run has no editor.
const ATMOSPHERE := preload("res://scripts/systems/atmosphere.gd")

const BOX_COST := 950
const BOX_SPIN := 2.9
const BOX_OFFER := 7.0
## html:2827 and html:2803. The teddy is long enough to read as an event in its
## own right; the close is just the lid.
const BOX_TEDDY := 2.2
const BOX_CLOSING := 0.6

## The reel's swap interval, html:2823: `0.09 + max(0, 2.9 - timer) * 0.055`
## seconds between swaps. The interval GROWS with elapsed time, so the reel slows
## into its answer — 0.09 s a swap at the start, 0.25 s at the end.
const SPIN_RATE_BASE := 0.09
const SPIN_RATE_SLOPE := 0.055

## How many door purchases deep a fresh run's box may start. See start_spots().
const START_DOOR_DEPTH := 1

var player: Player
## atmosphere.gd. Untyped for the same reason main.gd's `hud` and `lighting` are:
## the script is attached at runtime, so a typed variable cannot see
## `prop_sprite()`.
var atmos

var _state := "idle"      # idle | spinning | teddy | offering | closing
var _timer := 0.0
var _gun := ""
## What the reel is currently showing. Distinct from `_gun`, which is the answer:
## the two are only equal once the reel has landed, and that is the whole of "the
## reel does not lie".
var _show := ""
var _spin_t := 0.0
var _node: Sprite3D
var _teddy := false
## The box's row in the interact table. The same Dictionary the interact scan
## reads, not a copy — relocating the box moves it by writing `pos` here.
var _entry: Dictionary = {}


func bind(p: Player, a: Node3D) -> void:
	player = p
	atmos = a


## Called by InteractionSystem as it builds the table, which is also the moment
## the box first needs art.
func adopt(entry: Dictionary) -> void:
	_entry = entry
	# `Game.box_spot = 0` was hard-set here, so every fresh run put the box in the
	# Theatre, behind the 750 door, forever. Rolled now — and rolled *here* rather
	# than in `Game.reset_run()` because this is the first BOX draw of a run, and
	# moving a draw earlier or later in that stream shifts every box roll after it
	# for a given seed (constraint 6).
	var spots := start_spots()
	Game.box_spot = spots[Rng.stream(Rng.BOX).randi() % spots.size()]
	_entry.pos = MapData.BOXSPOTS[Game.box_spot]
	_place(Game.box_spot)


## Re-rolls the starting room from the BOX stream and moves the box to it.
##
## For a co-op CLIENT, which learns the run's seed from the host only AFTER adopt()
## has already spent its own boot seed. Without this, every client's box sits in a
## room drawn from its own seed and two players hunt the same box in different
## rooms — see main.gd::_apply_net_seed, which drives this.
##
## Re-enters adopt() rather than duplicating the roll, because this has to make the
## SAME draw at the SAME point in the BOX stream, and a second copy of that
## expression is a second thing that can drift out of step with the first
## (constraint 6).
func reseed() -> void:
	if _entry.is_empty():
		return
	adopt(_entry)


func state() -> String:
	return _state


func gun() -> String:
	return _gun


## What the reel is showing right now, or "" when the box is shut. The interact
## prompt reads this so the spin is legible from outside the box.
func shown() -> String:
	return _show


## True while the box is holding a weapon out. The interact prompt reads this.
func offering() -> bool:
	return _state == "offering"


# --- where the box may be ----------------------------------------------------

## How many door purchases deep each entry in MapData.BOXSPOTS is, measured from
## the player's spawn. -1 for a spot no sequence of purchases can reach.
##
## Computed off the map data rather than tabled, because BOXSPOTS, DOORS and the
## room rectangles are all data: a hard-coded "spot 2 is the far one" would still
## read correct after somebody moved a door, and would be wrong.
##
## One BFS layer per pass. Every door standing on the current frontier is opened
## together before the next layer is measured — opening them one at a time would
## let a door bought in this layer expose another in the same layer, and understate
## the depth of everything behind it.
static func spot_door_depth() -> Array[int]:
	# A scratch map, because this walk buys every door in the level and the live
	# MapData is the one the player is standing in.
	var m := MapData.new()
	m.build()
	var depth: Array[int] = []
	for i in MapData.BOXSPOTS.size():
		depth.append(-1)
	var layer := 0
	while true:
		for i in MapData.BOXSPOTS.size():
			if depth[i] >= 0:
				continue
			var s: Vector2 = MapData.BOXSPOTS[i]
			if m.reach[MapData.ix(int(s.x), int(s.y))] == 1:
				depth[i] = layer
		var frontier: Array[int] = []
		for di in MapData.DOORS.size():
			if m.door_open[di] == 0 and _door_reachable(m, di):
				frontier.append(di)
		if frontier.is_empty():
			break
		for di in frontier:
			m.open_door(di)
		layer += 1
	return depth


## A door is buyable when one of its tiles touches somewhere the player can stand.
## `reach` marks window tiles as reachable edges without them being standable, so
## the open test is load-bearing: without it a barricade would count as a way in.
static func _door_reachable(m: MapData, di: int) -> bool:
	for t: Array in MapData.DOORS[di].tiles:
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = int(t[0]) + d.x
			var ny: int = int(t[1]) + d.y
			if nx < 0 or ny < 0 or nx >= MapData.MAPW or ny >= MapData.MAPH:
				continue
			var ni := MapData.ix(nx, ny)
			if m.solid[ni] == 0 and m.reach[ni] == 1:
				return true
	return false


## Which spots a *fresh run* may put the box in.
##
## Not all of them. Spot 2 is in the Generator Hall, two purchases and at least
## 2000 points past the spawn, so a run that rolled it would have no box at all
## until round six or seven — the box would be an item you read about. One door is
## the reference's shape: in BO1 the start spot can be behind a purchase, it
## cannot be behind the whole map. A *relocation* is unrestricted, because by the
## time a teddy has fired the doors are the player's own problem.
static func start_spots() -> Array[int]:
	var depth := spot_door_depth()
	var out: Array[int] = []
	for i in depth.size():
		if depth[i] >= 0 and depth[i] <= START_DOOR_DEPTH:
			out.append(i)
	# Never return nothing: a map edit that walled everything off would otherwise
	# take the box out of the game with no error anywhere.
	if out.is_empty():
		out.append(0)
	return out


# --- the machine -------------------------------------------------------------

## Returns false when the player could not pay, so the caller can raise the deny
## cue — that cue is the HUD's and the interact layer owns the HUD handle.
func use() -> bool:
	if _state == "offering":
		player.give_gun(_gun, false)
		Game.toast.emit(Weapons.TABLE[_gun].name.to_upper())
		Sfx.play("powerup", -3.0)
		# html:2803. A take does not snap the lid shut, it starts the close.
		_enter("closing", BOX_CLOSING)
		return true
	if _state != "idle":
		return true
	if not Game.spend(BOX_COST):
		return false
	Game.box_uses += 1
	# ONE gameplay draw decides the answer, at the moment the money is spent. The
	# ancestor instead keeps the last thing the reel happened to show
	# (`G.boxWeapon = G.boxSpinShow`, html:2830) — which makes the result a
	# function of the frame times during the spin, and a seeded run that replays
	# on a different machine gets a different weapon. The reel below lands ON this
	# value instead, so "the reel does not lie" survives and determinism arrives.
	_gun = Weapons.roll_box(Rng.stream(Rng.BOX))
	# The teddy bear starts becoming likely after four pulls. html:2808, and the
	# `and` short-circuits exactly as the ancestor's `&&` does, so the draw is not
	# taken at all below four uses.
	_teddy = Game.box_uses > 3 and Rng.randf(Rng.BOX) < 0.16 * (Game.box_uses - 3)
	_show = ""
	_spin_t = 0.0
	_enter("spinning", BOX_SPIN)
	Sfx.play("box")
	return true


## Driven from main.gd rather than from this node's own `_process` — see the note
## on the drive order there. Runs immediately after the round loop and before the
## power-ups, exactly where main.gd's `_update_box` used to sit, because an
## expiring offer can relocate the box and that draws from the BOX stream.
func tick(dt: float) -> void:
	if _state == "idle":
		return
	_timer -= dt
	match _state:
		"spinning":
			_spin(dt)
		"offering":
			if _timer <= 0.0:
				# An offer nobody took closes; it does not vanish. html:2835.
				_enter("closing", BOX_CLOSING)
		"teddy":
			if _timer <= 0.0:
				# html:2838-2839. The move lands at the END of the bear, so the
				# 2.2 s is spent watching it sit in the box you just paid for.
				_relocate()
				_enter("idle", 0.0)
		"closing":
			if _timer <= 0.0:
				_gun = ""
				_enter("idle", 0.0)


## The reel. The swap interval grows as the spin runs down, so the last few swaps
## are visibly slower than the first — that deceleration is the beat the box is
## recognisable by, and it is the whole reason this is not a 2.9 s wait.
func _spin(dt: float) -> void:
	_spin_t += dt
	var rate := SPIN_RATE_BASE + maxf(0.0, BOX_SPIN - _timer) * SPIN_RATE_SLOPE
	if _spin_t > rate:
		_spin_t = 0.0
		if _timer <= rate:
			# The last swap of the reel shows the answer, so the answer is what the
			# player watched it stop on.
			_show = _gun
		else:
			# COSMETIC. Which weapons flick past on the way is a visual detail and
			# must not touch a gameplay stream (constraint 6) — the answer was
			# drawn from BOX in use() and nothing here can move it.
			_show = Weapons.roll_box(Rng.stream(Rng.VISUAL))
		_display()
	if _timer > 0.0:
		return
	if _teddy:
		# THE 950 BUYS NOTHING. The port used to hand over the weapon and *then*
		# move the box, which made a teddy strictly better than a normal pull. The
		# ancestor never reaches an offer on a teddy at all (html:2826-2828) and it
		# is right: the bear is the loss.
		Sfx.play("box", 0.0, 2.35)
		Game.toast.emit("THE BOX HAS MOVED")
		_show = ""
		_enter("teddy", BOX_TEDDY)
		return
	# Belt and braces against a long frame: the offer always shows the answer, even
	# if the swap above never got its last turn.
	_show = _gun
	_display()
	_enter("offering", BOX_OFFER)


## The single writer of `_state`, so art and reel can never disagree with it.
func _enter(s: String, t: float) -> void:
	_state = s
	_timer = t
	_set_art(_art_for(s))
	if s != "spinning" and s != "offering":
		_show = ""
	_display()


## html:2096 shows the TEDDY sprite for the whole spin whenever the bear is
## pending, and a plain CLOSED box during the teddy state itself — so the ancestor
## telegraphs the loss for 2.9 s and then hides it. That is backwards, and the
## reference is unambiguous: the bear appears at the end, as the reveal. Departure
## recorded here rather than silently.
func _art_for(s: String) -> String:
	match s:
		"spinning", "offering":
			return "open"
		"teddy":
			return "teddy"
	return "closed"


func _display() -> void:
	atmos.set_box_display(_show, MapData.BOXSPOTS[Game.box_spot])


func _relocate() -> void:
	_teddy = false
	Game.box_uses = 0
	var next := Game.box_spot
	while next == Game.box_spot:
		next = Rng.stream(Rng.BOX).randi() % MapData.BOXSPOTS.size()
	Game.box_spot = next
	_entry.pos = MapData.BOXSPOTS[next]
	_place(next)


func _place(spot: int) -> void:
	if _node and is_instance_valid(_node):
		_node.queue_free()
	_node = atmos.prop_sprite("box_closed", MapData.BOXSPOTS[spot], "MysteryBox")


func _set_art(which: String) -> void:
	if _node and is_instance_valid(_node):
		_node.texture = load(ATMOSPHERE.PROP_DIR + "box_" + which + ".png")
