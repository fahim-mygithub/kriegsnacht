extends Node3D

## The electric traps: a switch, a price, a window, a cooldown, and a volume that
## kills whatever walks into it.
##
## **THERE IS NO ANCESTOR FOR THIS.** `grep -i "trap\|electr\|shock"` over
## kriegsnacht.html returns nothing at all — the browser build has doors, wall
## buys, a box, perks, Pack-a-Punch and a generator, and no traps of any kind. So
## every number below is designed against Black Ops rather than ported, and none
## of it may be justified by pointing at a line of the ancestor. Where the
## reference is specific it is named; where it is not, the number was measured with
## `--sim` and the measurement is recorded next to it.
##
## What the reference says, and what is carried over:
##
##  - **It is a purchase, not a pickup.** Der Riese's electro-shock defenses cost
##    1000 points a use, which is exactly the MP40 wall buy on this map — so the
##    trap is priced against the one purchase a player is most likely to be
##    weighing it against. `TRAP_COST` RESTATES that figure rather than reading it
##    back — constraint 3 leaves no choice, a `const` initialiser cannot be a call
##    — so the equality is held by an assertion instead. See TRAP_COST.
##  - **It needs the power on.** The generator sits behind two bought doors, so
##    nothing here exists before round five or so on any real line of play. That
##    gate is most of why a trap cannot flatten the early game.
##  - **IT PAYS NOTHING.** A trap kill in BO1 awards the player no points. This is
##    the whole anti-abuse mechanism and it is self-enforcing rather than tuned:
##    the only income in the game is what you shoot, so a player who lets the trap
##    take the round earns nothing and cannot afford to arm it again. See
##    `_sweep()` and `Game.trap_clearing`.
##
## THREE DEPARTURES FROM THE REFERENCE, each recorded as a departure because a
## change from a source that is not written down as one reads as a mistake later —
## and the first draft of this header got all three the wrong way round, stating
## each as though it were canon.
##
##  1. **Canon's window is longer than it is dark; this one is not.** Der Riese's
##     defenses run about a minute and are ready again about thirty seconds later,
##     a duty cycle around two thirds. This port is 20 s live against a 45 s
##     cooldown, which is under a third — inverted, not merely shortened. The
##     reason is that a round here is not a BO1 round: round 7 clears in ~42 s in
##     the sim, so canon's minute would cover a whole mid-game round rather than a
##     push inside one. The number is measured; see ACTIVE.
##  2. **Canon's trap can down the player; this one cannot touch them.** In Der
##     Riese a player without Juggernog who walks into a live gate goes down, and
##     that is what makes the trap a hazard to route around rather than a free
##     safe zone. `_sweep()` reads the `zombies` group and nothing else, so here it
##     is the safe zone. This is the departure with the most gameplay in it and it
##     is the one worth revisiting: doing it properly wants a Juggernog
##     interaction and a player-damage call site, neither of which is in this
##     package.
##  3. **Canon kills late; this one kills instantly.** A zombie that crosses Der
##     Riese's barrier is zapped and dies "soon after, though not always
##     immediately", and can still swing on the way down. Here it is deleted on
##     the frame it enters the rect, with no health test, walkers, crawlers and
##     hounds alike. A staggered death would need a per-body damage-over-time the
##     rest of this project has no shape for, and the instant version is what the
##     sim numbers below were measured against.

## 1000, and it is the MP40's wall-buy price on this map (map_data.gd:97). The
## brief's question — "is it worth its cost against the same points the player
## would spend on a wall-buy" — is only answerable if the two numbers are the
## same, so they are the same by construction.
##
## RESTATED, NOT READ BACK, and that is forced rather than chosen: constraint 3
## makes `const TRAP_COST := MapData.wallbuy_cost("mp40")` a hard parse error,
## because a `const` initialiser has to be a constant expression and that is a
## call. So the equality is held by an assertion instead —
## scripts/dev/checks/traps.gd's "the trap is priced at the MP40 wall buy",
## which checks it against the canonical table AND against 256 shuffled layouts,
## because a rolled layout is the state a real run is actually in. An earlier
## draft of this comment claimed the constant read the table back. It never did.
##
## ONE FLAT PRICE IS DEFENSIBLE BECAUSE THE VALUE IS FLAT, and that was measured
## rather than assumed. A consumable priced the same for everybody is only fair if
## it is not worth wildly more to a bad loadout than to a good one. Twenty rounds,
## seed 20260729, `--sim-trap 1.0` against each gun's own no-trap baseline:
##
##   gun            baseline z·s   with trap   reduction   activations
##   m1911 (start)      129,910      55,221      -57.5%        59
##   mp40  (1000)        32,756      14,882      -54.6%        21
##   rpk   (box)         20,400      10,242      -49.8%        18
##
## Under eight points of spread across a six-fold spread in weapon power. The trap
## is not a crutch that rescues a pistol run and it does not become redundant on a
## strong gun. The pistol player buys it three times as often only because a pistol
## run is three times as long and pays PTS_HIT on far more shots — and it costs
## them 101,170 points of income on top of the 59,000 spent, which is the same
## self-limiting economy the window note below describes, harder.
## See notes/balance/sim-m4trap-gun-*.
const TRAP_COST := 1000

## THE WINDOW IS MEASURED, NOT GUESSED, and 20 s is the knee of a curve rather
## than a round number.
##
## `--sim --sim-trap 1` models the worst case there is: the player camped behind
## the gate so that every body in the round has to cross it. Twenty rounds, MP40,
## seed 20260729, against a no-trap baseline of 32,756 contact z·s:
##
##   window   contact z·s   vs baseline   activations   bodies per activation
##     12 s        20,848        -36%             28              6.1
##     20 s        14,882        -55%             21             12.0
##     30 s        12,088        -63%             17             17.8
##
## At 12 s the purchase does not pay for itself in any currency: six bodies for a
## thousand points, and one to three of them in the rounds before twelve. The step
## from 20 to 30 buys only eight more points of damage reduction for half again as
## much window, because THE ECONOMY IS ALREADY THE BINDING CONSTRAINT — a longer
## window kills more, a trap kill pays nothing, and the player can afford four
## FEWER activations across the run as a result. That self-limiting behaviour is
## the anti-abuse mechanism and it is why the window did not need to be tuned down
## to be safe. See notes/balance/sim-m4trap-*.
##
## The cooldown runs from the moment the trap switches OFF, so a full cycle is
## ACTIVE + COOLDOWN and the gate is dark for more than twice as long as it is lit.
## scripts/dev/checks/traps.gd asserts that ratio rather than either number.
## Canon's ratio is the other way up — see departure 1 in the header.
const ACTIVE := 20.0
const COOLDOWN := 45.0

## Where the traps are, and what volume each one kills inside.
##
## All three sit on chokes the map already had, which is the reference's own siting
## rule — a trap is worth its price because of where it is, not because of what it
## does. `rect` is in grid metres (x, z), the same space `MapData` and
## `Player.grid_pos()` use.
##
## `axis` is which way the arc runs, and it is declared rather than inferred from
## the rect's proportions: the Tunnel's band is square, so there is nothing to
## infer from, and a gate rotated ninety degrees is invisible in a headless test
## and obvious in play.
##
## `switch` is deliberately OUTSIDE every rect. Arming a trap you are standing in
## is a different feature, and one of these three (the Landing) is two tiles
## across with no room to stand.
const SPOTS := [
	{
		"key": "corridor", "label": "Electric trap",
		# The Corridor (map_data.gd:47) is the only way from the Lobby to the
		# Theatre once door 0 is bought. The band is its eastern two metres, so the
		# gate is crossed by anything routing east or west through it.
		"rect": Rect2(20.0, 7.0, 2.0, 4.0), "axis": "z",
		# The south wall, not the north: window 3 (18,6) opens into (18,7), and a
		# switch on the north wall would sit inside that barricade's own 1.7 m
		# interact radius and fight it for the F key.
		"switch": Vector2(18.5, 10.82),
	},
	{
		"key": "tunnel", "label": "Electric trap",
		# The Tunnel (map_data.gd:51), between the Alley and the Generator Hall.
		"rect": Rect2(20.0, 23.0, 2.0, 2.0), "axis": "z",
		"switch": Vector2(17.5, 24.82),
	},
	{
		"key": "landing", "label": "Electric trap",
		# The Landing (map_data.gd:52) is a two-by-one room and the whole of the
		# route from the Theatre to the Generator Hall. It is the tightest choke on
		# the map, so the trap covers all of it.
		"rect": Rect2(29.0, 18.0, 2.0, 1.0), "axis": "x",
		# In the Generator Hall proper, and far enough east that it does not sit
		# inside door 2's 2.4 m radius while that door is still for sale.
		"switch": Vector2(31.4, 19.5),
	},
]

## Post height, and the arc's. 1.9 m clears a walking sprite (1.82 m) so nothing
## can be seen stepping over the top of the gate.
const POST_H := 1.9
const POST_W := 0.16

## The light at the gate. Energy is LINEAR — constraint 7 — and is in the same
## family as the muzzle flash's 4.0 (atmosphere.gd:91) and the room lamps' 3.0
## (lighting.gd:109), not a value copied off a canvas.
## RETUNED AGAINST A RENDERED FRAME, not reasoned about. The first pass was 2.6
## energy with the sheet at 0.28-0.70 alpha on an ADDITIVE blend, and
## `--shot notes/perf/shots/m4-trap-corridor.png 270` came back with a solid white
## slab across the Corridor that the wall behind it could not be seen through and
## that bleached both its own posts. Additive alpha is not a fade — it is how much
## of the sheet is added on top of what is already there — so the number that
## looks reasonable as an opacity is roughly three times too much as a gain.
const ARC_ENERGY := 1.7
const ARC_RANGE := 5.0

## THE AUTHORED HUE, IN DISPLAY SPACE, and it is used raw in exactly one place and
## converted in the other two. Which of the three is which is not a style question
## — this project has settled each case separately and they do not agree:
##
##  - `light_color` (below) takes it RAW. projectile.gd:139 is explicit: "light_color
##    is a light, not an albedo, and constraint 7 is explicit that a canvas number
##    must not become a light energy — so only the hue carries across". The energy
##    is chosen against this renderer's other lights and the hue rides along.
##  - The ADDITIVE arc sheet takes it LINEARISED. Constraint 7's exception: a
##    BLEND_ADD surface is a light contribution, because its output is *added* to a
##    framebuffer whose contents are already linear. gunart.gd:600's "pass the hex
##    through unconverted, the encode on the way out cancels the skipped decode"
##    argument is correct and does NOT reach here — it holds for an unshaded surface
##    that REPLACES the pixel, where the two transfer functions really do cancel.
##    An additive surface does not replace anything; it adds to a linear sum, and
##    there is nothing for the encode to cancel against. The port's other additive
##    hues agree: zombie.gd:1295 and projectile.gd:199 both convert, both with a
##    comment saying why.
##  - `emission` takes it LINEARISED for the same reason. Emission is added to the
##    lit result, so it is a light contribution by the same test.
##
## MEASURED, not reasoned: display (0.580, 0.860, 1.000) decodes to linear
## (0.296, 0.711, 1.000). Left raw, the red channel is 1.96x too strong and the
## blue:red ratio collapses from 3.4:1 to 1.7:1 — the arc renders as a pale
## white-cyan rather than the electric blue it is authored as. That is a hue error,
## not a brightness one, and it is invisible to every assertion in the suite.
const ARC_COLOR := Color(0.58, 0.86, 1.0)

## The same hue as the renderer has to receive it. Cached rather than converted at
## each use so the two additive call sites cannot drift apart.
static var ARC_COLOR_LINEAR: Color = ARC_COLOR.srgb_to_linear()

## The crackle. NO RANDOM NUMBER IS DRAWN ANYWHERE IN THIS FILE, for the reason
## verify.gd's `_impacts` already pins on fx.gd: weapon spread rides the VISUAL
## stream, so a cosmetic draw here would shift every shot of a seeded run. Two
## sines at incommensurate rates give a signal that never repeats over any window
## a player watches and costs nothing to reproduce.
const FLICKER_A := 31.0
const FLICKER_B := 7.3

## How often the arc is heard, and how far away it is worth a voice. The 3D pool is
## fourteen (sfx.gd:22) and a groan is a threat cue; a trap across the map must not
## steal one, and `play_at` takes a player whether or not the listener is in range.
const CRACKLE_EVERY := 0.62
const CRACKLE_DIST := 14.0

var player: Player

## ONE POST MATERIAL PER GATE, and that is a fix rather than a preference.
##
## There used to be a single shared `_mat_post` and `_paint()` wrote its emission
## only on the branch where a trap is live, which produced two wrong frames that no
## assertion could see and `--shot` showed immediately: arming the Corridor lit the
## Tunnel's posts fifteen metres away through a wall, and once any gate had been
## live every gate's posts stayed lit for the rest of the run, cooldown included.
## The posts are the ONLY at-a-distance readout a trap has — there is no HUD badge
## for one — so a gate that is not live has to actually look it. The arc sheet can
## still be shared, because its instances are hidden when they are off.
var _mat_arc: StandardMaterial3D
## Live state per SPOTS row, same order: t (seconds left live), cd (seconds left
## on cooldown), and the three nodes. Kept alongside SPOTS rather than inside it
## because SPOTS is a `const` and therefore genuinely immutable.
var _live: Array[Dictionary] = []
var _phase := 0.0
var _kills := 0


func bind(p: Player) -> void:
	player = p


## Builds the hardware. Separate from `_ready()` for the same reason every other
## system's is: main.gd decides construction order, and this one wants to exist
## before the warm-up pass asks it for its materials.
func build() -> void:
	# One arc material for all three gates, so the pulse is in lockstep when two
	# are live at once. That is not a compromise: they are on the same mains and
	# the flicker is a function of wall time rather than of either trap's own
	# clock, so in-phase is what it should look like.
	_mat_arc = StandardMaterial3D.new()
	_mat_arc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_arc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_arc.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat_arc.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_arc.disable_receive_shadows = true
	# Depth fog runs on unshaded transparents like any other surface, and on an
	# additive one it is wrong twice over — it lays fog grey over a wall the same fog
	# already greyed, and it drags the arc toward the fog colour with distance, so
	# the gate stops reading as lit at exactly the range the player needs to see it
	# from to decide whether to route through it. This is the same call, for the same
	# reason, that zombie.gd's eye material and lighting.gd's lamp fixtures both make;
	# the arc was the only additive light surface in the project that was still
	# taking the fog.
	_mat_arc.disable_fog = true
	# LINEARISED, because this surface is BLEND_ADD — see ARC_COLOR. Alpha is the
	# gain and is carried untouched; only the hue is a colour-space quantity.
	_mat_arc.albedo_color = Color(ARC_COLOR_LINEAR.r, ARC_COLOR_LINEAR.g,
		ARC_COLOR_LINEAR.b, 0.0)

	for row: Dictionary in SPOTS:
		_live.append(_build_one(row))


## The hardware finish, one instance per gate. A20's rule decides when emission is
## switched on: the feature flag selects the shader variant, so it is enabled here
## at zero energy from the first frame and only the multiplier ever moves. Turning
## it on the first time a trap is bought would compile a variant mid-fight, on a
## platform with no program cache.
func _new_post_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.17, 0.18, 0.16)
	m.metallic = 0.45
	m.roughness = 0.55
	m.emission_enabled = true
	# LINEARISED. Emission is added to the lit result, so it is a light contribution
	# by the same test the arc sheet meets — see ARC_COLOR. The post is the gate's
	# only at-a-distance readout, so getting its hue wrong is not cosmetic: a
	# white-cyan post and a blue one are the difference between "that is a lamp" and
	# "that is live".
	m.emission = ARC_COLOR_LINEAR
	m.emission_energy_multiplier = 0.0
	return m


func _build_one(row: Dictionary) -> Dictionary:
	var rect: Rect2 = row.rect
	var mid := rect.get_center()
	var along_z: bool = String(row.axis) == "z"
	# The gate spans one axis of the rect and sits at the centre of the other, so a
	# zombie crossing the choke walks through the sheet rather than alongside it.
	var span: float = rect.size.y if along_z else rect.size.x

	var arc := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(span, POST_H)
	arc.mesh = quad
	arc.material_override = _mat_arc
	arc.position = Vector3(mid.x, POST_H * 0.5, mid.y)
	# A QuadMesh faces +Z with its width along X. For a gate that runs along Z the
	# whole thing turns a quarter turn, which puts the width on Z and the face on X.
	if along_z:
		arc.rotation.y = PI * 0.5
	arc.visible = false
	# Billboarding is off, so the AABB is the geometry and no cull margin is needed
	# — the opposite of the zombies' eye quads (verify.gd's `_eyes`).
	add_child(arc)

	var posts: Array[MeshInstance3D] = []
	var mat_post := _new_post_material()
	var box := BoxMesh.new()
	box.size = Vector3(POST_W, POST_H, POST_W)
	for side: float in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		p.mesh = box
		p.material_override = mat_post
		var off: float = (span * 0.5 - POST_W * 0.5) * side
		p.position = Vector3(mid.x + (0.0 if along_z else off), POST_H * 0.5,
			mid.y + (off if along_z else 0.0))
		add_child(p)
		posts.append(p)

	var light := OmniLight3D.new()
	light.light_color = ARC_COLOR
	light.light_energy = 0.0
	light.omni_range = ARC_RANGE
	# Shadowless, like the muzzle flash: on this renderer a shadowed omni needs six
	# cubemap passes over every instance it touches, and this one is at head height
	# in a corridor full of zombies.
	light.shadow_enabled = false
	light.visible = false
	light.position = Vector3(mid.x, 1.25, mid.y)
	add_child(light)

	return {
		"key": String(row.key), "label": String(row.label),
		"rect": rect, "switch": Vector2(row.switch), "centre": Vector3(mid.x, 1.2, mid.y),
		# `flash` is bumped on every kill and decayed, so the gate visibly spikes when
		# it takes something. It is PER GATE and not a field on the system, because
		# two gates can be live at once and a body dying in the Corridor is not a
		# thing that happened at the Landing. It is the only feedback a trap kill
		# gets besides the one sweep voice: there is deliberately no blood, because a
		# body dropped by a few hundred volts has not been shot and `player.impact`
		# means "a round landed here".
		"t": 0.0, "cd": 0.0, "crackle": 0.0, "flash": 0.0,
		"arc": arc, "posts": posts, "light": light, "mat_post": mat_post,
	}


## Every material this system owns, for main.gd's warm-up pass. Same accessor as
## fx, atmos, lighting and the viewmodel: main never has to know how many there
## are, and verify.gd's "every material is reachable from the warm-up" assertion
## reads it.
func materials() -> Array:
	var out: Array = [_mat_arc]
	for t: Dictionary in _live:
		out.append(t.mat_post)
	return out


# --- the public face ----------------------------------------------------------

## The switch rows, for whoever builds the interactables. Only the three fields an
## interactable needs, so a caller cannot reach in and write the live clocks.
func spots() -> Array:
	var out: Array = []
	for t: Dictionary in _live:
		out.append({"key": t.key, "label": t.label, "switch": t.switch})
	return out


## "idle" | "live" | "cooldown". Unknown keys answer "idle" rather than throwing:
## the caller is a UI scan and a typo there should show the wrong prompt, not stop
## the frame.
func state_of(key: String) -> String:
	var t := _find(key)
	if t.is_empty():
		return "idle"
	if float(t.t) > 0.0:
		return "live"
	return "cooldown" if float(t.cd) > 0.0 else "idle"


func active_left(key: String) -> float:
	var t := _find(key)
	return 0.0 if t.is_empty() else float(t.t)


func cooldown_left(key: String) -> float:
	var t := _find(key)
	return 0.0 if t.is_empty() else float(t.cd)


## Lifetime trap kills. Read by the soak print and the assertions; nothing acts
## on it.
func kills() -> int:
	return _kills


## Switches a trap on. **It does not take the money** — the caller does, exactly as
## every door, wall buy and perk machine in interaction_system.gd already does its
## own `Game.spend`. Splitting it the other way would put a second wallet writer in
## a file that has no other business with the economy.
##
## Refuses anything that is not idle, and refuses with no power: the prompt already
## says both, but `arm()` is also what the assertions and any future power-up would
## call, and a rule that only exists in the prompt is a rule that is not enforced.
func arm(key: String) -> bool:
	if not Game.power_on:
		return false
	var t := _find(key)
	if t.is_empty() or float(t.t) > 0.0 or float(t.cd) > 0.0:
		return false
	t.t = ACTIVE
	t.crackle = 0.0
	var at: Vector3 = t.centre
	# The generator's own whine, pitched up: this is the same current arriving
	# somewhere smaller. A prebaked id, deliberately — sfx.gd synthesises an unknown
	# id in a per-sample GDScript loop on the main thread the first time it is asked
	# for, which for a combat cue means a hitch in the middle of a fight.
	Sfx.play_at("power_on", at, -5.0, 1.55)
	return true


## Cancels everything, without paying anything back. For `restart()` and for the
## assertions; nothing in play calls it.
func reset() -> void:
	for t: Dictionary in _live:
		t.t = 0.0
		t.cd = 0.0
		t.flash = 0.0
		_paint(t)
	_kills = 0


# --- the loop -----------------------------------------------------------------

## Driven from main.gd's fixed order rather than from this node's own `_process`,
## and constraint 6 is why it has to be: a trap kill routes through
## `Zombie.died` -> `round_director._on_zombie_died`, which draws from the DROPS
## stream. So the frame position of this call is part of a seeded run's identity.
func tick(dt: float) -> void:
	_phase += dt
	for t: Dictionary in _live:
		t.flash = maxf(0.0, float(t.flash) - dt * 4.0)
		if float(t.t) > 0.0:
			t.t = maxf(0.0, float(t.t) - dt)
			_sweep(t)
			_crackle(t, dt)
			if float(t.t) <= 0.0:
				t.cd = COOLDOWN
				# The whine an octave and a half down, which is the same cue running
				# out of current.
				Sfx.play_at("power_on", t.centre, -11.0, 0.6)
		elif float(t.cd) > 0.0:
			t.cd = maxf(0.0, float(t.cd) - dt)
		_paint(t)


## Everything standing in the volume dies, now, with no health test and no
## line-of-sight test.
##
## NO LOS, and that is a decision rather than an oversight. `los.gd` is the shared
## visibility test and four callers have to agree about it — but all four are
## asking "can A see B across open floor", and this is asking "is B inside this
## box". The volume is two metres of corridor with a wall down each side; there is
## nothing for a ray to be occluded by that is not already outside the rect.
##
## Collected before anything is killed. `take_damage` reaches the director
## synchronously through `died`, which erases the body from its live list and can
## spawn a power-up, so killing inside the walk would be mutating the world under
## an iterator for no gain.
func _sweep(t: Dictionary) -> void:
	var rect: Rect2 = t.rect
	var caught: Array[Zombie] = []
	for n in get_tree().get_nodes_in_group("zombies"):
		if not is_instance_valid(n):
			continue
		var z: Zombie = n
		if z.state == Zombie.State.DYING:
			continue
		# XZ only. Every enemy in the game stands on the floor at y = 0, so a height
		# test would be a test of a constant — and the day something flies, the arc
		# is 1.9 m tall and the answer is to test against POST_H here rather than to
		# have been testing a value that was always true.
		if not rect.has_point(Vector2(z.global_position.x, z.global_position.z)):
			continue
		caught.append(z)
	if caught.is_empty():
		return

	# A TRAP KILL PAYS NOTHING. See the header: this is the reference's rule and it
	# is also the only thing standing between a 1000-point switch and a points farm,
	# because the alternative — 60 a body, up to sixteen bodies a window — makes the
	# trap pay for itself twice over and then buy the next one.
	#
	# `trap_clearing` and not `nuke_clearing`, and the two are not interchangeable:
	# the Nuke's flag suppresses the drop roll as well (game_state.gd's `try_drop`),
	# because the ancestor's Nuke never reaches `zombieDamage` at all. A trap does.
	# Canon's drop roll lives in the zombie's own death callback and does not care
	# what killed it, so the power-up still rolls and only the payout is gated.
	Game.trap_clearing = true
	for z: Zombie in caught:
		# hit_y at the feet, so it can never be scored as a headshot by anything
		# downstream that reads the cause. 1e9 rather than the body's health for the
		# same reason `_cone_blast` uses it: overkill is how "this is not a damage
		# event, it is a deletion" is spelled everywhere else in this project.
		# BLAST rather than the default bullet: zombie.gd already names the trap as
		# the case its away-from-the-player fallback gets wrong. A body cooked in the
		# gate should be thrown out of the gate, not back toward whoever bought it —
		# and the player is usually standing past it, so the fallback shoves the
		# corpse the one direction it must not go.
		z.take_damage(1e9, 0.0, false, Zombie.Cause.BLAST,
			(z.centre() - t.centre).normalized())
		_kills += 1
	Game.trap_clearing = false
	t.flash = 1.0

	# ONE VOICE FOR THE SWEEP, NOT ONE PER BODY, and the size of the catch is a
	# level rather than a repeat.
	#
	# `take_damage` already plays "hit" at -10 dB and `_die` plays "death" at -12
	# (zombie.gd:897, :1003), so every body in this gate is worth two positional
	# voices before this file opens its mouth. A per-body third — which is what was
	# here, the SAME "hit" sample again at -1.0 dB, nine decibels over the one
	# played at the same point on the same frame — made it three a body.
	# `Sfx.POOL_3D` is 14 and `_free_player_3d()` STEALS THE OLDEST rather than
	# refusing the new one (sfx.gd:694-704), so a gate that caught ten did not
	# merely sound bad: it evicted every groan, footfall and barricade hit on the
	# map, and a groan is a threat cue. The sim's late activations take 21-49 bodies
	# across a window, so ten arriving on one frame is ordinary rather than a
	# pathological case.
	Sfx.play_at("hit", t.centre, -10.0 + minf(6.0, 2.0 * float(caught.size())), 1.9)


## The arc's voice. Rate-limited and distance-culled — see CRACKLE_EVERY.
func _crackle(t: Dictionary, dt: float) -> void:
	t.crackle = float(t.crackle) - dt
	if float(t.crackle) > 0.0:
		return
	t.crackle = CRACKLE_EVERY
	if player == null or not is_instance_valid(player):
		return
	var at: Vector3 = t.centre
	if player.global_position.distance_to(at) > CRACKLE_DIST:
		return
	# Pitch walks with the same deterministic flicker the light uses, so the sound
	# and the light are the same signal rather than two that drift apart.
	Sfx.play_at("empty", at, -15.0, 1.5 + 0.5 * _flicker())


## -1..1, and reproducible from the clock alone. See FLICKER_A.
func _flicker() -> float:
	return sin(_phase * FLICKER_A) * sin(_phase * FLICKER_B)


## The whole visual state of one trap, written in one place — the light, the arc's
## alpha and the posts' emission all say the same thing, so they are set together
## and there is no state in which two of the three disagree.
func _paint(t: Dictionary) -> void:
	var arc: MeshInstance3D = t.arc
	var light: OmniLight3D = t.light
	var mat_post: StandardMaterial3D = t.mat_post
	var on: bool = float(t.t) > 0.0
	arc.visible = on
	light.visible = on
	if not on:
		# THE OFF BRANCH HAS TO WRITE SOMETHING. The arc and the light are hidden by
		# an instance flag, but the posts are geometry that is always drawn, so a
		# dark gate is dark only if its emission is actively put back. Returning here
		# without doing that is what left every post on the map lit for the rest of
		# the run after the first activation.
		mat_post.emission_energy_multiplier = 0.0
		return
	var k := 0.62 + 0.38 * absf(_flicker()) + float(t.flash) * 0.9
	light.light_energy = ARC_ENERGY * k
	# The arc sheet is shared, so its alpha is written once per live gate rather
	# than once per gate — every live gate wants the same value, because the flicker
	# is a function of wall time and they are on the same mains.
	_mat_arc.albedo_color.a = clampf(0.09 + 0.17 * k, 0.0, 1.0)
	mat_post.emission_energy_multiplier = 0.40 * k


func _find(key: String) -> Dictionary:
	for t: Dictionary in _live:
		if String(t.key) == key:
			return t
	return {}
